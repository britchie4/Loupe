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

    func action(executablePath path: String) -> Action {
        let quoted = Self.shellQuoted(path)
        switch self {
        case .claudeCode:
            return .copy("claude mcp add --scope user loupe -- \(quoted) --mcp")
        case .codex:
            return .copy("codex mcp add loupe -- \(quoted) --mcp")
        case .xcode:
            let base = "$HOME/Library/Developer/Xcode/CodingAssistant"
            return .copy("""
            CLAUDE_CONFIG_DIR="\(base)/ClaudeAgentConfig" claude mcp add --scope user loupe -- \(quoted) --mcp
            CODEX_HOME="\(base)/codex" codex mcp add loupe -- \(quoted) --mcp
            """)
        case .cursor:
            return .open(Self.cursorInstallLink(executablePath: path))
        case .other:
            return .copy("""
            Please connect Loupe to your tools. Loupe is a Mac app that lets me leave notes on an app's interface for you to work through.

            Add it as a local MCP server (stdio) named "loupe":
            Command: \(path)
            Arguments: --mcp

            Once it's added (you may need to restart), call Loupe's get_status tool to confirm the connection.
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
