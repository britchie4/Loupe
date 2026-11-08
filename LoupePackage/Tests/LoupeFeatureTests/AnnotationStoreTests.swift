import Testing
import Foundation
import ApplicationServices
@testable import LoupeFeature

@MainActor
struct AnnotationStoreTests {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LoupeTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Notes.json")
    }

    private func element(title: String, windowFrame: CGRect? = CGRect(x: 100, y: 100, width: 800, height: 600)) -> AXElementInfo {
        AXElementInfo(
            role: "AXButton",
            identifier: nil,
            title: title,
            value: nil,
            frame: CGRect(x: 120, y: 140, width: 60, height: 24),
            hierarchyPath: [HierarchyNode(role: "AXWindow", title: "Main"), HierarchyNode(role: "AXButton", title: title)],
            element: AXUIElementCreateSystemWide(),
            siblings: [SiblingInfo(role: "AXButton", identifier: nil, title: "Cancel", relativePosition: .before)],
            windowFrame: windowFrame
        )
    }

    @Test func notesSurviveRelaunch() throws {
        let url = tempURL()
        let store = AnnotationStore(fileURL: url)
        store.selectApp(key: "com.example.notes")
        let note = store.addAnnotation(text: "Make it blue", for: element(title: "Save"), appName: "Notes", bundleIdentifier: "com.example.notes")
        store.setStatus(id: note.id, to: .done, message: "Changed the tint")

        let reopened = AnnotationStore(fileURL: url)
        reopened.selectApp(key: "com.example.notes")

        let saved = try #require(reopened.annotations.first)
        #expect(saved.id == note.id)
        #expect(saved.text == "Make it blue")
        #expect(saved.status == .done)
        #expect(saved.replies.map(\.text) == ["Changed the tint"])
        #expect(saved.hierarchyPath.count == 2)
        #expect(saved.siblings.first?.title == "Cancel")
    }

    @Test func notesAreGroupedPerApp() {
        let store = AnnotationStore(fileURL: nil)
        store.selectApp(key: "com.example.a")
        _ = store.addAnnotation(text: "A1", for: element(title: "One"), appName: "A", bundleIdentifier: "com.example.a")
        _ = store.addAnnotation(text: "A2", for: element(title: "Two"), appName: "A", bundleIdentifier: "com.example.a")
        _ = store.addAnnotation(text: "B1", for: element(title: "Three"), appName: "B", bundleIdentifier: "com.example.b")

        #expect(store.annotations.map(\.text) == ["A1", "A2"])

        store.selectApp(key: "com.example.b")
        #expect(store.annotations.map(\.text) == ["B1"])
        // Badge numbers count within each app
        #expect(store.annotations.first?.badgeNumber == 1)
        #expect(store.appKeys == ["com.example.a", "com.example.b"])
    }

    @Test func clearOnlyAffectsCurrentApp() {
        let store = AnnotationStore(fileURL: nil)
        store.selectApp(key: "com.example.a")
        _ = store.addAnnotation(text: "A1", for: element(title: "One"), appName: "A", bundleIdentifier: "com.example.a")
        _ = store.addAnnotation(text: "B1", for: element(title: "Two"), appName: "B", bundleIdentifier: "com.example.b")

        store.clear()

        #expect(store.annotations.isEmpty)
        #expect(store.notes(forAppKey: "com.example.b").count == 1)
    }

    @Test func editAndDeleteKeepIdentity() throws {
        let store = AnnotationStore(fileURL: nil)
        store.selectApp(key: "com.example.a")
        let first = store.addAnnotation(text: "Old", for: element(title: "One"), appName: "A", bundleIdentifier: "com.example.a")
        let second = store.addAnnotation(text: "Other", for: element(title: "Two"), appName: "A", bundleIdentifier: "com.example.a")

        store.updateAnnotation(id: first.id, text: "New")
        #expect(store.note(id: first.id)?.text == "New")
        #expect(store.note(id: first.id)?.badgeNumber == 1)

        store.removeAnnotation(id: first.id)
        #expect(store.annotations.map(\.id) == [second.id])

        // The next note continues numbering after the highest badge
        let third = store.addAnnotation(text: "Third", for: element(title: "Three"), appName: "A", bundleIdentifier: "com.example.a")
        #expect(third.badgeNumber == 3)
    }

    @Test func repliesAndStatusChanges() {
        let store = AnnotationStore(fileURL: nil)
        store.selectApp(key: "com.example.a")
        let note = store.addAnnotation(text: "Fix", for: element(title: "One"), appName: "A", bundleIdentifier: "com.example.a")
        #expect(note.status == .pending)

        store.setStatus(id: note.id, to: .seen)
        store.addReply(id: note.id, text: "Which one?", author: .agent)
        store.setStatus(id: note.id, to: .dismissed, message: "   ")

        let updated = store.note(id: note.id)
        #expect(updated?.status == .dismissed)
        // A blank message adds no reply
        #expect(updated?.replies.map(\.text) == ["Which one?"])
        #expect(updated?.status.isOpen == false)
    }

    @Test func unreadableFileIsMovedAside() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        let store = AnnotationStore(fileURL: url)
        #expect(store.appKeys.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("unreadable.json").path))
    }

    @Test func badgesFollowWindowMoves() {
        let note = Annotation(
            badgeNumber: 1,
            text: "x",
            elementFrame: CGRect(x: 120, y: 140, width: 60, height: 24),
            elementRole: "AXButton",
            elementIdentifier: nil,
            windowFrame: CGRect(x: 100, y: 100, width: 800, height: 600)
        )
        let moved = note.elementFrame(currentWindowFrame: CGRect(x: 300, y: 50, width: 800, height: 600))
        #expect(moved.origin == CGPoint(x: 320, y: 90))
        #expect(note.elementFrame(currentWindowFrame: nil) == note.elementFrame)
    }
}
