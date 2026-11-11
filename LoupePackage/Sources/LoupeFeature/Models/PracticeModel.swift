import Foundation

// The practice step in first-run setup: a pretend app where a new person points at
// something, leaves a note, and sees what happens to it next.
//
// With the person's own agent connected through Agent Link ("live"), that agent picks the
// note up, changes the practice app and marks the note done. Without one, the practice is
// what such a person does for real: leave a note, then copy it for their agent. Nothing
// here pretends to be an agent.
//
// Everything here is its own small world. Practice notes are `PracticeMessage` values that
// live only in a `PracticeModel`; nothing in this file knows about `Annotation` or
// `AnnotationStore`, so a practice note can never end up among real notes or on disk.

// MARK: - What can be pointed at

/// Something a person can point at in the practice app. The practice app is a small real
/// page, so this can be anything on it: the three things it starts with, or whatever an
/// agent has added since.
public struct PracticeElement: Hashable, Identifiable, Sendable {
    /// How the element is found on the page: its `id` attribute, or the `data-loupe-key`
    /// Loupe gave it when it was first picked
    public let id: String
    /// The accessibility role a real app would report, so names match the rest of Loupe
    public let role: String
    /// The words on the element when it was pointed at
    public let title: String

    public init(id: String, role: String, title: String) {
        self.id = id
        self.role = role
        self.title = title
    }

    /// The three things the practice app starts with
    public static let heading = PracticeElement(id: "heading", role: "AXHeading", title: "Weekend Planner")
    public static let reminder = PracticeElement(id: "reminder", role: "AXCheckBox", title: "Remind me on Friday")
    public static let saveButton = PracticeElement(id: "saveButton", role: "AXButton", title: "Save Plan")
    public static let allCases: [PracticeElement] = [.heading, .reminder, .saveButton]

    public var rawValue: String { id }

    // Two values name the same element when they point at the same place on the page,
    // even if its words have changed since
    public static func == (lhs: PracticeElement, rhs: PracticeElement) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public var isCheckbox: Bool { role == "AXCheckBox" }

    /// First line of the note window's header, e.g. "Button in Practice App"
    public var kindLine: String {
        "\(ElementKind.name(forRole: role)) in \(PracticeCopy.appName)"
    }

    /// Second line of the note window's header: the words on the element, in quotes
    public var nameLine: String {
        title.isEmpty ? ElementKind.name(forRole: role) : "\u{201C}\(title)\u{201D}"
    }

    /// What VoiceOver reads for the element, with the words it shows right now
    public func accessibilityLabel(showing text: String) -> String {
        "\(text), \(ElementKind.name(forRole: role).lowercased()) in the practice app"
    }

