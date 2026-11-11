import Testing
import Foundation
@testable import LoupeFeature

/// Setup's hands-on practice: point, leave a note, then either a connected agent picks it
/// up and changes the practice app, or the person copies the note for their agent
@MainActor
struct PracticeTests {

    /// A practice with no agent connected, at the given stage
    private func practice(at stage: PracticeStage, note: String = "make this bigger") -> PracticeModel {
        var model = PracticeModel()
        if stage == .pointing { return model }
        model.select(.saveButton)
        if stage == .writingNote { return model }
        model.addNote(note)
        if stage == .noteAdded { return model }
        model.copyNote()
        if stage == .done { return model }
        model.continueToFinish()
        return model
    }

    /// A practice whose note is waiting on the person's own connected agent
    private func livePractice(note: String = "make this bigger") -> PracticeModel {
        var model = PracticeModel()
        model.select(.saveButton)
        model.addNote(note, liveAgent: "Claude Code")
        return model
    }

    /// Mutating calls can't sit inside #expect, so their result is checked here
    private func expect(_ result: Bool, _ expected: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(result == expected, sourceLocation: sourceLocation)
    }

    // MARK: Pointing and writing

    @Test func startsByPointingWithNothingOnScreen() {
        let model = PracticeModel()
        #expect(model.stage == .pointing)
        #expect(model.stepNumber == 1)
        #expect(model.outlinedElement == nil)
        #expect(model.badge == nil)
        #expect(model.status == nil)
        #expect(model.messages.isEmpty)
        #expect(!model.isNoteOpen)
        #expect(model.pageHTML == PracticePage.startingHTML)
    }

    @Test func hoverOutlinesWhatIsUnderThePointer() {
        var model = PracticeModel()
        model.hover(.heading)
        #expect(model.outlinedElement == .heading)
        // "Entered B" can arrive before "left A"
        model.hover(.saveButton)
        model.unhover(.heading)
        #expect(model.outlinedElement == .saveButton)
        model.unhover(.saveButton)
        #expect(model.outlinedElement == nil)
    }

    /// The practice app is a page, so anything on it can be pointed at, not only what it starts with
    @Test func anythingOnThePageCanBeNoted() {
        var model = PracticeModel()
        let added = PracticeElement(id: "item1", role: "AXLink", title: "Help")
        model.hover(added)
        #expect(model.outlinedElement == added)
        expect(model.select(added), true)
        #expect(model.selected == added)
        #expect(added.kindLine == "Link in Practice App")
        #expect(added.suggestedNote == "Make this bigger")
        // The same place on the page is the same element, whatever it says now
        #expect(PracticeElement(id: "saveButton", role: "AXButton", title: "Save Trip") == .saveButton)
    }

    @Test func clickingOpensTheNoteWindowAndCancelClosesIt() {
        var model = PracticeModel()
        model.hover(.reminder)
        expect(model.select(.reminder), true)
        #expect(model.stage == .writingNote)
        #expect(model.stepNumber == 1)
        #expect(model.isNoteOpen)
        #expect(model.outlinedElement == .reminder)
        // The pointer wandering off no longer moves the outline
        model.hover(.heading)
        #expect(model.outlinedElement == .reminder)

        model.cancelNote()
        #expect(model.stage == .pointing)
        #expect(model.selected == nil)
    }

    @Test func aBlankNoteIsRefused() {
        var model = practice(at: .writingNote)
        expect(model.addNote("   \n"), false)
        #expect(model.stage == .writingNote)
    }

    @Test func addingTheNotePinsANumberedBadge() {
        var model = practice(at: .writingNote)
        expect(model.addNote("  make this bigger \n"), true)
        #expect(model.stage == .noteAdded)
        #expect(model.stepNumber == 2)
        #expect(model.messages.map(\.text) == ["make this bigger"])
        #expect(model.badge == .numbered(1))
        #expect(model.status?.label == "Waiting")
    }

