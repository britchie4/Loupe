import AppKit
import SwiftUI

/// The optional step in setup before the practice: connect a coding agent through
/// Agent Link, so the person's own agent takes part in the practice.
///
/// Agent Link stays off unless the person turns it on here (or later in Settings).
struct AgentConnectView: View {
    @Bindable var settings: LoupeSettings
    /// "Skip, I want to start using Loupe" in first-run setup, "Close" when reopened later
    let skipLabel: String
    let onPractice: () -> Void
    let onSkip: () -> Void

    private let server = AgentLinkServer.shared
    @State private var copiedCommand: String?
    @AppStorage("loupe.agentSetupTarget") private var setupTarget: AgentSetupTarget = .claudeCode

    private var connectedAgents: [String] {
        server.status == .listening ? server.connectedAgents : []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Optional")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Color.loupeAccentText)
                .padding(.top, 12)

            Text(PracticeCopy.connectTitle)
                .font(.title2.weight(.semibold))
                .padding(.top, 10)

            Text(PracticeCopy.connectBody)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            steps
                .padding(.top, 18)

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                practiceButton

                Text(PracticeCopy.connectFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .opacity(connectedAgents.isEmpty ? 1 : 0)
                    .accessibilityHidden(!connectedAgents.isEmpty)

                Button(skipLabel, action: onSkip)
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 36)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(width: 480, height: 620)
    }

    // MARK: Steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: 16) {
            step(1, PracticeCopy.connectStepOne) {
                Text(PracticeCopy.connectStepOneDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } accessory: {
                Toggle(PracticeCopy.connectStepOne, isOn: $settings.agentLinkEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Color.loupeAccentStrong)
            }

            Divider().opacity(0.6)

            step(2, PracticeCopy.connectStepTwo) {
                HStack(spacing: 8) {
                    Picker("Agent", selection: $setupTarget) {
                        ForEach(AgentSetupTarget.allCases) { target in
                            Text(target.displayName).tag(target)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Agent to set up")

                    setupButton(for: setupTarget)
                }
                Text(setupTarget.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!settings.agentLinkEnabled)
            .opacity(settings.agentLinkEnabled ? 1 : 0.5)

            Divider().opacity(0.6)

            step(3, PracticeCopy.connectStepThree) {
                statusLine
            }
            .opacity(settings.agentLinkEnabled ? 1 : 0.5)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func step(
        _ number: Int,
        _ title: String,
        @ViewBuilder detail: () -> some View,
        @ViewBuilder accessory: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.loupeBadge))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.callout.weight(.semibold))
                detail()
            }
            Spacer(minLength: 8)
            accessory()
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch server.status {
        case .off:
            Text(PracticeCopy.connectOff)
                .font(.caption)
                .foregroundStyle(.secondary)
        case .listening:
            if connectedAgents.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    Text(PracticeCopy.connectWaiting)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label {
                    Text(PracticeCopy.connected(connectedAgents))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                }
                .font(.caption.weight(.medium))
            }
        case .failed(let message):
            Label {
                Text(message).foregroundStyle(.primary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Buttons

    @ViewBuilder
    private var practiceButton: some View {
        if let agent = connectedAgents.first {
            Button(action: onPractice) {
                Text(PracticeCopy.practiceWith(PracticeCopy.displayName(forAgent: agent)))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.loupeAccentStrong)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        } else {
            Button(action: onPractice) {
                Text(PracticeCopy.practiceWithoutAgent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func setupButton(for target: AgentSetupTarget) -> some View {
        switch target.action {
        case .copy(let text):
            Button(copiedCommand == text ? PracticeCopy.copiedLabel : target.buttonTitle) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copiedCommand = text
            }
            .help(text)
        case .open(let url):
            Button(target.buttonTitle) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
