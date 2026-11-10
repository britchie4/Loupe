import Foundation

// The practice step in first-run setup: a pretend app where a new person points at
// something, leaves a note, and watches an agent change the pretend app.
//
// The agent is the person's own, through Agent Link, when one is connected ("live").
// Otherwise a pretend agent with fixed lines plays the part ("scripted"): no model, no network.
//
// Everything here is its own small world. Practice notes are `PracticeMessage` values that
// live only in a `PracticeModel`; nothing in this file knows about `Annotation` or
// `AnnotationStore`, so a practice note can never end up among real notes or on disk.

// MARK: - What can be pointed at

/// The things a person can point at in the practice app
public enum PracticeElement: String, CaseIterable, Identifiable, Sendable {
    case heading
    case reminder
    case saveButton

    public var id: String { rawValue }

    /// The accessibility role a real app would report, so names match the rest of Loupe
    public var role: String {
        switch self {
        case .heading: "AXHeading"
        case .reminder: "AXCheckBox"
        case .saveButton: "AXButton"
        }
    }

    /// The words on the element when the practice starts
    public var title: String {
        switch self {
        case .heading: "Weekend Planner"
        case .reminder: "Remind me on Friday"
        case .saveButton: "Save Plan"
        }
    }

    /// First line of the note window's header, e.g. "Button in Practice App"
    public var kindLine: String {
        "\(ElementKind.name(forRole: role)) in \(PracticeCopy.appName)"
    }

    /// Second line of the note window's header: the words on the element, in quotes
    public var nameLine: String {
        "\u{201C}\(title)\u{201D}"
    }

    /// What VoiceOver reads for the element, with the words it shows right now
    public func accessibilityLabel(showing text: String) -> String {
        "\(text), \(ElementKind.name(forRole: role).lowercased()) in the practice app"
    }

    /// A note that fits this element, offered as a one-click suggestion
    public var suggestedNote: String {
        switch self {
        case .heading: "Make this title blue"
        case .reminder: "Tick this by default"
        case .saveButton: "Make this button bigger"
        }
    }

    /// What the suggested note asks for. Also what the pretend agent falls back to
    /// when it can't make sense of a note.
    public var suggestedChange: PracticeChange {
        switch self {
        case .heading: PracticeChange(color: .blue)
        case .reminder: PracticeChange(checked: true)
        case .saveButton: PracticeChange(size: .bigger)
        }
    }
}

// MARK: - How the practice app looks

public enum PracticeSize: String, CaseIterable, Sendable {
    case smaller
    case normal
    case bigger
    case muchBigger = "much_bigger"

    public var scale: CGFloat {
        switch self {
        case .smaller: 0.82
        case .normal: 1
        case .bigger: 1.3
        case .muchBigger: 1.6
        }
    }
}

public enum PracticeColor: String, CaseIterable, Sendable {
    /// The element's own colour
    case standard = "default"
    case red, orange, yellow, green, blue, purple, pink, gray
}

/// How one element of the practice app looks right now
public struct PracticeLook: Equatable, Sendable {
    public var text: String
    public var size: PracticeSize = .normal
    public var color: PracticeColor = .standard
    public var bold = false
    /// Only the checkbox shows this
    public var checked = false
    /// Taken out of the practice app. Its place stays, so nothing else moves.
    public var removed = false
}

/// A change to an element's look. Anything left nil stays as it is.
public struct PracticeChange: Equatable, Sendable {
    public var text: String?
    public var size: PracticeSize?
    public var color: PracticeColor?
    public var bold: Bool?
    public var checked: Bool?
    /// True takes the element out of the practice app, false puts it back
    public var removed: Bool?

    public init(text: String? = nil, size: PracticeSize? = nil, color: PracticeColor? = nil, bold: Bool? = nil, checked: Bool? = nil, removed: Bool? = nil) {
        self.text = text
        self.size = size
        self.color = color
        self.bold = bold
        self.checked = checked
        self.removed = removed
    }

