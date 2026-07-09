import Foundation
import ServiceManagement

/// LaunchAtLoginService handles launch at login functionality
class LaunchAtLoginService {

    // MARK: - Singleton

    static let shared = LaunchAtLoginService()

    // MARK: - Properties

    // Launch at login support
    private var launchHelper: SMAppService {
        SMAppService.mainApp
    }

    // MARK: - Initialization

    private init() {
        // Private initialization to ensure singleton
    }

    // MARK: - Public Methods

    /// Gets whether the app launches at login
    var isEnabled: Bool {
        return launchHelper.status == .enabled
    }

    /// Sets whether the app launches at login
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if launchHelper.status == .enabled {
                    log.log("LaunchAtLoginService: Launch at login already enabled")
                } else {
                    try launchHelper.register()
                    log.log("LaunchAtLoginService: Launch at login enabled")
                }
            } else {
                if launchHelper.status != .enabled {
                    log.log("LaunchAtLoginService: Launch at login already disabled")
                } else {
                    try launchHelper.unregister()
                    log.log("LaunchAtLoginService: Launch at login disabled")
                }
            }
        } catch {
            log.log("LaunchAtLoginService: Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    }

    /// Resets launch at login to disabled
    func reset() {
        try? launchHelper.unregister()
    }
}
