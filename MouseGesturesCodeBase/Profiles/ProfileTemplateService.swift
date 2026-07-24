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
        return DefaultProfiles.getProfile(for: type) ?? DefaultProfiles.createWindowManagementProfile()
    }

    /// Imports a template profile into the configuration
    func importTemplateProfile(type: DefaultProfileType) -> ConfigurationProfile? {
        var profile = createTemplateProfile(type: type)

        // Generate unique name if needed (against a live synchronized snapshot).
        let existingNames = Set(configuration.profilesSnapshot.map { $0.name })
        var importName = profile.name
        var counter = 2
        while existingNames.contains(importName) {
            importName = "\(profile.name) (\(counter))"
            counter += 1
        }
        profile.name = importName
        profile.id = UUID() // New ID
        profile.isDefault = false // Template imports are not default

        // Add to configuration (under the configQueue barrier).
        configuration.mutateProfiles { $0.append(profile) }
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
        return configuration.profilesSnapshot.contains { profile in
            profile.name == templateName || profile.name.hasPrefix("\(templateName) (")
        }
    }

    /// Resets to default profiles (removes all custom profiles and imports defaults)
    func resetToDefaults() {
        // Import default Window Management profile as the default
        var defaultProfile = DefaultProfiles.createWindowManagementProfile()
        defaultProfile.isDefault = true

        // Replace all profiles and set the active id atomically under the
        // configQueue barrier (previously three separate unsynchronized writes,
        // any of which could race the save encoder).
        configuration.setProfiles([defaultProfile], activeProfileId: defaultProfile.id)
        configuration.save()

        log.log("Reset to default profiles")
    }
}
