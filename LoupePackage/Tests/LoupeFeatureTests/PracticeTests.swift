import Testing
import Foundation
@testable import LoupeFeature

/// The practice step in setup: point, leave a note, talk to a pretend agent, finish
@MainActor
struct PracticeTests {

    /// A practice that has reached the given stage the way a person would get there
    private func practice(at stage: PracticeStage) -> PracticeModel {
        var model = PracticeModel()
        let steps: [(PracticeStage, (inout PracticeModel) -> Void)] = [
            (.writingNote, { $0.select(.saveButton) }),
            (.noteAdded, { $0.addNote("make this bigger") }),
            (.questionForYou, { $0.agentMoves() }),
            (.answered, { $0.answer("everywhere") }),
            (.done, { $0.agentMoves() }),
            (.finished, { $0.continueToFinish() })
        ]
        for (reached, step) in steps where model.stage != stage {
            step(&model)
            #expect(model.stage == reached)
        }
        return model
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
        // And a different element can be picked afterwards
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
        #expect(model.status == .waiting)
        #expect(model.status?.label == "Waiting")
        #expect(model.outlinedElement == nil)
        #expect(model.isNoteOpen)
        #expect(model.pendingAgentMove == .askQuestion)
    }

    // MARK: Agent replies

    @Test func theAgentAsksAQuestion() {
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
        #expect(model.messages.last?.author == .user)
        #expect(model.status?.label == "Waiting")
        #expect(model.pendingAgentMove == .finish)
    }

    @Test func theAgentFinishesAndTheBadgeTurnsGreen() {
        var model = practice(at: .answered)
        expect(model.agentMoves(), true)
        #expect(model.stage == .done)
        #expect(model.messages.map(\.author) == [.user, .agent, .user, .agent])
        #expect(model.messages.last?.text == PracticeCopy.agentDone)
        #expect(model.messages.map(\.id) == [0, 1, 2, 3])
        #expect(model.badge == .done)
        #expect(model.status?.label == "Done")
        #expect(model.pendingAgentMove == nil)
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
    }

    @Test func actionsOutOfTurnDoNothing() {
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
        #expect(!PracticeCopy.agentDone.contains("?"))
    }

    @Test func elementsUseLoupesPlainNames() {
        #expect(PracticeElement.saveButton.kindLine == "Button in Practice App")
        #expect(PracticeElement.saveButton.nameLine == "\u{201C}Save Plan\u{201D}")
        #expect(PracticeElement.reminder.kindLine == "Checkbox in Practice App")
        #expect(PracticeElement.heading.kindLine == "Heading in Practice App")
    }

    @Test func noEmDashesAnywhereInThePractice() {
        for string in PracticeCopy.allStrings {
            #expect(!string.isEmpty)
            #expect(!string.contains("\u{2014}"), "Em dash in: \(string)")
        }
    }

    @Test func theAgentLinkMessageIsKept() {
        #expect(PracticeCopy.agentLinkBody.contains("Agent Link in Settings"))
        #expect(PracticeCopy.copyBody.contains("Copy"))
    }

    // MARK: The scripted agent's timing

    @Test func aWholePracticeRunsWithScriptedReplies() async throws {
        let session = PracticeSession(agentDelay: .milliseconds(10))
        session.hover(.saveButton)
        session.select(.saveButton)
        session.addNote("make this bigger")
        #expect(session.model.stage == .noteAdded)

        try await waitUntil { session.model.stage == .questionForYou }
        session.answer("everywhere")
        #expect(session.model.stage == .answered)

        try await waitUntil { session.model.stage == .done }
        #expect(session.model.badge == .done)
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

    /// Mutating calls can't sit inside #expect, so their result is checked here
    private func expect(_ result: Bool, _ expected: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(result == expected, sourceLocation: sourceLocation)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
