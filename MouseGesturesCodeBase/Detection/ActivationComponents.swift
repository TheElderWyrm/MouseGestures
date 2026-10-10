import Foundation
import SwiftUI
import AppKit

// MARK: - Activation Component System

/// Configuration for a single activation component
protocol ActivationComponentConfig: Codable, Equatable {
    var isEnabled: Bool { get set }
    var displayValue: String { get } // For preview/display
}

/// Metadata describing what UI a component needs
struct ActivationComponentUIMetadata {
    let type: ActivationType
    let displayName: String
    let icon: String
    let description: String
    let uiFields: [UIField]

    enum UIField {
        case modifierKeys
        case screenZone
        case dragType
        case mouseButton
        case keyboardShortcut
    }
}

// MARK: - Concrete Component Configurations

struct ModifierKeyConfig: ActivationComponentConfig {
    var isEnabled: Bool = false
    var modifiers: NSEvent.ModifierFlags = []

    var displayValue: String {
        guard isEnabled else { return "Not configured" }
        let symbols = modifiers.symbolString
        return symbols.isEmpty ? "No modifiers" : symbols
    }
}

/// A trigger declared by an external detection plugin (see ExternalTriggerAPI.swift).
struct ExternalTriggerConfig: ActivationComponentConfig {
    var isEnabled: Bool = false
    var pluginId: String = ""
    var triggerId: String = ""
    var displayName: String = ""
    /// Per-gesture overrides of the trigger's options; a missing key means the plugin's own setting.
    var options: [String: AnyCodable]? = nil

    var displayValue: String {
        guard isEnabled else { return "Not configured" }
        return displayName.isEmpty ? triggerId : displayName
    }
}

struct ScreenZoneConfig: ActivationComponentConfig {
    var isEnabled: Bool = false
    var zone: ScreenZone = .topRight

    var displayValue: String {
        guard isEnabled else { return "Not configured" }
        return zone.displayName
    }
}

struct DragTypeConfig: ActivationComponentConfig {
    var isEnabled: Bool = false
    var dragType: DragModifier = .none
    /// When true the gesture fires on click-in-zone **and** drag-into-zone (combined mode).
    var allowClick: Bool = false

    var displayValue: String {
        guard isEnabled else { return "Not configured" }
        if allowClick {
            return dragType.displayName.replacingOccurrences(of: " Drag", with: " Click/Drag")
        }
        return dragType.displayName
    }

    // Custom Codable so old saved gestures without `allowClick` decode correctly.
    enum CodingKeys: String, CodingKey { case isEnabled, dragType, allowClick }

    init(isEnabled: Bool = false, dragType: DragModifier = .none, allowClick: Bool = false) {
        self.isEnabled = isEnabled
        self.dragType = dragType
        self.allowClick = allowClick
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled  = try c.decode(Bool.self, forKey: .isEnabled)
        dragType   = try c.decode(DragModifier.self, forKey: .dragType)
        allowClick = try c.decodeIfPresent(Bool.self, forKey: .allowClick) ?? false
    }
}

struct MouseButtonConfig: ActivationComponentConfig {
    var isEnabled: Bool = false
    var button: MouseButtonTrigger.MouseButton = .none

    var displayValue: String {
        guard isEnabled else { return "Not configured" }
        return button.rawValue
    }
}

struct KeyboardShortcutConfig: ActivationComponentConfig {
    var isEnabled: Bool = false
    var keyboardTrigger: KeyboardTrigger?

    var displayValue: String {
        guard isEnabled else { return "Not configured" }
        return keyboardTrigger?.displayString ?? "Not set"
    }
}

// MARK: - Gesture Component Storage

/// Stores all activation component configurations for a gesture
struct GestureActivationComponents: Codable, Equatable {
    var modifierKey: ModifierKeyConfig? = nil
    var screenZone: ScreenZoneConfig? = nil
    var dragType: DragTypeConfig? = nil
    var mouseButton: MouseButtonConfig? = nil
    var keyboardShortcut: KeyboardShortcutConfig? = nil
    /// Plugin triggers (shake, schedule…). Any one of them fires the gesture; they may come from different plugins.
    var externalTriggers: [ExternalTriggerConfig] = []
    /// When true, the gesture will NOT fire if any mouse button is currently pressed
    var requireNoMouse: Bool = false

    /// Default initializer
    init() {}

