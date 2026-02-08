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
    
    /// Default initializer
    init() {}
    
    /// Get all enabled activation types
    var enabledTypes: Set<ActivationType> {
        var types = Set<ActivationType>()
        if modifierKey?.isEnabled == true { types.insert(.modifierKey) }
        if screenZone?.isEnabled == true { types.insert(.screenZone) }
        if dragType?.isEnabled == true && dragType?.dragType != .none {
            types.insert(.mouseButton) // Drag requires button hold
        }
        if mouseButton?.isEnabled == true && mouseButton?.button != .none {
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
    
    /// Get display preview of all enabled components
    var previewString: String {
        var parts: [String] = []
        
        if let mod = modifierKey, mod.isEnabled {
            parts.append(mod.displayValue)
        }
        if let zone = screenZone, zone.isEnabled {
            parts.append(zone.displayValue)
        }
        if let drag = dragType, drag.isEnabled, drag.dragType != .none {
            parts.append(drag.displayValue)
        }
        if let btn = mouseButton, btn.isEnabled, btn.button != .none {
            parts.append(btn.displayValue)
        }
        if let kbd = keyboardShortcut, kbd.isEnabled, kbd.keyboardTrigger != nil {
            parts.append(kbd.displayValue)
        }
        
        return parts.isEmpty ? "No triggers configured" : parts.joined(separator: " + ")
    }
    
    // MARK: - Legacy Conversion Helpers
    
    /// Create from legacy gesture structure
    init(fromLegacyGesture gesture: Gesture) {
        // Modifier keys from GestureTrigger
        if !gesture.modifiers.isEmpty {
            self.modifierKey = ModifierKeyConfig(isEnabled: true, modifiers: gesture.modifiers)
        }
        
        // Screen zone from GestureTrigger
        self.screenZone = ScreenZoneConfig(isEnabled: true, zone: gesture.zone)
        
        // Drag type from GestureTrigger
        if gesture.dragModifier != .none {
            self.dragType = DragTypeConfig(isEnabled: true, dragType: gesture.dragModifier)
        }
        
        // Mouse button from ActivationSettings
        if let mouseBtn = gesture.mouseButtonTrigger {
            self.mouseButton = MouseButtonConfig(isEnabled: true, button: mouseBtn.button)
        }
        
        // Keyboard shortcut from ActivationSettings
        if let kbd = gesture.keyboardTrigger {
            self.keyboardShortcut = KeyboardShortcutConfig(isEnabled: true, keyboardTrigger: kbd)
        }
    }
    
    /// Convert to legacy structure (for backward compatibility during transition)
    func toLegacyActivationType() -> ActivationSettings.ActivationType {
        let hasGesture = screenZone?.isEnabled == true
        let hasKeyboard = keyboardShortcut?.isEnabled == true
        let hasMouse = mouseButton?.isEnabled == true
        
        switch (hasGesture, hasKeyboard, hasMouse) {
        case (true, false, false): return .gesture
        case (false, true, false): return .keyboard
        case (false, false, true): return .mouseButton
        case (true, true, false): return .both
        case (true, false, true): return .gestureMouseButton
        case (false, true, true): return .keyboardMouseButton
        case (true, true, true): return .all
        default: return .gesture
        }
    }
}

// MARK: - Component UI Provider Protocol

/// Protocol for plugins to provide component UI metadata
protocol ActivationComponentUIProvider {
    /// Get metadata for all components this plugin can provide
    func getComponentUIMetadata() -> [ActivationComponentUIMetadata]
}