    public var isEmpty: Bool {
        text == nil && size == nil && color == nil && bold == nil && checked == nil && removed == nil
    }

    /// The parts that make sense on every element (size, colour, weight), without the
    /// parts that belong to one element (its words, its tick, whether it is there at all)
    public var styleOnly: PracticeChange {
        PracticeChange(size: size, color: color, bold: bold)
    }

    /// Longest text an element can be given, so the practice app's layout holds
    public static let maxTextLength = 40

    /// Trim new text to one short line; nil if nothing is left
    public static func cleanedText(_ text: String) -> String? {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxTextLength))
    }
}

// MARK: - Conversation

/// One message in the practice note's conversation
public struct PracticeMessage: Equatable, Identifiable, Sendable {
    public enum Author: String, Equatable, Sendable {
        case user
        case agent
    }

    public let id: Int
    public let author: Author
    public let text: String
    public let time: Date
}

/// What the pretend agent does next, after a short pause
public enum PracticeAgentMove: Equatable, Sendable {
    case askQuestion
    case finish
}

/// The badge drawn on the element once it has a note
public enum PracticeBadge: Equatable, Sendable {
    /// Coral circle with the note's number
    case numbered(Int)
    /// Green circle with a check
    case done
    /// Grey circle: the agent declined the note
    case dismissed
}

// MARK: - Stages

/// Where the person is in the practice
public enum PracticeStage: Equatable, Sendable, CaseIterable {
    /// Pointing at the practice app; nothing chosen yet
    case pointing
    /// The note window is open on an element and the note is being written
    case writingNote
    /// The note is added and nobody has replied yet
    case noteAdded
    /// The agent wrote back and the person can answer
    case questionForYou
    /// The answer is sent and the agent hasn't finished yet
    case answered
    /// The agent finished (or declined) the note
    case done
    /// The closing screen about Copy and Agent Link
    case finished
}

// MARK: - State machine

/// The practice's state and the only ways it can change.
/// Calls that don't fit the current stage do nothing, so neither the view nor an agent
/// can get it into a state that makes no sense (an answer before a question, two notes,
/// a change with no note, and so on).
public struct PracticeModel: Equatable, Sendable {
    public private(set) var stage: PracticeStage = .pointing
    /// The element under the pointer while pointing
    public private(set) var hovered: PracticeElement?
    /// The element the note is attached to
    public private(set) var selected: PracticeElement?
    public private(set) var messages: [PracticeMessage] = []
    /// How each element of the practice app looks right now
    public private(set) var looks: [PracticeElement: PracticeLook]

    /// The connected agent handling the note, by name. Nil when the pretend agent plays the part.
    public private(set) var liveAgent: String?
    /// The live agent has fetched the note since the person last wrote
    public private(set) var agentHasRead = false
    /// The live agent marked the note seen
    public private(set) var agentIsWorking = false
    /// The agent declined the note instead of finishing it
    public private(set) var wasDismissed = false
    /// An agent changed the practice app at least once
    public private(set) var appWasChanged = false
    /// The live agent has made no progress for a while: offer the pretend agent instead
    public private(set) var offersPretendAgent = false

    public init() {
        looks = Dictionary(uniqueKeysWithValues: PracticeElement.allCases.map { ($0, PracticeLook(text: $0.title)) })
    }

    public var isLive: Bool { liveAgent != nil }

    public func look(of element: PracticeElement) -> PracticeLook {
        looks[element] ?? PracticeLook(text: element.title)
    }

    // MARK: Pointing

    /// The pointer (or keyboard focus) moved onto an element
    public mutating func hover(_ element: PracticeElement) {
        guard stage == .pointing else { return }
        hovered = element
    }

    /// The pointer left an element. Ignored if the pointer has already reached another
    /// one, since "entered B" can arrive before "left A".
    public mutating func unhover(_ element: PracticeElement) {
        guard hovered == element else { return }
        hovered = nil
    }

