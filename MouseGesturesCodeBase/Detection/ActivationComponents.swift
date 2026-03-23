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
    
    var displayValue: String {
        guard isEnabled else { return "Not configured" }
        return dragType.displayName
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
    /// When true, the gesture will NOT fire if any mouse button is currently pressed
    var requireNoMouse: Bool = false

    /// Default initializer
    init() {}
    
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
        return !enabledTypes.isEmpty
    }
    
    /// All registered components as (label, config) pairs in display order
    var allComponents: [(label: String, config: any ActivationComponentConfig)] {
        var result: [(String, any ActivationComponentConfig)] = []
        if let c = screenZone { result.append(("Zone", c)) }
        if let c = modifierKey { result.append(("Modifiers", c)) }
        if let c = dragType { result.append(("Drag", c)) }
        if let c = mouseButton { result.append(("Mouse Button", c)) }
        if let c = keyboardShortcut { result.append(("Keyboard", c)) }
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
        return segments.joined(separator: "|")
    }
    
}

// MARK: - Component UI Provider Protocol

/// Protocol for plugins to provide component UI metadata
protocol ActivationComponentUIProvider {
    /// Get metadata for all components this plugin can provide
    func getComponentUIMetadata() -> [ActivationComponentUIMetadata]
}
