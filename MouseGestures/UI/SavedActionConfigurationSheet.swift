import SwiftUI
import AppKit

// MARK: - Add/Edit Saved Action Sheet

struct SavedActionConfigurationSheet: View {
    let mode: Mode
    let existingAction: SavedAction?
    let onSave: (SavedAction) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    
    // Action configuration state
    @State private var actionName: String
    @State private var selectedActionId: String
    @State private var parameters: [String: AnyCodable]
    
    // UI State
    @State private var selectedCategory = "All"
    @State private var showingDuplicateNameAlert = false
    @State private var hasAdvancedConfig = false
    @State private var advancedConfigCount = 0
    
    enum Mode {
        case add
        case edit
        
        var title: String {
            switch self {
            case .add: return "Add Saved Action"
            case .edit: return "Edit Saved Action"
            }
        }
        
        var buttonTitle: String {
            switch self {
            case .add: return "Add"
            case .edit: return "Save"
            }
        }
    }
    
    init(mode: Mode, existingAction: SavedAction? = nil, onSave: @escaping (SavedAction) -> Void) {
        self.mode = mode
        self.existingAction = existingAction
        self.onSave = onSave
        
        // Initialize state from existing action or defaults
        if let action = existingAction {
            _actionName = State(initialValue: action.name)
            _selectedActionId = State(initialValue: action.actionIdentifier)
            _parameters = State(initialValue: action.parameters)
        } else {
            _actionName = State(initialValue: "")
            _selectedActionId = State(initialValue: "")
            _parameters = State(initialValue: [:])
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Configuration Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameSection
                    actionSelectionSection
                    parameterConfigurationSection
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 600, height: 500)
        .onAppear {
            updateAdvancedConfigState()
        }
        .alert("Duplicate Name", isPresented: $showingDuplicateNameAlert) {
            Button("OK") {}
        } message: {
            Text("A saved action with this name already exists. Please choose a different name.")
        }
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
        HStack {
            Text(mode.title)
                .font(.title2)
                .bold()
            
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
        }
        .padding()
    }
    
    private var nameSection: some View {
        GroupBox("Action Name") {
            TextField("Enter a descriptive name", text: $actionName)
                .textFieldStyle(.roundedBorder)
                .padding(.vertical, 8)
        }
    }
    