    /// The person clicked an element: open the note window on it
    @discardableResult
    public mutating func select(_ element: PracticeElement) -> Bool {
        guard stage == .pointing else { return false }
        hovered = nil
        selected = element
        stage = .writingNote
        return true
    }

    // MARK: Writing the note

    /// Close the note window without adding the note
    public mutating func cancelNote() {
        guard stage == .writingNote else { return }
        selected = nil
        stage = .pointing
    }

    /// Add the note. Blank text is refused, like in the real note window.
    /// - Parameter liveAgent: the connected agent that will handle it, or nil for the pretend agent
    @discardableResult
    public mutating func addNote(_ text: String, liveAgent: String? = nil, at time: Date = Date()) -> Bool {
        guard stage == .writingNote, let text = Self.cleaned(text) else { return false }
        append(.user, text, at: time)
        self.liveAgent = liveAgent
        stage = .noteAdded
        return true
    }

    /// Answer the agent. Blank text is refused.
    @discardableResult
    public mutating func answer(_ text: String, at time: Date = Date()) -> Bool {
        guard stage == .questionForYou, let text = Self.cleaned(text) else { return false }
        append(.user, text, at: time)
        agentHasRead = false
        agentIsWorking = false
        stage = .answered
        return true
    }

    /// Leave the practice app for the closing screen. The practice note is thrown away.
    @discardableResult
    public mutating func continueToFinish() -> Bool {
        guard stage == .done else { return false }
        messages = []
        selected = nil
        liveAgent = nil
        stage = .finished
        return true
    }

    // MARK: What an agent can do (the person's own agent, or the pretend one)

    /// Whether the note is waiting on an agent
    private var isAgentsTurn: Bool {
        stage == .noteAdded || stage == .answered
    }

    /// Whether there is a note an agent may still act on
    public var hasOpenNote: Bool {
        isAgentsTurn || stage == .questionForYou
    }

    /// The agent fetched the note
    public mutating func agentRead() {
        guard isAgentsTurn else { return }
        agentHasRead = true
        offersPretendAgent = false
    }

    /// The agent said it is working on the note
    @discardableResult
    public mutating func agentMarkedSeen() -> Bool {
        guard hasOpenNote else { return false }
        agentHasRead = true
        agentIsWorking = true
        offersPretendAgent = false
        return true
    }

    /// The agent wrote back without finishing, usually to ask something
    @discardableResult
    public mutating func agentReplied(_ text: String, at time: Date = Date()) -> Bool {
        guard hasOpenNote, let text = Self.cleaned(text) else { return false }
        append(.agent, text, at: time)
        offersPretendAgent = false
        stage = .questionForYou
        return true
    }

    /// The agent changed how elements of the practice app look
    @discardableResult
    public mutating func agentChanged(_ elements: [PracticeElement], _ change: PracticeChange) -> Bool {
        guard hasOpenNote, !elements.isEmpty, !change.isEmpty else { return false }
        for element in elements {
            var look = look(of: element)
            if let text = change.text.flatMap(PracticeChange.cleanedText) { look.text = text }
            if let size = change.size { look.size = size }
            if let color = change.color { look.color = color }
            if let bold = change.bold { look.bold = bold }
            if let checked = change.checked, element == .reminder { look.checked = checked }
            if let removed = change.removed { look.removed = removed }
            looks[element] = look
        }
        appWasChanged = true
        offersPretendAgent = false
        return true
    }

    /// The agent finished the note, or declined it
    @discardableResult
    public mutating func agentFinished(message: String?, dismissed: Bool = false, at time: Date = Date()) -> Bool {
        guard hasOpenNote else { return false }
        if let text = message.flatMap(Self.cleaned) { append(.agent, text, at: time) }
        wasDismissed = dismissed
        agentIsWorking = false
        offersPretendAgent = false
        stage = .done
        return true
    }

    // MARK: Switching from the person's agent to the pretend one

