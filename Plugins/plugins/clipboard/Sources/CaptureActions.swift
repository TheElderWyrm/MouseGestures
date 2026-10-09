import Cocoa
import MouseGestures

/// Quick Capture actions (inbox file, note files, Reminders, Apple Notes) inside the Clipboard & Capture plugin.
enum CaptureActions {
    private static let fromClipboard = ParameterDefinition(key: "useClipboard", name: "Capture the clipboard instead of the selection", type: .boolean,
                                                           defaultValue: AnyCodable(false), description: "Off = copy the current selection first")

    static let settingsFields: [PluginSettingField] = [
        PluginSettingField(key: "inbox", title: "Inbox file", kind: .path(directoriesOnly: false), defaultValue: AnyCodable("~/Documents/Inbox.md"),
                           help: "“Add to Inbox File” appends here (created if missing)."),
        PluginSettingField(key: "notesFolder", title: "Note files folder", kind: .path(directoriesOnly: true), defaultValue: AnyCodable("~/Documents/Notes"),
                           help: "“Save as New Note File” creates one Markdown file per capture here."),
        PluginSettingField(key: "includeSource", title: "Note which app it came from", kind: .toggle, defaultValue: AnyCodable(true)),
        PluginSettingField(key: "info", title: "Reminders and Notes", kind: .info,
                           help: "The first time you add to Reminders or Notes, macOS asks whether MouseGestures may control them (System Settings ▸ Privacy & Security ▸ Automation)."),
        PluginSettingField(key: "restoreClipboard", title: "Restore the clipboard afterwards", kind: .toggle, defaultValue: AnyCodable(true),
                           help: "Capturing a selection copies it first; this puts your previous clipboard back."),
    ]

    static let actions: [PluginAction] = [
        PluginAction(id: "append_inbox", name: "Add to Inbox File", description: "Append the selection to your inbox file",
                     supportedParameters: [ParameterDefinition(key: "style", name: "Format", type: .selection, defaultValue: AnyCodable("bullet"), description: "How the entry looks",
                                                               validation: ValidationRule(allowedValues: CaptureFormat.styles.map { AnyCodable($0.id) }),
                                                               displayValues: Dictionary(uniqueKeysWithValues: CaptureFormat.styles.map { ($0.id, $0.label) })), Self.fromClipboard],
                     icon: "tray.and.arrow.down"),
        PluginAction(id: "new_note_file", name: "Save as New Note File", description: "Create a Markdown file for the selection",
                     supportedParameters: [ParameterDefinition(key: "open", name: "Open it afterwards", type: .boolean, defaultValue: AnyCodable(false), description: "Open the new file"), Self.fromClipboard],
                     icon: "doc.badge.plus"),
        PluginAction(id: "add_reminder", name: "Add to Reminders", description: "Make a reminder from the selection (first line = title)",
                     supportedParameters: [ParameterDefinition(key: "list", name: "List", type: .string, description: "Reminders list (blank = default list)"),
                                           ParameterDefinition(key: "inMinutes", name: "Remind me in (minutes)", type: .number, description: "Blank = no alert time", validation: ValidationRule(minValue: 1, maxValue: 525600)), Self.fromClipboard],
                     icon: "checklist"),
        PluginAction(id: "add_apple_note", name: "Add to Apple Notes", description: "Create a note from the selection (first line = title)",
                     supportedParameters: [ParameterDefinition(key: "folder", name: "Folder", type: .string, description: "Notes folder (blank = Notes)"), Self.fromClipboard],
                     icon: "note.text.badge.plus"),
        PluginAction(id: "open_inbox", name: "Open Inbox File", description: "Open the inbox file", icon: "tray.full"),
    ]

    static let ids: Set<String> = Set(actions.map { $0.id })

