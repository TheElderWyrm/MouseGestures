import Cocoa

/// Sound device switching inside the built-in Media Control plugin.
enum AudioSwitchActions {
    static let actions: [PluginAction] = [
        PluginAction(id: "cycle_audio_output", name: "Next Sound Output", description: "Switch to the next speakers / headphones / AirPlay output", icon: "hifispeaker.2"),
        PluginAction(id: "cycle_audio_input", name: "Next Sound Input", description: "Switch to the next microphone", icon: "mic"),
    ]

    static let ids: Set<String> = Set(actions.map { $0.id })

    static func execute(_ action: PluginAction, context: PluginContext) throws {
        switch action.id {
        case "cycle_audio_output", "cycle_audio_input":
            let output = action.id == "cycle_audio_output"
            let list = AudioDevices.devices(output: output)
            guard let next = AudioDevices.next(after: AudioDevices.defaultDevice(output: output), in: list) else {
                context.showNotification(title: output ? "Sound output" : "Sound input", message: "There's only one device", style: .info); return
            }
            guard AudioDevices.setDefault(next.id, output: output) else { throw PluginError.executionFailed("Couldn't switch to \(next.name)") }
            context.showNotification(title: output ? "Sound output" : "Sound input", message: next.name, style: .success)
        default: throw PluginError.actionNotFound(action.id)
        }
    }
}
