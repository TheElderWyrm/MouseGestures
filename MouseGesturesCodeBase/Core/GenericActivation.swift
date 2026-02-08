import Foundation
import Cocoa
import Carbon

// MARK: - Generic Activation System (Plugin-Independent)

/// Generic activation configuration - no hard-coded plugin types
struct GenericActivation: Codable, Equatable {
    /// Enabled detection plugin IDs and their configuration data
    /// Key: plugin ID (e.g., "keyboard_detector", "mouse_button_detector")
    /// Value: plugin-specific configuration as generic dictionary
    var detectionConfigs: [String: [String: AnyCodable]]
    
    /// Whether activation is enabled
    var isEnabled: Bool
    
    init(detectionConfigs: [String: [String: AnyCodable]] = [:], isEnabled: Bool = true) {
        self.detectionConfigs = detectionConfigs
        self.isEnabled = isEnabled
    }
    
    // MARK: - Plugin Configuration Helpers
    
    /// Get configuration for a specific detection plugin
    func config(for pluginId: String) -> [String: AnyCodable]? {
        return detectionConfigs[pluginId]
    }
    
    /// Check if a detection plugin is configured
    func hasConfig(for pluginId: String) -> Bool {
        return detectionConfigs[pluginId] != nil
    }
    
    /// Set configuration for a detection plugin
    mutating func setConfig(_ config: [String: AnyCodable]?, for pluginId: String) {
        if let config = config {
            detectionConfigs[pluginId] = config
        } else {
            detectionConfigs.removeValue(forKey: pluginId)
        }
    }
    
    /// Get list of configured detection plugins
    var configuredPlugins: [String] {
        return Array(detectionConfigs.keys)
    }
    
    // MARK: - Backward Compatibility Helpers
    
    /// Get keyboard trigger from generic storage (for backward compatibility)
    var keyboardTrigger: KeyboardTrigger? {
        guard let config = detectionConfigs["keyboard_detector"] else { return nil }
        
        guard let keyCode = config["keyCode"]?.value as? Int,
              let modifiersRaw = config["modifiers"]?.value as? UInt,
              let displayString = config["displayString"]?.value as? String else {
            return nil
        }
        
        return KeyboardTrigger(
            keyCode: CGKeyCode(keyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: modifiersRaw),
            displayString: displayString
        )
    }
    
    /// Set keyboard trigger in generic storage
    mutating func setKeyboardTrigger(_ trigger: KeyboardTrigger?) {
        guard let trigger = trigger else {
            detectionConfigs.removeValue(forKey: "keyboard_detector")
            return
        }
        
        detectionConfigs["keyboard_detector"] = [
            "keyCode": AnyCodable(Int(trigger.keyCode)),
            "modifiers": AnyCodable(trigger.modifiers.rawValue),
            "displayString": AnyCodable(trigger.displayString)
        ]
    }
    
    /// Get mouse button trigger from generic storage (for backward compatibility)
    var mouseButtonTrigger: MouseButtonTrigger? {
        guard let config = detectionConfigs["mouse_button_detector"] else { return nil }
        
        guard let buttonRaw = config["button"]?.value as? String,
              let button = MouseButtonTrigger.MouseButton(rawValue: buttonRaw),
              let modifiersRaw = config["modifiers"]?.value as? UInt else {
            return nil
        }
        
        return MouseButtonTrigger(
            button: button,
            modifiers: NSEvent.ModifierFlags(rawValue: modifiersRaw)
        )
    }
    
    /// Set mouse button trigger in generic storage
    mutating func setMouseButtonTrigger(_ trigger: MouseButtonTrigger?) {
        guard let trigger = trigger else {
            detectionConfigs.removeValue(forKey: "mouse_button_detector")
            return
        }
        
        detectionConfigs["mouse_button_detector"] = [
            "button": AnyCodable(trigger.button.rawValue),
            "modifiers": AnyCodable(trigger.modifiers.rawValue),
            "displayString": AnyCodable(trigger.displayString)
        ]
    }
    
