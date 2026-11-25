import Testing
import Foundation
import CryptoKit
@testable import LoupeFeature

/// The loupe-notes skill that ships inside Loupe and in the repository's skills/ folder
struct AgentSkillTests {

    /// The repository's skills/ folder, which `npx skills add` installs from
    private var repositorySkills: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LoupeFeatureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // LoupePackage
            .deletingLastPathComponent() // repository
            .appendingPathComponent("skills", isDirectory: true)
    }

    private var bundledNotesSkill: AgentSkill? {
        AgentSkill.bundled.first { $0.name == "loupe-notes" }
    }

    @Test func loupeShipsTheNotesSkill() throws {
        let skill = try #require(bundledNotesSkill)
        #expect(skill.files.first?.path == "SKILL.md")
        #expect(skill.files.map(\.path).contains("references/finding-the-element.md"))
        #expect(skill.files.map(\.path).contains("references/checking-and-reporting.md"))
        #expect(skill.frontmatter["description"]?.contains("Loupe") == true)
    }

    @Test func bundledSkillMatchesTheRepositoryCopy() throws {
        // Agents that read skills from disk install the repository copy; agents that get it from
        // Loupe get the bundled one. They must be the same, file for file and byte for byte.
        let fromRepository = AgentSkill.load(from: repositorySkills)
        #expect(!fromRepository.isEmpty)
        #expect(fromRepository == AgentSkill.bundled)
    }

    @Test func everyLinkInTheSkillResolvesToAFileItShips() throws {
        let skill = try #require(bundledNotesSkill)
        let paths = Set(skill.files.map(\.path))
        for file in skill.files {
            let text = String(decoding: file.data, as: UTF8.self)
            // Relative markdown links, such as [finding the element](references/finding-the-element.md)
            let links = text.matches(of: #/\]\(([^)#:]+)\)/#).map { String($0.1) }
            let folder = (file.path as NSString).deletingLastPathComponent
            for link in links {
                let target = ((folder as NSString).appendingPathComponent(link) as NSString).standardizingPath
                #expect(paths.contains(target), "\(file.path) links to \(link), which the skill doesn't include")
            }
        }
    }

    @Test func readsFrontmatter() {
        let text = "---\nname: demo\ndescription: \"Quoted: with a colon\"\n---\n\n# Demo\n"
        #expect(AgentSkill.parseFrontmatter(text) == ["name": "demo", "description": "Quoted: with a colon"])
        #expect(AgentSkill.parseFrontmatter("# No frontmatter\n") == nil)
    }

    @Test func refusesASkillWhoseNameDoesNotMatchItsFolder() {
        let data = Data("---\nname: other\ndescription: Something\n---\n".utf8)
        #expect(AgentSkill(name: "demo", files: [.init(path: "SKILL.md", data: data)]) == nil)
    }
}

/// Agent Link serving skills, in the order a skills-aware agent asks for them
@MainActor
struct MCPSkillsTests {

    private let modernMeta = #""_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"claude-code","title":"Claude Code"}}"#

    private func handler() -> MCPHandler {
        MCPHandler(tools: [], skills: AgentSkill.bundled)
    }

