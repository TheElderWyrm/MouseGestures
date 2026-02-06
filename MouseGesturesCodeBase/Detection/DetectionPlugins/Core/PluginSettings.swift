import Foundation
import Cocoa

// MARK: - Plugin Setting Definition

/// Defines a single setting that a detection plugin requires
public struct PluginSettingDefinition {
    public let key: String
    public let displayName: String
    public let description: String?
    public let category: SettingCategory
    public let type: SettingType
    public let defaultValue: Any
    public let isAdvanced: Bool
    public let dependsOn: SettingDependency?
    public let validation: SettingValidation?
    
    // MARK: - Setting Category
    
    public enum SettingCategory: String, Codable, CaseIterable {
        case general
        case detection
        case appearance
        case performance
        case advanced
        
        public var displayName: String {
            switch self {
            case .general: return "General"
            case .detection: return "Detection"
            case .appearance: return "Appearance"
            case .performance: return "Performance"
            case .advanced: return "Advanced"
            }
        }
        
        public var sortOrder: Int {
            switch self {
            case .general: return 0
            case .detection: return 1
            case .appearance: return 2
            case .performance: return 3
            case .advanced: return 4
            }
        }
        
        public var icon: String {
            switch self {
            case .general: return "gearshape"
            case .detection: return "hand.tap"
            case .appearance: return "paintbrush"
            case .performance: return "speedometer"
            case .advanced: return "wrench.and.screwdriver"
            }
        }
    }
    
    // MARK: - Setting Type
    
    public enum SettingType {
        case toggle(label: String)
        case slider(min: Double, max: Double, step: Double, unit: String?)
        case stepper(min: Int, max: Int, step: Int)
        case picker(options: [PickerOption])
        case segmentedPicker(options: [PickerOption])
        case color
        case keyboardShortcut
        case text(placeholder: String?, maxLength: Int?)
        case textArea(rows: Int)
        case path(fileTypes: [String]?, isDirectory: Bool)
        case button(title: String, style: ButtonStyle, action: () -> Void)
        case info(text: String) // Read-only informational text
        case custom(viewBuilder: () -> NSView)
        
        public enum ButtonStyle {
            case normal
            case destructive
            case primary
        }
    }
    
    public struct PickerOption: Equatable {
        public let value: String
        public let displayName: String
        public let icon: NSImage?
        
        public init(value: String, displayName: String, icon: NSImage? = nil) {
            self.value = value
            self.displayName = displayName
            self.icon = icon
        }
        
        public static func == (lhs: PickerOption, rhs: PickerOption) -> Bool {
            return lhs.value == rhs.value && lhs.displayName == rhs.displayName
        }
    }
    
    // MARK: - Setting Dependency
    
    public struct SettingDependency {
        public let key: String
        public let condition: Condition
        
        public enum Condition {
            case equals(Any)
            case notEquals(Any)
            case greaterThan(Double)
            case lessThan(Double)
            case isTrue
            case isFalse
            case isEmpty
            case isNotEmpty
        }
        
        public init(key: String, condition: Condition) {
            self.key = key
            self.condition = condition
        }
        
        public func isSatisfied(by value: Any?) -> Bool {
            switch condition {
            case .isTrue:
                return (value as? Bool) == true
            case .isFalse:
                return (value as? Bool) == false
            case .equals(let expected):
                return areEqual(value, expected)
            case .notEquals(let expected):
                return !areEqual(value, expected)
            case .greaterThan(let threshold):
                return (value as? Double ?? (value as? CGFloat).map { Double($0) } ?? 0) > threshold
            case .lessThan(let threshold):
                return (value as? Double ?? (value as? CGFloat).map { Double($0) } ?? 0) < threshold
            case .isEmpty:
                if let str = value as? String { return str.isEmpty }
                if let arr = value as? [Any] { return arr.isEmpty }
                return value == nil
            case .isNotEmpty:
                if let str = value as? String { return !str.isEmpty }
                if let arr = value as? [Any] { return !arr.isEmpty }
                return value != nil
            }
        }
        
        private func areEqual(_ lhs: Any?, _ rhs: Any) -> Bool {
            if let l = lhs as? String, let r = rhs as? String { return l == r }
            if let l = lhs as? Int, let r = rhs as? Int { return l == r }
            if let l = lhs as? Double, let r = rhs as? Double { return l == r }
            if let l = lhs as? Bool, let r = rhs as? Bool { return l == r }
            return "\(lhs ?? "nil")" == "\(rhs)"
        }
    }
    
    // MARK: - Setting Validation
    
    public struct SettingValidation {
        public let rule: ValidationRule
        public let errorMessage: String
        
        public enum ValidationRule {
            case range(min: Double, max: Double)
            case intRange(min: Int, max: Int)
            case notEmpty
            case regex(String)
            case maxLength(Int)
            case custom((Any) -> Bool)
        }
        
        public init(rule: ValidationRule, errorMessage: String) {
            self.rule = rule
            self.errorMessage = errorMessage
        }
        
        public func validate(_ value: Any) -> Bool {
            switch rule {
            case .range(let min, let max):
                guard let num = value as? Double ?? (value as? CGFloat).map({ Double($0) }) else { return false }
                return num >= min && num <= max
            case .intRange(let min, let max):
                guard let num = value as? Int else { return false }
                return num >= min && num <= max
            case .notEmpty:
                if let str = value as? String { return !str.isEmpty }
                return true
            case .regex(let pattern):
                guard let str = value as? String else { return false }
                return str.range(of: pattern, options: .regularExpression) != nil
            case .maxLength(let max):
                guard let str = value as? String else { return true }
                return str.count <= max
            case .custom(let validator):
                return validator(value)
            }
        }
    }
    
