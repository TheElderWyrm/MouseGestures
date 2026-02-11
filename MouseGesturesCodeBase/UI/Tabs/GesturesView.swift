import SwiftUI
import AppKit

// MARK: - Gestures Tab
struct GesturesView: View {
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedGesture: Gesture?
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
            MGPageHeader("Gestures") {
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
                
                MGSearchField("Search gestures...", text: $searchText)
                    .frame(width: MGStyle.Layout.searchFieldWidth)
                
                MGHeaderDivider()
                
                Button(action: { activeSheet = .addGesture }) {
                    Label("Add Gesture", systemImage: "plus")
                }
                
                Button(action: { activeSheet = .profilePicker }) {
                    Label("Change Profile", systemImage: "person.2")
                }
                
                Button(action: { showingResetConfirmation = true }) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .foregroundColor(.red)
                }
            }
            
            Divider()
            
            // Main Content
            HSplitView {
                gestureListView
                    .frame(minWidth: MGStyle.Layout.listMinWidth, idealWidth: MGStyle.Layout.listIdealWidth)
                
                if let gesture = selectedGesture {
                    gestureDetailView(gesture: gesture)
                        .frame(minWidth: MGStyle.Layout.detailMinWidth)
                } else {
                    MGEmptyState(icon: "hand.tap", title: "Select a gesture to view details")
                        .background(MGStyle.Colors.contentBackground)
                        .frame(minWidth: MGStyle.Layout.detailMinWidth)
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
    
    // MARK: - Gesture List View
    
    private var gestureListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            MGListSectionHeader(
                "Configured Gestures",
                count: filteredGestures.count,
                trailing: !filteredGestures.isEmpty ? AnyView(
                    Button(action: clearAllGestures) {
                        Text("Clear All")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                ) : nil
            )
            
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
                        MGEmptyState(
                            icon: searchText.isEmpty ? "hand.draw" : "magnifyingglass",
                            title: searchText.isEmpty ? "No gestures configured" : "No matching gestures",
                            actionLabel: searchText.isEmpty ? "Add Your First Gesture" : nil,
                            action: searchText.isEmpty ? { activeSheet = .addGesture } : nil
                        )
                        .padding(.vertical, 40)
                    }
                }
            }
        }
        .background(MGStyle.Colors.contentBackground)
    }
    
    // MARK: - Gesture Detail View
    
    private func gestureDetailView(gesture: Gesture) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                    Text("Gesture Details")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(gesture.displayDescription)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Trigger Information
                GroupBox("Trigger") {
                    VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                        LabeledContent("Zone:") {
                            Text(gesture.zone.rawValue).fontWeight(.medium)
                        }
                        LabeledContent("Modifiers:") {
                            Text(modifiersDescription(gesture.modifiers)).fontWeight(.medium)
                        }
                        if gesture.dragModifier != .none {
                            LabeledContent("Drag Modifier:") {
                                Text(gesture.dragModifier.displayName).fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.vertical, MGStyle.Spacing.sm)
                }
                
                // Action Information
                GroupBox("Action") {
                    VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                        if let actionDef = UIServices.shared.getActionDefinition(for: gesture.actionIdentifier) {
                            LabeledContent("Name:") {
                                Text(actionDef.name).fontWeight(.medium)
                            }
                            LabeledContent("Description:") {
                                Text(actionDef.description).foregroundColor(.secondary)
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
                    .padding(.vertical, MGStyle.Spacing.sm)
                }
                
                // Activation Settings
                GroupBox("Activation") {
                    VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                        LabeledContent("Type:") {
                            Text(gesture.activation.activationType.rawValue).fontWeight(.medium)
                        }
                        Toggle("Enabled", isOn: .constant(gesture.activation.isEnabled))
                            .disabled(true)
                        if let keyboard = gesture.activation.keyboardTrigger {
                            LabeledContent("Keyboard:") {
                                Text(keyboard.displayString).fontWeight(.medium)
                            }
                        }
                        if let mouse = gesture.activation.mouseButtonTrigger {
                            LabeledContent("Mouse Button:") {
                                Text(mouse.displayString).fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.vertical, MGStyle.Spacing.sm)
                }
                
                // Timing Settings
                if gesture.timing.repeatOnHold || gesture.timing.longPressEnabled {
                    GroupBox("Timing") {
                        VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                            if gesture.timing.repeatOnHold {
                                Toggle("Repeat on Hold", isOn: .constant(true)).disabled(true)
                                LabeledContent("Initial Delay:") {
                                    Text("\(gesture.timing.repeatInitialDelay, specifier: "%.1f")s").fontWeight(.medium)
                                }
                                LabeledContent("Repeat Interval:") {
                                    Text("\(gesture.timing.repeatInterval, specifier: "%.1f")s").fontWeight(.medium)
                                }
                            }
                            if gesture.timing.longPressEnabled {
                                Toggle("Long Press", isOn: .constant(true)).disabled(true)
                                LabeledContent("Threshold:") {
                                    Text("\(gesture.timing.longPressThreshold, specifier: "%.1f")s").fontWeight(.medium)
                                }
                                if let longPressAction = gesture.longPressActionIdentifier {
                                    LabeledContent("Long Press Action:") {
                                        Text(longPressAction).fontWeight(.medium).lineLimit(1)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, MGStyle.Spacing.sm)
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
            .padding(MGStyle.Spacing.xl)
        }
        .background(MGStyle.Colors.contentBackground)
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
            Toggle("", isOn: $isEnabled)
                .toggleStyle(CheckboxToggleStyle())
                .onChange(of: isEnabled) { newValue in
                    onToggleEnabled(newValue)
                }
                .help(isEnabled ? "Gesture is enabled" : "Gesture is disabled")
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                Text(gesture.displayDescription)
                    .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                    .lineLimit(1)
                    .opacity(isEnabled ? 1.0 : 0.5)
                
                if let actionDef = UIServices.shared.getActionDefinition(for: gesture.actionIdentifier) {
                    Text(actionDef.name)
                        .font(.system(size: MGStyle.FontSize.caption))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .opacity(isEnabled ? 1.0 : 0.5)
                } else {
                    Text(gesture.actionIdentifier)
                        .font(.system(size: MGStyle.FontSize.caption))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .opacity(isEnabled ? 1.0 : 0.5)
                }
            }
            
            Spacer()
            
            if isHovered {
                MGRowActions(actions: [
                    .init("pencil") { onEdit() },
                    .init("trash", destructive: true) { onDelete() }
                ])
            }
        }
        .mgListRow(isSelected: isSelected, isHovered: isHovered)
        .onHover { hovering in isHovered = hovering }
        .onTapGesture { onSelect() }
    }
}

// MARK: - Profile Picker Sheet

struct ProfilePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedProfileId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            MGSheetHeader("Select Profile", onCancel: { dismiss() })
            
            ScrollView {
                VStack(spacing: MGStyle.Spacing.md) {
                    ForEach(uiServices.profiles.sorted(by: { $0.name < $1.name })) { profile in
                        ProfileRow(
                            profile: profile,
                            isActive: profile.id == uiServices.activeProfileId,
                            isSelected: profile.id == selectedProfileId,
                            onSelect: { selectedProfileId = profile.id }
                        )
                    }
                }
                .padding(MGStyle.Spacing.xl)
            }
            
            MGSheetFooter("Select", disabled: selectedProfileId == nil) {
                if let profileId = selectedProfileId {
                    uiServices.switchToProfile(profileId)
                    dismiss()
                }
            } leading: {
                Button("New Profile...") {
                    if let newProfile = uiServices.createProfile(name: "New Profile") {
                        selectedProfileId = newProfile.id
                    }
                }
            }
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
            VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                HStack {
                    Text(profile.name)
                        .fontWeight(isActive ? .bold : .regular)
                    
                    if isActive {
                        MGBadge("Active", color: .green)
                    }
                    
                    if profile.isDefault {
                        MGBadge("Default")
                    }
                }
                
                Text("\(profile.gestures.count) gestures")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .mgListRow(isSelected: isSelected, isHovered: false)
        .onTapGesture { onSelect() }
    }
}
