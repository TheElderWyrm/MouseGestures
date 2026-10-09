import Cocoa

/// System switches that live inside the built-in System Control plugin: Dock auto-hide, Stage Manager,
/// keep awake, Wi-Fi, microphone mute, screen saver.
enum SystemSwitchActions {
    static let actions: [PluginAction] = [
        PluginAction(id: "toggle_dock_autohide", name: "Toggle Dock Auto-Hide", description: "Show or hide the Dock automatically", icon: "dock.rectangle"),
        PluginAction(id: "toggle_stage_manager", name: "Toggle Stage Manager", description: "Turn Stage Manager on or off", icon: "rectangle.3.group"),
        PluginAction(id: "toggle_keep_awake", name: "Toggle Keep Awake", description: "Prevent the Mac from sleeping until toggled off", icon: "cup.and.saucer"),
        PluginAction(id: "toggle_wifi", name: "Toggle Wi-Fi", description: "Turn Wi-Fi on or off", icon: "wifi"),
        PluginAction(id: "toggle_mic_mute", name: "Toggle Microphone Mute", description: "Mute or restore the system input volume", icon: "mic.slash"),
        PluginAction(id: "screen_saver", name: "Start Screen Saver", description: "Start the screen saver now", icon: "sparkles.tv"),
    ]

    static let ids: Set<String> = Set(actions.map { $0.id })

    static func execute(_ action: PluginAction, with parameters: ActionParameters, context: PluginContext, settings: PluginHost?) throws {
        switch action.id {
        case "toggle_dock_autohide":
            try context.executeAppleScript("tell application \"System Events\" to tell dock preferences to set autohide to not autohide")
        case "toggle_stage_manager":
            let on = (try? capture("/usr/bin/defaults", ["read", "com.apple.WindowManager", "GloballyEnabled"]))?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
            try Self.run("/usr/bin/defaults", ["write", "com.apple.WindowManager", "GloballyEnabled", "-bool", on ? "false" : "true"])
            try Self.run("/usr/bin/killall", ["Dock"])
        case "toggle_keep_awake":
            if let p = awakeProcess, p.isRunning {
                p.terminate(); awakeProcess = nil
                context.showNotification(title: "Keep Awake off", message: "Your Mac can sleep again", style: .info)
            } else {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
                p.arguments = ["-dims"]
                try p.run()
                awakeProcess = p
                context.showNotification(title: "Keep Awake on", message: "Your Mac won't sleep until you toggle this off", style: .success)
            }
        case "toggle_wifi":
            let dev = try Self.wifiDevice()
            let on = try Self.capture("/usr/sbin/networksetup", ["-getairportpower", dev]).contains(": On")
            try Self.run("/usr/sbin/networksetup", ["-setairportpower", dev, on ? "off" : "on"])
        case "toggle_mic_mute":
            let vol = Int(try Self.capture("/usr/bin/osascript", ["-e", "input volume of (get volume settings)"]).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            if vol > 0 {
                settings?.setSetting("micVolumeBeforeMute", to: vol)
                try Self.run("/usr/bin/osascript", ["-e", "set volume input volume 0"])
            } else {
                let back = Int(settings?.number("micVolumeBeforeMute", default: 75) ?? 75)
                try Self.run("/usr/bin/osascript", ["-e", "set volume input volume \(max(back, 1))"])
            }
        case "screen_saver":
            try Self.run("/usr/bin/open", ["-a", "ScreenSaverEngine"])
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    private static var awakeProcess: Process?

    private static func wifiDevice() throws -> String {
        let out = try capture("/usr/sbin/networksetup", ["-listallhardwareports"])
        var sawWiFi = false
        for line in out.components(separatedBy: "\n") {
            if line.contains("Hardware Port: Wi-Fi") { sawWiFi = true }
            else if sawWiFi, line.hasPrefix("Device:") { return line.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces) }
        }
        throw PluginError.executionFailed("No Wi-Fi interface found")
    }

    @discardableResult private static func capture(_ tool: String, _ args: [String]) throws -> String {
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

    private static func run(_ tool: String, _ args: [String]) throws { _ = try capture(tool, args) }
}
