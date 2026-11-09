import AppKit
import SwiftUI

// The practice step in setup: a pretend app inside the setup window where a new person
// tries Loupe's loop (point, leave a note, hear back from an agent) before using it for real.
//
// The instructions, step count and Skip stay in one place at the top while the practice
// app and the note window change underneath. The outline, badge and note window are
// look-alikes of the real ones (`OverlayWindowController`, `AnnotationPopover`); they are
// drawn here on purpose instead of running the real inspection engine, which ignores
// Loupe's own windows. Nothing here touches the real notes.

// MARK: - Practice screen

struct PracticeView: View {
    let session: PracticeSession
    /// The closing screen's button: "Get Started" in first-run setup, "Done" when reopened later
    var finishLabel = "Get Started"
    let onSkip: () -> Void
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stage: PracticeStage { session.model.stage }

    var body: some View {
        ZStack {
            if stage == .finished {
                PracticeFinishView(finishLabel: finishLabel, onFinish: onFinish)
                    .transition(.opacity)
            } else {
                practice
                    .transition(.opacity)
            }
        }
        .frame(width: 480, height: 620)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.3), value: stage)
        .onChange(of: stage) { _, newStage in announce(newStage) }
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(PracticeCopy.stepLabel(session.model.stepNumber))
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.loupeAccentText)
                    .accessibilityLabel("Practice, step \(session.model.stepNumber) of \(PracticeModel.stepCount)")
                Spacer()
                Button(PracticeCopy.skipLabel, action: onSkip)
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityHint("Ends the practice. Nothing is saved.")
            }
            .padding(.top, 12)

            instructions
                .padding(.top, 10)

            PracticeStageView(session: session)
                .padding(.top, 12)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
    }

    /// Title and one or two lines of what to do, always in the same place
    private var instructions: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(PracticeCopy.title(for: stage))
                    .font(.title2.weight(.semibold))
                Text(PracticeCopy.body(for: stage))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .id(stage)
            .transition(.opacity)

            Spacer(minLength: 0)

            if stage == .done {
                Button(PracticeCopy.continueLabel) { session.continueToFinish() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.loupeAccentStrong)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .transition(.opacity)
            }
        }
        .frame(height: 76, alignment: .topLeading)
    }

    /// Read each new instruction (and the agent's line, when there is one) to VoiceOver
    private func announce(_ stage: PracticeStage) {
        var parts: [String] = []
        if let last = session.model.messages.last, last.author == .agent {
            parts.append("Agent: \(last.text)")
        }
        parts.append(PracticeCopy.title(for: stage) + ".")
        parts.append(PracticeCopy.body(for: stage))
        AccessibilityNotification.Announcement(parts.joined(separator: " ")).post()
    }
}

// MARK: - Stage: the practice app with Loupe's outline, badge and note window over it

