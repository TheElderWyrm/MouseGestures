import Foundation
import AppKit

// MARK: - MenuBarVisibilityService
// Single-purpose service for managing menu bar icon visibility

class MenuBarVisibilityService {
    static let shared = MenuBarVisibilityService()

    private let configuration = Configuration.shared

    private init() {}

    func isHidden() -> Bool {
        return configuration.hideFromMenuBar
    }

    func setHidden(_ hidden: Bool) {
        configuration.hideFromMenuBar = hidden
        configuration.save()

        NotificationCenter.default.post(
            name: Notification.Name("menuBarVisibilityChanged"),
            object: nil,
            userInfo: ["hidden": hidden]
        )
        // MenuIcon only observes "GestureConfigurationChanged" for live updates
        // (see MenuIcon.configurationChanged()); post it too so toggling
        // visibility takes effect immediately instead of waiting for some
        // unrelated config change to happen to fire it.
        NotificationCenter.default.post(name: NSNotification.Name("GestureConfigurationChanged"), object: nil)

        log.log("Menu bar icon \(hidden ? "hidden" : "shown")")
    }

    func toggleVisibility() {
        setHidden(!isHidden())
    }
}
