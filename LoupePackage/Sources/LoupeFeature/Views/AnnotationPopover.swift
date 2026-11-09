import SwiftUI

extension Notification.Name {
    static let loupePopoverReadyForFocus = Notification.Name("loupePopoverReadyForFocus")
}

/// What the note window shows about the element a note is attached to.
/// Built from a live element (new note) or from a saved note (existing note).
struct NoteElementSummary {
    /// Plain-language kind and app, e.g. "Menu in TextEdit"
    let kindLine: String
    /// The words on the element, e.g. "\"Regular\"", or the kind when it has none
    let nameLine: String
    /// Technical details for the Details section (raw accessibility names, for developers)
    let details: [(label: String, value: String)]

    init(element: AXElementInfo, appName: String?) {
        self.init(
            role: element.role,
            identifier: element.identifier,
            title: element.title,
            value: element.value,
            path: element.hierarchyPath,
            appName: appName
        )
    }

    init(annotation: Annotation) {
        self.init(
            role: annotation.elementRole,
            identifier: annotation.elementIdentifier,
            title: annotation.elementTitle,
            value: annotation.elementValue,
            path: annotation.hierarchyPath,
            appName: annotation.appName
        )
    }

    private init(
        role: String,
        identifier: String?,
        title: String?,
        value: String?,
        path: [HierarchyNode],
        appName: String?
    ) {
        let kind = ElementKind.name(forRole: role)
        if let appName, !appName.isEmpty {
            kindLine = "\(kind) in \(appName)"
        } else {
            kindLine = kind
        }
        if let visible = ElementKind.visibleText(title: title, value: value, identifier: identifier) {
            nameLine = "\u{201C}\(visible)\u{201D}"
        } else {
            nameLine = kind
        }

        var rows: [(label: String, value: String)] = [("Role", role)]
        if let identifier, !identifier.isEmpty { rows.append(("Identifier", identifier)) }
        if let title, !title.isEmpty { rows.append(("Title", title)) }
        if let value, !value.isEmpty { rows.append(("Value", value)) }
        if !path.isEmpty {
            rows.append(("Path", path.map { $0.annotatedString }.joined(separator: " > ")))
        }
        details = rows
    }
}

/// Shared between the note window and its panel controller: whether the user has typed
/// something unsaved (which makes the window hold on to clicks elsewhere), and the window's size.
@MainActor
final class NoteWindowState: ObservableObject {
    @Published var hasUnsavedInput = false
    var onSizeChange: ((CGSize) -> Void)?
}

/// The note window: write a new note, or follow the conversation on an existing one
struct AnnotationPopover: View {
    enum Mode {
        case new(onAdd: (String) -> Void)
        case existing(
            note: Annotation,
            onEdit: (String) -> Annotation?,
            onReply: (String) -> Annotation?,
            onDelete: () -> Void
        )
    }

    private enum Field: Hashable {
        case newNote, reply, edit
    }

    let summary: NoteElementSummary
    let mode: Mode
    let onClose: () -> Void
    @ObservedObject var windowState: NoteWindowState

    @State private var note: Annotation?
    @State private var newText = ""
    @State private var replyText = ""
    @State private var editText = ""
    @State private var isEditing = false
    @State private var showDetails = false
    @State private var threadHeight: CGFloat = 0
    @FocusState private var focus: Field?

    /// Tallest the conversation gets before it scrolls
    private let maxThreadHeight: CGFloat = 340

    /// How long the window takes to open or close a section, like the details
    static let resizeAnimationDuration: Double = 0.22

