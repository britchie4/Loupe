import AppKit
import Combine
import SwiftUI

/// App delegate that manages the toolbar-only app lifecycle.
/// This replaces the traditional WindowGroup approach to avoid creating a main window.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    /// The central coordinator for the app
    public let coordinator = AppCoordinator()

    /// Menu bar status item for quick access
    private var statusItem: NSStatusItem?

    /// Coral dot shown over the menu bar glyph when a note has a question for the person
    private var statusDot: StatusDotView?
    private var questionsSubscription: AnyCancellable?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure as agent app (no dock icon initially - we'll show dock presence)
        // Actually, we want dock presence, so we leave activation policy as regular

        // Set up menu bar icon
        setupMenuBarIcon()

        #if DEBUG
        // Development only: `-LoupePracticePreview YES` opens the practice by itself, without
        // asking for Accessibility access or starting the toolbar, so its look can be checked
        // in a real window. `-LoupePreviewAppearance light` (or `dark`) picks the appearance.
        if UserDefaults.standard.bool(forKey: "LoupePracticePreview") {
            switch UserDefaults.standard.string(forKey: "LoupePreviewAppearance") {
            case "light": NSApp.appearance = NSAppearance(named: .aqua)
            case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
            default: break
            }
            coordinator.showPractice()
            return
        }
        #endif

        // Check accessibility permission and show appropriate UI
        coordinator.inspector.checkAccessibilityPermission()

        if !coordinator.inspector.isAccessibilityEnabled {
            // Show permission panel on first launch or if permission revoked
            coordinator.showOnboarding()
        } else {
            // Permission granted - start normal flow
            coordinator.startApp()
        }
    }

    // MARK: - Menu Bar Setup

    private func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // A one-colour lens that follows the menu bar, plus a coral dot when a note needs the person
        updateMenuBarIcon(questionsForYou: coordinator.annotationStore.questionsForYou)
        questionsSubscription = coordinator.annotationStore.$questionsForYou
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] count in self?.updateMenuBarIcon(questionsForYou: count) }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Loupe", action: #selector(showLoupe), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Practice Using Loupe", action: #selector(showPractice), keyEquivalent: ""))
        menu.addItem(coordinator.updater.makeMenuItem())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Loupe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func updateMenuBarIcon(questionsForYou count: Int) {
        guard let button = statusItem?.button else { return }
        let needsYou = count > 0
        button.image = MenuBarIcon.image(leavingRoomForDot: needsYou)
        let description = needsYou
            ? (count == 1 ? "Loupe: a note has a question for you" : "Loupe: \(count) notes have questions for you")
            : "Loupe"
        button.toolTip = description
        button.setAccessibilityLabel(description)

        guard needsYou else {
            statusDot?.removeFromSuperview()
            statusDot = nil
            return
        }
        button.layoutSubtreeIfNeeded()
        let bounds = button.bounds
        let size = MenuBarIcon.size
        let imageLeft = (bounds.width - size.width) / 2
        let imageTop = (bounds.height - size.height) / 2
        let r = MenuBarIcon.dotRadius
        let centerFromTop = imageTop + MenuBarIcon.dotCenter.y
        let y = button.isFlipped ? centerFromTop - r : bounds.height - centerFromTop - r
        let frame = NSRect(x: imageLeft + MenuBarIcon.dotCenter.x - r, y: y, width: r * 2, height: r * 2)
        if let statusDot {
            statusDot.frame = frame
        } else {
            let dot = StatusDotView(frame: frame)
            button.addSubview(dot)
            statusDot = dot
        }
    }

    @objc private func showPractice() {
        coordinator.showPractice()
    }

    @objc private func showLoupe() {
        coordinator.floatingToolbar.show()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Terminate when the toolbar is closed
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        // Cleanup if needed
        coordinator.cleanup()
    }

    public func applicationDidBecomeActive(_ notification: Notification) {
        // Ensure toolbar is visible when app becomes active
        coordinator.ensureToolbarVisible()
    }
}
