import SwiftUI
import AppKit

extension View {
    /// System Liquid Glass on macOS 26+, so the label follows the user's transparency setting;
    /// the lighter custom effect on earlier versions
    @ViewBuilder
    func loupeLabelGlassBackground(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(LightLiquidGlassBackground(cornerRadius: cornerRadius))
        }
    }
}

/// Small floating label showing the current element's role and title
public struct ElementLabelView: View {
    let role: String
    let title: String?
    let identifier: String?
    let namingStyle: NamingStyle

    public init(role: String, title: String?, identifier: String?, namingStyle: NamingStyle = .humanized) {
        self.role = role
        self.title = title
        self.identifier = identifier
        self.namingStyle = namingStyle
    }

    public var body: some View {
        Group {
            switch namingStyle {
            case .humanized:
                humanizedLabel
            case .technical:
                technicalLabel
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .loupeLabelGlassBackground(cornerRadius: 6)
    }

    /// Humanized label: `button "Save"` or `textField (email)`
    private var humanizedLabel: some View {
        HStack(spacing: 4) {
            Text(simplifiedRole)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            if let displayText = title ?? identifier {
                Text("\"\(displayText)\"")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
    }

    /// Technical label: `AXButton[title="Save"]`
    private var technicalLabel: some View {
        Text(technicalString)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.primary)
            .lineLimit(1)
    }

    /// Remove "AX" prefix from role for humanized display
    private var simplifiedRole: String {
        if role.hasPrefix("AX") {
            return String(role.dropFirst(2)).lowercased()
        }
        return role.lowercased()
    }

    /// Build technical string like `AXButton[title="Save"]`
    private var technicalString: String {
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

// MARK: - Light Liquid Glass Background

/// Lighter liquid glass effect for small UI elements like hover labels
/// Uses inner glow and multi-layer shadows but skips the border stroke for subtlety
private struct LightLiquidGlassBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            // Material backdrop
            shape
                .fill(.ultraThinMaterial)

            // Subtle inner glow
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
        // Multi-layer shadows (lighter than full effect)
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)   // Ambient
        .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)   // Near
    }
}

// MARK: - Element Label Window Controller

/// Controller for the floating element label window
@MainActor
public final class ElementLabelWindowController {

    private var window: NSWindow?
    private var hostingView: NSHostingView<ElementLabelView>?

    public init() {}

    /// Show the label near an element frame
    /// - Parameters:
    ///   - element: The accessibility element info
    ///   - highlightFrame: The element's frame in screen coordinates (AppKit coordinate system)
    ///   - namingStyle: The naming style to use for display
    public func show(for element: AXElementInfo, highlightFrame: CGRect, namingStyle: NamingStyle = .humanized) {
        let labelView = ElementLabelView(
            role: element.role,
            title: element.title,
            identifier: element.identifier,
            namingStyle: namingStyle
        )

        if window == nil {
            createWindow()
        }

        guard let window = window else { return }

        // Update content
        let hosting = NSHostingView(rootView: labelView)
        hosting.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        window.contentView = hosting

        // Size to fit content
        let fittingSize = hosting.fittingSize
        let labelSize = NSSize(
            width: min(fittingSize.width + 4, 300),
            height: fittingSize.height + 4
        )

        // Position above the highlight, centered horizontally
        let labelOrigin = NSPoint(
            x: highlightFrame.midX - labelSize.width / 2,
            y: highlightFrame.maxY + 8  // 8px above the element
        )

        // Ensure label stays on screen
        let adjustedOrigin = adjustOriginToScreen(labelOrigin, size: labelSize)

        window.setFrame(NSRect(origin: adjustedOrigin, size: labelSize), display: true)
        window.orderFront(nil)
    }

    /// Hide the label
    public func hide() {
        window?.orderOut(nil)
    }

    /// Update position without recreating content
    public func updatePosition(highlightFrame: CGRect) {
        guard let window = window, window.isVisible else { return }

        let labelSize = window.frame.size
        let labelOrigin = NSPoint(
            x: highlightFrame.midX - labelSize.width / 2,
            y: highlightFrame.maxY + 8
        )

        let adjustedOrigin = adjustOriginToScreen(labelOrigin, size: labelSize)
        window.setFrameOrigin(adjustedOrigin)
    }

    // MARK: - Private

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 24),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        self.window = window
    }

    private func adjustOriginToScreen(_ origin: NSPoint, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.screen(containing: origin) ?? NSScreen.primaryScreen else { return origin }

        let screenFrame = screen.visibleFrame
        var adjusted = origin

        // Keep within horizontal bounds
        if adjusted.x < screenFrame.minX {
            adjusted.x = screenFrame.minX + 4
        } else if adjusted.x + size.width > screenFrame.maxX {
            adjusted.x = screenFrame.maxX - size.width - 4
        }

        // Keep within vertical bounds
        if adjusted.y + size.height > screenFrame.maxY {
            // Place below the element if it would go off top
            adjusted.y = origin.y - size.height - 16 - 8
        }
        if adjusted.y < screenFrame.minY {
            adjusted.y = screenFrame.minY + 4
        }

        return adjusted
    }
}
