import Foundation
import SwiftUI
import AppKit

// MARK: - UIServices
// Central service layer for UI to interact with backend functionality
// All UI components should use this service instead of directly accessing backend classes

public class UIServices: ObservableObject {
    static let shared = UIServices()

    // Dependencies - Core
    let configuration = Configuration.shared
    private let profileManager = ProfileManager.shared
    private let serviceAdapter = ServicePluginAdapter()

    // Service accessors using plugin system with adapter
    private var gestureService: GestureConfigurationService {
        serviceAdapter.getGestureConfigurationService()
    }
    private var profileManagementService: ProfileManagementService {
        serviceAdapter.getProfileManagementService()
    }
    private var profileImportExportService: ProfileImportExportService {
        serviceAdapter.getProfileImportExportService()
    }
    private var hapticFeedbackService: HapticFeedbackService {
        serviceAdapter.getHapticFeedbackService()
    }
    private var zoneVisualizationService: ZoneVisualizationService {
        serviceAdapter.getZoneVisualizationService()
    }
    private var developerModeService: DeveloperModeToggleService {
        serviceAdapter.getDeveloperModeToggleService()
    }
    private var debugLoggingService: DebugLoggingService {
        serviceAdapter.getDebugLoggingService()
    }
    private var settingsImportExportService: SettingsImportExportService {
        serviceAdapter.getSettingsImportExportService()
    }
    private var applicationResetService: ApplicationResetService {
        serviceAdapter.getApplicationResetService()
    }
    private var accessibilityPermissionService: AccessibilityPermissionService {
        serviceAdapter.getAccessibilityPermissionService()
    }
    private var menuBarVisibilityService: MenuBarVisibilityService {
        serviceAdapter.getMenuBarVisibilityService()
    }
    private var logFileService: LogFileService {
        serviceAdapter.getLogFileService()
    }
    private var pluginManagementService: PluginManagementService {
        serviceAdapter.getPluginManagementService()
    }
    private var performanceMonitorService: PerformanceMonitorService {
        serviceAdapter.getPerformanceMonitorService()
    }
    private var debugReportService: DebugReportService {
        serviceAdapter.getDebugReportService()
    }
    private var gestureSearchService: GestureSearchService {
        serviceAdapter.getGestureSearchService()
    }
    private var savedActionsSortService: SavedActionsSortService {
        serviceAdapter.getSavedActionsSortService()
    }
    private var systemInformationService: SystemInformationService {
        serviceAdapter.getSystemInformationService()
    }
    private var applicationDiscoveryService: ApplicationDiscoveryService {
        serviceAdapter.getApplicationDiscoveryService()
    }

    // MARK: - Published Properties for UI Binding
    @Published var profiles: [ConfigurationProfile] = []
    @Published var activeProfileId: UUID?
    @Published var gestures: [Gesture] = []
    @Published var savedActions: [SavedAction] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isOnboardingCompleted: Bool = UserDefaults.standard.bool(forKey: "MGOnboardingCompleted")

    var tutorialService = TutorialService.shared
    let licenseService = LicenseService.shared

    // MARK: - Initialization

    private init() {
        loadData()
        setupNotifications()
    }

