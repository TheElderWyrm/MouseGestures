import Cocoa
import MouseGestures

/// Text management: change case, clean up, edit lines, wrap, Markdown, encode/decode, JSON, calculate, insert snippets.
/// Everything works on the current selection (copied, transformed and pasted back) or, if
/// "Apply to selected text" is off, on the clipboard alone. The transformations live in TextOps.swift.
@objc(TextToolsPlugin)
public final class TextToolsPlugin: NSObject, GestureActionPlugin, PluginExtension {
    public var identifier: String { "com.mousegestures.lib.texttools" }
    public var name: String { "Text" }
    public override var description: String { "Format, clean up, convert and insert text" }
    public var version: String { "2.1.0" }
    public var author: String { "MouseGestures" }
    public var category: ActionCategory { .productivity }
    public var isExternal: Bool = false
    public var icon: NSImage? { NSImage(systemSymbolName: "textformat", accessibilityDescription: nil) }

    private var context: PluginContext?
    private var settings: PluginHost?
    private var restoreClipboard: Bool { settings?.bool("restoreClipboard", default: true) ?? true }

    public var settingsFields: [PluginSettingField] {[
        PluginSettingField(key: "restoreClipboard", title: "Restore the clipboard afterwards", kind: .toggle,
                           defaultValue: AnyCodable(true),
                           help: "Text is replaced by pasting; this puts your previous clipboard contents back afterwards."),
        PluginSettingField(key: "info", title: "Placeholders for “Insert Text”",
                           kind: .info, help: "{date} {time} {datetime} {uuid} {clipboard} are replaced when the text is inserted."),
    ]}
    public func pluginAttached(host: PluginHost) { settings = host }
    public func pluginDetached() { settings = nil }

    // MARK: actions

    private static let applyParam = ParameterDefinition(
        key: "applyToSelection", name: "Apply to selected text", type: .boolean, defaultValue: AnyCodable(true),
        description: "Copy the current selection, transform it and paste it back. Off = transform the clipboard only.")

