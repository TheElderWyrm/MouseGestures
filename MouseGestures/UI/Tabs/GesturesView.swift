import SwiftUI
import AppKit

// MARK: - Gestures Tab
struct GesturesView: View {
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedGesture: Gesture?
    // Sheet presentation - using single enum to avoid multiple .sheet modifier bug
    enum ActiveSheet: Identifiable {
        case addGesture
        case editGesture(Gesture)
        case profilePicker
        
        var id: String {
            switch self {
            case .addGesture: return "add"
            case .editGesture(let g): return "edit-\(g.id)"
            case .profilePicker: return "profile"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var showingResetConfirmation = false
    @State private var searchText = ""
    
    private var filteredGestures: [Gesture] {
        if searchText.isEmpty {
            return uiServices.gestures
        }
        return uiServices.searchGestures(query: searchText)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Main Content
            HSplitView {
                // Gesture List
                gestureListView
                    .frame(minWidth: 300, idealWidth: 400)
                
                // Detail View
                if let gesture = selectedGesture {
                    gestureDetailView(gesture: gesture)
                        .frame(minWidth: 300)
                } else {
                    emptyDetailView
                        .frame(minWidth: 300)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addGesture:
                AddGestureSheet()
            case .editGesture(let gesture):
                EditGestureSheet(gesture: gesture)
            case .profilePicker:
                ProfilePickerSheet()
            }
        }
        .alert("Reset Gestures", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                uiServices.resetToDefaultProfiles()
            }
        } message: {
            Text("This will reset all profiles and gestures to factory defaults. This action cannot be undone.")
        }
        .onAppear {
            uiServices.loadData()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gestures")
                    .font(.largeTitle)
                    .bold()
                
                if let profile = uiServices.getActiveProfile() {
                    HStack {
                        Text("Active Profile:")
                            .foregroundColor(.secondary)
                        Text(profile.name)
                            .fontWeight(.medium)
                        
                        Button(action: { activeSheet = .profilePicker }) {
                            Image(systemName: "chevron.down.circle")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.subheadline)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search gestures...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .frame(width: 200)
                
                Divider()
                    .frame(height: 20)
                
                // Add Gesture
                Button(action: { activeSheet = .addGesture }) {
                    Label("Add Gesture", systemImage: "plus")
                }
                
                // Change Profile
                Button(action: { activeSheet = .profilePicker }) {
                    Label("Change Profile", systemImage: "person.2")
                }
                
                // Reset Button
                Button(action: { showingResetConfirmation = true }) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    // MARK: - Gesture List View
    
    private var gestureListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // List Header
            HStack {
                Text("Configured Gestures (\(filteredGestures.count))")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !filteredGestures.isEmpty {
                    Button(action: clearAllGestures) {
                        Text("Clear All")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(filteredGestures, id: \.id) { gesture in
                        GestureRowView(
                            gesture: gesture,
                            isSelected: selectedGesture?.id == gesture.id,
                            onSelect: { selectedGesture = gesture },
                            onDelete: { deleteGesture(gesture) },
                            onEdit: { 
                                selectedGesture = gesture
                                activeSheet = .editGesture(gesture)
                            },
                            onToggleEnabled: { isEnabled in
                                toggleGestureEnabled(gesture, enabled: isEnabled)
                            }
                        )
                    }
                    
                    if filteredGestures.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: searchText.isEmpty ? "hand.draw" : "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary.opacity(0.5))
                            
                            Text(searchText.isEmpty ? "No gestures configured" : "No matching gestures")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            if searchText.isEmpty {
                                Button(action: { activeSheet = .addGesture }) {
                                    Label("Add Your First Gesture", systemImage: "plus.circle")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Gesture Detail View
    
    private func gestureDetailView(gesture: Gesture) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Gesture Details")
                        .font(.title2)
                        .bold()
                    
                    Text(gesture.displayDescription)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Trigger Information
                GroupBox("Trigger") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Zone:") {
                            Text(gesture.zone.rawValue)
                                .fontWeight(.medium)
                        }
                        
                        LabeledContent("Modifiers:") {
                            Text(modifiersDescription(gesture.modifiers))
                                .fontWeight(.medium)
                        }
                        
                        if gesture.dragModifier != .none {
                            LabeledContent("Drag Modifier:") {
                                Text(gesture.dragModifier.displayName)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Action Information
                GroupBox("Action") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let actionDef = UIServices.shared.getActionDefinition(for: gesture.actionIdentifier) {
                            LabeledContent("Name:") {
                                Text(actionDef.name)
                                    .fontWeight(.medium)
                            }
                            
                            LabeledContent("Description:") {
                                Text(actionDef.description)
                                    .foregroundColor(.secondary)
                            }
                            
                            LabeledContent("Plugin:") {
                                Text(gesture.actionIdentifier.split(separator: ".").first.map(String.init) ?? "Unknown")
                                    .fontWeight(.medium)
                            }
                        } else {
                            Text("Action: \(gesture.actionIdentifier)")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Activation Settings
                GroupBox("Activation") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Type:") {
                            Text(gesture.activation.activationType.rawValue)
                                .fontWeight(.medium)
                        }
                        
                        Toggle("Enabled", isOn: .constant(gesture.activation.isEnabled))
                            .disabled(true)
                        
                        if let keyboard = gesture.activation.keyboardTrigger {
                            LabeledContent("Keyboard:") {
                                Text(keyboard.displayString)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        if let mouse = gesture.activation.mouseButtonTrigger {
                            LabeledContent("Mouse Button:") {
                                Text(mouse.displayString)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Timing Settings
                if gesture.timing.repeatOnHold || gesture.timing.longPressEnabled {
                    GroupBox("Timing") {
                        VStack(alignment: .leading, spacing: 8) {
                            if gesture.timing.repeatOnHold {
                                Toggle("Repeat on Hold", isOn: .constant(true))
                                    .disabled(true)
                                
                                LabeledContent("Initial Delay:") {
                                    Text("\(gesture.timing.repeatInitialDelay, specifier: "%.1f")s")
                                        .fontWeight(.medium)
                                }
                                
                                LabeledContent("Repeat Interval:") {
                                    Text("\(gesture.timing.repeatInterval, specifier: "%.1f")s")
                                        .fontWeight(.medium)
                                }
                            }
                            
                            if gesture.timing.longPressEnabled {
                                Toggle("Long Press", isOn: .constant(true))
                                    .disabled(true)
                                
                                LabeledContent("Threshold:") {
                                    Text("\(gesture.timing.longPressThreshold, specifier: "%.1f")s")
                                        .fontWeight(.medium)
                                }
                                
                                if let longPressAction = gesture.longPressActionIdentifier {
                                    LabeledContent("Long Press Action:") {
                                        Text(longPressAction)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Actions
                HStack {
                    Button(action: { 
                        selectedGesture = gesture
                        activeSheet = .editGesture(gesture)
                    }) {
                        Label("Edit", systemImage: "pencil")
                    }
                    
                    Button(action: { deleteGesture(gesture) }) {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                }
                .padding(.top)
            }
            .padding()
        }
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Empty Detail View
    
    private var emptyDetailView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.tap")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Select a gesture to view details")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Helper Methods
    
    private func deleteGesture(_ gesture: Gesture) {
        if uiServices.removeGesture(gesture) {
            if selectedGesture?.id == gesture.id {
                selectedGesture = nil
            }
        }
    }
    
    private func clearAllGestures() {
        uiServices.clearAllGestures()
        selectedGesture = nil
    }
    
    private func toggleGestureEnabled(_ gesture: Gesture, enabled: Bool) {
        var updatedGesture = gesture
        updatedGesture.activation.isEnabled = enabled
        _ = uiServices.updateGesture(oldGesture: gesture, newGesture: updatedGesture)
    }
    
    private func modifiersDescription(_ modifiers: NSEvent.ModifierFlags) -> String {
        return uiServices.getModifiersDescription(modifiers)
    }
}

// MARK: - Gesture Row View

struct GestureRowView: View {
    let gesture: Gesture
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onEdit: () -> Void
    let onToggleEnabled: (Bool) -> Void
    
    @State private var isHovered = false
    @State private var isEnabled: Bool
    
    init(gesture: Gesture, isSelected: Bool, onSelect: @escaping () -> Void, 
         onDelete: @escaping () -> Void, onEdit: @escaping () -> Void, 
         onToggleEnabled: @escaping (Bool) -> Void) {
        self.gesture = gesture
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onEdit = onEdit
        self.onToggleEnabled = onToggleEnabled
        self._isEnabled = State(initialValue: gesture.isEnabled)
    }
    
    var body: some View {
        HStack {
            // Checkbox to enable/disable
            Toggle("", isOn: $isEnabled)
                .toggleStyle(CheckboxToggleStyle())
                .onChange(of: isEnabled) { newValue in
                    onToggleEnabled(newValue)
                }
                .help(isEnabled ? "Gesture is enabled" : "Gesture is disabled")
            
            VStack(alignment: .leading, spacing: 4) {
                Text(gesture.displayDescription)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .opacity(isEnabled ? 1.0 : 0.5)
                
                if let actionDef = UIServices.shared.getActionDefinition(for: gesture.actionIdentifier) {
                    Text(actionDef.name)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .opacity(isEnabled ? 1.0 : 0.5)
                } else {
                    Text(gesture.actionIdentifier)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .opacity(isEnabled ? 1.0 : 0.5)
                }
            }
            
            Spacer()
            
            if isHovered {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : 
                      (isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear))
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Profile Picker Sheet

struct ProfilePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedProfileId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Profile")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // Profile List
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(uiServices.profiles.sorted(by: { $0.name < $1.name })) { profile in
                        ProfileRow(
                            profile: profile,
                            isActive: profile.id == uiServices.activeProfileId,
                            isSelected: profile.id == selectedProfileId,
                            onSelect: {
                                selectedProfileId = profile.id
                            }
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("New Profile...") {
                    // Handle new profile creation
                    if let newProfile = uiServices.createProfile(name: "New Profile") {
                        selectedProfileId = newProfile.id
                    }
                }
                
                Spacer()
                
                Button("Select") {
                    if let profileId = selectedProfileId {
                        uiServices.switchToProfile(profileId)
                        dismiss()
                    }
                }
                .keyboardShortcut(.return)
                .disabled(selectedProfileId == nil)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .onAppear {
            selectedProfileId = uiServices.activeProfileId
        }
    }
}

struct ProfileRow: View {
    let profile: ConfigurationProfile
    let isActive: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(profile.name)
                        .fontWeight(isActive ? .bold : .regular)
                    
                    if isActive {
                        Text("(Active)")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    if profile.isDefault {
                        Text("Default")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                Text("\(profile.gestures.count) gestures")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}
