import Cocoa
import MouseGestures

@objc(QuickLaunchPlugin)
public final class QuickLaunchPlugin: NSObject, GestureActionPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.quicklaunch" }
    public var name: String { "Web Tools" }
    public override var description: String { "Web search, dictionary lookup and browser page links" }
    public var version: String { "1.2.0" }
    public var author: String { "MouseGestures" }
    public var category: ActionCategory { .productivity }
    public var isExternal: Bool = false
    public var icon: NSImage? { NSImage(systemSymbolName: "bolt.horizontal", accessibilityDescription: nil) }

    private static let engines: [String: (String, String)] = [
        "google": ("Google", "https://www.google.com/search?q=%s"),
        "duckduckgo": ("DuckDuckGo", "https://duckduckgo.com/?q=%s"),
        "wikipedia": ("Wikipedia", "https://en.wikipedia.org/w/index.php?search=%s"),
        "youtube": ("YouTube", "https://www.youtube.com/results?search_query=%s"),
        "maps": ("Apple Maps", "https://maps.apple.com/?q=%s"),
    ]

    private var settings: PluginHost?
    public var settingsFields: [PluginSettingField] {[
        PluginSettingField(key: "defaultEngine", title: "Default search engine",
                           kind: .choice(Self.engines.keys.sorted().map { PluginSettingChoice($0, Self.engines[$0]!.0) }),
                           defaultValue: AnyCodable("google"), help: "Used by \"Search Selection\" when the gesture doesn't pick one."),
        PluginSettingField(key: "customTemplate", title: "Custom search URL", kind: .text(placeholder: "https://example.com/?q=%s"),
                           help: "Optional. Overrides the engine; %s is replaced by the selected text."),
    ]}
    public func pluginAttached(host: PluginHost) { settings = host }
    public func pluginDetached() { settings = nil }

    public var providedActions: [PluginAction] {[
        PluginAction(id: "search_selection", name: "Search Selection on the Web", description: "Search the selected text",
                     requiresParameters: true,
                     supportedParameters: [ParameterDefinition(
                        key: "engine", name: "Search engine", type: .selection, defaultValue: AnyCodable("google"),
                        description: "Where to search",
                        validation: ValidationRule(allowedValues: Self.engines.keys.sorted().map { AnyCodable($0) }),
                        displayValues: Dictionary(uniqueKeysWithValues: Self.engines.map { ($0.key, $0.value.0) }))],
                     icon: "magnifyingglass"),
        PluginAction(id: "open_clipboard_url", name: "Open URL from Clipboard", description: "Open the web address on the clipboard", icon: "doc.on.clipboard"),
        PluginAction(id: "open_selection_url", name: "Open Selected Link", description: "Open the selected text as a web address", icon: "link.badge.plus"),
        PluginAction(id: "search_clipboard", name: "Search Clipboard on the Web", description: "Search the text on the clipboard",
                     requiresParameters: true,
                     supportedParameters: [ParameterDefinition(
                        key: "engine", name: "Search engine", type: .selection, defaultValue: AnyCodable("google"),
                        description: "Where to search",
                        validation: ValidationRule(allowedValues: Self.engines.keys.sorted().map { AnyCodable($0) }),
                        displayValues: Dictionary(uniqueKeysWithValues: Self.engines.map { ($0.key, $0.value.0) }))],
                     icon: "doc.text.magnifyingglass"),
        PluginAction(id: "define_selection", name: "Look Up in Dictionary", description: "Define the selected text in the Dictionary app", icon: "character.book.closed"),
        PluginAction(id: "copy_page_url", name: "Copy Page URL", description: "Copy the address of the front browser tab (Safari, Chrome, Brave, Edge, Opera, Vivaldi, Arc)", icon: "link"),
        PluginAction(id: "copy_page_markdown", name: "Copy Page as Markdown Link", description: "Copy [title](url) for the front browser tab", icon: "text.badge.plus"),
    ]}

    public func initialize(context: PluginContext) throws {}
    public func cleanup() {}
    public func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult { .valid }

    public func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        switch action.id {
        case "search_selection":
            try search(Self.copySelection(context), parameters: parameters)
        case "search_clipboard":
            guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw PluginError.executionFailed("The clipboard has no text")
            }
            try search(text, parameters: parameters)
        case "open_selection_url":
            guard let url = Self.webURL(try Self.copySelection(context)) else { throw PluginError.executionFailed("The selection isn't a web address") }
            NSWorkspace.shared.open(url)
        case "define_selection":
            let text = try Self.copySelection(context)
            let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            guard let url = URL(string: "dict://\(q)") else { throw PluginError.executionFailed("Can't look that up") }
            NSWorkspace.shared.open(url)
        case "copy_page_url", "copy_page_markdown":
            let (title, url) = try Self.frontPage()
            let out = action.id == "copy_page_url" ? url : "[\(title.replacingOccurrences(of: "]", with: "\\]"))](\(url))"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(out, forType: .string)
            context.showNotification(title: "Copied", message: out, style: .success)
        case "open_clipboard_url":
            guard let url = Self.webURL(NSPasteboard.general.string(forType: .string)) else { throw PluginError.executionFailed("Clipboard doesn't hold a web address") }
            NSWorkspace.shared.open(url)
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    private func search(_ text: String, parameters: ActionParameters) throws {
        let custom = settings?.string("customTemplate") ?? ""
        let engine = parameters.string(for: "engine") ?? settings?.string("defaultEngine", default: "google") ?? "google"
        let template = custom.contains("%s") ? custom : (Self.engines[engine]?.1 ?? Self.engines["google"]!.1)
        let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#"))) ?? text
        if let url = URL(string: template.replacingOccurrences(of: "%s", with: q)) { NSWorkspace.shared.open(url) }
    }

    /// Copies the current selection and returns it (leaves it on the clipboard).
    static func copySelection(_ context: PluginContext) throws -> String {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        context.sendKeyboardShortcut(keyCode: 8, modifiers: .maskCommand)
        let deadline = Date().addingTimeInterval(0.6)
        while pb.changeCount == before, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        guard pb.changeCount != before, let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw PluginError.executionFailed("No text is selected")
        }
        return text
    }

    /// Title and URL of the front tab in whichever supported browser is frontmost.
    static func frontPage() throws -> (String, String) {
        guard let app = NSWorkspace.shared.frontmostApplication, let name = app.localizedName else { throw PluginError.executionFailed("No front app") }
        let script: String
        switch app.bundleIdentifier ?? "" {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            script = "tell application \"\(name)\" to return (name of current tab of front window) & linefeed & (URL of current tab of front window)"
        case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera":
            script = "tell application \"\(name)\" to return (title of active tab of front window) & linefeed & (URL of active tab of front window)"
        default: throw PluginError.executionFailed("\(name) isn't a supported browser")
        }
        var err: NSDictionary?
        guard let r = NSAppleScript(source: script)?.executeAndReturnError(&err).stringValue else {
            throw PluginError.executionFailed("AppleScript: \(err?[NSAppleScript.errorMessage] ?? "failed")")
        }
        let parts = r.components(separatedBy: "\n")
        guard parts.count >= 2, !parts[1].isEmpty else { throw PluginError.executionFailed("No page is open") }
        return (parts[0], parts[1])
    }

    static func webURL(_ s: String?) -> URL? {
        guard var t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, !t.contains(" ") else { return nil }
        if !t.contains("://") { t = "https://" + t }
        guard let u = URL(string: t), ["http", "https"].contains(u.scheme?.lowercased() ?? ""), (u.host ?? "").contains(".") else { return nil }
        return u
    }
}
