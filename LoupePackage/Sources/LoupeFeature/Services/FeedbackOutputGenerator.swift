import Foundation
import AppKit

/// Generates markdown output from annotations for AI agents
public struct FeedbackOutputGenerator {

    public init() {}

    // MARK: - Element Naming

    /// Generate element name for an annotation (always technical for agent output)
    private func elementName(for annotation: Annotation) -> String {
        annotation.displayLabel(style: .technical)
    }

    // MARK: - Search Patterns

    /// Generate search patterns prioritized for identifier-first lookup
    /// - Parameter annotation: The annotation to generate patterns for
    /// - Returns: Array of regex patterns
    private func searchPatterns(for annotation: Annotation) -> [String] {
        annotation.searchPatterns
    }

    // MARK: - Disambiguation

    /// Generate a disambiguation hint using sibling context
    /// - Parameter annotation: The annotation to generate a hint for
    /// - Returns: A prose hint string, or nil if no useful context is available
    private func disambiguationHint(for annotation: Annotation) -> String? {
        guard !annotation.siblings.isEmpty else { return nil }

        // Find the most descriptive nearby sibling (prefer one with a title)
        let bestSibling = annotation.siblings.first { $0.title != nil && !($0.title?.isEmpty ?? true) }
            ?? annotation.siblings.first { $0.identifier != nil && !($0.identifier?.isEmpty ?? true) }

        guard let sibling = bestSibling else { return nil }

        let siblingDesc: String
        let cleanRole = sibling.role.hasPrefix("AX") ? String(sibling.role.dropFirst(2)).lowercased() : sibling.role.lowercased()
        if let title = sibling.title, !title.isEmpty {
            siblingDesc = "\(cleanRole) \"\(title)\""
        } else if let identifier = sibling.identifier, !identifier.isEmpty {
            siblingDesc = "\(cleanRole) (\(identifier))"
        } else {
            return nil
        }

        // Build the search term from the annotation's identifier or title
        let searchTerm: String
        if let id = annotation.elementIdentifier, !id.isEmpty {
            searchTerm = id
        } else if let name = ElementKind.accessibleName(title: annotation.elementTitle, description: annotation.elementDescription) {
            searchTerm = name
        } else {
            return nil
        }

        return "This element is near \(siblingDesc) — search for \"\(searchTerm)\" alongside \"\(sibling.title ?? sibling.identifier ?? "")\" in the same container"
    }

    // MARK: - Format Generation

    /// Generate detailed format output (location, search patterns, siblings, disambiguation)
    private func generateDetailed(
        annotations: [Annotation],
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String?
    ) -> String {
        var output = ""

        // Header with screen info
        output += "## App Feedback: \(appName)\n"
        if let bundleId = bundleIdentifier {
            output += "**Bundle ID:** \(bundleId)\n"
        }
        if let window = windowTitle {
            output += "**Window:** \(window)\n"
        }
        if let screen = NSScreen.main {
            let size = screen.frame.size
            output += "**Screen:** \(Int(size.width))×\(Int(size.height))\n"
        }
        output += "\n"

        if annotations.isEmpty {
            output += "_No annotations recorded._\n"
            return output
        }

        for annotation in annotations {
            let name = elementName(for: annotation)
            output += "### \(annotation.badgeNumber). \(name)\n"
            output += "**Location:** \(annotation.aiLocationString)\n"

            if let identifier = annotation.elementIdentifier, !identifier.isEmpty {
                output += "**Identifier:** \(identifier)\n"
            }

            // Siblings (if available in the annotation)
            if let siblings = annotation.siblingContext, !siblings.isEmpty {
                output += "**Siblings:** \(siblings)\n"
            }

            // Window context
            if let window = annotation.windowTitle {
                output += "**Window:** \(window)\n"
            }

            // Search patterns
            let patterns = searchPatterns(for: annotation)
            if !patterns.isEmpty {
                output += "**Search patterns:**\n"
                for pattern in patterns {
                    output += "- `\(pattern)`\n"
                }
            }

            // Disambiguation hint
            if let hint = disambiguationHint(for: annotation) {
                output += "**Disambiguation:** \(hint)\n"
            }

            output += "**Feedback:** \(annotation.text)\n\n"
        }

        return output
    }

