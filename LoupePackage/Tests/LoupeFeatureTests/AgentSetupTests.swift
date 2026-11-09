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

    @Test func terminalCommandsRegisterLoupe() {
        #expect(copied(.claudeCode) == "claude mcp add --scope user loupe -- '\(path)' --mcp")
        #expect(copied(.codex) == "codex mcp add loupe -- '\(path)' --mcp")
    }

    @Test func xcodeSetsUpBothBuiltInAgents() throws {
        let lines = try #require(copied(.xcode)).split(separator: "\n")
        #expect(lines.count == 2)
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

    @Test func hintsUseNoEmDashes() {
        for target in AgentSetupTarget.allCases {
            #expect(!target.hint.contains("\u{2014}"))
        }
    }
}
