import AppKit
import SwiftUI

// MARK: - State

enum OnboardingPhase {
    case requestingPermission
    case permissionGranted
    /// Optional: connect a coding agent so it takes part in the practice (see `AgentConnectView`)
    case connectingAgent
    /// The hands-on practice: a pretend app inside this window (see `PracticeView`)
    case practicing
}

@Observable @MainActor
final class OnboardingState {
    var phase: OnboardingPhase = .requestingPermission
    /// False when the practice was reopened from the menu bar after setup
    var isFirstRun = true
    /// Where Agent Link is turned on. Nil only in previews and tests, which skip the connect step.
    var settings: LoupeSettings?
    let practice = PracticeSession()
}

// MARK: - View

struct OnboardingView: View {
    let state: OnboardingState
    let onGrantAccess: () -> Void
    let onOpenSettings: () -> Void
    /// "Try It": go to the practice, by way of connecting an agent if none is connected
    let onStartPractice: () -> Void
    /// Leave the connect step for the practice itself
    let onBeginPractice: () -> Void
    let onSkip: () -> Void
    let onPracticeFinished: () -> Void

    var body: some View {
        Group {
            switch state.phase {
            case .requestingPermission:
                requestingPermissionContent
            case .permissionGranted:
                permissionGrantedContent
            case .connectingAgent:
                if let settings = state.settings {
                    AgentConnectView(
                        settings: settings,
                        skipLabel: state.isFirstRun ? "Skip, I want to start using Loupe" : "Close",
                        onPractice: onBeginPractice,
                        onSkip: onSkip
                    )
                }
            case .practicing:
                PracticeView(
                    session: state.practice,
                    finishLabel: state.isFirstRun ? "Get Started" : "Done",
                    onSkip: onSkip,
                    onFinish: onPracticeFinished
                )
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
            Text(SetupCopy.permissionTitle)
                .font(.title2)
                .fontWeight(.semibold)

            // Explanation
            VStack(spacing: 8) {
                Text(SetupCopy.permissionReason)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text(SetupCopy.permissionNote())
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 40)

            // Instructions
            VStack(alignment: .leading, spacing: 8) {
                instructionRow(number: "1", text: "Click **Grant Access** below")
                instructionRow(number: "2", text: LocalizedStringKey(SetupCopy.turnOnStep()))
                instructionRow(number: "3", text: LocalizedStringKey(SetupCopy.returnStep))
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
                .tint(Color.loupeAccentStrong)
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

            Text("Take a minute to try Loupe on a practice app. Nothing you do there is saved.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 60)
                .transition(.opacity)

            Spacer()

            // Actions
            VStack(spacing: 10) {
                Button {
                    onStartPractice()
                } label: {
                    Text("Try It")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.loupeAccentStrong)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button {
                    onSkip()
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
                .background(Circle().fill(Color.loupeBadge))

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Words on the permission screen

/// What setup says when it asks for the one permission Loupe needs.
///
/// macOS 27 renamed that permission from "Accessibility" to "Device Control and Data
/// Access" and attached a broad warning to it. The screen uses the name the person will
/// actually see in System Settings, says in plain words what Loupe does with it, and
/// only promises what is true of the code: Loupe reads other apps and never acts in them.
enum SetupCopy {
    /// The permission's name in System Settings on this version of macOS
    static func settingName(macOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> String {
        macOSMajorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
    }

    static let permissionTitle = "Let Loupe see the app you point at"

    static let permissionReason = "Loupe reads the buttons, labels and layout of the app you choose, so each note says exactly what you pointed at."

    /// Names the permission as macOS shows it, and answers the warning macOS attaches to it
    static func permissionNote(macOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> String {
        let name = settingName(macOSMajorVersion: macOSMajorVersion)
        if macOSMajorVersion >= 27 {
            return "macOS calls this \(name) and warns about everything it could allow. Loupe only reads. It never clicks or types in your apps."
        }
        return "macOS calls this \(name). Loupe only reads. It never clicks or types in your apps."
    }

    /// Step 2, as Markdown so the app's name stands out
    static func turnOnStep(macOSMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> String {
        "Turn on **Loupe** under \(settingName(macOSMajorVersion: macOSMajorVersion))"
    }

    /// Step 3. Setup stays open after access is granted, so the person comes back to it.
    static let returnStep = "Come back to this window"
}