    /// The live agent has said nothing for a while: show the offer to use the pretend agent
    public mutating func offerPretendAgent() {
        guard isLive, isAgentsTurn else { return }
        offersPretendAgent = true
    }

    /// Hand the note to the pretend agent. Real agents can no longer see it.
    @discardableResult
    public mutating func switchToPretendAgent() -> Bool {
        guard isLive, isAgentsTurn else { return false }
        liveAgent = nil
        agentHasRead = false
        agentIsWorking = false
        offersPretendAgent = false
        return true
    }

    // MARK: The pretend agent's script

    /// What the pretend agent will do next, if it is the pretend agent's turn
    public var pendingAgentMove: PracticeAgentMove? {
        guard !isLive else { return nil }
        switch stage {
        case .noteAdded: return .askQuestion
        case .answered: return .finish
        default: return nil
        }
    }

    /// The pretend agent takes its turn: first a question, then the change
    @discardableResult
    public mutating func agentMoves(at time: Date = Date()) -> Bool {
        switch pendingAgentMove {
        case .askQuestion:
            return agentReplied(PracticeCopy.agentQuestion, at: time)
        case .finish:
            guard let element = selected else { return false }
            let note = messages.first { $0.author == .user }?.text ?? ""
            let answer = messages.last { $0.author == .user }?.text ?? ""
            let reading = PracticeInterpreter.reading(of: note, for: element)
            let everywhere = PracticeInterpreter.wantsEverywhere(answer) && !reading.change.styleOnly.isEmpty
            agentChanged([element], reading.change)
            if everywhere {
                agentChanged(PracticeElement.allCases.filter { $0 != element }, reading.change.styleOnly)
            }
            let message = PracticeInterpreter.doneMessage(for: reading, everywhere: everywhere)
            return agentFinished(message: message, at: time)
        case nil:
            return false
        }
    }

    // MARK: What to show

    /// The element drawn with Loupe's outline: under the pointer, or being written about
    public var outlinedElement: PracticeElement? {
        switch stage {
        case .pointing: hovered
        case .writingNote: selected
        default: nil
        }
    }

    /// Whether the note window is open
    public var isNoteOpen: Bool {
        switch stage {
        case .writingNote, .noteAdded, .questionForYou, .answered, .done: true
        case .pointing, .finished: false
        }
    }

    /// The badge on the element, once the note exists
    public var badge: PracticeBadge? {
        switch stage {
        case .noteAdded, .questionForYou, .answered: .numbered(1)
        case .done: wasDismissed ? .dismissed : .done
        case .pointing, .writingNote, .finished: nil
        }
    }

    /// The agent's latest message asks something
    public var agentAskedQuestion: Bool {
        guard let last = messages.last, last.author == .agent else { return false }
        return last.text.contains("?")
    }

    /// The status shown in the note window's header, in the real note window's own words
    public var status: NoteAttention? {
        switch stage {
        case .noteAdded, .answered: agentIsWorking ? .agentWorking : .waiting
        case .questionForYou: agentAskedQuestion ? .questionForYou : .agentReplied
        case .done: wasDismissed ? .dismissed : .done
        case .pointing, .writingNote, .finished: nil
        }
    }

    /// Which of the three practice steps this is: hover, annotate, agent replies
    public var stepNumber: Int {
        switch stage {
        case .pointing: 1
        case .writingNote: 2
        case .noteAdded, .questionForYou, .answered, .done, .finished: 3
        }
    }

    public static let stepCount = 3

    // MARK: Helpers

    private mutating func append(_ author: PracticeMessage.Author, _ text: String, at time: Date) {
        messages.append(PracticeMessage(id: messages.count, author: author, text: text, time: time))
    }

    private static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - The pretend agent's reading of a note

/// How the pretend agent turns a typed note into a change. It only spots a few common
/// words. There is no model behind it, and it says so when it can't make sense of a note.
public enum PracticeInterpreter {

