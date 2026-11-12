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
        #expect(try #require(copied(.claudeCode)).hasPrefix("claude mcp remove --scope user loupe >/dev/null 2>&1; claude mcp add --scope user loupe -- '\(path)' --mcp && echo '"))
        #expect(try #require(copied(.codex)).hasPrefix("codex mcp add loupe -- '\(path)' --mcp && echo '"))
    }

    /// Claude Code refuses to add a second "loupe", so an older one (a previous build, or
    /// Loupe before it moved to Applications) is removed first, without a message if there is none
    @Test func claudeCodeReplacesAnOlderLoupe() throws {
        let command = try #require(copied(.claudeCode))
        let remove = try #require(command.range(of: "claude mcp remove --scope user loupe"))
        let add = try #require(command.range(of: "claude mcp add --scope user loupe"))
        #expect(remove.lowerBound < add.lowerBound)
        // A failed remove (nothing to remove) must not stop the add
        #expect(command.contains(">/dev/null 2>&1; claude mcp add"))
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
        let claudeDir = "CLAUDE_CONFIG_DIR=\"$HOME/Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig\""
        #expect(lines[0].hasPrefix("\(claudeDir) claude mcp remove --scope user loupe >/dev/null 2>&1; \(claudeDir) claude mcp add"))
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

    // MARK: The permission screen

    /// macOS 27 renamed the permission. The screen uses the name the person will see.
    @Test func thePermissionIsNamedAsThisMacNamesIt() {
        #expect(SetupCopy.settingName(macOSMajorVersion: 27) == "Device Control and Data Access")
        #expect(SetupCopy.settingName(macOSMajorVersion: 26) == "Accessibility")
        #expect(SetupCopy.settingName(macOSMajorVersion: 14) == "Accessibility")
        #expect(SetupCopy.turnOnStep(macOSMajorVersion: 27) == "Turn on **Loupe** under Device Control and Data Access")
        #expect(SetupCopy.turnOnStep(macOSMajorVersion: 15) == "Turn on **Loupe** under Accessibility")
    }

    @Test func thePermissionScreenSaysWhatLoupeDoesInPlainWords() {
        let strings = [SetupCopy.permissionTitle, SetupCopy.permissionReason, SetupCopy.returnStep,
                       SetupCopy.permissionNote(macOSMajorVersion: 27), SetupCopy.permissionNote(macOSMajorVersion: 15)]
        for string in strings {
            #expect(!string.contains("\u{2014}"))
            #expect(!string.contains("API"))
        }
        // The broad warning only exists on macOS 27 and later
        #expect(SetupCopy.permissionNote(macOSMajorVersion: 27).contains("warns"))
        #expect(!SetupCopy.permissionNote(macOSMajorVersion: 15).contains("warns"))
        #expect(SetupCopy.permissionNote(macOSMajorVersion: 27).contains("never clicks or types"))
        // Setup no longer closes itself once access is granted
        #expect(!SetupCopy.returnStep.contains("close"))
    }
}
