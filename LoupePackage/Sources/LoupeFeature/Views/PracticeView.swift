import AppKit
import SwiftUI

// The practice step in setup: a pretend app inside the setup window where a new person
// tries Loupe's loop (point, leave a note, hear back from an agent) before using it for real.
//
// A three-line checklist, the step count and Skip stay in one place at the top while the
// practice app and the note window change underneath. The checklist shows every step, which
// one is next, and the one button that step needs. The outline, badge and note window are
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
                PracticeFinishView(finishLabel: finishLabel, connectedAgent: session.connectedAgent(), onFinish: onFinish)
                    .transition(.opacity)
            } else {
                practice
                    .transition(.opacity)
            }
        }
        .frame(width: 480, height: 620)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.3), value: stage)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .smooth(duration: 0.3), value: session.model.agentHasRead)
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
                if session.model.hasFinishedANote, stage != .done {
                    // One note is done, so moving on is always one click away,
                    // even in the middle of another note
                    Button(PracticeCopy.continueLabel) { session.continueToFinish() }
                        .controlSize(.small)
                        .accessibilityHint("Ends the practice and shows what to do next")
                } else {
                    Button(PracticeCopy.skipLabel, action: onSkip)
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityHint("Ends the practice. Nothing is saved.")
                }
            }
            .frame(height: 20)
            .padding(.top, 10)

            PracticeChecklistView(
                items: checklist,
                onCopyNote: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.model.copiedText, forType: .string)
                    session.copyNote()
                },
                onContinue: { session.continueToFinish() }
            )
                .frame(height: 94, alignment: .top)
                .padding(.top, 8)

            PracticeStageView(session: session)
                .padding(.top, 12)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
    }

    private var checklist: [PracticeChecklistItem] {
        PracticeCopy.checklist(for: session.model, connectedAgent: session.connectedAgent())
    }

    /// Read each new step (and the agent's line, when there is one) to VoiceOver
    private func announce(_ stage: PracticeStage) {
        guard stage != .finished else { return }
        var parts: [String] = []
        if let last = session.model.messages.last, last.author == .agent {
            parts.append("Agent: \(last.text)")
        }
        let step = PracticeCopy.currentStep(for: session.model, connectedAgent: session.connectedAgent())
        parts.append("Step \(session.model.stepNumber) of \(PracticeModel.stepCount). \(step).")
        AccessibilityNotification.Announcement(parts.joined(separator: " ")).post()
    }
}

// MARK: - Checklist

/// The three steps of the practice. Finished ones are ticked, the one to do now is
/// highlighted and holds its button, and the ones still to come are listed plainly.
private struct PracticeChecklistView: View {
    let items: [PracticeChecklistItem]
    let onCopyNote: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(items) { item in
                row(item)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Practice steps")
    }

