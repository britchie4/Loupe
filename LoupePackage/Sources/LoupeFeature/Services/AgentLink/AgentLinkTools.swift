import Foundation

/// The tools Loupe offers coding agents through Agent Link
@MainActor
enum AgentLinkTools {

    static func make(coordinator: AppCoordinator) -> [AgentLinkTool] {
        [getStatus(coordinator)]
    }

    /// Whether Loupe is ready, which app it is pointed at, and how many notes are open
    private static func getStatus(_ coordinator: AppCoordinator) -> AgentLinkTool {
        AgentLinkTool(
            name: "get_status",
            title: "Get Loupe status",
            description: "Check that Loupe is running, see which app the user selected for inspection, and how many notes are open for it.",
            readOnly: true
        ) { [weak coordinator] _ in
            guard let coordinator else { return .failure("Loupe is shutting down.") }
            let notes = coordinator.annotationStore.annotations
            var status: [String: JSONValue] = [
                "loupeVersion": .string(MCPHandler.appVersion),
                "accessibilityPermission": .bool(coordinator.inspector.isAccessibilityEnabled),
                "inspecting": .bool(coordinator.isInspecting),
                "openNotes": .int(notes.filter { $0.status.isOpen }.count),
                "totalNotes": .int(notes.count),
            ]
            if let app = coordinator.selectedApp {
                status["targetApp"] = [
                    "name": .string(app.name),
                    "bundleIdentifier": app.bundleIdentifier.map { .string($0) } ?? .null,
                ]
            } else {
                status["targetApp"] = .null
            }
            return AgentLinkToolResult(.object(status))
        }
    }
}
