import Foundation
import CoreGraphics

// MARK: - Note Status

/// Where a note stands in the hand-off to a coding agent
public enum NoteStatus: String, Codable, CaseIterable, Sendable {
    /// Written, not yet picked up by an agent
    case pending
    /// An agent has read the note
    case seen
    /// An agent reports the change is made
    case done
    /// An agent (or the user) decided not to act on the note
    case dismissed

    public var displayName: String {
        switch self {
        case .pending: return "Open"
        case .seen: return "Seen by agent"
        case .done: return "Done"
        case .dismissed: return "Dismissed"
        }
    }

    /// Whether the note still needs work
    public var isOpen: Bool {
        self == .pending || self == .seen
    }
}

// MARK: - Note Reply

/// A message attached to a note, for example an agent explaining what it changed
public struct NoteReply: Identifiable, Equatable, Codable, Sendable {
    public enum Author: String, Codable, Sendable {
        case agent
        case user
    }

    public let id: UUID
    public let author: Author
    public let text: String
    public let createdAt: Date

    public init(id: UUID = UUID(), author: Author, text: String, createdAt: Date = Date()) {
        self.id = id
        self.author = author
        self.text = text
        self.createdAt = createdAt
    }
}

// MARK: - Annotation

/// Represents an annotation attached to an accessibility element
public struct Annotation: Identifiable, Equatable, Codable {
    public let id: UUID
    public let badgeNumber: Int
    public var text: String
    public let elementFrame: CGRect
    public let elementRole: String
    public let elementSubrole: String?
    public let elementIdentifier: String?
    public let elementTitle: String?
    /// The accessibility description, which names SwiftUI controls that have no title.
    /// Missing from notes saved before Loupe 2.0.
    public let elementDescription: String?
    public let elementValue: String?
    public let hierarchyPath: [HierarchyNode]
    public let windowTitle: String?
    /// Frame of the containing window when the note was made, so badges can follow the window
    public let windowFrame: CGRect?
    public let appName: String
    public let bundleIdentifier: String?
    public let createdAt: Date

    // Hand-off state
    public var status: NoteStatus
    public var replies: [NoteReply]
    public var updatedAt: Date

    // Extended properties for detailed/forensic output
    public let siblings: [SiblingInfo]
    public let windowLevel: Int?
    public let allAttributes: [String: String]?

    // Region ID if this annotation was created from a multi-select region
    public let regionId: UUID?

    /// Sibling context as a formatted string (backward-compatible computed property)
    public var siblingContext: String? {
        guard !siblings.isEmpty else { return nil }
        return siblings.map { $0.displayString }.joined(separator: ", ")
    }

    public init(
        id: UUID = UUID(),
        badgeNumber: Int,
        text: String,
        elementFrame: CGRect,
        elementRole: String,
        elementSubrole: String? = nil,
        elementIdentifier: String?,
        elementTitle: String? = nil,
        elementDescription: String? = nil,
        elementValue: String? = nil,
        hierarchyPath: [HierarchyNode] = [],
        windowTitle: String? = nil,
        windowFrame: CGRect? = nil,
        appName: String = "",
        bundleIdentifier: String? = nil,
        createdAt: Date = Date(),
        status: NoteStatus = .pending,
        replies: [NoteReply] = [],
        siblings: [SiblingInfo] = [],
        windowLevel: Int? = nil,
        allAttributes: [String: String]? = nil,
        regionId: UUID? = nil
    ) {
        self.id = id
        self.badgeNumber = badgeNumber
        self.text = text
        self.elementFrame = elementFrame
        self.elementRole = elementRole
        self.elementSubrole = elementSubrole
        self.elementIdentifier = elementIdentifier
        self.elementTitle = elementTitle
        self.elementDescription = elementDescription
        self.elementValue = elementValue
        self.hierarchyPath = hierarchyPath
        self.windowTitle = windowTitle
        self.windowFrame = windowFrame
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.createdAt = createdAt
        self.status = status
        self.replies = replies
        self.updatedAt = createdAt
        self.siblings = siblings
        self.windowLevel = windowLevel
        self.allAttributes = allAttributes
        self.regionId = regionId
    }

