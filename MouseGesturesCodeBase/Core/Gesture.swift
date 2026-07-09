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
    /// User-defined name. If nil, the UI falls back to the action's display name.
    var name: String?

    var longPressActionIdentifier: String?
    var longPressParameters: [String: AnyCodable]?

    // MARK: - Coding Keys

    enum CodingKeys: String, CodingKey {
        case genericActivation
        case components
        case actionIdentifier
        case timing
        case parameters
        case name
        case longPressActionIdentifier
        case longPressParameters
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        actionIdentifier = try c.decode(String.self, forKey: .actionIdentifier)
        timing = try c.decode(TimingSettings.self, forKey: .timing)
        parameters = try c.decode([String: AnyCodable].self, forKey: .parameters)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        longPressActionIdentifier = try c.decodeIfPresent(String.self, forKey: .longPressActionIdentifier)
        longPressParameters = try c.decodeIfPresent([String: AnyCodable].self, forKey: .longPressParameters)
        genericActivation = try c.decode(GenericActivation.self, forKey: .genericActivation)
        components = try c.decode(GestureActivationComponents.self, forKey: .components)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(genericActivation, forKey: .genericActivation)
        try c.encode(components, forKey: .components)
        try c.encode(actionIdentifier, forKey: .actionIdentifier)
        try c.encode(timing, forKey: .timing)
        try c.encode(parameters, forKey: .parameters)
        try c.encodeIfPresent(name, forKey: .name)
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

    var zone: ScreenZone {
        guard components.screenZone?.isEnabled == true else { return .topRight }
        return components.screenZone?.zone ?? .topRight
    }
    var modifiers: NSEvent.ModifierFlags {
        guard components.modifierKey?.isEnabled == true else { return [] }
        return components.modifierKey?.modifiers ?? []
    }
    var dragModifier: DragModifier {
        guard components.dragType?.isEnabled == true else { return .none }
        return components.dragType?.dragType ?? .none
    }

    var isEnabled: Bool {
        get { genericActivation.isEnabled }
        set { genericActivation.isEnabled = newValue }
    }

    var keyboardTrigger: KeyboardTrigger? {
        get {
            guard components.keyboardShortcut?.isEnabled == true else { return nil }
            return genericActivation.keyboardTrigger
        }
        set { genericActivation.setKeyboardTrigger(newValue) }
    }

    var mouseButtonTrigger: MouseButtonTrigger? {
        get {
            guard components.mouseButton?.isEnabled == true else { return nil }
            return genericActivation.mouseButtonTrigger
        }
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
         name: String? = nil,
         longPressActionIdentifier: String? = nil,
         longPressParameters: [String: AnyCodable]? = nil) {
        self.components = components
        self.genericActivation = genericActivation
        self.actionIdentifier = actionIdentifier
        self.timing = timing
        self.parameters = parameters
        self.name = name
        self.longPressActionIdentifier = longPressActionIdentifier
        self.longPressParameters = longPressParameters
    }

    /// Convenience initializer with zone, modifiers, and drag
    init(zone: ScreenZone,
         modifiers: NSEvent.ModifierFlags,
         dragModifier: DragModifier = .none,
         actionIdentifier: String,
         parameters: [String: AnyCodable] = [:],
         name: String? = nil,
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
        self.name = name
        self.longPressActionIdentifier = longPressActionIdentifier
        self.longPressParameters = longPressParameters
    }

    // MARK: - Component Helpers

    func updatingComponents(_ newComponents: GestureActivationComponents) -> Gesture {
        var newActivation = genericActivation
        newActivation.setKeyboardTrigger(newComponents.keyboardShortcut?.keyboardTrigger)
        let mouseTrigger: MouseButtonTrigger? = (newComponents.mouseButton?.button != MouseButtonTrigger.MouseButton.none && newComponents.mouseButton?.button != nil)
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