    static func execute(_ action: PluginAction, with parameters: ActionParameters, context: PluginContext, settings: PluginHost?) throws {
        let fm = FileManager.default
        func path(_ key: String, _ def: String) -> String { ((settings?.string(key, default: def) ?? def) as NSString).expandingTildeInPath }
        if action.id == "open_inbox" {
            let p = path("inbox", "~/Documents/Inbox.md")
            guard fm.fileExists(atPath: p) else { throw PluginError.executionFailed("The inbox doesn't exist yet") }
            NSWorkspace.shared.open(URL(fileURLWithPath: p)); return
        }
        let text = try captured(parameters, context, settings)
        let source = (settings?.bool("includeSource", default: true) ?? true) ? context.getFrontmostApplication()?.localizedName : nil
        let now = Date()

        switch action.id {
        case "append_inbox":
            let p = path("inbox", "~/Documents/Inbox.md")
            let entry = CaptureFormat.entry(text, style: parameters.string(for: "style") ?? "bullet", date: now, source: source)
            try fm.createDirectory(atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            var existing = (try? String(contentsOfFile: p, encoding: .utf8)) ?? ""
            if !existing.isEmpty, !existing.hasSuffix("\n") { existing += "\n" }
            try (existing + entry + "\n").write(toFile: p, atomically: true, encoding: .utf8)
            context.showNotification(title: "Added to inbox", message: String(text.prefix(80)), style: .success)
        case "new_note_file":
            let dir = path("notesFolder", "~/Documents/Notes")
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let file = (dir as NSString).appendingPathComponent(CaptureFormat.noteFileName(text, date: now))
            let (title, body) = CaptureFormat.titleAndBody(text)
            let content = "# \(title)\n\n" + (body.isEmpty ? "" : body + "\n\n") + (source.map { "_From \($0), \(CaptureFormat.stamp(now))_\n" } ?? "")
            try content.write(toFile: file, atomically: true, encoding: .utf8)
            if parameters.bool(for: "open") ?? false { NSWorkspace.shared.open(URL(fileURLWithPath: file)) }
            context.showNotification(title: "Note saved", message: (file as NSString).lastPathComponent, style: .success)
        case "add_reminder":
            let (title, body) = CaptureFormat.titleAndBody(text)
            let list = (parameters.string(for: "list") ?? "").trimmingCharacters(in: .whitespaces)
            var props = "name:\"\(CaptureFormat.appleScriptString(title))\", body:\"\(CaptureFormat.appleScriptString(body))\""
            if let m = parameters.number(for: "inMinutes") { props += ", remind me date:((current date) + \(Int(m * 60)))" }
            let target = list.isEmpty ? "default list" : "list \"\(CaptureFormat.appleScriptString(list))\""
            try context.executeAppleScript("tell application \"Reminders\" to make new reminder at end of \(target) with properties {\(props)}")
            context.showNotification(title: "Reminder added", message: title, style: .success)
        case "add_apple_note":
            let (title, body) = CaptureFormat.titleAndBody(text)
            let folder = (parameters.string(for: "folder") ?? "").trimmingCharacters(in: .whitespaces)
            let html = "<h1>\(CaptureFormat.appleScriptString(escapeHTML(title)))</h1><div>" + CaptureFormat.appleScriptString(escapeHTML(body)).replacingOccurrences(of: "\n", with: "<br>") + "</div>"
            let at = folder.isEmpty ? "" : " at folder \"\(CaptureFormat.appleScriptString(folder))\""
            try context.executeAppleScript("tell application \"Notes\" to make new note\(at) with properties {body:\"\(html)\"}")
            context.showNotification(title: "Note added", message: title, style: .success)
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    /// The text to capture: the clipboard, or the current selection (copied, then the clipboard is put back).
    private static func captured(_ parameters: ActionParameters, _ context: PluginContext, _ settings: PluginHost?) throws -> String {
        let pb = NSPasteboard.general
        if parameters.bool(for: "useClipboard") ?? false {
            guard let t = pb.string(forType: .string), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PluginError.executionFailed("The clipboard has no text") }
            return t
        }
        let saved: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } }
        let before = pb.changeCount
        context.sendKeyboardShortcut(keyCode: 8, modifiers: .maskCommand)
        let deadline = Date().addingTimeInterval(0.6)
        while pb.changeCount == before, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        guard pb.changeCount != before, let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PluginError.executionFailed("No text is selected")
        }
        if settings?.bool("restoreClipboard", default: true) ?? true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                pb.clearContents()
                for entries in saved { let item = NSPasteboardItem(); for (t, d) in entries { item.setData(d, forType: t) }; pb.writeObjects([item]) }
            }
        }
        return text
    }
}
