import Foundation
import SwiftUI

// MARK: - Service Plugin Protocol
/// Protocol that all service plugins must conform to
public protocol ServicePlugin: AnyObject {
    /// Unique identifier for the service
    var identifier: String { get }
    
    /// Display name of the service
    var name: String { get }
    
    /// Description of what the service does
    var description: String { get }
    
    /// Category of the service
    var category: ServiceCategory { get }
    
    /// Version of the service plugin
    var version: String { get }
    
    /// Author of the service plugin
    var author: String { get }
    
    /// Whether this is a built-in service or external
    var isBuiltIn: Bool { get }
    
    /// Whether the service requires special permissions
    var requiredPermissions: ServicePermissions { get }
    
    /// Whether the service is currently enabled
    var isEnabled: Bool { get set }
    
    /// Initialize the service
    func initialize() throws
    
    /// Cleanup when service is being unloaded
    func cleanup()
    
    /// Get the service instance (singleton or new instance based on service type)
    func getServiceInstance() -> Any?
    
    /// Validate that the service can run in the current environment
    func validateEnvironment() -> ServiceValidationResult
    
    /// Get any configuration options for the service
    func getConfigurationOptions() -> [ServiceConfigOption]
    
    /// Apply configuration changes
    func applyConfiguration(_ config: [String: Any])
    
    /// Load configuration from persistent storage
    func loadConfiguration() -> [String: Any]?
    
    /// Save configuration to persistent storage
    func saveConfiguration(_ config: [String: Any])
}

// MARK: - Service Category
public enum ServiceCategory: String, CaseIterable, Codable {
    case system = "System"
    case ui = "UI"
    case data = "Data"
    case automation = "Automation"
    case developer = "Developer"
    case accessibility = "Accessibility"
    case profile = "Profile"
    case gesture = "Gesture"
    case plugin = "Plugin"
    case utility = "Utility"
    case monitoring = "Monitoring"
    case importExport = "Import/Export"
    
    var icon: String {
        switch self {
        case .system: return "gear"
        case .ui: return "uiwindow.split.2x1"
        case .data: return "externaldrive"
        case .automation: return "gearshape.2"
        case .developer: return "hammer"
        case .accessibility: return "accessibility"
        case .profile: return "person.crop.circle"
        case .gesture: return "hand.draw"
        case .plugin: return "puzzlepiece"
        case .utility: return "wrench"
        case .monitoring: return "chart.line.uptrend.xyaxis"
        case .importExport: return "arrow.up.arrow.down"
        }
    }
}

// MARK: - Service Permissions
public struct ServicePermissions: Codable, Equatable {
    public var requiresAccessibility: Bool = false
    public var requiresFileAccess: Bool = false
    public var requiresNetworkAccess: Bool = false
    public var requiresNotifications: Bool = false
    public var requiresScreenRecording: Bool = false
    public var requiresAutomation: Bool = false
    public var requiresFullDiskAccess: Bool = false
    
    public init(requiresAccessibility: Bool = false, requiresFileAccess: Bool = false,
                requiresNetworkAccess: Bool = false, requiresNotifications: Bool = false,
                requiresScreenRecording: Bool = false, requiresAutomation: Bool = false,
                requiresFullDiskAccess: Bool = false) {
        self.requiresAccessibility = requiresAccessibility
        self.requiresFileAccess = requiresFileAccess
        self.requiresNetworkAccess = requiresNetworkAccess
        self.requiresNotifications = requiresNotifications
        self.requiresScreenRecording = requiresScreenRecording
        self.requiresAutomation = requiresAutomation
        self.requiresFullDiskAccess = requiresFullDiskAccess
    }
    
    public static var none: ServicePermissions {
        return ServicePermissions()
    }
    
    public static var basic: ServicePermissions {
        return ServicePermissions(requiresFileAccess: true)
    }
    
    public static var accessibility: ServicePermissions {
        return ServicePermissions(requiresAccessibility: true)
    }
    
    public static var full: ServicePermissions {
        return ServicePermissions(
            requiresAccessibility: true,
            requiresFileAccess: true,
            requiresNetworkAccess: true,
            requiresNotifications: true,
            requiresScreenRecording: true,
            requiresAutomation: true,
            requiresFullDiskAccess: true
        )
    }
}

// MARK: - Service Validation Result
public struct ServiceValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
    
    static var success: ServiceValidationResult {
        return ServiceValidationResult(isValid: true, errors: [], warnings: [])
    }
    
    static func failure(_ error: String) -> ServiceValidationResult {
        return ServiceValidationResult(isValid: false, errors: [error], warnings: [])
    }
    
    static func warning(_ warning: String) -> ServiceValidationResult {
        return ServiceValidationResult(isValid: true, errors: [], warnings: [warning])
    }
}

// MARK: - Service Configuration Option
public struct ServiceConfigOption: Identifiable {
    public let id = UUID()
    let key: String
    let label: String
    let type: ConfigOptionType
    let defaultValue: Any?
    let description: String?
    let validation: ((Any) -> Bool)?
    
