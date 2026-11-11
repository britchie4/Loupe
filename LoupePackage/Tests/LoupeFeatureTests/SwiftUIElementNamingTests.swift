import Testing
import Foundation
import AppKit
import ApplicationServices
@testable import LoupeFeature

/// SwiftUI controls have no accessibility title: `Button("Save Plan")` reports its text as
/// the accessibility description. Loupe names them from that, everywhere a name is shown
/// or handed to an agent.
@MainActor
struct SwiftUIElementNamingTests {

    private let store = AnnotationStore(fileURL: nil)
    private let handler: MCPHandler

    init() {
        let context = AgentLinkTools.Context(
            store: store, inspector: AccessibilityInspector(), selectedApp: { nil }, isInspecting: { false }
        )
        handler = MCPHandler(tools: AgentLinkTools.make(context: context))
        store.selectApp(key: "com.example.planner")
    }

    /// What Loupe reads from a SwiftUI `Button("Save Plan")`
    private func swiftUIButton() -> AXElementInfo {
        AXElementInfo(
            role: "AXButton",
            identifier: nil,
            title: nil,
            value: nil,
            frame: CGRect(x: 773, y: 513, width: 83, height: 24),
            hierarchyPath: [
                HierarchyNode(role: "AXWindow", title: "Weekend Planner"),
                HierarchyNode(role: "AXGroup"),
                HierarchyNode(role: "AXButton", description: "Save Plan")
            ],
            element: AXUIElementCreateSystemWide(),
            axDescription: "Save Plan"
        )
    }

    private func addNote() -> Annotation {
        store.addAnnotation(
            text: "Make this stand out",
            for: swiftUIButton(),
            windowTitle: "Weekend Planner",
            appName: "Weekend Planner",
            bundleIdentifier: "com.example.planner"
        )
    }

    // MARK: Names on screen

    @Test func hoverLabelNamesASwiftUIButton() {
        let button = swiftUIButton()
        #expect(button.displayLabel(style: .humanized) == "Button \u{201C}Save Plan\u{201D}")
        #expect(button.displayLabel(style: .technical) == "AXButton[description=\"Save Plan\"]")
    }

    @Test func titleStillWinsOverDescription() {
        #expect(ElementKind.visibleText(title: "Save", description: "Saves the plan", value: nil, identifier: nil) == "Save")
        #expect(ElementKind.technicalLabel(role: "AXButton", identifier: "save", title: "Save", description: "Saves the plan")
            == "AXButton[identifier=\"save\", title=\"Save\"]")
        #expect(ElementKind.accessibleName(title: "Save", description: "Saves the plan") == "Save")
    }

    @Test func descriptionComesBeforeValue() {
        // A SwiftUI checkbox: its label is the description, its value is 0 or 1
        #expect(ElementKind.visibleText(title: nil, description: "Remind me on Friday", value: "0", identifier: nil) == "Remind me on Friday")
        #expect(ElementKind.accessibleName(title: " ", description: " ") == nil)
        #expect(ElementKind.technicalLabel(role: "AXButton", identifier: nil, title: nil, description: "") == "AXButton")
    }

    @Test func noteWindowHeaderNamesASwiftUIButton() {
        let live = NoteElementSummary(element: swiftUIButton(), appName: "Weekend Planner")
        #expect(live.kindLine == "Button in Weekend Planner")
        #expect(live.nameLine == "\u{201C}Save Plan\u{201D}")
        #expect(live.details.contains { $0.label == "Description" && $0.value == "Save Plan" })

        let saved = NoteElementSummary(annotation: addNote())
        #expect(saved.nameLine == "\u{201C}Save Plan\u{201D}")
    }

    @Test func savedNoteKeepsTheName() {
        let note = addNote()
        #expect(note.elementTitle == nil)
        #expect(note.elementDescription == "Save Plan")
        #expect(note.displayLabel == "Button \u{201C}Save Plan\u{201D}")
        #expect(note.aiLocationString.hasSuffix("AXGroup > AXButton[description=\"Save Plan\"]"))
    }

    // MARK: What the agent gets

    @Test func searchPatternsUseTheDescription() {
        let patterns = swiftUIButton().searchPatterns
        #expect(patterns.contains("Button\\(\"Save Plan\"\\)"))
        #expect(patterns.contains("Text\\(\"Save Plan\"\\)"))
        #expect(patterns.contains("accessibilityLabel\\(\"Save Plan\"\\)"))
        #expect(addNote().searchPatterns == patterns)
    }

    @Test func titledElementsKeepTheirPatterns() {
        let patterns = SearchPatternGenerator.patterns(identifier: nil, title: "Save", description: "Saves the plan", role: "AXButton")
        #expect(patterns == ["Text\\(\"Save\"\\)", "Button\\(\"Save\"\\)", "AXButton.*Save"])
        #expect(SearchPatternGenerator.patterns(identifier: nil, title: nil, role: "AXButton").isEmpty)
    }

    @Test func agentSeesNameAndPatternsInListNotes() throws {
        addNote()
        let request: JSONValue = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": "list_notes", "arguments": [:]]]
        let response = try #require(handler.handle(message: request))
        guard case .array(let notes)? = response["result"]?["structuredContent"]?["notes"] else {
            Issue.record("list_notes returned no notes")
            return
        }
        let note = try #require(notes.first)

        #expect(note["screenText"]?["description"] == "Save Plan")
        #expect(note["screenText"]?["title"] == .null)
        guard case .array(let patterns)? = note["element"]?["searchPatterns"] else {
            Issue.record("the note has no search patterns")
            return
        }
        #expect(patterns.contains(.string("Button\\(\"Save Plan\"\\)")))
    }

    @Test func copiedFeedbackNamesASwiftUIButton() {
        let markdown = FeedbackOutputGenerator().generateMarkdown(
            annotations: [addNote()],
            appName: "Weekend Planner",
            bundleIdentifier: "com.example.planner",
            windowTitle: "Weekend Planner",
            settings: LoupeSettings()
        )
        #expect(markdown.contains("Save Plan"))
    }

    // MARK: Notes saved before 2.0

    @Test func olderNotesWithoutADescriptionStillLoad() throws {
        let data = try JSONEncoder().encode(addNote())
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "elementDescription")
        let older = try JSONDecoder().decode(Annotation.self, from: JSONSerialization.data(withJSONObject: json))

        #expect(older.elementDescription == nil)
        #expect(older.displayLabel == "Button")
    }

    // MARK: Note window stays above the toolbar

    @Test func noteWindowSitsAboveTheToolbar() {
        let panel = AnnotationPopoverController.makePanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 200))
        #expect(panel.level == AnnotationPopoverController.panelLevel)
        #expect(panel.level.rawValue > FloatingToolbarWindowController.windowLevel.rawValue)
    }
}
