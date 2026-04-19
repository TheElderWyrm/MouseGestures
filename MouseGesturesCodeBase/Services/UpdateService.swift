import Foundation
import SwiftUI

/// Service for checking app updates and managing versions
public class UpdateService: ObservableObject {
    
    // MARK: - Singleton
    public static let shared = UpdateService()
    
    // MARK: - Constants
    private let updateURL = URL(string: "https://raw.githubusercontent.com/eldritchbookwyrm/MouseGestures/main/version.json")
    private let lastCheckKey = "MGLastUpdateCheck"
    private let autoUpdateKey = "MGAutoUpdateEnabled"
    
    // MARK: - Properties
    @Published public var currentVersion: String = ""
    @Published public var latestVersion: String = ""
    @Published public var isUpdateAvailable: Bool = false
    @Published public var updateReleaseNotes: String = ""
    @Published public var isChecking: Bool = false
    @Published public var lastCheckDate: Date?
    
    private init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        lastCheckDate = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    }
    
    // MARK: - Public API
    
    /// Check for updates manually
    public func checkForUpdates(quietly: Bool = false) {
        guard !isChecking else { return }
        
        isChecking = true
        
        // In a real app, we'd fetch from a remote URL. 
        // For this prototype, we'll simulate a check.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.isChecking = false
            self.lastCheckDate = Date()
            UserDefaults.standard.set(self.lastCheckDate, forKey: self.lastCheckKey)
            
            // Simulation: 1.0.0 is current, 1.1.0 is latest
            self.latestVersion = "1.1.0"
            self.isUpdateAvailable = self.compareVersions(self.currentVersion, self.latestVersion) == .orderedAscending
            self.updateReleaseNotes = """
                - Added Onboarding UI for new users
                - Added Update Checker and automatic notifications
                - Improved license management for Pro features
                - Fixed Finder 'Quit Application' behavior
                - Optimized Modifier Key and Keyboard Shortcut detection
                """
            
            if self.isUpdateAvailable && !quietly {
                self.showUpdateNotification()
            }
        }
    }
    
    /// Returns true if auto-update is enabled
    public var isAutoUpdateEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoUpdateKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoUpdateKey) }
    }
    
    // MARK: - Helper Methods
    
    private func compareVersions(_ v1: String, _ v2: String) -> ComparisonResult {
        return v1.compare(v2, options: .numeric)
    }
    
    private func showUpdateNotification() {
        NotificationCenter.default.post(
            name: NSNotification.Name("MGUpdateAvailable"),
            object: self
        )
        
        // Also show a system notification if configured
        if Configuration.shared.notificationOnActivation {
            PluginManager.shared.showPluginNotification(
                title: "Update Available",
                message: "MouseGestures v\(latestVersion) is now available.",
                style: .info,
                pluginId: "com.mousegestures.system"
            )
        }
    }
}
