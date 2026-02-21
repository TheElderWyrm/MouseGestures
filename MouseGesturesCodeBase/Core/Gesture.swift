import Foundation
import Cocoa
import Carbon

// MARK: - Timing Configuration

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

// MARK: - Gesture

/// Plugin-based gesture structure using generic activation system.
/// Zone, modifiers, and drag are stored exclusively in `components`.
struct Gesture: Codable, Equatable {
    
    // MARK: - Stored Properties
    
    /// Generic activation (plugin-independent detection configs)
    var genericActivation: GenericActivation
    
    /// Full modular component system (zone, modifiers, drag, keyboard, mouse button)
    var components: GestureActivationComponents
    
    var actionIdentifier: String
    var timing: TimingSettings
    var parameters: [String: AnyCodable]
    
    var longPressActionIdentifier: String?
    var longPressParameters: [String: AnyCodable]?
    
    // MARK: - Coding Keys
    
    enum CodingKeys: String, CodingKey {
        case genericActivation
        case activation           // Legacy key (ActivationSettings)
        case components
        case trigger              // Legacy key (GestureTrigger)
        case actionIdentifier
        case timing
        case parameters
        case longPressActionIdentifier
        case longPressParameters
    }
    
    // MARK: - Codable (with migration)
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        actionIdentifier = try c.decode(String.self, forKey: .actionIdentifier)
        timing = try c.decode(TimingSettings.self, forKey: .timing)
        parameters = try c.decode([String: AnyCodable].self, forKey: .parameters)
        longPressActionIdentifier = try c.decodeIfPresent(String.self, forKey: .longPressActionIdentifier)
        longPressParameters = try c.decodeIfPresent([String: AnyCodable].self, forKey: .longPressParameters)
        
        // --- Migrate genericActivation ---
        if let generic = try? c.decode(GenericActivation.self, forKey: .genericActivation) {
            genericActivation = generic
        } else if let legacy = try? c.decode(LegacyActivationSettings.self, forKey: .activation) {
            // Migrate from old ActivationSettings
            var configs: [String: [String: AnyCodable]] = [:]
            if let kbd = legacy.keyboardTrigger {
                configs["keyboard_detector"] = [
                    "keyCode": AnyCodable(Int(kbd.keyCode)),
                    "modifiers": AnyCodable(kbd.modifiers.rawValue),
                    "displayString": AnyCodable(kbd.displayString)
                ]
            }
            if let mouse = legacy.mouseButtonTrigger {
                configs["mouse_button_detector"] = [
                    "button": AnyCodable(mouse.button.rawValue),
                    "modifiers": AnyCodable(mouse.modifiers.rawValue),
                    "displayString": AnyCodable(mouse.displayString)
                ]
            }
            genericActivation = GenericActivation(detectionConfigs: configs, isEnabled: legacy.isEnabled)
        } else {
            genericActivation = GenericActivation()
        }
        
        // --- Migrate components ---
        if let comps = try? c.decode(GestureActivationComponents.self, forKey: .components) {
            components = comps
        } else {
            // Build components from legacy GestureTrigger + genericActivation
            var comps = GestureActivationComponents()
            
            if let trigger = try? c.decode(LegacyGestureTrigger.self, forKey: .trigger) {
                comps.screenZone = ScreenZoneConfig(isEnabled: true, zone: trigger.zone)
                if !trigger.modifiers.isEmpty {
                    comps.modifierKey = ModifierKeyConfig(isEnabled: true, modifiers: trigger.modifiers)
                }
                if trigger.dragModifier != .none {
                    comps.dragType = DragTypeConfig(isEnabled: true, dragType: trigger.dragModifier)
                }
            }
            
            if let kbd = genericActivation.keyboardTrigger {
                comps.keyboardShortcut = KeyboardShortcutConfig(isEnabled: true, keyboardTrigger: kbd)
            }
            if let mouse = genericActivation.mouseButtonTrigger {
                comps.mouseButton = MouseButtonConfig(isEnabled: true, button: mouse.button)
            }
            
            components = comps
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(genericActivation, forKey: .genericActivation)
        try c.encode(components, forKey: .components)
        try c.encode(actionIdentifier, forKey: .actionIdentifier)
        try c.encode(timing, forKey: .timing)
        try c.encode(parameters, forKey: .parameters)
        try c.encodeIfPresent(longPressActionIdentifier, forKey: .longPressActionIdentifier)
        try c.encodeIfPresent(longPressParameters, forKey: .longPressParameters)
    }
    
    // MARK: - Unique Identifiers
    
    var id: String {
        let dragPart = dragModifier != .none ? "_\(dragModifier.rawValue)" : ""
        return "\(zone.rawValue)_\(modifiers.rawValue)\(dragPart)_\(actionIdentifier)"
    }
    
    var triggerKey: String {
        return components.triggerKey
    }
    
    // MARK: - Display
    
