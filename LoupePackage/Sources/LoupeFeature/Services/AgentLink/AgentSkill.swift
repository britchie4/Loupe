import Foundation
import CryptoKit

/// A skill Agent Link serves to coding agents through the MCP Skills extension
/// (`io.modelcontextprotocol/skills`): a folder with a `SKILL.md` and any supporting files.
///
/// Agents that support the extension get Loupe's playbook straight from Loupe, matching the
/// installed version, with nothing separate to install. The same files live in the
/// repository's `skills/` folder for agents that install skills from disk.
public struct AgentSkill: Sendable, Equatable {

    /// One file in the skill, with its path relative to the skill's folder
    public struct File: Sendable, Equatable {
        public let path: String
        public let data: Data
    }

    public let name: String
    /// Every frontmatter field of `SKILL.md`, unchanged
    public let frontmatter: [String: String]
    /// `SKILL.md` first, then the rest by path
    public let files: [File]

    /// The Skills extension's identifier, as servers declare it in their capabilities
    static let extensionID = "io.modelcontextprotocol/skills"

    public init?(name: String, files: [File]) {
        guard let skillFile = files.first(where: { $0.path == "SKILL.md" }),
              let text = String(data: skillFile.data, encoding: .utf8),
              let frontmatter = Self.parseFrontmatter(text),
              frontmatter["name"] == name,
              frontmatter["description"]?.isEmpty == false
        else { return nil }
        self.name = name
        self.frontmatter = frontmatter
        self.files = [skillFile] + files.filter { $0.path != "SKILL.md" }.sorted { $0.path < $1.path }
    }

    // MARK: - URIs

    public var skillURI: String { uri(for: "SKILL.md") }

    func uri(for path: String) -> String { "skill://\(name)/\(path)" }

    func file(at uri: String) -> File? {
        files.first { self.uri(for: $0.path) == uri }
    }

    // MARK: - Protocol Shapes

    /// The entry `skills/list` and `skills/get` return: frontmatter plus a manifest of every file
    var entry: JSONValue {
        [
            "uri": .string(skillURI),
            "frontmatter": .object(frontmatter.mapValues { .string($0) }),
            "resources": .array(files.map { file in
                [
                    "uri": .string(uri(for: file.path)),
                    "digest": .string(Self.digest(file.data)),
                    "size": .int(file.data.count),
                ]
            }),
        ]
    }

    /// What `resources/read` returns for one of this skill's files
    func contents(of file: File) -> JSONValue {
        [
            "uri": .string(uri(for: file.path)),
            "mimeType": .string(Self.mimeType(for: file.path)),
            "text": .string(String(decoding: file.data, as: UTF8.self)),
        ]
    }

    static func digest(_ data: Data) -> String {
        "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func mimeType(for path: String) -> String {
        path.hasSuffix(".md") ? "text/markdown" : "text/plain"
    }

    // MARK: - Frontmatter

    /// The `key: value` lines between the opening and closing `---` of a SKILL.md.
    /// Loupe's skills use plain one-line values, which is all this reads.
    static func parseFrontmatter(_ text: String) -> [String: String]? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }

        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty { fields[key] = value }
        }
        return fields
    }

    // MARK: - Loading

    /// Read every skill in a folder of skill folders
    static func load(from directory: URL) -> [AgentSkill] {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.sorted().compactMap { name in
            let root = directory.appendingPathComponent(name, isDirectory: true).resolvingSymlinksInPath()
            let rootComponents = root.pathComponents
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return nil }
            var files: [File] = []
            for case let url as URL in enumerator {
                let resolved = url.resolvingSymlinksInPath()
                guard (try? resolved.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                      resolved.pathComponents.starts(with: rootComponents),
                      let data = try? Data(contentsOf: resolved) else { continue }
                let path = resolved.pathComponents.dropFirst(rootComponents.count).joined(separator: "/")
                files.append(File(path: path, data: data))
            }
            return AgentSkill(name: name, files: files)
        }
    }

    /// The skills that ship inside Loupe
    public static let bundled: [AgentSkill] = {
        guard let directory = Bundle.module.url(forResource: "Skills", withExtension: nil) else { return [] }
        return load(from: directory)
    }()
}