    func setOnboardingCompleted(_ completed: Bool) {
        UserDefaults.standard.set(completed, forKey: "MGOnboardingCompleted")
        isOnboardingCompleted = completed
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(profilesChanged),
            name: .profilesDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(profileChanged),
            name: .profileDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(savedActionsChanged),
            name: Notification.Name("savedActionsDidChange"),
            object: nil
        )
    }

    @objc private func profilesChanged() {
        loadData()
    }

    @objc private func profileChanged() {
        loadData()
    }

    @objc private func savedActionsChanged() {
        loadSavedActions()
    }

    // MARK: - Data Loading

    func loadData() {
        let update = {
            self.profiles = self.configuration.profiles
            self.activeProfileId = self.configuration.activeProfileId
            self.gestures = self.configuration.gestures
            self.savedActions = SavedActionsManager.shared.savedActions
        }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async { update() } }
    }

    private func loadSavedActions() {
        let update = { self.savedActions = SavedActionsManager.shared.savedActions }
        if Thread.isMainThread { update() } else { DispatchQueue.main.async { update() } }
    }

    // MARK: - Profile Management

    func getActiveProfile() -> ConfigurationProfile? {
        return profileManagementService.getActiveProfile()
    }

    func switchToProfile(_ profileId: UUID) {
        profileManagementService.activateProfile(profileId: profileId)
        loadData()
    }

    func createProfile(name: String, basedOn: ConfigurationProfile? = nil) -> ConfigurationProfile? {
        let baseProfileId = basedOn?.id
        let profile = profileManagementService.createProfile(name: name, baseProfileId: baseProfileId)
        loadData()
        return profile
    }

    func deleteProfile(_ profileId: UUID) -> Bool {
        let success = profileManagementService.deleteProfile(profileId: profileId)
        if success {
            loadData()
        }
        return success
    }

    func renameProfile(_ profileId: UUID, to newName: String) -> Bool {
        let success = profileManagementService.updateProfile(profileId: profileId, name: newName)
        if success {
            loadData()
        }
        return success
    }

    func updateProfileGestures(_ profileId: UUID, gestures: [Gesture]) -> Bool {
        let success = profileManagementService.updateProfile(profileId: profileId, gestures: gestures)
        if success {
            loadData()
        }
        return success
    }

    func updateProfileKeyboardShortcut(_ profileId: UUID, shortcut: KeyboardTrigger?) -> Bool {
        let success = profileManagementService.updateProfile(profileId: profileId, keyboardShortcut: .some(shortcut))
        if success { loadData() }
        return success
    }

    func updateProfileKeyboardShortcutEnabled(_ profileId: UUID, enabled: Bool) -> Bool {
        let success = profileManagementService.updateProfile(profileId: profileId, keyboardShortcutEnabled: enabled)
        if success { loadData() }
        return success
    }

    func duplicateProfile(_ profileId: UUID) -> ConfigurationProfile? {
        let profile = profileManagementService.duplicateProfile(profileId: profileId)
        loadData()
        return profile
    }

    func importDefaultProfile(type: DefaultProfileType) -> Bool {
        let profile = profileManagementService.importDefaultProfile(type: type)
        if profile != nil {
            loadData()
            return true
        }
        return false
    }

    func resetToDefaultProfiles() {
        profileManagementService.resetToDefaults()
        loadData()
    }

    /// Replace the current profile's gestures with those from the given template
    func resetCurrentProfileToTemplate(_ type: DefaultProfileType) {
        guard let template = DefaultProfiles.getProfile(for: type) else { return }
        gestureService.replaceAllGestures(template.gestures)
        loadData()
    }

    func validateProfileName(_ name: String, excludingId: UUID? = nil) -> ProfileNameValidation {
        return profileManagementService.validateProfileName(name, excludingId: excludingId)
    }

    func searchProfiles(query: String) -> [ConfigurationProfile] {
        return profileManagementService.searchProfiles(query: query)
    }

    // MARK: - Gesture Management

    func getGesturesForActiveProfile() -> [Gesture] {
        return gestures
    }

    func addGesture(_ gesture: Gesture) -> Bool {
        let success = gestureService.addGesture(gesture)
        if success {
            loadData()
        }
        return success
    }

    func updateGesture(oldGesture: Gesture, newGesture: Gesture) -> Bool {
        let success = gestureService.updateGesture(oldGesture: oldGesture, newGesture: newGesture)
        if success {
            loadData()
        }
        return success
    }

    func removeGesture(_ gesture: Gesture) -> Bool {
        let success = gestureService.removeGesture(gesture)
        if success {
            loadData()
        }
        return success
    }

    func removeGestureAt(index: Int) -> Bool {
        guard index < gestures.count else { return false }
        let gesture = gestures[index]
        return removeGesture(gesture)
    }

    func clearAllGestures() {
        gestureService.clearAllGestures()
        loadData()
    }

    func isGestureConflicting(_ gesture: Gesture) -> Bool {
        return gestureService.isGestureConflicting(gesture)
    }

    func searchGestures(query: String) -> [Gesture] {
        return gestureSearchService.searchGestures(in: gestures, query: query)
    }

    func getModifiersDescription(_ modifiers: NSEvent.ModifierFlags) -> String {
        return gestureSearchService.modifiersDescription(modifiers)
    }

    // MARK: - Available Actions

    func getAvailableActions() -> [String: [PluginAction]] {
        return gestureService.getAvailableActions()
    }

    func getActionDefinition(for identifier: String) -> PluginAction? {
        return gestureService.getActionDefinition(for: identifier)
    }

    // MARK: - Import/Export

    func exportProfile(_ profileId: UUID, to url: URL) -> Bool {
        return profileManagementService.exportProfile(profileId: profileId, to: url)
    }

    func exportProfiles(_ profileIds: [UUID], to url: URL) -> Int {
        return profileManagementService.exportProfiles(profileIds: profileIds, to: url)
    }

    func importProfile(from url: URL) -> ConfigurationProfile? {
        let profile = profileManagementService.importProfile(from: url)
        loadData()
        return profile
    }

    func importMultipleProfiles(from url: URL) -> [ConfigurationProfile] {
        let profiles = profileManagementService.importMultipleProfiles(from: url)
        loadData()
        return profiles
    }

    // MARK: - App Profile Management

    func getAppProfileMappings() -> [AppProfileMapping] {
        return configuration.appProfileMappings
    }

    func getDisabledApps() -> [DisabledApp] {
        return configuration.disabledApps
    }

    func addAppProfileMapping(bundleId: String, appName: String, profileId: UUID) {
        configuration.addAppProfileMapping(bundleId: bundleId, appName: appName, profileId: profileId)
        loadData()
    }

    func removeAppProfileMapping(bundleId: String) {
        configuration.removeAppProfileMapping(bundleId: bundleId)
        loadData()
    }

    func addDisabledApp(bundleId: String, appName: String) {
        configuration.addDisabledApp(bundleId: bundleId, appName: appName)
        loadData()
    }

    func removeDisabledApp(bundleId: String) {
        configuration.removeDisabledApp(bundleId: bundleId)
        loadData()
    }

    func clearAllDisabledApps() {
        configuration.clearAllDisabledApps()
        loadData()
    }

    func getProfileForApp(bundleId: String) -> ConfigurationProfile? {
        return configuration.getProfileForApp(bundleId: bundleId)
    }

    func isAppDisabled(bundleId: String) -> Bool {
        return configuration.isAppDisabled(bundleId: bundleId)
    }

    func getAllInstalledApps() -> [(bundleId: String, name: String, icon: NSImage?)] {
        return applicationDiscoveryService.getAllInstalledApplications()
    }

    func searchInstalledApps(query: String) -> [(bundleId: String, name: String, icon: NSImage?)] {
        return applicationDiscoveryService.searchApplications(query: query)
    }

    // MARK: - Settings Management

    func isGesturesEnabled() -> Bool {
        return configuration.isEnabled
    }

    func setGesturesEnabled(_ enabled: Bool) {
        configuration.isEnabled = enabled
        configuration.save()
        NotificationCenter.default.post(name: Notification.Name("gesturesEnabledChanged"), object: nil)
    }

    func isLaunchAtLoginEnabled() -> Bool {
        return LaunchAtLoginService.shared.isEnabled
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        LaunchAtLoginService.shared.setEnabled(enabled)
    }

    func isHapticFeedbackEnabled() -> Bool {
        return hapticFeedbackService.isEnabled()
    }

    func setHapticFeedbackEnabled(_ enabled: Bool) {
        hapticFeedbackService.setEnabled(enabled)
    }

    func isMenuBarIconHidden() -> Bool {
        return menuBarVisibilityService.isHidden()
    }

    func setMenuBarIconHidden(_ hidden: Bool) {
        menuBarVisibilityService.setHidden(hidden)
    }

    func menuBarIconOption() -> MenuBarIconOption {
        return Configuration.shared.menuBarIconOption
    }

    func setMenuBarIconOption(_ option: MenuBarIconOption) {
        Configuration.shared.menuBarIconOption = option
        Configuration.shared.save()
        NotificationCenter.default.post(name: NSNotification.Name("GestureConfigurationChanged"), object: nil)
    }

    func customMenuBarIconData() -> Data? {
        return Configuration.shared.customMenuBarIconData
    }

    func customMenuBarIconIsTemplate() -> Bool {
        return Configuration.shared.customMenuBarIconIsTemplate
    }

    /// Sets the custom menu bar icon and switches the active option to `.custom`.
    func setCustomMenuBarIcon(data: Data, isTemplate: Bool) {
        Configuration.shared.customMenuBarIconData = data
        Configuration.shared.customMenuBarIconIsTemplate = isTemplate
        Configuration.shared.menuBarIconOption = .custom
        Configuration.shared.save()
        NotificationCenter.default.post(name: NSNotification.Name("GestureConfigurationChanged"), object: nil)
    }

    func setCustomMenuBarIconIsTemplate(_ isTemplate: Bool) {
        Configuration.shared.customMenuBarIconIsTemplate = isTemplate
        Configuration.shared.save()
        NotificationCenter.default.post(name: NSNotification.Name("GestureConfigurationChanged"), object: nil)
    }

    func isShowZoneHighlights() -> Bool {
        return zoneVisualizationService.isShowZoneHighlights()
    }

    func setShowZoneHighlights(_ show: Bool) {
        zoneVisualizationService.setShowZoneHighlights(show)
    }

    func isShowZoneLabels() -> Bool {
        return zoneVisualizationService.isShowZoneLabels()
    }

    func setShowZoneLabels(_ show: Bool) {
        zoneVisualizationService.setShowZoneLabels(show)
    }

    func getEdgeThreshold() -> CGFloat {
        return zoneVisualizationService.getEdgeThreshold()
    }

    func setEdgeThreshold(_ threshold: CGFloat) {
        zoneVisualizationService.setEdgeThreshold(threshold)
    }

    func getCornerSize() -> CGFloat {
        return zoneVisualizationService.getCornerSize()
    }

    func setCornerSize(_ size: CGFloat) {
        zoneVisualizationService.setCornerSize(size)
    }

    func getCornerBuffer() -> CGFloat {
        return zoneVisualizationService.getCornerBuffer()
    }

    func setCornerBuffer(_ buffer: CGFloat) {
        zoneVisualizationService.setCornerBuffer(buffer)
    }

    func isDeveloperModeEnabled() -> Bool {
        return developerModeService.isEnabled()
    }

    func setDeveloperModeEnabled(_ enabled: Bool) {
        developerModeService.setEnabled(enabled)
    }

    func isDebugModeEnabled() -> Bool {
        return debugLoggingService.isEnabled()
    }

    func setDebugModeEnabled(_ enabled: Bool) {
        debugLoggingService.setEnabled(enabled)
    }

    func isNotificationOnActivation() -> Bool {
        return Configuration.shared.notificationOnActivation
    }

    func setNotificationOnActivation(_ enabled: Bool) {
        Configuration.shared.notificationOnActivation = enabled
        Configuration.shared.save()
    }

    func exportAppSettings(to url: URL) -> Bool {
        return settingsImportExportService.exportSettings(to: url)
    }

    func importAppSettings(from url: URL, mergeProfiles: Bool = false) -> Bool {
        let result = settingsImportExportService.importSettings(from: url, mergeProfiles: mergeProfiles)
        if !result.success {
            errorMessage = result.error
        }
        loadData()
        return result.success
    }

    func resetAppToDefaults() {
        applicationResetService.resetToDefaults()
        loadData()
    }

    // MARK: - Developer Tools Management

    func getLogFiles() -> [URL] {
        return logFileService.getLogFiles().map { $0.url }
    }

    func deleteLogFile(_ url: URL) -> Bool {
        let success = logFileService.deleteLogFile(url)
        if !success {
            errorMessage = "Failed to delete log file"
        }
        return success
    }

    func clearAllLogs() -> Bool {
        return logFileService.clearAllLogs()
    }

    func exportLogs(to url: URL) -> Bool {
        let success = logFileService.exportLogs(to: url)
        if !success {
            errorMessage = "Failed to export logs"
        }
        return success
    }

    func getLoadedPlugins() -> [PluginInfo] {
        return pluginManagementService.getLoadedPlugins()
    }

    func enablePlugin(_ identifier: String) -> Bool {
        // Placeholder - plugins are always enabled when loaded
        return true
    }

    func disablePlugin(_ identifier: String) -> Bool {
        PluginManager.shared.unloadPlugin(identifier: identifier)
        return true
    }

    func reloadPlugin(_ identifier: String) -> Bool {
        return pluginManagementService.reloadPlugin(identifier)
    }

    func installPlugin(from url: URL) -> Bool {
        let result = pluginManagementService.installPlugin(from: url)
        if !result.success {
            errorMessage = result.error
        }
        return result.success
    }

    func uninstallPlugin(_ identifier: String) -> Bool {
        let result = pluginManagementService.uninstallPlugin(identifier)
        if !result.success {
            errorMessage = result.error
        }
        return result.success
    }

    func updatePluginPermissions(_ identifier: String, permissions: PluginPermissions) {
        pluginManagementService.updatePluginPermissions(identifier, permissions: permissions)
    }

    func getPluginActions(_ identifier: String) -> [PluginAction] {
        return pluginManagementService.getPluginActions(identifier)
    }

    func generateDebugReport() -> String {
        return debugReportService.generateReport()
    }

    // MARK: - System Information

    func getSystemMetrics() -> SystemMetrics {
        return systemInformationService.getSystemMetrics()
    }

    func getMemoryUsage() -> (resident: Int, virtual: Int)? {
        return systemInformationService.getMemoryUsage()
    }

    func formatBytes(_ bytes: Int) -> String {
        return systemInformationService.formatBytes(bytes)
    }

    func getProcessUptime() -> TimeInterval {
        return systemInformationService.getProcessUptime()
    }

    func formatUptime(_ uptime: TimeInterval) -> String {
        return systemInformationService.formatUptime(uptime)
    }

    func getThreadCount() -> Int {
        return systemInformationService.getThreadCount()
    }

    func getAppDiskUsage() -> Int64? {
        return systemInformationService.getAppDiskUsage()
    }

    // MARK: - Saved Actions Management

    func getSavedActions() -> [SavedAction] {
        return SavedActionsManager.shared.savedActions
    }

    func addSavedAction(_ action: SavedAction) {
        SavedActionsManager.shared.addAction(action)
        loadSavedActions()
    }

    func updateSavedAction(_ action: SavedAction) {
        SavedActionsManager.shared.updateAction(action)
        loadSavedActions()
    }

    func deleteSavedAction(_ action: SavedAction) {
        SavedActionsManager.shared.deleteAction(action)
        loadSavedActions()
    }

    func clearAllSavedActions() {
        SavedActionsManager.shared.clearAll()
        loadSavedActions()
    }

    func getSavedAction(byId id: UUID) -> SavedAction? {
        return SavedActionsManager.shared.getAction(byId: id)
    }

    func exportSavedAction(_ action: SavedAction) -> Data? {
        return SavedActionsManager.shared.exportAction(action)
    }

    func importSavedAction(from data: Data) -> SavedAction? {
        let action = SavedActionsManager.shared.importAction(from: data)
        if action != nil {
            loadSavedActions()
        }
        return action
    }

    func exportAllSavedActions() -> Data? {
        return SavedActionsManager.shared.exportAllActions()
    }

    func importSavedActions(from data: Data, replaceExisting: Bool = false) -> Bool {
        let success = SavedActionsManager.shared.importActions(from: data, replaceExisting: replaceExisting)
        if success {
            loadSavedActions()
        }
        return success
    }

    func sortSavedActions(_ actions: [SavedAction], by order: SavedActionsSortService.SortOrder) -> [SavedAction] {
        return savedActionsSortService.sortActions(actions, by: order)
    }

    func filterSavedActions(_ actions: [SavedAction], searchText: String) -> [SavedAction] {
        return savedActionsSortService.filterActions(actions, searchText: searchText)
    }

    func getIconForSavedAction(_ action: SavedAction) -> String {
        return savedActionsSortService.getIconForAction(action)
    }
}

