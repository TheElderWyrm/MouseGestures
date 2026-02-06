import SwiftUI
import AppKit

// MARK: - Add/Edit Saved Action Sheet

struct SavedActionConfigurationSheet: View {
    let mode: Mode
    let existingAction: SavedAction?
    let onSave: (SavedAction) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    
    @State private var actionName: String
    @State private var selectedActionId: String
    @State private var parameters: [String: AnyCodable]
    
    @State private var showingDuplicateNameAlert = false
    
    enum Mode {
        case add, edit
        var title: String { self == .add ? "Add Saved Action" : "Edit Saved Action" }
        var buttonTitle: String { self == .add ? "Add" : "Save" }
    }
    
    init(mode: Mode, existingAction: SavedAction? = nil, onSave: @escaping (SavedAction) -> Void) {
        self.mode = mode
        self.existingAction = existingAction
        self.onSave = onSave
        
        if let a = existingAction {
            _actionName = State(initialValue: a.name)
            _selectedActionId = State(initialValue: a.actionIdentifier)
            _parameters = State(initialValue: a.parameters)
        } else {
            _actionName = State(initialValue: "")
            _selectedActionId = State(initialValue: "")
            _parameters = State(initialValue: [:])
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameSection
                    ActionSelectionView(
                        selectedActionId: $selectedActionId,
                        actionParameters: $parameters
                    )
                }
                .padding()
            }
            
            Divider()
            footerView
        }
        .frame(width: 600, height: 500)
        .alert("Duplicate Name", isPresented: $showingDuplicateNameAlert) {
            Button("OK") {}
        } message: {
            Text("A saved action with this name already exists. Please choose a different name.")
        }
    }
    
    // MARK: - Components
    
    private var headerView: some View {
        HStack {
            Text(mode.title).font(.title2).bold()
            Spacer()
            Button("Cancel") { dismiss() }
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
    
    private var footerView: some View {
        HStack {
            if !actionName.isEmpty && !selectedActionId.isEmpty {
                VStack(alignment: .leading) {
                    Text("Preview:").font(.caption).foregroundColor(.secondary)
                    Text(actionName).font(.system(.body)).bold()
                    if let action = PluginManager.shared.getAction(identifier: selectedActionId)?.action {
                        Text(action.name).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Button(mode.buttonTitle) { saveAction() }
                .keyboardShortcut(.return)
                .disabled(!isValid)
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private var isValid: Bool {
        !actionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !selectedActionId.isEmpty
    }
    
    private func saveAction() {
        let trimmed = actionName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if mode == .add || existingAction?.name != trimmed {
            let existing = uiServices.getSavedActions()
            if existing.contains(where: { $0.name == trimmed && $0.id != existingAction?.id }) {
                showingDuplicateNameAlert = true
                return
            }
        }
        
        let saved: SavedAction
        if let ex = existingAction {
            saved = SavedAction(
                id: ex.id, name: trimmed,
                actionIdentifier: selectedActionId, parameters: parameters,
                dateCreated: ex.dateCreated, dateModified: Date()
            )
        } else {
            saved = SavedAction(
                name: trimmed,
                actionIdentifier: selectedActionId,
                parameters: parameters
            )
        }
        
        onSave(saved)
        dismiss()
    }
}

// MARK: - Convenience Wrappers

struct AddSavedActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    
    var body: some View {
        SavedActionConfigurationSheet(mode: .add) { action in
            uiServices.addSavedAction(action)
        }
    }
}

struct EditSavedActionSheet: View {
    let action: SavedAction
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    
    var body: some View {
        SavedActionConfigurationSheet(mode: .edit, existingAction: action) { updated in
            uiServices.updateSavedAction(updated)
        }
    }
}
