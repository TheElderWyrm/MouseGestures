import Cocoa
import UserNotifications

/// Manages profile switching and related operations
public class ProfileManager {

    // MARK: - Singleton

    static let shared = ProfileManager()

    // MARK: - Properties

    private let configuration = Configuration.shared

    // MARK: - Initialization

    private init() {
        // Private initialization to ensure singleton
    }

    // MARK: - Public Methods

    /// Returns all profiles sorted by name
    var sortedProfiles: [ConfigurationProfile] {
        return configuration.profilesSnapshot.sorted { $0.name < $1.name }
    }

    /// Returns the currently active profile ID
    var activeProfileId: UUID? {
        return configuration.activeProfileIdSnapshot
    }

    /// Returns the currently active profile
    var activeProfile: ConfigurationProfile? {
        // Configuration's `activeProfile` getter already reads under configQueue.
        return configuration.activeProfile
    }

    /// Switches to a specific profile by ID
    /// - Parameter profileId: The UUID of the profile to switch to
    /// - Returns: True if the switch was successful, false otherwise
    @discardableResult
    func switchToProfile(withId profileId: UUID) -> Bool {
        // Enforce Free mode profile limit
        if !LicenseService.shared.isPro, let freeId = Configuration.shared.freeModeProfileId {
            if profileId != freeId {
                log.log("Access Denied: Cannot switch to other profiles in Free mode.")
                return false
            }
        }

        guard let profile = configuration.profileSnapshot(withId: profileId) else {
            log.log("Failed to switch to profile with ID: \(profileId) - profile not found")
            return false
        }

        // Apply the profile and set it as the new default
        configuration.applyProfile(profile, setAsDefault: true)
        configuration.save()

        // Show notification
        showProfileNotification(profileName: profile.name)

        // Post notification for UI updates
        NotificationCenter.default.post(name: .profileDidChange, object: nil, userInfo: ["profile": profile])

        log.log("Switched to profile: \(profile.name)")
        return true
    }

    /// Switches to the next profile in the list
    func switchToNextProfile() {
        // Read profiles + active id together in one synchronized snapshot so the
        // index we compute stays consistent with the active id.
        let state = configuration.profilesState
        guard !state.profiles.isEmpty else {
            log.log("Cannot switch to next profile - no profiles available")
            return
        }

        let currentIndex = state.profiles.firstIndex(where: { $0.id == state.activeId }) ?? 0
        let nextIndex = (currentIndex + 1) % state.profiles.count
        let nextProfile = state.profiles[nextIndex]

        configuration.applyProfile(nextProfile, setAsDefault: true)
        configuration.save()

        showProfileNotification(profileName: nextProfile.name)

        // Post notification for UI updates
        NotificationCenter.default.post(name: .profileDidChange, object: nil, userInfo: ["profile": nextProfile])

        log.log("Switched to next profile: \(nextProfile.name)")
    }

    /// Switches to the previous profile in the list
    func switchToPreviousProfile() {
        // Read profiles + active id together in one synchronized snapshot so the
        // index we compute stays consistent with the active id.
        let state = configuration.profilesState
        guard !state.profiles.isEmpty else {
            log.log("Cannot switch to previous profile - no profiles available")
            return
        }

        let currentIndex = state.profiles.firstIndex(where: { $0.id == state.activeId }) ?? 0
        let previousIndex = currentIndex > 0 ? currentIndex - 1 : state.profiles.count - 1
        let previousProfile = state.profiles[previousIndex]

        configuration.applyProfile(previousProfile, setAsDefault: true)
        configuration.save()

        showProfileNotification(profileName: previousProfile.name)

        // Post notification for UI updates
        NotificationCenter.default.post(name: .profileDidChange, object: nil, userInfo: ["profile": previousProfile])

        log.log("Switched to previous profile: \(previousProfile.name)")
    }

    /// Creates a new profile with the given name and optional settings
    /// - Parameters:
    ///   - name: The name for the new profile
    ///   - basedOn: Optional profile to copy settings from
    /// - Returns: The newly created profile, or nil if creation failed
    @discardableResult
    func createProfile(named name: String, basedOn sourceProfile: ConfigurationProfile? = nil) -> ConfigurationProfile? {
        let newProfile: ConfigurationProfile

        if let source = sourceProfile {
            // Create a copy of the source profile with a new ID and name
            newProfile = ConfigurationProfile(
                name: name,
                gestures: source.gestures,
                isDefault: false,
                keyboardShortcut: source.keyboardShortcut
            )
        } else {
            // Create a new empty profile
            newProfile = ConfigurationProfile(
                name: name,
                gestures: [],
                isDefault: false
            )
        }

        // Add to configuration (under the configQueue barrier).
        configuration.mutateProfiles { $0.append(newProfile) }
        configuration.save()

        // Post notification for UI updates
        NotificationCenter.default.post(name: .profilesDidChange, object: nil)

        log.log("Created new profile: \(name)")
        return newProfile
    }

