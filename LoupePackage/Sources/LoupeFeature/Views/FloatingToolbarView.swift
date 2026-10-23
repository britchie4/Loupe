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
            self.glassEffect(.regular.tint(.clear), in: RoundedRectangle(cornerRadius: cornerRadius))
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

    /// Namespace for glass effect morphing (macOS 26+)
    @Namespace private var glassNamespace

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
        GlassEffectContainer(spacing: 40) {
            if isExpanded {
                expandedMorphingContent
            } else {
                collapsedMorphingContent
            }
        }
        .animation(.bouncy, value: isExpanded)
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
        ZStack(alignment: .topTrailing) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .saturation(0)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(width: 52, height: 44)
                .glassEffect(.regular.tint(.clear).interactive(), in: Circle())
                .glassEffectID("toolbar", in: glassNamespace)
                .padding(.top, 6)
                .padding(.trailing, 6)

            if annotationCount > 0 {
                Text("\(annotationCount)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.loupeBadge))
            }
        }
        .contentShape(Circle())
        .onTapGesture {
            withAnimation(.bouncy) {
                isExpanded = true
            }
        }
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
                withAnimation(.bouncy) {
                    isExpanded = false
                }
            }
        }
        .padding(8)
        // Note: Using non-interactive glass so button taps pass through
        .glassEffect(.regular.tint(.clear), in: RoundedRectangle(cornerRadius: 14))
        .glassEffectID("toolbar", in: glassNamespace) // Same ID as collapsed - enables morphing!
    }

    // MARK: - Legacy Toolbar (Pre-macOS 26)

    /// Single container that morphs between collapsed circle and expanded pill
    /// Uses onTapGesture instead of Button to prevent accidental clicks during window dragging
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
        .onTapGesture {
            // Only expand when collapsed - when expanded, let inner buttons handle taps
            if !isExpanded {
                withAnimation(.smooth(duration: 0.4)) {
                    isExpanded = true
                }
            }
        }
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
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 28, height: 28)
            .saturation(0)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .frame(width: 52, height: 44)
            .padding(.top, 6)
            .padding(.trailing, 6)
            .overlay(alignment: .topTrailing) {
                if annotationCount > 0 {
                    Text("\(annotationCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.loupeBadge))
                }
            }
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
                    .foregroundColor(showSuccess ? Color.loupeSuccess : .secondary)
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
