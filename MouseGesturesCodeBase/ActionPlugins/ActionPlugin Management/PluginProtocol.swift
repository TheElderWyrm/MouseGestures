import Cocoa

// MARK: - Plugin Protocol

/// Protocol that all action plugins must conform to
public protocol GestureActionPlugin: AnyObject {
    /// Unique identifier for the plugin
    var identifier: String { get }
    
    /// Display name for the plugin
    var name: String { get }
    
    /// Description of what the plugin does
    var description: String { get }
    
    /// Version of the plugin
    var version: String { get }
    
    /// Author of the plugin
    var author: String { get }
    
    /// Category for grouping in UI
    var category: ActionCategory { get }
    
    /// Icon for the plugin (optional)
    var icon: NSImage? { get }
    
    /// Actions provided by this plugin
    var providedActions: [PluginAction] { get }
    
    /// Called when the plugin is loaded
    func initialize(context: PluginContext) throws
    
    /// Called when the plugin is about to be unloaded
    func cleanup()
    
    /// Execute a specific action provided by this plugin
    func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws
    
    /// Validate that an action can be executed with given parameters
    func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult
    
    /// Get the configuration UI for a specific action (optional)
    func configurationView(for action: PluginAction) -> NSView?
    
    /// Whether the action has advanced configuration that requires a custom editor
    func hasAdvancedConfiguration(for action: PluginAction) -> Bool
    
    /// Present the advanced configuration editor as a sheet
    /// - Parameters:
    ///   - action: The action to configure
    ///   - currentParameters: Current parameter values
    ///   - parentWindow: Window to present the sheet on
    ///   - completion: Called with updated parameters, or nil if cancelled
    func presentAdvancedConfiguration(
        for action: PluginAction,
        currentParameters: [String: AnyCodable],
        parentWindow: NSWindow,
        completion: @escaping ([String: AnyCodable]?) -> Void
    )
}

// MARK: - Default Implementations
extension GestureActionPlugin {
    func configurationView(for action: PluginAction) -> NSView? { nil }
    func hasAdvancedConfiguration(for action: PluginAction) -> Bool { false }
    func presentAdvancedConfiguration(
        for action: PluginAction,
        currentParameters: [String: AnyCodable],
        parentWindow: NSWindow,
        completion: @escaping ([String: AnyCodable]?) -> Void
    ) {
        completion(nil)
    }
}

// MARK: - Supporting Types

/// Categories for organizing actions in the UI
public enum ActionCategory: String, CaseIterable, Codable {
    case core = "Core"
    case window = "Window Management"
    case system = "System Control"
    case media = "Media Control"
    case application = "Application"
    case file = "File Operations"
    case automation = "Automation"
    case productivity = "Productivity"
    case development = "Development"
    case network = "Network"
    case security = "Security"
    case accessibility = "Accessibility"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .core: return "star.circle"
        case .window: return "rectangle.split.3x3"
        case .system: return "gear"
        case .media: return "play.circle"
        case .application: return "app"
        case .file: return "folder"
        case .automation: return "gearshape.2"
        case .productivity: return "checkmark.circle"
        case .development: return "hammer"
        case .network: return "network"
        case .security: return "lock"
        case .accessibility: return "accessibility"
        case .custom: return "star"
        }
    }
}

/// Individual action provided by a plugin
public struct PluginAction: Codable, Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let requiresParameters: Bool
    public let supportedParameters: [ParameterDefinition]
    public let supportsLongPress: Bool
    public let supportsRepeat: Bool
    public let icon: String? // SF Symbol name
    /// When true, this action is hidden from the action selection UI but still available for programmatic use (e.g. bundles)
    public let hidden: Bool
    
    public init(
        id: String,
        name: String,
        description: String,
        requiresParameters: Bool = false,
        supportedParameters: [ParameterDefinition] = [],
        supportsLongPress: Bool = false,
        supportsRepeat: Bool = false,
        icon: String? = nil,
        hidden: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.requiresParameters = requiresParameters
        self.supportedParameters = supportedParameters
        self.supportsLongPress = supportsLongPress
        self.supportsRepeat = supportsRepeat
        self.icon = icon
        self.hidden = hidden
    }
}

/// Rule that controls when a parameter is visible based on another parameter's value
public struct ParameterVisibilityRule: Codable, Equatable {
    /// The key of the sibling parameter to check
    public let key: String
    /// The value that sibling parameter must have for this parameter to be visible (single match)
    public let value: String
    /// Multiple acceptable values — parameter is visible if sibling matches ANY of these (OR logic)
    public let values: [String]?
    
    public init(key: String, value: String) {
        self.key = key
        self.value = value
        self.values = nil
    }
    
    /// Create a rule that matches any of the given values
    public init(key: String, anyOf values: [String]) {
        self.key = key
        self.value = values.first ?? ""
        self.values = values
    }
    
    /// Returns true when the given current value satisfies this rule
    public func matches(_ currentValue: String) -> Bool {
        if let values = values {
            return values.contains(currentValue)
        }
        return currentValue == value
    }
}

