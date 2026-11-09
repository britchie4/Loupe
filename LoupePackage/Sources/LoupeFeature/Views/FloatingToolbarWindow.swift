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

    /// The latest size the toolbar content asked for, applied after the current layout pass
    private var pendingContentSize: CGSize?

    /// Where the pointer and window were when the collapsed icon started being dragged
    /// A press on the collapsed icon: where it started, and whether it became a drag
    private struct IconPress {
        var mouse: NSPoint
        var origin: NSPoint
        var isDragging = false
    }
    private var iconPress: IconPress?
    private var iconMouseMonitor: Any?
    /// How far the pointer must move before a press becomes a drag, in points
    static let dragThreshold: CGFloat = 3

    /// Remembers where the person left the collapsed icon
    private static let savedFrameKey = "loupe.toolbarCollapsedFrame"

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
        // Catch clicks across the whole window, even where nothing is drawn at that moment.
        // A see-through window otherwise lets clicks fall through its clear pixels, so a
        // click on the icon while it was still animating closed went to the app beneath.
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // Collapsed, the icon moves with its own drag (see handleIconMouse); expanded, the bar's background drags it
        window.isMovableByWindowBackground = false

        super.init(window: window)

        setupContent()
        setupObservers()
        positionWindow()
        installIconMouseHandling()
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
        self.annotationCount = store.annotations.filter { $0.status.isOpen }.count

        // Observe annotation changes via Combine
        store.$annotations
            // Count only notes that still need work
            .map { $0.filter { $0.status.isOpen }.count }
            .receive(on: RunLoop.main)
            .assign(to: &$annotationCount)
    }

    // MARK: - Setup

    private func setupContent() {
        let toolbarView = FloatingToolbarHostView(controller: self)

        let hosting = NSHostingView(rootView: AnyView(toolbarView))
        // The window is sized here (see applyContentSize), in one step that keeps the right
        // and bottom edges still. Letting the hosting view resize the window itself grew it
        // to the right first and moved it back a moment later, which made the toolbar jump.
        hosting.sizingOptions = []
        hosting.frame = window?.contentView?.bounds ?? .zero
        hosting.autoresizingMask = [.width, .height]

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
                window.isMovableByWindowBackground = expanded
                self.handleExpandedChange(expanded)
            }
            .store(in: &cancellables)
    }

    private func handleExpandedChange(_ expanded: Bool) {
        if expanded {
            onExpand?()
        } else {
            onCollapse?()
        }
    }

    /// The toolbar content reported a new size (it expanded, collapsed, or a badge appeared)
    func contentSizeChanged(_ size: CGSize) {
        pendingContentSize = size
        // Resize after the current layout pass; resizing mid-layout makes AppKit apply it twice
        DispatchQueue.main.async { [weak self] in
            guard let self, let size = self.pendingContentSize else { return }
            self.pendingContentSize = nil
            self.applyContentSize(size)
        }
    }

    /// Fit the window to the content in one step, keeping its right and bottom edges where
    /// they are (so it grows to the left) and keeping it on the display it is on now.
    private func applyContentSize(_ size: CGSize) {
        guard let window, size.width > 0, size.height > 0 else { return }
        let current = window.frame
        let newSize = NSSize(width: ceil(size.width), height: ceil(size.height))
        guard abs(current.width - newSize.width) > 0.5 || abs(current.height - newSize.height) > 0.5 else { return }

        var frame = NSRect(
            x: current.maxX - newSize.width,
            y: current.minY,
            width: newSize.width,
            height: newSize.height
        )
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        if let index = Self.indexOfScreen(containing: current, screenFrames: visibleFrames) {
            frame = Self.clamped(frame, into: visibleFrames[index])
        }
        window.setFrame(frame, display: true)
        saveCollapsedFrame()
    }

    /// The display that holds the middle of `frame`, falling back to the one it overlaps most
    static func screen(containing frame: NSRect, in screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        indexOfScreen(containing: frame, screenFrames: screens.map(\.frame)).map { screens[$0] }
    }

    /// Index of the display frame that holds the middle of `frame`, or else the one it overlaps most
    static func indexOfScreen(containing frame: NSRect, screenFrames: [NSRect]) -> Int? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let match = screenFrames.firstIndex(where: { $0.contains(center) }) {
            return match
        }
        func overlap(_ screen: NSRect) -> CGFloat {
            let shared = screen.intersection(frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        return screenFrames.indices.max { overlap(screenFrames[$0]) < overlap(screenFrames[$1]) }
    }

    private func positionWindow() {
        guard let window = window, let screen = NSScreen.main else { return }

        // Wait briefly for SwiftUI to lay out content and determine size
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }

            let size = window.frame.size  // Use actual size from SwiftUI content

            // Go back to where the person left it, as long as that display is still connected
            if let saved = UserDefaults.standard.string(forKey: Self.savedFrameKey) {
                let previous = NSRectFromString(saved)
                // Keep the saved right and bottom edges, the ones the toolbar grows from
                let savedFrame = NSRect(x: previous.maxX - size.width, y: previous.minY, width: size.width, height: size.height)
                let visibleFrames = NSScreen.screens.map(\.visibleFrame)
                if let index = Self.indexOfScreen(containing: savedFrame, screenFrames: visibleFrames) {
                    let frame = Self.clamped(savedFrame, into: visibleFrames[index])
                    window.setFrame(frame, display: true)
                    return
                }
            }

            let screenFrame = screen.visibleFrame

            // Position at bottom-right with padding
            let origin = NSPoint(
                x: screenFrame.maxX - size.width - 20,
                y: screenFrame.minY + 20
            )

            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }
    }

    /// `frame` moved just enough to sit inside `visible`, keeping a small margin
    static func clamped(_ frame: NSRect, into visible: NSRect, padding: CGFloat = 8) -> NSRect {
        var result = frame
        result.origin.x = min(max(frame.minX, visible.minX + padding), visible.maxX - frame.width - padding)
        result.origin.y = min(max(frame.minY, visible.minY + padding), visible.maxY - frame.height - padding)
        return result
    }

    // MARK: - Moving the Icon

    /// Clicks and drags on the collapsed icon are handled here, from the window's own
    /// mouse events, rather than with SwiftUI tap and drag gestures. Those gestures
    /// could wedge after some open-and-close sequences and then ignore every click,
    /// even though the clicks kept arriving. Events still pass through, so the glass
    /// keeps its pressed look and right-click still shows the menu.
    private func installIconMouseHandling() {
        iconMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleIconMouse(event) }
            return event
        }
    }

    private func handleIconMouse(_ event: NSEvent) {
        guard let window, event.window === window else { return }
        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        switch event.type {
        case .leftMouseDown:
            // Control-click opens the context menu instead
            guard !isExpanded, !event.modifierFlags.contains(.control) else {
                iconPress = nil
                return
            }
            iconPress = IconPress(mouse: mouse, origin: window.frame.origin)
        case .leftMouseDragged:
            guard var press = iconPress, !isExpanded else { return }
            if !press.isDragging {
                guard hypot(mouse.x - press.mouse.x, mouse.y - press.mouse.y) >= Self.dragThreshold else { return }
                press.isDragging = true
                iconPress = press
                NSCursor.closedHand.push()
            }
            window.setFrameOrigin(NSPoint(
                x: press.origin.x + mouse.x - press.mouse.x,
                y: press.origin.y + mouse.y - press.mouse.y
            ))
        case .leftMouseUp:
            guard let press = iconPress else { return }
            iconPress = nil
            if press.isDragging {
                NSCursor.pop()
                settleIconOnScreen()
            } else if !isExpanded {
                openFromIcon()
            }
        default:
            break
        }
    }

    private func openFromIcon() {
        if #available(macOS 26.0, *) {
            withAnimation(.bouncy) { isExpanded = true }
        } else {
            withAnimation(.smooth(duration: 0.4)) { isExpanded = true }
        }
    }

    /// Settle the icon fully on the display it was dropped on
    private func settleIconOnScreen() {
        guard let window else { return }
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        if let index = Self.indexOfScreen(containing: window.frame, screenFrames: visibleFrames) {
            let frame = Self.clamped(window.frame, into: visibleFrames[index])
            if frame != window.frame {
                window.setFrame(frame, display: true, animate: true)
            }
        }
        saveCollapsedFrame()
    }

    private func saveCollapsedFrame() {
        guard let window, !isExpanded, pendingContentSize == nil else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.savedFrameKey)
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
        .fixedSize()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            controller.contentSizeChanged(size)
        }
        // Hug the window's right and bottom edges, the ones that stay still while it resizes
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .overlay(alignment: .topTrailing) {
            CollapsedCountBadge(count: controller.annotationCount, isExpanded: controller.isExpanded)
        }
    }
}

/// The open-note count on the collapsed icon. It's pinned to the window's corner
/// rather than to the icon, and fades in once the icon has finished sliding in, so
/// it never rides the icon's spring or gets clipped by the window's edge.
private struct CollapsedCountBadge: View {
    let count: Int
    let isExpanded: Bool
    @State private var iconSettled = false

    /// Roughly how long the icon's slide-in takes to come to rest
    private static let settleDelay: Duration = .milliseconds(420)

    var body: some View {
        ZStack {
            // Always-present placeholder: an empty container never appears, so its
            // .task below would never run and the badge would never be shown
            Color.clear.frame(width: 1, height: 1)
            if count > 0, !isExpanded, iconSettled {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.loupeBadge))
                    .transition(.opacity)
                    .accessibilityLabel(count == 1 ? "1 open note" : "\(count) open notes")
            }
        }
        .allowsHitTesting(false)
        .task(id: isExpanded) {
            iconSettled = false
            guard !isExpanded else { return }
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { iconSettled = true }
        }
    }
}
