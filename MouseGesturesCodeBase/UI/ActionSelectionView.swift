import SwiftUI
import AppKit

// MARK: - Shared Action Selection + Parameter Configuration

struct ActionSelectionView: View {
    @Binding var selectedActionId: String
    @Binding var actionParameters: [String: AnyCodable]
    
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
            VStack(alignment: .leading, spacing: 10) {
                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    TextField("Search actions...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
                
                // Category chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
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
                    .padding(.horizontal, 2)
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
                }
                
                // Selected action description
                if let action = selectedAction {
                    HStack(spacing: 6) {
                        if let iconName = action.icon {
                            Image(systemName: iconName)
                                .foregroundColor(.accentColor)
                                .font(.system(size: 12))
                        }
                        Text(action.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                } else if let saved = selectedSavedAction {
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                        Text("Saved action: \(saved.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 8)
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
                .padding(.vertical, 8)
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
                    .font(.system(size: 11, weight: .semibold))
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
                    .font(.system(size: 11, weight: .semibold))
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
        HStack(spacing: 8) {
            if let iconName = entry.icon {
                Image(systemName: iconName)
                    .foregroundColor(entry.isSaved ? .orange : .accentColor)
                    .font(.system(size: 13))
                    .frame(width: 20, alignment: .center)
            } else {
                Image(systemName: entry.isSaved ? "bookmark.fill" : "circle.fill")
                    .foregroundColor(entry.isSaved ? .orange : .secondary.opacity(0.3))
                    .font(.system(size: entry.isSaved ? 13 : 5))
                    .frame(width: 20, alignment: .center)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if isSearching {
                    Text(entry.categoryLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 1)
    }
    
    // MARK: - Category Chip
    
    private func categoryChip(_ label: String, icon: String, count: Int) -> some View {
        let isSelected = selectedCategory == label
        return Button(action: { selectedCategory = label }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(shortLabel(label))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.clear : Color(NSColor.separatorColor), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
    
    private func shortLabel(_ label: String) -> String {
        switch label {
        case "Window Management": return "Window"
        case "System Control": return "System"
        case "Media Control": return "Media"
        case "Application": return "App"
        case "File Operations": return "File"
        case "Automation": return "Auto"
        case "Productivity": return "Productivity"
        case "Development": return "Dev"
        default: return label
        }
    }
    
    // MARK: - Parameter Section
    
    private var parameterSection: some View {
        Group {
            if let action = selectedAction {
                if hasAdvancedConfig {
                    advancedConfigBox(for: action)
                }
                let simple = action.supportedParameters.filter { $0.type != .json }
                if !simple.isEmpty {
                    GroupBox("Parameters") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(simple, id: \.key) { p in
                                paramField(for: p)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
    
    private func advancedConfigBox(for action: PluginAction) -> some View {
        GroupBox("Advanced Configuration") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("This action requires advanced configuration.")
                        .font(.system(size: 13))
                    if advancedConfigCount > 0 {
                        Text("\(advancedConfigCount) item(s) configured")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Not yet configured")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Spacer()
                Button("Configure...") { openAdvanced(for: action) }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Parameter Fields
    
    @ViewBuilder
    private func paramField(for p: ParameterDefinition) -> some View {
        switch p.type {
        case .string, .path, .url:
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name)
                    .font(.system(size: 12, weight: .medium))
                TextField(p.description, text: strBinding(p.key, def: p.defaultValue?.value as? String ?? ""))
                    .textFieldStyle(.roundedBorder)
            }
        case .number:
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name)
                    .font(.system(size: 12, weight: .medium))
                TextField(p.description, text: numBinding(p.key, def: p.defaultValue?.value as? Double ?? 0))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
        case .boolean:
            Toggle(p.name, isOn: boolBinding(p.key, def: p.defaultValue?.value as? Bool ?? false))
        case .selection:
            if let vals = p.validation?.allowedValues {
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.name)
                        .font(.system(size: 12, weight: .medium))
                    Picker("", selection: strBinding(p.key, def: p.defaultValue?.value as? String ?? "")) {
                        ForEach(vals.compactMap { $0.value as? String }, id: \.self) { v in
                            Text(v.replacingOccurrences(of: "_", with: " ").capitalized).tag(v)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        case .application:
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name)
                    .font(.system(size: 12, weight: .medium))
                Picker("", selection: strBinding(p.key, def: "")) {
                    Text("Select...").tag("")
                    ForEach(WindowTargeting.getAllRunningApplications(), id: \.bundleId) { app in
                        Text(app.name).tag(app.bundleId)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        case .script:
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(.system(size: 12, weight: .medium))
                Text(p.description).font(.caption).foregroundColor(.secondary)
                TextEditor(text: strBinding(p.key, def: p.defaultValue?.value as? String ?? ""))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 150)
                    .border(Color(NSColor.separatorColor), width: 1)
                    .cornerRadius(4)
            }
        case .keyboardShortcut:
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name)
                    .font(.system(size: 12, weight: .medium))
                Text("Configure via Activation settings")
                    .font(.caption).foregroundColor(.secondary)
            }
        case .json:
            EmptyView()
        default:
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name)
                    .font(.system(size: 12, weight: .medium))
                TextField(p.description, text: strBinding(p.key, def: p.defaultValue?.value as? String ?? ""))
                    .textFieldStyle(.roundedBorder)
            }
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
    }
    
    private struct CategoryGroup: Identifiable {
        let category: String
        let icon: String
        let entries: [ActionEntry]
        var id: String { category }
    }
    
    // MARK: - Data Sources
    
    private var allActionEntries: [ActionEntry] {
        PluginManager.shared.getAllActions().map { item in
            let fullId = item.pluginId + "." + item.action.id
            let cat = PluginManager.shared.getPlugin(identifier: item.pluginId)?.category ?? .custom
            return ActionEntry(
                id: fullId,
                name: item.action.name,
                description: item.action.description,
                icon: item.action.icon,
                category: cat,
                categoryLabel: cat.rawValue,
                isSaved: false
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
                isSaved: true
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
        if selectedCategory == "All" { return allActionEntries }
        if selectedCategory == "Saved" { return savedActionEntries }
        return allActionEntries.filter { $0.category.rawValue == selectedCategory }
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
            if let arr = bd.value as? [[String: Any]] { advancedConfigCount = arr.count }
            else if let s = bd.value as? String,
                    let d = s.data(using: .utf8),
                    let arr = try? JSONSerialization.jsonObject(with: d) as? [Any] { advancedConfigCount = arr.count }
            else { advancedConfigCount = 0 }
        } else { advancedConfigCount = 0 }
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
