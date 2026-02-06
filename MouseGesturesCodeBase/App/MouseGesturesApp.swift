import SwiftUI

/// SwiftUI App structure for MouseGestures with Settings support
@main
struct MouseGesturesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The Settings scene definition. The main app window is handled by the AppDelegate
        // to avoid showing a blank window on startup for this menu bar app.
        Settings {
            TabManager()
        }
    }
}