/// Where each practice element sits, so the outline, badge and note window can be placed on it
private struct PracticeFrameKey: PreferenceKey {
    static var defaultValue: [PracticeElement: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [PracticeElement: Anchor<CGRect>], nextValue: () -> [PracticeElement: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct PracticeStageView: View {
    let session: PracticeSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let noteWidth: CGFloat = 340

    var body: some View {
        PracticeAppView(session: session)
            .overlayPreferenceValue(PracticeFrameKey.self) { anchors in
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        if let element = session.model.outlinedElement, let anchor = anchors[element] {
                            outline(for: element, frame: proxy[anchor], stageWidth: proxy.size.width)
                        }
                        if let element = session.model.selected, let anchor = anchors[element] {
                            noteLayer(for: element, frame: proxy[anchor], stageSize: proxy.size)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
            }
    }

    /// Loupe's hover outline, and the small name label that follows it while pointing
    @ViewBuilder
    private func outline(for element: PracticeElement, frame: CGRect, stageWidth: CGFloat) -> some View {
        PracticeOutline()
            .frame(width: frame.width + 4, height: frame.height + 4)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)

        if session.model.stage == .pointing {
            let label = ElementLabelView(role: element.role, title: element.title, identifier: nil)
                .fixedSize()
            Group {
                if element == .heading {
                    // Nothing else is on the heading's line, so its label sits beside it
                    // instead of covering the row underneath
                    label
                        .frame(height: frame.height, alignment: .center)
                        .offset(x: frame.maxX + 12, y: frame.minY)
                } else if frame.midX > stageWidth / 2 {
                    // Near the right side: line the label up with the outline's right edge
                    label
                        .frame(width: frame.maxX + 2, alignment: .trailing)
                        .offset(y: frame.maxY + 10)
                } else {
                    label
                        .offset(x: frame.minX - 2, y: frame.maxY + 10)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    /// The badge on the element and the note window below it
    @ViewBuilder
    private func noteLayer(for element: PracticeElement, frame: CGRect, stageSize: CGSize) -> some View {
        if let badge = session.model.badge {
            PracticeBadgeView(badge: badge)
                .position(x: frame.maxX + 2, y: frame.minY - 2)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
        }

        if session.model.isNoteOpen {
            // Below the element, like the real note window, and kept inside the stage
            let x = min(max(frame.midX - noteWidth / 2, 6), stageSize.width - noteWidth - 6)
            let y = frame.maxY + 12
            PracticeNoteWindow(
                session: session,
                element: element,
                maxHeight: stageSize.height - y
            )
            .frame(width: noteWidth)
            .offset(x: x, y: y)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .top).combined(with: .opacity))
        }
    }
}

// MARK: - The practice app

/// A small pretend app window with three things to point at
private struct PracticeAppView: View {
    let session: PracticeSession

    @FocusState private var focused: PracticeElement?

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Practice app")
        // Keyboard focus counts as pointing, so the outline follows Tab as well as the mouse
        .onChange(of: focused) { old, new in
            if let old { session.unhover(old) }
            if let new { session.hover(new) }
        }
    }

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.primary.opacity(0.16))
                        .frame(width: 11, height: 11)
                }
                Spacer()
            }
            Text(PracticeCopy.appName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityHidden(true)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            target(.heading) {
                Text(PracticeElement.heading.title)
                    .font(.title2.weight(.bold))
            }

            HStack(spacing: 8) {
                target(.reminder) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                            .stroke(Color.secondary, lineWidth: 1.2)
                            .frame(width: 14, height: 14)
                        Text(PracticeElement.reminder.title)
                            .font(.body)
                    }
                }
                Spacer(minLength: 8)
                target(.saveButton, padded: false) {
                    Text(PracticeElement.saveButton.title)
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                        )
                }
            }

            placeholderRows
                .padding(.top, 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    /// Grey bars standing in for the rest of the app. Not something to point at.
    private var placeholderRows: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach([0.78, 0.62, 0.7, 0.5, 0.74, 0.58], id: \.self) { width in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule()
                            .fill(Color.primary.opacity(0.1))
                            .frame(width: 300 * width, height: 8)
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                            .frame(width: 220 * width, height: 8)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// One thing in the practice app that can be pointed at and clicked
    private func target(
        _ element: PracticeElement,
        padded: Bool = true,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button {
            session.select(element)
        } label: {
            label()
                .foregroundStyle(.primary)
                .padding(.horizontal, padded ? 4 : 0)
                .padding(.vertical, padded ? 2 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focused, equals: element)
        .focusEffectDisabled()
        .onHover { inside in
            if inside { session.hover(element) } else { session.unhover(element) }
        }
        .anchorPreference(key: PracticeFrameKey.self, value: .bounds) { [element: $0] }
        .allowsHitTesting(session.model.stage == .pointing)
        .accessibilityLabel(element.accessibilityLabel)
        .accessibilityHint("Opens a practice note on this element")
    }
}

// MARK: - Outline and badge (look-alikes of the real overlay's)

/// Loupe's hover outline: a coral border with a soft glow and a faint fill
private struct PracticeOutline: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        shape
            .fill(Color.loupeHighlight.opacity(0.08))
            .overlay(shape.stroke(Color.loupeHighlight.opacity(0.3), lineWidth: 8))
            .overlay(shape.stroke(Color.loupeHighlight.opacity(0.5), lineWidth: 5))
            .overlay(shape.stroke(Color.loupeHighlight, lineWidth: 2))
    }
}

/// The note's badge: its number on coral while open, a check on green when done
private struct PracticeBadgeView: View {
    let badge: PracticeBadge

    var body: some View {
        ZStack {
            Circle().fill(badge == .done ? Color.green : Color.loupeBadge)
            Circle().stroke(Color.white, lineWidth: 2)
            switch badge {
            case .numbered(let number):
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 20, height: 20)
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        .accessibilityElement()
        .accessibilityLabel(badge == .done ? "Note 1, done" : "Note 1")
    }
}

// MARK: - Note window (look-alike of the real one)

private struct PracticeNoteWindow: View {
    private enum Field: Hashable {
        case newNote, reply
    }

    let session: PracticeSession
    let element: PracticeElement
    /// Room between the note window's top and the bottom of the stage
    let maxHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var noteText = ""
    @State private var replyText = ""
    @State private var threadHeight: CGFloat = 0
    @FocusState private var focus: Field?