/// Definition of a parameter that an action can accept
public struct ParameterDefinition: Codable, Equatable {
    public let key: String
    public let name: String
    public let type: ParameterType
    public let required: Bool
    public let defaultValue: AnyCodable?
    public let description: String
    public let validation: ValidationRule?
    /// When set, this parameter is only shown when the referenced sibling has the specified value
    public let visibleWhen: ParameterVisibilityRule?
    /// Visual group name — parameters with the same group are rendered together under a shared header
    public let group: String?
    /// Human-readable labels for selection values (key = raw value, value = display label)
    public let displayValues: [String: String]?
    /// Unit suffix shown after number fields (e.g. "%", "px", "s")
    public let suffix: String?
    /// Label shown in the picker when no value is selected (e.g. "Default Browser", "Default App")
    /// Defaults to "Select..." when nil
    public let placeholderLabel: String?
    /// When true, the application picker filters to installed browsers only
    public let filterBrowsers: Bool?
    /// Key identifying a runtime data provider for dynamic option lists (e.g. "window.layouts")
    public let optionProvider: String?

    public init(
        key: String,
        name: String,
        type: ParameterType,
        required: Bool = false,
        defaultValue: AnyCodable? = nil,
        description: String = "",
        validation: ValidationRule? = nil,
        visibleWhen: ParameterVisibilityRule? = nil,
        group: String? = nil,
        displayValues: [String: String]? = nil,
        suffix: String? = nil,
        placeholderLabel: String? = nil,
        filterBrowsers: Bool? = nil,
        optionProvider: String? = nil
    ) {
        self.key = key
        self.name = name
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
        self.description = description
        self.validation = validation
        self.visibleWhen = visibleWhen
        self.group = group
        self.displayValues = displayValues
        self.suffix = suffix
        self.placeholderLabel = placeholderLabel
        self.filterBrowsers = filterBrowsers
        self.optionProvider = optionProvider
    }
}

/// Types of parameters
public enum ParameterType: String, Codable {
    case string
    case number
    case boolean
    case path
    case url
    case color
    case keyboardShortcut
    case selection // From a list
    case script
    case json
    case window
    case application
    case coordinate
    case size
    case profile
    case actionId  // Picker showing all registered action identifiers
}

/// Validation rules for parameters
public struct ValidationRule: Codable, Equatable {
    public let minValue: Double?
    public let maxValue: Double?
    public let minLength: Int?
    public let maxLength: Int?
    public let regex: String?
    public let allowedValues: [AnyCodable]?
    public let fileExists: Bool?
    public let isDirectory: Bool?
    
    public init(
        minValue: Double? = nil,
        maxValue: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        regex: String? = nil,
        allowedValues: [AnyCodable]? = nil,
        fileExists: Bool? = nil,
        isDirectory: Bool? = nil
    ) {
        self.minValue = minValue
        self.maxValue = maxValue
        self.minLength = minLength
        self.maxLength = maxLength
        self.regex = regex
        self.allowedValues = allowedValues
        self.fileExists = fileExists
        self.isDirectory = isDirectory
    }
}

/// Parameters passed to an action
public struct ActionParameters: Codable {
    private var values: [String: AnyCodable]
    
    public init() {
        self.values = [:]
    }
    
    public init(values: [String: AnyCodable]) {
        self.values = values
    }
    
    public subscript(key: String) -> AnyCodable? {
        get { values[key] }
        set { values[key] = newValue }
    }
    
    public func string(for key: String) -> String? {
        values[key]?.value as? String
    }
    
    public func number(for key: String) -> Double? {
        values[key]?.value as? Double
    }
    
    public func bool(for key: String) -> Bool? {
        values[key]?.value as? Bool
    }
    
    public func array(for key: String) -> [Any]? {
        values[key]?.value as? [Any]
    }
    
    public func dictionary(for key: String) -> [String: Any]? {
        values[key]?.value as? [String: Any]
    }
    
    public var keys: [String] {
        Array(values.keys)
    }
    
    public var isEmpty: Bool {
        values.isEmpty
    }
}

/// Result of validating an action
public struct ValidationResult {
    public let isValid: Bool
    public let errors: [String]
    public let warnings: [String]
    
    public init(isValid: Bool = true, errors: [String] = [], warnings: [String] = []) {
        self.isValid = isValid
        self.errors = errors
        self.warnings = warnings
    }
    
    public static var valid: ValidationResult {
        ValidationResult()
    }
    
    public static func invalid(error: String) -> ValidationResult {
        ValidationResult(isValid: false, errors: [error])
    }
}

// MARK: - Plugin Lifecycle

/// Protocol for plugin lifecycle notifications
public protocol PluginLifecycleDelegate: AnyObject {
    func pluginDidLoad(_ plugin: GestureActionPlugin)
    func pluginWillUnload(_ plugin: GestureActionPlugin)
    func plugin(_ plugin: GestureActionPlugin, didFailWithError error: Error)
}

// MARK: - Plugin Logger Protocol

/// Protocol for plugin logging
public protocol PluginLogger {
    func log(_ message: String, file: String, function: String, line: Int)
    var isDebugEnabled: Bool { get }
}

// MARK: - Plugin Context

