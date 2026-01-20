import Foundation
import Cocoa

// MARK: - Detection Plugin Protocol

/// Protocol that all detection plugins must conform to
protocol DetectionPlugin: AnyObject, PluginSettingsProvider {
    /// Unique identifier for the plugin
    var identifier: String { get }
    
    /// Display name of the plugin
    var name: String { get }
    
    /// Description of what the plugin detects
    var description: String { get }
    
    /// Version of the plugin
    var version: String { get }
    
    /// Whether the plugin is currently enabled
    var isEnabled: Bool { get set }
    
    /// Priority for plugin execution (higher = earlier)
    var priority: Int { get }
    
    /// Plugin dependencies (identifiers of plugins this one depends on)
    var dependencies: [String] { get }
    
    /// Initialize the plugin with context
    func initialize(context: DetectionContext) throws
    
    /// Start detection
    func start() throws
    
    /// Stop detection
    func stop()
    
    /// Clean up resources
    func cleanup()
    
    /// Configuration view for the plugin (for per-gesture trigger configuration)
    func configurationView() -> NSView?
    
    /// Handle global configuration changes (gestures, profiles, etc.)
    func configurationChanged()
    
    /// Get plugin statistics
    func getStatistics() -> DetectionPluginStatistics
}

// MARK: - Detection Context

/// Context provided to detection plugins
class DetectionContext {
    /// Delegate for triggering gestures
    weak var delegate: DetectionPluginDelegate?
    
    /// Logger for the plugin
    let logger: PluginLogger
    
    /// Configuration access
    let configuration: ConfigurationAccess
    
    /// Access to other detection plugins
    weak var pluginManager: DetectionPluginManager?
    
    /// Plugin-specific storage directory
    let storageDirectory: URL
    
    init(delegate: DetectionPluginDelegate?,
         logger: PluginLogger,
         configuration: ConfigurationAccess,
         pluginManager: DetectionPluginManager?,
         storageDirectory: URL) {
        self.delegate = delegate
        self.logger = logger
        self.configuration = configuration
        self.pluginManager = pluginManager
        self.storageDirectory = storageDirectory
    }
}

// MARK: - Detection Plugin Delegate

/// Delegate protocol for detection plugins to report events
protocol DetectionPluginDelegate: AnyObject {
    /// Called when a gesture is detected
    func detectionPlugin(_ plugin: DetectionPlugin, didDetectGesture gesture: Gesture, context: GestureContext)
    
    /// Called when a profile switch is triggered
    func detectionPlugin(_ plugin: DetectionPlugin, didTriggerProfileSwitch profile: ConfigurationProfile)
    
    /// Called when plugin state changes
    func detectionPlugin(_ plugin: DetectionPlugin, stateChanged state: DetectionPluginState)
    
    /// Called when plugin encounters an error
    func detectionPlugin(_ plugin: DetectionPlugin, didEncounterError error: Error)
    
    /// Query if detection should continue
    func detectionPluginShouldContinue(_ plugin: DetectionPlugin) -> Bool
}

// MARK: - Gesture Context

/// Context information about how a gesture was triggered
struct GestureContext {
    /// Source of the gesture trigger
    enum TriggerSource {
        case screenZone(zone: ScreenZone, dragState: DragModifier)
        case keyboard(trigger: KeyboardTrigger)
        case mouseButton(button: MouseButtonTrigger.MouseButton, modifiers: NSEvent.ModifierFlags)
        case `repeat`
        case custom(String)
    }
    
    /// The source that triggered this gesture
    let source: TriggerSource
    
    /// Current modifier keys pressed
    let modifiers: NSEvent.ModifierFlags
    
    /// Timestamp of the trigger
    let timestamp: Date
    
    /// Additional metadata
    let metadata: [String: Any]
    