    @Test func elementsUseLoupesPlainNames() {
        #expect(PracticeElement.saveButton.kindLine == "Button in Practice App")
        #expect(PracticeElement.saveButton.nameLine == "\u{201C}Save Plan\u{201D}")
        #expect(PracticeElement.reminder.kindLine == "Checkbox in Practice App")
        #expect(PracticeElement.heading.kindLine == "Heading in Practice App")
    }

    // MARK: Without an agent: copy the note

    /// Nobody pretends to be an agent. Without one, the person does what they will do
    /// for real: copy the note for their agent.
    @Test func withoutAnAgentTheNoteIsCopied() {
        var model = practice(at: .noteAdded, note: "make the letters italic")
        #expect(!model.isLive)
        let step = PracticeCopy.checklist(for: model)[1]
        #expect(step.isCurrent)
        #expect(step.text == "Copy your note")
        #expect(step.action == .copyNote)
        #expect(model.copiedText == "Loupe practice note 1\nButton in Practice App: \u{201C}Save Plan\u{201D}\nRequest: make the letters italic")

        expect(model.copyNote(), true)
        #expect(model.stage == .done)
        #expect(model.wasCopied)
        // Nothing was done to it yet, so it keeps its number and nothing on the page changes
        #expect(model.badge == .numbered(1))
        #expect(model.status?.label == "Waiting")
        #expect(model.pageHTML == PracticePage.startingHTML)
        #expect(model.messages.count == 1)
        let last = PracticeCopy.checklist(for: model)[2]
        #expect(last.text == "Copied. Paste it into your agent, or continue")
        #expect(last.action == .continuePractice)
    }

    @Test func copyingBelongsOnlyToANoteWithoutAnAgent() {
        var live = livePractice()
        expect(live.copyNote(), false)
        #expect(live.stage == .noteAdded)
        for stage in [PracticeStage.pointing, .writingNote, .done, .finished] {
            var model = practice(at: stage)
            expect(model.copyNote(), false)
        }
    }

    // MARK: A connected agent

    @Test func aLiveNoteWaitsForThePersonsOwnAgent() {
        var model = livePractice()
        #expect(model.isLive)
        #expect(model.liveAgent == "Claude Code")
        // The step to do now is telling that agent, with the phrase ready to copy
        var step = PracticeCopy.checklist(for: model)[1]
        #expect(step.isCurrent)
        #expect(step.text == "Tell Claude Code \u{201C}Check my Loupe notes\u{201D}")
        #expect(step.action == .copyPhrase(PracticeCopy.agentPrompt))

        model.agentRead()
        #expect(model.agentHasRead)
        step = PracticeCopy.checklist(for: model)[1]
        #expect(step.isDone && !step.isCurrent && step.action == nil)
        #expect(PracticeCopy.currentStep(for: model) == "Watch the practice app: Claude Code is on it")
        expect(model.agentMarkedSeen(), true)
        #expect(model.status?.label == "Agent working")
    }

    @Test func aLiveAgentRewritesThePageAndFinishes() {
        var model = livePractice(note: "make the letters italic")
        let page = "<button id=\"saveButton\" style=\"font-style: italic\">Save Plan</button>"
        expect(model.agentRewrotePage("  \(page)\n"), true)
        #expect(model.pageHTML == page)
        #expect(model.appWasChanged)

        expect(model.agentFinished(message: "Made the letters italic."), true)
        #expect(model.stage == .done)
        #expect(model.badge == .done)
        #expect(model.messages.last?.text == "Made the letters italic.")
        #expect(PracticeCopy.currentStep(for: model) == "It changed. Leave another note, or continue")
        // Nothing more can be done to a finished note
        expect(model.agentRewrotePage("<p>later</p>"), false)
        expect(model.agentReplied("one more thing"), false)
        #expect(model.pageHTML == page)
    }

    @Test func aPageWithNothingLeftIsRefused() {
        var model = livePractice()
        expect(model.agentRewrotePage("   "), false)
        expect(model.agentRewrotePage("<script>only()</script>"), false)
        expect(model.agentRewrotePage(String(repeating: "x", count: PracticePage.maxLength + 1)), false)
        #expect(model.pageHTML == PracticePage.startingHTML)
        #expect(!model.appWasChanged)
    }

