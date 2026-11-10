import Foundation

/// The agents Loupe gives setup steps for in Settings > Agent Link.
/// Each one keeps its list of tools in its own place, so each gets its own text.
public enum AgentSetupTarget: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex
    case cursor
    case xcode
    case other

    public var id: String { rawValue }

    /// How setup is delivered: text to copy, or a link that opens the agent
    public enum Action: Equatable, Sendable {
        case copy(String)
        case open(URL)
    }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .xcode: "Xcode"
        case .other: "Other agent"
        }
    }

    /// One line telling the person what to do with the button's result
    public var hint: String {
        switch self {
        case .claudeCode:
            "Paste into Terminal. Also covers the Code tab in the Claude desktop app."
        case .codex:
            "Paste into Terminal. Also covers the Codex app and editor plugins."
        case .cursor:
            "Opens Cursor, which asks you to confirm."
        case .xcode:
            "Paste into Terminal. Sets up both of Xcode's built-in agents, Claude Agent and Codex."
        case .other:
            "Paste into your agent's chat and it adds Loupe itself. The text also has the details for setting it up by hand."
        }
    }

    public var buttonTitle: String {
        switch self {
        case .cursor: "Add to Cursor"
        case .other: "Copy setup prompt"
        default: "Copy setup command"
        }
    }

    public var action: Action {
        action(executablePath: Self.executablePath)
    }

    /// What the person has to do once setup has run, said by the setup command itself.
    /// A chat that was open before setup never gets Loupe's tools, and nothing else tells
    /// the person so. In Terminal this is printed. Pasted into an agent's chat, the agent
    /// runs the command and passes the message on.
    var afterSetupMessage: String? {
        switch self {
        case .claudeCode:
            "Loupe is added. Start a new session in Claude Code to connect it. Sessions that are already open cannot see Loupe."
        case .codex:
            "Loupe is added. Start a new chat in Codex to connect it. Chats that are already open cannot see Loupe."
        case .xcode:
            "Next, start a new conversation in Xcode to connect Loupe. Conversations that are already open cannot see it."
        case .cursor, .other:
            nil
        }
    }

    func action(executablePath path: String) -> Action {
        let quoted = Self.shellQuoted(path)
        let say = afterSetupMessage.map { "echo \(Self.shellQuoted($0))" } ?? ""
        switch self {
        case .claudeCode:
            // The message only prints when adding Loupe worked
            return .copy("claude mcp add --scope user loupe -- \(quoted) --mcp && \(say)")
        case .codex:
            return .copy("codex mcp add loupe -- \(quoted) --mcp && \(say)")
        case .xcode:
            let base = "$HOME/Library/Developer/Xcode/CodingAssistant"
            return .copy("""
            CLAUDE_CONFIG_DIR="\(base)/ClaudeAgentConfig" claude mcp add --scope user loupe -- \(quoted) --mcp
            CODEX_HOME="\(base)/codex" codex mcp add loupe -- \(quoted) --mcp
            \(say)
            """)
        case .cursor:
            return .open(Self.cursorInstallLink(executablePath: path))
        case .other:
            return .copy("""
            Please connect Loupe to your tools. Loupe is a Mac app that lets me leave notes on an app's interface for you to work through.

            Add it as a local MCP server (stdio) named "loupe":
            Command: \(path)
            Arguments: --mcp

            Once it's added, call Loupe's get_status tool to confirm the connection. If Loupe's tools are not available in this chat yet, tell me to start a new chat: chats that are already open cannot see newly added tools.
            """)
        }
    }

    // MARK: - Helpers

    static var executablePath: String {
        Bundle.main.executablePath ?? "/Applications/Loupe.app/Contents/MacOS/Loupe"
    }

    static func shellQuoted(_ path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// Cursor's one-click install link: the server's settings as JSON, base64-encoded
    static func cursorInstallLink(executablePath path: String) -> URL {
        let config: [String: Any] = ["command": path, "args": ["--mcp"]]
        let json = (try? JSONSerialization.data(withJSONObject: config, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        var components = URLComponents()
        components.scheme = "cursor"
        components.host = "anysphere.cursor-deeplink"
        components.path = "/mcp/install"
        components.queryItems = [
            URLQueryItem(name: "name", value: "loupe"),
            URLQueryItem(name: "config", value: json.base64EncodedString())
        ]
        // Base64 can contain + / =, which must be escaped inside a query value
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .replacingOccurrences(of: "/", with: "%2F")
        return components.url ?? URL(string: "cursor://")!
    }
}