    public struct Reading: Equatable, Sendable {
        public let change: PracticeChange
        /// False when nothing in the note was recognised and the element's suggested change was used
        public let understood: Bool
    }

    /// Phrases that introduce new words for an element, as in "rename it to Trip Planner"
    private static let renameMarkers = [
        "rename it to ", "rename this to ", "rename to ", "call it ", "call this ",
        "change it to ", "change this to ", "change the text to ", "change the title to ",
        "change the label to ", "change the name to ", "change the wording to ",
        "should say ", "make it say ", "make this say ", "to say ", "should read ", "to read ",
    ]

    private static let colorWords: [String: PracticeColor] = [
        "red": .red, "orange": .orange, "yellow": .yellow, "green": .green, "blue": .blue,
        "purple": .purple, "violet": .purple, "pink": .pink, "gray": .gray, "grey": .gray,
    ]

    public static func reading(of note: String, for element: PracticeElement) -> Reading {
        var change = PracticeChange()
        var rest = note

        // New words first, so a name like "Big Plans" isn't also read as "bigger"
        let lowered = note.lowercased()
        if lowered.count == note.count,
           let marker = renameMarkers.compactMap({ lowered.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
            let start = note.index(note.startIndex, offsetBy: lowered.distance(from: lowered.startIndex, to: marker.upperBound))
            let quoteLike = CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}.!").union(.whitespacesAndNewlines)
            let newText = String(note[start...]).trimmingCharacters(in: quoteLike)
            if let cleaned = PracticeChange.cleanedText(newText) {
                change.text = cleaned
                rest = String(note[..<start])
            }
        }

        let text = spacedWords(rest)
        func has(_ phrases: String...) -> Bool {
            phrases.contains { text.contains(" \($0) ") }
        }

        // "Delete this" is one of the first things people try. Taking the tick off a
        // checkbox is not removing the checkbox.
        let aboutTheTick = element == .reminder && has("remove the tick", "remove the check", "remove the checkmark", "remove tick", "remove check")
        if !aboutTheTick, has("delete", "remove", "hide", "get rid", "take out", "take away", "take this out", "drop", "lose", "gone") {
            return Reading(change: PracticeChange(removed: true), understood: true)
        }

        if has("much bigger", "way bigger", "a lot bigger", "much larger", "huge", "giant", "massive", "enormous") {
            change.size = .muchBigger
        } else if has("bigger", "larger", "big", "large", "increase", "grow", "taller", "wider", "enlarge") {
            change.size = .bigger
        } else if has("smaller", "small", "tiny", "shrink", "reduce", "little", "compact", "less big") {
            change.size = .smaller
        }

        for (word, color) in colorWords where has(word) {
            change.color = color
            break
        }

        if has("bold", "bolder", "heavier", "thicker", "strong", "stronger", "stand out", "pop", "emphasis", "emphasize", "prominent") {
            change.bold = true
        }

        if element == .reminder {
            if aboutTheTick || has("uncheck", "unchecked", "untick", "unticked", "turn off", "off by default", "disable", "disabled", "deselect") {
                change.checked = false
            } else if has("check", "checked", "tick", "ticked", "turn on", "on by default", "enable", "enabled", "select", "selected") {
                change.checked = true
            }
        }

        if change.isEmpty {
            return Reading(change: element.suggestedChange, understood: false)
        }
        return Reading(change: change, understood: true)
    }

    /// Lowercased words with single spaces between and around them (" make it bigger "),
    /// so whole words and phrases can be looked for
    private static func spacedWords(_ text: String) -> String {
        let letters = String(text.lowercased().map { $0.isLetter ? $0 : " " })
        return " " + letters.split(separator: " ").joined(separator: " ") + " "
    }

    /// Whether an answer to "Only here, or everywhere this appears?" means everywhere
    public static func wantsEverywhere(_ answer: String) -> Bool {
        let text = spacedWords(answer)
        let onlyHere = ["only here", "just here", "only this", "just this", "not every", "not all", "here only", "this one"]
        if onlyHere.contains(where: { text.contains(" \($0)") }) { return false }
        return ["everywhere", "everything", "every", "all", "both", "all of them"].contains { text.contains(" \($0) ") }
    }