    /// Deletes a profile by ID
    /// - Parameter profileId: The UUID of the profile to delete
    /// - Returns: True if the profile was deleted, false otherwise
    @discardableResult
    func deleteProfile(withId profileId: UUID) -> Bool {
        // Don't delete the active profile
        if profileId == configuration.activeProfileIdSnapshot {
            log.log("Cannot delete active profile")
            return false
        }

        // Don't delete if it's the only profile
        if configuration.profilesSnapshot.count <= 1 {
            log.log("Cannot delete the last remaining profile")
            return false
        }

        // Find and remove the profile by id inside the barrier, so the removal
        // is serialized with the save encoder and never uses a stale index.
        var deletedName: String?
        configuration.mutateProfiles { profiles in
            guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
            deletedName = profiles[index].name
            profiles.remove(at: index)
        }

        guard let name = deletedName else {
            log.log("Profile not found for deletion: \(profileId)")
            return false
        }

        configuration.save()

        // Post notification for UI updates
        NotificationCenter.default.post(name: .profilesDidChange, object: nil)

        log.log("Deleted profile: \(name)")
        return true
    }

    /// Renames a profile
    /// - Parameters:
    ///   - profileId: The UUID of the profile to rename
    ///   - newName: The new name for the profile
    /// - Returns: True if the profile was renamed, false otherwise
    @discardableResult
    func renameProfile(withId profileId: UUID, to newName: String) -> Bool {
        // Look up + rename by id inside the barrier (no stale index, serialized
        // with the save encoder).
        var oldName: String?
        configuration.mutateProfiles { profiles in
            guard let index = profiles.firstIndex(where: { $0.id == profileId }) else { return }
            oldName = profiles[index].name
            profiles[index].name = newName
        }

        guard let old = oldName else {
            log.log("Profile not found for renaming: \(profileId)")
            return false
        }

        configuration.save()

        // Post notification for UI updates
        NotificationCenter.default.post(name: .profilesDidChange, object: nil)

        log.log("Renamed profile from '\(old)' to '\(newName)'")
        return true
    }

    /// Duplicates an existing profile
    /// - Parameter profileId: The UUID of the profile to duplicate
    /// - Returns: The newly created duplicate profile, or nil if duplication failed
    @discardableResult
    func duplicateProfile(withId profileId: UUID) -> ConfigurationProfile? {
        let snapshot = configuration.profilesSnapshot
        guard let sourceProfile = snapshot.first(where: { $0.id == profileId }) else {
            log.log("Profile not found for duplication: \(profileId)")
            return nil
        }

        // Generate a unique name for the duplicate against the same snapshot.
        let existingNames = Set(snapshot.map { $0.name })
        var duplicateName = "\(sourceProfile.name) Copy"
        var counter = 2
        while existingNames.contains(duplicateName) {
            duplicateName = "\(sourceProfile.name) Copy \(counter)"
            counter += 1
        }

        return createProfile(named: duplicateName, basedOn: sourceProfile)
    }

    /// Exports a profile to a file
    /// - Parameters:
    ///   - profileId: The UUID of the profile to export
    ///   - url: The URL where to save the profile
    /// - Returns: True if the export was successful, false otherwise
    func exportProfile(withId profileId: UUID, to url: URL) -> Bool {
        guard let profile = configuration.profileSnapshot(withId: profileId) else {
            log.log("Profile not found for export: \(profileId)")
            return false
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(profile)
            // Atomic write (temp file + rename) to match ProfileImportExportService,
            // so a crash/interrupt mid-write can't leave a truncated export file.
            try data.write(to: url, options: .atomic)

            log.log("Exported profile '\(profile.name)' to: \(url.path)")
            return true
        } catch {
            log.log("Failed to export profile: \(error)")
            return false
        }
    }

    /// Imports a profile from a file
    /// - Parameter url: The URL of the profile file to import
    /// - Returns: The imported profile, or nil if import failed
    @discardableResult
    func importProfile(from url: URL) -> ConfigurationProfile? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            var profile = try decoder.decode(ConfigurationProfile.self, from: data)

            // Generate a new ID to avoid conflicts
            profile.id = UUID()

            // Check for name conflicts and adjust if necessary
            let existingNames = Set(configuration.profilesSnapshot.map { $0.name })
            var importName = profile.name
            var counter = 2
            while existingNames.contains(importName) {
                importName = "\(profile.name) (\(counter))"
                counter += 1
            }
            profile.name = importName

            // Add to configuration (under the configQueue barrier).
            configuration.mutateProfiles { $0.append(profile) }
            configuration.save()

            // Post notification for UI updates
            NotificationCenter.default.post(name: .profilesDidChange, object: nil)

            log.log("Imported profile: \(profile.name)")
            return profile
        } catch {
            log.log("Failed to import profile from \(url.path): \(error)")
            return nil
        }
    }

    // MARK: - Private Methods

    private func showProfileNotification(profileName: String) {
        // Use UserNotifications framework for macOS 11+
        let content = UNMutableNotificationContent()
        content.title = "Profile Switched"
        content.body = "Active profile: \(profileName)"
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                log.log("Failed to show notification: \(error)")
            }
        }

        // Remove notification after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the active profile changes
    static let profileDidChange = Notification.Name("ProfileDidChange")

    /// Posted when the list of profiles changes (add, remove, rename)
    static let profilesDidChange = Notification.Name("ProfilesDidChange")
}