// MARK: - String Extension

extension String {
    var expandingTildeInPath: String {
        return (self as NSString).expandingTildeInPath
    }
}

// MARK: - Plugin Info

struct PluginInfo {
    let identifier: String
    let name: String
    let version: String
    let author: String
    let description: String
    let category: ActionCategory
    let actionCount: Int
    let permissions: PluginPermissions
    let isBuiltIn: Bool
    let isEnabled: Bool
}

// MARK: - Default Profile Types

enum DefaultProfileType: String, CaseIterable {
    case windowManagement = "Window Management"
    case applicationManagement = "Application Management"
    case mediaControl = "Media Control"
    case browserNavigation = "Browser Navigation"
    case system = "System"
    case full = "Full"

    var description: String {
        switch self {
        case .windowManagement:
            return "Focused on window sizing, positioning, and spaces navigation"
        case .applicationManagement:
            return "App lifecycle, spaces, and Exposé — close, quit, hide, and switch"
        case .mediaControl:
            return "Control media playback, seeking, and volume"
        case .browserNavigation:
            return "Browser page and tab navigation: back/forward, reload, tabs"
        case .system:
            return "Brightness, Do Not Disturb, Dark Mode, lock screen, and screenshots"
        case .full:
            return "All default profiles combined, each on its own modifier combination"
        }
    }

    var iconName: String {
        switch self {
        case .windowManagement:
            return "rectangle.3.group"
        case .applicationManagement:
            return "square.grid.2x2"
        case .mediaControl:
            return "play.circle"
        case .browserNavigation:
            return "safari"
        case .system:
            return "gearshape"
        case .full:
            return "square.stack.3d.up"
        }
    }
}
