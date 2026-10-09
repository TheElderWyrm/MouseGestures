import Cocoa
import MouseGestures

@objc(FinderHelpersPlugin)
public final class FinderHelpersPlugin: NSObject, GestureActionPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.finderhelpers" }
    public var name: String { "Finder Helpers" }
    public override var description: String { "Finder and desktop: copy paths, Terminal here, hidden files, desktop icons, eject disks" }
    public var version: String { "1.3.0" }
    public var author: String { "MouseGestures" }
    public var category: ActionCategory { .file }
    public var isExternal: Bool = false
    public var icon: NSImage? { NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: nil) }

    private var settings: PluginHost?
    public var settingsFields: [PluginSettingField] {[
        PluginSettingField(key: "terminalApp", title: "Terminal application",
                           kind: .choice([PluginSettingChoice("Terminal", "Terminal"), PluginSettingChoice("iTerm", "iTerm"),
                                          PluginSettingChoice("Ghostty", "Ghostty"), PluginSettingChoice("Warp", "Warp")]),
                           defaultValue: AnyCodable("Terminal"), help: "Used by \"Open Terminal Here\"."),
        PluginSettingField(key: "notifyOnCopy", title: "Show a notification after copying a path", kind: .toggle, defaultValue: AnyCodable(true)),
    ]}
    public func pluginAttached(host: PluginHost) { settings = host }
    public func pluginDetached() { settings = nil }

    public var providedActions: [PluginAction] {[
        PluginAction(id: "copy_path", name: "Copy Path of Selection", description: "Copy the POSIX path(s) of the selected Finder items", icon: "doc.on.doc"),
        PluginAction(id: "terminal_here", name: "Open Terminal Here", description: "Open Terminal at the front Finder window's folder", icon: "terminal"),
        PluginAction(id: "new_window", name: "New Finder Window", description: "Open a new Finder window at your home folder", icon: "macwindow.badge.plus"),
        PluginAction(id: "toggle_desktop_icons", name: "Toggle Desktop Icons", description: "Hide or show every icon on the desktop (clean screen for sharing)", icon: "rectangle.dashed"),
        PluginAction(id: "eject_all_disks", name: "Eject All Disks", description: "Eject every external disk and disk image", icon: "eject"),
        PluginAction(id: "show_hidden", name: "Toggle Hidden Files", description: "Show or hide hidden files in Finder (switches to Finder first)", icon: "eye"),
    ]}

    public func initialize(context: PluginContext) throws {}
    public func cleanup() {}
    public func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult { .valid }

    public func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "copy_path":
            let out = try Self.osascript("""
            tell application "Finder"
              set sel to selection as alias list
              if sel is {} then set sel to {(target of front window) as alias}
              set paths to {}
              repeat with f in sel
                set end of paths to POSIX path of f
              end repeat
              set AppleScript's text item delimiters to linefeed
              return paths as text
            end tell
            """)
            guard !out.isEmpty else { throw PluginError.executionFailed("Nothing selected in Finder") }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(out, forType: .string)
            if settings?.bool("notifyOnCopy", default: true) ?? true { context.showNotification(title: "Path copied", message: out, style: .success) }
        case "terminal_here":
            let path = try Self.osascript("tell application \"Finder\" to return POSIX path of (target of front window as alias)")
            guard !path.isEmpty else { throw PluginError.executionFailed("No Finder window is open") }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", settings?.string("terminalApp", default: "Terminal") ?? "Terminal", path]
            try p.run()
        case "new_window":
            try context.executeAppleScript("tell application \"Finder\"\n make new Finder window to home\n activate\nend tell")
        case "show_hidden":
            // The shortcut only works in Finder, so bring it forward first.
            try context.executeAppleScript("tell application \"Finder\" to activate")
            Thread.sleep(forTimeInterval: 0.25)
            context.sendKeyboardShortcut(keyCode: 47, modifiers: [.maskCommand, .maskShift]) // ⌘⇧.
        case "toggle_desktop_icons":
            let on = (try? Self.capture("/usr/bin/defaults", ["read", "com.apple.finder", "CreateDesktop"]))?.trimmingCharacters(in: .whitespacesAndNewlines) != "0"
            _ = try Self.capture("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", on ? "false" : "true"])
            _ = try Self.capture("/usr/bin/killall", ["Finder"])
        case "eject_all_disks":
            try context.executeAppleScript("tell application \"Finder\" to eject (every disk whose ejectable is true)")
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    private static func capture(_ tool: String, _ args: [String]) throws -> String {
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

    private static func osascript(_ source: String) throws -> String {
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw PluginError.executionFailed("Bad script") }
        let result = script.executeAndReturnError(&err)
        if let err = err { throw PluginError.executionFailed("AppleScript: \(err[NSAppleScript.errorMessage] ?? "failed")") }
        return result.stringValue ?? ""
    }
}