    /// The key notes are grouped under: the app's bundle ID, or its name when there is none
    public var appKey: String {
        AnnotationStore.appKey(bundleIdentifier: bundleIdentifier, appName: appName)
    }

    /// AI-friendly location string for identifying this element
    public var aiLocationString: String {
        hierarchyPath.aiLocationString
    }

    /// Display label formatted according to the naming style
    /// - Parameter style: The naming style to use
    /// - Returns: Formatted element name
    public func displayLabel(style: NamingStyle) -> String {
        switch style {
        case .humanized:
            return ElementKind.label(role: elementRole, title: elementTitle, description: elementDescription, value: elementValue, identifier: elementIdentifier)
        case .technical:
            return ElementKind.technicalLabel(role: elementRole, identifier: elementIdentifier, title: elementTitle, description: elementDescription)
        }
    }

    /// Search patterns that AI agents can use to find this element in code
    public var searchPatterns: [String] {
        SearchPatternGenerator.patterns(
            identifier: elementIdentifier, title: elementTitle, description: elementDescription, value: elementValue, role: elementRole
        )
    }

    /// Display label for the element (defaults to humanized)
    public var displayLabel: String {
        displayLabel(style: .humanized)
    }

    /// The element's frame adjusted for how far its window has moved since the note was made
    /// - Parameter currentWindowFrame: The window's frame now, in the same (AX) coordinates
    public func elementFrame(currentWindowFrame: CGRect?) -> CGRect {
        guard let original = windowFrame, let current = currentWindowFrame else { return elementFrame }
        return elementFrame.offsetBy(
            dx: current.origin.x - original.origin.x,
            dy: current.origin.y - original.origin.y
        )
    }

    /// Position for the badge (top-right corner of the element)
    public var badgePosition: CGPoint {
        CGPoint(
            x: elementFrame.maxX - 8,
            y: elementFrame.minY + 8
        )
    }
}

// MARK: - Annotation Store

/// Manages notes, grouped per app and saved to disk so they survive quitting Loupe.
///
/// `annotations` always holds the notes for the currently selected app.
@MainActor
public final class AnnotationStore: ObservableObject {
    /// Notes for the currently selected app
    @Published public private(set) var annotations: [Annotation] = []

    /// The app whose notes are in `annotations`
    public private(set) var currentAppKey: String?

    /// How many notes, across every app, end with a question from an agent
    /// that the person hasn't answered yet. Drives the menu bar's coral dot.
    @Published public private(set) var questionsForYou = 0

    /// Every app's notes, keyed by `appKey`
    private var notesByApp: [String: [Annotation]] = [:]

    /// Where notes are saved; nil keeps them in memory only
    private let fileURL: URL?

