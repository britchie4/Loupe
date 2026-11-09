import Foundation

// The practice step in first-run setup: a pretend app where a new person points at
// something, leaves a note, and has a short scripted conversation with a pretend agent.
//
// Everything here is its own small world. Practice notes are `PracticeMessage` values that
// live only in a `PracticeModel`; nothing in this file knows about `Annotation` or
// `AnnotationStore`, so a practice note can never end up among real notes, on disk, or in
// front of a real agent. The agent's lines are fixed text: no model and no network.

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

    /// The words shown on the element
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

    /// What VoiceOver reads for the element in the practice app
    public var accessibilityLabel: String {
        "\(title), \(ElementKind.name(forRole: role).lowercased()) in the practice app"
    }
}

// MARK: - Conversation

/// One message in the practice note's conversation
public struct PracticeMessage: Equatable, Identifiable, Sendable {
    public enum Author: Equatable, Sendable {
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
    /// The agent asked something and is waiting for an answer
    case questionForYou
    /// The answer is sent and the agent hasn't finished yet
    case answered
    /// The agent finished the change
    case done
    /// The closing screen about Copy and Agent Link
    case finished
}

// MARK: - State machine

/// The practice's state and the only ways it can change.
/// Calls that don't fit the current stage do nothing, so the view can't get it into a
/// state that makes no sense (an answer before a question, two notes, and so on).
public struct PracticeModel: Equatable, Sendable {
    public private(set) var stage: PracticeStage = .pointing
    /// The element under the pointer while pointing
    public private(set) var hovered: PracticeElement?
    /// The element the note is attached to
    public private(set) var selected: PracticeElement?
    public private(set) var messages: [PracticeMessage] = []

    public init() {}

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
    @discardableResult
    public mutating func addNote(_ text: String, at time: Date = Date()) -> Bool {
        guard stage == .writingNote, let text = Self.cleaned(text) else { return false }
        append(.user, text, at: time)
        stage = .noteAdded
        return true
    }

    // MARK: The agent's turn

    /// What the pretend agent will do next, if it is the agent's turn
    public var pendingAgentMove: PracticeAgentMove? {
        switch stage {
        case .noteAdded: .askQuestion
        case .answered: .finish
        default: nil
        }
    }

    /// The pretend agent takes its turn with its scripted line
    @discardableResult
    public mutating func agentMoves(at time: Date = Date()) -> Bool {
        switch pendingAgentMove {
        case .askQuestion:
            append(.agent, PracticeCopy.agentQuestion, at: time)
            stage = .questionForYou
            return true
        case .finish:
            append(.agent, PracticeCopy.agentDone, at: time)
            stage = .done
            return true
        case nil:
            return false
        }
    }

    // MARK: Answering and finishing

    /// Answer the agent's question. Blank text is refused.
    @discardableResult
    public mutating func answer(_ text: String, at time: Date = Date()) -> Bool {
        guard stage == .questionForYou, let text = Self.cleaned(text) else { return false }
        append(.user, text, at: time)
        stage = .answered
        return true
    }

    /// Leave the practice app for the closing screen. The practice note is thrown away.
    @discardableResult
    public mutating func continueToFinish() -> Bool {
        guard stage == .done else { return false }
        messages = []
        selected = nil
        stage = .finished
        return true
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
        case .done: .done
        case .pointing, .writingNote, .finished: nil
        }
    }

    /// The status shown in the note window's header, in the real note window's own words
    public var status: NoteAttention? {
        switch stage {
        case .noteAdded, .answered: .waiting
        case .questionForYou: .questionForYou
        case .done: .done
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

// MARK: - Words

/// Every word the practice shows, in one place so it can be checked (no em dashes)
public enum PracticeCopy {
    public static let appName = "Practice App"

    // The pretend agent's scripted lines. They are written to fit any note on any element.
    public static let agentQuestion = "Sure. Only here, or everywhere this appears?"
    public static let agentDone = "Done. Have a look when you're ready."

    public static let skipLabel = "Skip practice"
    public static let continueLabel = "Continue"

    public static func stepLabel(_ number: Int) -> String {
        "Practice \u{00B7} Step \(number) of \(PracticeModel.stepCount)"
    }

    /// The instruction title for a stage
    public static func title(for stage: PracticeStage) -> String {
        switch stage {
        case .pointing: "Point at anything"
        case .writingNote: "Say what should change"
        case .noteAdded: "Your note is pinned"
        case .questionForYou: "Your agent has a question"
        case .answered: "Answer sent"
        case .done: "That's the whole loop"
        case .finished: "You're ready"
        }
    }

    /// The instruction text for a stage
    public static func body(for stage: PracticeStage) -> String {
        switch stage {
        case .pointing:
            "Move your pointer over the practice app. Loupe outlines what you point at. Click to leave a note."
        case .writingNote:
            "Type a note for your coding agent. Anything works, like \u{201C}make this bigger\u{201D}. Then click Add."
        case .noteAdded:
            "The numbered badge marks the spot. With Agent Link, your coding agent picks the note up from here."
        case .questionForYou:
            "This reply is scripted for practice. With Agent Link, your own agent asks here. Type an answer and click Send."
        case .answered:
            "Your answer goes straight back to your agent. No copying, no switching windows."
        case .done:
            "The badge turns green when your agent finishes the change."
        case .finished:
            "Your practice note is gone. Real notes reach your agent in one of two ways."
        }
    }

    // Closing screen
    public static let copyTitle = "Copy and paste"
    public static let copyBody = "Click Copy in Loupe's toolbar, then paste your notes into Claude Code, Cursor, Codex, or any coding agent."
    public static let agentLinkTitle = "Agent Link"
    public static let agentLinkBody = "Skip the pasting. Turn on Agent Link in Settings, and your agent reads your notes and replies right in Loupe."

    /// Everything above, for checks that apply to all user-facing words
    public static var allStrings: [String] {
        var strings = [
            appName, agentQuestion, agentDone, skipLabel, continueLabel,
            copyTitle, copyBody, agentLinkTitle, agentLinkBody
        ]
        strings += (1...PracticeModel.stepCount).map(stepLabel)
        for stage in PracticeStage.allCases {
            strings.append(title(for: stage))
            strings.append(body(for: stage))
        }
        for element in PracticeElement.allCases {
            strings += [element.title, element.kindLine, element.nameLine, element.accessibilityLabel]
        }
        return strings
    }
}
