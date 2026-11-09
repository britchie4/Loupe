import Foundation

// MARK: - Output Format

/// Defines the level of detail in generated feedback output
public enum OutputFormat: String, CaseIterable, Identifiable {
    case detailed = "detailed"
    case forensic = "forensic"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .detailed: return "Detailed"
        case .forensic: return "Forensic"
        }
    }

    public var description: String {
        switch self {
        case .detailed:
            return "Location, search patterns, siblings, disambiguation"
        case .forensic:
            return "Detailed + all AX attributes and frame coordinates"
        }
    }
}

// MARK: - Naming Style

/// Controls how element names are displayed in output
public enum NamingStyle: String, CaseIterable, Identifiable {
    case humanized = "humanized"
    case technical = "technical"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .humanized: return "Humanized"
        case .technical: return "Technical"
        }
    }

    public var description: String {
        switch self {
        case .humanized:
            return "button \"Save\", textField (email)"
        case .technical:
            return "AXButton[title=\"Save\"], AXTextField[identifier=\"email\"]"
        }
    }
}

// MARK: - Settings Model

/// Observable settings model with UserDefaults persistence
@Observable
public final class LoupeSettings {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let outputFormat = "loupe.outputFormat"
        static let namingStyle = "loupe.namingStyle"
        static let agentLinkEnabled = "loupe.agentLinkEnabled"
    }

    /// Posted when Agent Link is turned on or off
    public static let agentLinkEnabledDidChange = Notification.Name("loupe.agentLinkEnabledDidChange")

    // MARK: - Properties

    /// The level of detail for generated feedback output
    public var outputFormat: OutputFormat {
        didSet {
            UserDefaults.standard.set(outputFormat.rawValue, forKey: Keys.outputFormat)
        }
    }

    /// How element names are displayed (humanized vs technical)
    public var namingStyle: NamingStyle {
        didSet {
            UserDefaults.standard.set(namingStyle.rawValue, forKey: Keys.namingStyle)
        }
    }

    /// Whether coding agents may connect to Loupe (off until the user turns it on)
    public var agentLinkEnabled: Bool {
        didSet {
            UserDefaults.standard.set(agentLinkEnabled, forKey: Keys.agentLinkEnabled)
            NotificationCenter.default.post(name: Self.agentLinkEnabledDidChange, object: self)
        }
    }

    // MARK: - Initialization

    public init() {
        // Load persisted values or use defaults
        if let formatString = UserDefaults.standard.string(forKey: Keys.outputFormat),
           let format = OutputFormat(rawValue: formatString) {
            self.outputFormat = format
        } else {
            self.outputFormat = .detailed
        }

        if let styleString = UserDefaults.standard.string(forKey: Keys.namingStyle),
           let style = NamingStyle(rawValue: styleString) {
            self.namingStyle = style
        } else {
            self.namingStyle = .humanized
        }

        self.agentLinkEnabled = UserDefaults.standard.bool(forKey: Keys.agentLinkEnabled)
    }

    // MARK: - Reset

    /// Reset all settings to defaults
    public func resetToDefaults() {
        outputFormat = .detailed
        namingStyle = .humanized
    }
}
