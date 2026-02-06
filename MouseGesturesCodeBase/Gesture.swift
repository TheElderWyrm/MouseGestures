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
        var desc = "\(zone.rawValue) + \(modifiersDescription)"
        if dragModifier != .none {
            desc += " + \(dragModifier.displayName)"
        }
        return desc
    }
    
    private var modifiersDescription: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        return parts.isEmpty ? "No Modifiers" : parts.joined(separator: "")
    }
}

/// Settings for how a gesture can be activated
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

/// New gesture structure using plugin action identifiers
struct Gesture: Codable, Equatable {

    
    // Core components
    let trigger: GestureTrigger
    var actionIdentifier: String  // Plugin action ID
    var activation: ActivationSettings
    var timing: TimingSettings
    var parameters: [String: AnyCodable]  // Generic parameters for the plugin
    
    // Long press variant
    var longPressActionIdentifier: String?
    var longPressParameters: [String: AnyCodable]?
    

    
    // Unique identifier
    var id: String {
        let dragPart = trigger.dragModifier != .none ? "_\(trigger.dragModifier.rawValue)" : ""
        return "\(trigger.zone.rawValue)_\(trigger.modifiers.rawValue)\(dragPart)_\(actionIdentifier)"
    }
    
    // Display description for UI
    var displayDescription: String {
        var parts: [String] = []
        
        if activation.hasGesture {
            parts.append(trigger.displayString)
        }
        
        if activation.hasKeyboard, let kbd = activation.keyboardTrigger {
            parts.append(kbd.displayString)
        }
        
        if activation.hasMouseButton, let mouse = activation.mouseButtonTrigger {
            parts.append(mouse.displayString)
        }
        
        return parts.isEmpty ? "Not Configured" : parts.joined(separator: " | ")
    }
    
    // MARK: - Initializers
    
    init(trigger: GestureTrigger,
         actionIdentifier: String,
         activation: ActivationSettings = ActivationSettings(),
         timing: TimingSettings = TimingSettings(),
         parameters: [String: AnyCodable] = [:],
         longPressActionIdentifier: String? = nil,
         longPressParameters: [String: AnyCodable]? = nil) {
        self.trigger = trigger
        self.actionIdentifier = actionIdentifier
        self.activation = activation
        self.timing = timing
        self.parameters = parameters
        self.longPressActionIdentifier = longPressActionIdentifier
        self.longPressParameters = longPressParameters
    }
    
    // Convenience initializer from zone and modifiers
    init(zone: ScreenZone,
         modifiers: NSEvent.ModifierFlags,
         dragModifier: DragModifier = .none,
         actionIdentifier: String,
         parameters: [String: AnyCodable] = [:],
         keyboardTrigger: KeyboardTrigger? = nil,
         mouseButtonTrigger: MouseButtonTrigger? = nil,
         activationType: ActivationSettings.ActivationType = .both,
         isEnabled: Bool = true,
         repeatOnHold: Bool = false,
         repeatInitialDelay: TimeInterval = 0.5,
         repeatInterval: TimeInterval = 0.5,
         longPressEnabled: Bool = false,
         longPressThreshold: TimeInterval = 0.8,
         longPressActionIdentifier: String? = nil,
         longPressParameters: [String: AnyCodable]? = nil) {
        
        self.trigger = GestureTrigger(zone: zone, modifiers: modifiers, dragModifier: dragModifier)
        self.actionIdentifier = actionIdentifier
        
        self.activation = ActivationSettings(
            activationType: activationType,
            keyboardTrigger: keyboardTrigger,
            mouseButtonTrigger: mouseButtonTrigger,
            isEnabled: isEnabled
        )
        
        self.timing = TimingSettings(
            repeatOnHold: repeatOnHold,
            repeatInitialDelay: repeatInitialDelay,
            repeatInterval: repeatInterval,
            longPressEnabled: longPressEnabled,
            longPressThreshold: longPressThreshold
        )
        
        self.parameters = parameters
        self.longPressActionIdentifier = longPressActionIdentifier
        self.longPressParameters = longPressParameters
    }
    
    // MARK: - Computed Properties for convenience
    
    var zone: ScreenZone { trigger.zone }
    var modifiers: NSEvent.ModifierFlags { trigger.modifiers }
    var dragModifier: DragModifier { trigger.dragModifier }
    var isEnabled: Bool {
        get { activation.isEnabled }
        set { activation.isEnabled = newValue }
    }
    var keyboardTrigger: KeyboardTrigger? { activation.keyboardTrigger }
    var mouseButtonTrigger: MouseButtonTrigger? { activation.mouseButtonTrigger }
    var activationType: ActivationSettings.ActivationType { activation.activationType }
    var repeatOnHold: Bool { timing.repeatOnHold }
    var repeatInitialDelay: TimeInterval { timing.repeatInitialDelay }
    var repeatInterval: TimeInterval { timing.repeatInterval }
    var longPressEnabled: Bool { timing.longPressEnabled }
    var longPressThreshold: TimeInterval { timing.longPressThreshold }
    
    // MARK: - Execution
    
    func execute() {
        // Convert [String: AnyCodable] to ActionParameters (which is also [String: AnyCodable])
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


