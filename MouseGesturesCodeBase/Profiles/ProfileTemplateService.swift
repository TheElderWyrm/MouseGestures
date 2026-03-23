import Foundation

// MARK: - Profile Template Service

class ProfileTemplateService {
    
    // MARK: - Singleton
    
    static let shared = ProfileTemplateService()
    
    // MARK: - Properties
    
    private let configuration = Configuration.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Template Creation Methods
    
    /// Creates and returns a template profile of the specified type
    func createTemplateProfile(type: DefaultProfileType) -> ConfigurationProfile {
        switch type {
        case .windowManagement:
            return DefaultProfiles.createWindowManagementProfile()
        case .mediaControl:
            return DefaultProfiles.createMediaControlProfile()
        case .systemNavigation:
            return DefaultProfiles.createSystemNavigationProfile()
        case .productivity:
            return DefaultProfiles.createProductivityProfile()
        case .minimal:
            return DefaultProfiles.createMinimalProfile()
        case .developer:
            return DefaultProfiles.createDeveloperProfile()
        case .tabNavigation:
            return DefaultProfiles.createTabNavigationProfile()
        }
    }
    
    /// Imports a template profile into the configuration
    func importTemplateProfile(type: DefaultProfileType) -> ConfigurationProfile? {
        var profile = createTemplateProfile(type: type)
        
        // Generate unique name if needed
        var importName = profile.name
        var counter = 2
        while configuration.profiles.contains(where: { $0.name == importName }) {
            importName = "\(profile.name) (\(counter))"
            counter += 1
        }
        profile.name = importName
        profile.id = UUID() // New ID
        profile.isDefault = false // Template imports are not default
        
        // Add to configuration
        configuration.profiles.append(profile)
        configuration.save()
        
        log.log("Imported template profile: \(profile.name)")
        return profile
    }
    
    /// Imports multiple template profiles
    func importMultipleTemplates(types: [DefaultProfileType]) -> [ConfigurationProfile] {
        var importedProfiles: [ConfigurationProfile] = []
        
        for type in types {
            if let profile = importTemplateProfile(type: type) {
                importedProfiles.append(profile)
            }
        }
        
        return importedProfiles
    }
    
    /// Gets all available template types
    func getAllTemplateTypes() -> [DefaultProfileType] {
        return DefaultProfileType.allCases
    }
    
    /// Gets template information without creating the profile
    func getTemplateInfo(type: DefaultProfileType) -> (name: String, description: String, gestureCount: Int) {
        let profile = createTemplateProfile(type: type)
        return (
            name: type.rawValue,
            description: type.description,
            gestureCount: profile.gestures.count
        )
    }
    
    /// Checks if a template has already been imported (by name)
    func isTemplateImported(type: DefaultProfileType) -> Bool {
        let templateName = type.rawValue
        return configuration.profiles.contains { profile in
            profile.name == templateName || profile.name.hasPrefix("\(templateName) (")
        }
    }
    
    /// Resets to default profiles (removes all custom profiles and imports defaults)
    func resetToDefaults() {
        // Clear existing profiles
        configuration.profiles.removeAll()
        
        // Import default Window Management profile as the default
        var defaultProfile = DefaultProfiles.createWindowManagementProfile()
        defaultProfile.isDefault = true
        configuration.profiles.append(defaultProfile)
        
        // Set as active
        configuration.activeProfileId = defaultProfile.id
        configuration.save()
        
        log.log("Reset to default profiles")
    }
}