    var displayDescription: String {
        return components.previewString
    }
    
    // MARK: - Computed Properties (derived from components)
    
    var zone: ScreenZone { components.screenZone?.zone ?? .topRight }
    var modifiers: NSEvent.ModifierFlags { components.modifierKey?.modifiers ?? [] }
    var dragModifier: DragModifier { components.dragType?.dragType ?? .none }
    
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
    
    var repeatOnHold: Bool { timing.repeatOnHold }
    var repeatInitialDelay: TimeInterval { timing.repeatInitialDelay }
    var repeatInterval: TimeInterval { timing.repeatInterval }
    var longPressEnabled: Bool { timing.longPressEnabled }
    var longPressThreshold: TimeInterval { timing.longPressThreshold }
    
    /// Whether this gesture has a screen zone trigger (vs. keyboard-only or mouse-click-only)
    var hasZoneTrigger: Bool {
        return components.screenZone?.isEnabled == true
    }
    
    // MARK: - Initializers
    
    /// Primary initializer using the component system
    init(components: GestureActivationComponents,
         genericActivation: GenericActivation = GenericActivation(),
         actionIdentifier: String,
         timing: TimingSettings = TimingSettings(),
         parameters: [String: AnyCodable] = [:],
         longPressActionIdentifier: String? = nil,
         longPressParameters: [String: AnyCodable]? = nil) {
        self.components = components
        self.genericActivation = genericActivation
        self.actionIdentifier = actionIdentifier
        self.timing = timing
        self.parameters = parameters
        self.longPressActionIdentifier = longPressActionIdentifier
        self.longPressParameters = longPressParameters
    }
    
    /// Convenience initializer with zone, modifiers, and drag
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
        
        var comps = GestureActivationComponents()
        comps.screenZone = ScreenZoneConfig(isEnabled: true, zone: zone)
        if !modifiers.isEmpty {
            comps.modifierKey = ModifierKeyConfig(isEnabled: true, modifiers: modifiers)
        }
        if dragModifier != .none {
            comps.dragType = DragTypeConfig(isEnabled: true, dragType: dragModifier)
        }
        if let kbd = keyboardTrigger {
            comps.keyboardShortcut = KeyboardShortcutConfig(isEnabled: true, keyboardTrigger: kbd)
        }
        if let mouse = mouseButtonTrigger {
            comps.mouseButton = MouseButtonConfig(isEnabled: true, button: mouse.button)
        }
        self.components = comps
        
        var activation = GenericActivation(isEnabled: isEnabled)
        activation.setKeyboardTrigger(keyboardTrigger)
        activation.setMouseButtonTrigger(mouseButtonTrigger)
        self.genericActivation = activation
        
        self.actionIdentifier = actionIdentifier
        self.timing = timing
        self.parameters = parameters
        self.longPressActionIdentifier = longPressActionIdentifier
        self.longPressParameters = longPressParameters
    }
    
    // MARK: - Component Helpers
    
    func updatingComponents(_ newComponents: GestureActivationComponents) -> Gesture {
        var newActivation = genericActivation
        newActivation.setKeyboardTrigger(newComponents.keyboardShortcut?.keyboardTrigger)
        let mouseTrigger: MouseButtonTrigger? = (newComponents.mouseButton?.button != .none && newComponents.mouseButton?.button != nil)
            ? MouseButtonTrigger(button: newComponents.mouseButton!.button, modifiers: [])
            : nil
        newActivation.setMouseButtonTrigger(mouseTrigger)
        newActivation.isEnabled = newComponents.isValid
        
        return Gesture(
            components: newComponents,
            genericActivation: newActivation,
            actionIdentifier: actionIdentifier,
            timing: timing,
            parameters: parameters,
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

// MARK: - Legacy Migration Types (private, decode-only)

/// Used only during Codable migration from old save files. Not a live data structure.
private struct LegacyGestureTrigger: Codable {
    let zone: ScreenZone
    let modifiers: NSEvent.ModifierFlags
    let dragModifier: DragModifier
    
    init(zone: ScreenZone, modifiers: NSEvent.ModifierFlags, dragModifier: DragModifier = .none) {
        self.zone = zone
        self.modifiers = modifiers
        self.dragModifier = dragModifier
    }
}

/// Used only during Codable migration from old save files. Not a live data structure.
private struct LegacyActivationSettings: Codable {
    var activationType: ActivationType
    var keyboardTrigger: KeyboardTrigger?
    var mouseButtonTrigger: MouseButtonTrigger?
    var isEnabled: Bool
    
    enum CodingKeys: String, CodingKey {
        case activationType
        case keyboardTrigger
        case mouseButtonTrigger
        case isEnabled
    }
    
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
        case both = "Both"
        case gestureMouseButton = "Gesture + Mouse Button"
        case keyboardMouseButton = "Keyboard + Mouse Button"
        case all = "All Methods"
    }
}