    private enum CodingKeys: String, CodingKey {
        case modifierKey, screenZone, dragType, mouseButton, keyboardShortcut, externalTriggers, requireNoMouse
        case legacyExternalTrigger = "externalTrigger"      // before a gesture could hold several
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modifierKey = try c.decodeIfPresent(ModifierKeyConfig.self, forKey: .modifierKey)
        screenZone = try c.decodeIfPresent(ScreenZoneConfig.self, forKey: .screenZone)
        dragType = try c.decodeIfPresent(DragTypeConfig.self, forKey: .dragType)
        mouseButton = try c.decodeIfPresent(MouseButtonConfig.self, forKey: .mouseButton)
        keyboardShortcut = try c.decodeIfPresent(KeyboardShortcutConfig.self, forKey: .keyboardShortcut)
        requireNoMouse = try c.decodeIfPresent(Bool.self, forKey: .requireNoMouse) ?? false
        if let many = try c.decodeIfPresent([ExternalTriggerConfig].self, forKey: .externalTriggers) {
            externalTriggers = many
        } else if let one = try c.decodeIfPresent(ExternalTriggerConfig.self, forKey: .legacyExternalTrigger) {
            externalTriggers = [one]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(modifierKey, forKey: .modifierKey)
        try c.encodeIfPresent(screenZone, forKey: .screenZone)
        try c.encodeIfPresent(dragType, forKey: .dragType)
        try c.encodeIfPresent(mouseButton, forKey: .mouseButton)
        try c.encodeIfPresent(keyboardShortcut, forKey: .keyboardShortcut)
        if !externalTriggers.isEmpty { try c.encode(externalTriggers, forKey: .externalTriggers) }
        try c.encode(requireNoMouse, forKey: .requireNoMouse)
    }

    /// The enabled plugin triggers.
    var activeExternalTriggers: [ExternalTriggerConfig] { externalTriggers.filter { $0.isEnabled } }

    /// Get all enabled activation types
    var enabledTypes: Set<ActivationType> {
        var types = Set<ActivationType>()
        if modifierKey?.isEnabled == true { types.insert(.modifierKey) }
        if screenZone?.isEnabled == true { types.insert(.screenZone) }
        if dragType?.isEnabled == true && dragType?.dragType != DragModifier.none {
            types.insert(.mouseButton) // Drag requires button hold
        }
        if mouseButton?.isEnabled == true && mouseButton?.button != MouseButtonTrigger.MouseButton.none {
            types.insert(.mouseButton)
        }
        if keyboardShortcut?.isEnabled == true && keyboardShortcut?.keyboardTrigger != nil {
            types.insert(.keyboardShortcut)
        }
        return types
    }

    /// Check if gesture is valid (has at least one enabled component)
    var isValid: Bool {
        return !enabledTypes.isEmpty || requireNoMouse || !activeExternalTriggers.isEmpty
    }

    /// All registered components as (label, config) pairs in display order
    var allComponents: [(label: String, config: any ActivationComponentConfig)] {
        var result: [(String, any ActivationComponentConfig)] = []
        if let c = screenZone { result.append(("Zone", c)) }
        if let c = modifierKey { result.append(("Modifiers", c)) }
        if let c = dragType { result.append(("Drag", c)) }
        if let c = mouseButton { result.append(("Mouse Button", c)) }
        if let c = keyboardShortcut { result.append(("Keyboard", c)) }
        for c in externalTriggers { result.append(("Plugin", c)) }
        return result
    }

    /// Only enabled components with their labels and display values
    var enabledComponentDetails: [(label: String, value: String)] {
        return allComponents
            .filter { $0.config.isEnabled }
            .map { (label: $0.label, value: $0.config.displayValue) }
    }

    /// Get display preview of all enabled components
    var previewString: String {
        let parts = enabledComponentDetails.map { $0.value }
        return parts.isEmpty ? "No triggers configured" : parts.joined(separator: " + ")
    }

    /// Deterministic key for duplicate detection — built generically from all enabled components
    var triggerKey: String {
        // Each component contributes a deterministic segment only if enabled
        var segments: [String] = []
        for (label, config) in allComponents where config.isEnabled {
            segments.append("\(label):\(config.displayValue)")
        }
        // Plugin triggers are alternatives, so their order must not matter
        return segments.sorted().joined(separator: "|")
    }

}

// MARK: - Component UI Provider Protocol

/// Protocol for plugins to provide component UI metadata
protocol ActivationComponentUIProvider {
    /// Get metadata for all components this plugin can provide
    func getComponentUIMetadata() -> [ActivationComponentUIMetadata]
}
