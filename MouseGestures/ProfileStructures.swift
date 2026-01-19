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
    var hapticFeedbackEnabled: Bool
    var edgeThreshold: CGFloat
    var cornerSize: CGFloat
    var cornerBuffer: CGFloat
    var createdDate: Date
    var modifiedDate: Date
    var isDefault: Bool
    var keyboardShortcut: KeyboardTrigger? // Direct keyboard shortcut for switching to this profile
    var userInfo: [String: AnyCodable] = [:] // For extensibility
    
    init(name: String, gestures: [Gesture] = [], hapticFeedbackEnabled: Bool = true,
         edgeThreshold: CGFloat = 30, cornerSize: CGFloat = 100, cornerBuffer: CGFloat = 50,
         isDefault: Bool = false, keyboardShortcut: KeyboardTrigger? = nil) {
        self.id = UUID()
        self.name = name
        self.gestures = gestures
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
        self.edgeThreshold = edgeThreshold
        self.cornerSize = cornerSize
        self.cornerBuffer = cornerBuffer
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.isDefault = isDefault
        self.keyboardShortcut = keyboardShortcut
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
