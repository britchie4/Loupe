import Testing
import Foundation
@testable import LoupeFeature

/// The practice step in setup: point, leave a note, and watch an agent change the practice app
@MainActor
struct PracticeTests {

    /// A practice with the pretend agent that has reached the given stage the way a person would
    private func practice(at stage: PracticeStage, note: String = "make this bigger", answer: String = "only here") -> PracticeModel {
        var model = PracticeModel()
        let steps: [(PracticeStage, (inout PracticeModel) -> Void)] = [
            (.writingNote, { $0.select(.saveButton) }),
            (.noteAdded, { $0.addNote(note) }),
            (.questionForYou, { $0.agentMoves() }),
            (.answered, { $0.answer(answer) }),
            (.done, { $0.agentMoves() }),
            (.finished, { $0.continueToFinish() })
        ]
        for (reached, step) in steps where model.stage != stage {
            step(&model)
            #expect(model.stage == reached)
        }
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

    // MARK: Hover

    @Test func startsByPointingWithNothingOnScreen() {
        let model = PracticeModel()
        #expect(model.stage == .pointing)
        #expect(model.stepNumber == 1)
        #expect(model.outlinedElement == nil)
        #expect(model.badge == nil)
        #expect(model.status == nil)
        #expect(model.messages.isEmpty)
        #expect(!model.isNoteOpen)
        #expect(model.pendingAgentMove == nil)
        for element in PracticeElement.allCases {
            #expect(model.look(of: element) == PracticeLook(text: element.title))
        }
    }

    @Test func pointingOutlinesTheElementUnderThePointer() {
        var model = PracticeModel()
        model.hover(.heading)
        #expect(model.outlinedElement == .heading)
        // Moving from one element to the next: "entered" can arrive before "left"
        model.hover(.saveButton)
        model.unhover(.heading)
        #expect(model.outlinedElement == .saveButton)
        model.unhover(.saveButton)
        #expect(model.outlinedElement == nil)
    }

    // MARK: Annotate

    @Test func clickingOpensTheNoteWindowAndKeepsTheOutline() {
        var model = PracticeModel()
        model.hover(.reminder)
        expect(model.select(.reminder), true)
        #expect(model.stage == .writingNote)
        #expect(model.stepNumber == 2)
        #expect(model.isNoteOpen)
        #expect(model.selected == .reminder)
        #expect(model.outlinedElement == .reminder)
        // The pointer wandering off no longer moves the outline
        model.hover(.heading)
        #expect(model.outlinedElement == .reminder)
        #expect(model.badge == nil)
    }

    @Test func cancellingGoesBackToPointing() {
        var model = practice(at: .writingNote)
        model.cancelNote()
        #expect(model.stage == .pointing)
        #expect(model.selected == nil)
        #expect(!model.isNoteOpen)
        expect(model.select(.heading), true)
        #expect(model.selected == .heading)
    }

    @Test func blankNotesAreRefused() {
        var model = practice(at: .writingNote)
        expect(model.addNote(""), false)
        expect(model.addNote("  \n "), false)
        #expect(model.stage == .writingNote)
        #expect(model.messages.isEmpty)
    }

    @Test func addingTheNotePinsANumberedBadge() {
        var model = practice(at: .writingNote)
        expect(model.addNote("  make this bigger \n"), true)
        #expect(model.stage == .noteAdded)
        #expect(model.stepNumber == 3)
        #expect(model.messages.map(\.text) == ["make this bigger"])
        #expect(model.messages.first?.author == .user)
        #expect(model.badge == .numbered(1))
        #expect(model.status?.label == "Waiting")
        #expect(model.outlinedElement == nil)
        #expect(model.isNoteOpen)
        #expect(!model.isLive)
        #expect(model.pendingAgentMove == .askQuestion)
    }

    // MARK: The pretend agent

    @Test func thePretendAgentAsksAQuestion() {
        var model = practice(at: .noteAdded)
        expect(model.agentMoves(), true)
        #expect(model.stage == .questionForYou)
        #expect(model.messages.last?.author == .agent)
        #expect(model.messages.last?.text == PracticeCopy.agentQuestion)
        #expect(model.status?.label == "Question for you")
        #expect(model.badge == .numbered(1))
        // It waits for the person now
        #expect(model.pendingAgentMove == nil)
        expect(model.agentMoves(), false)
    }

    @Test func answeringReturnsTheNoteToWaiting() {
        var model = practice(at: .questionForYou)
        expect(model.answer("   "), false)
        #expect(model.stage == .questionForYou)
        expect(model.answer(" everywhere "), true)
        #expect(model.stage == .answered)
        #expect(model.messages.last?.text == "everywhere")
        #expect(model.status?.label == "Waiting")
        #expect(model.pendingAgentMove == .finish)
    }

    @Test func thePretendAgentChangesThePracticeAppAndTheBadgeTurnsGreen() {
        let model = practice(at: .done, note: "Make this button bigger", answer: "Only here")
        #expect(model.messages.map(\.author) == [.user, .agent, .user, .agent])
        #expect(model.messages.map(\.id) == [0, 1, 2, 3])
        #expect(model.messages.last?.text == "Done. I made it bigger.")
        #expect(model.look(of: .saveButton).size == .bigger)
        // Only the element the note is on
        #expect(model.look(of: .heading).size == .normal)
        #expect(model.look(of: .reminder).size == .normal)
        #expect(model.appWasChanged)
        #expect(model.badge == .done)
        #expect(model.status?.label == "Done")
        #expect(model.pendingAgentMove == nil)
    }

    @Test func answeringEverywhereChangesEveryElement() {
        let model = practice(at: .done, note: "make this red and bold", answer: "Everywhere, please")
        for element in PracticeElement.allCases {
            #expect(model.look(of: element).color == .red)
            #expect(model.look(of: element).bold)
        }
        #expect(model.messages.last?.text == "Done. I turned everything red and made everything bold.")
    }

    @Test func aRenameStaysOnTheOneElementEvenWhenAnsweredEverywhere() {
        let model = practice(at: .done, note: "Rename it to Save Trip", answer: "everywhere")
        #expect(model.look(of: .saveButton).text == "Save Trip")
        #expect(model.look(of: .heading).text == "Weekend Planner")
        #expect(model.look(of: .reminder).text == "Remind me on Friday")
        #expect(model.messages.last?.text == "Done. I renamed it to \u{201C}Save Trip\u{201D}.")
    }

    @Test func aNoteItCannotReadGetsTheSuggestedChangeAndAnHonestReply() {
        let model = practice(at: .done, note: "this feels off somehow", answer: "here")
        #expect(model.look(of: .saveButton).size == .bigger)
        let reply = model.messages.last?.text ?? ""
        #expect(reply.contains("practice agent"))
        #expect(reply.contains("made it bigger"))
    }

    // MARK: Reading a note

    @Test func commonWordsAreUnderstood() {
        func change(_ note: String, _ element: PracticeElement = .saveButton) -> PracticeChange {
            PracticeInterpreter.reading(of: note, for: element).change
        }
        #expect(change("Make this button bigger") == PracticeChange(size: .bigger))
        #expect(change("WAY bigger!") == PracticeChange(size: .muchBigger))
        #expect(change("make it smaller") == PracticeChange(size: .smaller))
        #expect(change("should be green") == PracticeChange(color: .green))
        #expect(change("Grey, and bolder") == PracticeChange(color: .gray, bold: true))
        #expect(change("make it pop") == PracticeChange(bold: true))
        #expect(change("Rename this to \u{201C}Save Trip\u{201D}.") == PracticeChange(text: "Save Trip"))
        // New words aren't mistaken for requests: "Big" here is part of the name
        #expect(change("call it Big Blue Plans") == PracticeChange(text: "Big Blue Plans"))
        #expect(change("make it blue and change the text to Go") == PracticeChange(text: "Go", color: .blue))
        // Whole words only
        #expect(!PracticeInterpreter.reading(of: "the wording is unclear, reword it", for: .saveButton).understood)
    }

    @Test func tickingOnlyAppliesToTheCheckbox() {
        #expect(PracticeInterpreter.reading(of: "Tick this by default", for: .reminder).change == PracticeChange(checked: true))
        #expect(PracticeInterpreter.reading(of: "untick it", for: .reminder).change == PracticeChange(checked: false))
        #expect(!PracticeInterpreter.reading(of: "tick this", for: .saveButton).understood)
    }

    @Test func everySuggestedNoteIsUnderstoodAsItsSuggestedChange() {
        for element in PracticeElement.allCases {
            let reading = PracticeInterpreter.reading(of: element.suggestedNote, for: element)
            #expect(reading.understood, "\(element.suggestedNote)")
            #expect(reading.change == element.suggestedChange, "\(element.suggestedNote)")
        }
    }

    @Test func everywhereIsReadFromTheAnswer() {
        for answer in ["everywhere", "Everywhere, please", "all of them", "do both", "every one"] {
            #expect(PracticeInterpreter.wantsEverywhere(answer), "\(answer)")
        }
        for answer in ["only here", "just this one", "here", "not everywhere", "just here, not all", "small one"] {
            #expect(!PracticeInterpreter.wantsEverywhere(answer), "\(answer)")
        }
    }

    // MARK: A connected agent

    @Test func aLiveNoteWaitsForThePersonsOwnAgent() {
        var model = livePractice()
        #expect(model.isLive)
        #expect(model.liveAgent == "Claude Code")
        // The pretend agent stays out of it
        #expect(model.pendingAgentMove == nil)
        expect(model.agentMoves(), false)
        #expect(PracticeCopy.title(for: model) == "Now ask your agent")
        #expect(PracticeCopy.body(for: model).contains(PracticeCopy.agentPrompt))

        model.agentRead()
        #expect(model.agentHasRead)
        #expect(PracticeCopy.title(for: model) == "Your agent is on it")
        expect(model.agentMarkedSeen(), true)
        #expect(model.status?.label == "Agent working")
    }

    @Test func aLiveAgentCanChangeAnyElementAndFinish() {
        var model = livePractice()
        expect(model.agentChanged([.saveButton], PracticeChange(text: "  Save Trip\nsecond line", size: .muchBigger, color: .blue)), true)
        expect(model.agentChanged([.heading, .reminder], PracticeChange(bold: true, checked: true)), true)
        #expect(model.look(of: .saveButton) == PracticeLook(text: "Save Trip", size: .muchBigger, color: .blue))
        #expect(model.look(of: .heading).bold)
        // A tick only lands on the checkbox
        #expect(!model.look(of: .heading).checked)
        #expect(model.look(of: .reminder).checked)

        expect(model.agentFinished(message: "Made the button bigger and blue."), true)
        #expect(model.stage == .done)
        #expect(model.badge == .done)
        #expect(model.messages.last?.text == "Made the button bigger and blue.")
        #expect(PracticeCopy.title(for: model) == "Your agent made the change")
        // Nothing more can be done to a finished note
        expect(model.agentChanged([.heading], PracticeChange(color: .red)), false)
        expect(model.agentReplied("one more thing"), false)
    }

    @Test func aLiveAgentCanAskAndBeAnsweredMoreThanOnce() {
        var model = livePractice()
        expect(model.agentReplied("How much bigger?"), true)
        #expect(model.stage == .questionForYou)
        #expect(model.status?.label == "Question for you")
        expect(model.answer("A lot"), true)
        #expect(model.stage == .answered)
        #expect(!model.agentHasRead)
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
        #expect(PracticeCopy.title(for: model) == "Your agent passed on this one")
    }

    @Test func aQuietAgentCanBeSwappedForThePretendOne() {
        var model = livePractice(note: "make it purple")
        #expect(!model.offersPretendAgent)
        model.offerPretendAgent()
        #expect(model.offersPretendAgent)
        expect(model.switchToPretendAgent(), true)
        #expect(!model.isLive)
        #expect(!model.offersPretendAgent)
        #expect(model.pendingAgentMove == .askQuestion)
        model.agentMoves()
        model.answer("only here")
        model.agentMoves()
        #expect(model.look(of: .saveButton).color == .purple)
        #expect(model.stage == .done)
    }

    @Test func thePretendAgentIsNeverOfferedInAScriptedPractice() {
        var model = practice(at: .noteAdded)
        model.offerPretendAgent()
        #expect(!model.offersPretendAgent)
        expect(model.switchToPretendAgent(), false)
    }

    @Test func nothingChangesBeforeThereIsANote() {
        var model = PracticeModel()
        let start = model
        expect(model.agentChanged([.heading], PracticeChange(color: .red)), false)
        expect(model.agentReplied("hello?"), false)
        expect(model.agentMarkedSeen(), false)
        expect(model.agentFinished(message: "done"), false)
        model.agentRead()
        #expect(model == start)
    }

    // MARK: Finish

    @Test func finishingThrowsThePracticeNoteAway() {
        var model = practice(at: .done)
        expect(model.continueToFinish(), true)
        #expect(model.stage == .finished)
        #expect(model.messages.isEmpty)
        #expect(model.selected == nil)
        #expect(model.badge == nil)
        #expect(!model.isNoteOpen)
        #expect(!model.hasOpenNote)
    }

    @Test func personsActionsOutOfTurnDoNothing() {
        for stage in PracticeStage.allCases {
            let start = practice(at: stage)

            var model = start
            if stage != .pointing {
                expect(model.select(.heading), false)
                model.hover(.heading)
            }
            if stage != .writingNote {
                expect(model.addNote("another note"), false)
                model.cancelNote()
            }
            if stage != .questionForYou { expect(model.answer("an answer"), false) }
            if stage != .noteAdded, stage != .answered { expect(model.agentMoves(), false) }
            if stage != .done { expect(model.continueToFinish(), false) }
            #expect(model == start, "\(stage) changed after an action that doesn't belong to it")
        }
    }

    // MARK: Words

    @Test func scriptedQuestionReadsAsAQuestionToTheRealNoteWindow() {
        // The real note window decides "Question for you" by looking for a question mark
        #expect(PracticeCopy.agentQuestion.contains("?"))
    }

    @Test func elementsUseLoupesPlainNames() {
        #expect(PracticeElement.saveButton.kindLine == "Button in Practice App")
        #expect(PracticeElement.saveButton.nameLine == "\u{201C}Save Plan\u{201D}")
        #expect(PracticeElement.reminder.kindLine == "Checkbox in Practice App")
        #expect(PracticeElement.heading.kindLine == "Heading in Practice App")
        #expect(PracticeElement.saveButton.accessibilityLabel(showing: "Save Trip") == "Save Trip, button in the practice app")
    }

    @Test func noEmDashesAnywhereInThePractice() {
        var strings = PracticeCopy.fixedStrings

        // Every instruction, scripted and live, at every point of the practice
        var moments = PracticeStage.allCases.map { practice(at: $0) }
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
        var declined = live
        declined.agentFinished(message: nil, dismissed: true)
        moments.append(declined)
        live.agentFinished(message: "Done.")
        moments.append(live)
        for moment in moments {
            strings += [PracticeCopy.title(for: moment), PracticeCopy.body(for: moment)]
        }

        // Everything the pretend agent can say
        for element in PracticeElement.allCases {
            for note in [element.suggestedNote, "rename it to Trip", "smaller, pink and bold", "untick it", "delete this", "no idea"] {
                let reading = PracticeInterpreter.reading(of: note, for: element)
                strings.append(PracticeInterpreter.doneMessage(for: reading, everywhere: false))
                strings.append(PracticeInterpreter.doneMessage(for: reading, everywhere: true))
            }
        }

        for string in strings {
            #expect(!string.isEmpty)
            #expect(!string.contains("\u{2014}"), "Em dash in: \(string)")
        }
    }

    @Test func askingToDeleteSomethingRemovesIt() {
        for note in ["delete this button", "Remove this", "hide it please", "get rid of this", "take this out"] {
            let reading = PracticeInterpreter.reading(of: note, for: .saveButton)
            #expect(reading.understood, "\(note)")
            #expect(reading.change == PracticeChange(removed: true), "\(note)")
        }
        // Taking the tick off a checkbox is not removing the checkbox
        #expect(PracticeInterpreter.reading(of: "remove the tick", for: .reminder).change == PracticeChange(checked: false))
        // A new name that happens to contain such a word is still a rename
        #expect(PracticeInterpreter.reading(of: "rename it to Delete Plan", for: .saveButton).change == PracticeChange(text: "Delete Plan"))

        let reading = PracticeInterpreter.reading(of: "delete this button", for: .saveButton)
        #expect(PracticeInterpreter.doneMessage(for: reading, everywhere: false) == "Done. I removed it.")
    }

    @Test func theScriptedAgentRemovesOnlyTheElementAskedAbout() {
        // Even when the answer is "everywhere": removing is about one element, not a style
        let model = practice(at: .done, note: "delete this button", answer: "everywhere")
        #expect(model.look(of: .saveButton).removed)
        #expect(!model.look(of: .heading).removed)
        #expect(!model.look(of: .reminder).removed)
        #expect(model.messages.last?.text == "Done. I removed it.")
        #expect(model.appWasChanged)
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

    @Test func agentsThatDoNotIntroduceThemselvesAreYourAgent() {
        #expect(PracticeCopy.displayName(forAgent: "Agent") == "your agent")
        #expect(PracticeCopy.displayName(forAgent: "Claude Code") == "Claude Code")
    }

    // MARK: Running a practice

    @Test func aWholeScriptedPracticeRunsByItself() async throws {
        let session = PracticeSession(agentDelay: .milliseconds(10))
        session.hover(.saveButton)
        session.select(.saveButton)
        session.addNote("make this bigger")
        #expect(session.model.stage == .noteAdded)
        #expect(!session.isOpenToAgents)

        try await waitUntil { session.model.stage == .questionForYou }
        session.answer("everywhere")
        #expect(session.model.stage == .answered)

        try await waitUntil { session.model.stage == .done }
        #expect(session.model.badge == .done)
        #expect(session.model.look(of: .heading).size == .bigger)
        session.continueToFinish()
        #expect(session.model.stage == .finished)
    }

    @Test func startingOverStopsAReplyThatWasOnItsWay() async throws {
        let session = PracticeSession(agentDelay: .milliseconds(40))
        session.select(.heading)
        session.addNote("bolder")
        session.reset()
        #expect(session.model == PracticeModel())

        try await Task.sleep(for: .milliseconds(150))
        #expect(session.model == PracticeModel())
    }

    @Test func aConnectedAgentGetsTheNoteAndThePretendAgentStaysQuiet() async throws {
        let session = PracticeSession(agentDelay: .milliseconds(10), quietAgentDelay: .milliseconds(60))
        session.connectedAgent = { "Claude Code" }
        session.select(.saveButton)
        session.addNote("make this bigger")
        #expect(session.model.isLive)
        #expect(session.isOpenToAgents)

        // No scripted reply arrives; after a while the pretend agent is offered instead
        try await waitUntil { session.model.offersPretendAgent }
        #expect(session.model.stage == .noteAdded)
        #expect(session.model.messages.count == 1)

        // The person takes the offer and the scripted practice carries on
        session.usePretendAgent()
        #expect(!session.isOpenToAgents)
        try await waitUntil { session.model.stage == .questionForYou }
        // A real agent can no longer touch the note
        #expect(!session.agentReplied("late reply"))
        #expect(!session.agentChanged([.heading], PracticeChange(color: .red)))
    }

    @Test func anAgentMakingProgressIsNotInterrupted() async throws {
        let session = PracticeSession(quietAgentDelay: .milliseconds(80))
        session.connectedAgent = { "Claude Code" }
        session.select(.saveButton)
        session.addNote("make this bigger")
        try await Task.sleep(for: .milliseconds(50))
        session.agentRead()
        try await Task.sleep(for: .milliseconds(50))
        // 100 ms since the note, but only 50 since the agent last did something
        #expect(!session.model.offersPretendAgent)
        #expect(session.agentChanged([.saveButton], PracticeChange(size: .bigger)))
        #expect(session.agentFinished(message: "Bigger now.", dismissed: false))
        try await Task.sleep(for: .milliseconds(120))
        #expect(!session.model.offersPretendAgent)
        #expect(session.model.stage == .done)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