    /// A note that fits this element, offered as a one-click suggestion
    public var suggestedNote: String {
        switch role {
        case "AXHeading": "Make this title blue"
        case "AXCheckBox": "Tick this by default"
        case "AXButton": "Make this button bigger"
        default: "Make this bigger"
        }
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
    /// The practice app's page, as HTML: what it starts as, or what a connected agent last wrote
    public private(set) var pageHTML = PracticePage.startingHTML

    /// The connected agent handling the note, by name. Nil when no agent is connected and the note is copied instead.
    public private(set) var liveAgent: String?
    /// The live agent has fetched the note since the person last wrote
    public private(set) var agentHasRead = false
    /// The live agent marked the note seen
    public private(set) var agentIsWorking = false
    /// The agent declined the note instead of finishing it
    public private(set) var wasDismissed = false
    /// An agent changed the practice app at least once
    public private(set) var appWasChanged = false
    /// The live agent has made no progress for a while, so the person is reminded how to reach it
    public private(set) var agentIsQuiet = false
    /// The note was copied for an agent (the way without Agent Link) instead of being picked up by one
    public private(set) var wasCopied = false

    /// Badges left by earlier notes in this practice. The person can leave as many notes
    /// as they like, one at a time, and the practice app keeps every change.
    public private(set) var finishedNotes: [PracticeElement: PracticeBadge] = [:]
    /// The current note's number: 1 for the first note, 2 for the next, and so on
    public private(set) var noteNumber = 0
    /// Goes up each time a note is put away, so the note window starts fresh for the next one
    public private(set) var noteRound = 0

    public init() {}

    public var isLive: Bool { liveAgent != nil }

    /// At least one note has been finished (or declined), so the person may move on any time
    public var hasFinishedANote: Bool { stage == .done || !finishedNotes.isEmpty }

    /// Whether elements of the practice app can be pointed at and clicked right now:
    /// at the start, and again once a note is finished
    public var canPickElement: Bool { stage == .pointing || stage == .done }

    // MARK: Pointing

    /// The pointer (or keyboard focus) moved onto an element
    public mutating func hover(_ element: PracticeElement) {
        guard canPickElement else { return }
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
        guard canPickElement else { return false }
        if stage == .done { putNoteAway() }
        hovered = nil
        selected = element
        stage = .writingNote
        return true
    }

    /// Close the finished note to leave another one. Its badge stays on the element.
    @discardableResult
    public mutating func leaveAnotherNote() -> Bool {
        guard stage == .done else { return false }
        putNoteAway()
        stage = .pointing
        return true
    }

    /// The finished note leaves its badge behind and everything about it is cleared.
    /// The practice app keeps the changes that were made for it.
    private mutating func putNoteAway() {
        if let selected, let badge { finishedNotes[selected] = badge }
        selected = nil
        hovered = nil
        messages = []
        liveAgent = nil
        agentHasRead = false
        agentIsWorking = false
        wasDismissed = false
        appWasChanged = false
        agentIsQuiet = false
        wasCopied = false
        noteRound += 1
    }

    // MARK: Writing the note

    /// Close the note window without adding the note
    public mutating func cancelNote() {
        guard stage == .writingNote else { return }
        selected = nil
        stage = .pointing
    }

    /// Add the note. Blank text is refused, like in the real note window.
    /// - Parameter liveAgent: the connected agent that will handle it, or nil when none is connected and the note will be copied
    @discardableResult
    public mutating func addNote(_ text: String, liveAgent: String? = nil, at time: Date = Date()) -> Bool {
        guard stage == .writingNote, let text = Self.cleaned(text) else { return false }
        append(.user, text, at: time)
        self.liveAgent = liveAgent
        noteNumber += 1
        // A new note on an element takes the place of that element's earlier badge
        if let selected { finishedNotes[selected] = nil }
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

    /// Leave the practice app for the closing screen. The practice notes are thrown away.
    /// Allowed as soon as one note has been finished, even in the middle of another.
    @discardableResult
    public mutating func continueToFinish() -> Bool {
        guard stage != .finished, hasFinishedANote else { return false }
        putNoteAway()
        finishedNotes = [:]
        stage = .finished
        return true
    }

    // MARK: Without an agent: copy the note

    /// The person copied the note for their agent, which is how notes travel without
    /// Agent Link. That is the whole loop for them, so the note counts as finished.
    @discardableResult
    public mutating func copyNote() -> Bool {
        guard stage == .noteAdded, !isLive else { return false }
        wasCopied = true
        stage = .done
        return true
    }

    /// The note as it is copied: what it is on, and what it asks for
    public var copiedText: String {
        guard let selected, let request = messages.first?.text else { return "" }
        return "Loupe practice note \(noteNumber)\n\(selected.kindLine): \(selected.nameLine)\nRequest: \(request)"
    }

    // MARK: What a connected agent can do

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
        agentIsQuiet = false
    }

    /// The agent said it is working on the note
    @discardableResult
    public mutating func agentMarkedSeen() -> Bool {
        guard hasOpenNote else { return false }
        agentHasRead = true
        agentIsWorking = true
        agentIsQuiet = false
        return true
    }

    /// The agent wrote back without finishing, usually to ask something
    @discardableResult
    public mutating func agentReplied(_ text: String, at time: Date = Date()) -> Bool {
        guard hasOpenNote, let text = Self.cleaned(text) else { return false }
        append(.agent, text, at: time)
        agentIsQuiet = false
        stage = .questionForYou
        return true
    }

    /// A connected agent rewrote the practice app's page. Anything HTML and CSS can say is
    /// allowed (see `PracticePage.cleaned`).
    @discardableResult
    public mutating func agentRewrotePage(_ html: String) -> Bool {
        guard hasOpenNote, let html = PracticePage.cleaned(html) else { return false }
        pageHTML = html
        appWasChanged = true
        agentIsQuiet = false
        return true
    }

    /// The agent finished the note, or declined it
    @discardableResult
    public mutating func agentFinished(message: String?, dismissed: Bool = false, at time: Date = Date()) -> Bool {
        guard hasOpenNote else { return false }
        if let text = message.flatMap(Self.cleaned) { append(.agent, text, at: time) }
        wasDismissed = dismissed
        agentIsWorking = false
        agentIsQuiet = false
        stage = .done
        return true
    }

    /// The live agent has said nothing for a while
    public mutating func agentWentQuiet() {
        guard isLive, isAgentsTurn else { return }
        agentIsQuiet = true
    }

    // MARK: What to show

    /// The element drawn with Loupe's outline: under the pointer, or being written about
    public var outlinedElement: PracticeElement? {
        switch stage {
        case .pointing, .done: hovered
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

    /// The badge on the current note's element, once the note exists
    public var badge: PracticeBadge? {
        switch stage {
        case .noteAdded, .questionForYou, .answered: .numbered(noteNumber)
        // A copied note is still waiting on an agent, so it keeps its number
        case .done: wasCopied ? .numbered(noteNumber) : (wasDismissed ? .dismissed : .done)
        case .pointing, .writingNote, .finished: nil
        }
    }

    /// Every badge to draw: earlier notes' badges, and the current note's on its element
    public var badges: [PracticeElement: PracticeBadge] {
        var all = finishedNotes
        if let selected, let badge { all[selected] = badge }
        return all
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
        case .done: wasCopied ? .waiting : (wasDismissed ? .dismissed : .done)
        case .pointing, .writingNote, .finished: nil
        }
    }

    /// Which of the checklist's three steps this is: leave a note, get it to the agent
    /// (tell your connected agent, or copy it), then watch the change or paste the note
    public var stepNumber: Int {
        switch stage {
        case .pointing, .writingNote: 1
        case .noteAdded: isLive && agentHasRead ? 3 : 2
        case .questionForYou: isLive ? 3 : 2
        case .answered, .done, .finished: 3
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

// MARK: - Checklist

/// One line of the checklist at the top of the practice. It replaces a paragraph of
/// instructions: the person sees all three steps, which one they are on, and the one
/// button that step needs.
public struct PracticeChecklistItem: Equatable, Identifiable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Copy what to say to the person's own agent
        case copyPhrase(String)
        /// Copy the note itself, for pasting into an agent
        case copyNote
        /// Go on to the closing screen
        case continuePractice
    }

    /// 1, 2 or 3
    public let id: Int
    public let text: String
    /// Shown with a check mark
    public let isDone: Bool
    /// The step to do now. It is highlighted and holds the action, if there is one.
    public let isCurrent: Bool
    public let action: Action?
}

// MARK: - Words

/// Every word the practice shows, in one place so it can be checked (no em dashes)
public enum PracticeCopy {
    public static let appName = "Practice App"

    /// What the person says to their own agent to send it to Loupe
    public static let agentPrompt = "Check my Loupe notes"
    public static let agentFollowUp = "I answered in Loupe"

    public static let copyPhraseLabel = "Copy Phrase"
    public static let copiedLabel = "Copied"
    public static let suggestionPrefix = "Try:"
    public static let skipLabel = "Skip practice"
    public static let continueLabel = "Continue"
    public static let noAgentYet = "No agent has picked this up yet."
    public static let copyNoteLabel = "Copy Note"
    /// Under a note when no agent is connected
    public static let copyHint = "Copy puts this note on your clipboard, ready to paste into your agent."
    /// Under a note when the connected agent has been quiet for a while
    public static let quietAgentHint = "Still waiting. Open a new chat in your agent and say \u{201C}\(agentPrompt)\u{201D}."

    public static func stepLabel(_ number: Int) -> String {
        "Practice \u{00B7} Step \(number) of \(PracticeModel.stepCount)"
    }

    /// The three checklist lines for where the practice is.
    /// - Parameter connectedAgent: the person's own agent if one is connected right now.
    ///   Before a note exists, it decides whether the list talks about that agent or the practice one.
    public static func checklist(for model: PracticeModel, connectedAgent: String? = nil) -> [PracticeChecklistItem] {
        let noteExists = model.stage != .pointing && model.stage != .writingNote
        let agent = noteExists ? model.liveAgent : connectedAgent
        let current = model.stepNumber
        let allDone = model.stage == .done || model.stage == .finished

        func item(_ number: Int, _ text: String, action: PracticeChecklistItem.Action? = nil) -> PracticeChecklistItem {
            PracticeChecklistItem(
                id: number,
                text: text,
                isDone: allDone || number < current,
                isCurrent: number == current,
                action: number == current ? action : nil
            )
        }

        // 1. Leave a note
        let first: String
        switch model.stage {
        case .pointing: first = model.hasFinishedANote ? "Click something else to leave another note" : "Click something in the practice app"
        case .writingNote: first = "Say what should change, then click Add"
        default: first = "Leave a note"
        }

        // 2. Get the note to the agent
        let second: String
        var secondAction: PracticeChecklistItem.Action?
        if let agent {
            if current == 2 {
                second = "Tell \(agent) \u{201C}\(agentPrompt)\u{201D}"
                secondAction = .copyPhrase(agentPrompt)
            } else {
                second = "Tell \(agent) to check your notes"
            }
        } else {
            second = "Copy your note"
            if current == 2 { secondAction = .copyNote }
        }

        // 3. Watch the change
        var third = agent == nil ? "Paste it into your coding agent" : "Watch the practice app change"
        var thirdAction: PracticeChecklistItem.Action?
        if allDone {
            if model.wasCopied {
                third = "Copied. Paste it into your agent, or continue"
            } else {
                third = model.wasDismissed ? "No change this time. Try another, or continue" : "It changed. Leave another note, or continue"
            }
            if model.stage == .done { thirdAction = .continuePractice }
        } else if current == 3, let agent {
            switch model.stage {
            case .questionForYou:
                third = model.agentAskedQuestion ? "Answer \(agent) in the note" : "Read the reply from \(agent) in the note"
            case .answered where !model.agentHasRead:
                third = "Tell \(agent) \u{201C}\(agentFollowUp)\u{201D}"
                thirdAction = .copyPhrase(agentFollowUp)
            default:
                third = "Watch the practice app: \(agent) is on it"
            }
        }

        var items = [item(1, first), item(2, second, action: secondAction), item(3, third, action: thirdAction)]
        // When everything is ticked, the last line is still the one to act on
        if model.stage == .done {
            items[2] = PracticeChecklistItem(id: 3, text: third, isDone: true, isCurrent: true, action: thirdAction)
        }
        return items
    }

    /// The line to act on now, for reading out
    public static func currentStep(for model: PracticeModel, connectedAgent: String? = nil) -> String {
        checklist(for: model, connectedAgent: connectedAgent).first { $0.isCurrent }?.text ?? ""
    }

    public static let leaveAnotherNoteLabel = "Leave Another Note"
    public static let closingTitle = "You're ready"
    public static let closingBody = "Your practice notes are gone. Real notes reach your agent in one of two ways."

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
    public static let connectFootnote = "Without an agent, you practice leaving a note and copying it."

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
            appName, agentPrompt, agentFollowUp, skipLabel, continueLabel,
            noAgentYet, copyNoteLabel, copyHint, quietAgentHint, copyPhraseLabel, copiedLabel, suggestionPrefix,
            leaveAnotherNoteLabel, closingTitle, closingBody,
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
