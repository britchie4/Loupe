import Foundation

// Agent Link and setup's hands-on practice.
//
// While a new person is in the practice with their own agent connected, the practice note
// is offered to that agent through the same tools as real notes (list_notes, get_note,
// reply_to_note, update_note), so the practice shows the real loop. The practice note is
// never written to the AnnotationStore: these tools read and change a `PracticeSession`.
//
// The pretend app has no code behind it, so `change_practice_app` stands in for the edit
// an agent would make in a real project. It can only restyle the three practice elements.
extension AgentLinkTools {

    /// The app key agents see on the practice note
    static let practiceAppKey = "loupe.practice"

    static let practiceStatusLine = "The user is in Loupe's built-in practice and has left a practice note. list_notes returns it."

    static let practiceClosedMessage = "That practice note is finished or the practice was closed. Nothing more to do for it."

    private static let practiceHowTo = "This note is from Loupe's built-in practice: a new user is trying Loupe on a pretend app inside Loupe. There is no code to edit. Make the requested change with change_practice_app, then call update_note with status done and one short sentence saying what you changed."

    // MARK: Finding the practice note

    /// The practice note's JSON for list_notes, if the practice is on and the filters include it.
    /// Listing it counts as the agent having read it.
    static func practiceNotes(_ practice: PracticeSession?, app: String?, filter: String) -> [JSONValue] {
        guard let practice, practice.isOpenToAgents, app == nil || app == practiceAppKey else { return [] }
        let status = practiceStatus(practice)
        let included: Bool
        switch filter {
        case "all": included = true
        case "open": included = status == .pending || status == .seen
        default: included = status.rawValue == filter
        }
        guard included else { return [] }
        practice.agentRead()
        return [practiceNoteJSON(practice)]
    }

    // MARK: Tool