    init(summary: NoteElementSummary, mode: Mode, windowState: NoteWindowState, onClose: @escaping () -> Void) {
        self.summary = summary
        self.mode = mode
        self.windowState = windowState
        self.onClose = onClose
        if case .existing(let note, _, _, _) = mode {
            self._note = State(initialValue: note)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if showDetails {
                detailsView
                    .transition(.opacity)
            }
            Divider().opacity(0.6)
            if let note {
                thread(for: note)
                Divider().opacity(0.6)
                composer(for: note)
                Divider().opacity(0.6)
                footer
            } else {
                newNoteBody
            }
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .popoverBackground()
        .tint(Color.loupeAccentStrong)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            windowState.onSizeChange?(size)
        }
        .onChange(of: newText) { updateUnsavedInput() }
        .onChange(of: replyText) { updateUnsavedInput() }
        .onChange(of: editText) { updateUnsavedInput() }
        .onChange(of: isEditing) { updateUnsavedInput() }
        .onReceive(NotificationCenter.default.publisher(for: .loupePopoverReadyForFocus)) { _ in
            let target = initialFocus
            focus = target
            // Defensive retry: if SwiftUI silently drops the focus assignment
            // (e.g. view not yet in responder chain), try again after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if focus != target {
                    focus = target
                }
            }
        }
    }

    // MARK: Header

    private var attention: NoteAttention? {
        note.map(NoteAttention.init(note:))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.kindLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(summary.nameLine)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if let attention {
                StatusLabel(attention: attention)
            }
            Button {
                withAnimation(.smooth(duration: Self.resizeAnimationDuration)) { showDetails.toggle() }
            } label: {
                Image(systemName: showDetails ? "info.circle.fill" : "info.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(showDetails ? "Hide details" : "Show details")
            .accessibilityLabel(showDetails ? "Hide element details" : "Show element details")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(summary.details.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.label)
                        .foregroundStyle(.tertiary)
                        .frame(width: 64, alignment: .trailing)
                    Text(row.value)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: New note

    private var newNoteBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputField("What should change?", text: $newText, lines: 3...6)
                .focused($focus, equals: .newNote)
            HStack {
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") {
                    if case .new(let onAdd) = mode { onAdd(newText) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isBlank(newText))
            }
        }
        .padding(14)
    }

    // MARK: Conversation

    private func thread(for note: Annotation) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                userNoteMessage(note)
                ForEach(note.replies) { reply in
                    MessageBubble(
                        author: reply.author == .agent ? "Agent" : "You",
                        time: reply.createdAt,
                        isMine: reply.author == .user
                    ) {
                        Text(reply.text)
                    }
                }
                if note.replies.isEmpty, note.status == .pending {
                    Text("No agent has picked this up yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { threadHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(max(threadHeight, 1), maxThreadHeight))
    }

    @ViewBuilder
    private func userNoteMessage(_ note: Annotation) -> some View {
        MessageBubble(
            author: "You",
            time: note.createdAt,
            isMine: true,
            action: isEditing ? nil : ("Edit", { startEditing(note) })
        ) {
            if isEditing {
                VStack(alignment: .trailing, spacing: 8) {
                    inputField("What should change?", text: $editText, lines: 2...6)
                        .focused($focus, equals: .edit)
                    HStack(spacing: 8) {
                        Button("Cancel") { isEditing = false }
                            .controlSize(.small)
                        Button("Save") { saveEdit() }
                            .controlSize(.small)
                            .keyboardShortcut(.defaultAction)
                            .disabled(isBlank(editText))
                    }
                }
            } else {
                Text(note.text)
            }
        }
    }

    // MARK: Reply box

    private func composer(for note: Annotation) -> some View {
        let isClosed = !note.status.isOpen
        let placeholder: String
        if isClosed {
            placeholder = "Add a follow-up to reopen"
        } else if attention == .questionForYou {
            placeholder = "Answer the agent"
        } else {
            placeholder = "Add more detail"
        }

        return HStack(alignment: .bottom, spacing: 8) {
            inputField(placeholder, text: $replyText, lines: 1...5)
                .focused($focus, equals: .reply)
            let send = Button(isClosed ? "Reopen" : "Send") { sendReply() }
                .disabled(isBlank(replyText))
            if isEditing {
                send
            } else {
                send.keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Button("Delete note", role: .destructive) {
                if case .existing(_, _, _, let onDelete) = mode { onDelete() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.85))
            Spacer()
            Button("Close") { onClose() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: Pieces

    private func inputField(_ placeholder: String, text: Binding<String>, lines: ClosedRange<Int>) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(lines)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }

    // MARK: Actions

    private var initialFocus: Field? {
        guard let note else { return .newNote }
        return NoteAttention(note: note).focusesReply ? .reply : nil
    }

    private func startEditing(_ note: Annotation) {
        editText = note.text
        isEditing = true
        DispatchQueue.main.async { focus = .edit }
    }

    private func saveEdit() {
        guard case .existing(_, let onEdit, _, _) = mode, !isBlank(editText) else { return }
        if let updated = onEdit(editText) { note = updated }
        isEditing = false
    }

    private func sendReply() {
        guard case .existing(_, _, let onReply, _) = mode, !isBlank(replyText) else { return }
        if let updated = onReply(replyText) { note = updated }
        replyText = ""
        focus = .reply
    }

    private func updateUnsavedInput() {
        let editing = isEditing && editText != (note?.text ?? "")
        windowState.hasUnsavedInput = !isBlank(newText) || !isBlank(replyText) || editing
    }

    private func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Message bubble

/// One message in a note's conversation: who wrote it, when, and the text
private struct MessageBubble<Content: View>: View {
    let author: String
    let time: Date
    let isMine: Bool
    var action: (label: String, perform: () -> Void)? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(author)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(Self.timeLabel(time))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                if let action {
                    Button(action.label, action: action.perform)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.loupeAccentText)
                }
            }
            content
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isMine ? Color.loupeAccent.opacity(0.16) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isMine ? Color.loupeAccent.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(author), \(Self.timeLabel(time))")
    }

    static func timeLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}

// MARK: - Status label

/// The colored label in the header that says what the note needs
private struct StatusLabel: View {
    let attention: NoteAttention

    private var color: Color {
        switch attention {
        case .waiting, .agentWorking: return .loupeAccentText
        case .questionForYou, .agentReplied: return .blue
        case .done: return .green
        case .dismissed: return .secondary
        }
    }

    var body: some View {
        Text(attention.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18)))
            .fixedSize()
            .accessibilityLabel("Status: \(attention.label)")
    }
}

