import Foundation

// MARK: - DeveloperModeService
// Single-purpose service for managing developer mode

class DeveloperModeToggleService {
    static let shared = DeveloperModeToggleService()

    private let configuration = Configuration.shared

    private init() {}

    func isEnabled() -> Bool {
        return configuration.developerModeEnabled
    }

    func setEnabled(_ enabled: Bool) {
        configuration.developerModeEnabled = enabled
        configuration.save()

        NotificationCenter.default.post(
            name: Notification.Name("developerModeChanged"),
            object: nil,
            userInfo: ["enabled": enabled]
        )

        log.log("Developer mode \(enabled ? "enabled" : "disabled")")
    }
}
