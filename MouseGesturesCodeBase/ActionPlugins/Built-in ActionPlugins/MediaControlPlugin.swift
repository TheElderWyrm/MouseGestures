import Cocoa

// MARK: - Media Control Plugin

/// Built-in plugin for media control actions
class MediaControlPlugin: NSObject, GestureActionPlugin {
    
    // MARK: - Plugin Properties
    
    let identifier = "com.mousegestures.media"
    let name = "Media Control"
    override var description: String { "Control media playback and system audio" }
    let version = "2.0.0"
    let author = "MouseGestures"
    let category = ActionCategory.media
    let icon: NSImage? = nil
    
    // MARK: - Actions
    
    lazy var providedActions: [PluginAction] = [
        PluginAction(
            id: "play_pause",
            name: "Play/Pause",
            description: "Toggle media playback",
            icon: "playpause"
        ),
        
        // Consolidated: next_track + previous_track → track_skip
        PluginAction(
            id: "track_skip",
            name: "Skip Track",
            description: "Skip to next or previous track",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "direction",
                    name: "Direction",
                    type: .selection,
                    defaultValue: AnyCodable("next"),
                    description: "Skip direction",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("next"),
                        AnyCodable("previous")
                    ]),
                    displayValues: ["next": "Next Track", "previous": "Previous Track"]
                )
            ],
            supportsRepeat: true,
            icon: "forward.end"
        ),
        
        // Consolidated: volume_up + volume_down + mute + set_volume → volume
        PluginAction(
            id: "volume",
            name: "Volume Control",
            description: "Adjust system volume",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "mode",
                    name: "Mode",
                    type: .selection,
                    defaultValue: AnyCodable("up"),
                    description: "Volume action to perform",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("up"),
                        AnyCodable("down"),
                        AnyCodable("mute"),
                        AnyCodable("set")
                    ]),
                    displayValues: [
                        "up": "Volume Up",
                        "down": "Volume Down",
                        "mute": "Toggle Mute",
                        "set": "Set Level"
                    ]
                ),
                ParameterDefinition(
                    key: "amount",
                    name: "Amount",
                    type: .number,
                    defaultValue: AnyCodable(5),
                    description: "Volume step size (for up/down) or target level (for set)",
                    validation: ValidationRule(minValue: 0, maxValue: 100),
                    visibleWhen: ParameterVisibilityRule(key: "mode", anyOf: ["up", "down", "set"]),
                    suffix: "%"
                )
            ],
            supportsRepeat: true,
            icon: "speaker.wave.2"
        ),
        
        // Consolidated: fast_forward + rewind → seek
        PluginAction(
            id: "seek",
            name: "Seek",
            description: "Seek forward or backward in playback",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "direction",
                    name: "Direction",
                    type: .selection,
                    defaultValue: AnyCodable("forward"),
                    description: "Seek direction",
                    validation: ValidationRule(allowedValues: [
                        AnyCodable("forward"),
                        AnyCodable("backward")
                    ]),
                    displayValues: ["forward": "Forward", "backward": "Backward"]
                ),
                ParameterDefinition(
                    key: "seconds",
                    name: "Seconds",
                    type: .number,
                    defaultValue: AnyCodable(10),
                    description: "Seconds to seek",
                    validation: ValidationRule(minValue: 1, maxValue: 60),
                    suffix: "s"
                )
            ],
            supportsRepeat: true,
            icon: "goforward.10"
        )
    ]
    
    // MARK: - Plugin Lifecycle
    
    private var context: PluginContext?
    
    func initialize(context: PluginContext) throws {
        self.context = context
        context.logger.log("Media Control Plugin initialized", file: #file, function: #function, line: #line)
    }
    
    func cleanup() {
        context?.logger.log("Media Control Plugin cleaned up", file: #file, function: #function, line: #line)
        context = nil
    }
    
    // MARK: - Action Execution
    
    func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "play_pause":
            sendMediaKey(.playPause)
            
        // Consolidated track skip
        case "track_skip":
            let direction = parameters.string(for: "direction") ?? "next"
            sendMediaKey(direction == "next" ? .nextTrack : .previousTrack)
            
        // Legacy aliases for backward compatibility
        case "next_track":
            sendMediaKey(.nextTrack)
        case "previous_track":
            sendMediaKey(.previousTrack)
            
        // Consolidated volume control
        case "volume":
            let mode = parameters.string(for: "mode") ?? "up"
            let amount = parameters.number(for: "amount") ?? 5
            switch mode {
            case "up":
                changeVolume(by: Int(amount), context: context)
            case "down":
                changeVolume(by: -Int(amount), context: context)
            case "mute":
                toggleMute(context: context)
            case "set":
                setVolume(to: Int(amount), context: context)
            default:
                break
            }
            
        // Legacy aliases for backward compatibility
        case "volume_up":
            let amount = parameters.number(for: "amount") ?? 5
            changeVolume(by: Int(amount), context: context)
        case "volume_down":
            let amount = parameters.number(for: "amount") ?? 5
            changeVolume(by: -Int(amount), context: context)
        case "mute":
            toggleMute(context: context)
        case "set_volume":
            if let level = parameters.number(for: "level") {
                setVolume(to: Int(level), context: context)
            }
            
        // Consolidated seek
        case "seek":
            let direction = parameters.string(for: "direction") ?? "forward"
            let seconds = parameters.number(for: "seconds") ?? 10
            if direction == "forward" {
                seekMedia(seconds: Int(seconds), forward: true)
            } else {
                seekMedia(seconds: Int(seconds), forward: false)
            }
            
        // Legacy aliases for backward compatibility
        case "fast_forward":
            let seconds = parameters.number(for: "seconds") ?? 10
            seekMedia(seconds: Int(seconds), forward: true)
        case "rewind":
            let seconds = parameters.number(for: "seconds") ?? 10
            seekMedia(seconds: Int(seconds), forward: false)
            
        default:
            throw PluginError.actionNotFound(action.id)
        }
    }
    
    func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        switch action.id {
        case "volume":
            let mode = parameters.string(for: "mode") ?? "up"
            if mode == "set" {
                guard parameters.number(for: "amount") != nil else {
                    return ValidationResult.invalid(error: "Volume level is required for Set mode")
                }
            }
        case "set_volume":
            guard parameters.number(for: "level") != nil else {
                return ValidationResult.invalid(error: "Volume level is required")
            }
        default:
            break
        }
        return .valid
    }
    
    func configurationView(for action: PluginAction) -> NSView? {
        return nil
    }
    
    // MARK: - NX Media Key Types
    
    /// System media key types (from IOKit/hidsystem)
    private enum NXMediaKeyType: UInt32 {
        case playPause     = 16  // NX_KEYTYPE_PLAY
        case nextTrack     = 17  // NX_KEYTYPE_NEXT
        case previousTrack = 18  // NX_KEYTYPE_PREVIOUS
        case fastForward   = 19  // NX_KEYTYPE_FAST
        case rewind        = 20  // NX_KEYTYPE_REWIND
    }
    
    /// Send a system media key event using NX_KEYTYPE events.
    /// This works system-wide regardless of which app is focused.
    private func sendMediaKey(_ key: NXMediaKeyType) {
        // Build NX key event data: key type in bits 16-23, state in bits 8-15
        // Key down
        let keyDownData = Int((key.rawValue << 16) | (0x0A << 8))
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            data1: keyDownData,
            data2: -1
        )
        
        // Key up
        let keyUpData = Int((key.rawValue << 16) | (0x0B << 8))
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: keyUpData,
            data2: -1
        )
        
        if let keyDown = keyDown {
            keyDown.cgEvent?.post(tap: .cghidEventTap)
        }
        if let keyUp = keyUp {
            keyUp.cgEvent?.post(tap: .cghidEventTap)
        }
    }
    
    /// Seek forward or backward in media playback using NX media keys.
    private func seekMedia(seconds: Int, forward: Bool) {
        // Send the appropriate NX media key for seeking
        // For apps that support it, this triggers proper seeking rather than track skip
        let key: NXMediaKeyType = forward ? .fastForward : .rewind
        
        // For NX seek keys, we send key-down, wait, then key-up to simulate hold duration
        let keyDownData = Int((key.rawValue << 16) | (0x0A << 8))
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: keyDownData,
            data2: -1
        )
        
        if let keyDown = keyDown {
            keyDown.cgEvent?.post(tap: .cghidEventTap)
        }
        
        // Hold for proportional to seconds requested (100ms per second as approximation)
        let holdDuration = useconds_t(min(seconds * 100_000, 2_000_000))
        usleep(holdDuration)
        
        let keyUpData = Int((key.rawValue << 16) | (0x0B << 8))
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: 0xa00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: keyUpData,
            data2: -1
        )
        
        if let keyUp = keyUp {
            keyUp.cgEvent?.post(tap: .cghidEventTap)
        }
    }
    
    // MARK: - Volume Control (AppleScript — these are system-level, not media keys)
    
    private func changeVolume(by amount: Int, context: PluginContext) {
        let script = """
            set currentVolume to output volume of (get volume settings)
            set newVolume to currentVolume + \(amount)
            if newVolume > 100 then set newVolume to 100
            if newVolume < 0 then set newVolume to 0
            set volume output volume newVolume
        """
        try? context.executeAppleScript(script)
    }
    
    private func setVolume(to level: Int, context: PluginContext) {
        let clampedLevel = min(max(level, 0), 100)
        let script = "set volume output volume \(clampedLevel)"
        try? context.executeAppleScript(script)
    }
    
    private func toggleMute(context: PluginContext) {
        let script = """
            set currentMute to (output muted of (get volume settings))
            set volume output muted not currentMute
        """
        try? context.executeAppleScript(script)
    }
}
