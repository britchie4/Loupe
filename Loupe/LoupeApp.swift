import SwiftUI
import LoupeFeature

struct LoupeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty Settings scene to satisfy SwiftUI App protocol
        // The actual UI is managed by AppDelegate and FloatingToolbarWindowController
        Settings {
            EmptyView()
        }
    }
}
