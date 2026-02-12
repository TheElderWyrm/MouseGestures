import Foundation
import Cocoa
import Carbon

// MARK: - Core Components

/// Core gesture trigger information
struct GestureTrigger: Codable, Equatable {
    let zone: ScreenZone
    let modifiers: NSEvent.ModifierFlags
    let dragModifier: DragModifier
    
    init(zone: ScreenZone, modifiers: NSEvent.ModifierFlags, dragModifier: DragModifier = .none) {
        self.zone = zone
        self.modifiers = modifiers
        self.dragModifier = dragModifier
    }
    
    var displayString: String {
        let modDesc = modifiers.symbolString.isEmpty ? "No Modifiers" : modifiers.symbolString
        var desc = "\(zone.rawValue) + \(modDesc)"
        if dragModifier != .none {
            desc += " + \(dragModifier.displayName)"
        }
        return desc
    }
}

/// LEGACY: Settings for how a gesture can be activated
/// DEPRECATED: Use GenericActivation instead
/// Kept for backward compatibility during migration
struct ActivationSettings: Codable, Equatable {
    var activationType: ActivationType
    var keyboardTrigger: KeyboardTrigger?
    var mouseButtonTrigger: MouseButtonTrigger?
    var isEnabled: Bool
    
    init(activationType: ActivationType = .both, 
         keyboardTrigger: KeyboardTrigger? = nil,
         mouseButtonTrigger: MouseButtonTrigger? = nil,
         isEnabled: Bool = true) {
        self.activationType = activationType
        self.keyboardTrigger = keyboardTrigger
        self.mouseButtonTrigger = mouseButtonTrigger
        self.isEnabled = isEnabled
    }
    
    enum ActivationType: String, Codable, CaseIterable {
        case gesture = "Gesture Only"
        case keyboard = "Keyboard Only"
        case mouseButton = "Mouse Button Only"
        case both = "Both" // Gesture + Keyboard
        case gestureMouseButton = "Gesture + Mouse Button"
        case keyboardMouseButton = "Keyboard + Mouse Button"
        case all = "All Methods"
    }
    
    var hasGesture: Bool {
        switch activationType {
        case .gesture, .both, .gestureMouseButton, .all:
            return true
        default:
            return false
        }
    }
    
    var hasKeyboard: Bool {
        switch activationType {
        case .keyboard, .both, .keyboardMouseButton, .all:
            return true
        default:
            return false
        }
    }
    
    var hasMouseButton: Bool {
        switch activationType {
        case .mouseButton, .gestureMouseButton, .keyboardMouseButton, .all:
            return true
        default:
            return false
        }
    }
}

/// Timing configuration for repeating and long press actions
struct TimingSettings: Codable, Equatable {
    var repeatOnHold: Bool
    var repeatInitialDelay: TimeInterval
    var repeatInterval: TimeInterval
    var longPressEnabled: Bool
    var longPressThreshold: TimeInterval
    
    init(repeatOnHold: Bool = false,
         repeatInitialDelay: TimeInterval = 0.5,
         repeatInterval: TimeInterval = 0.5,
         longPressEnabled: Bool = false,
         longPressThreshold: TimeInterval = 0.8) {
        self.repeatOnHold = repeatOnHold
        self.repeatInitialDelay = repeatInitialDelay
        self.repeatInterval = repeatInterval
        self.longPressEnabled = longPressEnabled
        self.longPressThreshold = longPressThreshold
    }
}

// MARK: - Plugin-Based Gesture Structure

/// Gesture structure with generic plugin activation system
struct Gesture: Codable, Equatable {
    
    // MARK: - Stored Properties
    
    // Core components
    let trigger: GestureTrigger
    var actionIdentifier: String
    var timing: TimingSettings
    var parameters: [String: AnyCodable]
    
    // Generic activation (plugin-independent)
    var genericActivation: GenericActivation
    
    // Modular component system (optional)
    var components: GestureActivationComponents?
    
    // Long press variant
    var longPressActionIdentifier: String?
    var longPressParameters: [String: AnyCodable]?
    
    // MARK: - Coding Keys
    
    enum CodingKeys: String, CodingKey {
        case trigger
        case actionIdentifier
        case timing
        case parameters
        case genericActivation
        case activation // Legacy key
        case components
        case longPressActionIdentifier
        case longPressParameters
    }
    
    // MARK: - Codable Implementation (with migration)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        trigger = try container.decode(GestureTrigger.self, forKey: .trigger)
        actionIdentifier = try container.decode(String.self, forKey: .actionIdentifier)
        timing = try container.decode(TimingSettings.self, forKey: .timing)
        parameters = try container.decode([String: AnyCodable].self, forKey: .parameters)
        components = try container.decodeIfPresent(GestureActivationComponents.self, forKey: .components)
        longPressActionIdentifier = try container.decodeIfPresent(String.self, forKey: .longPressActionIdentifier)
        longPressParameters = try container.decodeIfPresent([String: AnyCodable].self, forKey: .longPressParameters)
        