    private func row(_ item: PracticeChecklistItem) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                marker(item)
                Text(item.text)
                    .font(.callout.weight(item.isCurrent ? .semibold : .regular))
                    .foregroundStyle(item.isCurrent ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .id(item.text)
                    .transition(.opacity)
            }
            // The step reads as one thing; its button stays a button of its own
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(item.id), \(item.isDone ? "done" : item.isCurrent ? "do this now" : "coming up"): \(item.text)")
            Spacer(minLength: 4)
            switch item.action {
            case .copyPhrase(let phrase):
                CopyPhraseButton(phrase: phrase)
            case .copyNote:
                Button(PracticeCopy.copyNoteLabel, action: onCopyNote)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.loupeAccentStrong)
                    .accessibilityHint("Copies your practice note, the way Copy does in Loupe's toolbar")
            case .continuePractice:
                Button(PracticeCopy.continueLabel, action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.loupeAccentStrong)
                    .keyboardShortcut(.defaultAction)
            case nil:
                EmptyView()
            }
        }
        .padding(.horizontal, 8)
        // Every line is the same height, so the list never shifts as the highlight moves
        .frame(height: 30)
        .background {
            if item.isCurrent {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.loupeAccent.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.loupeAccent.opacity(0.75), lineWidth: 1.5)
                    )
            }
        }
    }

    /// A green check when done, the step's number on coral when it is the one to do,
    /// and the number in a plain ring while it is still to come
    @ViewBuilder
    private func marker(_ item: PracticeChecklistItem) -> some View {
        if item.isDone {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color(practiceHex: 0x2E9D55))
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        } else {
            Text("\(item.id)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(item.isCurrent ? Color.white : Color.secondary)
                .frame(width: 18, height: 18)
                .background {
                    if item.isCurrent {
                        Circle().fill(Color.loupeAccentStrong)
                    } else {
                        Circle().stroke(Color.secondary.opacity(0.7), lineWidth: 1.5)
                    }
                }
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Stage: the practice app with Loupe's outline, badge and note window over it

private struct PracticeStageView: View {
    let session: PracticeSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the practice app's page says about itself: what is under the pointer and
    /// where the noted elements are
    @State private var page = PracticePageState()

    private let noteWidth: CGFloat = 340

    var body: some View {
        PracticeAppView(session: session, page: page)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    // The page reports places measured from its own top-left corner,
                    // which sits just under the practice app's title bar
                    let origin = CGPoint(x: 0, y: PracticeAppView.pageTop)
                    ZStack(alignment: .topLeading) {
                        if let element = session.model.outlinedElement, let frame = outlineFrame(for: element) {
                            outline(for: element, frame: frame.offsetBy(dx: origin.x, dy: origin.y), stageWidth: proxy.size.width)
                        }
                        // Earlier notes keep their badges while another note is left
                        ForEach(Array(session.model.badges.keys), id: \.id) { element in
                            if let badge = session.model.badges[element], let frame = page.frames[element.id] {
                                badgeView(badge, frame: frame.offsetBy(dx: origin.x, dy: origin.y))
                            }
                        }
                        if let element = session.model.selected, let frame = page.frames[element.id] {
                            noteLayer(for: element, frame: frame.offsetBy(dx: origin.x, dy: origin.y), stageSize: proxy.size)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
            }
    }

    /// Where to draw the outline: around what is under the pointer, or around the element
    /// a note is being written on
    private func outlineFrame(for element: PracticeElement) -> CGRect? {
        if session.model.stage == .writingNote { return page.frames[element.id] }
        return page.hover?.frame
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
                if frame.maxX + 180 < stageWidth, frame.width > stageWidth * 0.25 {
                    // Room beside it on its own line (the heading): sit there instead of
                    // covering the row underneath
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

    /// A note's badge on its element
    private func badgeView(_ badge: PracticeBadge, frame: CGRect) -> some View {
        PracticeBadgeView(badge: badge)
            .position(x: frame.maxX + 2, y: frame.minY - 2)
            .allowsHitTesting(false)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
    }

    /// The note window below its element
    @ViewBuilder
    private func noteLayer(for element: PracticeElement, frame: CGRect, stageSize: CGSize) -> some View {
        if session.model.isNoteOpen {
            // Below the element, like the real note window, and kept inside the stage
            let x = min(max(frame.midX - noteWidth / 2, 6), stageSize.width - noteWidth - 6)
            let y = min(frame.maxY + 12, stageSize.height - 190)
            PracticeNoteWindow(
                session: session,
                element: element,
                maxHeight: stageSize.height - y
            )
            .frame(width: noteWidth)
            .offset(x: x, y: y)
            // Each note gets a fresh window, so nothing typed for the last one carries over
            .id(session.model.noteRound)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .top).combined(with: .opacity))
        }
    }
}

// MARK: - The practice app

/// A small pretend app window. Its content is a real page (`PracticePageWebView`), so an
/// agent can change anything about it and a person can point at anything on it.
private struct PracticeAppView: View {
    let session: PracticeSession
    let page: PracticePageState

    static let titleBarHeight: CGFloat = 30
    /// Where the page starts, measured from the top of the practice app
    static let pageTop: CGFloat = titleBarHeight + 1

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            PracticePageWebView(session: session, page: page)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
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
        .frame(height: Self.titleBarHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityHidden(true)
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

/// A note's badge: its number on coral while open, a check on green when done,
/// a dash on grey when the agent declined
private struct PracticeBadgeView: View {
    let badge: PracticeBadge

    private var fill: Color {
        switch badge {
        case .numbered: .loupeBadge
        case .done: .green
        case .dismissed: .gray
        }
    }

    private var label: String {
        switch badge {
        case .numbered(let number): "Note \(number)"
        case .done: "Finished note"
        case .dismissed: "Declined note"
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Circle().stroke(Color.white, lineWidth: 2)
            switch badge {
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
            case .dismissed:
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
            case .numbered(let number):
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 20, height: 20)
        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

private extension NSColor {
    convenience init(practiceHex hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private extension Color {
    init(practiceHex hex: Int) {
        self.init(nsColor: NSColor(practiceHex: hex))
    }
}

/// Copies what to say to the person's own agent
private struct CopyPhraseButton: View {
    let phrase: String
    @State private var copied = false

    var body: some View {
        Button(copied ? PracticeCopy.copiedLabel : PracticeCopy.copyPhraseLabel) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(phrase, forType: .string)
            copied = true
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.loupeAccentStrong)
        .help(phrase)
        .accessibilityLabel(copied ? "Copied" : "Copy the phrase: \(phrase)")
        .onChange(of: phrase) { copied = false }
        // "Copied" is a brief confirmation, not a lasting state: the clipboard may hold
        // something else a minute later, so the button goes back to offering the copy
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { copied = false }
        }
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
                if stage == .done || session.model.isLive { Divider().opacity(0.6) }
                if stage == .done {
                    HStack {
                        Spacer()
                        Button(PracticeCopy.leaveAnotherNoteLabel) { session.leaveAnotherNote() }
                            .accessibilityHint("Closes this note. The practice app keeps its changes.")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                } else if session.model.isLive {
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
                // One click fills in a note that fits this element
                Button {
                    noteText = element.suggestedNote
                    focus = .newNote
                } label: {
                    Text("\(PracticeCopy.suggestionPrefix) \(element.suggestedNote)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.loupeAccentText)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.loupeAccent.opacity(0.14)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use the suggested note: \(element.suggestedNote)")
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
        let chrome: CGFloat = 106
        return max(90, maxHeight - chrome)
    }

    /// The small line under the conversation saying what the note is waiting for
    private var caption: String? {
        let model = session.model
        if !model.isLive {
            return stage == .noteAdded ? PracticeCopy.copyHint : nil
        }
        if model.agentIsQuiet { return PracticeCopy.quietAgentHint }
        if stage == .noteAdded, !model.agentHasRead { return PracticeCopy.noAgentYet }
        return nil
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
                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .id(caption)
                            .transition(.opacity)
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
            // The agent's closing line is the payoff. When the note finishes, the room for
            // the conversation changes, so bring that line back into view afterwards.
            .onChange(of: stage) { _, newStage in
                guard newStage == .done, let last = session.model.messages.last else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
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
            return NSColor(practiceHex: isDark ? dark : light)
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
    /// The person's own agent, when one is connected through Agent Link right now
    let connectedAgent: String?
    let onFinish: () -> Void

    private var agentLinkBody: String {
        connectedAgent.map(PracticeCopy.agentLinkConnectedBody(agent:)) ?? PracticeCopy.agentLinkBody
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 28)

            LoupeMark()
                .frame(width: 92)

            Text(PracticeCopy.closingTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Text(PracticeCopy.closingBody)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 48)

            VStack(spacing: 10) {
                card(icon: "doc.on.doc", title: PracticeCopy.copyTitle, text: PracticeCopy.copyBody)
                card(icon: "bubble.left.and.bubble.right", title: PracticeCopy.agentLinkTitle, text: agentLinkBody)
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