    public init(key: String, label: String, type: ConfigOptionType, defaultValue: Any? = nil, description: String? = nil, validation: ((Any) -> Bool)? = nil) {
        self.key = key
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.description = description
        self.validation = validation
    }
    
    public enum ConfigOptionType {
        case boolean
        case integer(min: Int?, max: Int?)
        case double(min: Double?, max: Double?)
        case string(maxLength: Int?)
        case selection(options: [String])
        case path(type: PathType)
        
        public enum PathType {
            case file
            case directory
        }
    }
}

// MARK: - Service Plugin Base Class
/// Base implementation for service plugins
open class BaseServicePlugin: ServicePlugin {
    public var identifier: String { fatalError("Must override") }
    public var name: String { fatalError("Must override") }
    public var description: String { fatalError("Must override") }
    public var category: ServiceCategory { .utility }
    public var version: String { "1.0.0" }
    public var author: String { "MouseGestures" }
    public var isBuiltIn: Bool { true }
    public var requiredPermissions: ServicePermissions { .none }
    public var isEnabled: Bool = true
    
    public init() {}
    
    open func initialize() throws {
        // Default implementation - override in subclasses
    }
    
    open func cleanup() {
        // Default implementation - override in subclasses
    }
    
    open func getServiceInstance() -> Any? {
        return nil
    }
    
    open func validateEnvironment() -> ServiceValidationResult {
        return .success
    }
    
    open func getConfigurationOptions() -> [ServiceConfigOption] {
        return []
    }
    
    open func applyConfiguration(_ config: [String: Any]) {
        // Default implementation - save to persistent storage
        saveConfiguration(config)
    }
    
    open func loadConfiguration() -> [String: Any]? {
        // Default implementation - load from Configuration storage
        guard let config = Configuration.shared.getPluginConfiguration(for: identifier),
              let dict = config.value as? [String: Any] else {
            return nil
        }
        return dict
    }
    
    open func saveConfiguration(_ config: [String: Any]) {
        // Default implementation - save to Configuration storage
        Configuration.shared.setPluginConfiguration(for: identifier, configuration: AnyCodable(config))
    }
}

// MARK: - Service Plugin Info
/// Information about a loaded service plugin
public struct ServicePluginInfo: Identifiable, Codable {
    public let id: UUID
    public let identifier: String
    public let name: String
    public let description: String
    public let category: ServiceCategory
    public let version: String
    public let author: String
    public let isBuiltIn: Bool
    public let isEnabled: Bool
    public let requiredPermissions: ServicePermissions
    
    private enum CodingKeys: String, CodingKey {
        case identifier, name, description, category, version, author, isBuiltIn, isEnabled, requiredPermissions
    }
    
    public init(from plugin: ServicePlugin) {
        self.id = UUID()
        self.identifier = plugin.identifier
        self.name = plugin.name
        self.description = plugin.description
        self.category = plugin.category
        self.version = plugin.version
        self.author = plugin.author
        self.isBuiltIn = plugin.isBuiltIn
        self.isEnabled = plugin.isEnabled
        self.requiredPermissions = plugin.requiredPermissions
    }
    
    public init(from decoder: Decoder) throws {
        self.id = UUID()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.identifier = try container.decode(String.self, forKey: .identifier)
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try container.decode(String.self, forKey: .description)
        self.category = try container.decode(ServiceCategory.self, forKey: .category)
        self.version = try container.decode(String.self, forKey: .version)
        self.author = try container.decode(String.self, forKey: .author)
        self.isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        self.isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        self.requiredPermissions = try container.decode(ServicePermissions.self, forKey: .requiredPermissions)
    }
}

// MARK: - Service Registration
/// Protocol for services that can be registered with the plugin system
public protocol RegisterableService {
    static var serviceIdentifier: String { get }
    static var shared: Self { get }
}

// MARK: - Simple Service Plugin
/// Generic service plugin that wraps a singleton service with zero custom logic.
/// Replaces dozens of boilerplate BaseServicePlugin subclasses.
public class SimpleServicePlugin<T>: BaseServicePlugin {
    private let _identifier: String
    private let _name: String
    private let _description: String
    private let _category: ServiceCategory
    private let _permissions: ServicePermissions
    private let factory: () -> T
    private var service: T?
    
    public init(id: String, name: String, description: String,
                category: ServiceCategory = .utility,
                permissions: ServicePermissions = .none,
                factory: @escaping () -> T) {
        self._identifier = id
        self._name = name
        self._description = description
        self._category = category
        self._permissions = permissions
        self.factory = factory
        super.init()
    }
    
    public override var identifier: String { _identifier }
    public override var name: String { _name }
    public override var description: String { _description }
    public override var category: ServiceCategory { _category }
    public override var requiredPermissions: ServicePermissions { _permissions }
    
    public override func initialize() throws {
        service = factory()
        log.log("\(_name): Initialized")
    }
    
    public override func cleanup() {
        service = nil
        log.log("\(_name): Cleaned up")
    }
    
    public override func getServiceInstance() -> Any? {
        return service
    }
}