    init(source: TriggerSource,
                modifiers: NSEvent.ModifierFlags = [],
                timestamp: Date = Date(),
                metadata: [String: Any] = [:]) {
        self.source = source
        self.modifiers = modifiers
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

// MARK: - Detection Plugin State

/// State of a detection plugin
enum DetectionPluginState: Equatable {
    case uninitialized
    case initialized
    case starting
    case running
    case stopping
    case stopped
    case error(Error)
    
    static func == (lhs: DetectionPluginState, rhs: DetectionPluginState) -> Bool {
        switch (lhs, rhs) {
        case (.uninitialized, .uninitialized),
             (.initialized, .initialized),
             (.starting, .starting),
             (.running, .running),
             (.stopping, .stopping),
             (.stopped, .stopped):
            return true
        case (.error(_), .error(_)):
            // Consider all error states equal for simplicity
            return true
        default:
            return false
        }
    }
}

// MARK: - Detection Plugin Statistics

/// Statistics for a detection plugin
struct DetectionPluginStatistics {
    /// Number of events detected
    let eventsDetected: Int
    
    /// Number of gestures triggered
    let gesturesTriggered: Int
    
    /// Number of errors encountered
    let errorsEncountered: Int
    
    /// Time since last event
    let timeSinceLastEvent: TimeInterval?
    
    /// CPU usage percentage
    let cpuUsage: Double
    
    /// Memory usage in bytes
    let memoryUsage: Int
    
    /// Custom statistics
    let customStats: [String: Any]
    
    init(eventsDetected: Int = 0,
                gesturesTriggered: Int = 0,
                errorsEncountered: Int = 0,
                timeSinceLastEvent: TimeInterval? = nil,
                cpuUsage: Double = 0,
                memoryUsage: Int = 0,
                customStats: [String: Any] = [:]) {
        self.eventsDetected = eventsDetected
        self.gesturesTriggered = gesturesTriggered
        self.errorsEncountered = errorsEncountered
        self.timeSinceLastEvent = timeSinceLastEvent
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.customStats = customStats
    }
}

// MARK: - Configuration Access

/// Protocol for accessing configuration
protocol ConfigurationAccess {
    /// Get current gestures
    var gestures: [Gesture] { get }
    
    /// Get current profiles
    var profiles: [ConfigurationProfile] { get }
    
    /// Get active profile ID
    var activeProfileId: String? { get }
    
    /// Get edge threshold
    var edgeThreshold: CGFloat { get }
    
    /// Get corner size
    var cornerSize: CGFloat { get }
    
    /// Get corner buffer
    var cornerBuffer: CGFloat { get }
    
    /// Check if haptic feedback is enabled
    var hapticFeedbackEnabled: Bool { get }
    
    /// Check if gestures are enabled globally
    var isEnabled: Bool { get }
    
    /// Get app-specific configuration
    func getAppConfiguration(bundleId: String) -> AppConfiguration?
    
    /// Check if app is disabled
    func isAppDisabled(bundleId: String) -> Bool
}



// MARK: - Base Detection Plugin

/// Base class for detection plugins with common functionality
open class BaseDetectionPlugin: NSObject, DetectionPlugin, PluginSettingsDelegate {
    // MARK: - Properties
    
    open var identifier: String { 
        fatalError("Subclasses must override identifier") 
    }
    
    open var name: String { 
        fatalError("Subclasses must override name") 
    }
    
    open override var description: String { 
        fatalError("Subclasses must override description") 
    }
    
    open var version: String { "1.0.0" }
    
    var isEnabled: Bool = true
    
    open var priority: Int { 100 }
    
    /// Plugin dependencies - override in subclasses if needed
    open var dependencies: [String] { [] }
    
    internal var context: DetectionContext?
    internal var state: DetectionPluginState = .uninitialized
    internal var statistics = DetectionPluginStatistics()
    
    // MARK: - Settings
    
    /// Override in subclasses to provide setting definitions
    open var settingsDefinitions: [PluginSettingDefinition] { [] }
    
    /// Settings storage - lazily initialized
    private var _settings: PluginSettings?
    public var settings: PluginSettings {
        if _settings == nil {
            _settings = PluginSettings(pluginId: identifier, definitions: settingsDefinitions, delegate: self)
        }
        return _settings!
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
    }
    
    // MARK: - DetectionPlugin Protocol
    
    func initialize(context: DetectionContext) throws {
        self.context = context
        state = .initialized
        context.logger.log("\(name) initialized", file: #file, function: #function, line: #line)
    }
    
    func start() throws {
        guard state == .initialized || state == .stopped else {
            throw DetectionPluginError.invalidState("Cannot start from state: \(state)")
        }
        
        state = .starting
        context?.logger.log("\(name) starting...", file: #file, function: #function, line: #line)
        
        // Subclasses override to add specific start logic
        
        state = .running
        context?.logger.log("\(name) started", file: #file, function: #function, line: #line)
        context?.delegate?.detectionPlugin(self, stateChanged: state)
    }
    
    func stop() {
        guard state == .running else { return }
        
        state = .stopping
        context?.logger.log("\(name) stopping...", file: #file, function: #function, line: #line)
        
        // Subclasses override to add specific stop logic
        
        state = .stopped
        context?.logger.log("\(name) stopped", file: #file, function: #function, line: #line)
        context?.delegate?.detectionPlugin(self, stateChanged: state)
    }
    
    func cleanup() {
        stop()
        context = nil
        state = .uninitialized
    }
    
    func configurationView() -> NSView? {
        // Subclasses can override to provide configuration UI
        return nil
    }
    
    func configurationChanged() {
        // Subclasses override to handle configuration changes
        context?.logger.log("\(name) configuration changed", file: #file, function: #function, line: #line)
    }
    
    func getStatistics() -> DetectionPluginStatistics {
        return statistics
    }
    
    // MARK: - Helper Methods
    
    /// Trigger a gesture detection
    internal func triggerGesture(_ gesture: Gesture, context: GestureContext) {
        self.context?.delegate?.detectionPlugin(self, didDetectGesture: gesture, context: context)
    }
    
    /// Trigger a profile switch
    internal func triggerProfileSwitch(_ profile: ConfigurationProfile) {
        self.context?.delegate?.detectionPlugin(self, didTriggerProfileSwitch: profile)
    }
    
    /// Report an error
    internal func reportError(_ error: Error) {
        state = .error(error)
        context?.logger.log("Error in \(name): \(error)", file: #file, function: #function, line: #line)
        context?.delegate?.detectionPlugin(self, didEncounterError: error)
    }
    
    /// Check if detection should continue
    internal func shouldContinue() -> Bool {
        return context?.delegate?.detectionPluginShouldContinue(self) ?? false
    }
    
    // MARK: - PluginSettingsDelegate
    
    public func pluginSettings(_ settings: PluginSettings, didChangeValue value: Any, forKey key: String, oldValue: Any?) {
        // Forward to the settingChanged method that subclasses can override
        settingChanged(key, value: value, oldValue: oldValue)
    }
    
    // MARK: - PluginSettingsProvider
    
    /// Override in subclasses to react to setting changes
    open func settingChanged(_ key: String, value: Any, oldValue: Any?) {
        context?.logger.log("\(name) setting changed: \(key)", file: #file, function: #function, line: #line)
    }
}

// MARK: - Detection Plugin Error

/// Errors that can occur in detection plugins
enum DetectionPluginError: LocalizedError {
    case invalidState(String)
    case initializationFailed(String)
    case startFailed(String)
    case configurationError(String)
    case resourceUnavailable(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidState(let message):
            return "Invalid plugin state: \(message)"
        case .initializationFailed(let message):
            return "Plugin initialization failed: \(message)"
        case .startFailed(let message):
            return "Plugin start failed: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .resourceUnavailable(let message):
            return "Resource unavailable: \(message)"
        }
    }
}
