import Cocoa
import Carbon

/// Which glyph the menu bar status item shows when it's visible. `.custom`
/// pairs with `Configuration.customMenuBarIconData` (a user-supplied image);
/// every other case is a built-in SF Symbol alternative to the default hand.
enum MenuBarIconOption: String, Codable, CaseIterable {
    case cursor
    case cursorFill
    case tap
    case tapFill
    case motion
    case corners
    case custom

    /// SF Symbol name for the built-in options; nil for `.custom`, which is
    /// rendered from `customMenuBarIconData` instead.
    var symbolName: String? {
        switch self {
        case .cursor: return "hand.draw"
        case .cursorFill: return "hand.draw.fill"
        case .tap: return "hand.tap"
        case .tapFill: return "hand.tap.fill"
        case .motion: return "cursorarrow.motionlines"
        case .corners: return "rectangle.dashed"
        case .custom: return nil
        }
    }

    var displayName: String {
        switch self {
        case .cursor: return "Hand"
        case .cursorFill: return "Hand (Filled)"
        case .tap: return "Tap"
        case .tapFill: return "Tap (Filled)"
        case .motion: return "Motion Lines"
        case .corners: return "Corners"
        case .custom: return "Custom"
        }
    }
}

public class Configuration: Codable {
    // The static shared instance is the single source of truth for the app's configuration.
    public static let shared = Configuration()

    // --- Stored Properties ---
    var isEnabled: Bool = true
    var profiles: [ConfigurationProfile] = []
    var activeProfileId: UUID?
    var appProfileMappings: [AppProfileMapping] = []
    var disabledApps: [DisabledApp] = []  // Apps where gestures are disabled
    var hapticFeedbackEnabled: Bool = true
    var edgeThreshold: CGFloat = 30
    var cornerSize: CGFloat = 100
    var cornerBuffer: CGFloat = 50
    var showZoneHighlights: Bool = true
    var showZoneLabels: Bool = false
    // Transient: not persisted, synced from plugin settings at runtime
    var zoneHighlightColor: NSColor = NSColor.systemBlue.withAlphaComponent(0.3)
    var hideFromMenuBar: Bool = false  // When true, app hides menu bar icon
    var menuBarIconOption: MenuBarIconOption = .cursor  // Which glyph to show in the menu bar
    var customMenuBarIconData: Data?  // User-supplied image, used when menuBarIconOption == .custom
    var customMenuBarIconIsTemplate: Bool = false  // Render the custom icon monochrome (menu-bar-native) vs. as-is (color)
    var debugModeEnabled: Bool = false  // When true, enables logging
    var developerModeEnabled: Bool = false  // When true, shows developer tab
    var notificationOnActivation: Bool = false  // When true, shows a banner notification when any gesture fires
    var freeModeProfileId: UUID?  // The single profile allowed in Free mode

    // Plugin configuration storage - allows plugins to store arbitrary data
    var pluginConfigurations: [String: AnyCodable] = [:]

    // Thread safety
    private let configQueue = DispatchQueue(label: "com.mousegestures.config", attributes: .concurrent)

    // Save batching
    private var saveTimer: Timer?
    private var pendingSave = false
    private let saveQueue = DispatchQueue(label: "com.mousegestures.save")

    // The initializer is private to ensure no other instances can be created.
    private init() {
        loadConfigurationFromFile()
    }