    private static func choice(_ key: String, _ name: String, _ items: [(id: String, label: String)], _ def: String) -> ParameterDefinition {
        ParameterDefinition(key: key, name: name, type: .selection, defaultValue: AnyCodable(def), description: name,
                            validation: ValidationRule(allowedValues: items.map { AnyCodable($0.id) }),
                            displayValues: Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.label) }))
    }

    private static let modes: [(id: String, label: String)] = [("pretty", "Pretty-print"), ("minify", "Minify")]
    private static let typo: [(id: String, label: String)] = [("smart", "Curly quotes, dashes and ellipses"), ("straight", "Plain straight quotes and dashes")]
    private static let unitModes: [(id: String, label: String)] = [("replace", "Replace with the result"), ("append", "Append “= result”")]
    private static let calcModes: [(id: String, label: String)] = [("replace", "Replace with the result"), ("append", "Append “= result”")]

    public var providedActions: [PluginAction] {
        func a(_ id: String, _ name: String, _ desc: String, _ icon: String, _ params: [ParameterDefinition] = [], apply: Bool = true) -> PluginAction {
            PluginAction(id: id, name: name, description: desc, requiresParameters: !params.isEmpty && apply,
                         supportedParameters: params + (apply ? [Self.applyParam] : []), icon: icon)
        }
        return [
            a("change_case", "Change Case", "UPPER, lower, Title, Sentence, camel, snake, kebab…", "textformat.size", [Self.choice("style", "Style", TextOps.caseStyles, "upper")]),
            a("clean_text", "Clean Up Text", "Whitespace, broken lines, HTML, accents, emoji", "sparkles", [Self.choice("operation", "Clean-up", TextOps.cleanOps, "whitespace")]),
            a("sort_lines", "Sort Lines", "Sort lines A–Z, Z–A, numerically, by length", "arrow.up.arrow.down", [Self.choice("order", "Order", TextOps.sortOrders, "az")]),
            a("edit_lines", "Edit Lines", "Dedupe, reverse, shuffle, number, join, split, indent", "list.number", [Self.choice("operation", "Operation", TextOps.lineOps, "dedupe")]),
            a("prefix_suffix", "Add Prefix / Suffix", "Put text before and/or after every line", "text.alignleft",
              [ParameterDefinition(key: "prefix", name: "Prefix", type: .string, description: "Added to the start of each line"),
               ParameterDefinition(key: "suffix", name: "Suffix", type: .string, description: "Added to the end of each line")]),
            a("wrap_text", "Wrap in Quotes / Brackets", "Surround the text with quotes, brackets, backticks, bold…", "quote.opening", [Self.choice("style", "Wrap with", TextOps.wrapStyles, "double")]),
            a("markdown_format", "Markdown Format", "Lists, checklist, quote, code block, headings, link", "number.square", [Self.choice("kind", "Format", TextOps.markdownKinds, "bullets")]),
            a("encode_decode", "Encode / Decode", "URL, Base64, HTML, ROT13, reverse", "lock.rotation", [Self.choice("kind", "Conversion", TextOps.encodings, "url_encode")]),
            a("format_json", "Format JSON", "Pretty-print or minify JSON", "curlybraces", [Self.choice("mode", "Mode", Self.modes, "pretty")]),
            a("typography", "Smart / Straight Typography", "Curly vs straight quotes, dashes, ellipses", "character.cursor.ibeam", [Self.choice("mode", "Mode", Self.typo, "smart")]),
            a("slugify", "Make URL Slug", "“Hello, World!” → hello-world", "link.badge.plus"),
            a("calculate", "Calculate", "Evaluate the selected arithmetic (2+3*4)", "plus.forwardslash.minus", [Self.choice("mode", "Result", Self.calcModes, "replace")]),
            a("convert_units", "Convert Units", "“5 km to mi”, “70 F to C”, “2 lb in kg” — length, weight, temperature, volume, speed, data", "ruler", [Self.choice("mode", "Result", Self.unitModes, "replace")]),
            a("convert_timestamp", "Convert Timestamp", "Unix time ⇄ readable date", "clock.arrow.2.circlepath"),
            a("text_stats", "Count Words", "Show words, characters, lines and reading time", "number", apply: false),
            a("swap_clipboard", "Swap with Clipboard", "Paste the clipboard over the selection and keep the old selection on the clipboard", "arrow.left.arrow.right", apply: false),
            a("plain_paste", "Paste as Plain Text", "Paste the clipboard without formatting", "doc.plaintext", apply: false),
            a("insert_datetime", "Insert Date / Time", "Type the current date or time", "calendar.badge.clock",
              [Self.choice("format", "Format", TextOps.dateFormats.map { ($0.id, $0.label) }, "iso_date")], apply: false),
            a("insert_uuid", "Insert UUID", "Type a new random UUID", "number.circle", apply: false),
            a("insert_text", "Insert Text", "Type your own text; {date} {time} {clipboard} {uuid} are replaced", "text.insert",
              [ParameterDefinition(key: "text", name: "Text", type: .string, required: true, description: "What to type")], apply: false),
            a("insert_lorem", "Insert Placeholder Text", "Type lorem ipsum", "text.justify",
              [ParameterDefinition(key: "sentences", name: "Sentences", type: .number, defaultValue: AnyCodable(3), description: "How many sentences",
                                   validation: ValidationRule(minValue: 1, maxValue: 50))], apply: false),
        ]
    }

    public func initialize(context: PluginContext) throws { self.context = context }
    public func cleanup() { context = nil }

    public func validate(action: PluginAction, with parameters: ActionParameters) -> ValidationResult {
        if action.id == "insert_text", (parameters.string(for: "text") ?? "").isEmpty { return .invalid(error: "Enter the text to insert") }
        return .valid
    }

    // MARK: execute

    public func execute(action: PluginAction, with parameters: ActionParameters, context: PluginContext) throws {
        let apply = parameters.bool(for: "applyToSelection") ?? true
        func s(_ key: String, _ def: String) -> String { parameters.string(for: key) ?? def }
        func fail(_ m: String) -> PluginError { PluginError.executionFailed(m) }

        switch action.id {
        case "change_case": let st = s("style", "upper"); try transform(apply, context) { TextOps.changeCase($0, style: st) }
        case "clean_text": let op = s("operation", "whitespace"); try transform(apply, context) { TextOps.clean($0, operation: op) }
        case "sort_lines": let o = s("order", "az"); try transform(apply, context) { TextOps.sortLines($0, order: o) }
        case "edit_lines": let op = s("operation", "dedupe"); try transform(apply, context) { TextOps.editLines($0, operation: op) }
        case "prefix_suffix":
            let p = s("prefix", ""), x = s("suffix", "")
            guard !(p.isEmpty && x.isEmpty) else { throw PluginError.invalidParameters("Set a prefix or a suffix") }
            try transform(apply, context) { TextOps.prefixSuffix($0, prefix: p, suffix: x) }
        case "wrap_text": let st = s("style", "double"); try transform(apply, context) { TextOps.wrap($0, style: st) }
        case "markdown_format":
            let k = s("kind", "bullets")
            let url = k == "link" ? (NSPasteboard.general.string(forType: .string) ?? "") : ""
            if k == "link" { guard WebCheck.looksLikeURL(url) else { throw fail("Copy a web address first, then select the link text") } }
            try transform(apply, context, clipboardIsInput: k != "link") { TextOps.markdown($0, kind: k, url: url) }
        case "encode_decode":
            let k = s("kind", "url_encode")
            try transform(apply, context) { TextOps.encode($0, kind: k) }
        case "format_json": let m = s("mode", "pretty") == "minify"; try transform(apply, context) { TextOps.formatJSON($0, minify: m) }
        case "typography": let m = s("mode", "smart"); try transform(apply, context) { m == "smart" ? TextOps.smartTypography($0) : TextOps.straighten($0) }
        case "slugify": try transform(apply, context) { TextOps.slugify($0) }
        case "calculate":
            let append = s("mode", "replace") == "append"
            try transform(apply, context) { text in
                guard let v = TextOps.calculate(text) else { return nil }
                let r = TextOps.formatNumber(v)
                return append ? text + " = " + r : r
            }
        case "convert_units":
            let append = s("mode", "replace") == "append"
            try transform(apply, context) { text in
                guard let r = TextOps.convertUnits(text) else { return nil }
                return append ? "\(r.value) \(text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .whitespaces).dropFirst().first ?? "") = \(r.result)" : r.result
            }
        case "convert_timestamp": try transform(apply, context) { TextOps.convertTimestamp($0) }
        case "text_stats":
            let text = try readSelection(context)
            context.showNotification(title: "Text statistics", message: TextOps.stats(text), style: .info)
        case "swap_clipboard":
            let pb = NSPasteboard.general
            let old = pb.string(forType: .string) ?? ""
            let selected = try readSelection(context)
            Self.set(old)
            context.sendKeyboardShortcut(keyCode: 9, modifiers: .maskCommand)
            Thread.sleep(forTimeInterval: 0.15)
            Self.set(selected)
        case "plain_paste":
            guard let text = NSPasteboard.general.string(forType: .string) else { return }
            let saved = Self.snapshot()
            Self.set(text)
            context.sendKeyboardShortcut(keyCode: 9, modifiers: .maskCommand)
            if restoreClipboard { Self.restore(saved, after: 0.4) }
        case "insert_datetime": try insert(TextOps.renderDate(format: s("format", "iso_date"), at: Date()), context)
        case "insert_uuid": try insert(UUID().uuidString, context)
        case "insert_text":
            guard let t = parameters.string(for: "text"), !t.isEmpty else { throw PluginError.invalidParameters("No text to insert") }
            try insert(TextOps.expand(t, at: Date(), clipboard: NSPasteboard.general.string(forType: .string) ?? ""), context)
        case "insert_lorem": try insert(TextOps.lorem(sentences: Int(parameters.number(for: "sentences") ?? 3)), context)
        default: throw PluginError.actionNotFound(action.id)
        }
    }

    // MARK: clipboard plumbing

    /// Copies the selection (⌘C) and returns it. The clipboard keeps the selection.
    private func readSelection(_ context: PluginContext) throws -> String {
        let pb = NSPasteboard.general
        let before = pb.changeCount
        context.sendKeyboardShortcut(keyCode: 8, modifiers: .maskCommand)
        let deadline = Date().addingTimeInterval(0.6)
        while pb.changeCount == before, Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        guard pb.changeCount != before, let text = pb.string(forType: .string) else { throw PluginError.executionFailed("No text is selected") }
        return text
    }

    private func transform(_ applyToSelection: Bool, _ context: PluginContext, clipboardIsInput: Bool = true, _ f: (String) -> String?) throws {
        let pb = NSPasteboard.general
        let saved = Self.snapshot()
        let input: String
        if applyToSelection { input = try readSelection(context) }
        else {
            guard let t = pb.string(forType: .string) else { throw PluginError.executionFailed("The clipboard has no text") }
            input = t
        }
        guard let output = f(input) else {
            if applyToSelection, restoreClipboard { Self.restore(saved, after: 0.05) }
            throw PluginError.executionFailed("Couldn't convert that text")
        }
        Self.set(output)
        if applyToSelection {
            context.sendKeyboardShortcut(keyCode: 9, modifiers: .maskCommand) // ⌘V
            if restoreClipboard { Self.restore(saved, after: 0.4) }
        }
    }

    private func insert(_ text: String, _ context: PluginContext) throws {
        let saved = Self.snapshot()
        Self.set(text)
        context.sendKeyboardShortcut(keyCode: 9, modifiers: .maskCommand)
        if restoreClipboard { Self.restore(saved, after: 0.4) }
    }

    private static func set(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private static func snapshot() -> [[(NSPasteboard.PasteboardType, Data)]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in item.types.compactMap { t in item.data(forType: t).map { (t, $0) } } }
    }

    private static func restore(_ items: [[(NSPasteboard.PasteboardType, Data)]], after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let pb = NSPasteboard.general
            pb.clearContents()
            for entries in items {
                let item = NSPasteboardItem()
                for (t, d) in entries { item.setData(d, forType: t) }
                pb.writeObjects([item])
            }
        }
    }
}

private enum WebCheck {
    static func looksLikeURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.contains(" "), let u = URL(string: t), let scheme = u.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto", "ftp"].contains(scheme)
    }
}
