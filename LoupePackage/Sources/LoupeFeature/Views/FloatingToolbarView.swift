import SwiftUI

// MARK: - Liquid Glass Background

extension View {
    /// Applies Apple's liquid glass effect on macOS 26+, falling back to a polished custom effect on earlier versions
    ///
    /// The custom fallback creates a premium "liquid glass" appearance using:
    /// - Translucent material backdrop with blur
    /// - Multi-layered shadows (soft ambient + sharper near-shadow)
    /// - Inner glow overlay for depth
    /// - Subtle gradient border stroke that catches light
    @ViewBuilder
    func loupeGlassBackground(cornerRadius: CGFloat = 12) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(
                LiquidGlassBackground(cornerRadius: cornerRadius)
            )
        }
    }
}

/// Custom liquid glass background that mimics Apple's premium glass effect
///
/// Layered composition (bottom to top):
/// 1. Outer shadows - create depth and lift
/// 2. Material fill - frosted glass with blur
/// 3. Inner glow overlay - adds dimensional thickness
/// 4. Gradient border stroke - catches light on edges
private struct LiquidGlassBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            // Layer 1: Material backdrop (frosted glass effect)
            shape
                .fill(.ultraThinMaterial)

            // Layer 2: Inner glow - gradient from top creates "thickness"
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Layer 3: Subtle gradient border stroke
            shape
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.15),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        // Multi-layered shadows for depth:
        // - Soft ambient shadow (large, diffuse)
        // - Near shadow (smaller, sharper, gives "lift")
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 8)  // Ambient
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)    // Near
    }
}

/// Floating toolbar for controlling inspection and managing annotations
///
/// Mental model:
/// - Collapsed = inspection OFF, target app has focus
/// - Expanded = inspection ON, Loupe owns focus
///
/// On macOS 26+, uses Apple's Liquid Glass morphing system with `GlassEffectContainer`
/// and `glassEffectID` for true glass-to-glass morphing animations. The Exit button
/// shares an ID with the collapsed eye icon, enabling seamless morphing between states.
public struct FloatingToolbarView: View {
    @Binding var isExpanded: Bool
    @Binding var selectedApp: TargetApp?
    let availableApps: [TargetApp]
    let showCopySuccess: Bool
    let annotationCount: Int
    let settings: LoupeSettings
    let onCopyFeedback: () -> Void
    let onClearAnnotations: () -> Void
    let onRefreshApps: () -> Void
    let onCheckForUpdates: () -> Void

    /// State for settings popover
    @State private var isSettingsPopoverPresented = false

    /// The open bar's natural width, measured while it's showing, so the single
    /// glass shape can animate between the icon and the bar (macOS 26+)
    @State private var expandedBarWidth: CGFloat = 275

    public init(
        isExpanded: Binding<Bool>,
        selectedApp: Binding<TargetApp?>,
        availableApps: [TargetApp],
        showCopySuccess: Bool,
        annotationCount: Int,
        settings: LoupeSettings,
        onCopyFeedback: @escaping () -> Void,
        onClearAnnotations: @escaping () -> Void,
        onRefreshApps: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void = {}
    ) {
        self._isExpanded = isExpanded
        self._selectedApp = selectedApp
        self.availableApps = availableApps
        self.showCopySuccess = showCopySuccess
        self.annotationCount = annotationCount
        self.settings = settings
        self.onCopyFeedback = onCopyFeedback
        self.onClearAnnotations = onClearAnnotations
        self.onRefreshApps = onRefreshApps
        self.onCheckForUpdates = onCheckForUpdates
    }

