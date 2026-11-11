import Foundation
import Observation

/// Runs one practice: holds the state the practice screens draw from, hands the practice
/// note to the person's own agent when one is connected through Agent Link, and otherwise
/// plays a pretend agent's scripted replies after a short pause.
///
/// It has no connection to the real notes. A connected agent reaches the practice note
/// only through the calls in "For connected agents" below, and only while that note is live.
@Observable @MainActor
public final class PracticeSession {
    public private(set) var model = PracticeModel()

    /// How long the pretend agent "thinks" before each scripted reply
    @ObservationIgnored public var agentDelay: Duration
    /// How long a connected agent may stay quiet before the pretend agent is offered instead
    @ObservationIgnored public var quietAgentDelay: Duration
    /// The connected agent to hand a new note to, by name. Nil means the pretend agent plays the part.
    @ObservationIgnored public var connectedAgent: () -> String? = { nil }
    /// Whether Loupe's setup window (permission, connect, practice) is showing right now.
    /// Agents are told, so they don't send a newcomer off to pick an app mid-setup.
    @ObservationIgnored public var isSetupOnScreen = false
    /// How agents refer to the current practice note
    @ObservationIgnored public private(set) var noteID = UUID()

    /// The practice app's page as it is on screen, with the pretend agent's changes in it.
    /// The page reports this after each change. Nil until it has.
    @ObservationIgnored private var renderedHTML: String?

    @ObservationIgnored private var agentTask: Task<Void, Never>?
    @ObservationIgnored private var quietTask: Task<Void, Never>?

    public init(agentDelay: Duration = .milliseconds(1300), quietAgentDelay: Duration = .seconds(30)) {
        self.agentDelay = agentDelay
        self.quietAgentDelay = quietAgentDelay
    }

    // MARK: The person's actions

    public func hover(_ element: PracticeElement) { model.hover(element) }
    public func unhover(_ element: PracticeElement) { model.unhover(element) }
    public func select(_ element: PracticeElement) { model.select(element) }
    public func cancelNote() { model.cancelNote() }

    public func addNote(_ text: String) {
        guard model.addNote(text, liveAgent: connectedAgent()) else { return }
        noteID = UUID()
        waitForAgent()
    }

    public func answer(_ text: String) {
        guard model.answer(text) else { return }
        waitForAgent()
    }

    /// Stop waiting for the person's own agent and let the pretend agent take the note
    public func usePretendAgent() {
        guard model.switchToPretendAgent() else { return }
        waitForAgent()
    }

    /// Close the finished note so another one can be left
    public func leaveAnotherNote() { model.leaveAnotherNote() }

    /// On to the closing screen. Anything still on its way from an agent is dropped.
    public func continueToFinish() {
        guard model.continueToFinish() else { return }
        agentTask?.cancel()
        agentTask = nil
        quietTask?.cancel()
        quietTask = nil
    }

    /// Throw the practice away and start over (also stops a reply that was on its way)
    public func reset() {
        agentTask?.cancel()
        agentTask = nil
        quietTask?.cancel()
        quietTask = nil
        renderedHTML = nil
        model = PracticeModel()
    }

    // MARK: The practice app's page

    /// The page told us what its source is now
    public func pageWasRendered(_ html: String) {
        renderedHTML = html
    }

    /// The page's source to hand to a connected agent: what is on screen right now
    public var currentPageHTML: String {
        renderedHTML ?? model.pageHTML
    }

    // MARK: For connected agents (called by Agent Link's tools)

    /// Whether a connected agent may see the practice note right now
    public var isOpenToAgents: Bool {
        model.isLive && (model.hasOpenNote || model.stage == .done)
    }

    public func agentRead() {
        guard model.isLive else { return }
        model.agentRead()
        waitForAgent()
    }

    @discardableResult
    public func agentMarkedSeen() -> Bool {
        guard model.isLive, model.agentMarkedSeen() else { return false }
        waitForAgent()
        return true
    }

    @discardableResult
    public func agentReplied(_ text: String) -> Bool {
        guard model.isLive, model.agentReplied(text) else { return false }
        waitForAgent()
        return true
    }

    @discardableResult
    public func agentChanged(_ elements: [PracticeElement], _ change: PracticeChange) -> Bool {
        guard model.isLive, model.agentChanged(elements, change) else { return false }
        waitForAgent()
        return true
    }

    /// The connected agent rewrote the practice app's page
    @discardableResult
    public func agentRewrotePage(_ html: String) -> Bool {
        guard model.isLive, model.agentRewrotePage(html) else { return false }
        // What the agent wrote is the page now, even before it has been drawn
        renderedHTML = model.pageHTML
        waitForAgent()
        return true
    }

    @discardableResult
    public func agentFinished(message: String?, dismissed: Bool) -> Bool {
        guard model.isLive, model.agentFinished(message: message, dismissed: dismissed) else { return false }
        waitForAgent()
        return true
    }

    // MARK: Waiting on an agent

    /// Whenever the note changes hands: the pretend agent replies on a timer, while a
    /// connected agent gets time to make progress before the pretend agent is offered instead
    private func waitForAgent() {
        agentTask?.cancel()
        quietTask?.cancel()

        if model.isLive {
            guard model.stage == .noteAdded || model.stage == .answered else { return }
            let delay = quietAgentDelay
            quietTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.model.offerPretendAgent()
            }
        } else if model.pendingAgentMove != nil {
            let delay = agentDelay
            agentTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.model.agentMoves()
            }
        }
    }
}
