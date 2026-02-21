import Foundation

// Export data structures for profiles
struct ProfileExportData: Codable {
    let profile: ConfigurationProfile
    let exportDate: Date
    let appVersion: String
    
    init(profile: ConfigurationProfile) {
        self.profile = profile
        self.exportDate = Date()
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
}


struct ProfileBundleExportData: Codable {
    let profiles: [ConfigurationProfile]
    let exportDate: Date
    let appVersion: String
    
    init(profiles: [ConfigurationProfile]) {
        self.profiles = profiles
        self.exportDate = Date()
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
}


// Structure to store configuration profile
struct ConfigurationProfile: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var gestures: [Gesture]
    var createdDate: Date
    var modifiedDate: Date
    var isDefault: Bool
    var keyboardShortcut: KeyboardTrigger? // Direct keyboard shortcut for switching to this profile
    // Backing store: nil means "not yet set" (migrates to true for existing data)
    private var _keyboardShortcutEnabled: Bool?
    /// Whether the quick-switch shortcut is currently active. Defaults to true for backwards compatibility.
    var keyboardShortcutEnabled: Bool {
        get { _keyboardShortcutEnabled ?? true }
        set { _keyboardShortcutEnabled = newValue }
    }
    var userInfo: [String: AnyCodable] = [:] // For extensibility
    
    // Legacy fields: decoded for migration but no longer used (zone/haptic are global settings)
    private var hapticFeedbackEnabled: Bool?
    private var edgeThreshold: CGFloat?
    private var cornerSize: CGFloat?
    private var cornerBuffer: CGFloat?
    
    /// Access legacy values for one-time migration to global settings
    var legacyHapticFeedbackEnabled: Bool? { hapticFeedbackEnabled }
    var legacyEdgeThreshold: CGFloat? { edgeThreshold }
    var legacyCornerSize: CGFloat? { cornerSize }
    var legacyCornerBuffer: CGFloat? { cornerBuffer }
    
    init(name: String, gestures: [Gesture] = [],
         isDefault: Bool = false, keyboardShortcut: KeyboardTrigger? = nil,
         keyboardShortcutEnabled: Bool = true) {
        self.id = UUID()
        self.name = name
        self.gestures = gestures
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.isDefault = isDefault
        self.keyboardShortcut = keyboardShortcut
        self._keyboardShortcutEnabled = keyboardShortcutEnabled
        self.userInfo = [:]
    }
    
    mutating func updateModifiedDate() {
        self.modifiedDate = Date()
    }
}


// Structure to store app-profile mappings
struct AppProfileMapping: Codable, Equatable {
    var id: UUID
    var appBundleIdentifier: String  // Bundle ID of the app (e.g., com.apple.Safari)
    var appName: String              // Display name for the UI
    var profileId: UUID              // Profile to use for this app
    var createdDate: Date
    var modifiedDate: Date
    
    init(appBundleIdentifier: String, appName: String, profileId: UUID) {
        self.id = UUID()
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
        self.profileId = profileId
        self.createdDate = Date()
        self.modifiedDate = Date()
    }
    
    mutating func updateModifiedDate() {
        self.modifiedDate = Date()
    }
}


// Structure to store disabled app information
struct DisabledApp: Codable, Equatable {
    var id: UUID
    var appBundleIdentifier: String  // Bundle ID of the app
    var appName: String              // Display name for the UI
    var createdDate: Date
    
    init(appBundleIdentifier: String, appName: String) {
        self.id = UUID()
        self.appBundleIdentifier = appBundleIdentifier
        self.appName = appName
        self.createdDate = Date()
    }
}
