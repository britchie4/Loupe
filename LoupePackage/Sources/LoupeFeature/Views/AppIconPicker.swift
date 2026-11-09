import SwiftUI
import AppKit

/// A compact app icon picker that shows the selected app's icon
/// and expands to a picker when clicked
public struct AppIconPicker: View {
    @Binding var selectedApp: TargetApp?
    let availableApps: [TargetApp]
    let onRefresh: () -> Void

    @State private var isExpanded = false
    @State private var query = ""
    @State private var highlightedID: pid_t?
    @FocusState private var isSearchFocused: Bool

    public init(
        selectedApp: Binding<TargetApp?>,
        availableApps: [TargetApp],
        onRefresh: @escaping () -> Void
    ) {
        self._selectedApp = selectedApp
        self.availableApps = availableApps
        self.onRefresh = onRefresh
    }

    /// Apps matching the search, in list order
    private var matches: [TargetApp] {
        AppListOrdering.filtered(availableApps, query: query)
    }

    public var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                appIconView

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 36)
        }
        .buttonStyle(AppIconPickerButtonStyle())
        .accessibilityLabel(selectedApp.map { "App to inspect: \($0.name)" } ?? "Choose an app to inspect")
        .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
            appPickerPopover
        }
        .onAppear {
            // With no app picked, open the list so the next step is obvious
            guard selectedApp == nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if selectedApp == nil { isExpanded = true }
            }
        }
    }

    // MARK: - App Icon View

    private var appIconView: some View {
        Group {
            if let app = selectedApp, let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .help("Inspecting \(app.name). Click to change.")
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 34, height: 34)

                    Image(systemName: "app.dashed")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                .help("Choose an app to inspect")
            }
        }
    }

    // MARK: - Picker Popover

    private var appPickerPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search, with refresh beside it
            HStack(spacing: 6) {
                searchField

                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Refresh the list")
                .accessibilityLabel("Refresh the list")
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 10)

            Divider()

            // App list
            if matches.isEmpty {
                Text(availableApps.isEmpty ? "No open apps to inspect" : "No open app matches \u{201C}\(query)\u{201D}")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(matches) { app in
                                AppPickerRow(
                                    app: app,
                                    isSelected: selectedApp?.id == app.id,
                                    isHighlighted: highlightedID == app.id,
                                    onHover: { highlightedID = app.id }
                                ) {
                                    choose(app)
                                }
                                .id(app.id)
                            }
                        }
                        .padding(4)
                    }
                    .frame(maxHeight: 300)
                    .onChange(of: highlightedID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(id)
                        }
                    }
                }
            }
        }
        .frame(width: 280)
        .onAppear {
            // Catch anything that changed while the list was closed, and start ready to type
            onRefresh()
            query = ""
            highlightedID = availableApps.first?.id
            isSearchFocused = true
        }
        .onChange(of: query) {
            highlightedID = matches.first?.id
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Choose an app to inspect", text: $query)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search open apps")
                .focused($isSearchFocused)
                .onSubmit {
                    if let app = matches.first(where: { $0.id == highlightedID }) ?? matches.first {
                        choose(app)
                    }
                }
                .onKeyPress(.downArrow) {
                    moveHighlight(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveHighlight(by: -1)
                    return .handled
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func moveHighlight(by step: Int) {
        let list = matches
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == highlightedID } ?? (step > 0 ? -1 : list.count)
        let next = min(max(current + step, 0), list.count - 1)
        highlightedID = list[next].id
    }

    private func choose(_ app: TargetApp) {
        selectedApp = app
        isExpanded = false
    }
}

// MARK: - App Icon Picker Button Style

/// Custom button style for the app icon picker with press feedback.
private struct AppIconPickerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - App Picker Row

private struct AppPickerRow: View {
    let app: TargetApp
    let isSelected: Bool
    let isHighlighted: Bool
    let onHover: () -> Void
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // App icon
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "app.fill")
                        .frame(width: 24, height: 24)
                }

                // App name
                Text(app.name)
                    .font(.body)
                    .lineLimit(1)

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.loupeAccent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Color.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering in
            if hovering { onHover() }
        }
    }
}

// MARK: - NSImage Grayscale Extension

public extension NSImage {
    /// Returns a grayscale version of the image
    func grayscale() -> NSImage {
        guard let tiffData = self.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return self
        }

        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(0.0, forKey: kCIInputSaturationKey)

        guard let outputImage = filter?.outputImage else {
            return self
        }

        let rep = NSCIImageRep(ciImage: outputImage)
        let grayscaleImage = NSImage(size: rep.size)
        grayscaleImage.addRepresentation(rep)

        return grayscaleImage
    }
}
