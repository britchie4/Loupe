import Testing
import Foundation
@testable import LoupeFeature

/// A connected agent taking part in setup's practice through Agent Link's tools
@MainActor
struct PracticeAgentToolsTests {

    private let store = AnnotationStore(fileURL: nil)
    private let practice = PracticeSession(quietAgentDelay: .seconds(3600))
    private let handler: MCPHandler

    init() {
        let context = AgentLinkTools.Context(
            store: store,
            inspector: AccessibilityInspector(),
            selectedApp: { nil },
            isInspecting: { false },
            practice: practice
        )
        handler = MCPHandler(tools: AgentLinkTools.make(context: context))
    }

    private func call(_ name: String, _ arguments: JSONValue = [:]) throws -> (result: JSONValue, isError: Bool) {
        let request: JSONValue = ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": .string(name), "arguments": arguments]]
        let response = try #require(handler.handle(message: request))
        let result = try #require(response["result"])
        return (try #require(result["structuredContent"]), result["isError"]?.boolValue ?? false)
    }

    /// Leave a practice note on the Save Plan button with an agent connected
    private func leaveLiveNote(_ text: String = "Make this button bigger") {
        practice.connectedAgent = { "Claude Code" }
        practice.select(.saveButton)
        practice.addNote(text)
    }

    private var noteID: JSONValue { .string(practice.noteID.uuidString) }

    private func notes(_ result: JSONValue) -> [JSONValue] {
        if case .array(let items)? = result["notes"] { return items }
        return []
    }

    // MARK: Finding the practice note

    @Test func noPracticeNoteMeansNothingChangesForAgents() throws {
        // No app selected and no practice: the usual answer
        #expect(try call("list_notes").isError)
        #expect(try call("get_status").result["practice"] == nil)
        #expect(try call("edit_practice_app", ["html": "<p>Hello</p>"]).isError)
    }

    @Test func aPracticeWithoutAnAgentIsInvisibleToAgents() throws {
        practice.select(.saveButton)
        practice.addNote("Make this button bigger")
        #expect(!practice.model.isLive)

        #expect(try call("list_notes").isError)
        #expect(try call("get_note", ["id": noteID]).isError)
        #expect(try call("edit_practice_app", ["html": "<p>Hello</p>"]).isError)
        #expect(practice.model.pageHTML == PracticePage.startingHTML)
    }

    @Test func checkingNotesFindsThePracticeNote() throws {
        leaveLiveNote()
        #expect(try call("get_status").result["practice"]?.stringValue == AgentLinkTools.practiceStatusLine)
        #expect(!practice.model.agentHasRead)

        let list = try call("list_notes")
        #expect(!list.isError)
        let found = notes(list.result)
        #expect(found.count == 1)
        let note = try #require(found.first)
        #expect(note["id"] == noteID)
        #expect(note["request"] == "Make this button bigger")
        #expect(note["status"] == "pending")
        #expect(note["app"]?["bundleIdentifier"]?.stringValue == AgentLinkTools.practiceAppKey)
        #expect(note["element"]?["identifier"] == "saveButton")
        #expect(note["practice"]?.stringValue?.contains("edit_practice_app") == true)
        // The note carries the practice app's page, so the agent can see what it is changing
        #expect(note["practiceApp"]?["html"]?.stringValue == PracticePage.startingHTML)
        // Listing it tells the person their agent picked it up
        #expect(practice.model.agentHasRead)

        // It is never one of the real notes
        #expect(store.annotations.isEmpty)
    }

    @Test func thePracticeNoteLeadsTheRealNotesOfTheSelectedApp() throws {
        store.selectApp(key: "com.example.app")
        leaveLiveNote()
        let list = try call("list_notes")
        #expect(list.result["app"] == "com.example.app")
        #expect(notes(list.result).first?["id"] == noteID)
        // Asking for another app by name leaves the practice note out
        #expect(notes(try call("list_notes", ["app": "com.example.other"]).result).isEmpty)
        #expect(notes(try call("list_notes", ["status": "done"]).result).isEmpty)
    }

    // MARK: Doing the work

    @Test func anAgentEditsThePageThenMarksTheNoteDone() throws {
        leaveLiveNote("make the letters italic")

        // Done before any change is refused, with a pointer to the right tool
        let early = try call("update_note", ["id": noteID, "status": "done", "message": "Done"])
        #expect(early.isError)
        #expect(early.result["error"]?.stringValue?.contains("edit_practice_app") == true)
        #expect(practice.model.stage == .noteAdded)

        #expect(!(try call("update_note", ["id": noteID, "status": "seen"]).isError))
        #expect(practice.model.status?.label == "Agent working")

        // Italic was the request the old fixed list of changes could not do
        let italic = "<button id=\"saveButton\" style=\"font-style: italic\">Save Plan</button>"
        let changed = try call("edit_practice_app", ["edits": [["find": "<button id=\"saveButton\">Save Plan</button>", "replace": .string(italic)]]])
        #expect(!changed.isError)
        #expect(practice.model.pageHTML.contains(italic))
        #expect(practice.model.pageHTML.contains("<h1 id=\"heading\">Weekend Planner</h1>"))
        #expect(changed.result["practiceApp"]?["html"]?.stringValue == practice.model.pageHTML)

        let done = try call("update_note", ["id": noteID, "status": "done", "message": "Made the button's letters italic."])
        #expect(!done.isError)
        #expect(done.result["note"]?["status"] == "done")
        #expect(practice.model.stage == .done)
        #expect(practice.model.badge == .done)
        #expect(practice.model.messages.last?.text == "Made the button's letters italic.")

        // The finished note can still be read, but not worked on
        #expect(!(try call("get_note", ["id": noteID]).isError))
        #expect(try call("edit_practice_app", ["html": "<p>Later</p>"]).isError)
        #expect(store.annotations.isEmpty)
    }

    /// Nothing limits what the page can become: new things, moved things, a different page
    @Test func anAgentCanRewriteTheWholePage() throws {
        leaveLiveNote("add a cancel button and a subtitle")
        let page = """
        <h1 id="heading">Weekend Planner</h1>
        <p class="subtitle" style="opacity: .7">Two days, no plans yet</p>
        <div class="row"><button id="cancel">Cancel</button><button id="saveButton">Save Plan</button></div>
        """
        #expect(!(try call("edit_practice_app", ["html": .string(page)])).isError)
        #expect(practice.model.pageHTML == page)
        #expect(practice.model.appWasChanged)
    }

    /// The page can't run code or load anything, and what is kept says so
    @Test func scriptsAndOutsideContentAreDropped() throws {
        leaveLiveNote()
        let page = "<h1 id=\"heading\">Hi</h1><script>alert(1)</script><iframe src=\"https://example.com\"></iframe><link rel=\"stylesheet\" href=\"https://example.com/a.css\"><p>Kept</p>"
        #expect(!(try call("edit_practice_app", ["html": .string(page)])).isError)
        #expect(practice.model.pageHTML == "<h1 id=\"heading\">Hi</h1><p>Kept</p>")
    }

    @Test func badEditsAreRefusedWithAReason() throws {
        leaveLiveNote()
        #expect(try call("edit_practice_app", [:]).isError)
        #expect(try call("edit_practice_app", ["html": "   "]).isError)
        #expect(try call("edit_practice_app", ["html": "<script>only()</script>"]).isError)
        #expect(try call("edit_practice_app", ["html": "<p>a</p>", "edits": [["find": "a", "replace": "b"]]]).isError)
        #expect(try call("edit_practice_app", ["edits": [["find": "", "replace": "b"]]]).isError)
        #expect(try call("edit_practice_app", ["html": .string(String(repeating: "<p>long</p>", count: 4000))]).isError)
        // Text that isn't on the page changes nothing, and says where to look
        let missing = try call("edit_practice_app", ["edits": [["find": "<button>Nope</button>", "replace": "<b>x</b>"]]])
        #expect(missing.isError)
        #expect(missing.result["error"]?.stringValue?.contains("practiceApp.html") == true)
        #expect(!practice.model.appWasChanged)
        #expect(practice.model.pageHTML == PracticePage.startingHTML)
    }

    /// What the practice agent changed earlier is part of the page a real agent is shown,
    /// so its edit builds on what the person sees
    @Test func theAgentSeesThePageAsItIsOnScreen() throws {
        leaveLiveNote()
        let onScreen = PracticePage.startingHTML.replacingOccurrences(of: "<h1 id=\"heading\">", with: "<h1 id=\"heading\" style=\"color: var(--loupe-blue)\">")
        practice.pageWasRendered(onScreen)

        let note = try #require(notes(try call("list_notes").result).first)
        #expect(note["practiceApp"]?["html"]?.stringValue == onScreen)

        // An edit is made against that page, and from then on the agent's page is the page
        #expect(!(try call("edit_practice_app", ["edits": [["find": "Weekend Planner", "replace": "Holiday Planner"]]])).isError)
        #expect(practice.model.pageHTML.contains("style=\"color: var(--loupe-blue)\">Holiday Planner"))
        #expect(practice.currentPageHTML == practice.model.pageHTML)
    }

    @Test func anAgentsQuestionAndThePersonsAnswerGoThroughThePracticeNote() throws {
        leaveLiveNote()
        let asked = try call("reply_to_note", ["id": noteID, "text": "How much bigger?"])
        #expect(!asked.isError)
        #expect(practice.model.stage == .questionForYou)
        #expect(practice.model.status?.label == "Question for you")

        practice.answer("Twice the size")
        let note = try #require(try call("get_note", ["id": noteID]).result["note"])
        guard case .array(let replies)? = note["replies"] else {
            Issue.record("No replies on the practice note")
            return
        }
        #expect(replies.count == 2)
        #expect(replies.last?["from"] == "user")
        #expect(replies.last?["text"] == "Twice the size")
        #expect(note["status"] == "pending")
        #expect(store.annotations.isEmpty)
    }

    /// "Delete this button" was the first note tried with a real agent, and it stalled
    @Test func anAgentCanDeleteAnElement() throws {
        leaveLiveNote("delete this button")
        _ = try call("list_notes")

        let removed = try call("edit_practice_app", ["edits": [["find": "<button id=\"saveButton\">Save Plan</button>", "replace": ""]]])
        #expect(!removed.isError)
        #expect(!practice.model.pageHTML.contains("saveButton"))
        #expect(practice.model.pageHTML.contains("id=\"reminder\""))

        #expect(!(try call("update_note", ["id": noteID, "status": "done", "message": "Removed the button."])).isError)
        #expect(practice.model.stage == .done)
        #expect(store.annotations.isEmpty)
    }

    /// The person is looking at Loupe, so an agent that can't do something has to say so there
    @Test func agentsAreToldToAnswerInsideLoupe() throws {
        leaveLiveNote("make it spin")
        let note = try #require(notes(try call("list_notes").result).first)
        let guidance = try #require(note["practice"]?.stringValue)
        #expect(guidance.contains("watching Loupe, not this chat"))
        #expect(guidance.contains("dismissed"))
        #expect(!guidance.contains("\u{2014}"))
    }

    /// During setup no app is selected yet. Agents are told that is expected.
    @Test func statusSaysWhenSetupIsOnScreen() throws {
        #expect(try call("get_status").result["setup"] == nil)

        practice.isSetupOnScreen = true
        #expect(try call("get_status").result["setup"]?.stringValue == AgentLinkTools.setupStatusLine)

        // Once there is a practice note, that is the thing to say
        leaveLiveNote()
        let status = try call("get_status").result
        #expect(status["setup"] == nil)
        #expect(status["practice"]?.stringValue == AgentLinkTools.practiceStatusLine)
    }

    /// A person can leave several notes, one at a time. Each one reaches the agent as its own note.
    @Test func aSecondNoteReachesTheAgentAsANewNote() throws {
        leaveLiveNote("Make this button bigger")
        let firstID = noteID
        _ = try call("list_notes")
        _ = try call("edit_practice_app", ["edits": [["find": "<button id=\"saveButton\">", "replace": "<button id=\"saveButton\" style=\"font-size: 20px\">"]]])
        _ = try call("update_note", ["id": firstID, "status": "done", "message": "Bigger."])
        #expect(practice.model.stage == .done)

        practice.select(.heading)
        practice.addNote("make it green")
        #expect(noteID != firstID)

        let found = notes(try call("list_notes").result)
        #expect(found.count == 1)
        let note = try #require(found.first)
        #expect(note["id"] == noteID)
        #expect(note["number"]?.intValue == 2)
        #expect(note["request"]?.stringValue == "make it green")
        #expect(note["replies"] == .array([]))

        // The first note is closed for good, and the new one needs its own change before "done"
        #expect(try call("get_note", ["id": firstID]).isError)
        #expect(try call("update_note", ["id": noteID, "status": "done", "message": "Done."]).isError)
        _ = try call("edit_practice_app", ["edits": [["find": "<h1 id=\"heading\">", "replace": "<h1 id=\"heading\" style=\"color: green\">"]]])
        #expect(!(try call("update_note", ["id": noteID, "status": "done", "message": "Green now."])).isError)

        // Both changes are still there
        #expect(practice.model.pageHTML.contains("style=\"font-size: 20px\""))
        #expect(practice.model.pageHTML.contains("style=\"color: green\""))
        #expect(practice.model.badges == [.saveButton: .done, .heading: .done])
        #expect(store.annotations.isEmpty)
    }

    @Test func anAgentCanDeclineThePracticeNote() throws {
        leaveLiveNote("delete my files")
        let declined = try call("update_note", ["id": noteID, "status": "dismissed", "message": "I can only restyle the practice app."])
        #expect(!declined.isError)
        #expect(practice.model.badge == .dismissed)
        #expect(practice.model.messages.last?.text == "I can only restyle the practice app.")
    }

    @Test func realNotesAreUntouchedByPracticeCalls() throws {
        store.selectApp(key: "com.example.app")
        leaveLiveNote()
        // A made-up id is still "no note", not the practice note
        #expect(try call("get_note", ["id": .string(UUID().uuidString)]).isError)
        #expect(try call("reply_to_note", ["id": .string(UUID().uuidString), "text": "hi"]).isError)
        #expect(practice.model.messages.count == 1)
    }
}
