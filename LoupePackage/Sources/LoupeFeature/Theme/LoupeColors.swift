import AppKit
import SwiftUI

// MARK: - Brand Color Definitions

/// Loupe 2.0 palette: coral on ink.
extension Color {
    /// Brand coral. For shapes, outlines and icons, never for small text.
    static let loupeAccent = Color(hex: "#ff5b3a")
    /// Deeper coral behind white text (badges, prominent buttons): 4.6:1 with white.
    static let loupeAccentStrong = Color(hex: "#d63d1f")
    /// Coral for text: deeper in light mode, lighter in dark mode, so it stays readable.
    static let loupeAccentText = Color(nsColor: NSColor(name: "loupeAccentText") { appearance in
        appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil
            ? NSColor(srgbRed: 1, green: 0x7A / 255.0, blue: 0x5C / 255.0, alpha: 1)
            : NSColor(srgbRed: 0xD6 / 255.0, green: 0x3D / 255.0, blue: 0x1F / 255.0, alpha: 1)
    })
    static let loupeAccentDim = Color(hex: "#ff5b3a").opacity(0.2)
    static let loupeInk = Color(hex: "#14161b")

    // Semantic aliases
    static let loupeHighlight = Color.loupeAccent
    static let loupeBadge = Color.loupeAccentStrong
    static let loupeSuccess = Color.loupeAccent
    static let loupeActiveIcon = Color.loupeAccent
    static let loupeDelete = Color.red
}

// MARK: - Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
