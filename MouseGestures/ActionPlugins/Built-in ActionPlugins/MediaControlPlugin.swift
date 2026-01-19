import Cocoa

// MARK: - Media Control Plugin

/// Built-in plugin for media control actions
class MediaControlPlugin: NSObject, GestureActionPlugin {
    
    // MARK: - Plugin Properties
    
    let identifier = "com.mousegestures.media"
    let name = "Media Control"
    override var description: String { "Control media playback and system audio" }
    let version = "1.0.0"
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
        PluginAction(
            id: "next_track",
            name: "Next Track",
            description: "Skip to next track",
            icon: "forward.end"
        ),
        PluginAction(
            id: "previous_track",
            name: "Previous Track",
            description: "Go to previous track",
            icon: "backward.end"
        ),
        PluginAction(
            id: "volume_up",
            name: "Volume Up",
            description: "Increase volume",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "amount",
                    name: "Amount",
                    type: .number,
                    defaultValue: AnyCodable(5),
                    description: "Volume change amount (0-100)",
                    validation: ValidationRule(minValue: 0, maxValue: 100)
                )
            ],
            supportsRepeat: true,
            icon: "speaker.plus"
        ),
        PluginAction(
            id: "volume_down",
            name: "Volume Down",
            description: "Decrease volume",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "amount",
                    name: "Amount",
                    type: .number,
                    defaultValue: AnyCodable(5),
                    description: "Volume change amount (0-100)",
                    validation: ValidationRule(minValue: 0, maxValue: 100)
                )
            ],
            supportsRepeat: true,
            icon: "speaker.minus"
        ),
        PluginAction(
            id: "mute",
            name: "Mute/Unmute",
            description: "Toggle mute state",
            icon: "speaker.slash"
        ),
        PluginAction(
            id: "set_volume",
            name: "Set Volume",
            description: "Set volume to specific level",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "level",
                    name: "Volume Level",
                    type: .number,
                    required: true,
                    description: "Volume level (0-100)",
                    validation: ValidationRule(minValue: 0, maxValue: 100)
                )
            ],
            icon: "speaker.wave.2"
        ),
        PluginAction(
            id: "fast_forward",
            name: "Fast Forward",
            description: "Fast forward playback",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "seconds",
                    name: "Seconds",
                    type: .number,
                    defaultValue: AnyCodable(10),
                    description: "Number of seconds to skip forward",
                    validation: ValidationRule(minValue: 1, maxValue: 60)
                )
            ],
            supportsRepeat: true,
            icon: "goforward.10"
        ),
        PluginAction(
            id: "rewind",
            name: "Rewind",
            description: "Rewind playback",
            requiresParameters: true,
            supportedParameters: [
                ParameterDefinition(
                    key: "seconds",
                    name: "Seconds",
                    type: .number,
                    defaultValue: AnyCodable(10),
                    description: "Number of seconds to skip backward",
                    validation: ValidationRule(minValue: 1, maxValue: 60)
                )
            ],
            supportsRepeat: true,
            icon: "gobackward.10"
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
            mediaPlayPause(context: context)
        case "next_track":
            mediaNextTrack(context: context)
        case "previous_track":
            mediaPreviousTrack(context: context)
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
        case "fast_forward":
            let seconds = parameters.number(for: "seconds") ?? 10
            skipForward(seconds: Int(seconds), context: context)
        case "rewind":
            let seconds = parameters.number(for: "seconds") ?? 10
            skipBackward(seconds: Int(seconds), context: context)
        default:
            throw PluginError.actionNotFound(action.id)
        }
    }
    
    func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        switch action.id {
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
    
    // MARK: - Private Implementation
    
    private func mediaPlayPause(context: PluginContext) {
        // Media keys need special handling - using keyboard shortcut as fallback
        context.sendKeyboardShortcut(keyCode: 49, modifiers: []) // Space key
    }
    
    private func mediaNextTrack(context: PluginContext) {
        // Use keyboard shortcut that works in many apps
        context.sendKeyboardShortcut(keyCode: 124, modifiers: [.maskCommand]) // Cmd+Right
    }
    
    private func mediaPreviousTrack(context: PluginContext) {
        // Use keyboard shortcut that works in many apps
        context.sendKeyboardShortcut(keyCode: 123, modifiers: [.maskCommand]) // Cmd+Left
    }
    
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
    
    private func skipForward(seconds: Int, context: PluginContext) {
        // This would need to be app-specific
        // For now, use keyboard shortcut that works in many apps
        context.sendKeyboardShortcut(keyCode: 124, modifiers: []) // Right arrow
    }
    
    private func skipBackward(seconds: Int, context: PluginContext) {
        // This would need to be app-specific
        // For now, use keyboard shortcut that works in many apps
        context.sendKeyboardShortcut(keyCode: 123, modifiers: []) // Left arrow
    }
    
    // Helper methods removed - now using context methods
}