    /// Generate forensic format output (detailed + all AX attributes and frame coordinates)
    private func generateForensic(
        annotations: [Annotation],
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String?
    ) -> String {
        var output = ""

        // Full header
        output += "## App Feedback: \(appName)\n"
        if let bundleId = bundleIdentifier {
            output += "**Bundle ID:** \(bundleId)\n"
        }
        if let window = windowTitle {
            output += "**Window:** \(window)\n"
        }
        if let screen = NSScreen.main {
            let size = screen.frame.size
            output += "**Screen:** \(Int(size.width))×\(Int(size.height))\n"
        }
        output += "\n"

        if annotations.isEmpty {
            output += "_No annotations recorded._\n"
            return output
        }

        for annotation in annotations {
            let name = elementName(for: annotation)
            output += "### \(annotation.badgeNumber). \(name)\n"
            output += "**Location:** \(annotation.aiLocationString)\n"

            if let identifier = annotation.elementIdentifier, !identifier.isEmpty {
                output += "**Identifier:** \(identifier)\n"
            }

            // Siblings
            if let siblings = annotation.siblingContext, !siblings.isEmpty {
                output += "**Siblings:** \(siblings)\n"
            }

            // Window context with level
            if let window = annotation.windowTitle {
                if let level = annotation.windowLevel {
                    output += "**Window:** \(window) (level: \(level))\n"
                } else {
                    output += "**Window:** \(window)\n"
                }
            }

            // Element frame
            let frame = annotation.elementFrame
            output += "**Frame:** x=\(Int(frame.origin.x)), y=\(Int(frame.origin.y)), w=\(Int(frame.width)), h=\(Int(frame.height))\n"

            // All attributes (forensic mode)
            if let allAttrs = annotation.allAttributes, !allAttrs.isEmpty {
                output += "**All Attributes:**\n"
                for (key, value) in allAttrs.sorted(by: { $0.key < $1.key }) {
                    output += "- \(key): \(value)\n"
                }
            }

            // Search patterns
            let patterns = searchPatterns(for: annotation)
            if !patterns.isEmpty {
                output += "**Search patterns:**\n"
                for pattern in patterns {
                    output += "- `\(pattern)`\n"
                }
            }

            // Disambiguation hint
            if let hint = disambiguationHint(for: annotation) {
                output += "**Disambiguation:** \(hint)\n"
            }

            output += "**Feedback:** \(annotation.text)\n\n"
        }

        return output
    }

    // MARK: - Public API

    /// Generate markdown feedback document from annotations
    /// - Parameters:
    ///   - annotations: The list of annotations to include
    ///   - appName: Name of the inspected application
    ///   - bundleIdentifier: Bundle ID of the inspected application
    ///   - windowTitle: Title of the inspected window
    ///   - settings: Output settings (format selection)
    /// - Returns: Formatted markdown string
    public func generateMarkdown(
        annotations: [Annotation],
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String?,
        settings: LoupeSettings
    ) -> String {
        switch settings.outputFormat {
        case .detailed:
            return generateDetailed(
                annotations: annotations,
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle
            )
        case .forensic:
            return generateForensic(
                annotations: annotations,
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                windowTitle: windowTitle
            )
        }
    }

    /// Generate markdown with default detailed format
    public func generateMarkdown(
        annotations: [Annotation],
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String?
    ) -> String {
        generateDetailed(
            annotations: annotations,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle
        )
    }

    /// Copy markdown to clipboard using specified settings
    public func copyToClipboard(
        annotations: [Annotation],
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String?,
        settings: LoupeSettings
    ) {
        let markdown = generateMarkdown(
            annotations: annotations,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle,
            settings: settings
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    /// Copy markdown to clipboard with default detailed format
    public func copyToClipboard(
        annotations: [Annotation],
        appName: String,
        bundleIdentifier: String?,
        windowTitle: String?
    ) {
        let markdown = generateMarkdown(
            annotations: annotations,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            windowTitle: windowTitle
        )

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}