extension View {
    /// Liquid Glass behind the note window on macOS 26+; nothing on earlier versions,
    /// where the panel's own layer draws the background
    @ViewBuilder
    func popoverBackground() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            self
        }
    }
}

// MARK: - Popover Panel

/// Custom NSPanel subclass for popover-style presentation without a caret
private class PopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        // Handle Escape key
        close()
    }
}

/// Custom NSView subclass that accepts first mouse to ensure clicks work
/// immediately when the panel appears, even if it's not yet the key window.
private class FirstMouseView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        // Critical: Return true to accept mouse clicks even when panel isn't key window
        // Without this, borderless panels may ignore the first click
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Let subviews (the SwiftUI hosting view) handle the hit test
        // This ensures mouse events reach the actual controls
        return super.hitTest(point)
    }
}

/// Controller for managing the annotation popover presentation using a borderless panel
@MainActor
final class AnnotationPopoverController {
    private var panel: NSPanel?
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var onDismissCallback: (() -> Void)?
    /// Unsaved typing and size reports from the open note window
    private var windowState: NoteWindowState?
    /// Whether the cursor goes into a text box when the window opens
    private var focusesOnOpen = true
    /// The content's latest reported size, kept even before the panel exists so the panel
    /// can catch up with a size reported while it was being created
    private var lastContentSize: CGSize?
    /// Keeps the open note window's SwiftUI content alive
    private var hostingController: NSViewController?

    /// Spacing between element and panel edge
    private let panelOffset: CGFloat = 8

    /// Show the window for writing a new note on an element
    /// - Parameters:
    ///   - elementFrame: The element's frame in screen coordinates (AppKit: origin at bottom-left)
    ///   - preferredEdge: Which edge of the element to attach the window to
    ///   - summary: What to show about the element
    ///   - onAdd: Called with the note's text when the user adds it
    ///   - onDismiss: Called when the window closes
    func showNewNote(
        forElementFrame elementFrame: NSRect,
        preferredEdge: NSRectEdge,
        summary: NoteElementSummary,
        onAdd: @escaping (String) -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        present(
            forElementFrame: elementFrame,
            preferredEdge: preferredEdge,
            summary: summary,
            focusesOnOpen: true,
            onDismiss: onDismiss
        ) { [weak self] in
            .new(onAdd: { text in
                onAdd(text)
                self?.dismiss()
            })
        }
    }

