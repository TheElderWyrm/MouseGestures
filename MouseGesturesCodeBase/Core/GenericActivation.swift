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
    
    // MARK: - Keyboard Trigger Helpers
    
    var keyboardTrigger: KeyboardTrigger? {
        guard let config = detectionConfigs["keyboard_detector"],
              let keyCode = config["keyCode"]?.value as? Int,
              let modifiersRaw = config["modifiers"]?.value as? UInt,
              let displayString = config["displayString"]?.value as? String else { return nil }
        return KeyboardTrigger(
            keyCode: CGKeyCode(keyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: modifiersRaw),
            displayString: displayString
        )
    }
    
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
    
    // MARK: - Mouse Button Trigger Helpers
    
    var mouseButtonTrigger: MouseButtonTrigger? {
        guard let config = detectionConfigs["mouse_button_detector"],
              let buttonRaw = config["button"]?.value as? String,
              let button = MouseButtonTrigger.MouseButton(rawValue: buttonRaw),
              let modifiersRaw = config["modifiers"]?.value as? UInt else { return nil }
        return MouseButtonTrigger(
            button: button,
            modifiers: NSEvent.ModifierFlags(rawValue: modifiersRaw)
        )
    }
    
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
}

// MARK: - Detection Plugin Configuration Protocols

/// Protocol for types that can be stored in generic activation
protocol DetectionPluginConfig: Codable {
    func toGenericConfig() -> [String: AnyCodable]
    static func fromGenericConfig(_ config: [String: AnyCodable]) -> Self?
}

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
              let displayString = config["displayString"]?.value as? String else { return nil }
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
              let modifiersRaw = config["modifiers"]?.value as? UInt else { return nil }
        return MouseButtonTrigger(
            button: button,
            modifiers: NSEvent.ModifierFlags(rawValue: modifiersRaw)
        )
    }
}