        // Migration: Try new format first, fall back to legacy
        if let generic = try? container.decode(GenericActivation.self, forKey: .genericActivation) {
            genericActivation = generic
        } else if let legacy = try? container.decode(ActivationSettings.self, forKey: .activation) {
            // Migrate from legacy format
            genericActivation = GenericActivation(from: legacy)
        } else {
            // Default
            genericActivation = GenericActivation()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(trigger, forKey: .trigger)
        try container.encode(actionIdentifier, forKey: .actionIdentifier)
        try container.encode(timing, forKey: .timing)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(genericActivation, forKey: .genericActivation)
        try container.encodeIfPresent(components, forKey: .components)
        try container.encodeIfPresent(longPressActionIdentifier, forKey: .longPressActionIdentifier)
        try container.encodeIfPresent(longPressParameters, forKey: .longPressParameters)
    }
    
    // MARK: - Unique Identifiers
    
    var id: String {
        let dragPart = trigger.dragModifier != .none ? "_\(trigger.dragModifier.rawValue)" : ""
        return "\(trigger.zone.rawValue)_\(trigger.modifiers.rawValue)\(dragPart)_\(actionIdentifier)"
    }
    
    var triggerKey: String {
        var parts: [String] = [
            "\(trigger.zone.rawValue)",
            "\(trigger.modifiers.rawValue)"
        ]
        if trigger.dragModifier != .none {
            parts.append("drag_\(trigger.dragModifier.rawValue)")
        }
        if let kbd = genericActivation.keyboardTrigger {
            parts.append("kbd_\(kbd.keyCode)_\(kbd.modifiers.rawValue)")
        }
        if let mb = genericActivation.mouseButtonTrigger {
            parts.append("mb_\(mb.button.rawValue)")
        }
        return parts.joined(separator: "_")
    }
    
    // MARK: - Display
    
    var displayDescription: String {
        var parts: [String] = []
        
        // Always show zone-based gesture
        parts.append(trigger.displayString)
        
        // Show keyboard trigger if configured
        if let kbd = genericActivation.keyboardTrigger {
            parts.append(kbd.displayString)
        }
        
        // Show mouse button trigger if configured
        if let mouse = genericActivation.mouseButtonTrigger {
            parts.append(mouse.displayString)
        }
        
        return parts.isEmpty ? "Not Configured" : parts.joined(separator: " | ")
    }
    
    // MARK: - Initializers
    
    init(trigger: GestureTrigger,
         actionIdentifier: String,
         genericActivation: GenericActivation = GenericActivation(),
         timing: TimingSettings = TimingSettings(),
         parameters: [String: AnyCodable] = [:],
         components: GestureActivationComponents? = nil,
         longPressActionIdentifier: String? = nil,
         longPressParameters: [String: AnyCodable]? = nil) {
        self.trigger = trigger
        self.actionIdentifier = actionIdentifier
        self.genericActivation = genericActivation
        self.timing = timing
        self.parameters = parameters
        self.components = components
        self.longPressActionIdentifier = longPressActionIdentifier
        self.longPressParameters = longPressParameters
    }
    
    // Initializer from components
    init(components: GestureActivationComponents,
         actionIdentifier: String,
         timing: TimingSettings = TimingSettings(),
         parameters: [String: AnyCodable] = [:],
         longPressActionIdentifier: String? = nil,
         longPressParameters: [String: AnyCodable]? = nil) {
        
        // Convert components to trigger
        let zone = components.screenZone?.zone ?? .topRight
        let modifiers = components.modifierKey?.modifiers ?? []
        let drag = components.dragType?.dragType ?? .none
        self.trigger = GestureTrigger(zone: zone, modifiers: modifiers, dragModifier: drag)
        
        self.actionIdentifier = actionIdentifier
        self.timing = timing
        self.parameters = parameters
        self.components = components
        self.longPressActionIdentifier = longPressActionIdentifier
        self.longPressParameters = longPressParameters
        
        // Set up generic activation from components
        var activation = GenericActivation(isEnabled: components.isValid)
        activation.setKeyboardTrigger(components.keyboardShortcut?.keyboardTrigger)
        if let mouseBtn = components.mouseButton, mouseBtn.button != MouseButtonTrigger.MouseButton.none {
            activation.setMouseButtonTrigger(MouseButtonTrigger(button: mouseBtn.button, modifiers: []))
        }
        self.genericActivation = activation
    }
    