    /// Default location: Application Support/<bundle id>/Notes.json
    public static var defaultFileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = Bundle.main.bundleIdentifier ?? "Loupe"
        return support.appendingPathComponent(folder, isDirectory: true).appendingPathComponent("Notes.json")
    }

    /// The key notes are grouped under for an app
    public nonisolated static func appKey(bundleIdentifier: String?, appName: String) -> String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty { return bundleIdentifier }
        return appName
    }

    /// - Parameter fileURL: Where to save notes. Pass nil to keep notes in memory only.
    public init(fileURL: URL? = AnnotationStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
        recountQuestions()
    }

    // MARK: - App Selection

    /// Switch to another app's notes
    public func selectApp(key: String?) {
        currentAppKey = key
        refreshCurrent()
    }

    /// Notes for any app (used by the agent connection)
    public func notes(forAppKey key: String) -> [Annotation] {
        notesByApp[key] ?? []
    }

    /// Keys of every app that has notes
    public var appKeys: [String] {
        notesByApp.keys.filter { !(notesByApp[$0]?.isEmpty ?? true) }.sorted()
    }

    /// Find a note in any app
    public func note(id: UUID) -> Annotation? {
        for notes in notesByApp.values {
            if let note = notes.first(where: { $0.id == id }) { return note }
        }
        return nil
    }

    // MARK: - Editing

    /// Add a new annotation for an element
    public func addAnnotation(
        text: String,
        for element: AXElementInfo,
        windowTitle: String? = nil,
        appName: String = "",
        bundleIdentifier: String? = nil
    ) -> Annotation {
        let key = Self.appKey(bundleIdentifier: bundleIdentifier, appName: appName)
        let existing = notesByApp[key] ?? []
        let annotation = Annotation(
            badgeNumber: (existing.map(\.badgeNumber).max() ?? 0) + 1,
            text: text,
            elementFrame: element.frame,
            elementRole: element.role,
            elementSubrole: element.subrole,
            elementIdentifier: element.identifier,
            elementTitle: element.title,
            elementDescription: element.axDescription,
            elementValue: element.value,
            hierarchyPath: element.hierarchyPath,
            windowTitle: windowTitle,
            windowFrame: element.windowFrame,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            siblings: element.siblings,
            windowLevel: element.windowLevel,
            allAttributes: element.allAttributes
        )
        notesByApp[key, default: []].append(annotation)
        didChange()
        return annotation
    }

    /// Remove an annotation by ID
    public func removeAnnotation(id: UUID) {
        for key in notesByApp.keys {
            notesByApp[key]?.removeAll { $0.id == id }
        }
        didChange()
    }

    /// Update annotation text
    public func updateAnnotation(id: UUID, text: String) {
        modify(id: id) { $0.text = text }
    }

    /// Change a note's status, optionally adding a reply that explains why
    @discardableResult
    public func setStatus(id: UUID, to status: NoteStatus, message: String? = nil, author: NoteReply.Author = .agent) -> Annotation? {
        modify(id: id) { note in
            note.status = status
            if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                note.replies.append(NoteReply(author: author, text: message))
            }
        }
    }

    /// Add the user's own reply from the note window. Replying puts the note back to open
    /// (pending) so an agent's next look at the open notes picks it up again.
    @discardableResult
    public func addUserReply(id: UUID, text: String) -> Annotation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return note(id: id) }
        return modify(id: id) { note in
            note.replies.append(NoteReply(author: .user, text: trimmed))
            note.status = .pending
        }
    }

    /// Add a reply to a note
    @discardableResult
    public func addReply(id: UUID, text: String, author: NoteReply.Author) -> Annotation? {
        modify(id: id) { $0.replies.append(NoteReply(author: author, text: text)) }
    }

    /// Find annotation near a given point (for click detection)
    public func annotation(near point: CGPoint, tolerance: CGFloat = 20) -> Annotation? {
        annotations.first { annotation in
            let badgePos = annotation.badgePosition
            let distance = hypot(point.x - badgePos.x, point.y - badgePos.y)
            return distance <= tolerance
        }
    }

    /// Clear the current app's notes
    public func clear() {
        guard let key = currentAppKey else { return }
        notesByApp[key] = nil
        didChange()
    }

    // MARK: - Private

    @discardableResult
    private func modify(id: UUID, _ change: (inout Annotation) -> Void) -> Annotation? {
        for key in notesByApp.keys {
            if let index = notesByApp[key]?.firstIndex(where: { $0.id == id }) {
                change(&notesByApp[key]![index])
                notesByApp[key]![index].updatedAt = Date()
                let updated = notesByApp[key]![index]
                didChange()
                return updated
            }
        }
        return nil
    }

    private func didChange() {
        notesByApp = notesByApp.filter { !$0.value.isEmpty }
        refreshCurrent()
        recountQuestions()
        save()
    }

    private func recountQuestions() {
        let count = notesByApp.values.joined().filter { NoteAttention(note: $0) == .questionForYou }.count
        if count != questionsForYou { questionsForYou = count }
    }

    private func refreshCurrent() {
        annotations = currentAppKey.flatMap { notesByApp[$0] } ?? []
    }

    // MARK: - Persistence

    /// On-disk format, versioned so it can change later
    private struct SavedNotes: Codable {
        var version: Int
        var apps: [String: [Annotation]]
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let saved = try JSONDecoder.loupe.decode(SavedNotes.self, from: data)
            notesByApp = saved.apps
        } catch {
            // Keep the unreadable file aside rather than overwriting it
            let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            print("[Loupe] Could not read saved notes, moved aside: \(error)")
        }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.loupe.encode(SavedNotes(version: 1, apps: notesByApp))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[Loupe] Could not save notes: \(error)")
        }
    }
}

// MARK: - JSON Coding

extension JSONEncoder {
    static var loupe: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var loupe: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
