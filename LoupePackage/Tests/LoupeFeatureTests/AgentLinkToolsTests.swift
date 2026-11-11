import Testing
import Foundation
import ApplicationServices
@testable import LoupeFeature

@MainActor
struct AgentLinkToolsTests {

    private let store = AnnotationStore(fileURL: nil)
    private let handler: MCPHandler

    init() {
        let inspector = AccessibilityInspector()
        let context = AgentLinkTools.Context(store: store, inspector: inspector, selectedApp: { nil }, isInspecting: { false })
        handler = MCPHandler(tools: AgentLinkTools.make(context: context))
        store.selectApp(key: "com.example.app")
    }

    @discardableResult
    private func addNote(_ text: String, title: String, app: String = "com.example.app") -> Annotation {
        store.addAnnotation(
            text: text,
            for: AXElementInfo(
                role: "AXButton",
                identifier: "saveButton",
                title: title,
                value: nil,
                frame: CGRect(x: 10, y: 20, width: 60, height: 24),
                hierarchyPath: [HierarchyNode(role: "AXWindow", title: "Main"), HierarchyNode(role: "AXButton", title: title)],
                element: AXUIElementCreateSystemWide()
            ),
            windowTitle: "Main",
            appName: "Example",
            bundleIdentifier: app
        )
    }

    private func call(_ name: String, _ arguments: JSONValue = [:]) throws -> (result: JSONValue, isError: Bool) {
        let request: JSONValue = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": .string(name), "arguments": arguments]]
        let response = try #require(handler.handle(message: request))
        let result = try #require(response["result"])
        return (try #require(result["structuredContent"]), result["isError"]?.boolValue ?? false)
    }

    @Test func listsOpenNotesForSelectedApp() throws {
        addNote("Make it blue", title: "Save")
        let done = addNote("Rename", title: "Cancel")
        store.setStatus(id: done.id, to: .done)
        addNote("Other app", title: "Go", app: "com.example.other")

        let open = try call("list_notes")
        #expect(open.result["notes"]?.arrayCount == 1)
        let first = open.result["notes"]?.firstItem
        #expect(first?["request"] == "Make it blue")
        #expect(first?["element"]?["identifier"] == "saveButton")
        // Screen text is kept apart and flagged as data
        #expect(first?["screenText"]?["title"] == "Save")
        #expect(open.result["notice"]?.stringValue == AgentLinkTools.screenTextNotice)

        #expect(try call("list_notes", ["status": "all"]).result["notes"]?.arrayCount == 2)
        #expect(try call("list_notes", ["app": "com.example.other"]).result["notes"]?.arrayCount == 1)
    }

    @Test func updatesStatusWithMessageByNumber() throws {
        let note = addNote("Make it blue", title: "Save")

        let result = try call("update_note", ["number": 1, "status": "done", "message": "Changed the tint in HeaderView.swift"])
        #expect(result.isError == false)
        #expect(result.result["note"]?["status"] == "done")

        let saved = try #require(store.note(id: note.id))
        #expect(saved.status == .done)
        #expect(saved.replies.first?.author == .agent)
        #expect(saved.replies.first?.text == "Changed the tint in HeaderView.swift")
    }

    @Test func repliesByIdKeepStatus() throws {
        let note = addNote("Fix", title: "Save")
        let result = try call("reply_to_note", ["id": .string(note.id.uuidString), "text": "Which Save button?"])
        #expect(result.isError == false)
        #expect(store.note(id: note.id)?.status == .pending)
        #expect(store.note(id: note.id)?.replies.map(\.text) == ["Which Save button?"])
    }

    @Test func rejectsBadRequests() throws {
        addNote("Fix", title: "Save")
        #expect(try call("update_note", ["number": 1, "status": "pending"]).isError)
        #expect(try call("update_note", ["number": 9, "status": "done"]).isError)
        #expect(try call("reply_to_note", ["number": 1, "text": "  "]).isError)
        #expect(try call("get_note", ["id": "not-a-uuid"]).isError)
        // Looking at the app needs an app selected in Loupe
        #expect(try call("find_elements", ["query": "Save"]).isError)
        #expect(try call("inspect_element", ["x": 10, "y": 10]).isError)
    }

    @Test func getNoteAndStatus() throws {
        let note = addNote("Fix", title: "Save")
        let detail = try call("get_note", ["id": .string(note.id.uuidString)])
        #expect(detail.result["note"]?["number"] == 1)

        let status = try call("get_status")
        #expect(status.result["openNotes"] == 1)
        #expect(status.result["appsWithNotes"]?.arrayCount == 1)
        #expect(status.result["targetApp"] == .null)
    }

    @Test func listOffersReadOnlyHints() throws {
        let list = try #require(handler.handle(message: ["jsonrpc": "2.0", "id": 1, "method": "tools/list"]))
        guard case .array(let tools)? = list["result"]?["tools"] else {
            Issue.record("No tools listed")
            return
        }
        let readOnly = Dictionary(uniqueKeysWithValues: tools.compactMap { tool -> (String, Bool)? in
            guard let name = tool["name"]?.stringValue, let hint = tool["annotations"]?["readOnlyHint"]?.boolValue else { return nil }
            return (name, hint)
        })
        #expect(readOnly == [
            "get_status": true, "list_notes": true, "get_note": true, "inspect_element": true, "find_elements": true,
            "update_note": false, "reply_to_note": false, "edit_practice_app": false,
        ])
    }
}

private extension JSONValue {
    var arrayCount: Int? {
        if case .array(let items) = self { return items.count }
        return nil
    }

    var firstItem: JSONValue? {
        if case .array(let items) = self { return items.first }
        return nil
    }
}
