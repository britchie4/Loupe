import Foundation
import Observation

/// Runs one practice: holds the state the practice screens draw from, and plays the
/// pretend agent's scripted replies after a short pause. No model, no network, and no
/// connection to the real notes.
@Observable @MainActor
public final class PracticeSession {
    public private(set) var model = PracticeModel()

    /// How long the pretend agent "thinks" before each scripted reply
    @ObservationIgnored public var agentDelay: Duration

    @ObservationIgnored private var agentTask: Task<Void, Never>?

    public init(agentDelay: Duration = .milliseconds(1300)) {
        self.agentDelay = agentDelay
    }

    // MARK: The person's actions

    public func hover(_ element: PracticeElement) { model.hover(element) }
    public func unhover(_ element: PracticeElement) { model.unhover(element) }
    public func select(_ element: PracticeElement) { model.select(element) }
    public func cancelNote() { model.cancelNote() }

    public func addNote(_ text: String) {
        if model.addNote(text) { scheduleAgent() }
    }

    public func answer(_ text: String) {
        if model.answer(text) { scheduleAgent() }
    }

    public func continueToFinish() { model.continueToFinish() }

    /// Throw the practice away and start over (also stops a reply that was on its way)
    public func reset() {
        agentTask?.cancel()
        agentTask = nil
        model = PracticeModel()
    }

    // MARK: The pretend agent

    private func scheduleAgent() {
        agentTask?.cancel()
        guard model.pendingAgentMove != nil else { return }
        let delay = agentDelay
        agentTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.model.agentMoves()
        }
    }
}
