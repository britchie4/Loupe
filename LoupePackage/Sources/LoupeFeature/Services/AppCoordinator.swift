import AppKit
import SwiftUI

/// Coordinates global app state and controllers
@MainActor
@Observable
public final class AppCoordinator {

    // MARK: - UserDefaults Keys

    private enum DefaultsKeys {
        static let lastSelectedAppBundleID = "lastSelectedAppBundleID"
        static let hasShownPermissionPanel = "hasShownPermissionPanel"
    }

    // MARK: - Controllers

    public let floatingToolbar = FloatingToolbarWindowController()
    private let onboardingWindow = OnboardingWindowController()
    private let toolbarTipController = ToolbarTipWindowController()

    // MARK: - Shared State

    /// The accessibility inspector shared across the app
    public let inspector = AccessibilityInspector()

    /// The currently selected target app
    public var selectedApp: TargetApp? {
        didSet {
            annotationStore.selectApp(key: selectedApp.map {
                AnnotationStore.appKey(bundleIdentifier: $0.bundleIdentifier, appName: $0.name)
            })

            if let app = selectedApp {
                inspector.setTargetApp(app)
                // Persist the selection
                UserDefaults.standard.set(app.bundleIdentifier, forKey: DefaultsKeys.lastSelectedAppBundleID)
            } else {
                // Keep the remembered app, so it comes back on its own when it relaunches
                inspector.clearTargetApp()
            }

            // If toolbar is expanded, restart inspection on the new app
            if floatingToolbar.isExpanded {
                stopInspection()
                if selectedApp != nil {
                    startInspection()
                }
            }

            // Update toolbar with new app selection
            floatingToolbar.updateSelectedApp(selectedApp)
            publishAppList()
        }
    }

    /// Whether inspection mode is active (derived from toolbar expanded state)
    public var isInspecting: Bool {
        floatingToolbar.isExpanded && overlayController != nil
    }

    /// The overlay controller (created when inspection starts)
    public private(set) var overlayController: OverlayWindowController?

    /// Persistent annotation store (survives across inspection sessions)
    public let annotationStore = AnnotationStore()

    /// Checks for and installs new Loupe releases
    public let updater = SoftwareUpdater()

    /// Connects Loupe to coding agents (off until the user turns it on)
    public let agentLink = AgentLinkServer.shared
    private var agentLinkObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    /// Apps the person switched to, most recent first, so the picker can list them first
    private var recentAppIDs: [pid_t] = []

    // MARK: - Initialization

    public init() {
        setupCallbacks()
    }

    // MARK: - Setup

    private func setupCallbacks() {
        // Floating toolbar expand/collapse callbacks
        floatingToolbar.onExpand = { [weak self] in
            self?.startInspection()
        }

        floatingToolbar.onCollapse = { [weak self] in
            self?.stopInspectionAndReleaseFocus()
        }

        floatingToolbar.onCopyFeedback = { [weak self] in
            self?.copyFeedbackToClipboard()
        }

        floatingToolbar.onClearAnnotations = { [weak self] in
            self?.clearAnnotations()
        }

        floatingToolbar.onAppSelected = { [weak self] app in
            self?.selectedApp = app
        }

        floatingToolbar.onRefreshApps = { [weak self] in
            self?.refreshApps()
        }

        floatingToolbar.onCheckForUpdates = { [weak self] in
            self?.updater.checkForUpdates()
        }
    }

    // MARK: - Inspection Control

    private func startInspection() {
        guard let app = selectedApp else {
            // No app selected: stay open so the person can pick one from the toolbar
            return
        }

        // Create overlay
        let controller = OverlayWindowController(
            inspector: inspector,
            targetApp: app,
            annotationStore: annotationStore,
            settings: floatingToolbar.settings
        )

        // Register the toolbar window as an exclusion zone so mouse events
        // over the toolbar are passed through instead of being consumed
        if let toolbarWindow = floatingToolbar.window {
            controller.addExclusionWindow(toolbarWindow)
        }

        // Wire up Escape key to collapse the toolbar
        controller.onRequestCollapse = { [weak self] in
            self?.floatingToolbar.isExpanded = false
        }

        controller.isInspectionActive = true
        controller.showWindow(nil)
        overlayController = controller

        // Connect toolbar to annotation store for badge updates
        floatingToolbar.setAnnotationStore(annotationStore)

        // Bring target app forward AFTER overlay is shown
        // (showWindow can steal focus, so activate must come last)
        if let runningApp = NSRunningApplication(processIdentifier: app.id) {
            runningApp.activate(options: [])
        }

        // Force badge refresh after window is fully shown (fixes timing issue)
        DispatchQueue.main.async {
            controller.refreshAnnotationBadges()
        }
    }

    private func stopInspection() {
        overlayController?.isInspectionActive = false
        overlayController?.close()
        overlayController = nil
    }

    /// Stop inspection when user collapses the toolbar.
    /// Target app already has focus (it was activated on expand).
    private func stopInspectionAndReleaseFocus() {
        stopInspection()
    }

    // MARK: - Services

    private let feedbackGenerator = FeedbackOutputGenerator()
    private let richClipboard = RichClipboard()

    // MARK: - Actions

