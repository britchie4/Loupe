import Foundation

// MARK: - Plain-language element names

/// Turns raw accessibility roles into words a person would use ("AXPopUpButton" → "Menu")
public enum ElementKind {
    private static let names: [String: String] = [
        "AXButton": "Button",
        "AXPopUpButton": "Menu",
        "AXMenuButton": "Menu button",
        "AXMenu": "Menu",
        "AXMenuItem": "Menu item",
        "AXMenuBarItem": "Menu bar item",
        "AXStaticText": "Text",
        "AXTextField": "Text field",
        "AXTextArea": "Text area",
        "AXSearchField": "Search field",
        "AXSecureTextField": "Password field",
        "AXComboBox": "Combo box",
        "AXCheckBox": "Checkbox",
        "AXRadioButton": "Option",
        "AXRadioGroup": "Option group",
        "AXSegmentedControl": "Segmented control",
        "AXSlider": "Slider",
        "AXIncrementor": "Stepper",
        "AXImage": "Image",
        "AXLink": "Link",
        "AXHeading": "Heading",
        "AXTable": "Table",
        "AXOutline": "List",
        "AXList": "List",
        "AXRow": "Row",
        "AXCell": "Cell",
        "AXColumn": "Column",
        "AXGroup": "Group",
        "AXScrollArea": "Scroll area",
        "AXScrollBar": "Scroll bar",
        "AXSplitGroup": "Split view",
        "AXSplitter": "Divider",
        "AXToolbar": "Toolbar",
        "AXTabGroup": "Tabs",
        "AXTab": "Tab",
        "AXWindow": "Window",
        "AXSheet": "Sheet",
        "AXDrawer": "Drawer",
        "AXProgressIndicator": "Progress bar",
        "AXBusyIndicator": "Spinner",
        "AXDisclosureTriangle": "Disclosure arrow",
        "AXColorWell": "Color picker",
        "AXDateField": "Date field",
        "AXWebArea": "Web page",
        "AXValueIndicator": "Slider handle",
        "AXLevelIndicator": "Level indicator"
    ]

    /// A short, capitalized name for a role. Unknown roles are split into words ("AXFooBar" → "Foo bar").
    public static func name(forRole role: String) -> String {
        if let known = names[role] { return known }
        let bare = role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
        guard !bare.isEmpty else { return "Element" }
        var words: [String] = []
        var current = ""
        for character in bare {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        let sentence = words.joined(separator: " ").lowercased()
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    /// The plain-language name used everywhere Loupe shows an element: `Menu "Regular"`,
    /// or just `Button` when the element has no words of its own.
    public static func label(role: String, title: String?, value: String?, identifier: String?) -> String {
        let kind = name(forRole: role)
        guard let text = visibleText(title: title, value: value, identifier: identifier) else { return kind }
        return "\(kind) \u{201C}\(text)\u{201D}"
    }

    /// Whether a developer-assigned identifier reads like words ("First Text View") rather than
    /// a name the system generated ("_NS:31") or a long code
    public static func isReadableIdentifier(_ identifier: String) -> Bool {
        let trimmed = identifier.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("_"), trimmed.count <= 40 else { return false }
        guard trimmed.contains(where: \.isLetter) else { return false }
        if trimmed.contains("<") || trimmed.contains(":") { return false }
        if UUID(uuidString: trimmed) != nil { return false }
        return true
    }

    /// The words a person sees on the element: its title, else its value, else a readable
    /// identifier. Long values are shortened to one line.
    public static func visibleText(title: String?, value: String?, identifier: String?, limit: Int = 40) -> String? {
        let readableIdentifier = identifier.flatMap { isReadableIdentifier($0) ? $0 : nil }
        let candidates = [title, value, readableIdentifier]
        guard let raw = candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        let oneLine = raw.components(separatedBy: .newlines).first ?? raw
        guard oneLine.count > limit else { return oneLine }
        return String(oneLine.prefix(limit - 1)) + "…"
    }
}

// MARK: - What a note needs from the user

/// The single thing the note window's header label tells the user about a note
public enum NoteAttention: Equatable, Sendable {
    /// No agent has picked the note up yet
    case waiting
    /// An agent marked it seen and hasn't replied since
    case agentWorking
    /// The agent's latest message asks the user something
    case questionForYou
    /// The agent's latest message is an update, not a question
    case agentReplied
    case done
    case dismissed

    public init(note: Annotation) {
        switch note.status {
        case .done:
            self = .done
        case .dismissed:
            self = .dismissed
        case .pending, .seen:
            if let last = note.replies.last, last.author == .agent {
                self = last.text.contains("?") ? .questionForYou : .agentReplied
            } else {
                self = note.status == .seen ? .agentWorking : .waiting
            }
        }
    }

    public var label: String {
        switch self {
        case .waiting: return "Waiting"
        case .agentWorking: return "Agent working"
        case .questionForYou: return "Question for you"
        case .agentReplied: return "Agent replied"
        case .done: return "Done"
        case .dismissed: return "Dismissed"
        }
    }

    /// Whether the window should put the cursor in the reply box when it opens
    public var focusesReply: Bool {
        self == .questionForYou
    }
}
