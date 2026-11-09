import SwiftUI

/// Settings popover for configuring output format and naming style
public struct SettingsView: View {
    @Bindable var settings: LoupeSettings

    public init(settings: LoupeSettings) {
        self.settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Output Format
            VStack(alignment: .leading, spacing: 6) {
                Text("Output Format")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Picker("Format", selection: $settings.outputFormat) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                Text(settings.outputFormat.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Naming Style (UI display only)
            VStack(alignment: .leading, spacing: 6) {
                Text("Display Style")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                AccentSegmentedControl(
                    label: "Display Style",
                    options: NamingStyle.allCases,
                    selection: $settings.namingStyle,
                    title: \.displayName
                )

                Text(settings.namingStyle.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)

                Text("Affects hover labels and popovers only.\nClipboard output is always technical.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .toggleStyle(VisibleSwitchStyle())

            Text("Lets your coding agent read your notes, reply, and mark them done. Agents can look at the app you picked but can never click or type.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if settings.agentLinkEnabled {
                statusLine

                Text("Set up once in your agent:")
                    .font(.caption)
                    .foregroundStyle(.primary)
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
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Teach your agent the notes workflow:")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .padding(.top, 4)

                copyButton("Copy skill install command", command: AgentLinkServer.skillInstallCommand)
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch server.status {
        case .listening:
            Label {
                Text(server.connectedAgents.isEmpty
                    ? "Ready. No agent connected yet."
                    : "Connected: \(server.connectedAgents.joined(separator: ", "))")
                    .foregroundStyle(server.connectedAgents.isEmpty ? .secondary : .primary)
            } icon: {
                Image(systemName: "circle.fill")
                    .foregroundStyle(server.connectedAgents.isEmpty ? Color.secondary : Color.green)
                    .imageScale(.small)
            }
            .font(.caption)
        case .failed(let message):
            Label {
                Text(message).foregroundStyle(.primary)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
                .font(.caption)
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

// MARK: - Segmented control

/// A segmented choice whose selected segment stays blue. The system control
/// only turns blue once the popover has focus, so it looked grey on first open.
private struct AccentSegmentedControl<Value: Hashable & Identifiable>: View {
    let label: String
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 92)
                        .frame(height: 24)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
        )
        .animation(.snappy(duration: 0.15), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// MARK: - Switch

/// A small switch that stays colored when on. The settings popover never becomes
/// the key window, and the system switch turns grey in that state, so on and off
/// looked almost the same.
private struct VisibleSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            Spacer(minLength: 0)
            Capsule()
                .fill(configuration.isOn ? Color.accentColor : Color.secondary.opacity(0.35))
                .frame(width: 32, height: 18)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                        .padding(2)
                }
                .animation(.snappy(duration: 0.15), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SettingsView(settings: LoupeSettings())
        .background(.regularMaterial)
}
#endif