    /// Copy all annotations as markdown to clipboard
    public func copyFeedbackToClipboard() {
        guard let app = selectedApp else { return }

        let settings = floatingToolbar.settings

        // Generate markdown with selected settings
        let markdown = feedbackGenerator.generateMarkdown(
            // Done and dismissed notes need no more work, so leave them out
            annotations: annotationStore.annotations.filter { $0.status.isOpen },
            appName: app.name,
            bundleIdentifier: app.bundleIdentifier,
            windowTitle: inspector.getTargetWindowTitle(),
            settings: settings
        )

        // Copy to clipboard
        richClipboard.copyText(markdown)
    }

    /// Clear all annotations
    public func clearAnnotations() {
        annotationStore.clear()
        floatingToolbar.refreshContent()
    }

    // MARK: - Lifecycle

    /// Show the floating toolbar
    public func showToolbar() {
        floatingToolbar.show()
    }

    /// Refresh running apps list
    public func refreshApps() {
        inspector.refreshRunningApps()
        // Update toolbar with the new app list
        publishAppList()
        reconcileSelectedApp()
    }

    /// Keep the selection pointing at a running app: follow it when it relaunches,
    /// let go when it quits, and pick the remembered app back up when it returns.
    private func reconcileSelectedApp() {
        let apps = inspector.runningApps
        guard let current = selectedApp else {
            restoreLastSelectedApp()
            return
        }
        if apps.contains(current) { return }

        if let bundleID = current.bundleIdentifier,
           let relaunched = apps.first(where: { $0.bundleIdentifier == bundleID }) {
            selectedApp = relaunched
        } else {
            selectedApp = nil
        }
    }

    /// Give the toolbar the open apps: the selected one first, then the most recently used
    private func publishAppList() {
        floatingToolbar.updateAvailableApps(AppListOrdering.ordered(
            inspector.runningApps,
            selectedID: selectedApp?.id,
            recentIDs: recentAppIDs
        ))
    }

    /// Refresh the app list whenever an app opens or quits, and note which app was used last
    private func observeRunningApps() {
        guard workspaceObservers.isEmpty else { return }
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            recentAppIDs = [frontmost.processIdentifier]
        }
        let center = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshApps()
                }
            }
        }
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, let pid, pid != ProcessInfo.processInfo.processIdentifier else { return }
                self.recentAppIDs = AppListOrdering.noting(pid, in: self.recentAppIDs)
                self.publishAppList()
            }
        })
    }

    // MARK: - App Lifecycle (called from AppDelegate)

    /// Setup's hands-on practice. Agent Link's tools reach the practice note through it.
    public var practiceSession: PracticeSession { onboardingWindow.practice }

    /// Setup can connect an agent before the app proper starts, so Agent Link is made ready here too
    private func prepareSetup() {
        configureAgentLink()
        onboardingWindow.settings = floatingToolbar.settings
        practiceSession.connectedAgent = { [agentLink] in
            guard agentLink.status == .listening, let name = agentLink.connectedAgents.first else { return nil }
            return PracticeCopy.displayName(forAgent: name)
        }
    }

    /// Show the onboarding window for first-time permission setup
    public func showOnboarding() {
        prepareSetup()
        onboardingWindow.show { [weak self] in
            self?.startApp()
        }
    }

    /// Open the hands-on practice by itself (from the menu bar), for people who are already set up
    public func showPractice() {
        prepareSetup()
        onboardingWindow.showPractice()
    }

    /// Start the app after permission is granted
    public func startApp() {
        // Refresh apps and restore last selection
        refreshApps()
        restoreLastSelectedApp()
        observeRunningApps()
        configureAgentLink()

        // Show the floating toolbar with a fade-in
        if let toolbarWindow = floatingToolbar.window {
            toolbarWindow.alphaValue = 0
        }
        showToolbar()
        if let toolbarWindow = floatingToolbar.window {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                toolbarWindow.animator().alphaValue = 1
            }
        }

        // Show toolbar tooltip after fade-in completes (0.4s animation + 0.4s extra delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, let toolbarWindow = self.floatingToolbar.window else { return }
            self.toolbarTipController.showIfNeeded(relativeTo: toolbarWindow)
        }

        // Update toolbar with initial state
        publishAppList()
        floatingToolbar.updateSelectedApp(selectedApp)
    }

    // MARK: - Agent Link

    /// Give agents their tools, and follow the Agent Link setting
    private func configureAgentLink() {
        agentLink.tools = AgentLinkTools.make(coordinator: self)
        agentLink.setEnabled(floatingToolbar.settings.agentLinkEnabled)

        guard agentLinkObserver == nil else { return }
        agentLinkObserver = NotificationCenter.default.addObserver(
            forName: LoupeSettings.agentLinkEnabledDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.agentLink.setEnabled(self.floatingToolbar.settings.agentLinkEnabled)
            }
        }
    }

    /// Restore the previously selected app if it's still running
    private func restoreLastSelectedApp() {
        guard let lastBundleID = UserDefaults.standard.string(forKey: DefaultsKeys.lastSelectedAppBundleID) else {
            return
        }

        // Find the app in running apps
        if let matchingApp = inspector.runningApps.first(where: { $0.bundleIdentifier == lastBundleID }) {
            selectedApp = matchingApp
        }
    }

    /// Ensure toolbar is visible (called when app becomes active)
    public func ensureToolbarVisible() {
        if !floatingToolbar.isVisible {
            floatingToolbar.show()
        }
    }

    /// Cleanup before app terminates
    public func cleanup() {
        agentLink.stop()
        stopInspection()
        onboardingWindow.dismiss()
        toolbarTipController.dismiss()
    }
}
