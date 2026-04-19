import SwiftUI

// MARK: - UI Plugin Protocol

/// Protocol defining the interface for UI tab plugins
protocol UIPlugin: ObservableObject {
    /// Unique identifier for the plugin
    var identifier: String { get }
    
    /// Display name for the tab
    var displayName: String { get }
    
    /// SF Symbol name for the tab icon
    var iconName: String { get }
    
    /// Plugin version
    var version: String { get }
    
    /// Plugin author
    var author: String { get }
    
    /// Plugin description
    var description: String { get }
    
    /// Category of the plugin
    var category: UIPluginCategory { get }
    
    /// Minimum app version required
    var minimumAppVersion: String { get }
    
    /// Whether the plugin should be visible by default
    var isVisibleByDefault: Bool { get }
    
    /// Whether the plugin requires special permissions
    var requiredPermissions: UIPluginPermissions { get }
    
    /// Sort order for the tab (lower values appear first)
    var sortOrder: Int { get }
    
    /// Whether the plugin requires a Pro license
    var isPro: Bool { get }
    
    /// Initialize the plugin with context
    func initialize(context: UIPluginContext) async throws
    
    /// Create the main view for this plugin
    @MainActor
    func createView() -> AnyView
    
    /// Create the settings view for this plugin (optional)
    @MainActor
    func createSettingsView() -> AnyView?
    
    /// Called when the tab becomes active
    @MainActor
    func onActivate()
    
    /// Called when the tab becomes inactive
    @MainActor
    func onDeactivate()
    
    /// Clean up resources
    func cleanup()
    
    /// Check if the plugin should be visible based on current conditions
    func shouldBeVisible(context: UIPluginContext) -> Bool
}

// MARK: - Default Implementations

extension UIPlugin {
    var isVisibleByDefault: Bool { true }
    var requiredPermissions: UIPluginPermissions { UIPluginPermissions() }
    var sortOrder: Int { 100 }
    var minimumAppVersion: String { "3.0.0" }
    var isPro: Bool { false }
    
    func createSettingsView() -> AnyView? { nil }
    func onActivate() {}
    func onDeactivate() {}
    func cleanup() {}
    func shouldBeVisible(context: UIPluginContext) -> Bool { isVisibleByDefault }
}

// MARK: - UI Plugin Category

public enum UIPluginCategory: String, CaseIterable {
    case core = "Core"
    case configuration = "Configuration"
    case management = "Management"
    case developer = "Developer"
    case `extension` = "Extension"
    case custom = "Custom"
    
    var displayName: String {
        switch self {
        case .core: return "Core Functionality"
        case .configuration: return "Configuration"
        case .management: return "Management"
        case .developer: return "Developer Tools"
        case .`extension`: return "Extensions"
        case .custom: return "Custom"
        }
    }
}

// MARK: - UI Plugin Permissions

public struct UIPluginPermissions: OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let none = UIPluginPermissions([])
    public static let configuration = UIPluginPermissions(rawValue: 1 << 0)
    public static let profiles = UIPluginPermissions(rawValue: 1 << 1)
    public static let gestures = UIPluginPermissions(rawValue: 1 << 2)
    public static let actions = UIPluginPermissions(rawValue: 1 << 3)
    public static let plugins = UIPluginPermissions(rawValue: 1 << 4)
    public static let system = UIPluginPermissions(rawValue: 1 << 5)
    public static let developer = UIPluginPermissions(rawValue: 1 << 6)
    
    public static let basic: UIPluginPermissions = [.configuration, .profiles, .gestures, .actions]
    public static let full: UIPluginPermissions = [.configuration, .profiles, .gestures, .actions, .plugins, .system, .developer]
}

// MARK: - UI Plugin Context

/// Context provided to UI plugins for accessing app functionality
public protocol UIPluginContext: AnyObject {
    /// Access to UI services
    var uiServices: UIServices { get }
    
    /// Access to configuration
    var configuration: Configuration { get }
    
    /// Access to profile manager
    var profileManager: ProfileManager { get }
    
    /// Access to plugin manager (for action plugins)
    var pluginManager: PluginManager { get }
    
    /// Logger for the plugin
    func logger(_ message: String, level: LogLevel)
    
    /// Show an alert
    @MainActor
    func showAlert(title: String, message: String, style: NSAlert.Style)
    
    /// Open a URL
    func openURL(_ url: URL)
    
    /// Get a preference value
    func getPreference(key: String) -> Any?
    
    /// Set a preference value
    func setPreference(key: String, value: Any?)
    
    /// Post a notification
    func postNotification(name: Notification.Name, object: Any?, userInfo: [AnyHashable: Any]?)
    
    /// Register for notifications
    func observeNotification(name: Notification.Name, using block: @escaping (Notification) -> Void) -> NSObjectProtocol
    
    /// Check if a feature is enabled
    func isFeatureEnabled(_ feature: String) -> Bool
    
    /// Get the current app version
    var appVersion: String { get }
    
    /// Check if developer mode is enabled
    var isDeveloperModeEnabled: Bool { get }
}

// MARK: - UI Plugin Metadata

struct UIPluginMetadata: Codable {
    let identifier: String
    let displayName: String
    let version: String
    let author: String
    let description: String
    let category: String
    let iconName: String
    let minimumAppVersion: String
    let requiredPermissions: [String]
    let mainClass: String
    let dependencies: [String]?
    let website: String?
    let supportEmail: String?
}

// MARK: - UI Plugin State

enum UIPluginState: Equatable {
    case unloaded
    case loading
    case loaded
    case active
    case error(String)
    case disabled
}

// MARK: - UI Plugin Lifecycle

protocol UIPluginLifecycle {
    /// Called before the plugin is loaded
    func willLoad()
    
    /// Called after the plugin is loaded
    func didLoad()
    
    /// Called before the plugin is unloaded
    func willUnload()
    
    /// Called after the plugin is unloaded
    func didUnload()
    
    /// Called when the plugin encounters an error
    func didEncounterError(_ error: Error)
}