    /// The pretend agent's closing line, saying exactly what it changed
    public static func doneMessage(for reading: Reading, everywhere: Bool) -> String {
        let change = reading.change
        let target = everywhere ? "everything" : "it"
        var parts: [String] = []
        if let removed = change.removed { parts.append(removed ? "removed it" : "put it back") }
        if let text = change.text { parts.append("renamed it to \u{201C}\(text)\u{201D}") }
        switch change.size {
        case .muchBigger: parts.append("made \(target) much bigger")
        case .bigger: parts.append("made \(target) bigger")
        case .smaller: parts.append("made \(target) smaller")
        case .normal: parts.append("put \(target) back to its normal size")
        case nil: break
        }
        if let color = change.color {
            parts.append(color == .standard ? "put \(target) back to its own color" : "turned \(target) \(color.rawValue)")
        }
        if let bold = change.bold { parts.append(bold ? "made \(target) bold" : "made \(target) lighter") }
        if let checked = change.checked { parts.append(checked ? "ticked it" : "unticked it") }

        let list: String
        switch parts.count {
        case 0: list = "left it as it was"
        case 1: list = parts[0]
        default: list = parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }

        if reading.understood {
            return "Done. I \(list)."
        }
        return "I'm a practice agent and only know a few tricks, so I \(list). Your own agent will do what you ask."
    }
}

// MARK: - Words

/// Every word the practice shows, in one place so it can be checked (no em dashes)
public enum PracticeCopy {
    public static let appName = "Practice App"

    /// The pretend agent's question. It is written to fit any note on any element.
    public static let agentQuestion = "Sure. Only here, or everywhere this appears?"

    /// What the person says to their own agent to send it to Loupe
    public static let agentPrompt = "Check my Loupe notes"
    public static let agentFollowUp = "I answered in Loupe"

    public static let copyPhraseLabel = "Copy Phrase"
    public static let copiedLabel = "Copied"
    public static let suggestionPrefix = "Try:"
    public static let skipLabel = "Skip practice"
    public static let continueLabel = "Continue"
    public static let usePretendAgentLabel = "Use the practice agent instead"
    public static let noAgentYet = "No agent has picked this up yet."

    public static func stepLabel(_ number: Int) -> String {
        "Practice \u{00B7} Step \(number) of \(PracticeModel.stepCount)"
    }

    /// The instruction title for where the practice is
    public static func title(for model: PracticeModel) -> String {
        switch model.stage {
        case .pointing: "Point at anything"
        case .writingNote: "Say what should change"
        case .noteAdded:
            if model.isLive { model.agentHasRead ? "Your agent is on it" : "Now ask your agent" } else { "Your note is pinned" }
        case .questionForYou:
            model.agentAskedQuestion ? "Your agent has a question" : "Your agent replied"
        case .answered:
            model.isLive && model.agentHasRead ? "Your agent is on it" : "Answer sent"
        case .done:
            if model.wasDismissed { "Your agent passed on this one" } else { model.isLive ? "Your agent made the change" : "That's the whole loop" }
        case .finished: "You're ready"
        }
    }

