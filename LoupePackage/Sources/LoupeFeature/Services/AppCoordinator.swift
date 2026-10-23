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
            if let app = selectedApp {
                inspector.setTargetApp(app)
                // Persist the selection
                UserDefaults.standard.set(app.bundleIdentifier, forKey: DefaultsKeys.lastSelectedAppBundleID)
            } else {
                inspector.clearTargetApp()
                UserDefaults.standard.removeObject(forKey: DefaultsKeys.lastSelectedAppBundleID)
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
            // No app selected - collapse toolbar back
            floatingToolbar.isExpanded = false
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
            annotations: annotationStore.annotations,
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
        floatingToolbar.updateAvailableApps(inspector.runningApps)
    }

    // MARK: - App Lifecycle (called from AppDelegate)

    /// Show the onboarding window for first-time permission setup
    public func showOnboarding() {
        onboardingWindow.show { [weak self] in
            self?.startApp()
        }
    }

    /// Start the app after permission is granted
    public func startApp() {
        // Refresh apps and restore last selection
        refreshApps()
        restoreLastSelectedApp()

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
        floatingToolbar.updateAvailableApps(inspector.runningApps)
        floatingToolbar.updateSelectedApp(selectedApp)
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
        stopInspection()
        onboardingWindow.dismiss()
        toolbarTipController.dismiss()
    }
}
