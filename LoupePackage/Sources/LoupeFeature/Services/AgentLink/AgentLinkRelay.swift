import Foundation
import Darwin

/// What runs when a coding agent launches `Loupe --mcp`.
///
/// It shows no interface and needs no permissions. It passes the agent's MCP messages
/// (newline-delimited JSON on standard input and output) to the running Loupe app over
/// the private Agent Link socket, and answers on Loupe's behalf when the app can't be reached.
public enum AgentLinkRelay {

    static let unreachableMessage = "Loupe isn't reachable. Open Loupe and turn on Agent Link in Loupe's Settings, then try again."

    /// Run until the agent closes standard input
    public static func run() -> Never {
        signal(SIGPIPE, SIG_IGN)
        let relay = Relay(socketPath: AgentLinkSocket.path(), output: FileHandle.standardOutput.fileDescriptor)
        while let line = readLine(strippingNewline: true) {
            relay.forward(Data(line.utf8))
        }
        // The agent is done sending; give Loupe a moment to answer what's still open
        relay.waitForPendingReplies(timeout: 5)
        relay.close()
        exit(0)
    }

    /// The relay's logic, separated from standard input and output so it can be tested
    final class Relay: @unchecked Sendable {
        private let socketPath: String
        private let output: Int32
        private let lock = NSLock()
        private var socketFD: Int32 = -1
        private var readerThread: Thread?
        /// Requests sent to Loupe that haven't been answered yet
        private var pending: [JSONValue] = []

        init(socketPath: String, output: Int32) {
            self.socketPath = socketPath
            self.output = output
        }

        /// Pass one line from the agent to Loupe, or answer it here if Loupe can't be reached
        func forward(_ line: Data) {
            let message = try? JSONValue.parse(line)
            let id = message?["method"] != nil ? message?["id"] : nil

            if ensureConnected() {
                if let id { lock.withLock { pending.append(id) } }
                var data = line
                data.append(0x0A)
                let fd = lock.withLock { socketFD }
                if AgentLinkSocket.writeAll(data, to: fd) { return }
                if let id { lock.withLock { pending.removeAll { $0 == id } } }
                disconnect()
            }

            if let message { answerLocally(message) }
        }

        func close() {
            disconnect()
        }

        /// Wait until every forwarded request has an answer, or the timeout passes
        func waitForPendingReplies(timeout: TimeInterval) {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if lock.withLock({ pending.isEmpty || socketFD < 0 }) { return }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }

        // MARK: - Connection

        private func ensureConnected() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if socketFD >= 0 { return true }
            guard let fd = AgentLinkSocket.connect(path: socketPath) else { return false }
            socketFD = fd
            let thread = Thread { [weak self] in self?.readLoop(fd: fd) }
            thread.name = "Loupe Agent Link relay"
            readerThread = thread
            thread.start()
            return true
        }

        /// Copy Loupe's replies to the agent, line by line
        private func readLoop(fd: Int32) {
            var buffer = LineBuffer()
            var bytes = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = read(fd, &bytes, bytes.count)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { break }
                for line in buffer.append(Data(bytes[0..<count])) {
                    if let id = (try? JSONValue.parse(line))?["id"] {
                        lock.withLock { pending.removeAll { $0 == id } }
                    }
                    var data = line
                    data.append(0x0A)
                    writeToAgent(data)
                }
            }
            // Loupe went away: fail anything still waiting so the agent isn't left hanging
            let unanswered: [JSONValue] = lock.withLock {
                if socketFD == fd {
                    Darwin.close(fd)
                    socketFD = -1
                }
                defer { pending.removeAll() }
                return pending
            }
            for id in unanswered {
                writeToAgent(MCPHandler.errorResponse(id: id, code: -32000, message: AgentLinkRelay.unreachableMessage).lineData())
            }
        }

        private func disconnect() {
            lock.withLock {
                if socketFD >= 0 {
                    // Shutting down wakes the reader thread, which then closes the descriptor
                    shutdown(socketFD, SHUT_RDWR)
                }
            }
        }

        // MARK: - Local Answers

        /// Answer when Loupe can't be reached, so the agent still gets a clear message
        private func answerLocally(_ message: JSONValue) {
            guard let method = message["method"]?.stringValue, let id = message["id"] else { return }
            let reply: JSONValue
            switch method {
            case "initialize":
                let requested = message["params"]?["protocolVersion"]?.stringValue
                let version = requested.flatMap { MCPHandler.supportedProtocolVersions.contains($0) ? $0 : nil }
                    ?? MCPHandler.supportedProtocolVersions[0]
                reply = MCPHandler.result(id: id, [
                    "protocolVersion": .string(version),
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "loupe", "title": "Loupe", "version": .string(MCPHandler.appVersion)],
                    "instructions": .string(AgentLinkRelay.unreachableMessage),
                ])
            case "ping":
                reply = MCPHandler.result(id: id, [:])
            default:
                reply = MCPHandler.errorResponse(id: id, code: -32000, message: AgentLinkRelay.unreachableMessage)
            }
            writeToAgent(reply.lineData())
        }

        private let outputLock = NSLock()

        private func writeToAgent(_ data: Data) {
            outputLock.withLock {
                _ = AgentLinkSocket.writeAll(data, to: output)
            }
        }
    }
}
