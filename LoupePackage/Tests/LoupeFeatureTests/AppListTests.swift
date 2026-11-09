import Testing
import AppKit
@testable import LoupeFeature

/// The app picker's order and search, and where the toolbar icon is allowed to sit
@MainActor
struct AppListTests {

    private let apps = [
        TargetApp(id: 1, name: "Claude"),
        TargetApp(id: 2, name: "Finder"),
        TargetApp(id: 3, name: "TextEdit"),
        TargetApp(id: 4, name: "Spotify"),
        TargetApp(id: 5, name: "Font Book")
    ]

    @Test func selectedAppComesFirstThenRecentThenAlphabetical() {
        let ordered = AppListOrdering.ordered(apps, selectedID: 3, recentIDs: [4, 2, 3])
        #expect(ordered.map(\.name) == ["TextEdit", "Spotify", "Finder", "Claude", "Font Book"])
    }

    @Test func noSelectionOrRecentsIsAlphabetical() {
        let ordered = AppListOrdering.ordered(apps, selectedID: nil, recentIDs: [])
        #expect(ordered.map(\.name) == ["Claude", "Finder", "Font Book", "Spotify", "TextEdit"])
    }

    @Test func searchPutsNamesThatStartWithTheTextFirst() {
        #expect(AppListOrdering.filtered(apps, query: "te").map(\.name) == ["TextEdit"])
        // "Book" starts a word in "Font Book"; "o" only appears inside the others
        #expect(AppListOrdering.filtered(apps, query: "bo").map(\.name) == ["Font Book"])
        #expect(AppListOrdering.filtered(apps, query: "f").map(\.name) == ["Finder", "Font Book", "Spotify"])
        #expect(AppListOrdering.filtered(apps, query: "  ").count == apps.count)
        #expect(AppListOrdering.filtered(apps, query: "zzz").isEmpty)
    }

    @Test func usingAnAppMovesItToTheFront() {
        #expect(AppListOrdering.noting(3, in: [1, 2, 3]) == [3, 1, 2])
        #expect(AppListOrdering.noting(9, in: [1, 2], limit: 2) == [9, 1])
    }

    @Test func iconIsPulledBackInsideTheDisplay() {
        let display = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let offRight = NSRect(x: 980, y: 400, width: 58, height: 50)
        #expect(FloatingToolbarWindowController.clamped(offRight, into: display).maxX == 992)
        let inside = NSRect(x: 300, y: 300, width: 58, height: 50)
        #expect(FloatingToolbarWindowController.clamped(inside, into: display) == inside)
    }
}
