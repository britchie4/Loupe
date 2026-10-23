import AppKit
import Combine
import SwiftUI

/// Controller for the floating toolbar window
///
/// Architecture: This controller manages a floating toolbar that can expand/collapse.
/// The key challenge is coordinating NSWindow frame changes with SwiftUI content sizing.
///
/// Solution: We observe window frame changes (caused by SwiftUI's intrinsic sizing)
/// and adjust the window origin to keep the RIGHT edge anchored. This creates the
/// effect of the toolbar growing leftward when expanding.
@MainActor
public final class FloatingToolbarWindowController: NSWindowController, ObservableObject {

    // MARK: - Published State

    @Published public var isExpanded = false
    @Published public var showCopySuccess = false

    // MARK: - App Selection State

    @Published public var selectedApp: TargetApp?
    @Published public var availableApps: [TargetApp] = []

    // MARK: - Callbacks

    /// Called when toolbar expands (starts inspection)
    public var onExpand: (() -> Void)?
    /// Called when toolbar collapses (stops inspection, releases focus)
    public var onCollapse: (() -> Void)?
    public var onCopyFeedback: (() -> Void)?
    public var onClearAnnotations: (() -> Void)?
    public var onAppSelected: ((TargetApp?) -> Void)?
    public var onRefreshApps: (() -> Void)?
    public var onCheckForUpdates: (() -> Void)?

    // MARK: - Private State

    var annotationStore: AnnotationStore?
    private var hostingView: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()
    private var frameObserver: NSObjectProtocol?

    /// Tracks the right edge position to anchor during resize
    private var anchoredRightEdge: CGFloat?

    /// Published annotation count for reactive updates
    @Published private(set) var annotationCount: Int = 0

    /// Settings for output format and naming style
    public let settings = LoupeSettings()

    /// Whether the toolbar window is currently visible
    public var isVisible: Bool {
        window?.isVisible ?? false
    }

    // MARK: - Initialization

    public init() {
        // Create window - size will be determined by SwiftUI content
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 64, height: 64)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isMovableByWindowBackground = true

        super.init(window: window)

        setupContent()
        setupObservers()
        positionWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    nonisolated deinit {
        // NotificationCenter observers are automatically removed when the object is deallocated
        // with block-based addObserver, so no manual cleanup needed
    }

    // MARK: - Configuration

    /// Set the annotation store to observe for badge counts
    public func setAnnotationStore(_ store: AnnotationStore) {
        self.annotationStore = store
        self.annotationCount = store.annotations.count

        // Observe annotation changes via Combine
        store.$annotations
            .map(\.count)
            .receive(on: RunLoop.main)
            .assign(to: &$annotationCount)
    }

    // MARK: - Setup

    private func setupContent() {
        let toolbarView = FloatingToolbarHostView(controller: self)

        let hosting = NSHostingView(rootView: AnyView(toolbarView))
        hosting.frame = window?.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]

        // Let SwiftUI size the window naturally
        window?.contentView = hosting
        hostingView = hosting
    }

    private func setupObservers() {
        // Observe isExpanded changes to trigger inspection callbacks
        // and capture the anchor point BEFORE SwiftUI resizes the window
        $isExpanded
            .dropFirst() // Skip initial value
            .sink { [weak self] expanded in
                guard let self = self, let window = self.window else { return }
                // Capture current right edge BEFORE the resize happens
                self.anchoredRightEdge = window.frame.maxX
                self.handleExpandedChange(expanded)
            }
            .store(in: &cancellables)

        // Observe window frame changes to adjust origin (keep right edge anchored)
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.handleWindowResize()
        }
    }

    private func handleExpandedChange(_ expanded: Bool) {
        if expanded {
            onExpand?()
        } else {
            onCollapse?()
        }
    }

    /// Called when window resizes (triggered by SwiftUI content change).
    /// Adjusts the window origin to keep the right edge anchored.
    private func handleWindowResize() {
        guard let window = window,
              let anchoredRightEdge = anchoredRightEdge else { return }

        let currentFrame = window.frame

        // Calculate where origin should be to keep right edge anchored
        let targetOriginX = anchoredRightEdge - currentFrame.width

        // Only adjust if there's a meaningful difference
        if abs(currentFrame.origin.x - targetOriginX) > 1 {
            var newFrame = currentFrame
            newFrame.origin.x = targetOriginX

            // Ensure window stays on screen
            if let screen = window.screen ?? NSScreen.main {
                let screenFrame = screen.visibleFrame
                let padding: CGFloat = 20

                // Don't let left edge go off screen
                if newFrame.origin.x < screenFrame.minX + padding {
                    newFrame.origin.x = screenFrame.minX + padding
                }

                // Don't let right edge go off screen
                if newFrame.maxX > screenFrame.maxX - padding {
                    newFrame.origin.x = screenFrame.maxX - newFrame.width - padding
                }
            }

            window.setFrame(newFrame, display: false)
        }

        // Clear the anchor after handling
        self.anchoredRightEdge = nil
    }

    private func positionWindow() {
        guard let window = window, let screen = NSScreen.main else { return }

        // Wait briefly for SwiftUI to lay out content and determine size
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }

            let screenFrame = screen.visibleFrame
            let size = window.frame.size  // Use actual size from SwiftUI content

            // Position at bottom-right with padding
            let origin = NSPoint(
                x: screenFrame.maxX - size.width - 20,
                y: screenFrame.minY + 20
            )

            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }
    }

    // MARK: - Public Methods

    /// Refresh the toolbar content (call when annotation count changes)
    /// Note: With reactive SwiftUI binding, this is now a no-op but kept for API compatibility
    public func refreshContent() {
        // No longer needed - SwiftUI observes changes automatically
    }

    /// Update the list of available apps
    public func updateAvailableApps(_ apps: [TargetApp]) {
        availableApps = apps
    }

    /// Update the currently selected app
    public func updateSelectedApp(_ app: TargetApp?) {
        selectedApp = app
    }

    /// Show the toolbar window
    public func show() {
        showWindow(nil)
        window?.orderFront(nil)
    }

    /// Hide the toolbar window
    public func hide() {
        window?.orderOut(nil)
    }

    /// Toggle visibility
    public func toggleVisibility() {
        if window?.isVisible == true {
            hide()
        } else {
            show()
        }
    }
}

// MARK: - SwiftUI Host View

/// A SwiftUI wrapper that observes the controller and renders the toolbar
/// This allows proper reactive updates when @Published properties change
private struct FloatingToolbarHostView: View {
    @ObservedObject var controller: FloatingToolbarWindowController

    var body: some View {
        FloatingToolbarView(
            isExpanded: Binding(
                get: { controller.isExpanded },
                set: { controller.isExpanded = $0 }
            ),
            selectedApp: Binding(
                get: { controller.selectedApp },
                set: {
                    controller.selectedApp = $0
                    controller.onAppSelected?($0)
                }
            ),
            availableApps: controller.availableApps,
            showCopySuccess: controller.showCopySuccess,
            annotationCount: controller.annotationCount,
            settings: controller.settings,
            onCopyFeedback: {
                controller.onCopyFeedback?()
                controller.showCopySuccess = true
                // Reset after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    controller.showCopySuccess = false
                }
            },
            onClearAnnotations: {
                controller.onClearAnnotations?()
            },
            onRefreshApps: {
                controller.onRefreshApps?()
            },
            onCheckForUpdates: {
                controller.onCheckForUpdates?()
            }
        )
    }
}
