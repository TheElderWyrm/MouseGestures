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

        log.log("Menu bar icon \(hidden ? "hidden" : "shown")")
    }

    func toggleVisibility() {
        setHidden(!isHidden())
    }
}
