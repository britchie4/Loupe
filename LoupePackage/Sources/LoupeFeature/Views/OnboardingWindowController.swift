import AppKit
import SwiftUI

/// Manages the setup window: it asks for accessibility permission, then offers a short
/// hands-on practice. The same window can be reopened later for the practice alone.
/// Uses a normal-level NSWindow (not floating) so the native macOS
/// permission dialog can appear above it naturally.
@MainActor
public final class OnboardingWindowController {

    private var window: NSWindow?
    private var permissionCheckTimer: Timer?
    private var closeObserver: NSObjectProtocol?
    private var onComplete: (() -> Void)?
    /// True from the moment the window starts closing on purpose, so the close isn't handled twice
    private var isFinishing = false
    private let state = OnboardingState()

    public init() {}

    /// The practice that runs in this window. Agent Link's tools reach the practice note through it.
    public var practice: PracticeSession { state.practice }

    /// Where the connect step turns Agent Link on
    public var settings: LoupeSettings? {
        get { state.settings }
        set { state.settings = newValue }
    }

    // MARK: - Public API

    /// Show the setup window for first-run permission.
    /// - Parameter onComplete: Called once setup is over (practice finished, skipped, or the
    ///   window closed after permission was granted).
    public func show(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        state.isFirstRun = true
        state.phase = .requestingPermission
        state.practice.reset()
        presentWindow()
        startPermissionPolling()
    }

    /// Open the practice by itself, for someone who already finished setup.
    /// If setup is on screen already, that window just comes forward.
    public func showPractice() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // Setup is still waiting for permission behind a closed window: bring that back instead
        if permissionCheckTimer != nil {
            presentWindow()
            return
        }
        onComplete = nil
        state.isFirstRun = false
        state.practice.reset()
        state.phase = phaseBeforePractice
        presentWindow()
    }

    /// Dismiss the setup window immediately (e.g., on app termination).
    public func dismiss() {
        stopPermissionPolling()
        isFinishing = true
        tearDownWindow()
        state.practice.reset()
    }

    // MARK: - Window

    private func presentWindow() {
        tearDownWindow()
        isFinishing = false
        state.practice.isSetupOnScreen = true

        let contentView = OnboardingView(
            state: state,
            onGrantAccess: { [weak self] in
                self?.requestPermission()
            },
            onOpenSettings: { [weak self] in
                self?.openSystemSettings()
            },
            onStartPractice: { [weak self] in
                self?.startPractice()
            },
            onBeginPractice: { [weak self] in
                self?.beginPractice()
            },
            onSkip: { [weak self] in
                self?.fadeOutAndComplete()
            },
            onPracticeFinished: { [weak self] in
                self?.fadeOutAndComplete()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: contentView)
        window.center()

        // Closing the window with its red button counts as skipping
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // Handled right away, not on a later turn of the run loop: Loupe quits when its
            // last window closes, so the toolbar has to be up before this window is gone.
            MainActor.assumeIsolated {
                self?.windowClosedByUser()
            }
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// - Parameter close: false when the window is already closing itself
    private func tearDownWindow(close: Bool = true) {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil
        if close { window?.close() }
        window = nil
        state.practice.isSetupOnScreen = false
    }

    /// The person closed the window themselves. While permission is still missing, setup
    /// keeps waiting for it (as before). After that, closing means "skip": carry on into the app.
    private func windowClosedByUser() {
        guard !isFinishing, state.phase != .requestingPermission else { return }
        isFinishing = true
        finish(closeWindow: false)
    }

    // MARK: - Permission Handling

    private func requestPermission() {
        // Trigger the native macOS accessibility permission dialog.
        // Using the string literal avoids a Swift 6 concurrency warning
        // on the C global kAXTrustedCheckOptionPrompt.
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Practice

    /// Where "Try It" leads: straight to the practice when an agent is already connected
    /// (or there is nowhere to connect one), otherwise to the optional connect step first
    private var phaseBeforePractice: OnboardingPhase {
        guard state.settings != nil, state.practice.connectedAgent() == nil else { return .practicing }
        return .connectingAgent
    }

    private func startPractice() {
        state.practice.reset()
        withAnimation(.easeOut(duration: 0.3)) {
            state.phase = phaseBeforePractice
        }
    }

    private func beginPractice() {
        state.practice.reset()
        withAnimation(.easeOut(duration: 0.3)) {
            state.phase = .practicing
        }
    }

    // MARK: - Polling

    private func startPermissionPolling() {
        stopPermissionPolling()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermission()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    private func checkPermission() {
        guard permissionCheckTimer != nil, AXIsProcessTrusted() else { return }

        stopPermissionPolling()

        // The person closed the setup window while granting access: don't bring it back,
        // just start Loupe.
        guard let window, window.isVisible else {
            isFinishing = true
            finish()
            return
        }

        // Transition to granted phase with animation
        withAnimation(.easeOut(duration: 0.4)) {
            state.phase = .permissionGranted
        }

        // Permission is usually granted while System Settings is in front. Bring setup
        // forward so the offer to practice (and Skip) is the next thing the person sees,
        // instead of leaving it hidden behind System Settings.
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Finishing

    private func fadeOutAndComplete() {
        guard !isFinishing else { return }
        isFinishing = true

        guard let window else {
            finish()
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.finish()
            }
        })
    }

    /// Close the window, throw the practice away, and tell the app setup is over (once)
    private func finish(closeWindow: Bool = true) {
        stopPermissionPolling()
        tearDownWindow(close: closeWindow)
        state.practice.reset()
        let completion = onComplete
        onComplete = nil
        completion?()
    }
}
