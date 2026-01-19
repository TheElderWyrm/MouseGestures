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
                    // TODO: Add parameter configuration section when needed
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            footerView
        }
        .frame(width: 600, height: 400)
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