    @Test func aLiveAgentCanAskAndBeAnsweredMoreThanOnce() {
        var model = livePractice()
        expect(model.agentReplied("How much bigger?"), true)
        #expect(model.stage == .questionForYou)
        #expect(model.status?.label == "Question for you")
        #expect(PracticeCopy.currentStep(for: model) == "Answer Claude Code in the note")
        expect(model.answer("A lot"), true)
        #expect(model.stage == .answered)
        #expect(!model.agentHasRead)
        let step = PracticeCopy.checklist(for: model)[2]
        #expect(step.text == "Tell Claude Code \u{201C}I answered in Loupe\u{201D}")
        #expect(step.action == .copyPhrase(PracticeCopy.agentFollowUp))
        expect(model.agentReplied("Got it, working on it."), true)
        #expect(model.status?.label == "Agent replied")
        expect(model.answer("Thanks"), true)
        expect(model.agentFinished(message: nil), true)
        #expect(model.messages.count == 5)
    }

    @Test func aDeclinedNoteShowsAsDismissed() {
        var model = livePractice()
        expect(model.agentFinished(message: "I can't do that here.", dismissed: true), true)
        #expect(model.badge == .dismissed)
        #expect(model.status?.label == "Dismissed")
        #expect(PracticeCopy.currentStep(for: model) == "No change this time. Try another, or continue")
    }

    @Test func aQuietAgentGetsAReminderNotAStandIn() {
        var model = livePractice()
        #expect(!model.agentIsQuiet)
        model.agentWentQuiet()
        #expect(model.agentIsQuiet)
        #expect(model.isLive)
        // Any sign of life clears it
        model.agentRead()
        #expect(!model.agentIsQuiet)
        // Without an agent there is nobody to be quiet
        var alone = practice(at: .noteAdded)
        alone.agentWentQuiet()
        #expect(!alone.agentIsQuiet)
    }

    @Test func agentsCannotActWithoutAnOpenNote() {
        for stage in [PracticeStage.pointing, .writingNote, .done, .finished] {
            let start = practice(at: stage)
            var model = start
            expect(model.agentReplied("hello"), false)
            expect(model.agentRewrotePage("<p>x</p>"), false)
            expect(model.agentMarkedSeen(), false)
            expect(model.agentFinished(message: "done"), false)
            model.agentRead()
            #expect(model == start)
        }
    }

    // MARK: Checklist

    /// At every point exactly one step is the one to do, earlier steps are ticked,
    /// and only that step carries a button
    @Test func theChecklistAlwaysHasOneStepToDo() {
        var moments = PracticeStage.allCases.filter { $0 != .finished && $0 != .questionForYou && $0 != .answered }.map { practice(at: $0) }
        var live = livePractice()
        moments.append(live)
        live.agentRead()
        moments.append(live)
        live.agentReplied("Which one?")
        moments.append(live)
        live.answer("That one")
        moments.append(live)
        live.agentRead()
        moments.append(live)

        for model in moments {
            let items = PracticeCopy.checklist(for: model, connectedAgent: "Claude Code")
            #expect(items.map(\.id) == [1, 2, 3])
            #expect(items.filter(\.isCurrent).count == 1, "\(model.stage)")
            #expect(items.first { $0.isCurrent }?.id == model.stepNumber)
            for item in items where !item.isCurrent {
                #expect(item.action == nil)
                #expect(item.isDone == (item.id < model.stepNumber || model.stage == .done))
            }
        }
    }

    /// Before a note exists, the list already says what comes next
    @Test func theChecklistFitsWhetherAnAgentIsConnected() {
        let model = PracticeModel()
        let with = PracticeCopy.checklist(for: model, connectedAgent: "Codex").map(\.text)
        #expect(with == ["Click something in the practice app", "Tell Codex to check your notes", "Watch the practice app change"])
        let without = PracticeCopy.checklist(for: model).map(\.text)
        #expect(without == ["Click something in the practice app", "Copy your note", "Paste it into your coding agent"])
        #expect(PracticeCopy.currentStep(for: practice(at: .writingNote)) == "Say what should change, then click Add")
    }

