import AppKit
import Sparkle

/// Wraps Sparkle's standard updater, which reads the update feed (SUFeedURL in Info.plist)
/// and installs signed releases. Sparkle asks the user once whether to check automatically,
/// then checks daily if they agree.
@MainActor
public final class SoftwareUpdater {

    private let controller: SPUStandardUpdaterController

    public init() {
        #if DEBUG
        // Debug builds have their own identity and should never replace themselves with a release
        let startUpdater = false
        #else
        let startUpdater = true
        #endif

        controller = SPUStandardUpdaterController(
            startingUpdater: startUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Check for updates now and show the result to the user
    public func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Menu item wired to Sparkle, which enables it only while a check can start
    public func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        item.target = controller
        return item
    }
}