    public var body: some View {
        // Use Liquid Glass morphing on macOS 26+, fall back to legacy on earlier versions
        if #available(macOS 26.0, *) {
            morphingToolbar
        } else {
            legacyToolbar
        }
    }

    // MARK: - Liquid Glass Morphing Toolbar (macOS 26+)

    /// Morphing toolbar using Apple's GlassEffectContainer for true glass-to-glass animation.
    /// Uses a single unified glass effect that morphs between collapsed circle and expanded pill.
    @available(macOS 26.0, *)
    private var morphingToolbar: some View {
        // One glass shape that changes size, anchored to the bottom-right corner: opening
        // grows the bar out of the icon, closing shrinks it back into the icon in place.
        // (Two separate glass shapes handing off made the icon pinch in mid-bar and roll
        // to the corner, or jump to the middle before growing.)
        ZStack(alignment: .trailing) {
            if isExpanded {
                expandedMorphingContent
                    .transition(.opacity.animation(.easeOut(duration: 0.18)))
            } else {
                collapsedMorphingContent
                    .transition(.opacity.animation(.easeOut(duration: 0.18)))
            }
        }
        .frame(
            width: isExpanded ? expandedBarWidth : Self.iconGlassSize,
            height: isExpanded ? 52 : Self.iconGlassSize,
            alignment: .trailing
        )
        // Keep the buttons inside the glass while it grows
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 14 : Self.iconGlassSize / 2, style: .continuous))
        .glassEffect(
            .regular.interactive(!isExpanded),
            in: RoundedRectangle(cornerRadius: isExpanded ? 14 : Self.iconGlassSize / 2, style: .continuous)
        )
        // Collapsed, the circle sits 6 points in from the top and 10 from the right,
        // giving the 58 x 50 footprint the window expects
        .padding(.top, isExpanded ? 0 : 6)
        .padding(.trailing, isExpanded ? 0 : 10)
        .padding(.leading, isExpanded ? 0 : 4)
        .animation(.bouncy, value: isExpanded)
        // The overall footprint jumps straight to its final size (no animation), so the
        // window resizes once while the glass animates inside it
        .frame(
            width: isExpanded ? expandedBarWidth : 58,
            height: isExpanded ? 52 : 50,
            alignment: .bottomTrailing
        )
        // Note: No manual shadows here — glassEffect provides its own depth and shadow.
        // Adding shadows to the GlassEffectContainer creates a rectangular outline
        // because the container has rectangular bounds, not rounded ones.
        .contextMenu {
            Button("Check for Updates…") {
                onCheckForUpdates()
            }
            Button("Quit Loupe") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Collapsed state: App icon with badge, tappable to expand.
    /// Uses a ZStack so the badge renders above the glass compositing layer.
    @available(macOS 26.0, *)
    private var collapsedMorphingContent: some View {
        // The open-note count is drawn by the window, not here, so it doesn't ride
        // the icon's spring (see CollapsedCountBadge). Clicks and drags on the
        // collapsed icon are handled by the window (FloatingToolbarWindowController.handleIconMouse).
        LoupeMark()
            .frame(width: 34, height: 30)
            .frame(width: Self.iconGlassSize, height: Self.iconGlassSize)
            .contentShape(Circle())
            .help("Click to open. Drag to move.")
    }

    /// Expanded state: Single unified glass effect spanning entire toolbar
    @available(macOS 26.0, *)
    private var expandedMorphingContent: some View {
        HStack(spacing: 8) {
            // App Picker
            AppIconPicker(
                selectedApp: $selectedApp,
                availableApps: availableApps,
                onRefresh: onRefreshApps
            )

            Divider()
                .frame(height: 24)

            // Copy feedback (with success animation)
            CopyButton(
                showSuccess: showCopySuccess,
                isDisabled: annotationCount == 0,
                action: onCopyFeedback
            )

            // Clear annotations
            ToolbarButton(
                icon: "trash",
                label: "Clear",
                isActive: false,
                isDisabled: annotationCount == 0
            ) {
                onClearAnnotations()
            }

            // Settings
            ToolbarButton(
                icon: "gearshape",
                label: "Settings",
                isActive: isSettingsPopoverPresented,
                isDisabled: false
            ) {
                isSettingsPopoverPresented.toggle()
            }
            .popover(isPresented: $isSettingsPopoverPresented, arrowEdge: .bottom) {
                SettingsView(settings: settings)
            }

            Divider()
                .frame(height: 24)

            // Exit (collapse toolbar)
            ToolbarButton(
                icon: "xmark",
                label: "Exit",
                isActive: false
            ) {
                // The toolbar animates this change itself (see morphingToolbar)
                isExpanded = false
            }
        }
        .padding(8)
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if abs(width - expandedBarWidth) > 0.5 { expandedBarWidth = width }
        }
    }

    /// Diameter of the collapsed icon's glass circle
    static let iconGlassSize: CGFloat = 44

    // MARK: - Legacy Toolbar (Pre-macOS 26)

    /// Single container that morphs between collapsed circle and expanded pill
    /// Opening it from the collapsed state is handled by the window, not a gesture here
    private var legacyToolbar: some View {
        // Single morphing container with crossfading content
        ZStack {
            // Collapsed icon - fades out quickly as expansion starts
            legacyCollapsedContent
                .opacity(isExpanded ? 0 : 1)
                .scaleEffect(isExpanded ? 0.3 : 1)

            // Expanded toolbar - fades in as container expands
            legacyExpandedContent
                .padding(8)
                .opacity(isExpanded ? 1 : 0)
                .scaleEffect(isExpanded ? 1 : 0.5)
        }
        // Animate container size between fixed values (both numeric = animatable)
        .frame(
            width: isExpanded ? 288 : 58,
            height: isExpanded ? 52 : 50
        )
        .loupeGlassBackground(cornerRadius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .animation(.smooth(duration: 0.4), value: isExpanded)
        .help(isExpanded ? "" : "Click to open. Drag to move.")
        // Clicks and drags on the collapsed icon are handled by the window
        // (FloatingToolbarWindowController.handleIconMouse)
        .contextMenu {
            Button("Check for Updates…") {
                onCheckForUpdates()
            }
            Button("Quit Loupe") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Content shown when collapsed - just the app icon and badge (legacy)
    private var legacyCollapsedContent: some View {
        LoupeMark()
            .frame(width: 34, height: 30)
            .frame(width: 52, height: 44)
            .padding(.top, 6)
            .padding(.trailing, 6)
    }

    /// Content shown when expanded - the full toolbar buttons (legacy)
    private var legacyExpandedContent: some View {
        HStack(spacing: 8) {
            // App icon picker
            AppIconPicker(
                selectedApp: $selectedApp,
                availableApps: availableApps,
                onRefresh: onRefreshApps
            )

            Divider()
                .frame(height: 24)

            // Copy feedback (with success animation)
            CopyButton(
                showSuccess: showCopySuccess,
                isDisabled: annotationCount == 0,
                action: onCopyFeedback
            )

            // Clear annotations
            ToolbarButton(
                icon: "trash",
                label: "Clear",
                isActive: false,
                isDisabled: annotationCount == 0
            ) {
                onClearAnnotations()
            }

            // Settings
            ToolbarButton(
                icon: "gearshape",
                label: "Settings",
                isActive: isSettingsPopoverPresented,
                isDisabled: false
            ) {
                isSettingsPopoverPresented.toggle()
            }
            .popover(isPresented: $isSettingsPopoverPresented, arrowEdge: .bottom) {
                SettingsView(settings: settings)
            }

            Divider()
                .frame(height: 24)

            // Exit (collapse toolbar and stop inspection)
            ToolbarButton(
                icon: "xmark",
                label: "Exit",
                isActive: false
            ) {
                withAnimation(.smooth(duration: 0.4)) {
                    isExpanded = false
                }
            }
        }
    }

}

// MARK: - Copy Button with Success Animation

/// Copy button with success animation using standard Button for reliable tap handling.
private struct CopyButton: View {
    let showSuccess: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            if !isDisabled {
                action()
            }
        }) {
            VStack(spacing: 2) {
                ZStack {
                    // Clipboard icon (fades out on success)
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isDisabled ? .gray : .primary)
                        .opacity(showSuccess ? 0 : 1)

                    // Checkmark icon (fades in on success)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.loupeSuccess)
                        .opacity(showSuccess ? 1 : 0)
                        .scaleEffect(showSuccess ? 1.0 : 0.5)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showSuccess)

                Text(showSuccess ? "Copied!" : "Copy")
                    .font(.system(size: 9))
                    .foregroundColor(showSuccess ? Color.loupeAccentText : .secondary)
                    .opacity(isDisabled && !showSuccess ? 0.5 : 1.0)
            }
            .frame(width: 40, height: 36)
        }
        .buttonStyle(ToolbarButtonStyle())
        .disabled(isDisabled)
    }
}

// MARK: - Toolbar Button

/// A toolbar button using standard Button for reliable tap handling.
private struct ToolbarButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(iconColor)

                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .opacity(isDisabled ? 0.5 : 1.0)
            }
            .frame(width: 40, height: 36)
        }
        .buttonStyle(ToolbarButtonStyle())
        .disabled(isDisabled)
    }

    private var iconColor: Color {
        if isActive {
            return Color.loupeActiveIcon
        } else if isDisabled {
            return .gray
        } else {
            return .primary
        }
    }
}

// MARK: - Toolbar Button Style

/// Custom button style that provides press feedback with scale animation.
private struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}
