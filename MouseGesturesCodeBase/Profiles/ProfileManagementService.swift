import Foundation
import AppKit

/// Service responsible for profile management operations
class ProfileManagementService: ObservableObject {

    // MARK: - Singleton

    static let shared = ProfileManagementService()

    // MARK: - Published Properties

    @Published var profiles: [ConfigurationProfile] = []
    @Published var activeProfileId: UUID?
    @Published var isLoading = false
    @Published var lastError: Error?

    // MARK: - Properties

    private let configuration = Configuration.shared
    private let profileManager = ProfileManager.shared
    private let importExportService = ProfileImportExportService.shared

    // MARK: - Initialization

    private init() {
        loadProfiles()
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProfilesChanged),
            name: .profilesDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProfileChanged),
            name: .profileDidChange,
            object: nil
        )
    }

    // MARK: - Profile Loading

    func loadProfiles() {
        // Read the live state through the synchronized snapshot, then publish on
        // the main thread (these @Published properties feed SwiftUI bindings).
        let state = configuration.profilesState
        let update = {
            self.profiles = state.profiles
            self.activeProfileId = state.activeId
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async { update() } }
    }

    @objc private func handleProfilesChanged() {
        loadProfiles()
    }

    @objc private func handleProfileChanged() {
        loadProfiles()
    }

    // MARK: - Profile CRUD Operations

    /// Creates a new profile
    /// - Parameters:
    ///   - name: Name for the new profile
    ///   - baseProfileId: Optional ID of profile to copy from
    /// - Returns: The created profile, or nil if creation failed
    func createProfile(name: String, baseProfileId: UUID? = nil) -> ConfigurationProfile? {
        // Validate name
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log.log("Cannot create profile with empty name")
            return nil
        }

        // Check for duplicate names against LIVE configuration state. `profiles`
        // is a @Published UI cache refreshed via loadProfiles() (often async on
        // main), so it can lag behind an in-flight mutation and let a duplicate
        // slip through; validate against the source of truth instead.
        if configuration.profilesSnapshot.contains(where: { $0.name == name }) {
            log.log("Profile with name '\(name)' already exists")
            return nil
        }

        let baseProfile = baseProfileId.flatMap { id in
            configuration.profileSnapshot(withId: id)
        }

        let newProfile = profileManager.createProfile(named: name, basedOn: baseProfile)
        loadProfiles()

        return newProfile
    }

    /// Updates an existing profile
    /// - Parameters:
    ///   - profileId: ID of the profile to update
    ///   - name: New name for the profile
    ///   - gestures: New gestures for the profile
    /// - Returns: True if update was successful
    @discardableResult
    func updateProfile(profileId: UUID, name: String? = nil, gestures: [Gesture]? = nil, keyboardShortcut: KeyboardTrigger?? = nil, keyboardShortcutEnabled: Bool? = nil) -> Bool {
        // Duplicate-name check against LIVE state, not the @Published cache.
        if let newName = name,
           configuration.profilesSnapshot.contains(where: { $0.id != profileId && $0.name == newName }) {
            log.log("Profile with name '\(newName)' already exists")
            return false
        }

        // Look up by id and apply the edits inside the configQueue barrier, so
        // the mutation serializes with the save encoder and never relies on an
        // index computed outside the lock (which a concurrent add/remove could
        // invalidate — wrong profile overwritten, or an out-of-bounds crash).
        let found = configuration.mutateProfiles { profileList -> Bool in
            guard let profileIndex = profileList.firstIndex(where: { $0.id == profileId }) else {
                return false
            }

            // Update name if provided
            if let newName = name {
                profileList[profileIndex].name = newName
            }

            // Update gestures if provided
            if let newGestures = gestures {
                profileList[profileIndex].gestures = newGestures
            }

            // Update keyboard shortcut if provided (double-optional: nil means no change, .some(nil) means clear)
            if let newShortcut = keyboardShortcut {
                profileList[profileIndex].keyboardShortcut = newShortcut
            }

            // Update shortcut enabled state if provided
            if let enabled = keyboardShortcutEnabled {
                profileList[profileIndex].keyboardShortcutEnabled = enabled
            }

            return true
        }

        guard found else {
            log.log("Profile not found for update: \(profileId)")
            return false
        }

        configuration.save()

        NotificationCenter.default.post(name: .profilesDidChange, object: nil)
        loadProfiles()

        return true
    }

    /// Deletes a profile
    /// - Parameter profileId: ID of the profile to delete
    /// - Returns: True if deletion was successful
    @discardableResult
    func deleteProfile(profileId: UUID) -> Bool {
        // Check against Configuration's live activeProfileId (not our cached @Published one,
        // which may be stale if a switch just happened via DispatchQueue.main.async),
        // read through the synchronized snapshot.
        if profileId == configuration.activeProfileIdSnapshot {
            log.log("Cannot delete active profile — switch to another profile first")
            return false
        }

        // Prevent deletion if it's the last profile
        if configuration.profilesSnapshot.count <= 1 {
            log.log("Cannot delete the last profile")
            return false
        }

        let success = profileManager.deleteProfile(withId: profileId)
        if success {
            loadProfiles()
        }

        return success
    }

    /// Duplicates a profile
    /// - Parameter profileId: ID of the profile to duplicate
    /// - Returns: The duplicated profile, or nil if duplication failed
    func duplicateProfile(profileId: UUID) -> ConfigurationProfile? {
        let duplicate = profileManager.duplicateProfile(withId: profileId)
        if duplicate != nil {
            loadProfiles()
        }
        return duplicate
    }

    // MARK: - Profile Activation

    /// Activates a profile
    /// - Parameter profileId: ID of the profile to activate
    /// - Returns: True if activation was successful
    @discardableResult
    func activateProfile(profileId: UUID) -> Bool {
        let success = profileManager.switchToProfile(withId: profileId)
        if success {
            loadProfiles()
        }
        return success
    }

    /// Gets the currently active profile
    /// - Returns: The active profile, or nil if none
    func getActiveProfile() -> ConfigurationProfile? {
        return profileManager.activeProfile
    }

    // MARK: - Import/Export Operations

    /// Exports a profile
    /// - Parameter profileId: ID of the profile to export
    /// - Returns: True if export was successful
    @discardableResult
    func exportProfile(profileId: UUID, to url: URL) -> Bool {
        guard let profile = profiles.first(where: { $0.id == profileId }) else {
            log.log("Profile not found for export: \(profileId)")
            return false
        }

        do {
            try importExportService.exportProfile(profile, to: url)
            return true
        } catch {
            log.log("Failed to export profile: \(error)")
            return false
        }
    }

    /// Exports multiple profiles
    /// - Parameter profileIds: Array of profile IDs to export
    /// - Returns: Number of successfully exported profiles
    @discardableResult
    func exportProfiles(profileIds: [UUID], to url: URL) -> Int {
        let profilesToExport = profiles.filter { profileIds.contains($0.id) }
        do {
            try importExportService.exportProfiles(profilesToExport, to: url)
            return profilesToExport.count
        } catch {
            log.log("Failed to export profiles: \(error)")
            return 0
        }
    }

    /// Imports a profile from file
    /// - Returns: The imported profile, or nil if import failed
    func importProfile(from url: URL) -> ConfigurationProfile? {
        do {
            let imported = try importExportService.importProfile(from: url)
            configuration.mutateProfiles { $0.append(imported) }
            configuration.save()
            loadProfiles()
            return imported
        } catch {
            log.log("Failed to import profile: \(error)")
            return nil
        }
    }

    /// Imports multiple profiles from files
    /// - Returns: Array of imported profiles
    func importMultipleProfiles(from url: URL) -> [ConfigurationProfile] {
        do {
            let imported = try importExportService.importProfileBundle(from: url)
            if !imported.isEmpty {
                configuration.mutateProfiles { $0.append(contentsOf: imported) }
                configuration.save()
                loadProfiles()
            }
            return imported
        } catch {
            log.log("Failed to import profiles: \(error)")
            return []
        }
    }

    // MARK: - Default Profiles

    /// Imports a default profile template
    /// - Parameter type: The type of default profile to import
    /// - Returns: The imported profile, or nil if import failed
    func importDefaultProfile(type: DefaultProfileType) -> ConfigurationProfile? {
        guard var profile = DefaultProfiles.getProfile(for: type) else {
            log.log("Default profile not found for type: \(type)")
            return nil
        }

        // Generate new ID
        profile.id = UUID()

        // Handle name conflicts against LIVE state (not the @Published cache).
        let existingNames = Set(configuration.profilesSnapshot.map { $0.name })
        var importName = profile.name
        var counter = 2
        while existingNames.contains(importName) {
            importName = "\(profile.name) \(counter)"
            counter += 1
        }
        profile.name = importName

        // Mark as non-default
        profile.isDefault = false

        // Add to configuration (under the configQueue barrier).
        configuration.mutateProfiles { $0.append(profile) }
        configuration.save()

        NotificationCenter.default.post(name: .profilesDidChange, object: nil)
        loadProfiles()

        log.log("Imported default profile: \(profile.name)")
        return profile
    }

    /// Resets the current active profile's gestures to factory defaults
    func resetToDefaults() {
        guard let activeId = configuration.activeProfileIdSnapshot else {
            log.log("Cannot reset: no active profile")
            return
        }

        // Replace the active profile's gestures with the factory defaults inside
        // the barrier (serialized with the save encoder, no stale index).
        let defaults = Configuration.defaultGestures
        var resetName: String?
        configuration.mutateProfiles { profileList in
            guard let index = profileList.firstIndex(where: { $0.id == activeId }) else { return }
            profileList[index].gestures = defaults
            profileList[index].updateModifiedDate()
            resetName = profileList[index].name
        }

        guard let name = resetName else {
            log.log("Cannot reset: no active profile")
            return
        }

        configuration.save()

        NotificationCenter.default.post(name: .profilesDidChange, object: nil)
        loadProfiles()

        log.log("Reset active profile '\(name)' gestures to defaults")
    }

    // MARK: - Search and Filter

    /// Searches profiles by name
    /// - Parameter query: Search query
    /// - Returns: Array of matching profiles
    func searchProfiles(query: String) -> [ConfigurationProfile] {
        guard !query.isEmpty else { return profiles }

        let lowercaseQuery = query.lowercased()
        return profiles.filter { profile in
            profile.name.lowercased().contains(lowercaseQuery)
        }
    }

    /// Gets profiles sorted by various criteria
    /// - Parameter sortBy: Sort criteria
    /// - Returns: Sorted array of profiles
    func getSortedProfiles(sortBy: ProfileSortCriteria) -> [ConfigurationProfile] {
        switch sortBy {
        case .name:
            return profiles.sorted(by: { $0.name < $1.name })
        case .gestureCount:
            return profiles.sorted(by: { $0.gestures.count > $1.gestures.count })
        case .creationDate:
            return profiles.sorted(by: { $0.createdDate > $1.createdDate })
        case .lastModified:
            return profiles.sorted(by: { $0.modifiedDate > $1.modifiedDate })
        }
    }

    // MARK: - Validation

    /// Validates a profile name
    /// - Parameters:
    ///   - name: Name to validate
    ///   - excludingId: Optional ID to exclude from duplicate check (for renaming)
    /// - Returns: Validation result
    func validateProfileName(_ name: String, excludingId: UUID? = nil) -> ProfileNameValidation {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            return .invalid(reason: "Profile name cannot be empty")
        }

        if trimmedName.count > 50 {
            return .invalid(reason: "Profile name is too long (max 50 characters)")
        }

        // Validate against LIVE state (source of truth), not the @Published
        // cache, so validation can't pass/fail on a stale profile list.
        let isDuplicate = configuration.profilesSnapshot.contains { profile in
            profile.id != excludingId && profile.name == trimmedName
        }

        if isDuplicate {
            return .invalid(reason: "A profile with this name already exists")
        }

        return .valid
    }
}

// MARK: - Supporting Types

enum ProfileSortCriteria {
    case name
    case gestureCount
    case creationDate
    case lastModified
}

enum ProfileNameValidation {
    case valid
    case invalid(reason: String)

    var isValid: Bool {
        switch self {
        case .valid:
            return true
        case .invalid:
            return false
        }
    }

    var errorMessage: String? {
        switch self {
        case .valid:
            return nil
        case .invalid(let reason):
            return reason
        }
    }
}