    // MARK: - Convenience Initializers
    
    public init(
        key: String,
        displayName: String,
        description: String? = nil,
        category: SettingCategory = .general,
        type: SettingType,
        defaultValue: Any,
        isAdvanced: Bool = false,
        dependsOn: SettingDependency? = nil,
        validation: SettingValidation? = nil
    ) {
        self.key = key
        self.displayName = displayName
        self.description = description
        self.category = category
        self.type = type
        self.defaultValue = defaultValue
        self.isAdvanced = isAdvanced
        self.dependsOn = dependsOn
        self.validation = validation
    }
}

// MARK: - Plugin Settings Storage

/// Manages settings values for a single plugin
public class PluginSettings {
    private let pluginId: String
    private var values: [String: Any] = [:]
    private let definitions: [PluginSettingDefinition]
    private weak var delegate: PluginSettingsDelegate?
    
    public init(pluginId: String, definitions: [PluginSettingDefinition], delegate: PluginSettingsDelegate? = nil) {
        self.pluginId = pluginId
        self.definitions = definitions
        self.delegate = delegate
        
        // Initialize with default values
        for def in definitions {
            values[def.key] = def.defaultValue
        }
    }
    
    // MARK: - Value Access
    
    public func get<T>(_ key: String) -> T? {
        return values[key] as? T
    }
    
    public func get<T>(_ key: String, default defaultValue: T) -> T {
        return values[key] as? T ?? defaultValue
    }
    
    public func set(_ key: String, value: Any, notify: Bool = true) {
        let oldValue = values[key]
        values[key] = value
        
        if notify {
            delegate?.pluginSettings(self, didChangeValue: value, forKey: key, oldValue: oldValue)
        }
    }
    
    // MARK: - Typed Accessors
    
    public func getBool(_ key: String, default defaultValue: Bool = false) -> Bool {
        return get(key, default: defaultValue)
    }
    
    public func getInt(_ key: String, default defaultValue: Int = 0) -> Int {
        return get(key, default: defaultValue)
    }
    
    public func getDouble(_ key: String, default defaultValue: Double = 0.0) -> Double {
        // Handle CGFloat stored as Double
        if let cgFloat = values[key] as? CGFloat {
            return Double(cgFloat)
        }
        return get(key, default: defaultValue)
    }
    
    public func getCGFloat(_ key: String, default defaultValue: CGFloat = 0.0) -> CGFloat {
        if let double = values[key] as? Double {
            return CGFloat(double)
        }
        return get(key, default: defaultValue)
    }
    
    public func getString(_ key: String, default defaultValue: String = "") -> String {
        return get(key, default: defaultValue)
    }
    
    public func getColor(_ key: String, default defaultValue: NSColor = .white) -> NSColor {
        // Handle color stored as data (for persistence)
        if let data = values[key] as? Data {
            return (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)) ?? defaultValue
        }
        return get(key, default: defaultValue)
    }
    
    // MARK: - Subscript Access
    
    public subscript<T>(key: String, default defaultValue: T) -> T {
        get { get(key, default: defaultValue) }
        set { set(key, value: newValue) }
    }
    
    // MARK: - Validation
    
    public func validate(_ key: String, value: Any) -> (isValid: Bool, errorMessage: String?) {
        guard let definition = definitions.first(where: { $0.key == key }),
              let validation = definition.validation else {
            return (true, nil)
        }
        
        let isValid = validation.validate(value)
        return (isValid, isValid ? nil : validation.errorMessage)
    }
    
    public func validateAll() -> [(key: String, errorMessage: String)] {
        var errors: [(String, String)] = []
        for def in definitions {
            if let validation = def.validation {
                let value = values[def.key] ?? def.defaultValue
                if !validation.validate(value) {
                    errors.append((def.key, validation.errorMessage))
                }
            }
        }
        return errors
    }
    
    // MARK: - Dependency Checking
    
    public func isSettingVisible(_ key: String) -> Bool {
        guard let definition = definitions.first(where: { $0.key == key }),
              let dependency = definition.dependsOn else {
            return true
        }
        
        let dependencyValue = values[dependency.key]
        return dependency.isSatisfied(by: dependencyValue)
    }
    
    // MARK: - Serialization
    
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]
        for (key, value) in values {
            // Convert NSColor to Data for persistence
            if let color = value as? NSColor {
                if let data = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false) {
                    dict[key] = data
                }
            } else {
                dict[key] = value
            }
        }
        return dict
    }
    
    public func load(from dictionary: [String: Any]) {
        for (key, value) in dictionary {
            values[key] = value
        }
    }
    
    // MARK: - Reset
    
    public func resetToDefaults() {
        for def in definitions {
            set(def.key, value: def.defaultValue)
        }
    }
    
    public func resetToDefault(_ key: String) {
        if let def = definitions.first(where: { $0.key == key }) {
            set(key, value: def.defaultValue)
        }
    }
}

// MARK: - Plugin Settings Delegate

public protocol PluginSettingsDelegate: AnyObject {
    func pluginSettings(_ settings: PluginSettings, didChangeValue value: Any, forKey key: String, oldValue: Any?)
}

// MARK: - Plugin Settings Provider Protocol

/// Protocol for plugins that provide settings
public protocol PluginSettingsProvider {
    /// All setting definitions for this plugin
    var settingsDefinitions: [PluginSettingDefinition] { get }
    
    /// Current settings instance
    var settings: PluginSettings { get }
    
    /// Called when a setting value changes
    func settingChanged(_ key: String, value: Any, oldValue: Any?)
}

// MARK: - Default Implementation

public extension PluginSettingsProvider {
    func settingChanged(_ key: String, value: Any, oldValue: Any?) {
        // Default: do nothing. Plugins override to react to changes.
    }
}