    private var actionSelectionSection: some View {
        GroupBox("Action") {
            VStack(alignment: .leading, spacing: 12) {
                // Category Filter
                LabeledContent("Category:") {
                    Picker("", selection: $selectedCategory) {
                        Text("All").tag("All")
                        Text("Core Actions").tag("Core")
                        Text("Window Management").tag("Window")
                        Text("Media Control").tag("Media")
                        Text("System Control").tag("System")
                        Text("Automation").tag("Automation")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 200)
                }
                
                // Action Selection
                LabeledContent("Action:") {
                    Picker("", selection: $selectedActionId) {
                        if selectedActionId.isEmpty {
                            Text("Select an action...").tag("")
                        }
                        ForEach(filteredActions, id: \.0) { actionId, action in
                            Text(action.name)
                                .tag(actionId)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 300)
                }
                
                // Action Description
                if let action = getSelectedAction() {
                    Text(action.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var parameterConfigurationSection: some View {
        Group {
            if let action = getSelectedAction() {
                // Advanced configuration button
                if hasAdvancedConfig {
                    GroupBox("Advanced Configuration") {
                        VStack(alignment: .leading, spacing: 12) {
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
                                Button("Configure...") {
                                    openAdvancedConfiguration(for: action)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                
                // Simple parameter fields (skip json params when advanced config handles them)
                let simpleParams = action.supportedParameters.filter { param in
                    if hasAdvancedConfig && param.type == .json { return false }
                    return true
                }
                if !simpleParams.isEmpty {
                    GroupBox("Parameters") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(simpleParams, id: \.key) { paramDef in
                                parameterField(for: paramDef)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .onChange(of: selectedActionId) { _ in
            initializeParameterDefaults()
            updateAdvancedConfigState()
        }
    }
    
    @ViewBuilder
    private func parameterField(for paramDef: ParameterDefinition) -> some View {
        switch paramDef.type {
        case .string, .path, .url:
            LabeledContent("\(paramDef.name):") {
                TextField(paramDef.description, text: paramStringBinding(for: paramDef.key, default: paramDef.defaultValue?.value as? String ?? ""))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 200)
            }
        case .number:
            LabeledContent("\(paramDef.name):") {
                TextField(paramDef.description, text: paramNumberStringBinding(for: paramDef.key, default: paramDef.defaultValue?.value as? Double ?? 0))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
        case .boolean:
            Toggle(paramDef.name, isOn: paramBoolBinding(for: paramDef.key, default: paramDef.defaultValue?.value as? Bool ?? false))
        case .selection:
            if let allowedValues = paramDef.validation?.allowedValues {
                LabeledContent("\(paramDef.name):") {
                    Picker("", selection: paramStringBinding(for: paramDef.key, default: paramDef.defaultValue?.value as? String ?? "")) {
                        ForEach(allowedValues.compactMap { $0.value as? String }, id: \.self) { val in
                            Text(val.replacingOccurrences(of: "_", with: " ").capitalized).tag(val)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 200)
                }
            }
        case .application:
            LabeledContent("\(paramDef.name):") {
                Picker("", selection: paramStringBinding(for: paramDef.key, default: "")) {
                    Text("Select...").tag("")
                    ForEach(WindowTargeting.getAllRunningApplications(), id: \.bundleId) { app in
                        Text(app.name).tag(app.bundleId)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 200)
            }
        case .json:
            VStack(alignment: .leading, spacing: 4) {
                Text(paramDef.name)
                    .font(.system(size: 13, weight: .medium))
                Text(paramDef.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: paramJsonBinding(for: paramDef.key))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 150)
                    .border(Color(NSColor.separatorColor), width: 1)
                    .cornerRadius(4)
            }
        case .script:
            VStack(alignment: .leading, spacing: 4) {
                Text(paramDef.name)
                    .font(.system(size: 13, weight: .medium))
                Text(paramDef.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: paramStringBinding(for: paramDef.key, default: paramDef.defaultValue?.value as? String ?? ""))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 150)
                    .border(Color(NSColor.separatorColor), width: 1)
                    .cornerRadius(4)
            }
        case .keyboardShortcut:
            LabeledContent("\(paramDef.name):") {
                Text("Configure via Gesture settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        case .window, .coordinate, .size, .color:
            LabeledContent("\(paramDef.name):") {
                TextField(paramDef.description, text: paramStringBinding(for: paramDef.key, default: paramDef.defaultValue?.value as? String ?? ""))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 200)
            }
        }
    }
    
    private func initializeParameterDefaults() {
        parameters.removeAll()
        guard let action = getSelectedAction() else { return }
        for paramDef in action.supportedParameters {
            if let defaultVal = paramDef.defaultValue {
                parameters[paramDef.key] = defaultVal
            }
        }
    }
    
    private func paramStringBinding(for key: String, default defaultVal: String) -> Binding<String> {
        Binding(
            get: { parameters[key]?.value as? String ?? defaultVal },
            set: { parameters[key] = AnyCodable($0) }
        )
    }
    
    private func paramNumberStringBinding(for key: String, default defaultVal: Double) -> Binding<String> {
        Binding(
            get: {
                if let v = parameters[key]?.value as? Double { return String(v) }
                if let v = parameters[key]?.value as? Int { return String(v) }
                return String(defaultVal)
            },
            set: {
                if let d = Double($0) { parameters[key] = AnyCodable(d) }
            }
        )
    }
    
    private func paramBoolBinding(for key: String, default defaultVal: Bool) -> Binding<Bool> {
        Binding(
            get: { parameters[key]?.value as? Bool ?? defaultVal },
            set: { parameters[key] = AnyCodable($0) }
        )
    }
    
    private func paramJsonBinding(for key: String) -> Binding<String> {
        Binding(
            get: {
                if let val = parameters[key] {
                    // Try to pretty-print if it's a dictionary or array
                    if let dict = val.value as? [String: Any],
                       let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
                       let str = String(data: data, encoding: .utf8) {
                        return str
                    }
                    if let arr = val.value as? [Any],
                       let data = try? JSONSerialization.data(withJSONObject: arr, options: .prettyPrinted),
                       let str = String(data: data, encoding: .utf8) {
                        return str
                    }
                    if let str = val.value as? String {
                        return str
                    }
                }
                return "{}"
            },
            set: { newValue in
                // Try to parse as JSON, store as string if invalid
                if let data = newValue.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    if let dict = json as? [String: Any] {
                        parameters[key] = AnyCodable(dict)
                    } else if let arr = json as? [Any] {
                        parameters[key] = AnyCodable(arr)
                    } else {
                        parameters[key] = AnyCodable(newValue)
                    }
                } else {
                    parameters[key] = AnyCodable(newValue)
                }
            }
        )
    }
    
    private func updateAdvancedConfigState() {
        guard let (plugin, action) = PluginManager.shared.getAction(identifier: selectedActionId) else {
            hasAdvancedConfig = false
            advancedConfigCount = 0
            return
        }
        hasAdvancedConfig = plugin.hasAdvancedConfiguration(for: action)
        updateAdvancedConfigCount()
    }
    
    private func updateAdvancedConfigCount() {
        // Count items in bundle_actions if present
        if let bundleData = parameters["bundle_actions"] {
            if let array = bundleData.value as? [[String: Any]] {
                advancedConfigCount = array.count
            } else if let jsonStr = bundleData.value as? String,
                      let data = jsonStr.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                advancedConfigCount = arr.count
            } else {
                advancedConfigCount = 0
            }
        } else {
            advancedConfigCount = 0
        }
    }
    
    private func openAdvancedConfiguration(for action: PluginAction) {
        guard let (plugin, _) = PluginManager.shared.getAction(identifier: selectedActionId),
              let window = NSApp.keyWindow else { return }
        
        plugin.presentAdvancedConfiguration(
            for: action,
            currentParameters: parameters,
            parentWindow: window
        ) { updatedParams in
            if let updatedParams = updatedParams {
                DispatchQueue.main.async {
                    self.parameters = updatedParams
                    self.updateAdvancedConfigCount()
                }
            }
        }
    }
    
    private var footerView: some View {
        HStack {
            // Preview
            if !actionName.isEmpty && !selectedActionId.isEmpty {
                VStack(alignment: .leading) {
                    Text("Preview:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(actionName)
                        .font(.system(.body, design: .default))
                        .bold()
                    if let action = getSelectedAction() {
                        Text(action.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Button(mode.buttonTitle) {
                saveAction()
            }
            .keyboardShortcut(.return)
            .disabled(!isValid)
        }
        .padding()
    }
    
    // MARK: - Helper Methods
    
    private var filteredActions: [(String, PluginAction)] {
        let allActions = PluginManager.shared.getAllActions()
        
        if selectedCategory == "All" {
            return allActions.map { ($0.pluginId + "." + $0.action.id, $0.action) }
        }
        
        // Filter by category (plugin prefix)
        let prefix = selectedCategory.lowercased()
        return allActions
            .filter { $0.pluginId.lowercased().contains(prefix) }
            .map { ($0.pluginId + "." + $0.action.id, $0.action) }
    }
    
    private func getSelectedAction() -> PluginAction? {
        return PluginManager.shared.getAction(identifier: selectedActionId)?.action
    }
    
    private var isValid: Bool {
        !actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && 
        !selectedActionId.isEmpty
    }
    
    private func saveAction() {
        let trimmedName = actionName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for duplicate names (except when editing the same action)
        if mode == .add || existingAction?.name != trimmedName {
            let existingActions = uiServices.getSavedActions()
            if existingActions.contains(where: { $0.name == trimmedName && $0.id != existingAction?.id }) {
                showingDuplicateNameAlert = true
                return
            }
        }
        
        // Create the new/updated saved action
        let savedAction: SavedAction
        if let existing = existingAction {
            savedAction = SavedAction(
                id: existing.id,
                name: trimmedName,
                actionIdentifier: selectedActionId,
                parameters: parameters,
                dateCreated: existing.dateCreated,
                dateModified: Date()
            )
        } else {
            savedAction = SavedAction(
                name: trimmedName,
                actionIdentifier: selectedActionId,
                parameters: parameters
            )
        }
        
        // Save the action
        onSave(savedAction)
        dismiss()
    }
}

// MARK: - Convenience Wrappers

struct AddSavedActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    
    var body: some View {
        SavedActionConfigurationSheet(
            mode: .add,
            onSave: { action in
                uiServices.addSavedAction(action)
            }
        )
    }
}

struct EditSavedActionSheet: View {
    let action: SavedAction
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    
    var body: some View {
        SavedActionConfigurationSheet(
            mode: .edit,
            existingAction: action,
            onSave: { updatedAction in
                uiServices.updateSavedAction(updatedAction)
            }
        )
    }
}
