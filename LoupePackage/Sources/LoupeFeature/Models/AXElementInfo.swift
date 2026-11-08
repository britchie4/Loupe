import Foundation
import ApplicationServices
import AppKit

// MARK: - Relative Position

/// Describes the spatial relationship of a sibling element
public enum RelativePosition: String, Equatable, Codable {
    case before  // Appears before in reading order (typically left/above)
    case after   // Appears after in reading order (typically right/below)
    case above   // Spatially above
    case below   // Spatially below
}

// MARK: - Sibling Info

/// Information about a sibling element for disambiguation context
public struct SiblingInfo: Equatable, Codable {
    public let role: String
    public let identifier: String?
    public let title: String?
    public let relativePosition: RelativePosition

    public init(
        role: String,
        identifier: String?,
        title: String?,
        relativePosition: RelativePosition
    ) {
        self.role = role
        self.identifier = identifier
        self.title = title
        self.relativePosition = relativePosition
    }

    /// Human-readable description of the sibling
    public var displayString: String {
        let cleanRole = role.hasPrefix("AX") ? String(role.dropFirst(2)).lowercased() : role.lowercased()
        let name: String
        if let title = title, !title.isEmpty {
            name = "\(cleanRole) \"\(title)\""
        } else if let identifier = identifier, !identifier.isEmpty {
            name = "\(cleanRole) (\(identifier))"
        } else {
            name = cleanRole
        }
        return "\(name) (\(relativePosition.rawValue))"
    }
}

// MARK: - Hierarchy Node

/// Represents a single node in the accessibility hierarchy with identifying attributes
public struct HierarchyNode: Equatable, Codable {
    public let role: String
    public let subrole: String?
    public let identifier: String?
    public let title: String?

    public init(role: String, subrole: String? = nil, identifier: String? = nil, title: String? = nil) {
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.title = title
    }

    /// Annotated string with identifying attributes: AXGroup[identifier="toolbar"]
    public var annotatedString: String {
        var attrs: [String] = []
        if let id = identifier, !id.isEmpty {
            attrs.append("identifier=\"\(id)\"")
        }
        if let t = title, !t.isEmpty {
            attrs.append("title=\"\(t)\"")
        }
        if attrs.isEmpty {
            return role
        }
        return "\(role)[\(attrs.joined(separator: ", "))]"
    }

    /// Just the role name for compact display
    public var roleString: String { role }
}

// MARK: - HierarchyNode Array Extension

extension Array where Element == HierarchyNode {
    /// AI-friendly location string: AXWindow[title="App"] > AXGroup[identifier="toolbar"] > AXButton
    public var aiLocationString: String {
        map { $0.annotatedString }.joined(separator: " > ")
    }
}

// MARK: - Search Pattern Generator

/// Generates search patterns for AI agents to locate elements in code
public struct SearchPatternGenerator {
    /// Generate search patterns for an element
    /// - Parameters:
    ///   - identifier: The element's accessibility identifier
    ///   - title: The element's title
    ///   - role: The element's AX role
    /// - Returns: Array of regex patterns
    public static func patterns(identifier: String?, title: String?, role: String) -> [String] {
        var patterns: [String] = []

        // Priority 1: Identifier-based patterns
        if let identifier = identifier, !identifier.isEmpty {
            patterns.append("accessibilityIdentifier.*\(identifier)")
            patterns.append(".accessibilityIdentifier\\(\"\(identifier)\"\\)")

            // SF Symbol patterns: identifier contains dots and no spaces
            if looksLikeSFSymbol(identifier) {
                patterns.append("Image\\(systemName: \"\(identifier)\"\\)")
                patterns.append("systemSymbolName.*\(identifier)")
                patterns.append("Label.*\(identifier)")
            }
        }

        // Priority 2: Title-based patterns
        if let title = title, !title.isEmpty {
            let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            patterns.append("Text\\(\"\(escapedTitle)\"\\)")
            patterns.append("Button\\(\"\(escapedTitle)\"\\)")
            patterns.append("\(role).*\(escapedTitle)")
        }

        return patterns
    }

    /// Heuristic: if the string contains dots and no spaces, it's likely an SF Symbol name
    private static func looksLikeSFSymbol(_ name: String) -> Bool {
        name.contains(".") && !name.contains(" ")
    }
}

// MARK: - AX Element Info

/// Represents metadata extracted from an AXUIElement
public struct AXElementInfo: Identifiable, Equatable {
    public let id = UUID()
    public let role: String
    public let subrole: String?
    public let identifier: String?
    public let title: String?
    public let value: String?
    public let frame: CGRect
    public let hierarchyPath: [HierarchyNode]

    /// The raw AXUIElement reference (for further queries if needed)
    public let element: AXUIElement

