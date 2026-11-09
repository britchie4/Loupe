import Testing
import AppKit
@testable import LoupeFeature

/// The toolbar stays on the display it started on when it grows near a display edge
@MainActor
struct ToolbarPlacementTests {

    // A 27-inch monitor with a laptop screen to its right, lower down
    private let monitor = NSRect(x: 0, y: 0, width: 2304, height: 1296)
    private let laptop = NSRect(x: 2304, y: -246, width: 1470, height: 956)

    @Test func collapsedToolbarInMonitorCornerBelongsToMonitor() {
        let collapsed = NSRect(x: 2226, y: 34, width: 58, height: 50)
        #expect(FloatingToolbarWindowController.indexOfScreen(containing: collapsed, screenFrames: [monitor, laptop]) == 0)
    }

    @Test func toolbarMostlyOnLaptopBelongsToLaptop() {
        let grown = NSRect(x: 2226, y: 34, width: 275, height: 52)
        #expect(FloatingToolbarWindowController.indexOfScreen(containing: grown, screenFrames: [monitor, laptop]) == 1)
    }

    @Test func offScreenToolbarFallsBackToLargestOverlap() {
        let straddling = NSRect(x: 2290, y: 1280, width: 58, height: 50)
        #expect(FloatingToolbarWindowController.indexOfScreen(containing: straddling, screenFrames: [monitor, laptop]) == 0)
        #expect(FloatingToolbarWindowController.indexOfScreen(containing: .zero, screenFrames: []) == nil)
    }
}
