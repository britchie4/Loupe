import SwiftUI

/// Settings popover for configuring output format and naming style
public struct SettingsView: View {
    @Bindable var settings: LoupeSettings

    public init(settings: LoupeSettings) {
        self.settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Output Settings")
                .font(.headline)
                .foregroundStyle(.primary)

            Divider()

            // Output Format
            VStack(alignment: .leading, spacing: 6) {
                Text("Output Format")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Format", selection: $settings.outputFormat) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Text(settings.outputFormat.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Naming Style (UI display only)
            VStack(alignment: .leading, spacing: 6) {
                Text("Display Style")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Style", selection: $settings.namingStyle) {
                    ForEach(NamingStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(settings.namingStyle.description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fontDesign(.monospaced)

                Text("Affects hover labels and popovers only.\nClipboard output is always technical.")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }

            Divider()

            AgentLinkSettingsSection(settings: settings)
        }
        .padding(16)
        .frame(width: 300)
    }
}

// MARK: - Agent Link

/// Turns Agent Link on or off, shows whether an agent is connected, and offers setup commands
private struct AgentLinkSettingsSection: View {
    @Bindable var settings: LoupeSettings
    private let server = AgentLinkServer.shared
    @State private var copiedCommand: String?
    @AppStorage("loupe.agentSetupTarget") private var setupTarget: AgentSetupTarget = .claudeCode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $settings.agentLinkEnabled) {
                Text("Agent Link")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Text("Lets your coding agent read your notes, reply, and mark them done. Agents can look at the app you picked but can never click or type.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if settings.agentLinkEnabled {
                statusLine

                Text("Set up once in your agent:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

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
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Teach your agent the notes workflow:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                copyButton("Copy skill install command", command: AgentLinkServer.skillInstallCommand)
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch server.status {
        case .listening:
            Label(
                server.connectedAgents.isEmpty
                    ? "Ready. No agent connected yet."
                    : "Connected: \(server.connectedAgents.joined(separator: ", "))",
                systemImage: "circle.fill"
            )
            .font(.caption)
            .foregroundStyle(server.connectedAgents.isEmpty ? Color.secondary : Color.green)
            .symbolRenderingMode(.monochrome)
            .imageScale(.small)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .off:
            EmptyView()
        }
    }

    @ViewBuilder
    private func setupButton(for target: AgentSetupTarget) -> some View {
        switch target.action {
        case .copy(let text):
            copyButton(target.buttonTitle, command: text)
        case .open(let url):
            Button(target.buttonTitle) {
                NSWorkspace.shared.open(url)
            }
            .controlSize(.small)
        }
    }

    private func copyButton(_ title: String, command: String) -> some View {
        Button(copiedCommand == command ? "Copied" : title) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            copiedCommand = command
        }
        .controlSize(.small)
        .help(command)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SettingsView(settings: LoupeSettings())
        .background(.regularMaterial)
}
#endif