    // MARK: - Extended Properties (for detailed/forensic output)

    /// Sibling elements for disambiguation context
    public let siblings: [SiblingInfo]

    /// AXDescription attribute
    public let axDescription: String?

    /// AXHelp attribute
    public let help: String?

    /// AXRoleDescription attribute
    public let roleDescription: String?

    /// Whether the element is enabled
    public let enabled: Bool?

    /// Whether the element is focused
    public let focused: Bool?

    // MARK: - Window Context

    /// Frame of the containing window
    public let windowFrame: CGRect?

    /// Title of the containing window
    public let windowTitle: String?

    /// Window level (z-order)
    public let windowLevel: Int?

    // MARK: - Forensic Data

    /// All accessibility attributes (for forensic output mode)
    public let allAttributes: [String: String]?

    // MARK: - Initialization

    public init(
        role: String,
        subrole: String? = nil,
        identifier: String?,
        title: String?,
        value: String?,
        frame: CGRect,
        hierarchyPath: [HierarchyNode],
        element: AXUIElement,
        siblings: [SiblingInfo] = [],
        axDescription: String? = nil,
        help: String? = nil,
        roleDescription: String? = nil,
        enabled: Bool? = nil,
        focused: Bool? = nil,
        windowFrame: CGRect? = nil,
        windowTitle: String? = nil,
        windowLevel: Int? = nil,
        allAttributes: [String: String]? = nil
    ) {
        self.role = role
        self.subrole = subrole
        self.identifier = identifier
        self.title = title
        self.value = value
        self.frame = frame
        self.hierarchyPath = hierarchyPath
        self.element = element
        self.siblings = siblings
        self.axDescription = axDescription
        self.help = help
        self.roleDescription = roleDescription
        self.enabled = enabled
        self.focused = focused
        self.windowFrame = windowFrame
        self.windowTitle = windowTitle
        self.windowLevel = windowLevel
        self.allAttributes = allAttributes
    }

    // MARK: - Computed Properties

    /// Formatted hierarchy path for display (role names only)
    public var formattedPath: String {
        hierarchyPath.map { $0.roleString }.joined(separator: " → ")
    }

    /// AI-friendly location string for identifying this element in code
    /// Format: AXWindow[title="App"] > AXGroup[identifier="toolbar"] > AXButton[identifier="submit", title="Submit"]
    public var aiLocationString: String {
        hierarchyPath.aiLocationString
    }

    /// Display label formatted according to the naming style
    /// - Parameter style: The naming style to use
    /// - Returns: Formatted element name
    public func displayLabel(style: NamingStyle) -> String {
        switch style {
        case .humanized:
            let cleanRole = role.hasPrefix("AX") ? String(role.dropFirst(2)).lowercased() : role.lowercased()
            if let t = title, !t.isEmpty {
                return "\(cleanRole) \"\(t)\""
            } else if let id = identifier, !id.isEmpty {
                return "\(cleanRole) (\(id))"
            } else {
                return cleanRole
            }
        case .technical:
            var attrs: [String] = []
            if let id = identifier, !id.isEmpty {
                attrs.append("identifier=\"\(id)\"")
            }
            if let t = title, !t.isEmpty {
                attrs.append("title=\"\(t)\"")
            }
            if attrs.isEmpty {
                return role
            } else {
                return "\(role)[\(attrs.joined(separator: ", "))]"
            }
        }
    }

    /// Short display label for the element (defaults to humanized)
    public var displayLabel: String {
        displayLabel(style: .humanized)
    }

    /// Sibling context as a string for output
    public var siblingContextString: String? {
        guard !siblings.isEmpty else { return nil }
        return siblings.map { $0.displayString }.joined(separator: ", ")
    }

    /// Search patterns that AI agents can use to find this element in code
    public var searchPatterns: [String] {
        SearchPatternGenerator.patterns(identifier: identifier, title: title, role: role)
    }

    public static func == (lhs: AXElementInfo, rhs: AXElementInfo) -> Bool {
        // Compare by frame and role since AXUIElement isn't Equatable
        lhs.frame == rhs.frame && lhs.role == rhs.role && lhs.identifier == rhs.identifier
    }
}

// MARK: - Target App

/// Represents a running application that can be inspected
public struct TargetApp: Identifiable, Hashable {
    public let id: pid_t
    public let name: String
    public let bundleIdentifier: String?
    public let icon: NSImage?

    public init(from app: NSRunningApplication) {
        self.id = app.processIdentifier
        self.name = app.localizedName ?? "Unknown"
        self.bundleIdentifier = app.bundleIdentifier
        self.icon = app.icon
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: TargetApp, rhs: TargetApp) -> Bool {
        lhs.id == rhs.id
    }
}
