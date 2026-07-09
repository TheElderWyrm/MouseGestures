import Foundation

// MARK: - Profile Import/Export Service

class ProfileImportExportService {

    // MARK: - Singleton

    static let shared = ProfileImportExportService()

    // MARK: - Properties

    private let configuration = Configuration.shared
    private let fileManager = FileManager.default

    // MARK: - Initialization

    private init() {}

    // MARK: - Export Methods

    /// Exports a single profile to a file
    func exportProfile(_ profile: ConfigurationProfile, to url: URL) throws {
        let exportData = ProfileExportData(profile: profile)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(exportData)
        try data.write(to: url)

        log.log("Exported profile '\(profile.name)' to: \(url.path)")
    }

    /// Exports multiple profiles to a bundle file
    func exportProfiles(_ profiles: [ConfigurationProfile], to url: URL) throws {
        let exportData = ProfileBundleExportData(profiles: profiles)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(exportData)
        try data.write(to: url)

        log.log("Exported \(profiles.count) profiles to: \(url.path)")
    }

    /// Exports all profiles
    func exportAllProfiles(to url: URL) throws {
        try exportProfiles(configuration.profiles, to: url)
    }

    // MARK: - Import Methods

    /// Imports a single profile from a file
    func importProfile(from url: URL) throws -> ConfigurationProfile {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let exportData = try decoder.decode(ProfileExportData.self, from: data)

        var profile = exportData.profile
        profile.id = UUID() // Generate new ID to avoid conflicts

        // Check for name conflicts and adjust if necessary
        profile.name = generateUniqueProfileName(baseName: profile.name)

        log.log("Imported profile '\(profile.name)' from: \(url.path)")
        return profile
    }

    /// Imports multiple profiles from a bundle file
    func importProfileBundle(from url: URL) throws -> [ConfigurationProfile] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let bundleData = try decoder.decode(ProfileBundleExportData.self, from: data)

        var importedProfiles: [ConfigurationProfile] = []

        for var profile in bundleData.profiles {
            profile.id = UUID() // Generate new ID
            profile.name = generateUniqueProfileName(baseName: profile.name)
            importedProfiles.append(profile)
        }

        log.log("Imported \(importedProfiles.count) profiles from: \(url.path)")
        return importedProfiles
    }

    // MARK: - Validation Methods

    /// Validates a profile export file
    func validateProfileFile(at url: URL) -> (isValid: Bool, error: String?) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            _ = try decoder.decode(ProfileExportData.self, from: data)
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Validates a profile bundle file
    func validateProfileBundleFile(at url: URL) -> (isValid: Bool, error: String?) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            _ = try decoder.decode(ProfileBundleExportData.self, from: data)
            return (true, nil)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Helper Methods

    private func generateUniqueProfileName(baseName: String) -> String {
        var name = baseName
        var counter = 2

        while configuration.profiles.contains(where: { $0.name == name }) {
            name = "\(baseName) (\(counter))"
            counter += 1
        }

        return name
    }
}
