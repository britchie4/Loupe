import Testing
import Foundation
@testable import LoupeFeature

@MainActor
struct MCPHandlerTests {

    private func handler() -> MCPHandler {
        MCPHandler(tools: [
            AgentLinkTool(name: "echo", title: "Echo", description: "Echo back", readOnly: true) { args in
                AgentLinkToolResult(["got": args["text"] ?? .null])
            }
        ])
    }

    private func reply(_ handler: MCPHandler, _ json: String) throws -> JSONValue? {
        guard let data = handler.handle(line: Data(json.utf8)) else { return nil }
        #expect(data.last == 0x0A)
        #expect(data.dropLast().contains(0x0A) == false)
        return try JSONValue.parse(data)
    }

    @Test func initializeAgreesOnVersionAndNamesTheAgent() throws {
        let handler = handler()
        var agent: String?
        handler.onClientIdentified = { agent = $0 }

        let response = try #require(try reply(handler, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"claude-code","title":"Claude Code"}}}"#))
        #expect(response["id"] == 1)
        #expect(response["result"]?["protocolVersion"] == "2025-06-18")
        #expect(response["result"]?["serverInfo"]?["name"] == "loupe")
        #expect(agent == "Claude Code")
    }

    @Test func unknownVersionGetsTheNewest() throws {
        let response = try #require(try reply(handler(), #"{"jsonrpc":"2.0","id":"a","method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#))
        #expect(response["result"]?["protocolVersion"]?.stringValue == MCPHandler.supportedProtocolVersions[0])
    }

    @Test func listsAndCallsTools() throws {
        let handler = handler()
        let list = try #require(try reply(handler, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        #expect(list["result"]?["tools"] == [[
            "name": "echo", "title": "Echo", "description": "Echo back",
            "inputSchema": ["type": "object", "properties": [:]],
            "annotations": ["readOnlyHint": true, "openWorldHint": false],
        ]])

        let call = try #require(try reply(handler, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"echo","arguments":{"text":"hi"}}}"#))
        #expect(call["result"]?["structuredContent"] == ["got": "hi"])
        #expect(call["result"]?["isError"] == false)
        #expect(call["result"]?["content"]?.isTextContent == true)
    }

    @Test func errorsAreReported() throws {
        let handler = handler()
        let unknownTool = try #require(try reply(handler, #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"nope"}}"#))
        #expect(unknownTool["error"]?["code"] == -32602)

        let unknownMethod = try #require(try reply(handler, #"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#))
        #expect(unknownMethod["error"]?["code"] == -32601)

        let garbage = try #require(try reply(handler, "not json"))
        #expect(garbage["error"]?["code"] == -32700)
    }

    @Test func notificationsGetNoReply() throws {
        #expect(try reply(handler(), #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }
}

struct LineBufferTests {
    @Test func splitsAcrossChunks() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("{\"a\":".utf8)).isEmpty)
        let lines = buffer.append(Data("1}\n\n{\"b\":2}\n{\"c\"".utf8))
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == [#"{"a":1}"#, #"{"b":2}"#])
        #expect(buffer.append(Data(":3}\n".utf8)).map { String(decoding: $0, as: UTF8.self) } == [#"{"c":3}"#])
    }
}

/// The full path: relay (what the agent launches) to socket to the app's handler, and back
@MainActor
struct AgentLinkEndToEndTests {

    private func shortSocketPath() -> String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("lt-\(UUID().uuidString.prefix(6)).sock")
    }

    /// Reads what the relay writes to the agent
    private final class AgentSide: @unchecked Sendable {
        let pipe = Pipe()
        private var buffer = LineBuffer()

        func nextMessage(timeout: Duration = .seconds(3)) async throws -> JSONValue {
            let fd = pipe.fileHandleForReading.fileDescriptor
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                var bytes = [UInt8](repeating: 0, count: 4096)
                let count = read(fd, &bytes, bytes.count)
                if count > 0, let line = buffer.append(Data(bytes[0..<count])).first {
                    return try JSONValue.parse(line)
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw CancellationError()
        }
    }

    @Test func relayAnswersWhenLoupeIsOffThenReachesItWhenOn() async throws {
        let path = shortSocketPath()
        let agent = AgentSide()
        let relay = AgentLinkRelay.Relay(socketPath: path, output: agent.pipe.fileHandleForWriting.fileDescriptor)
        defer { relay.close() }

        // Loupe not listening: the relay still answers, with a clear message
        relay.forward(Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}"#.utf8))
        let offline = try await agent.nextMessage()
        #expect(offline["result"]?["instructions"]?.stringValue == AgentLinkRelay.unreachableMessage)

        relay.forward(Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"get_status"}}"#.utf8))
        let offlineCall = try await agent.nextMessage()
        #expect(offlineCall["error"]?["message"]?.stringValue == AgentLinkRelay.unreachableMessage)

        // Turn Agent Link on: the next request goes through to the app
        let server = AgentLinkServer(socketPath: path)
        server.tools = [AgentLinkTool(name: "get_status", title: "Status", description: "", readOnly: true) { _ in
            AgentLinkToolResult(["ok": true])
        }]
        server.start()
        defer { server.stop() }
        #expect(server.status == .listening)

        relay.forward(Data(#"{"jsonrpc":"2.0","id":3,"method":"initialize","params":{"clientInfo":{"name":"Test Agent"}}}"#.utf8))
        let online = try await agent.nextMessage()
        #expect(online["id"] == 3)
        #expect(online["result"]?["instructions"]?.stringValue == MCPHandler.serverInstructions)
        #expect(server.connectedAgents == ["Test Agent"])

        relay.forward(Data(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_status"}}"#.utf8))
        let call = try await agent.nextMessage()
        #expect(call["result"]?["structuredContent"] == ["ok": true])

        // Turning Agent Link off disconnects the agent, and the relay falls back to its message
        server.stop()
        #expect(server.connectedAgents.isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        relay.forward(Data(#"{"jsonrpc":"2.0","id":5,"method":"tools/list"}"#.utf8))
        let afterOff = try await agent.nextMessage()
        #expect(afterOff["error"]?["code"] == -32000)
    }

    @Test func secondServerOnSameSocketIsRefused() {
        let path = shortSocketPath()
        let first = AgentLinkServer(socketPath: path)
        first.start()
        defer { first.stop() }

        let second = AgentLinkServer(socketPath: path)
        second.start()
        if case .failed = second.status {} else {
            Issue.record("Expected the second server to fail, got \(second.status)")
        }
        #expect(first.status == .listening)
    }

    @Test func socketIsPrivateToThisUser() throws {
        let path = shortSocketPath()
        let server = AgentLinkServer(socketPath: path)
        server.start()
        defer { server.stop() }

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
        #expect(permissions & 0o077 == 0)
    }
}

private extension JSONValue {
    var isTextContent: Bool {
        guard case .array(let items) = self, let first = items.first else { return false }
        return first["type"] == "text" && first["text"]?.stringValue != nil
    }
}
