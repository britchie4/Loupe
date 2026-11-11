import Testing
import Foundation
@testable import LoupeFeature

/// Several notes on one element each keep a visible badge that opens its own note
struct BadgePlacementTests {

    @Test func aSingleBadgeStaysOnTheCorner() {
        let corner = CGPoint(x: 200, y: 50)
        #expect(OverlayWindowController.spreadBadgePositions([corner]) == [corner])
        #expect(OverlayWindowController.spreadBadgePositions([]).isEmpty)
    }

    @Test func notesOnOneElementSitSideBySideNewestOnTheCorner() {
        let corner = CGPoint(x: 200, y: 50)
        let spread = OverlayWindowController.spreadBadgePositions([corner, corner, corner])

        #expect(spread == [CGPoint(x: 168, y: 50), CGPoint(x: 184, y: 50), corner])
    }

    @Test func otherElementsAreLeftAlone() {
        let save = CGPoint(x: 200, y: 50)
        let checkbox = CGPoint(x: 80, y: 50)
        // Notes arrive oldest first, mixed across elements
        let spread = OverlayWindowController.spreadBadgePositions([save, checkbox, save])

        #expect(spread == [CGPoint(x: 184, y: 50), checkbox, save])
    }

    @Test func everyBadgeKeepsItsOwnClickTarget() {
        let corner = CGPoint(x: 200, y: 50)
        let spread = OverlayWindowController.spreadBadgePositions([corner, corner, corner, corner])

        // Each badge's centre lies outside every other badge's 20-point target
        for (index, position) in spread.enumerated() {
            for (other, otherPosition) in spread.enumerated() where other != index {
                #expect(abs(position.x - otherPosition.x) > 10)
            }
        }
    }
}
