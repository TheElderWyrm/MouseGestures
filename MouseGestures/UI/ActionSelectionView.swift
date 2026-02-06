import SwiftUI
import AppKit

// MARK: - Shared Action Selection + Parameter Configuration

struct ActionSelectionView: View {
    @Binding var selectedActionId: String
    @Binding var actionParameters: [String: AnyCodable]
    
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
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Category:") {
                    Picker("", selection: $selectedCategory) {
                        Text("All").tag("All")
                        ForEach(usedCategories, id: \.self) { cat in
                            Text(cat.rawValue).tag(cat.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                }
                
                LabeledContent("Action:") {
                    Picker("", selection: $selectedActionId) {
                        if selectedActionId.isEmpty {
                            Text("Select an action...").tag("")
                        }
                        ForEach(filteredActions, id: \.id) { entry in
                            Text(entry.action.name).tag(entry.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 300)
                }
                
                if let action = selectedAction {
                    Text(action.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
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
            LabeledContent("\(p.name):") {
                TextField(p.description, text: strBinding(p.key, def: p.defaultValue?.value as? String ?? ""))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 200)
            }
        case .number:
            LabeledContent("\(p.name):") {
                TextField(p.description, text: numBinding(p.key, def: p.defaultValue?.value as? Double ?? 0))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
        case .boolean:
            Toggle(p.name, isOn: boolBinding(p.key, def: p.defaultValue?.value as? Bool ?? false))
        case .selection:
            if let vals = p.validation?.allowedValues {
                LabeledContent("\(p.name):") {
                    Picker("", selection: strBinding(p.key, def: p.defaultValue?.value as? String ?? "")) {
                        ForEach(vals.compactMap { $0.value as? String }, id: \.self) { v in
                            Text(v.replacingOccurrences(of: "_", with: " ").capitalized).tag(v)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 200)
                }
            }
        case .application:
            LabeledContent("\(p.name):") {
                Picker("", selection: strBinding(p.key, def: "")) {
                    Text("Select...").tag("")
                    ForEach(WindowTargeting.getAllRunningApplications(), id: \.bundleId) { app in
                        Text(app.name).tag(app.bundleId)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 200)
            }
        case .script:
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(.system(size: 13, weight: .medium))
                Text(p.description).font(.caption).foregroundColor(.secondary)
                TextEditor(text: strBinding(p.key, def: p.defaultValue?.value as? String ?? ""))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 150)
                    .border(Color(NSColor.separatorColor), width: 1)
                    .cornerRadius(4)
            }
        case .keyboardShortcut:
            LabeledContent("\(p.name):") {
                Text("Configure via Activation settings")
                    .font(.caption).foregroundColor(.secondary)
            }
        case .json:
            EmptyView()
        default:
            LabeledContent("\(p.name):") {
                TextField(p.description, text: strBinding(p.key, def: p.defaultValue?.value as? String ?? ""))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 200)
            }
        }
    }
    
    // MARK: - Helpers
    
    private struct ActionEntry: Identifiable {
        let id: String
        let action: PluginAction
        let category: ActionCategory
    }
    
    private var allActionEntries: [ActionEntry] {
        PluginManager.shared.getAllActions().map { item in
            let fullId = item.pluginId + "." + item.action.id
            let cat = PluginManager.shared.getPlugin(identifier: item.pluginId)?.category ?? .custom
            return ActionEntry(id: fullId, action: item.action, category: cat)
        }
    }
    
    private var usedCategories: [ActionCategory] {
        let cats = Set(allActionEntries.map { $0.category })
        return ActionCategory.allCases.filter { cats.contains($0) }
    }
    
    private var filteredActions: [ActionEntry] {
        if selectedCategory == "All" { return allActionEntries }
        return allActionEntries.filter { $0.category.rawValue == selectedCategory }
    }
    
    private var selectedAction: PluginAction? {
        PluginManager.shared.getAction(identifier: selectedActionId)?.action
    }
    
    // Parameter bindings
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
