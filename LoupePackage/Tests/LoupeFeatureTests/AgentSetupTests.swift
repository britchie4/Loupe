import Testing
import Foundation
@testable import LoupeFeature

/// The per-agent setup text in Settings > Agent Link
struct AgentSetupTests {

    private let path = "/Applications/Loupe.app/Contents/MacOS/Loupe"

    private func copied(_ target: AgentSetupTarget) -> String? {
        if case .copy(let text) = target.action(executablePath: path) { return text }
        return nil
    }

    @Test func terminalCommandsRegisterLoupe() throws {
        #expect(try #require(copied(.claudeCode)).hasPrefix("claude mcp add --scope user loupe -- '\(path)' --mcp && echo '"))
        #expect(try #require(copied(.codex)).hasPrefix("codex mcp add loupe -- '\(path)' --mcp && echo '"))
    }

    /// A chat that was open before setup never gets Loupe's tools. The command itself says
    /// so, in Terminal or through the agent it was pasted into, and only when adding worked.
    @Test func setupEndsByAskingForANewChat() throws {
        let claude = try #require(copied(.claudeCode))
        #expect(claude.hasSuffix("&& echo 'Loupe is added. Start a new session in Claude Code to connect it. Sessions that are already open cannot see Loupe.'"))
        let codex = try #require(copied(.codex))
        #expect(codex.hasSuffix("&& echo 'Loupe is added. Start a new chat in Codex to connect it. Chats that are already open cannot see Loupe.'"))
        #expect(try #require(copied(.other)).contains("tell me to start a new chat"))

        for target in AgentSetupTarget.allCases {
            guard let message = target.afterSetupMessage else { continue }
            #expect(!message.contains("\u{2014}"))
            // Plain enough to sit inside a one-line shell command without surprises
            #expect(!message.contains("'") && !message.contains("\n") && !message.contains("!"))
        }
    }

    @Test func xcodeSetsUpBothBuiltInAgents() throws {
        let lines = try #require(copied(.xcode)).split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[2].hasPrefix("echo 'Next, start a new conversation in Xcode"))
        #expect(lines[0].hasPrefix("CLAUDE_CONFIG_DIR=\"$HOME/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig\" claude mcp add"))
        #expect(lines[1].hasPrefix("CODEX_HOME=\"$HOME/Library/Developer/Xcode/CodingAssistant/codex\" codex mcp add"))
    }

    @Test func otherAgentPromptHasManualDetails() throws {
        let prompt = try #require(copied(.other))
        #expect(prompt.contains("Command: \(path)"))
        #expect(prompt.contains("Arguments: --mcp"))
        #expect(!prompt.contains("\u{2014}"))
    }

    @Test func cursorLinkCarriesTheServerSettings() throws {
        guard case .open(let url) = AgentSetupTarget.cursor.action(executablePath: path) else {
            Issue.record("Cursor should open a link"); return
        }
        #expect(url.absoluteString.hasPrefix("cursor://anysphere.cursor-deeplink/mcp/install?name=loupe&config="))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let encoded = try #require(items.first { $0.name == "config" }?.value)
        let data = try #require(Data(base64Encoded: encoded))
        let config = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(config["command"] as? String == path)
        #expect(config["args"] as? [String] == ["--mcp"])
    }

    @Test func pathsWithQuotesStayQuotedInTerminal() {
        #expect(AgentSetupTarget.shellQuoted("/tmp/it's/Loupe") == "'/tmp/it'\\''s/Loupe'")
    }

    /// People paste the command into the agent itself, and for Codex that is the path
    /// that works even when its terminal command is missing
    @Test func hintsOfferPastingIntoTheAgent() {
        #expect(AgentSetupTarget.claudeCode.hint.hasPrefix("Paste into Terminal or a Claude Code session."))
        #expect(AgentSetupTarget.codex.hint.hasPrefix("Paste into Terminal or a Codex chat."))
    }

    @Test func hintsUseNoEmDashes() {
        for target in AgentSetupTarget.allCases {
            #expect(!target.hint.contains("\u{2014}"))
        }
    }
}