    /// The instruction text for where the practice is
    public static func body(for model: PracticeModel) -> String {
        let agent = model.liveAgent ?? "your agent"
        switch model.stage {
        case .pointing:
            return "Move your pointer over the practice app. Loupe outlines what you point at. Click to leave a note."
        case .writingNote:
            return "Type a note for your coding agent, or use the suggestion. Then click Add."
        case .noteAdded:
            if model.isLive {
                return model.agentHasRead
                    ? "Your note reached \(agent). Its reply and the change show up right here."
                    : "Loupe never interrupts your agent. Switch to \(agent) and say \u{201C}\(agentPrompt)\u{201D}."
            }
            return "The numbered badge marks the spot. With Agent Link, your coding agent picks the note up from here."
        case .questionForYou:
            if model.isLive {
                return "Type an answer and click Send. Then tell \(agent) you answered."
            }
            return "This reply is scripted for practice. With Agent Link, your own agent asks here. Type an answer and click Send."
        case .answered:
            if model.isLive {
                return model.agentHasRead
                    ? "Your answer reached \(agent). The change shows up right here."
                    : "Switch to \(agent) and say \u{201C}\(agentFollowUp)\u{201D}. It reads your answer from Loupe."
            }
            return "Your answer goes straight back to your agent. No copying, no switching windows."
        case .done:
            if model.wasDismissed {
                return "Agents can decline a note and say why. Nothing in the practice app changed."
            }
            return model.isLive
                ? "That change came from \(agent), which also marked your note done. In your own app, it changes the code."
                : "The practice app changed and the badge turned green. Your own agent does this in your real app."
        case .finished:
            return "Your practice note is gone. Real notes reach your agent in one of two ways."
        }
    }

    // Closing screen
    public static let copyTitle = "Copy and paste"
    public static let copyBody = "Click Copy in Loupe's toolbar, then paste your notes into Claude Code, Cursor, Codex, or any coding agent."
    public static let agentLinkTitle = "Agent Link"
    public static let agentLinkBody = "Skip the pasting. Turn on Agent Link in Settings, and your agent reads your notes and replies right in Loupe."

    /// The Agent Link card for someone whose own agent is already connected: nothing left to turn on
    public static func agentLinkConnectedBody(agent: String) -> String {
        "Skip the pasting. Agent Link is on, so leave your notes and tell \(agent) \u{201C}\(agentPrompt)\u{201D}. It replies right in Loupe."
    }

    // Connecting an agent before the practice
    public static let connectTitle = "Connect your coding agent"
    public static let connectBody = "With Agent Link, your agent reads your notes and replies right in Loupe. Connect it now and it joins the practice for real."
    public static let connectStepOne = "Turn on Agent Link"
    public static let connectStepOneDetail = "Agents can read your notes and look at the app you picked. They can never click or type."
    public static let connectStepTwo = "Add Loupe to your agent"
    public static let connectStepThree = "Start a new session in your agent"
    public static let connectWaiting = "Waiting for your agent to connect."
    public static let connectOff = "Turn on Agent Link first."
    public static let practiceWithoutAgent = "Practice Without an Agent"
    public static let connectFootnote = "Without an agent, a practice agent with scripted replies plays the part."

    /// How an agent is named in sentences. Agents that don't introduce themselves are "your agent".
    public static func displayName(forAgent name: String) -> String {
        name.isEmpty || name == "Agent" ? "your agent" : name
    }

    public static func connected(_ agents: [String]) -> String {
        "Connected: \(agents.joined(separator: ", "))"
    }

    public static func practiceWith(_ agent: String) -> String {
        "Practice with \(agent)"
    }

    /// Everything fixed above, for checks that apply to all user-facing words
    public static var fixedStrings: [String] {
        var strings = [
            appName, agentQuestion, agentPrompt, agentFollowUp, skipLabel, continueLabel,
            usePretendAgentLabel, noAgentYet, copyPhraseLabel, copiedLabel, suggestionPrefix,
            copyTitle, copyBody, agentLinkTitle, agentLinkBody,
            connectTitle, connectBody, connectStepOne, connectStepOneDetail, connectStepTwo,
            connectStepThree, connectWaiting, connectOff, practiceWithoutAgent, connectFootnote,
            connected(["Claude Code"]), practiceWith("Claude Code"), agentLinkConnectedBody(agent: "Claude Code"),
        ]
        strings += (1...PracticeModel.stepCount).map(stepLabel)
        for element in PracticeElement.allCases {
            strings += [element.title, element.kindLine, element.nameLine, element.suggestedNote]
        }
        return strings
    }
}