    /// Show a saved note as a conversation the user can reply to, edit, or delete
    /// - Parameters:
    ///   - onEdit: Saves new text for the user's note and returns the updated note
    ///   - onReply: Adds the user's reply and returns the updated note
    ///   - onDelete: Deletes the note (the window then closes)
    func showNote(
        _ note: Annotation,
        forElementFrame elementFrame: NSRect,
        preferredEdge: NSRectEdge,
        summary: NoteElementSummary,
        onEdit: @escaping (String) -> Annotation?,
        onReply: @escaping (String) -> Annotation?,
        onDelete: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        present(
            forElementFrame: elementFrame,
            preferredEdge: preferredEdge,
            summary: summary,
            focusesOnOpen: NoteAttention(note: note).focusesReply,
            onDismiss: onDismiss
        ) { [weak self] in
            .existing(
                note: note,
                onEdit: onEdit,
                onReply: onReply,
                onDelete: {
                    onDelete()
                    self?.dismiss()
                }
            )
        }
    }

    private func present(
        forElementFrame elementFrame: NSRect,
        preferredEdge: NSRectEdge,
        summary: NoteElementSummary,
        focusesOnOpen: Bool,
        onDismiss: (() -> Void)?,
        mode makeMode: () -> AnnotationPopover.Mode
    ) {
        // Dismiss any existing panel immediately (no animation when replacing)
        dismiss(animated: false)

        self.onDismissCallback = onDismiss
        self.focusesOnOpen = focusesOnOpen

        // Note: Glassmorphism dim overlay removed - NSVisualEffectView with .behindWindow
        // covering all screens causes WindowServer hangs. The modal behavior (wiggle on
        // click-outside, Escape to dismiss) works without the visual dim effect.

        let state = NoteWindowState()
        lastContentSize = nil
        state.onSizeChange = { [weak self] size in
            self?.lastContentSize = size
            // Resize after the current layout pass. Resizing the window in the middle of
            // SwiftUI's layout makes AppKit apply the size change twice, which leaves the
            // content taller than the window and the note's top cropped.
            DispatchQueue.main.async { [weak self] in
                guard let self, let latest = self.lastContentSize else { return }
                self.resizePanel(toFit: latest)
            }
        }
        self.windowState = state

        // Create the SwiftUI content
        let content = AnnotationPopover(
            summary: summary,
            mode: makeMode(),
            windowState: state,
            onClose: { [weak self] in
                self?.dismiss()
            }
        )

        // Create the hosting controller. It doesn't size the window itself (sizingOptions = []):
        // the window is sized here from the content's measured size and kept in step by
        // resizePanel, and the hosting view simply fills the window.
        let hostingController = NSHostingController(rootView: content)
        // The hosting view takes the content's own height and hangs from the top of the window,
        // so when the content grows or shrinks it never shifts while the window catches up.
        // (The window itself is sized by resizePanel; the hosting view doesn't resize it.)
        hostingController.sizingOptions = [.intrinsicContentSize]
        let measured = hostingController.sizeThatFits(in: NSSize(width: 340, height: 10_000))
        let contentSize = NSSize(width: ceil(measured.width), height: ceil(measured.height))

        // Calculate panel position based on preferred edge and element frame
        let panelOrigin = calculatePanelOrigin(
            elementFrame: elementFrame,
            contentSize: contentSize,
            preferredEdge: preferredEdge
        )

        // Create the panel with .nonactivatingPanel so it can become key (accept keyboard
        // input) without requiring the app to be active. This is critical because the overlay
        // window's click monitor consumes mouse events before they reach the window, so macOS
        // doesn't register user interaction and NSApp.activate() is silently declined.
        let panel = PopoverPanel(
            contentRect: NSRect(origin: panelOrigin, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isFloatingPanel = true  // Stay above other windows
        panel.becomesKeyOnlyIfNeeded = false  // Always become key when clicked
        panel.hidesOnDeactivate = false  // Stay visible when app loses focus

        // Wrap the hosting view in a FirstMouseView to ensure clicks work immediately
        let hostingView = hostingController.view
        let firstMouseContainer = FirstMouseView()
        firstMouseContainer.wantsLayer = true
        firstMouseContainer.addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: firstMouseContainer.leadingAnchor),
            hostingView.topAnchor.constraint(equalTo: firstMouseContainer.topAnchor)
        ])

