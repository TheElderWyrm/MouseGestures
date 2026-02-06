import Foundation

// MARK: - ApplicationResetService
// Single-purpose service for resetting application to defaults

class ApplicationResetService {
    static let shared = ApplicationResetService()
    
    private let configuration = Configuration.shared
    
    private init() {}
    
    func resetToDefaults() {
        // Reset configuration
        configuration.resetToDefaults()
        
        // Reset launch at login
        LaunchAtLoginService.shared.reset()
        
        // Post notification for UI updates
        NotificationCenter.default.post(
            name: Notification.Name("appResetToDefaults"),
            object: nil
        )
        
        log.log("Application reset to defaults")
    }
    
    func resetSpecificComponent(_ component: ResetComponent) {
        switch component {
        case .profiles:
            resetProfiles()
        case .gestures:
            resetGestures()
        case .settings:
            resetSettings()
        case .savedActions:
            resetSavedActions()
        }
    }
    
    private func resetProfiles() {
        // ProfileManager doesn't have resetToDefaults, use ProfileManagementService
        ProfileManagementService.shared.resetToDefaults()
        log.log("Profiles reset to defaults")
    }
    
    private func resetGestures() {
        configuration.gestures = []
        configuration.save()
        
        NotificationCenter.default.post(
            name: Notification.Name("gesturesReset"),
            object: nil
        )
        
        log.log("Gestures cleared")
    }
    
    private func resetSettings() {
        // Reset individual settings without affecting profiles/gestures
        configuration.isEnabled = true
        configuration.hapticFeedbackEnabled = true
        configuration.showZoneHighlights = false
        configuration.showZoneLabels = false
        configuration.edgeThreshold = 30
        configuration.cornerSize = 100
        configuration.cornerBuffer = 50
        configuration.hideFromMenuBar = false
        configuration.developerModeEnabled = false
        configuration.debugModeEnabled = false
        configuration.save()
        
        log.log("Settings reset to defaults")
    }
    
    private func resetSavedActions() {
        SavedActionsManager.shared.clearAll()
        log.log("Saved actions cleared")
    }
    
    enum ResetComponent {
        case profiles
        case gestures
        case settings
        case savedActions
    }
}
