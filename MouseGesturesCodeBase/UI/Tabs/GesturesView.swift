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
    @State private var showSearch = false
    
    private var filteredGestures: [Gesture] {
        if searchText.isEmpty { return uiServices.gestures }
        return uiServices.searchGestures(query: searchText)
    }
    
    private var activeProfileName: String {
        uiServices.getActiveProfile()?.name ?? "None"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            MGCompactHeader(
                "Gestures",
                subtitle: "Profile: \(activeProfileName) · \(uiServices.gestures.count) gesture\(uiServices.gestures.count == 1 ? "" : "s")",
                menuItems: [
                    MGMenuItem("Change Profile", icon: "person.2") { activeSheet = .profilePicker },
                    .divider,
                    MGMenuItem("Reset to Defaults", icon: "arrow.counterclockwise", destructive: true) {
                        showingResetConfirmation = true
                    },
                    MGMenuItem("Clear All Gestures", icon: "trash", destructive: true) { clearAllGestures() }
                ]
            ) {
                if showSearch {
                    MGSearchField("Search gestures...", text: $searchText)
                        .frame(width: MGStyle.Layout.searchFieldWidth)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSearch.toggle() } }) {
                    Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help("Search gestures")
                
                Button(action: { activeSheet = .addGesture }) {
                    Label("Add", systemImage: "plus")
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
                    MGEmptyState(icon: "hand.tap", title: "Select a gesture", description: "Choose a gesture from the list to view its details")
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
            Button("Reset", role: .destructive) { uiServices.resetToDefaultProfiles() }
        } message: {
            Text("This will reset all profiles and gestures to factory defaults. This action cannot be undone.")
        }
        .onAppear { uiServices.loadData() }
    }
    
    // MARK: - Gesture List View
    
    private var gestureListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            MGListSectionHeader(
                "Configured Gestures",
                count: filteredGestures.count
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
            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                // Title bar
                HStack {
                    VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                        Text(gesture.displayDescription)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        HStack(spacing: MGStyle.Spacing.md) {
                            MGBadge(
                                gesture.isEnabled ? "Enabled" : "Disabled",
                                color: gesture.isEnabled ? .green : .gray,
                                icon: gesture.isEnabled ? "checkmark.circle" : "minus.circle"
                            )
                            
                            if let actionDef = UIServices.shared.getActionDefinition(for: gesture.actionIdentifier) {
                                MGBadge(actionDef.name, color: .accentColor, icon: actionDef.icon ?? "bolt")
                            }
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: MGStyle.Spacing.md) {
                        Button(action: { activeSheet = .editGesture(gesture) }) {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button(action: { deleteGesture(gesture) }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.bottom, MGStyle.Spacing.sm)
                
                // Trigger Section
                MGDetailSection("Trigger", icon: "hand.tap") {
                    MGDetailRow("Zone", value: gesture.zone.rawValue, icon: "square.grid.3x3")
                    
                    let modsText = modifiersDescription(gesture.modifiers)
                    if !modsText.isEmpty && modsText != "None" {
                        MGDetailRow("Modifiers", value: modsText, icon: "command")
                    }
                    
                    if gesture.dragModifier != .none {
                        MGDetailRow("Drag", value: gesture.dragModifier.displayName, icon: "hand.draw")
                    }
                    
                    if let keyboard = gesture.activation.keyboardTrigger {
                        MGDetailRow("Keyboard", value: keyboard.displayString, icon: "keyboard")
                    }
                    
                    if let mouse = gesture.activation.mouseButtonTrigger {
                        MGDetailRow("Mouse", value: mouse.displayString, icon: "computermouse")
                    }
                    
                    MGDetailRow("Activation", value: gesture.activation.activationType.rawValue, icon: "bolt.circle")
                }
                
                // Action Section
                MGDetailSection("Action", icon: "bolt") {
                    if let actionDef = UIServices.shared.getActionDefinition(for: gesture.actionIdentifier) {
                        MGDetailRow("Name", value: actionDef.name, icon: "tag")
                        
                        Text(actionDef.description)
                            .font(.system(size: MGStyle.FontSize.caption))
                            .foregroundColor(.secondary)
                            .padding(.leading, 14)
                        
                        let plugin = gesture.actionIdentifier.split(separator: ".").first.map(String.init) ?? "Unknown"
                        MGDetailRow("Plugin", value: plugin, icon: "puzzlepiece.extension")
                    } else {
                        MGDetailRow("Identifier", value: gesture.actionIdentifier, icon: "tag")
                    }
                    
                    // Show parameters if any
                    if !gesture.parameters.isEmpty {
                        Divider()
                        ForEach(Array(gesture.parameters.keys.sorted()), id: \.self) { key in
                            if let val = gesture.parameters[key] {
                                MGDetailRow(key.capitalized, value: "\(val.value ?? "—")", icon: "slider.horizontal.3")
                            }
                        }
                    }
                }
                
                // Timing Section (only if configured)
                if gesture.timing.repeatOnHold || gesture.timing.longPressEnabled {
                    MGDetailSection("Timing", icon: "timer") {
                        if gesture.timing.repeatOnHold {
                            MGDetailRow("Repeat", value: "On Hold", icon: "repeat", valueColor: .blue)
                            MGDetailRow("Initial Delay", value: String(format: "%.1fs", gesture.timing.repeatInitialDelay))
                            MGDetailRow("Interval", value: String(format: "%.1fs", gesture.timing.repeatInterval))
                        }
                        if gesture.timing.longPressEnabled {
                            MGDetailRow("Long Press", value: "Enabled", icon: "hand.tap", valueColor: .blue)
                            MGDetailRow("Threshold", value: String(format: "%.1fs", gesture.timing.longPressThreshold))
                            if let longPressAction = gesture.longPressActionIdentifier {
                                MGDetailRow("Action", value: longPressAction, icon: "bolt")
                            }
                        }
                    }
                }
            }
            .padding(MGStyle.Spacing.xl)
        }
        .background(MGStyle.Colors.contentBackground)
    }
    
    // MARK: - Helper Methods
    
    private func deleteGesture(_ gesture: Gesture) {
        if uiServices.removeGesture(gesture) {
            if selectedGesture?.id == gesture.id { selectedGesture = nil }
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
                .onChange(of: isEnabled) { newValue in onToggleEnabled(newValue) }
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
        .onTapGesture(count: 2) { onEdit() }
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
        .onAppear { selectedProfileId = uiServices.activeProfileId }
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
                    if isActive { MGBadge("Active", color: .green) }
                    if profile.isDefault { MGBadge("Default") }
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
