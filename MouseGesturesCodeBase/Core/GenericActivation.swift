import Foundation
import Cocoa
import Carbon

/// Coerce a stored modifier value back to an `NSEvent.ModifierFlags` rawValue.
/// Modifier flags are persisted inside `AnyCodable`, which round-trips every
/// JSON number as `Int` — and older builds stored the raw `UInt`, which
/// AnyCodable's encoder has no case for and silently writes as `null`. Reading
/// with a bare `as? UInt` therefore returned nil after any save/reload, which
/// dropped the whole keyboard/mouse-button trigger (and with it the gesture) on
/// the next launch. Accept Int/UInt/NSNumber so the flags survive the round-trip.
fileprivate func decodeModifierRaw(_ value: Any?) -> UInt? {
    if let u = value as? UInt { return u }
    if let i = value as? Int { return UInt(bitPattern: i) }
    if let n = value as? NSNumber { return n.uintValue }
    return nil
}

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
              let modifiersRaw = decodeModifierRaw(config["modifiers"]?.value),
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
            // Store the rawValue as Int: AnyCodable can encode Int (it has no
            // UInt case and would otherwise drop it to null). See decodeModifierRaw.
            "modifiers": AnyCodable(Int(trigger.modifiers.rawValue)),
            "displayString": AnyCodable(trigger.displayString)
        ]
    }

    // MARK: - Mouse Button Trigger Helpers

    var mouseButtonTrigger: MouseButtonTrigger? {
        guard let config = detectionConfigs["mouse_button_detector"],
              let buttonRaw = config["button"]?.value as? String,
              let button = MouseButtonTrigger.MouseButton(rawValue: buttonRaw),
              let modifiersRaw = decodeModifierRaw(config["modifiers"]?.value) else { return nil }
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
            // Store as Int (AnyCodable has no UInt case → null). See decodeModifierRaw.
            "modifiers": AnyCodable(Int(trigger.modifiers.rawValue)),
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
            "modifiers": AnyCodable(Int(modifiers.rawValue)),
            "displayString": AnyCodable(displayString)
        ]
    }

    static func fromGenericConfig(_ config: [String: AnyCodable]) -> KeyboardTrigger? {
        guard let keyCode = config["keyCode"]?.value as? Int,
              let modifiersRaw = decodeModifierRaw(config["modifiers"]?.value),
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
            "modifiers": AnyCodable(Int(modifiers.rawValue)),
            "displayString": AnyCodable(displayString)
        ]
    }

    static func fromGenericConfig(_ config: [String: AnyCodable]) -> MouseButtonTrigger? {
        guard let buttonRaw = config["button"]?.value as? String,
              let button = MouseButton(rawValue: buttonRaw),
              let modifiersRaw = decodeModifierRaw(config["modifiers"]?.value) else { return nil }
        return MouseButtonTrigger(
            button: button,
            modifiers: NSEvent.ModifierFlags(rawValue: modifiersRaw)
        )
    }
}