    // MARK: - Migration from ActivationSettings
    
    /// Create from legacy ActivationSettings
    init(from legacy: ActivationSettings) {
        var configs: [String: [String: AnyCodable]] = [:]
        
        // Migrate keyboard trigger
        if let kbd = legacy.keyboardTrigger {
            configs["keyboard_detector"] = [
                "keyCode": AnyCodable(Int(kbd.keyCode)),
                "modifiers": AnyCodable(kbd.modifiers.rawValue),
                "displayString": AnyCodable(kbd.displayString)
            ]
        }
        
        // Migrate mouse button trigger
        if let mouse = legacy.mouseButtonTrigger {
            configs["mouse_button_detector"] = [
                "button": AnyCodable(mouse.button.rawValue),
                "modifiers": AnyCodable(mouse.modifiers.rawValue),
                "displayString": AnyCodable(mouse.displayString)
            ]
        }
        
        self.detectionConfigs = configs
        self.isEnabled = legacy.isEnabled
    }
    
    /// Convert to legacy ActivationSettings
    func toLegacy() -> ActivationSettings {
        let hasKeyboard = detectionConfigs["keyboard_detector"] != nil
        let hasMouseButton = detectionConfigs["mouse_button_detector"] != nil
        let hasGesture = true // Always true for zone-based gestures
        
        let activationType: ActivationSettings.ActivationType
        switch (hasGesture, hasKeyboard, hasMouseButton) {
        case (true, false, false): activationType = .gesture
        case (false, true, false): activationType = .keyboard
        case (false, false, true): activationType = .mouseButton
        case (true, true, false): activationType = .both
        case (true, false, true): activationType = .gestureMouseButton
        case (false, true, true): activationType = .keyboardMouseButton
        case (true, true, true): activationType = .all
        default: activationType = .gesture
        }
        
        return ActivationSettings(
            activationType: activationType,
            keyboardTrigger: keyboardTrigger,
            mouseButtonTrigger: mouseButtonTrigger,
            isEnabled: isEnabled
        )
    }
}

// MARK: - Detection Plugin Configuration Protocols

/// Protocol for types that can be stored in generic activation
protocol DetectionPluginConfig: Codable {
    /// Serialize to generic dictionary
    func toGenericConfig() -> [String: AnyCodable]
    
    /// Deserialize from generic dictionary
    static func fromGenericConfig(_ config: [String: AnyCodable]) -> Self?
}

// Make existing trigger types conform
extension KeyboardTrigger: DetectionPluginConfig {
    func toGenericConfig() -> [String: AnyCodable] {
        return [
            "keyCode": AnyCodable(Int(keyCode)),
            "modifiers": AnyCodable(modifiers.rawValue),
            "displayString": AnyCodable(displayString)
        ]
    }
    
    static func fromGenericConfig(_ config: [String: AnyCodable]) -> KeyboardTrigger? {
        guard let keyCode = config["keyCode"]?.value as? Int,
              let modifiersRaw = config["modifiers"]?.value as? UInt,
              let displayString = config["displayString"]?.value as? String else {
            return nil
        }
        
        return KeyboardTrigger(
            keyCode: CGKeyCode(keyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: modifiersRaw),
            displayString: displayString
        )
    }
}

extension MouseButtonTrigger: DetectionPluginConfig {
    func toGenericConfig() -> [String: AnyCodable] {
        return [
            "button": AnyCodable(button.rawValue),
            "modifiers": AnyCodable(modifiers.rawValue),
            "displayString": AnyCodable(displayString)
        ]
    }
    
    static func fromGenericConfig(_ config: [String: AnyCodable]) -> MouseButtonTrigger? {
        guard let buttonRaw = config["button"]?.value as? String,
              let button = MouseButton(rawValue: buttonRaw),
              let modifiersRaw = config["modifiers"]?.value as? UInt else {
            return nil
        }
        
        return MouseButtonTrigger(
            button: button,
            modifiers: NSEvent.ModifierFlags(rawValue: modifiersRaw)
        )
    }
}
