import Cocoa
import MouseGestures

/// Clipboard history + helpers. A background service watches the general pasteboard (text only) and keeps
/// the last few clips in memory; "Clipboard History Menu" pops them up at the pointer.
@objc(ClipboardPlugin)
public final class ClipboardPlugin: NSObject, GestureActionPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.clipboard" }
    public var name: String { "Clipboard & Capture" }
    public override var description: String { "Clipboard history, paste previous, collect and clean" }
    public var version: String { "1.1.0" }
    public var author: String { "MouseGestures" }
    public var category: ActionCategory { .productivity }
    public var isExternal: Bool = false
    public var icon: NSImage? { NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: nil) }

    private var host: PluginHost?
    private var history = ClipHistory()
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount
    private let lock = NSLock()

    // MARK: settings

    public var settingsFields: [PluginSettingField] { clipboardFields + CaptureActions.settingsFields }
    private var clipboardFields: [PluginSettingField] {[
        PluginSettingField(key: "size", title: "Clips to remember", kind: .number(min: 5, max: 100, step: 5, unit: nil), defaultValue: AnyCodable(20)),
        PluginSettingField(key: "ignoreApps", title: "Never record from these apps", kind: .text(placeholder: "bundle ids, comma separated"),
                           defaultValue: AnyCodable("com.1password.1password,com.agilebits.onepassword7,com.bitwarden.desktop,com.apple.keychainaccess,org.keepassxc.keepassxc"),
                           help: "Anything copied while one of these is frontmost is skipped. Clips marked concealed by a password manager are always skipped."),
        PluginSettingField(key: "info", title: "Privacy", kind: .info, help: "History lives in memory only and is gone when MouseGestures quits. Only plain text is kept."),
    ]}
    public func pluginAttached(host: PluginHost) { self.host = host }
    public func pluginDetached() { timer?.invalidate(); timer = nil; host = nil }
    public func settingChanged(key: String, value: Any?) {
        if key == "size" { lock.lock(); history.setLimit(Int(host?.number("size", default: 20) ?? 20)); lock.unlock() }
    }

    // MARK: service — watch the pasteboard

    public var runsBackgroundService: Bool { true }

    public func startService() throws {
        lastChange = NSPasteboard.general.changeCount
        lock.lock(); history.setLimit(Int(host?.number("size", default: 20) ?? 20)); lock.unlock()
        record()   // whatever is on the clipboard now counts as the first clip
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stopService() { timer?.invalidate(); timer = nil }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        record()
    }

    private func record() {
        let pb = NSPasteboard.general
        let types = (pb.types ?? []).map { $0.rawValue }
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") || types.contains("com.agilebits.onepassword") { return }
        let ignored = (host?.string("ignoreApps") ?? "").lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased(), ignored.contains(front) { return }
        guard let text = pb.string(forType: .string) else { return }
        lock.lock(); history.add(text); lock.unlock()
    }

    private func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return history.items }

    // MARK: actions

    public var providedActions: [PluginAction] { clipboardActions + CaptureActions.actions }
    private var clipboardActions: [PluginAction] {[
        PluginAction(id: "show_history", name: "Clipboard History Menu", description: "Pop up recent clips at the pointer and paste the one you pick", icon: "list.clipboard"),
        PluginAction(id: "paste_previous", name: "Paste Previous Clip", description: "Paste the clip copied before the current one (or the Nth most recent)",
                     supportedParameters: [ParameterDefinition(key: "position", name: "Position", type: .number, defaultValue: AnyCodable(2),
                                                               description: "1 = current clipboard, 2 = the one before…", validation: ValidationRule(minValue: 1, maxValue: 100))],
                     icon: "arrow.uturn.backward"),
        PluginAction(id: "collect_selection", name: "Collect Selection", description: "Add the selected text to the end of the clipboard instead of replacing it",
                     supportedParameters: [ParameterDefinition(key: "separator", name: "Separator", type: .selection, defaultValue: AnyCodable("newline"), description: "Between clips",
                                                               validation: ValidationRule(allowedValues: ["newline", "blank_line", "space", "comma"].map { AnyCodable($0) }),
                                                               displayValues: ["newline": "New line", "blank_line": "Blank line", "space": "Space", "comma": "Comma"])],
                     icon: "text.append"),
        PluginAction(id: "copy_plain", name: "Make Clipboard Plain Text", description: "Strip formatting from what's on the clipboard", icon: "doc.plaintext"),
        PluginAction(id: "clear_clipboard", name: "Clear Clipboard", description: "Empty the clipboard now", icon: "xmark.bin"),
        PluginAction(id: "clear_history", name: "Clear Clipboard History", description: "Forget every remembered clip", icon: "trash"),
    ]}

    public func initialize(context: PluginContext) throws {}
    public func cleanup() {}
    public func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult { .valid }

    public func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "show_history":
            let items = snapshot()
            guard !items.isEmpty else { context.showNotification(title: "Clipboard", message: "Nothing copied yet", style: .info); return }
            DispatchQueue.main.async { self.popUp(items, context: context) }
        case "paste_previous":
            let pos = max(1, Int(parameters.number(for: "position") ?? 2))
            let items = snapshot()
            guard pos <= items.count else { throw PluginError.executionFailed("Only \(items.count) clip\(items.count == 1 ? "" : "s") remembered") }
            paste(items[pos - 1], context)
        case "collect_selection":
            let sep = ["newline": "\n", "blank_line": "\n\n", "space": " ", "comma": ", "][parameters.string(for: "separator") ?? "newline"] ?? "\n"
            let pb = NSPasteboard.general
            let existing = pb.string(forType: .string) ?? ""
            let before = pb.changeCount
            context.sendKeyboardShortcut(keyCode: 8, modifiers: .maskCommand)
            let deadline = Date().addingTimeInterval(0.6)
            while pb.changeCount == before, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            guard pb.changeCount != before, let picked = pb.string(forType: .string) else { throw PluginError.executionFailed("No text is selected") }
            let combined = existing.isEmpty ? picked : existing + sep + picked
            pb.clearContents(); pb.setString(combined, forType: .string)
            context.showNotification(title: "Collected", message: "\(combined.components(separatedBy: "\n").count) lines on the clipboard", style: .success)
        case "copy_plain":
            guard let text = NSPasteboard.general.string(forType: .string) else { throw PluginError.executionFailed("The clipboard has no text") }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        case "clear_clipboard":
            NSPasteboard.general.clearContents()
        case "clear_history":
            lock.lock(); history.clear(); lock.unlock()
            context.showNotification(title: "Clipboard", message: "History cleared", style: .info)
        default:
            guard CaptureActions.ids.contains(action.id) else { throw PluginError.actionNotFound(action.id) }
            try CaptureActions.execute(action, with: parameters, context: context, settings: host)
        }
    }

    // MARK: paste + menu

    private func paste(_ text: String, _ context: PluginContext) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        lastChange = NSPasteboard.general.changeCount       // our own write isn't a new clip
        lock.lock(); history.add(text); lock.unlock()
        context.sendKeyboardShortcut(keyCode: 9, modifiers: .maskCommand)
    }

    private var menuContext: PluginContext?
    private var menuItems: [String] = []

    private func popUp(_ items: [String], context: PluginContext) {
        menuContext = context; menuItems = items
        let menu = NSMenu(title: "Clipboard History")
        menu.autoenablesItems = false
        for (i, text) in items.prefix(30).enumerated() {
            let item = NSMenuItem(title: ClipHistory.label(text), action: #selector(picked(_:)), keyEquivalent: i < 9 ? String(i + 1) : "")
            item.keyEquivalentModifierMask = []
            item.target = self; item.tag = i
            item.toolTip = String(text.prefix(300))
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear History", action: #selector(clearTapped), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        let frontApp = NSWorkspace.shared.frontmostApplication
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)     // returns after the menu closes
        // the chosen item's action ran during popUp; make sure the original app is frontmost for the paste
        if pendingPaste != nil { frontApp?.activate(options: []); }
        if let text = pendingPaste {
            pendingPaste = nil
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard let self = self, let ctx = self.menuContext else { return }
                self.paste(text, ctx)
            }
        }
    }

    private var pendingPaste: String?
    @objc private func picked(_ item: NSMenuItem) { if item.tag < menuItems.count { pendingPaste = menuItems[item.tag] } }
    @objc private func clearTapped() { lock.lock(); history.clear(); lock.unlock() }
}