    static func changePracticeApp(_ context: Context) -> AgentLinkTool {
        let elements = PracticeElement.allCases.map(\.rawValue)
        return AgentLinkTool(
            name: "change_practice_app",
            title: "Change Loupe's practice app",
            description: "Only for Loupe's built-in practice, where a new user tries Loupe on a pretend app inside Loupe (notes whose app is \"Practice App\"). The pretend app has no code, so this tool stands in for editing it: call it to make the change a practice note asks for, then call update_note with status done and one short sentence saying what you changed. Act right away with a sensible reading of the request; only ask a question (reply_to_note) if the request can't be understood. It cannot touch any real app or file.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "element": [
                        "type": "string",
                        "enum": .array((elements + ["all"]).map { .string($0) }),
                        "description": "Which practice element to change: the note's element.identifier, or all for every element.",
                    ],
                    "text": ["type": "string", "description": .string("New words for the element, at most \(PracticeChange.maxTextLength) characters. Not allowed with element all.")],
                    "size": ["type": "string", "enum": .array(PracticeSize.allCases.map { .string($0.rawValue) })],
                    "color": ["type": "string", "enum": .array(PracticeColor.allCases.map { .string($0.rawValue) })],
                    "bold": ["type": "boolean"],
                    "checked": ["type": "boolean", "description": "Tick or untick the checkbox. Only the reminder element has one."],
                ],
                "required": ["element"],
            ],
            readOnly: false
        ) { args in
            guard let practice = context.openPractice, practice.model.hasOpenNote else {
                return .failure("Loupe's practice has no open note right now. This tool only works during the practice.")
            }
            guard let name = args["element"]?.stringValue else { return .failure("element is required.") }
            let targets: [PracticeElement]
            if name == "all" {
                targets = PracticeElement.allCases
            } else if let element = PracticeElement(rawValue: name) {
                targets = [element]
            } else {
                return .failure("element must be one of \(elements.joined(separator: ", ")), or all.")
            }

            var change = PracticeChange()
            if let text = args["text"]?.stringValue {
                guard targets.count == 1 else { return .failure("text can only be set on one element at a time.") }
                guard let cleaned = PracticeChange.cleanedText(text) else { return .failure("text can't be empty.") }
                change.text = cleaned
            }
            if let size = args["size"]?.stringValue {
                guard let value = PracticeSize(rawValue: size) else { return .failure("size must be one of \(PracticeSize.allCases.map(\.rawValue).joined(separator: ", ")).") }
                change.size = value
            }
            if let color = args["color"]?.stringValue {
                guard let value = PracticeColor(rawValue: color) else { return .failure("color must be one of \(PracticeColor.allCases.map(\.rawValue).joined(separator: ", ")).") }
                change.color = value
            }
            change.bold = args["bold"]?.boolValue
            if let checked = args["checked"]?.boolValue {
                guard targets.contains(.reminder) else { return .failure("Only the reminder element has a checkbox.") }
                change.checked = checked
            }
            guard !change.isEmpty else { return .failure("Pass at least one of text, size, color, bold, or checked.") }
            guard practice.agentChanged(targets, change) else { return .failure(practiceClosedMessage) }

            return AgentLinkToolResult([
                "practiceApp": practiceAppJSON(practice),
                "next": "Call update_note with status done and one short sentence saying what you changed.",
            ])
        }
    }

    // MARK: Note actions

    static func updatePracticeNote(_ practice: PracticeSession, to status: NoteStatus, message: String?) -> AgentLinkToolResult {
        switch status {
        case .seen:
            guard practice.agentMarkedSeen() else { return .failure(practiceClosedMessage) }
        case .done:
            guard practice.model.hasOpenNote else { return .failure(practiceClosedMessage) }
            guard practice.model.appWasChanged else {
                return .failure("Nothing in the practice app has changed yet. Make the change with change_practice_app first, then mark the note done.")
            }
            guard practice.agentFinished(message: message, dismissed: false) else { return .failure(practiceClosedMessage) }
        case .dismissed:
            guard practice.agentFinished(message: message, dismissed: true) else { return .failure(practiceClosedMessage) }
        case .pending:
            return .failure("status must be seen, done, or dismissed.")
        }
        return AgentLinkToolResult(["note": practiceNoteJSON(practice)])
    }

    // MARK: JSON

    private static func practiceStatus(_ practice: PracticeSession) -> NoteStatus {
        let model = practice.model
        if model.stage == .done { return model.wasDismissed ? .dismissed : .done }
        return model.agentIsWorking ? .seen : .pending
    }

    static func practiceNoteJSON(_ practice: PracticeSession) -> JSONValue {
        let model = practice.model
        let element = model.selected ?? .saveButton
        let request = model.messages.first
        return [
            "id": .string(practice.noteID.uuidString),
            "number": 1,
            "status": .string(practiceStatus(practice).rawValue),
            "request": .string(request?.text ?? ""),
            "practice": .string(practiceHowTo),
            "app": ["name": .string(PracticeCopy.appName), "bundleIdentifier": .string(practiceAppKey)],
            "element": [
                "role": .string(element.role),
                "identifier": .string(element.rawValue),
                "location": .string("\(PracticeCopy.appName) > \(ElementKind.name(forRole: element.role)) \"\(element.title)\""),
            ],
            "screenText": ["title": .string(model.look(of: element).text)],
            "practiceApp": practiceAppJSON(practice),
            "replies": .array(model.messages.dropFirst().map { message in
                ["from": .string(message.author.rawValue), "text": .string(message.text), "at": .string(isoDate(message.time))]
            }),
            "createdAt": .string(isoDate(request?.time ?? Date())),
        ]
    }

    /// How every element of the practice app looks right now
    static func practiceAppJSON(_ practice: PracticeSession) -> JSONValue {
        .array(PracticeElement.allCases.map { element in
            let look = practice.model.look(of: element)
            var json: [String: JSONValue] = [
                "element": .string(element.rawValue),
                "role": .string(element.role),
                "text": .string(look.text),
                "size": .string(look.size.rawValue),
                "color": .string(look.color.rawValue),
                "bold": .bool(look.bold),
            ]
            if element == .reminder { json["checked"] = .bool(look.checked) }
            return .object(json)
        })
    }
}

extension AgentLinkTools.Context {

    /// The practice, while its note is visible to agents
    var openPractice: PracticeSession? {
        guard let practice, practice.isOpenToAgents else { return nil }
        return practice
    }

    /// The practice, if these arguments point at its note (by id, or by the practice app's key)
    func practice(matching args: JSONValue) -> PracticeSession? {
        guard let practice = openPractice else { return nil }
        if let id = args["id"]?.stringValue {
            return id.caseInsensitiveCompare(practice.noteID.uuidString) == .orderedSame ? practice : nil
        }
        if args["app"]?.stringValue == AgentLinkTools.practiceAppKey, (args["number"]?.intValue ?? 1) == 1 {
            return practice
        }
        return nil
    }

    func practiceNotesForList(_ args: JSONValue, filter: String) -> [JSONValue] {
        AgentLinkTools.practiceNotes(practice, app: args["app"]?.stringValue, filter: filter)
    }
}
