import AppKit
import AVKit
import SwiftUI

// MARK: - AVPlayerView wrapper

/// Wraps AppKit's `AVPlayerView` directly, bypassing the `_AVKit_SwiftUI` bridge
/// which crashes on macOS 26 due to a Swift runtime metadata resolution failure.
struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

// MARK: - State

enum OnboardingPhase {
    case requestingPermission
    case permissionGranted
    case watchingDemo
}

@Observable @MainActor
final class OnboardingState {
    var phase: OnboardingPhase = .requestingPermission
    var videoPlayer: AVPlayer?

    func prepareVideoPlayer() {
        guard let url = URL(string: "https://britchie4.github.io/Loupe/demo.mp4") else { return }
        videoPlayer = AVPlayer(url: url)
    }

    func playVideo() {
        videoPlayer?.seek(to: .zero)
        videoPlayer?.play()
    }

    func stopVideo() {
        videoPlayer?.pause()
        videoPlayer = nil
    }
}

// MARK: - View

struct OnboardingView: View {
    let state: OnboardingState
    let onGrantAccess: () -> Void
    let onOpenSettings: () -> Void
    let onWatchDemo: () -> Void
    let onSkipDemo: () -> Void
    let onDemoFinished: () -> Void

    var body: some View {
        Group {
            switch state.phase {
            case .requestingPermission:
                requestingPermissionContent
            case .permissionGranted:
                permissionGrantedContent
            case .watchingDemo:
                watchingDemoContent
            }
        }
        .frame(width: 480, height: 620)
        .background(.regularMaterial)
    }

    // MARK: - Phase 1: Requesting Permission

    private var requestingPermissionContent: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 8)

            // App icon
            appIcon
                .frame(width: 80, height: 80)

            // Title
            Text("Loupe needs Accessibility access")
                .font(.title2)
                .fontWeight(.semibold)

            // Explanation
            Text("To inspect UI elements in other apps, Loupe uses the macOS Accessibility API. You'll need to grant permission in System Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", text: "Click **Grant Access** below")
                instructionRow(number: "2", text: "Toggle **Loupe** on in System Settings")
                instructionRow(number: "3", text: "This window will close automatically")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
            )
            .padding(.horizontal, 40)

            Spacer()

            // Actions
            VStack(spacing: 10) {
                Button {
                    onGrantAccess()
                } label: {
                    Text("Grant Access")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.loupeAccent)
                .controlSize(.large)

                Button {
                    onOpenSettings()
                } label: {
                    Text("Open System Settings")
                        .font(.callout)
                }
                .buttonStyle(.link)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Phase 2: Permission Granted

    private var permissionGrantedContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.loupeAccent)
                .transition(.scale.combined(with: .opacity))

            Text("You're all set!")
                .font(.title2)
                .fontWeight(.semibold)
                .transition(.opacity)

            Spacer()

            // Actions
            VStack(spacing: 10) {
                Button {
                    onWatchDemo()
                } label: {
                    Label("Watch Demo", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.loupeAccent)
                .controlSize(.large)

                Button {
                    onSkipDemo()
                } label: {
                    Text("Skip, I want to start using Loupe")
                        .font(.callout)
                }
                .buttonStyle(.link)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 28)
        }
        .animation(.easeOut(duration: 0.4), value: state.phase == .permissionGranted)
    }

    // MARK: - Phase 3: Watching Demo

    private var watchingDemoContent: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 8)

            Text("How Loupe Works")
                .font(.title2)
                .fontWeight(.semibold)

            if let player = state.videoPlayer {
                NativeVideoPlayer(player: player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 24)
            }

            // Step-by-step explainer
            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", text: "**Hover** — Point at any element in any Mac app")
                instructionRow(number: "2", text: "**Annotate** — Click to describe the change you want")
                instructionRow(number: "3", text: "**Copy** — One click copies structured context")
                instructionRow(number: "4", text: "**Paste** — Feed it to Claude Code, Cursor, Codex, or any of your favorite coding agents")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
            )
            .padding(.horizontal, 40)

            Spacer()

            Button {
                onDemoFinished()
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.loupeAccent)
            .controlSize(.large)
            .padding(.horizontal, 60)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Helpers

    private var appIcon: some View {
        Group {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.loupeAccent)
            }
        }
    }

    private func instructionRow(number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.loupeAccent))

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }
}
