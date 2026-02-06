import Foundation

// MARK: - DebugLoggingService
// Single-purpose service for managing debug logging

class DebugLoggingService {
    static let shared = DebugLoggingService()
    
    private let configuration = Configuration.shared
    
    private init() {}
    
    func isEnabled() -> Bool {
        return configuration.debugModeEnabled
    }
    
    func setEnabled(_ enabled: Bool) {
        configuration.debugModeEnabled = enabled
        log.isDebugEnabled = enabled
        configuration.save()
        
        NotificationCenter.default.post(
            name: Notification.Name("debugLoggingChanged"),
            object: nil,
            userInfo: ["enabled": enabled]
        )
        
        log.log("Debug logging \(enabled ? "enabled" : "disabled")")
    }
}