    // Convenience initializer with zone and modifiers
    init(zone: ScreenZone,
         modifiers: NSEvent.ModifierFlags,
         dragModifier: DragModifier = .none,
         actionIdentifier: String,
         parameters: [String: AnyCodable] = [:],
         keyboardTrigger: KeyboardTrigger? = nil,
         mouseButtonTrigger: MouseButtonTrigger? = nil,
         isEnabled: Bool = true,
         timing: TimingSettings = TimingSettings(),
         longPressActionIdentifier: String? = nil,
         longPressParameters: [String: AnyCodable]? = nil) {
        
        self.trigger = GestureTrigger(zone: zone, modifiers: modifiers, dragModifier: dragModifier)
        self.actionIdentifier = actionIdentifier
        self.timing = timing
        self.parameters = parameters
        self.components = nil
        self.longPressActionIdentifier = longPressActionIdentifier
        self.longPressParameters = longPressParameters
        
        // Set up generic activation
        var activation = GenericActivation(isEnabled: isEnabled)
        activation.setKeyboardTrigger(keyboardTrigger)
        activation.setMouseButtonTrigger(mouseButtonTrigger)
        self.genericActivation = activation
    }
    
    // MARK: - Backward Compatibility Properties
    
    /// Legacy activation property (for backward compatibility)
    var activation: ActivationSettings {
        get { genericActivation.toLegacy() }
        set { genericActivation = GenericActivation(from: newValue) }
    }
    
    var zone: ScreenZone { trigger.zone }
    var modifiers: NSEvent.ModifierFlags { trigger.modifiers }
    var dragModifier: DragModifier { trigger.dragModifier }
    
    var isEnabled: Bool {
        get { genericActivation.isEnabled }
        set { genericActivation.isEnabled = newValue }
    }
    
    var keyboardTrigger: KeyboardTrigger? {
        get { genericActivation.keyboardTrigger }
        set { genericActivation.setKeyboardTrigger(newValue) }
    }
    
    var mouseButtonTrigger: MouseButtonTrigger? {
        get { genericActivation.mouseButtonTrigger }
        set { genericActivation.setMouseButtonTrigger(newValue) }
    }
    
    var activationType: ActivationSettings.ActivationType {
        activation.activationType
    }
    
    var repeatOnHold: Bool { timing.repeatOnHold }
    var repeatInitialDelay: TimeInterval { timing.repeatInitialDelay }
    var repeatInterval: TimeInterval { timing.repeatInterval }
    var longPressEnabled: Bool { timing.longPressEnabled }
    var longPressThreshold: TimeInterval { timing.longPressThreshold }
    
    // MARK: - Component System Helpers
    
    mutating func getComponents() -> GestureActivationComponents {
        if let existing = components {
            return existing
        }
        let migrated = GestureActivationComponents(fromLegacyGesture: self)
        self.components = migrated
        return migrated
    }
    
    func updatingComponents(_ newComponents: GestureActivationComponents) -> Gesture {
        let zone = newComponents.screenZone?.zone ?? trigger.zone
        let modifiers = newComponents.modifierKey?.modifiers ?? trigger.modifiers
        let drag = newComponents.dragType?.dragType ?? trigger.dragModifier
        let newTrigger = GestureTrigger(zone: zone, modifiers: modifiers, dragModifier: drag)
        
        var newActivation = genericActivation
        newActivation.setKeyboardTrigger(newComponents.keyboardShortcut?.keyboardTrigger)
        newActivation.setMouseButtonTrigger(
            (newComponents.mouseButton?.button != MouseButtonTrigger.MouseButton.none && newComponents.mouseButton?.button != nil) ?
            MouseButtonTrigger(button: newComponents.mouseButton!.button, modifiers: []) : nil
        )
        newActivation.isEnabled = newComponents.isValid
        
        return Gesture(
            trigger: newTrigger,
            actionIdentifier: actionIdentifier,
            genericActivation: newActivation,
            timing: timing,
            parameters: parameters,
            components: newComponents,
            longPressActionIdentifier: longPressActionIdentifier,
            longPressParameters: longPressParameters
        )
    }
    
    // MARK: - Execution
    
    func execute() {
        let actionParams = ActionParameters(values: parameters)
        do {
            try PluginManager.shared.executeAction(
                identifier: actionIdentifier,
                parameters: actionParams
            )
        } catch {
            log.log("Failed to execute gesture: \(error)")
        }
    }
    
    func executeLongPress() throws {
        if let longPressId = longPressActionIdentifier {
            let actionParams = ActionParameters(values: longPressParameters ?? parameters)
            try PluginManager.shared.executeAction(
                identifier: longPressId,
                parameters: actionParams
            )
        } else {
            let actionParams = ActionParameters(values: parameters)
            try PluginManager.shared.executeAction(
                identifier: actionIdentifier,
                parameters: actionParams
            )
        }
    }
}