    /// Decodes `T` but never throws: a malformed element becomes `nil` instead
    /// of failing its whole container. Used to decode the profiles array
    /// element-wise so one corrupt / hand-edited profile can't take down every
    /// profile (the outer load would otherwise throw and silently revert the
    /// entire configuration to a single default — total data loss, not a crash).
    private struct FailableDecodable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            self.value = try? container.decode(T.self)
        }
    }

    // Helper struct for robust decoding from JSON. Decode-only (Configuration
    // encodes itself, never this shim), so it conforms to Decodable, letting
    // `profiles` use the lossy wrapper above.
    private struct DecodedConfiguration: Decodable {
        var isEnabled: Bool
        var profiles: [FailableDecodable<ConfigurationProfile>]
        var activeProfileId: UUID?
        var appProfileMappings: [AppProfileMapping]
        var disabledApps: [DisabledApp]?
        var hapticFeedbackEnabled: Bool?
        var edgeThreshold: CGFloat?
        var cornerSize: CGFloat?
        var cornerBuffer: CGFloat?
        var showZoneHighlights: Bool?
        var showZoneLabels: Bool?
        var hideFromMenuBar: Bool?
        var menuBarIconOption: MenuBarIconOption?
        var customMenuBarIconData: Data?
        var customMenuBarIconIsTemplate: Bool?
        var debugModeEnabled: Bool?
        var developerModeEnabled: Bool?
        var notificationOnActivation: Bool?
        var freeModeProfileId: UUID?
        var pluginConfigurations: [String: AnyCodable]?
    }

    // Defines which properties are saved to disk.
    enum CodingKeys: String, CodingKey {
        case isEnabled, profiles, activeProfileId, appProfileMappings, disabledApps, hapticFeedbackEnabled, edgeThreshold, cornerSize, cornerBuffer, showZoneHighlights, showZoneLabels, hideFromMenuBar, menuBarIconOption, customMenuBarIconData, customMenuBarIconIsTemplate, debugModeEnabled, developerModeEnabled, notificationOnActivation, freeModeProfileId, pluginConfigurations
    }

    // --- Computed Properties ---
    // These act as a "window" into the settings of the currently active profile.

    private var activeProfileIndex: Int? {
        guard let id = activeProfileId else { return nil }
        return profiles.firstIndex { $0.id == id }
    }

    var gestures: [Gesture] {
        get {
            configQueue.sync {
                activeProfile?.gestures ?? []
            }
        }
        set {
            configQueue.async(flags: .barrier) {
                guard let index = self.activeProfileIndex else { return }
                self.profiles[index].gestures = newValue
                self.profiles[index].updateModifiedDate()
            }
        }
    }

    // hapticFeedbackEnabled, edgeThreshold, cornerSize, cornerBuffer
    // are now top-level stored properties (global settings, not per-profile)

    var activeProfile: ConfigurationProfile? {
        get {
            configQueue.sync {
                guard let id = activeProfileId else { return nil }
                return profiles.first { $0.id == id }
            }
        }
        set {
            configQueue.async(flags: .barrier) {
                self.activeProfileId = newValue?.id
            }
        }
    }

    // MARK: - Thread-safe profile access (for the profile-service layer)
    //
    // ProfileManager / ProfileManagementService / ProfileImportExportService /
    // ProfileTemplateService historically read and mutated `profiles` (and
    // `activeProfileId`) directly, off `configQueue`. That races the save
    // encoder, which walks the same arrays under a configQueue barrier in
    // `writeConfigurationToDisk`: a concurrent append/remove can reallocate the
    // array's backing buffer while `JSONEncoder().encode(self)` is iterating it
    // — a crash, or a truncated/corrupt gestures.json. (The `switch_profile`
    // gesture action reaches ProfileManager off the main thread, so this is not
    // hypothetical.) These accessors route those reads and writes through the
    // same barrier the rest of Configuration uses.
    //
    // The `mutate*`/`set*` calls run synchronously (`.sync(flags: .barrier)`)
    // so a caller observes its own write on return. The closures passed to
    // `mutateProfiles` must NOT call back into any of these synchronized
    // accessors (doing so re-enters the same queue and deadlocks).

    /// Synchronized snapshot of all profiles.
    var profilesSnapshot: [ConfigurationProfile] {
        configQueue.sync { profiles }
    }

    /// Synchronized read of the active profile id.
    var activeProfileIdSnapshot: UUID? {
        configQueue.sync { activeProfileId }
    }

    /// Synchronized snapshot of the profiles and the active id, read together
    /// (so an index computed from the array stays consistent with the id).
    var profilesState: (profiles: [ConfigurationProfile], activeId: UUID?) {
        configQueue.sync { (self.profiles, self.activeProfileId) }
    }

    /// Synchronized lookup of a single profile by id.
    func profileSnapshot(withId id: UUID) -> ConfigurationProfile? {
        configQueue.sync { profiles.first { $0.id == id } }
    }

    /// Atomic read-modify-write over the profiles array under the configQueue
    /// barrier. Returns the closure's result.
    @discardableResult
    func mutateProfiles<T>(_ body: (inout [ConfigurationProfile]) -> T) -> T {
        configQueue.sync(flags: .barrier) { body(&self.profiles) }
    }

    /// Atomically replaces all profiles and the active id under the barrier.
    func setProfiles(_ newProfiles: [ConfigurationProfile], activeProfileId newActiveId: UUID?) {
        configQueue.sync(flags: .barrier) {
            self.profiles = newProfiles
            self.activeProfileId = newActiveId
        }
    }

    // --- Core Methods ---

    private func loadConfigurationFromFile() {
        let url = Configuration.configurationURL

        guard FileManager.default.fileExists(atPath: url.path) else {
            log.log("No configuration file found. Creating and saving a default configuration.")
            let defaultProfile = Configuration.defaultProfile
            self.profiles = [defaultProfile]
            self.activeProfileId = defaultProfile.id
            self.save()
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(DecodedConfiguration.self, from: data)

            self.isEnabled = decoded.isEnabled
            // Drop any profile that failed to decode rather than failing the
            // whole load; log so the loss is visible.
            let decodedProfiles = decoded.profiles.compactMap { $0.value }
            let skippedCount = decoded.profiles.count - decodedProfiles.count
            if skippedCount > 0 {
                log.log("WARNING: Skipped \(skippedCount) unreadable profile(s) while loading configuration.")
            }
            self.profiles = decodedProfiles.map(Configuration.migratingLegacyCoreActions)
            self.activeProfileId = decoded.activeProfileId
            self.appProfileMappings = decoded.appProfileMappings
            self.disabledApps = decoded.disabledApps ?? []
            self.showZoneHighlights = decoded.showZoneHighlights ?? true
            self.showZoneLabels = decoded.showZoneLabels ?? false

            // Global zone/haptic settings
            self.hapticFeedbackEnabled = decoded.hapticFeedbackEnabled ?? true
            self.edgeThreshold = decoded.edgeThreshold ?? 30
            self.cornerSize = decoded.cornerSize ?? 100
            self.cornerBuffer = decoded.cornerBuffer ?? 50
            self.hideFromMenuBar = decoded.hideFromMenuBar ?? false
            self.menuBarIconOption = decoded.menuBarIconOption ?? .cursor
            self.customMenuBarIconData = decoded.customMenuBarIconData
            self.customMenuBarIconIsTemplate = decoded.customMenuBarIconIsTemplate ?? false
            self.debugModeEnabled = decoded.debugModeEnabled ?? false
            self.developerModeEnabled = decoded.developerModeEnabled ?? false
            self.notificationOnActivation = decoded.notificationOnActivation ?? false
            self.freeModeProfileId = decoded.freeModeProfileId
            self.pluginConfigurations = decoded.pluginConfigurations ?? [:]

            // Apply debug mode setting to logger
            log.isDebugEnabled = self.debugModeEnabled

            log.log("Successfully loaded configuration from disk.")

            if self.profiles.isEmpty {
                log.log("No profiles found. Creating the default Window Management profile.")
                let defaultProfile = Configuration.defaultProfile
                self.profiles = [defaultProfile]
                self.activeProfileId = defaultProfile.id
                self.save()
            } else if let activeId = self.activeProfileId {
                // Guard against an active id that points nowhere (e.g. the active
                // profile failed to decode and was skipped above). Without this,
                // `activeProfile` returns nil and no gestures resolve until the
                // user manually switches profiles.
                if !self.profiles.contains(where: { $0.id == activeId }) {
                    log.log("Active profile \(activeId) not found after load; falling back to default/first.")
                    self.activeProfileId = self.profiles.first(where: { $0.isDefault })?.id ?? self.profiles.first?.id
                    self.save()
                }
            } else {
                // No active profile recorded — pick the default (or first).
                self.activeProfileId = self.profiles.first(where: { $0.isDefault })?.id ?? self.profiles.first?.id
                self.save()
            }

        } catch {
            log.log("FATAL: Error loading configuration: \(error). Reverting to default settings.")
            let defaultProfile = Configuration.defaultProfile
            self.profiles = [defaultProfile]
            self.activeProfileId = defaultProfile.id
        }
    }

    /// Rewrites action identifiers from the retired `com.mousegestures.core`
    /// plugin (deleted — it only ever forwarded to the plugin that actually
    /// owns each action) to their current equivalents, so gestures saved
    /// before the plugin reorg keep resolving instead of silently failing.
    private static func migratingLegacyCoreActions(_ profile: ConfigurationProfile) -> ConfigurationProfile {
        let windowActions: Set<String> = [
            "close_window", "minimize", "maximize", "fullscreen", "hide_app",
            "quit_app", "mission_control", "show_desktop", "app_expose",
            "cycle_window", "cycle_space"
        ]
        let systemActions: Set<String> = ["lock_screen", "sleep_display", "empty_trash"]

        func migrate(_ identifier: String) -> String {
            let prefix = "com.mousegestures.core."
            guard identifier.hasPrefix(prefix) else { return identifier }
            let action = String(identifier.dropFirst(prefix.count))
            if action == "switch_profile" { return "com.mousegestures.automation.switch_profile" }
            if windowActions.contains(action) { return "com.mousegestures.window.\(action)" }
            if systemActions.contains(action) { return "com.mousegestures.system.\(action)" }
            return identifier
        }

        var migrated = profile
        migrated.gestures = profile.gestures.map { gesture in
            var g = gesture
            g.actionIdentifier = migrate(g.actionIdentifier)
            if let longPress = g.longPressActionIdentifier {
                g.longPressActionIdentifier = migrate(longPress)
            }
            return g
        }
        return migrated
    }

    func save() {
        // Schedule batched save to reduce disk I/O
        scheduleSave()
    }

    private func scheduleSave() {
        saveQueue.async { [weak self] in
            guard let self = self else { return }

            self.pendingSave = true

            // Cancel existing timer
            DispatchQueue.main.async {
                self.saveTimer?.invalidate()

                // Create new timer for batched save (1 second delay)
                self.saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
                    self?.performSave()
                }
            }
        }
    }

    /// Encodes the configuration and writes it atomically to disk.
    /// `requirePending` gates the batched path (only write if a save is
    /// actually pending); the synchronous `saveImmediate()` path passes
    /// `false` so it always persists regardless of the pending flag.
    private func writeConfigurationToDisk(requirePending: Bool) {
        saveQueue.sync {
            if requirePending {
                guard pendingSave else { return }
                pendingSave = false
            }

            do {
                // Snapshot under a barrier so concurrent mutators can't tear the
                // arrays while the encoder walks them. The mapping count is read
                // inside the same barrier — a bare `self.appProfileMappings.count`
                // here (off configQueue) would race a concurrent barrier writer
                // such as addAppProfileMapping.
                let (data, mappingCount) = try self.configQueue.sync(flags: .barrier) { () -> (Data, Int) in
                    (try JSONEncoder().encode(self), self.appProfileMappings.count)
                }

                log.log("Saving configuration to disk. Mappings count: \(mappingCount)")

                // Atomic write: writes to a temp file then renames, so a
                // crash mid-write can't leave a truncated gestures.json.
                try data.write(to: Configuration.configurationURL, options: .atomic)

                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("GestureConfigurationChanged"), object: nil)
                }
            } catch {
                log.log("Error saving configuration: \(error)")
            }
        }
    }

    private func performSave() {
        // Must NOT dispatch onto `saveQueue` here: writeConfigurationToDisk
        // synchronizes internally via `saveQueue.sync`, and calling that from
        // a block already executing on saveQueue is a guaranteed deadlock
        // that libdispatch traps as a fatal client bug ("dispatch_sync called
        // on queue already owned by current thread"). Hop onto a separate
        // queue instead so the write still happens off the caller's thread
        // (the 1s debounce Timer fires on main).
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.writeConfigurationToDisk(requirePending: true)
        }
    }

    // Force immediate, synchronous save (for critical operations / termination).
    func saveImmediate() {
        // Cancel any pending batched save so it can't fire after this one and
        // clobber a newer state. The timer lives on the main run loop, so hop
        // to main to invalidate it safely — but only via async if we're already
        // on the main thread (main.sync from main would deadlock).
        let invalidateTimer = { [weak self] in
            self?.saveTimer?.invalidate()
            self?.saveTimer = nil
        }
        if Thread.isMainThread {
            invalidateTimer()
        } else {
            DispatchQueue.main.sync(execute: invalidateTimer)
        }
        saveQueue.sync {
            pendingSave = false
        }
        writeConfigurationToDisk(requirePending: false)
    }

    func applyProfile(_ profile: ConfigurationProfile, setAsDefault: Bool = false) {
        // Mutate under a barrier so this serializes with configQueue readers
        // (getters and the save encoder) instead of racing them — a plain
        // assignment here concurrent with `JSONEncoder().encode(self)` in
        // performSave could read a half-published array.
        configQueue.async(flags: .barrier) {
            self.activeProfileId = profile.id

            // If setAsDefault is true, mark this as the new default profile
            if setAsDefault {
                // Mark all profiles as non-default
                for i in 0..<self.profiles.count {
                    self.profiles[i].isDefault = false
                }
                // Mark the selected profile as default
                if let index = self.profiles.firstIndex(where: { $0.id == profile.id }) {
                    self.profiles[index].isDefault = true
                }
            }
        }
    }

    // --- Profile Management Methods (for UI) ---

    func createProfile(name: String) -> ConfigurationProfile? {
        // Enforce license limits: only 1 profile allowed for Free version.
        // Read profiles under the queue (not nested inside the barrier below).
        let currentProfiles = configQueue.sync { profiles }
        if !LicenseService.shared.canUseMultipleProfiles && !currentProfiles.isEmpty {
            log.log("Access Denied: Multiple profiles require a Pro license.")
            return nil
        }

        // Snapshot the active profile's gestures BEFORE the barrier (the
        // `gestures` computed property does a configQueue.sync read; calling
        // it from inside a barrier on the same concurrent queue would
        // deadlock).
        let activeGestures = self.gestures

        // Create the new profile by copying gestures from the currently active one.
        let newProfile = ConfigurationProfile(
            name: name,
            gestures: activeGestures,
            isDefault: false
        )
        configQueue.async(flags: .barrier) {
            self.profiles.append(newProfile)
        }
        save()
        return newProfile
    }

    func deleteProfile(id: UUID) -> Bool {
        // Find, decide, and remove atomically inside a single barrier so the
        // mutation is serialized with configQueue readers (the getters and the
        // save encoder) AND the index can't go stale between lookup and
        // removal. The previous version read the index under one `sync`, then
        // removed at that index in a later `async` barrier — a concurrent
        // mutation in between could shift/invalidate the index (wrong profile
        // removed, or out-of-bounds crash). `wasActive` is likewise read inside
        // the barrier rather than off-queue.
        let removed: Bool = configQueue.sync(flags: .barrier) {
            guard profiles.count > 1,
                  let idx = profiles.firstIndex(where: { $0.id == id }) else {
                return false
            }
            let wasActive = (self.activeProfileId == id)
            self.profiles.remove(at: idx)
            // If the deleted profile was active, switch to the default or the first available.
            if wasActive {
                self.activeProfileId = self.profiles.first(where: { $0.isDefault })?.id ?? self.profiles.first?.id
            }
            return true
        }

        guard removed else {
            log.log("Cannot delete profile: It is the last one or not found.")
            return false
        }

        save()
        return true
    }

    func duplicateProfile(id: UUID, newName: String) -> ConfigurationProfile? {
        // Enforce license limits
        let currentProfiles = configQueue.sync { profiles }
        if !LicenseService.shared.canUseMultipleProfiles && !currentProfiles.isEmpty {
            log.log("Access Denied: Multiple profiles require a Pro license.")
            return nil
        }

        guard var profileToDuplicate = currentProfiles.first(where: { $0.id == id }) else { return nil }

        profileToDuplicate.id = UUID() // Assign a new unique ID
        profileToDuplicate.name = newName
        profileToDuplicate.isDefault = false
        profileToDuplicate.updateModifiedDate()

        configQueue.async(flags: .barrier) {
            self.profiles.append(profileToDuplicate)
        }
        save()
        return profileToDuplicate
    }

    // --- App Mapping Methods ---

    func addAppProfileMapping(bundleId: String, appName: String, profileId: UUID) {
        // Enforce license limits: advanced targeting requires a Pro license
        if !LicenseService.shared.canUseAdvancedTargeting {
            log.log("Access Denied: Advanced targeting (App-specific profiles) requires a Pro license.")
            return
        }

        let newMapping = AppProfileMapping(appBundleIdentifier: bundleId, appName: appName, profileId: profileId)
        configQueue.async(flags: .barrier) {
            self.appProfileMappings.removeAll { $0.appBundleIdentifier == bundleId }
            self.appProfileMappings.append(newMapping)
        }
        save()
    }

    func removeAppProfileMapping(bundleId: String) {
        configQueue.async(flags: .barrier) {
            self.appProfileMappings.removeAll { $0.appBundleIdentifier == bundleId }
        }
        save()
    }

    func getProfileForApp(bundleId: String) -> ConfigurationProfile? {
        return configQueue.sync {
            guard let mapping = appProfileMappings.first(where: { $0.appBundleIdentifier == bundleId }) else { return nil }
            return profiles.first { $0.id == mapping.profileId }
        }
    }

    func switchToAppProfile(bundleId: String) {
        // If the app has a specific profile mapping, use it
        // Otherwise, stay with the current profile (don't switch to default)
        // Read the active id through the synchronized accessor — this runs off
        // the main thread (AppConfigurationDetector fires on app switch), so a
        // bare `activeProfileId` read would race a concurrent barrier writer.
        let currentActive = activeProfileIdSnapshot
        guard let targetProfile = getProfileForApp(bundleId: bundleId),
              targetProfile.id != currentActive else {
            // App doesn't have a mapping - keep current profile
            return
        }

        // applyProfile dispatches its own barrier; the old code wrapped that in
        // a second barrier to toggle isAppBasedSwitch around it, but the inner
        // async barrier doesn't run synchronously inside the outer one, so the
        // flag toggling was already non-load-bearing here. Drop the redundant
        // nesting and just call applyProfile.
        applyProfile(targetProfile)

        // Save on main queue to avoid race conditions
        DispatchQueue.main.async {
            self.save()
        }
    }

    // --- Disabled Apps Methods ---

    func isAppDisabled(bundleId: String) -> Bool {
        return configQueue.sync {
            disabledApps.contains { $0.appBundleIdentifier == bundleId }
        }
    }

    func addDisabledApp(bundleId: String, appName: String) {
        let disabledApp = DisabledApp(appBundleIdentifier: bundleId, appName: appName)
        configQueue.async(flags: .barrier) {
            // Remove any existing entry for this bundle ID
            self.disabledApps.removeAll { $0.appBundleIdentifier == bundleId }
            // Add new disabled app entry
            self.disabledApps.append(disabledApp)
        }
        save()
    }

    func removeDisabledApp(bundleId: String) {
        configQueue.async(flags: .barrier) {
            self.disabledApps.removeAll { $0.appBundleIdentifier == bundleId }
        }
        save()
    }

    func clearAllDisabledApps() {
        configQueue.async(flags: .barrier) {
            self.disabledApps.removeAll()
        }
        save()
    }

    // --- Plugin Configuration Methods ---

    /// Get configuration for a specific plugin
    func getPluginConfiguration(for pluginIdentifier: String) -> AnyCodable? {
        return configQueue.sync {
            pluginConfigurations[pluginIdentifier]
        }
    }

    /// Set configuration for a specific plugin
    func setPluginConfiguration(for pluginIdentifier: String, configuration: AnyCodable?) {
        configQueue.async(flags: .barrier) {
            if let config = configuration {
                self.pluginConfigurations[pluginIdentifier] = config
            } else {
                self.pluginConfigurations.removeValue(forKey: pluginIdentifier)
            }
            self.save()
        }
    }

    /// Get a specific configuration value for a plugin
    func getPluginConfigValue<T>(for pluginIdentifier: String, key: String, type: T.Type) -> T? {
        guard let pluginConfig = getPluginConfiguration(for: pluginIdentifier),
              let dict = pluginConfig.value as? [String: Any],
              let value = dict[key] as? T else {
            return nil
        }
        return value
    }

    /// Set a specific configuration value for a plugin
    func setPluginConfigValue(for pluginIdentifier: String, key: String, value: Any?) {
        configQueue.async(flags: .barrier) {
            // Get or create the plugin configuration dictionary
            var config: [String: Any]
            if let existing = self.pluginConfigurations[pluginIdentifier],
               let dict = existing.value as? [String: Any] {
                config = dict
            } else {
                config = [:]
            }

            // Update the value
            if let val = value {
                config[key] = val
            } else {
                config.removeValue(forKey: key)
            }

            // Store back as AnyCodable
            self.pluginConfigurations[pluginIdentifier] = AnyCodable(config)
            self.save()
        }
    }

    /// Clear all configuration for a plugin
    func clearPluginConfiguration(for pluginIdentifier: String) {
        configQueue.async(flags: .barrier) {
            self.pluginConfigurations.removeValue(forKey: pluginIdentifier)
            self.save()
        }
    }

    /// Get all plugin configurations
    func getAllPluginConfigurations() -> [String: AnyCodable] {
        return configQueue.sync {
            pluginConfigurations
        }
    }

    // MARK: - Detection Plugin Settings (convenience methods)

    /// Get all settings for a detection plugin as a dictionary
    func getPluginSettings(_ pluginIdentifier: String) -> [String: Any] {
        return configQueue.sync {
            if let config = pluginConfigurations[pluginIdentifier],
               let dict = config.value as? [String: Any] {
                return dict
            }
            return [:]
        }
    }

    /// Set all settings for a detection plugin from a dictionary
    func setPluginSettings(_ pluginIdentifier: String, settings: [String: Any]) {
        configQueue.async(flags: .barrier) {
            self.pluginConfigurations[pluginIdentifier] = AnyCodable(settings)
            self.save()
        }
    }

    // Reset entire configuration to defaults
    func resetToDefaults() {
        // Build the default profile outside the barrier (pure construction, no
        // configQueue access), then apply every mutation under a single barrier
        // so the array/dictionary reassignments serialize with the save encoder
        // instead of racing it (a bare `self.profiles = ...` here concurrent
        // with `JSONEncoder().encode(self)` can tear the backing buffers).
        let defaultProfile = Configuration.defaultProfile // matches ProfileTemplateService.resetToDefaults()
        configQueue.sync(flags: .barrier) {
            self.profiles = [defaultProfile]
            self.activeProfileId = defaultProfile.id
            self.appProfileMappings = []
            self.disabledApps = []
            self.isEnabled = true
            self.showZoneHighlights = true
            self.showZoneLabels = false
            self.hideFromMenuBar = false
            self.menuBarIconOption = .cursor
            self.customMenuBarIconData = nil
            self.customMenuBarIconIsTemplate = false
            self.debugModeEnabled = false
            self.developerModeEnabled = false
            self.notificationOnActivation = false
            self.pluginConfigurations = [:]

            // Reset global zone/haptic settings
            self.hapticFeedbackEnabled = true
            self.edgeThreshold = 30
            self.cornerSize = 100
            self.cornerBuffer = 50

            // Point Free mode at the freshly created profile so a non-Pro user
            // can actually switch to it. Leaving a stale UUID here would lock
            // Free users out of every profile (the new default has a new UUID).
            self.freeModeProfileId = defaultProfile.id
        }

        // Persist the reset. Without this the change lives only in memory until
        // the next unrelated save or clean-quit saveImmediate(), so a crash /
        // force-kill in between silently loses it. Matches the other reset paths
        // (ProfileManagementService / ProfileTemplateService) which both save().
        save()
    }

    // --- Global Settings Export/Import ---

    // Structure for exporting ALL app settings (not just profiles)
    struct GlobalSettingsExportData: Codable {
        let profiles: [ConfigurationProfile]
        let activeProfileId: UUID?
        let appProfileMappings: [AppProfileMapping]
        let disabledApps: [DisabledApp]
        let isEnabled: Bool
        let hapticFeedbackEnabled: Bool
        let edgeThreshold: CGFloat
        let cornerSize: CGFloat
        let cornerBuffer: CGFloat
        let showZoneHighlights: Bool
        let showZoneLabels: Bool
        let hideFromMenuBar: Bool
        let menuBarIconOption: MenuBarIconOption
        let customMenuBarIconData: Data?
        let customMenuBarIconIsTemplate: Bool
        let debugModeEnabled: Bool
        let pluginConfigurations: [String: AnyCodable]
        let exportDate: Date
        let appVersion: String

        init(config: Configuration) {
            self.profiles = config.profiles
            self.activeProfileId = config.activeProfileId
            self.appProfileMappings = config.appProfileMappings
            self.disabledApps = config.disabledApps
            self.isEnabled = config.isEnabled
            self.hapticFeedbackEnabled = config.hapticFeedbackEnabled
            self.edgeThreshold = config.edgeThreshold
            self.cornerSize = config.cornerSize
            self.cornerBuffer = config.cornerBuffer
            self.showZoneHighlights = config.showZoneHighlights
            self.showZoneLabels = config.showZoneLabels
            self.hideFromMenuBar = config.hideFromMenuBar
            self.menuBarIconOption = config.menuBarIconOption
            self.customMenuBarIconData = config.customMenuBarIconData
            self.customMenuBarIconIsTemplate = config.customMenuBarIconIsTemplate
            self.debugModeEnabled = config.debugModeEnabled
            self.pluginConfigurations = config.pluginConfigurations
            self.exportDate = Date()
            self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        }
    }

    func exportGlobalSettings() -> Data? {
        // Build the snapshot under the configQueue (a concurrent read that
        // serializes against barrier writers) so `GlobalSettingsExportData`'s
        // direct reads of `profiles`/`appProfileMappings`/`disabledApps`/
        // `pluginConfigurations` can't be torn by a concurrent profile switch,
        // import, or reset running its own barrier.
        let exportData = configQueue.sync { GlobalSettingsExportData(config: self) }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(exportData)
            log.log("Successfully exported global settings")
            return data
        } catch {
            log.log("Error encoding global settings for export: \(error)")
            return nil
        }
    }

    func importGlobalSettings(from data: Data, mergeProfiles: Bool = false) -> (success: Bool, error: String?) {
        do {
            let decoder = JSONDecoder()
            let importData = try decoder.decode(GlobalSettingsExportData.self, from: data)

            // Apply the whole import under a single barrier so the array/dict
            // reassignments and appends (profiles / appProfileMappings /
            // disabledApps / pluginConfigurations) serialize with the save
            // encoder instead of racing it. This runs from the Settings import
            // UI on the main thread, concurrent with background/batched saves.
            configQueue.sync(flags: .barrier) {
                // Store current profiles if merging
                let existingProfiles = mergeProfiles ? self.profiles : []

                // Import all settings
                self.isEnabled = importData.isEnabled
                self.hapticFeedbackEnabled = importData.hapticFeedbackEnabled
                self.edgeThreshold = importData.edgeThreshold
                self.cornerSize = importData.cornerSize
                self.cornerBuffer = importData.cornerBuffer
                self.showZoneHighlights = importData.showZoneHighlights
                self.showZoneLabels = importData.showZoneLabels
                self.hideFromMenuBar = importData.hideFromMenuBar
                self.menuBarIconOption = importData.menuBarIconOption
                self.customMenuBarIconData = importData.customMenuBarIconData
                self.customMenuBarIconIsTemplate = importData.customMenuBarIconIsTemplate
                self.debugModeEnabled = importData.debugModeEnabled
                self.pluginConfigurations = importData.pluginConfigurations

                if mergeProfiles {
                    // Merge profiles - assign new IDs to avoid conflicts
                    var profileIdMap: [UUID: UUID] = [:]

                    for var profile in importData.profiles {
                        let oldId = profile.id
                        profile.id = UUID()
                        profileIdMap[oldId] = profile.id

                        // Check for name conflicts
                        let baseName = profile.name
                        var suffix = 1
                        while existingProfiles.contains(where: { $0.name == profile.name }) ||
                              self.profiles.contains(where: { $0.name == profile.name }) {
                            profile.name = "\(baseName) (\(suffix))"
                            suffix += 1
                        }

                        profile.isDefault = false
                        self.profiles.append(profile)
                    }

                    // Update mappings with new profile IDs
                    for var mapping in importData.appProfileMappings {
                        if let newProfileId = profileIdMap[mapping.profileId] {
                            mapping.id = UUID()
                            mapping.profileId = newProfileId

                            // Only add if not already mapped
                            if !self.appProfileMappings.contains(where: { $0.appBundleIdentifier == mapping.appBundleIdentifier }) {
                                self.appProfileMappings.append(mapping)
                            }
                        }
                    }

                    // Merge disabled apps
                    for disabledApp in importData.disabledApps {
                        if !self.disabledApps.contains(where: { $0.appBundleIdentifier == disabledApp.appBundleIdentifier }) {
                            self.disabledApps.append(disabledApp)
                        }
                    }

                } else {
                    // Replace everything
                    self.profiles = importData.profiles
                    self.activeProfileId = importData.activeProfileId
                    self.appProfileMappings = importData.appProfileMappings
                    self.disabledApps = importData.disabledApps

                    // Ensure we have at least one profile
                    if self.profiles.isEmpty {
                        let defaultProfile = Configuration.defaultProfile
                        self.profiles = [defaultProfile]
                        self.activeProfileId = defaultProfile.id
                    }

                    // Ensure active profile exists
                    if let activeId = self.activeProfileId {
                        if !self.profiles.contains(where: { $0.id == activeId }) {
                            self.activeProfileId = self.profiles.first?.id
                        }
                    } else {
                        self.activeProfileId = self.profiles.first?.id
                    }
                }
            }

            // Apply debug mode setting to logger (outside the barrier; reads the
            // decoded source value rather than re-reading self off-queue).
            log.isDebugEnabled = importData.debugModeEnabled

            // Save configuration
            save()

            log.log("Successfully imported global settings (merge: \(mergeProfiles))")
            return (true, nil)

        } catch {
            log.log("Error importing global settings: \(error)")
            return (false, "Failed to import settings: \(error.localizedDescription)")
        }
    }

    // --- Profile Import/Export Methods ---

    func exportProfile(id: UUID) -> Data? {
        guard let profile = profileSnapshot(withId: id) else {
            log.log("Profile not found for export: \(id)")
            return nil
        }

        let exportData = ProfileExportData(profile: profile)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(exportData)
            log.log("Successfully exported profile: \(profile.name)")
            return data
        } catch {
            log.log("Error encoding profile for export: \(error)")
            return nil
        }
    }

    func exportAllProfiles() -> Data? {
        let snapshot = profilesSnapshot
        let exportData = ProfileBundleExportData(profiles: snapshot)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(exportData)
            log.log("Successfully exported \(snapshot.count) profiles")
            return data
        } catch {
            log.log("Error encoding profiles for export: \(error)")
            return nil
        }
    }

    func importProfile(from data: Data) -> (success: Bool, profileName: String?, error: String?) {
        do {
            let decoder = JSONDecoder()
            let exportData = try decoder.decode(ProfileExportData.self, from: data)
            var importedProfile = exportData.profile

            // Generate new ID for imported profile
            importedProfile.id = UUID()

            // Mark as non-default
            importedProfile.isDefault = false

            // De-dupe the name against the live list and append, both inside the
            // same barrier so the check-then-append is atomic and serialized with
            // the save encoder (a bare `profiles.append` here would race it).
            mutateProfiles { profiles in
                let baseName = importedProfile.name
                var suffix = 1
                while profiles.contains(where: { $0.name == importedProfile.name }) {
                    importedProfile.name = "\(baseName) (\(suffix))"
                    suffix += 1
                }
                profiles.append(importedProfile)
            }

            // Save configuration
            save()

            log.log("Successfully imported profile: \(importedProfile.name)")
            return (true, importedProfile.name, nil)

        } catch {
            log.log("Error importing profile: \(error)")
            return (false, nil, "Failed to import profile: \(error.localizedDescription)")
        }
    }

    func importProfiles(from data: Data) -> (success: Bool, count: Int, error: String?) {
        do {
            let decoder = JSONDecoder()
            let exportData = try decoder.decode(ProfileBundleExportData.self, from: data)

            // Do the whole batch (per-profile de-dupe + append) inside one
            // barrier so it is atomic and serialized with the save encoder; the
            // name check also sees profiles appended earlier in this same loop.
            let importedCount = mutateProfiles { profiles -> Int in
                var count = 0
                for var profile in exportData.profiles {
                    // Generate new ID for each imported profile
                    profile.id = UUID()

                    // Check for name conflicts and rename if necessary
                    let baseName = profile.name
                    var suffix = 1
                    while profiles.contains(where: { $0.name == profile.name }) {
                        profile.name = "\(baseName) (\(suffix))"
                        suffix += 1
                    }

                    // Mark as non-default
                    profile.isDefault = false

                    // Add to profiles
                    profiles.append(profile)
                    count += 1
                }
                return count
            }

            // Save configuration
            save()

            log.log("Successfully imported \(importedCount) profiles")
            return (true, importedCount, nil)

        } catch {
            log.log("Error importing profiles: \(error)")
            return (false, 0, "Failed to import profiles: \(error.localizedDescription)")
        }
    }

    static var applicationSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MouseGestures")
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        return appFolder
    }

    private static var configurationURL: URL {
        return applicationSupportDirectory.appendingPathComponent("gestures.json")
    }
}