    private func reply(_ handler: MCPHandler, _ json: String) throws -> JSONValue {
        try JSONValue.parse(try #require(handler.handle(line: Data(json.utf8))))
    }

    @Test func discoverAnnouncesSkillsAndNamesTheAgent() throws {
        let handler = handler()
        var agent: String?
        handler.onClientIdentified = { agent = $0 }

        let response = try reply(handler, #"{"jsonrpc":"2.0","id":"x","method":"server/discover","params":{\#(modernMeta)}}"#)
        let result = try #require(response["result"])
        #expect(result["resultType"] == "complete")
        #expect(result["supportedVersions"] == ["2026-07-28"])
        #expect(result["capabilities"]?["resources"] != nil)
        #expect(result["capabilities"]?["extensions"]?["io.modelcontextprotocol/skills"] == [:])
        #expect(result["_meta"]?["io.modelcontextprotocol/serverInfo"]?["name"] == "loupe")
        #expect(result["instructions"]?.stringValue?.contains("skill://loupe-notes/SKILL.md") == true)
        #expect(result["ttlMs"]?.intValue ?? -1 >= 0)
        #expect(result["cacheScope"] == "public")
        #expect(agent == "Claude Code")
    }

    @Test func olderAgentsLearnAboutSkillsInTheHandshake() throws {
        let response = try reply(handler(), #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}"#)
        #expect(response["result"]?["capabilities"]?["extensions"]?["io.modelcontextprotocol/skills"] == [:])
        // Older agents get results in the older shape
        let tools = try reply(handler(), #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
        #expect(tools["result"]?["resultType"] == nil)
    }

    @Test func unsupportedModernVersionListsTheOnesLoupeSpeaks() throws {
        let response = try reply(handler(), #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2099-01-01"}}}"#)
        #expect(response["error"]?["code"] == -32022)
        #expect(response["error"]?["data"]?["requested"] == "2099-01-01")
        guard case .array(let supported)? = response["error"]?["data"]?["supported"] else {
            Issue.record("No supported versions listed")
            return
        }
        #expect(supported.contains("2026-07-28"))
        #expect(supported.contains("2025-11-25"))
    }

    /// Load the skill the way the spec tells a host to: list it, read each file in the manifest,
    /// and check every file's size and digest, and SKILL.md's frontmatter, against the listing.
    @Test func skillVerifiesTheWayAHostChecksIt() throws {
        let handler = handler()
        let list = try reply(handler, #"{"jsonrpc":"2.0","id":1,"method":"skills/list","params":{\#(modernMeta)}}"#)
        #expect(list["result"]?["resultType"] == "complete")
        #expect(list["result"]?["cacheScope"] == "public")
        guard case .array(let entries)? = list["result"]?["skills"], let entry = entries.first else {
            Issue.record("No skills listed")
            return
        }
        #expect(entry["uri"] == "skill://loupe-notes/SKILL.md")
        #expect(entry["frontmatter"]?["name"] == "loupe-notes")

        guard case .array(let manifest)? = entry["resources"] else {
            Issue.record("No manifest")
            return
        }
        #expect(manifest.count == 3)
        for (index, file) in manifest.enumerated() {
            let uri = try #require(file["uri"]?.stringValue)
            let read = try reply(handler, #"{"jsonrpc":"2.0","id":\#(index + 10),"method":"resources/read","params":{"uri":"\#(uri)",\#(modernMeta)}}"#)
            #expect(read["result"]?["resultType"] == "complete")
            let content = try #require(read["result"]?["contents"].flatMap { if case .array(let items) = $0 { items.first } else { nil } })
            #expect(content["uri"]?.stringValue == uri)
            #expect(content["mimeType"] == "text/markdown")
            let bytes = Data(try #require(content["text"]?.stringValue).utf8)
            #expect(file["size"]?.intValue == bytes.count)
            let digest = "sha256:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            #expect(file["digest"]?.stringValue == digest, "\(uri) doesn't match its manifest digest")

            if uri.hasSuffix("/SKILL.md") {
                let parsed = try #require(AgentSkill.parseFrontmatter(String(decoding: bytes, as: UTF8.self)))
                #expect(.object(parsed.mapValues { .string($0) }) == entry["frontmatter"])
            }
        }
    }

    @Test func getsASkillByURIAndRefusesUnknownOnes() throws {
        let handler = handler()
        let known = try reply(handler, #"{"jsonrpc":"2.0","id":1,"method":"skills/get","params":{"uri":"skill://loupe-notes/SKILL.md"}}"#)
        #expect(known["result"]?["skill"]?["uri"] == "skill://loupe-notes/SKILL.md")

        let unknownSkill = try reply(handler, #"{"jsonrpc":"2.0","id":2,"method":"skills/get","params":{"uri":"skill://nope/SKILL.md"}}"#)
        #expect(unknownSkill["error"]?["code"] == -32602)

        let unknownFile = try reply(handler, #"{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"skill://loupe-notes/missing.md"}}"#)
        #expect(unknownFile["error"]?["code"] == -32602)

        let outsideTheSkill = try reply(handler, #"{"jsonrpc":"2.0","id":4,"method":"resources/read","params":{"uri":"skill://loupe-notes/../../etc/passwd"}}"#)
        #expect(outsideTheSkill["error"]?["code"] == -32602)
    }

    @Test func generalResourceListingStaysEmpty() throws {
        let list = try reply(handler(), #"{"jsonrpc":"2.0","id":1,"method":"resources/list","params":{\#(modernMeta)}}"#)
        #expect(list["result"]?["resources"] == [])
    }
}
