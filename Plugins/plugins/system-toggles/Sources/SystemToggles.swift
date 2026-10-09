import Cocoa
import MouseGestures

@objc(SystemTogglesPlugin)
public final class SystemTogglesPlugin: NSObject, GestureActionPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.systemtoggles" }
    public var name: String { "System Toggles" }
    public override var description: String { "Quick system switches" }
    public var version: String { "1.4.0" }
    public var author: String { "MouseGestures" }
    public var category: ActionCategory { .system }
    public var isExternal: Bool = false
    public var icon: NSImage? { NSImage(systemSymbolName: "switch.2", accessibilityDescription: nil) }

    private var settings: PluginHost?
    public var settingsFields: [PluginSettingField] { [] }
    public func pluginAttached(host: PluginHost) { settings = host }
    public func pluginDetached() { settings = nil }

    public var providedActions: [PluginAction] {[
        PluginAction(id: "toggle_dock_autohide", name: "Toggle Dock Auto-Hide", description: "Show or hide the Dock automatically", icon: "dock.rectangle"),
        PluginAction(id: "toggle_stage_manager", name: "Toggle Stage Manager", description: "Turn Stage Manager on or off", icon: "rectangle.3.group"),
        PluginAction(id: "toggle_keep_awake", name: "Toggle Keep Awake", description: "Prevent the Mac from sleeping until toggled off", icon: "cup.and.saucer"),
        PluginAction(id: "toggle_wifi", name: "Toggle Wi-Fi", description: "Turn Wi-Fi on or off", icon: "wifi"),
        PluginAction(id: "toggle_mic_mute", name: "Toggle Microphone Mute", description: "Mute or restore the system input volume", icon: "mic.slash"),
        PluginAction(id: "cycle_audio_output", name: "Next Sound Output", description: "Switch to the next speakers / headphones / AirPlay output", icon: "hifispeaker.2"),
        PluginAction(id: "cycle_audio_input", name: "Next Sound Input", description: "Switch to the next microphone", icon: "mic"),
        PluginAction(id: "screen_saver", name: "Start Screen Saver", description: "Start the screen saver now", icon: "sparkles.tv"),
    ]}

    public func initialize(context: PluginContext) throws {}
    public func cleanup() {}
    public func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult { .valid }

    public func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "toggle_dock_autohide":
            try context.executeAppleScript("tell application \"System Events\" to tell dock preferences to set autohide to not autohide")
        case "toggle_stage_manager":
            let on = (try? capture("/usr/bin/defaults", ["read", "com.apple.WindowManager", "GloballyEnabled"]))?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
            try run("/usr/bin/defaults", ["write", "com.apple.WindowManager", "GloballyEnabled", "-bool", on ? "false" : "true"])
            try run("/usr/bin/killall", ["Dock"])
        case "toggle_keep_awake":
            if let p = Self.awakeProcess, p.isRunning {
                p.terminate(); Self.awakeProcess = nil
                context.showNotification(title: "Keep Awake off", message: "Your Mac can sleep again", style: .info)
            } else {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
                p.arguments = ["-dims"]
                try p.run()
                Self.awakeProcess = p
                context.showNotification(title: "Keep Awake on", message: "Your Mac won't sleep until you toggle this off", style: .success)
            }
        case "toggle_wifi":
            let dev = try wifiDevice()
            let on = try capture("/usr/sbin/networksetup", ["-getairportpower", dev]).contains(": On")
            try run("/usr/sbin/networksetup", ["-setairportpower", dev, on ? "off" : "on"])
        case "toggle_mic_mute":
            let vol = Int(try capture("/usr/bin/osascript", ["-e", "input volume of (get volume settings)"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            if vol > 0 {
                settings?.setSetting("micVolumeBeforeMute", to: vol)
                try run("/usr/bin/osascript", ["-e", "set volume input volume 0"])
            } else {
                let back = Int(settings?.number("micVolumeBeforeMute", default: 75) ?? 75)
                try run("/usr/bin/osascript", ["-e", "set volume input volume \(max(back, 1))"])
            }
        case "cycle_audio_output", "cycle_audio_input":
            let output = action.id == "cycle_audio_output"
            let list = AudioDevices.devices(output: output)
            guard let next = AudioDevices.next(after: AudioDevices.defaultDevice(output: output), in: list) else {
                context.showNotification(title: output ? "Sound output" : "Sound input", message: "There's only one device", style: .info); return
            }
            guard AudioDevices.setDefault(next.id, output: output) else { throw PluginError.executionFailed("Couldn't switch to \(next.name)") }
            context.showNotification(title: output ? "Sound output" : "Sound input", message: next.name, style: .success)
        case "screen_saver":
            try run("/usr/bin/open", ["-a", "ScreenSaverEngine"])
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    private static var awakeProcess: Process?

    private func wifiDevice() throws -> String {
        let out = try capture("/usr/sbin/networksetup", ["-listallhardwareports"])
        var sawWiFi = false
        for line in out.components(separatedBy: "\n") {
            if line.contains("Hardware Port: Wi-Fi") { sawWiFi = true }
            else if sawWiFi, line.hasPrefix("Device:") { return line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces) }
        }
        throw PluginError.executionFailed("No Wi-Fi interface found")
    }

    @discardableResult private func capture(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw PluginError.executionFailed("\(tool) failed (\(p.terminationStatus))") }
        return String(decoding: data, as: UTF8.self)
    }

    private func run(_ tool: String, _ args: [String]) throws { _ = try capture(tool, args) }
}