/// Context provided to plugins for accessing system features
public protocol PluginContext {
    /// Access to the gesture configuration
    var configuration: Configuration { get }
    
    /// Access to the logger
    var logger: PluginLogger { get }
    
    /// Register a notification observer
    func observeNotification(name: NSNotification.Name, handler: @escaping (Notification) -> Void) -> NSObjectProtocol
    
    /// Post a notification
    func postNotification(name: NSNotification.Name, userInfo: [String: Any]?)
    
    /// Get a preference value
    func preference(for key: String) -> Any?
    
    /// Set a preference value
    func setPreference(_ value: Any?, for key: String)
    
    /// Execute an action by its identifier
    func executeAction(identifier: String, parameters: ActionParameters) throws
    
    /// Show a user notification
    func showNotification(title: String, message: String, style: NotificationStyle)
    
    // MARK: - System Services (Sandboxed)
    
    /// Send a keyboard shortcut
    func sendKeyboardShortcut(keyCode: CGKeyCode, modifiers: CGEventFlags)
    
    /// Execute AppleScript
    func executeAppleScript(_ script: String) throws
    
    /// Get frontmost application
    func getFrontmostApplication() -> NSRunningApplication?
    
    /// Get all running applications
    func getRunningApplications() -> [NSRunningApplication]
    
    /// Terminate an application
    func terminateApplication(_ app: NSRunningApplication) -> Bool
    
    /// Hide an application
    func hideApplication(_ app: NSRunningApplication) -> Bool
    
    /// Get windows for application
    func getWindowsForApplication(_ pid: pid_t) -> [AXUIElement]
    
    /// Perform accessibility action on UI element
    func performAccessibilityAction(_ element: AXUIElement, action: String) -> Bool
    
    /// Set accessibility attribute value
    func setAccessibilityAttribute(_ element: AXUIElement, attribute: String, value: CFTypeRef) -> Bool
    
    /// Get accessibility attribute value
    func getAccessibilityAttribute(_ element: AXUIElement, attribute: String) -> CFTypeRef?
    
    /// Get target window based on targeting parameters
    func getTargetWindow(_ params: [String: Any]) -> (AXUIElement, pid_t)?
    
    /// Get target windows (supports multi-window targets like allWindowsOfApp/allWindows)
    func getTargetWindows(_ params: [String: Any]) -> [(AXUIElement, pid_t)]
    
    /// Get all visible windows
    func getAllVisibleWindows() -> [(window: AXUIElement, pid: pid_t)]
    
    /// Save data to plugin storage
    func saveData(_ data: Data, to filename: String) throws
    
    /// Load data from plugin storage
    func loadData(from filename: String) throws -> Data
    
    /// Check if file exists in plugin storage
    func fileExists(_ filename: String) -> Bool
    
    /// Delete file from plugin storage
    func deleteFile(_ filename: String) throws
    
    /// Release all currently held modifier keys (call before any synthetic key event that must arrive modifier-free)
    func releaseModifiers()
    
    /// Get list of saved profiles
    func getProfiles() -> [[String: Any]]
    
    /// Get active profile ID
    func getActiveProfileId() -> UUID?
    
    /// Apply a profile by ID
    func applyProfile(profileId: UUID)
    
    /// Save configuration
    func saveConfiguration()
}

/// Notification styles
public enum NotificationStyle {
    case info
    case success
    case warning
    case error
}

// MARK: - Plugin Error Types

public enum PluginError: LocalizedError {
    case initializationFailed(String)
    case actionNotFound(String)
    case invalidParameters(String)
    case executionFailed(String)
    case validationFailed(String)
    case configurationError(String)
    case dependencyMissing(String)
    case incompatibleVersion(String)
    
    public var errorDescription: String? {
        switch self {
        case .initializationFailed(let message):
            return "Plugin initialization failed: \(message)"
        case .actionNotFound(let action):
            return "Action not found: \(action)"
        case .invalidParameters(let message):
            return "Invalid parameters: \(message)"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .dependencyMissing(let dependency):
            return "Missing dependency: \(dependency)"
        case .incompatibleVersion(let message):
            return "Incompatible version: \(message)"
        }
    }
}

// MARK: - Plugin Metadata

/// Metadata for a plugin
public struct PluginMetadata: Codable {
    public let identifier: String
    public let name: String
    public let version: String
    public let author: String
    public let description: String
    public let website: String?
    public let minimumSystemVersion: String?
    public let maximumSystemVersion: String?
    public let dependencies: [String]?
    public let bundleIdentifier: String?
    public let mainClass: String?
    
    public init(
        identifier: String,
        name: String,
        version: String,
        author: String,
        description: String,
        website: String? = nil,
        minimumSystemVersion: String? = nil,
        maximumSystemVersion: String? = nil,
        dependencies: [String]? = nil,
        bundleIdentifier: String? = nil,
        mainClass: String? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.website = website
        self.minimumSystemVersion = minimumSystemVersion
        self.maximumSystemVersion = maximumSystemVersion
        self.dependencies = dependencies
        self.bundleIdentifier = bundleIdentifier
        self.mainClass = mainClass
    }
}
