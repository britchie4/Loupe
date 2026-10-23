import Foundation
import Testing
@testable import LoupeFeature

/// Tests for deciding whether the target app is the window a click would hit.
/// Each case lists the windows a click would hit at one point, from the top down.
struct TargetWindowFrontmostTests {

    private let targetPid: pid_t = 100
    private let loupePid: pid_t = 200
    private let overlay = 10

    private func isFrontmost(_ stack: [(number: Int, owner: WindowOwner?)]) -> Bool {
        OverlayWindowController.isTargetWindowFrontmost(
            targetPid: targetPid,
            loupePid: loupePid,
            overlayWindowNumber: overlay,
            windowBelow: { below in
                // Return the window under `below` (or the top one for 0), 0 when none is left
                guard let index = below == 0 ? -1 : stack.firstIndex(where: { $0.number == below }) else { return 0 }
                return index + 1 < stack.count ? stack[index + 1].number : 0
            },
            ownerOf: { number in stack.first(where: { $0.number == number })?.owner ?? nil }
        )
    }

    private var target: WindowOwner { WindowOwner(pid: targetPid, name: "Target") }
    private var loupe: WindowOwner { WindowOwner(pid: loupePid, name: "Loupe") }

    @Test func targetDirectlyUnderOverlayIsFrontmost() {
        #expect(isFrontmost([(overlay, loupe), (20, target)]))
    }

    @Test func otherAppWindowCoveringTargetBlocks() {
        #expect(!isFrontmost([(overlay, loupe), (30, WindowOwner(pid: 300, name: "Finder")), (20, target)]))
    }

    @Test func clickableWindowAboveOverlayBlocks() {
        #expect(!isFrontmost([(40, WindowOwner(pid: 300, name: "Panel")), (overlay, loupe), (20, target)]))
    }

    @Test func interactiveLoupeWindowBlocks() {
        // e.g. the floating toolbar or an annotation popover
        #expect(!isFrontmost([(50, loupe), (overlay, loupe), (20, target)]))
    }

    @Test func screenshotUtilityWindowsAreIgnored() {
        #expect(isFrontmost([(60, WindowOwner(pid: 400, name: "screencaptureui")), (overlay, loupe), (20, target)]))
    }

    @Test func unknownOwnerIsLookedThrough() {
        #expect(isFrontmost([(70, nil), (overlay, loupe), (20, target)]))
    }

    @Test func noWindowAtPointIsNotFrontmost() {
        #expect(!isFrontmost([]))
        #expect(!isFrontmost([(overlay, loupe)]))
    }
}
