import SwiftUI
import AppKit

// MARK: - Code Text Editor (disables smart quotes and autocorrection)

struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = isEditable
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.autoresizingMask = [.width]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.string = text
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
        textView.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextEditor
        init(_ parent: CodeTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

// MARK: - Shared Action Selection + Parameter Configuration

struct ActionSelectionView: View {
    @Binding var selectedActionId: String
    @Binding var actionParameters: [String: AnyCodable]

    @StateObject private var licenseService = LicenseService.shared
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    @State private var hasAdvancedConfig = false
    @State private var advancedConfigCount = 0

    var body: some View {
        Group {
            actionPickerSection
            parameterSection
        }
        .onAppear { refreshAdvancedState() }
        .onChange(of: selectedActionId) { _ in
            initDefaults()
            refreshAdvancedState()
        }
    }

    // MARK: - Action Picker

    private var actionPickerSection: some View {
        GroupBox("Action") {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                MGSearchField("Search actions...", text: $searchText)

                // Category chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: MGStyle.Spacing.md) {
                        categoryChip("All", icon: "square.grid.2x2", count: allActionEntries.count)
                        ForEach(usedCategories, id: \.self) { cat in
                            categoryChip(
                                cat.rawValue,
                                icon: cat.icon,
                                count: allActionEntries.filter { $0.category == cat }.count
                            )
                        }
                        if !savedActionEntries.isEmpty {
                            categoryChip("Saved", icon: "bookmark.fill", count: savedActionEntries.count)
                        }
                    }
                    .padding(.horizontal, MGStyle.Spacing.xs)
                }

                // Action list
                ScrollViewReader { proxy in
                    List(selection: Binding(
                        get: { selectedActionId.isEmpty ? nil : selectedActionId },
                        set: { if let v = $0 { selectedActionId = v } }
                    )) {
                        if isSearching {
                            searchResultsContent
                        } else if selectedCategory == "Saved" {
                            savedActionsContent
                        } else {
                            categorizedContent
                        }
                    }
                    .listStyle(.bordered)
                    .frame(height: 180)
                    .onChange(of: selectedActionId) { newId in
                        if !newId.isEmpty {
                            withAnimation { proxy.scrollTo(newId, anchor: .center) }
                        }
                    }
                    .onChange(of: searchText) { _ in
                        let firstId = isSearching
                            ? searchFilteredEntries.first?.id
                            : (allActionEntries.first?.id ?? savedActionEntries.first?.id)
                        if let id = firstId { proxy.scrollTo(id, anchor: .top) }
                    }
                    .onChange(of: selectedCategory) { _ in
                        let firstId = displayEntries.first?.id
                        if let id = firstId { proxy.scrollTo(id, anchor: .top) }
                    }
                }

                // Selected action banner
                if let action = selectedAction {
                    MGSelectionBanner(
                        icon: action.icon ?? "bolt.circle.fill",
                        title: action.name,
                        subtitle: action.description,
                        accentColor: .accentColor
                    )
                } else if let saved = selectedSavedAction {
                    MGSelectionBanner(
                        icon: "bookmark.fill",
                        title: saved.name,
                        subtitle: "Saved action",
                        accentColor: .orange
                    )
                } else if !selectedActionId.isEmpty {
                    MGSelectionBanner(
                        icon: "questionmark.circle",
                        title: selectedActionId,
                        subtitle: "Unknown action",
                        accentColor: .secondary
                    )
                }
            }
            .padding(.vertical, MGStyle.Spacing.md)
        }
    }

    // MARK: - Search Results Content

    @ViewBuilder
    private var searchResultsContent: some View {
        let results = searchFilteredEntries
        if results.isEmpty {
            Text("No actions matching \"\(searchText)\"")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, MGStyle.Spacing.md)
        } else {
            ForEach(results, id: \.id) { entry in
                actionRow(entry)
                    .tag(entry.id)
                    .id(entry.id)
            }
        }
    }

    // MARK: - Saved Actions Content

    @ViewBuilder
    private var savedActionsContent: some View {
        ForEach(savedActionEntries, id: \.id) { entry in
            actionRow(entry)
                .tag(entry.id)
                .id(entry.id)
        }
    }

    // MARK: - Categorized Content

    @ViewBuilder
    private var categorizedContent: some View {
        let entries = displayEntries
        let grouped = groupedByCategory(entries)
        ForEach(grouped, id: \.category) { group in
            Section(header:
                Label(group.category, systemImage: group.icon)
                    .font(.system(size: MGStyle.FontSize.caption, weight: .semibold))
                    .foregroundColor(.secondary)
            ) {
                ForEach(group.entries, id: \.id) { entry in
                    actionRow(entry)
                        .tag(entry.id)
                        .id(entry.id)
                }
            }
        }
        // Append saved actions at the bottom when showing "All"
        if selectedCategory == "All" && !savedActionEntries.isEmpty {
            Section(header:
                Label("Saved Actions", systemImage: "bookmark.fill")
                    .font(.system(size: MGStyle.FontSize.caption, weight: .semibold))
                    .foregroundColor(.secondary)
            ) {
                ForEach(savedActionEntries, id: \.id) { entry in
                    actionRow(entry)
                        .tag(entry.id)
                        .id(entry.id)
                }
            }
        }
    }

    // MARK: - Action Row

    private func actionRow(_ entry: ActionEntry) -> some View {
        HStack(spacing: MGStyle.Spacing.md) {
            if entry.isLocked {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary.opacity(0.5))
                    .font(.system(size: MGStyle.IconSize.row - 2))
                    .frame(width: 20, alignment: .center)
            } else if let iconName = entry.icon {
                Image(systemName: iconName)
                    .foregroundColor(entry.isSaved ? .orange : .accentColor)
                    .font(.system(size: MGStyle.IconSize.row))
                    .frame(width: 20, alignment: .center)
            } else {
                Image(systemName: entry.isSaved ? "bookmark.fill" : "circle.fill")
                    .foregroundColor(entry.isSaved ? .orange : .secondary.opacity(0.3))
                    .font(.system(size: entry.isSaved ? MGStyle.IconSize.row : 5))
                    .frame(width: 20, alignment: .center)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.name)
                        .font(.system(size: MGStyle.FontSize.body))
                        .lineLimit(1)

                    if entry.isLocked {
                        Text("PRO")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.orange.opacity(0.5), lineWidth: 1))
                    }
                }

                if isSearching {
                    Text(entry.categoryLabel)
                        .font(.system(size: MGStyle.FontSize.badge))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 1)
        .opacity(entry.isLocked ? 0.6 : 1.0)
        .disabled(entry.isLocked)
    }

    // MARK: - Category Chip

    private func categoryChip(_ label: String, icon: String, count: Int) -> some View {
        let isSelected = selectedCategory == label
        return Button(action: { selectedCategory = label }) {
            HStack(spacing: MGStyle.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: MGStyle.FontSize.badge))
                Text(shortLabel(label))
                    .font(.system(size: MGStyle.FontSize.caption, weight: isSelected ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, MGStyle.Spacing.sm)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15))
                    .cornerRadius(MGStyle.Corner.sm)
            }
            .padding(.horizontal, MGStyle.Spacing.md)
            .padding(.vertical, MGStyle.Spacing.sm)
            .background(isSelected ? Color.accentColor : MGStyle.Colors.cardBackground)
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(MGStyle.Corner.md)
            .overlay(
                RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                    .stroke(isSelected ? Color.clear : MGStyle.Colors.separator, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func shortLabel(_ label: String) -> String {
        let maxLen = 20
        if label.count <= maxLen { return label }
        // Take the first word if it's descriptive enough, otherwise truncate
        let first = label.split(separator: " ").first.map(String.init) ?? label
        return first.count <= maxLen ? first : String(label.prefix(maxLen))
    }

    // MARK: - Parameter Section

    private var parameterSection: some View {
        Group {
            if let action = selectedAction {
                if hasAdvancedConfig {
                    advancedConfigBox(for: action)
                }
                let simple = action.supportedParameters.filter { $0.type != .json && !$0.isAdvancedOnly }
                if !simple.isEmpty {
                    let grouped = parameterGroups(simple)
                    ForEach(grouped, id: \.name) { group in
                        GroupBox(group.name) {
                            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                                ForEach(group.params, id: \.key) { p in
                                    paramField(for: p)
                                }
                            }
                            .padding(.vertical, MGStyle.Spacing.md)
                        }
                    }
                }
            }
        }
    }

    /// Groups parameters by their `group` property for sectioned display
    private struct ParameterGroup: Identifiable {
        let name: String
        let params: [ParameterDefinition]
        var id: String { name }
    }

    private func parameterGroups(_ params: [ParameterDefinition]) -> [ParameterGroup] {
        var groups: [ParameterGroup] = []
        var currentGroupName: String? = nil
        var currentParams: [ParameterDefinition] = []

        for p in params {
            let groupName = p.group ?? "Parameters"
            if groupName != currentGroupName {
                if !currentParams.isEmpty, let name = currentGroupName {
                    groups.append(ParameterGroup(name: name, params: currentParams))
                }
                currentGroupName = groupName
                currentParams = [p]
            } else {
                currentParams.append(p)
            }
        }
        if !currentParams.isEmpty, let name = currentGroupName {
            groups.append(ParameterGroup(name: name, params: currentParams))
        }
        return groups
    }

    private func advancedConfigBox(for action: PluginAction) -> some View {
        GroupBox(action.advancedConfigLabel ?? "Advanced: \(action.name)") {
            HStack {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                    if advancedConfigCount > 0 {
                        HStack(spacing: MGStyle.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                            Text("\(advancedConfigCount) item(s) configured")
                                .font(.system(size: MGStyle.FontSize.body))
                        }
                    } else {
                        HStack(spacing: MGStyle.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                            Text("Not yet configured")
                                .font(.system(size: MGStyle.FontSize.body))
                                .foregroundColor(.orange)
                        }
                    }
                }
                Spacer()
                Button("Configure...") { openAdvanced(for: action) }
            }
            .padding(.vertical, MGStyle.Spacing.md)
        }
    }

    // MARK: - Parameter Fields

    /// Returns true when the parameter should be displayed given current parameter values
    private func shouldShow(_ p: ParameterDefinition) -> Bool {
        guard let rule = p.visibleWhen else { return true }
        if let stringVal = actionParameters[rule.key]?.value as? String {
            return rule.matches(stringVal)
        }
        if let boolVal = actionParameters[rule.key]?.value as? Bool {
            return rule.matches(boolVal ? "true" : "false")
        }
        let defaultStr = actionParameters[rule.key]?.value as? String ?? ""
        return rule.matches(defaultStr)
    }

    @ViewBuilder
    private func paramField(for p: ParameterDefinition) -> some View {
        if shouldShow(p) { paramFieldContent(for: p) }
    }

    /// Resolves the display label for a raw selection value
    private func displayLabel(for rawValue: String, param: ParameterDefinition) -> String {
        if let custom = param.displayValues?[rawValue] { return custom }
        // Auto-format: replace underscores and camelCase
        return rawValue
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .localizedCapitalized
    }

    @ViewBuilder
    private func paramFieldContent(for p: ParameterDefinition) -> some View {
        switch p.type {
        case .string:
            paramRow(p) {
                if let providerKey = p.optionProvider {
                    let options = resolveOptionProvider(providerKey)
                    if !options.isEmpty {
                        // Combo: pick from known options OR type a custom value
                        VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                            Picker("", selection: Binding(
                                get: {
                                    let v = actionParameters[p.key]?.value as? String ?? p.defaultValue?.value as? String ?? ""
                                    return options.contains(v) ? v : ""
                                },
                                set: { (v: String) in actionParameters[p.key] = AnyCodable(v) }
                            )) {
                                Text("Custom...").tag("")
                                ForEach(options, id: \.self) { opt in Text(opt).tag(opt) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            let current = actionParameters[p.key]?.value as? String ?? p.defaultValue?.value as? String ?? ""
                            if current.isEmpty || !options.contains(current) {
                                TextField("Type a name...", text: strBinding(p.key, def: p.defaultValue?.value as? String ?? ""))
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    } else {
                        TextField(p.description, text: strBinding(p.key, def: p.defaultValue?.value as? String ?? ""))
                            .textFieldStyle(.roundedBorder)
                    }
                } else {
                    TextField(p.description, text: strBinding(p.key, def: p.defaultValue?.value as? String ?? ""))
                        .textFieldStyle(.roundedBorder)
                }
            }
        case .path:
            paramRow(p) {
                HStack(spacing: MGStyle.Spacing.sm) {
                    TextField(p.description, text: strBinding(p.key, def: p.defaultValue?.value as? String ?? ""))
                        .textFieldStyle(.roundedBorder)
                    Button(action: { browseForPath(paramKey: p.key) }) {
                        Image(systemName: "folder")
                    }
                    .help("Browse...")
                }
            }
        case .url:
            paramRow(p) {
                HStack(spacing: MGStyle.Spacing.sm) {
                    TextField(p.description.isEmpty ? "https://" : p.description, text: strBinding(p.key, def: p.defaultValue?.value as? String ?? ""))
                        .textFieldStyle(.roundedBorder)
                    // URL validation indicator
                    let current = actionParameters[p.key]?.value as? String ?? ""
                    if !current.isEmpty {
                        if URL(string: current) != nil && (!current.isEmpty) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 12))
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                                .help("May not be a valid URL")
                        }
                    }
                }
            }
        case .number:
            paramRow(p) {
                if let minV = p.validation?.minValue, let maxV = p.validation?.maxValue {
                    // Slider + text field for bounded ranges
                    HStack(spacing: MGStyle.Spacing.md) {
                        Slider(
                            value: sliderBinding(p.key, def: p.defaultValue?.value as? Double ?? minV, min: minV, max: maxV),
                            in: minV...maxV,
                            step: maxV - minV > 10 ? 1 : 0.1
                        )
                        HStack(spacing: 2) {
                            TextField("", text: numBinding(p.key, def: p.defaultValue?.value as? Double ?? 0))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 55)
                                .multilineTextAlignment(.trailing)
                            if let suffix = p.suffix {
                                Text(suffix)
                                    .font(.system(size: MGStyle.FontSize.caption))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    // Plain text field for unbounded numbers
                    HStack(spacing: 2) {
                        TextField(p.description, text: numBinding(p.key, def: p.defaultValue?.value as? Double ?? 0))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        if let suffix = p.suffix {
                            Text(suffix)
                                .font(.system(size: MGStyle.FontSize.caption))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        case .boolean:
            HStack {
                Toggle(p.name, isOn: boolBinding(p.key, def: p.defaultValue?.value as? Bool ?? false))
                if !p.description.isEmpty {
                    Spacer()
                    Text(p.description)
                        .font(.system(size: MGStyle.FontSize.badge))
                        .foregroundColor(.secondary)
                }
            }
        case .selection:
            if let vals = p.validation?.allowedValues {
                let options = vals.compactMap { $0.value as? String }
                let defaultVal = (p.defaultValue?.value as? String).flatMap({ options.contains($0) ? $0 : nil }) ?? options.first ?? ""
                paramRow(p) {
                    Picker("", selection: strBinding(p.key, def: defaultVal)) {
                        // Only show "Select..." if no default is available and "" is not already an option
                        if !options.contains("") && p.defaultValue == nil {
                            Text("Select...").tag("")
                        }
                        ForEach(options, id: \.self) { v in
                            Text(displayLabel(for: v, param: p)).tag(v)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        case .application:
            paramRow(p) {
                HStack(spacing: MGStyle.Spacing.sm) {
                    Picker("", selection: strBinding(p.key, def: "")) {
                        Text(p.placeholderLabel ?? "Select...").tag("")
                        let isBrowserPicker = p.filterBrowsers == true
                        let appList = isBrowserPicker
                            ? WindowTargeting.getAllInstalledBrowsers()
                            : WindowTargeting.getAllRunningApplications()
                        let current = actionParameters[p.key]?.value as? String ?? ""
                        if !current.isEmpty && !appList.contains(where: { $0.bundleId == current }) {
                            let displayName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: current)
                                .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String }
                                ?? Bundle(url: NSWorkspace.shared.urlForApplication(withBundleIdentifier: current) ?? URL(fileURLWithPath: ""))?.object(forInfoDictionaryKey: "CFBundleName") as? String
                                ?? current
                            Text(displayName).tag(current)
                            Divider()
                        }
                        ForEach(appList, id: \.bundleId) { app in
                            Text(app.name).tag(app.bundleId)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    Button(action: { browseForApp(paramKey: p.key) }) {
                        Image(systemName: "folder")
                    }
                    .help("Browse for any installed application")
                }
            }
        case .profile:
            paramRow(p) {
                Picker("", selection: strBinding(p.key, def: "")) {
                    Text("Select...").tag("")
                    ForEach(ProfileManager.shared.sortedProfiles, id: \.name) { profile in
                        Text(profile.name).tag(profile.name)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        case .script:
            VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                HStack {
                    Text(p.name).font(.system(size: 12, weight: .medium))
                    Spacer()
                    if !p.description.isEmpty {
                        Text(p.description)
                            .font(.system(size: MGStyle.FontSize.badge))
                            .foregroundColor(.secondary)
                    }
                }
                let useFile = actionParameters["use_file"]?.value as? Bool ?? false
                if useFile, let filePath = actionParameters["script_path"]?.value as? String, !filePath.isEmpty {
                    // Show file contents as read-only preview
                    let fileContents = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? "(unable to read file)"
                    CodeTextEditor(text: .constant(fileContents), isEditable: false)
                        .frame(minHeight: 80, maxHeight: 150)
                        .border(MGStyle.Colors.separator, width: 1)
                        .cornerRadius(MGStyle.Corner.sm)
                        .opacity(0.75)
                    Text("Preview of: \(filePath)")
                        .font(.system(size: MGStyle.FontSize.badge))
                        .foregroundColor(.secondary)
                } else {
                    CodeTextEditor(text: strBinding(p.key, def: p.defaultValue?.value as? String ?? ""), isEditable: true)
                        .frame(minHeight: 80, maxHeight: 150)
                        .border(MGStyle.Colors.separator, width: 1)
                        .cornerRadius(MGStyle.Corner.sm)
                }
            }
        case .keyboardShortcut:
            paramRow(p) {
                HStack(spacing: MGStyle.Spacing.md) {
                    KeyboardShortcutFieldView(shortcut: Binding(
                        get: {
                            // Read from actionParameters dictionary
                            guard let dict = actionParameters[p.key]?.value as? [String: Any],
                                  let keyCode = dict["keyCode"] as? UInt16,
                                  let modifiers = dict["modifiers"] as? UInt,
                                  let displayString = dict["displayString"] as? String else {
                                return nil
                            }
                            var mods = NSEvent.ModifierFlags()
                            let flags = CGEventFlags(rawValue: UInt64(modifiers))
                            if flags.contains(.maskCommand) { mods.insert(.command) }
                            if flags.contains(.maskControl) { mods.insert(.control) }
                            if flags.contains(.maskAlternate) { mods.insert(.option) }
                            if flags.contains(.maskShift) { mods.insert(.shift) }
                            return KeyboardTrigger(keyCode: keyCode, modifiers: mods, displayString: displayString)
                        },
                        set: { trigger in
                            if let t = trigger {
                                var cgFlags: CGEventFlags = []
                                if t.modifiers.contains(.command) { cgFlags.insert(.maskCommand) }
                                if t.modifiers.contains(.control) { cgFlags.insert(.maskControl) }
                                if t.modifiers.contains(.option) { cgFlags.insert(.maskAlternate) }
                                if t.modifiers.contains(.shift) { cgFlags.insert(.maskShift) }
                                let dict: [String: Any] = [
                                    "keyCode": t.keyCode,
                                    "modifiers": UInt(cgFlags.rawValue),
                                    "displayString": t.displayString
                                ]
                                actionParameters[p.key] = AnyCodable(dict)
                            } else {
                                actionParameters.removeValue(forKey: p.key)
                            }
                        }
                    ))
                    .frame(width: 200, height: 24)

                    Button(action: { actionParameters.removeValue(forKey: p.key) }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear shortcut")
                }
            }
        case .actionId:
            paramRow(p) {
                Picker("", selection: strBinding(p.key, def: "")) {
                    Text("Select Action...").tag("")
                    ForEach(allActionEntries, id: \.id) { entry in
                        Text(entry.name).tag(entry.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        case .json:
            EmptyView()
        default:
            paramRow(p) {
                TextField(p.description, text: strBinding(p.key, def: p.defaultValue?.value as? String ?? ""))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    /// Consistent row layout for a parameter: label on the left, control on the right
    @ViewBuilder
    private func paramRow<Content: View>(_ p: ParameterDefinition, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
            HStack {
                Text(p.name)
                    .font(.system(size: 12, weight: .medium))
                if !p.description.isEmpty && p.type != .script {
                    Spacer()
                    Text(p.description)
                        .font(.system(size: MGStyle.FontSize.badge))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            content()
        }
    }

    // MARK: - Data Model

    private struct ActionEntry: Identifiable {
        let id: String
        let name: String
        let description: String
        let icon: String?
        let category: ActionCategory
        let categoryLabel: String
        let isSaved: Bool
        let isAdvanced: Bool
        let isExternal: Bool

        var isLocked: Bool {
            (isAdvanced || isExternal) && !LicenseService.shared.isPro
        }
    }

    private struct CategoryGroup: Identifiable {
        let category: String
        let icon: String
        let entries: [ActionEntry]
        var id: String { category }
    }

    // MARK: - Data Sources

    private var allActionEntries: [ActionEntry] {
        PluginManager.shared.getAllActions()
            .filter { !$0.action.hidden }
            .map { item in
                let fullId = item.pluginId + "." + item.action.id
                let plugin = PluginManager.shared.getPlugin(identifier: item.pluginId)
                let cat = plugin?.category ?? .custom
                let isAdvanced = (plugin?.isAdvanced ?? false) || item.action.isAdvanced
                let isExternal = plugin?.isExternal ?? false
                return ActionEntry(
                    id: fullId,
                    name: item.action.name,
                    description: item.action.description,
                    icon: item.action.icon,
                    category: cat,
                    categoryLabel: cat.rawValue,
                    isSaved: false,
                    isAdvanced: isAdvanced,
                    isExternal: isExternal
                )
            }
    }

    private var savedActionEntries: [ActionEntry] {
        SavedActionsManager.shared.savedActions.map { saved in
            ActionEntry(
                id: saved.id.uuidString,
                name: saved.name,
                description: "Saved action",
                icon: "bookmark.fill",
                category: .custom,
                categoryLabel: "Saved",
                isSaved: true,
                isAdvanced: false,
                isExternal: false
            )
        }
    }

    private var usedCategories: [ActionCategory] {
        let cats = Set(allActionEntries.map { $0.category })
        return ActionCategory.allCases.filter { cats.contains($0) }
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private var searchFilteredEntries: [ActionEntry] {
        let q = searchText.lowercased()
        let all = allActionEntries + savedActionEntries
        return all.filter {
            $0.name.lowercased().contains(q) ||
            $0.description.lowercased().contains(q) ||
            $0.categoryLabel.lowercased().contains(q)
        }
    }

    private var displayEntries: [ActionEntry] {
        if selectedCategory == "All" {
            return allActionEntries
        } else if selectedCategory == "Saved" {
            return savedActionEntries
        } else {
            return allActionEntries.filter { $0.category.rawValue == selectedCategory }
        }
    }

    private func groupedByCategory(_ entries: [ActionEntry]) -> [CategoryGroup] {
        var seen = Set<String>()
        var groups: [CategoryGroup] = []
        for cat in ActionCategory.allCases {
            let matching = entries.filter { $0.category == cat }
            if !matching.isEmpty && !seen.contains(cat.rawValue) {
                seen.insert(cat.rawValue)
                groups.append(CategoryGroup(category: cat.rawValue, icon: cat.icon, entries: matching))
            }
        }
        return groups
    }

    private var selectedAction: PluginAction? {
        PluginManager.shared.getAction(identifier: selectedActionId)?.action
    }

    private var selectedSavedAction: SavedAction? {
        SavedActionsManager.shared.savedActions.first { $0.id.uuidString == selectedActionId }
    }

    // MARK: - File/App Browsers

    private func browseForPath(paramKey: String) {
        let panel = NSOpenPanel()
        panel.title = "Select File or Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                actionParameters[paramKey] = AnyCodable(url.path)
            }
        }
    }

    private func browseForApp(paramKey: String) {
        let panel = NSOpenPanel()
        panel.title = "Select Application"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            // Extract bundle ID from the selected .app
            if let bundle = Bundle(url: url),
               let bundleId = bundle.bundleIdentifier {
                DispatchQueue.main.async {
                    actionParameters[paramKey] = AnyCodable(bundleId)
                }
            }
        }
    }

    // MARK: - Parameter Bindings

    private func strBinding(_ k: String, def d: String) -> Binding<String> {
        Binding(get: { actionParameters[k]?.value as? String ?? d },
                set: { actionParameters[k] = AnyCodable($0) })
    }
    private func numBinding(_ k: String, def d: Double) -> Binding<String> {
        Binding(
            get: {
                if let v = actionParameters[k]?.value as? Double { return String(v) }
                if let v = actionParameters[k]?.value as? Int { return String(v) }
                return String(d)
            },
            set: { if let v = Double($0) { actionParameters[k] = AnyCodable(v) } }
        )
    }
    private func boolBinding(_ k: String, def d: Bool) -> Binding<Bool> {
        Binding(get: { actionParameters[k]?.value as? Bool ?? d },
                set: { actionParameters[k] = AnyCodable($0) })
    }
    private func sliderBinding(_ k: String, def d: Double, min minV: Double, max maxV: Double) -> Binding<Double> {
        Binding(
            get: {
                if let v = actionParameters[k]?.value as? Double { return v }
                if let v = actionParameters[k]?.value as? Int { return Double(v) }
                return d
            },
            set: { actionParameters[k] = AnyCodable($0) }
        )
    }

    // MARK: - State Management

    private func initDefaults() {
        actionParameters.removeAll()
        guard let action = selectedAction else { return }
        for p in action.supportedParameters {
            if let d = p.defaultValue { actionParameters[p.key] = d }
        }
    }

    private func refreshAdvancedState() {
        guard let (plugin, action) = PluginManager.shared.getAction(identifier: selectedActionId) else {
            hasAdvancedConfig = false; advancedConfigCount = 0; return
        }
        hasAdvancedConfig = plugin.hasAdvancedConfiguration(for: action)
        refreshAdvancedCount()
    }

    private func refreshAdvancedCount() {
        if let bd = actionParameters["bundle_actions"] {
            if let arr = bd.value as? [[String: Any]] { advancedConfigCount = arr.count } else if let s = bd.value as? String,
                    let d = s.data(using: .utf8),
                    let arr = try? JSONSerialization.jsonObject(with: d) as? [Any] { advancedConfigCount = arr.count } else { advancedConfigCount = 0 }
        } else { advancedConfigCount = 0 }
    }

    private func resolveOptionProvider(_ key: String) -> [String] {
        let plugin = PluginManager.shared.getPlugin(identifier: "com.mousegestures.window")
        guard let wmp = plugin as? WindowManagementPlugin else { return [] }
        switch key {
        case "window.layouts":        return wmp.getAvailableLayouts()
        case "window.position_slots": return wmp.getAvailablePositionSlots()
        default: return []
        }
    }

    private func openAdvanced(for action: PluginAction) {
        guard let (plugin, _) = PluginManager.shared.getAction(identifier: selectedActionId),
              let window = NSApp.keyWindow else { return }
        plugin.presentAdvancedConfiguration(
            for: action, currentParameters: actionParameters, parentWindow: window
        ) { updated in
            if let updated = updated {
                DispatchQueue.main.async {
                    self.actionParameters = updated
                    self.refreshAdvancedCount()
                }
            }
        }
    }
}