        // The container stays the window's content view (so the window keeps it at the window's
        // size) and the hosting view is pinned inside it. Setting contentViewController here
        // would swap the container out and leave the note shifted and cropped as it resizes.
        panel.contentView = firstMouseContainer
        self.hostingController = hostingController  // Retain the hosting controller

        // IMPORTANT: Setting contentView can change the frame, so explicitly set it again
        // to ensure the panel is positioned at our calculated origin
        panel.setFrameOrigin(panelOrigin)

        // Style the content view with rounded corners and background.
        // On macOS 26+ the SwiftUI content draws its own Liquid Glass, so the layer stays clear.
        if #available(macOS 26.0, *) {
            panel.contentView?.wantsLayer = true
            panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        } else if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 8
            contentView.layer?.masksToBounds = true
            contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            contentView.layer?.borderColor = NSColor.separatorColor.cgColor
            contentView.layer?.borderWidth = 0.5
        }

        // Start transparent and fade in. (No scale animation: it required moving the content
        // layer's anchor point, which left the content shifted and cropped once the window
        // resized to fit a reply.)
        panel.alphaValue = 0

        self.panel = panel

        // The content may have reported its final size while the panel was being built
        // (before it existed); apply it now, and again after the first layout pass.
        if let size = lastContentSize { resizePanel(toFit: size) }
        DispatchQueue.main.async { [weak self] in
            if let size = self?.lastContentSize { self?.resizePanel(toFit: size) }
        }

        // Activate app and show the panel
        // Note: activateIgnoringOtherApps is a no-op on macOS 14+, so we use the
        // standard activate(). The polling loop handles the case where activation
        // is delayed or declined.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)

        // Poll until the panel is ready for focus, then assign it.
        // On macOS 14+, programmatic activation is async and may take
        // multiple run loop cycles — especially on the first app switch.
        awaitActivationAndFocus()

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        // Install event monitors
        installClickOutsideMonitor()
        installKeyboardMonitor()
    }

    /// Poll until the panel is key, then assign focus.
    /// On macOS 14+, NSPanel can become key without the app being fully "active"
    /// (NSApp.isActive), so we only gate on panel.isKeyWindow.
    private func awaitActivationAndFocus(attempt: Int = 0) {
        guard let panel = self.panel else { return }

        // NSPanel can accept keyboard focus without full app activation —
        // only require the panel to be key, not NSApp.isActive
        if panel.isKeyWindow {
            focusTextField()
            return
        }

        // Give up after ~1s (20 attempts × 50ms) — reduced from 2s since we
        // no longer wait for NSApp.isActive
        guard attempt < 20 else {
            // Last resort: force focus anyway (better than no focus)
            focusTextField()
            return
        }

        // Re-poke activation each cycle — macOS may need repeated requests
        if !NSApp.isActive {
            NSApp.activate()
        }
        if !panel.isKeyWindow {
            panel.makeKeyAndOrderFront(nil)
        }

        // Poll again on next run loop cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.awaitActivationAndFocus(attempt: attempt + 1)
        }
    }

    /// Consolidate all focus logic: ensure panel is key, set first responder, notify SwiftUI
    private func focusTextField() {
        guard let panel = self.panel else { return }

        if !panel.isKeyWindow {
            panel.makeKeyAndOrderFront(nil)
        }

        // Walk the view hierarchy to find the actual NSTextField (or its field editor
        // NSTextView). makeFirstResponder on the hosting view container is not enough —
        // SwiftUI wraps the text field in multiple layers and the hosting view itself
        // is not the responder that accepts text input.
        // A saved note that isn't waiting on an answer opens for reading: no cursor.
        if !focusesOnOpen {
            panel.makeFirstResponder(nil)
        } else if let contentView = panel.contentView,
           let textField = Self.findEditableTextField(in: contentView) {
            panel.makeFirstResponder(textField)
        } else if let hostingView = panel.contentView?.subviews.first {
            // Fallback: target the hosting view if we can't find the text field
            panel.makeFirstResponder(hostingView)
        }

        // Post on next run-loop cycle so SwiftUI has one layout pass to settle
        // before @FocusState is assigned
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .loupePopoverReadyForFocus, object: nil)
        }
    }

    /// Recursively search the view hierarchy for an editable NSTextField
    private static func findEditableTextField(in view: NSView) -> NSTextField? {
        for subview in view.subviews {
            if let textField = subview as? NSTextField, textField.isEditable {
                return textField
            }
            if let found = findEditableTextField(in: subview) {
                return found
            }
        }
        return nil
    }

    /// Calculate where to position the panel origin based on the element frame and preferred edge
    private func calculatePanelOrigin(
        elementFrame: NSRect,
        contentSize: NSSize,
        preferredEdge: NSRectEdge
    ) -> NSPoint {
        var origin: NSPoint
        let edgeName: String

        // Position the popover adjacent to the element's edge, vertically/horizontally centered
        switch preferredEdge {
        case .minX:
            // Panel appears to the left of element
            origin = NSPoint(
                x: elementFrame.minX - contentSize.width - panelOffset,
                y: elementFrame.midY - contentSize.height / 2
            )
            edgeName = "minX (left of element)"
        case .maxX:
            // Panel appears to the right of element
            origin = NSPoint(
                x: elementFrame.maxX + panelOffset,
                y: elementFrame.midY - contentSize.height / 2
            )
            edgeName = "maxX (right of element)"
        case .minY:
            // Panel appears above element (in AppKit coords, minY is bottom, so "above" means higher Y)
            origin = NSPoint(
                x: elementFrame.midX - contentSize.width / 2,
                y: elementFrame.maxY + panelOffset
            )
            edgeName = "minY (above element)"
        case .maxY:
            // Panel appears below element
            origin = NSPoint(
                x: elementFrame.midX - contentSize.width / 2,
                y: elementFrame.minY - contentSize.height - panelOffset
            )
            edgeName = "maxY (below element)"
        @unknown default:
            origin = NSPoint(
                x: elementFrame.maxX + panelOffset,
                y: elementFrame.midY - contentSize.height / 2
            )
            edgeName = "unknown"
        }

        // Verbose positioning logs disabled
        // print("[Loupe] calculatePanelOrigin:")
        // print("[Loupe]   elementFrame = \(elementFrame)")
        // print("[Loupe]   contentSize = \(contentSize)")
        // print("[Loupe]   preferredEdge = \(edgeName)")
        // print("[Loupe]   calculated origin = \(origin)")

        // Ensure panel stays on screen (use the screen containing the element, not the focused screen)
        if let screen = NSScreen.screen(containing: elementFrame) ?? NSScreen.primaryScreen {
            let screenFrame = screen.visibleFrame

            // Clamp horizontal position
            if origin.x < screenFrame.minX {
                origin.x = screenFrame.minX
            } else if origin.x + contentSize.width > screenFrame.maxX {
                origin.x = screenFrame.maxX - contentSize.width
            }

            // Clamp vertical position
            if origin.y < screenFrame.minY {
                origin.y = screenFrame.minY
            } else if origin.y + contentSize.height > screenFrame.maxY {
                origin.y = screenFrame.maxY - contentSize.height
            }

            // print("[Loupe]   final origin (after clamping) = \(origin)")
        }

        return origin
    }

    /// Resize the panel when its content grows or shrinks (a reply is added, the reply box
    /// gets taller, details open), keeping the top edge in place and the panel on screen.
    private func resizePanel(toFit size: CGSize) {
        guard let panel, size.width > 0, size.height > 0 else { return }
        let current = panel.frame
        let newSize = NSSize(width: ceil(size.width), height: ceil(size.height))
        guard abs(current.width - newSize.width) > 0.5 || abs(current.height - newSize.height) > 0.5 else { return }

        var frame = NSRect(
            x: current.minX,
            y: current.maxY - newSize.height,
            width: newSize.width,
            height: newSize.height
        )
        if let screen = panel.screen ?? NSScreen.screen(containing: current) ?? NSScreen.primaryScreen {
            let visible = screen.visibleFrame
            if frame.minY < visible.minY { frame.origin.y = visible.minY }
            if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
            if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
            if frame.minX < visible.minX { frame.origin.x = visible.minX }
        }
        panel.setFrame(frame, display: true)
        // The panel is transparent around the glass, so its shadow is traced from what's drawn.
        // Recompute it after resizing, or the old outline lingers behind the window, and again
        // once the content has finished animating to its new size.
        panel.invalidateShadow()
        DispatchQueue.main.asyncAfter(deadline: .now() + AnnotationPopover.resizeAnimationDuration + 0.05) { [weak panel] in
            panel?.invalidateShadow()
        }
    }

    /// Install event monitor to show wiggle animation when clicking outside the panel (modal behavior)
    private func installClickOutsideMonitor() {
        // Use a GLOBAL monitor to detect clicks anywhere, including clicks that go to other apps.
        // This is necessary because the overlay window ignores mouse events when the popover is active,
        // allowing clicks to pass through to the target app. Global monitors observe but cannot consume events.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel else { return }

            let clickLocation = NSEvent.mouseLocation
            let isInsidePanel = panel.frame.contains(clickLocation)

            // print("[Loupe] CLICK (global): location=\(clickLocation), panelFrame=\(panel.frame), isInsidePanel=\(isInsidePanel)")

            if !isInsidePanel {
                // Reading a note (nothing typed yet): a click elsewhere just closes it,
                // like a standard macOS popover.
                guard self.windowState?.hasUnsavedInput == true else {
                    self.dismiss()
                    return
                }
                // Unsaved typing: wiggle instead of closing so nothing is lost
                self.wiggle()
                // Re-activate Loupe and bring popover to front
                NSApp.activate()
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Remove the click-outside monitor
    private func removeClickOutsideMonitor() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
    }

    /// Install keyboard event monitor for Escape key
    private func installKeyboardMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }

            // Check for Escape key (keyCode 53)
            if event.keyCode == 53 {
                self.dismiss()
                return nil  // Consume the event
            }

            return event
        }
    }

    /// Remove the keyboard monitor
    private func removeKeyboardMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    /// Animate a "wiggle" shake to indicate the popover is modal and cannot be dismissed by clicking outside
    private func wiggle() {
        guard let panel = panel else { return }

        // Use the panel's frame for the wiggle animation
        let originalFrame = panel.frame

        // Apply animation by adjusting the window frame directly with timed offsets
        let shakeOffsets: [CGFloat] = [-8, 8, -6, 6, -3, 3, 0]
        let interval: UInt64 = 57_000_000  // ~57ms per step (0.4s / 7 steps)

        Task { @MainActor [weak self] in
            for offset in shakeOffsets {
                guard let self = self, let panel = self.panel else { return }
                var frame = originalFrame
                frame.origin.x = originalFrame.origin.x + offset
                panel.setFrame(frame, display: false)
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    /// Dismiss the current panel if shown
    /// - Parameter animated: Whether to animate the dismissal. Use `false` when replacing with a new popover.
    func dismiss(animated: Bool = true) {
        removeClickOutsideMonitor()
        removeKeyboardMonitor()
        windowState?.onSizeChange = nil
        windowState = nil

        guard let panel = panel else {
            onDismissCallback?()
            onDismissCallback = nil
            return
        }

        // Clear reference immediately to prevent multiple popovers
        self.panel = nil

        if animated {
            // Fade out
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                panel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    panel.close()
                    self?.onDismissCallback?()
                    self?.onDismissCallback = nil
                }
            }
        } else {
            // Immediate dismissal (no animation)
            panel.close()
            onDismissCallback?()
            onDismissCallback = nil
        }
    }
}