    // MARK: More than one note

    @Test func anotherNoteCanBeLeftOnceOneIsDone() {
        var model = livePractice()
        model.agentRewrotePage("<h1 id=\"heading\">Planner</h1><button id=\"saveButton\">Save</button>")
        model.agentFinished(message: "Done.")
        #expect(model.hasFinishedANote)
        #expect(model.canPickElement)
        let page = model.pageHTML

        // Clicking another element puts the finished note away and starts the next
        model.hover(.heading)
        #expect(model.outlinedElement == .heading)
        expect(model.select(.heading), true)
        #expect(model.stage == .writingNote)
        #expect(model.messages.isEmpty)
        #expect(model.noteRound == 1)
        #expect(model.finishedNotes == [.saveButton: .done])
        // The practice app keeps what the first note changed
        #expect(model.pageHTML == page)

        expect(model.addNote("make it green", liveAgent: "Claude Code"), true)
        #expect(model.noteNumber == 2)
        #expect(model.badges == [.saveButton: .done, .heading: .numbered(2)])
        // The new note needs its own change
        #expect(!model.appWasChanged)
    }

    @Test func theFinishedNoteCanBeClosedFirst() {
        var model = practice(at: .done)
        expect(model.leaveAnotherNote(), true)
        #expect(model.stage == .pointing)
        #expect(!model.isNoteOpen)
        // A copied note keeps its number as its badge
        #expect(model.finishedNotes == [.saveButton: .numbered(1)])
        #expect(PracticeCopy.currentStep(for: model) == "Click something else to leave another note")
        expect(model.leaveAnotherNote(), false)
        var open = practice(at: .noteAdded)
        expect(open.leaveAnotherNote(), false)
    }

    @Test func aNewNoteOnTheSameElementReplacesItsBadge() {
        var model = practice(at: .done)
        model.select(.saveButton)
        model.addNote("now make it blue")
        #expect(model.badges == [.saveButton: .numbered(2)])
    }

    /// Once one note is done, moving on is allowed from anywhere, even mid-note
    @Test func continueIsAvailableThroughoutAfterTheFirstNote() {
        for stage in [PracticeStage.pointing, .writingNote, .noteAdded] {
            var model = practice(at: stage)
            #expect(!model.hasFinishedANote)
            expect(model.continueToFinish(), false)
        }
        var model = practice(at: .done)
        model.select(.heading)
        model.addNote("make it green")
        expect(model.continueToFinish(), true)
        #expect(model.stage == .finished)
        #expect(model.messages.isEmpty)
        #expect(model.badges.isEmpty)
        #expect(!model.hasOpenNote)
    }

    @Test func personsActionsOutOfTurnDoNothing() {
        for stage in [PracticeStage.pointing, .writingNote, .noteAdded, .done, .finished] {
            let start = practice(at: stage)
            var model = start
            if stage != .pointing, stage != .done {
                expect(model.select(.heading), false)
                model.hover(.heading)
            }
            if stage != .writingNote {
                expect(model.addNote("another note"), false)
                model.cancelNote()
            }
            expect(model.answer("an answer"), false)
            if stage != .done { expect(model.continueToFinish(), false) }
            #expect(model == start, "\(stage) changed after an action that doesn't belong to it")
        }
    }

    // MARK: The page

    @Test func thePageStartsWithThreeThingsToPointAt() {
        for element in PracticeElement.allCases {
            #expect(PracticePage.startingHTML.contains("id=\"\(element.id)\""))
            #expect(PracticePage.startingHTML.contains(element.title))
        }
    }

    @Test func whatAnAgentSendsIsCleanedOfAnythingThatRunsOrLoads() {
        #expect(PracticePage.cleaned("<p>Hi</p><script>bad()</script>") == "<p>Hi</p>")
        #expect(PracticePage.cleaned("<SCRIPT src=x></SCRIPT><p>Hi</p>") == "<p>Hi</p>")
        #expect(PracticePage.cleaned("<iframe src=\"https://example.com\"></iframe><b>ok</b>") == "<b>ok</b>")
        #expect(PracticePage.cleaned("<link rel=stylesheet href=x><meta http-equiv=refresh><b>ok</b>") == "<b>ok</b>")
        // Styling is the point, so it stays
        #expect(PracticePage.cleaned("<style>h1 { color: red }</style><h1 style=\"font-style: italic\">Hi</h1>") == "<style>h1 { color: red }</style><h1 style=\"font-style: italic\">Hi</h1>")
        #expect(PracticePage.cleaned("  ") == nil)
    }