    private var stage: PracticeStage { session.model.stage }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.6)
            if stage == .writingNote {
                newNoteBody
            } else {
                thread
                if stage != .done {
                    Divider().opacity(0.6)
                    composer
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .practiceNoteBackground()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Practice note")
        .onAppear { focusSoon(.newNote) }
        .onChange(of: stage) { _, newStage in
            if newStage == .questionForYou { focusSoon(.reply) }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(element.kindLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(element.nameLine)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let status = session.model.status {
                PracticeStatusLabel(attention: status)
                    .id(status)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: New note

    private var newNoteBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            inputField("What should change?", text: $noteText, lines: 3...6)
                .focused($focus, equals: .newNote)
                .accessibilityLabel("Practice note text")
            HStack {
                Spacer()
                Button("Cancel") { session.cancelNote() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { session.addNote(noteText) }
                    .keyboardShortcut(.defaultAction)
                    .tint(Color.loupeAccentStrong)
                    .disabled(isBlank(noteText))
            }
        }
        .padding(14)
    }

    // MARK: Conversation

    /// Tallest the conversation gets before it scrolls: whatever the stage leaves
    /// after the header and the reply box
    private var maxThreadHeight: CGFloat {
        let chrome: CGFloat = stage == .done ? 54 : 106
        return max(90, maxHeight - chrome)
    }

    private var thread: some View {
        ScrollViewReader { scroller in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(session.model.messages) { message in
                        PracticeMessageBubble(message: message)
                            .id(message.id)
                            .transition(reduceMotion ? .opacity : .offset(y: 8).combined(with: .opacity))
                    }
                    if stage == .noteAdded {
                        Text("No agent has picked this up yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // Growing with a new message is movement: skip it with Reduce Motion
                    if reduceMotion || threadHeight == 0 {
                        threadHeight = height
                    } else {
                        withAnimation(.smooth(duration: 0.25)) { threadHeight = height }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(threadHeight, 1), maxThreadHeight))
            .onChange(of: session.model.messages.count) {
                if let last = session.model.messages.last {
                    scroller.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: Reply box

    private var composer: some View {
        let canAnswer = stage == .questionForYou
        return HStack(alignment: .bottom, spacing: 8) {
            inputField(canAnswer ? "Answer the agent" : "Add more detail", text: $replyText, lines: 1...4)
                .focused($focus, equals: .reply)
                .disabled(!canAnswer)
                .accessibilityLabel("Reply to the agent")
            Button("Send") {
                session.answer(replyText)
                replyText = ""
            }
            .keyboardShortcut(.defaultAction)
            .tint(Color.loupeAccentStrong)
            .disabled(!canAnswer || isBlank(replyText))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Pieces

    private func inputField(_ placeholder: String, text: Binding<String>, lines: ClosedRange<Int>) -> some View {
        TextField(placeholder, text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .tint(Color.loupeAccent)
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

    /// Put the cursor in a text box once it is on screen (and again if the first try is dropped)
    private func focusSoon(_ field: Field) {
        DispatchQueue.main.async {
            focus = field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if focus != field { focus = field }
            }
        }
    }

    private func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One message in the practice conversation: who wrote it, when, and the text
private struct PracticeMessageBubble: View {
    let message: PracticeMessage

    private var isMine: Bool { message.author == .user }
    private var author: String { isMine ? "You" : "Agent" }
    private var time: String { message.time.formatted(date: .omitted, time: .shortened) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(author)
                    .font(.caption.weight(.semibold))
                Text(time)
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.secondary)
            Text(message.text)
                .font(.callout)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(author), \(time): \(message.text)")
    }
}

/// The colored label in the note window's header that says what the note needs
private struct PracticeStatusLabel: View {
    let attention: NoteAttention

    /// The real note window's hues, deepened in light mode so the small text stays readable
    private var color: Color {
        switch attention {
        case .waiting, .agentWorking: .loupeAccentText
        case .questionForYou, .agentReplied: Self.adaptive(light: 0x0A5FD0, dark: 0x4DA3FF)
        case .done: Self.adaptive(light: 0x1B7A34, dark: 0x4CD964)
        case .dismissed: .secondary
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

    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

private extension View {
    /// The note window's surface: Liquid Glass on macOS 26+, a plain window surface before
    @ViewBuilder
    func practiceNoteBackground() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            self
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        }
    }
}

// MARK: - Closing screen

/// One short screen on the two ways real notes reach an agent: Copy, and Agent Link
private struct PracticeFinishView: View {
    let finishLabel: String
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 28)

            LoupeMark()
                .frame(width: 92)

            Text(PracticeCopy.title(for: .finished))
                .font(.title2)
                .fontWeight(.semibold)

            Text(PracticeCopy.body(for: .finished))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 48)

            VStack(spacing: 10) {
                card(icon: "doc.on.doc", title: PracticeCopy.copyTitle, text: PracticeCopy.copyBody)
                card(icon: "bubble.left.and.bubble.right", title: PracticeCopy.agentLinkTitle, text: PracticeCopy.agentLinkBody)
            }
            .padding(.horizontal, 40)
            .padding(.top, 6)

            Spacer(minLength: 28)

            Button {
                onFinish()
            } label: {
                Text(finishLabel)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.loupeAccentStrong)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.horizontal, 60)
            .padding(.bottom, 28)
        }
    }

    private func card(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.loupeAccentText)
                .frame(width: 24, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
    }
}
