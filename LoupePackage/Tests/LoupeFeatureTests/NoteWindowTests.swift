import Testing
import Foundation
import ApplicationServices
@testable import LoupeFeature

/// The note window's plain-language names, status label, and user replies
@MainActor
struct NoteWindowTests {

    private func element() -> AXElementInfo {
        AXElementInfo(
            role: "AXPopUpButton",
            identifier: nil,
            title: nil,
            value: "Regular",
            frame: CGRect(x: 120, y: 140, width: 80, height: 22),
            hierarchyPath: [],
            element: AXUIElementCreateSystemWide(),
            siblings: [],
            windowFrame: nil
        )
    }

    private func note(status: NoteStatus, replies: [NoteReply] = []) -> Annotation {
        Annotation(
            badgeNumber: 1,
            text: "make this bold",
            elementFrame: .zero,
            elementRole: "AXPopUpButton",
            elementIdentifier: nil,
            status: status,
            replies: replies
        )
    }

    // MARK: Names

    @Test func knownRolesGetPlainNames() {
        #expect(ElementKind.name(forRole: "AXPopUpButton") == "Menu")
        #expect(ElementKind.name(forRole: "AXStaticText") == "Text")
        #expect(ElementKind.name(forRole: "AXCheckBox") == "Checkbox")
    }

    @Test func unknownRolesAreSplitIntoWords() {
        #expect(ElementKind.name(forRole: "AXRulerMarker") == "Ruler marker")
        #expect(ElementKind.name(forRole: "AX") == "Element")
    }

    @Test func visibleTextPrefersTitleThenValueAndShortensLongText() {
        #expect(ElementKind.visibleText(title: "Save", value: "x", identifier: "id") == "Save")
        #expect(ElementKind.visibleText(title: " ", value: "Regular", identifier: nil) == "Regular")
        #expect(ElementKind.visibleText(title: nil, value: nil, identifier: nil) == nil)
        let long = String(repeating: "a", count: 60)
        let shortened = ElementKind.visibleText(title: long, value: nil, identifier: nil, limit: 40)
        #expect(shortened?.count == 40)
        #expect(shortened?.hasSuffix("…") == true)
        #expect(ElementKind.visibleText(title: "First line\nSecond", value: nil, identifier: nil) == "First line")
    }

    @Test func headerReadsInPlainLanguage() {
        let summary = NoteElementSummary(element: element(), appName: "TextEdit")
        #expect(summary.kindLine == "Menu in TextEdit")
        #expect(summary.nameLine == "\u{201C}Regular\u{201D}")
        #expect(summary.details.first?.label == "Role")
    }

    @Test func everyPlaceUsesTheSamePlainName() {
        let info = element()
        #expect(info.displayLabel(style: .humanized) == "Menu \u{201C}Regular\u{201D}")
        #expect(info.displayLabel(style: .technical) == "AXPopUpButton")
        #expect(ElementKind.label(role: "AXButton", title: nil, value: nil, identifier: nil) == "Button")
    }

    @Test func systemMadeIdentifiersAreHidden() {
        #expect(ElementKind.isReadableIdentifier("First Text View"))
        #expect(!ElementKind.isReadableIdentifier("_NS:31"))
        #expect(!ElementKind.isReadableIdentifier("12345"))
        #expect(!ElementKind.isReadableIdentifier("6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        #expect(ElementKind.visibleText(title: nil, value: "", identifier: "_NS:8") == nil)
        #expect(ElementKind.visibleText(title: nil, value: "", identifier: "First Text View") == "First Text View")
    }

    // MARK: Status label

    @Test func statusLabelSaysWhatTheNoteNeeds() {
        #expect(NoteAttention(note: note(status: .pending)) == .waiting)
        #expect(NoteAttention(note: note(status: .seen)) == .agentWorking)
        #expect(NoteAttention(note: note(status: .done)) == .done)
        #expect(NoteAttention(note: note(status: .dismissed)) == .dismissed)

        let question = note(status: .pending, replies: [NoteReply(author: .agent, text: "Bold text, or a bold label?")])
        #expect(NoteAttention(note: question) == .questionForYou)
        #expect(NoteAttention(note: question).focusesReply)

        let update = note(status: .seen, replies: [NoteReply(author: .agent, text: "Working on it.")])
        #expect(NoteAttention(note: update) == .agentReplied)

        let answered = note(status: .pending, replies: [
            NoteReply(author: .agent, text: "Which one?"),
            NoteReply(author: .user, text: "The text")
        ])
        #expect(NoteAttention(note: answered) == .waiting)
    }

    // MARK: Replies

    @Test func userReplyReopensTheNote() throws {
        let store = AnnotationStore(fileURL: nil)
        store.selectApp(key: "com.apple.TextEdit")
        let added = store.addAnnotation(text: "rename this", for: element(), appName: "TextEdit", bundleIdentifier: "com.apple.TextEdit")
        store.setStatus(id: added.id, to: .done, message: "Renamed it")

        let updated = try #require(store.addUserReply(id: added.id, text: "  Use Draft instead  "))
        #expect(updated.status == .pending)
        #expect(updated.replies.last?.author == .user)
        #expect(updated.replies.last?.text == "Use Draft instead")
    }

    @Test func blankUserReplyChangesNothing() throws {
        let store = AnnotationStore(fileURL: nil)
        store.selectApp(key: "com.apple.TextEdit")
        let added = store.addAnnotation(text: "rename this", for: element(), appName: "TextEdit", bundleIdentifier: "com.apple.TextEdit")
        store.setStatus(id: added.id, to: .done)

        let unchanged = try #require(store.addUserReply(id: added.id, text: "   "))
        #expect(unchanged.status == .done)
        #expect(unchanged.replies.isEmpty)
    }
}

/// The count behind the menu bar's coral dot
@MainActor
struct QuestionsForYouTests {
    private func element() -> AXElementInfo {
        AXElementInfo(role: "AXButton", identifier: nil, title: "Save", value: nil,
                      frame: .zero, hierarchyPath: [], element: AXUIElementCreateSystemWide(),
                      siblings: [], windowFrame: nil)
    }

    @Test func countsUnansweredAgentQuestionsAcrossApps() throws {
        let store = AnnotationStore(fileURL: nil)
        #expect(store.questionsForYou == 0)

        let a = store.addAnnotation(text: "rename", for: element(), appName: "TextEdit", bundleIdentifier: "com.apple.TextEdit")
        let b = store.addAnnotation(text: "bigger", for: element(), appName: "Notes", bundleIdentifier: "com.apple.Notes")
        store.addReply(id: a.id, text: "Rename to what?", author: .agent)
        store.addReply(id: b.id, text: "Bold or larger?", author: .agent)
        #expect(store.questionsForYou == 2)

        store.addUserReply(id: a.id, text: "Draft")
        #expect(store.questionsForYou == 1)

        store.setStatus(id: b.id, to: .done, message: "Made it bold.")
        #expect(store.questionsForYou == 0)
    }

    @Test func menuBarGlyphIsATemplateImage() {
        let image = MenuBarIcon.image(leavingRoomForDot: true)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
    }
}
