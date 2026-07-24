import SwiftUI

@main
struct VimitallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Minimal scene to satisfy the App protocol.
        // The app is LSUIElement - no dock icon, no app menu.
        // Preferences are opened via the menu bar controller's own NSWindow.
        Settings {
            EmptyView()
        }
    }
}
