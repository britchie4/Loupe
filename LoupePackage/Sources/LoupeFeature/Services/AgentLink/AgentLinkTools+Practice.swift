import Foundation

// Agent Link and setup's hands-on practice.
//
// While a new person is in the practice with their own agent connected, the practice note
// is offered to that agent through the same tools as real notes (list_notes, get_note,
// reply_to_note, update_note), so the practice shows the real loop. The practice note is
// never written to the AnnotationStore: these tools read and change a `PracticeSession`.
//
// The practice app is a small real page, so `edit_practice_app` is the edit an agent would
// make in a real project: it reads the page's source and writes it back however the note
// asks. Nothing limits what it can change. The page can't run scripts or load anything
// from outside (see `PracticePage` and `PracticePageWebView`).
extension AgentLinkTools {

    /// The app key agents see on the practice note
    static let practiceAppKey = "loupe.practice"

    static let practiceStatusLine = "The user is in Loupe's built-in practice and has left a practice note. list_notes returns it."

    static let setupStatusLine = "The user is going through Loupe's first-run setup and is about to try a practice note on a pretend app inside Loupe. No app is selected yet, and that is expected: do not ask them to pick one or to change any settings. When they ask you to check their Loupe notes, list_notes returns the practice note."

    /// The person is watching Loupe, not the agent's chat. An agent that only explains
    /// itself in its own chat leaves the practice looking stuck.
    private static let answerInLoupe = "The user is watching Loupe, not this chat, so answer there: finish with update_note, and if you truly can't do what the note asks, decline with update_note status dismissed and one short sentence on why."

    static let practiceClosedMessage = "That practice note is finished or the practice was closed. Nothing more to do for it."

    private static let practiceHowTo = "This note is from Loupe's built-in practice: a new user is trying Loupe on a practice app inside Loupe. The practice app is a small HTML page whose source is in practiceApp.html, and the note's element.identifier is that element's id or data-loupe-key attribute. Make the requested change with edit_practice_app, then call update_note with status done and one short sentence saying what you changed. \(answerInLoupe)"

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

    static func editPracticeApp(_ context: Context) -> AgentLinkTool {
        AgentLinkTool(
            name: "edit_practice_app",
            title: "Edit Loupe's practice app",
            description: "Only for Loupe's built-in practice, where a new user tries Loupe on a practice app inside Loupe (notes whose app is \"Practice App\"). \(PracticePage.howToEdit) Send the whole new page as html, or exact find-and-replace edits against the current source as edits. Act right away with a sensible reading of the request; only ask a question (reply_to_note) if the request can't be understood. Then call update_note with status done and one short sentence saying what you changed. \(answerInLoupe) It cannot touch any real app or file.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "html": ["type": "string", "description": .string("The practice app's whole new page: the HTML that goes inside its body. At most \(PracticePage.maxLength) characters.")],
                    "edits": [
                        "type": "array",
                        "description": "Changes to the current page instead of a whole new one, applied in order. Each find must match the current source exactly, and only its first match is replaced.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "find": ["type": "string"],
                                "replace": ["type": "string"],
                            ],
                            "required": ["find", "replace"],
                        ],
                    ],
                ],
            ],
            readOnly: false
        ) { args in
            guard let practice = context.openPractice, practice.model.hasOpenNote else {
                return .failure("Loupe's practice has no open note right now. This tool only works during the practice.")
            }

            var page: String
            if let html = args["html"]?.stringValue {
                guard args["edits"] == nil else { return .failure("Pass html or edits, not both.") }
                page = html
            } else if case .array(let edits)? = args["edits"], !edits.isEmpty {
                page = practice.currentPageHTML
                for edit in edits {
                    guard let find = edit["find"]?.stringValue, !find.isEmpty, let replace = edit["replace"]?.stringValue else {
                        return .failure("Each edit needs find and replace.")
                    }
                    guard let range = page.range(of: find) else {
                        return .failure("This text is not in the practice app's page, so nothing was changed: \(find.prefix(120)). The page's current source is in the note's practiceApp.html.")
                    }
                    page.replaceSubrange(range, with: replace)
                }
            } else {
                return .failure("Pass html (the whole new page) or edits (find-and-replace changes).")
            }

            guard page.trimmingCharacters(in: .whitespacesAndNewlines).count <= PracticePage.maxLength else {
                return .failure("The page is too long. Keep it under \(PracticePage.maxLength) characters.")
            }
            guard PracticePage.cleaned(page) != nil else {
                return .failure("Nothing would be left of the practice app's page. Send its new HTML.")
            }
            guard practice.agentRewrotePage(page) else { return .failure(practiceClosedMessage) }

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
                return .failure("Nothing in the practice app has changed yet. Make the change with edit_practice_app first, then mark the note done.")
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
            "number": .int(max(model.noteNumber, 1)),
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

    /// The practice app's page as it is right now
    static func practiceAppJSON(_ practice: PracticeSession) -> JSONValue {
        ["html": .string(practice.currentPageHTML)]
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
        if args["app"]?.stringValue == AgentLinkTools.practiceAppKey, (args["number"]?.intValue ?? practice.model.noteNumber) == practice.model.noteNumber {
            return practice
        }
        return nil
    }

    func practiceNotesForList(_ args: JSONValue, filter: String) -> [JSONValue] {
        AgentLinkTools.practiceNotes(practice, app: args["app"]?.stringValue, filter: filter)
    }
}
