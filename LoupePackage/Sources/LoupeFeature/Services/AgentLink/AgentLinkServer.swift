import Foundation
import Observation

/// Runs Agent Link inside the Loupe app: listens on the private socket and answers agents.
///
/// Off until the user turns on Agent Link in Settings.
@MainActor
@Observable
public final class AgentLinkServer {

    public enum Status: Equatable {
        case off
        case listening
        case failed(String)
    }

    /// Shared so Settings can show the live status
    public static let shared = AgentLinkServer()

    public private(set) var status: Status = .off
    /// Names of the agents connected right now (e.g. "Claude Code")
    public private(set) var connectedAgents: [String] = []

    @ObservationIgnored private var socketServer: AgentLinkSocketServer?
    @ObservationIgnored private var agentNames: [AgentLinkSocketServer.ConnectionID: String] = [:]
    @ObservationIgnored private let handler = MCPHandler(tools: [])
    @ObservationIgnored private let socketPath: String

    public init(socketPath: String = AgentLinkSocket.path()) {
        self.socketPath = socketPath
    }

    /// The tools agents can call
    public var tools: [AgentLinkTool] {
        get { handler.tools }
        set { handler.tools = newValue }
    }

    public var isRunning: Bool { socketServer != nil }

    /// Start or stop to match the user's setting
    public func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    public func start() {
        guard socketServer == nil else { return }
        let server = AgentLinkSocketServer(path: socketPath)

        server.onLine = { [weak self, weak server] id, line in
            // Handle on the main actor in arrival order, then reply on the socket queue
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let server else { return }
                    self.handler.onClientIdentified = { [weak self] name in
                        self?.agentNames[id] = name
                        self?.refreshAgents()
                    }
                    if let reply = self.handler.handle(line: line) {
                        server.send(reply, to: id)
                    }
                }
            }
        }
        server.onConnectionChange = { [weak self] id, connected in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if connected {
                        self.agentNames[id] = self.agentNames[id] ?? "Agent"
                    } else {
                        self.agentNames[id] = nil
                    }
                    self.refreshAgents()
                }
            }
        }

        do {
            try server.start()
            socketServer = server
            status = .listening
        } catch .alreadyInUse {
            status = .failed("Another copy of Loupe is already using Agent Link. Quit it, then try again.")
        } catch .pathTooLong {
            status = .failed("Agent Link couldn't create its connection file.")
        } catch .system(let message) {
            status = .failed("Agent Link couldn't start: \(message)")
        } catch {
            status = .failed("Agent Link couldn't start.")
        }
    }

    public func stop() {
        socketServer?.stop()
        socketServer = nil
        agentNames = [:]
        refreshAgents()
        status = .off
    }

    private func refreshAgents() {
        connectedAgents = agentNames.keys.sorted().compactMap { agentNames[$0] }
    }

    // MARK: - Setup

    /// Installs the loupe-notes skill, which teaches an agent the notes workflow,
    /// into Claude Code, Codex and other agents that read standard skills
    public static let skillInstallCommand = "npx skills add britchie4/Loupe"
}