    /// The page may only use inline styles and inline images, and is told so in its own document
    @Test func thePageIsLockedDown() {
        #expect(PracticePage.document.contains("default-src 'none'"))
        #expect(PracticePage.document.contains("style-src 'unsafe-inline'"))
        #expect(!PracticePage.document.contains("script-src"))
    }

    // MARK: Words

    @Test func noEmDashesAnywhereInThePractice() {
        var strings = PracticeCopy.fixedStrings

        var moments = [PracticeStage.pointing, .writingNote, .noteAdded, .done].map { practice(at: $0) }
        var live = livePractice()
        moments.append(live)
        live.agentRead()
        moments.append(live)
        live.agentReplied("Which one?")
        moments.append(live)
        live.answer("That one")
        moments.append(live)
        var declined = live
        declined.agentFinished(message: nil, dismissed: true)
        moments.append(declined)
        live.agentFinished(message: "Done.")
        moments.append(live)
        for moment in moments {
            strings += PracticeCopy.checklist(for: moment).map(\.text)
            strings += PracticeCopy.checklist(for: moment, connectedAgent: "Claude Code").map(\.text)
            strings.append(moment.copiedText + " ")
        }
        strings.append(PracticePage.howToEdit)

        for string in strings {
            #expect(!string.isEmpty)
            #expect(!string.contains("\u{2014}"), "Em dash in: \(string)")
        }
    }

    @Test func theAgentLinkMessageIsKept() {
        #expect(PracticeCopy.agentLinkBody.contains("Agent Link in Settings"))
        #expect(PracticeCopy.copyBody.contains("Copy"))
    }

    @Test func theClosingScreenDoesNotTellAConnectedPersonToTurnAgentLinkOn() {
        let text = PracticeCopy.agentLinkConnectedBody(agent: "Claude Code")
        #expect(text.contains("Agent Link is on"))
        #expect(text.contains("Claude Code"))
        #expect(text.contains(PracticeCopy.agentPrompt))
        #expect(!text.contains("Settings"))
    }

    // MARK: The running practice

    @Test func aNoteGoesToTheConnectedAgentWhenThereIsOne() {
        let session = PracticeSession()
        session.select(.saveButton)
        session.addNote("bigger")
        #expect(!session.model.isLive)
        #expect(!session.isOpenToAgents)
        // No agent: the agent's calls do nothing
        #expect(!session.agentRewrotePage("<p>x</p>"))
        #expect(session.copyNote())
        #expect(session.model.stage == .done)

        session.reset()
        session.connectedAgent = { "Codex" }
        session.select(.saveButton)
        session.addNote("bigger")
        #expect(session.model.liveAgent == "Codex")
        #expect(session.isOpenToAgents)
        #expect(!session.copyNote())
    }

    @Test func aQuietAgentBringsUpTheReminder() async throws {
        let session = PracticeSession(quietAgentDelay: .milliseconds(40))
        session.connectedAgent = { "Codex" }
        session.select(.heading)
        session.addNote("bolder")
        #expect(!session.model.agentIsQuiet)
        try await waitUntil { session.model.agentIsQuiet }
        // Nothing takes the note over
        #expect(session.model.isLive)
        #expect(session.model.stage == .noteAdded)
    }

    @Test func startingOverForgetsEverything() {
        let session = PracticeSession()
        session.connectedAgent = { "Codex" }
        session.select(.heading)
        session.addNote("bolder")
        session.agentRewrotePage("<p>New page</p>")
        session.pageWasRendered("<p>New page</p>")
        session.reset()
        #expect(session.model == PracticeModel())
        #expect(session.currentPageHTML == PracticePage.startingHTML)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
