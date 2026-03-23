import SwiftUI
import AppKit

// MARK: - Gestures Tab
struct GesturesView: View {
    @StateObject private var uiServices = UIServices.shared
    enum ActiveSheet: Identifiable {
        case addGesture
        case editGesture(Gesture)
        
        var id: String {
            switch self {
            case .addGesture: return "add"
            case .editGesture(let g): return "edit-\(g.id)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var showingResetConfirmation = false
    @State private var showingResetToTemplate = false
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var expandedGesture: String?
    @State private var showProfilePicker = false
    
    private var filteredGestures: [Gesture] {
        if searchText.isEmpty { return uiServices.gestures }
        return uiServices.searchGestures(query: searchText)
    }
    
    private var activeProfileName: String {
        uiServices.getActiveProfile()?.name ?? "None"
    }
    
    private var enabledCount: Int {
        uiServices.gestures.filter { $0.isEnabled }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            MGCompactHeader(
                "Gestures",
                menuItems: [
                    MGMenuItem("Reset to Template...", icon: "doc.badge.arrow.up") {
                        showingResetToTemplate = true
                    },
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
                    Label("Add Gesture", systemImage: "plus")
                }
            }
            
            Divider()
            
            // Profile bar with stats
            HStack(spacing: MGStyle.Spacing.lg) {
                profileSwitcher
                
                Divider().frame(height: 14)
                
                Text("\(enabledCount) of \(uiServices.gestures.count) active")
                    .font(.system(size: MGStyle.FontSize.caption))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, MGStyle.Spacing.xl)
            .padding(.vertical, MGStyle.Spacing.md)
            
            // Main Content
            if filteredGestures.isEmpty {
                if searchText.isEmpty {
                    gestureEmptyState
                } else {
                    MGEmptyState(icon: "magnifyingglass", title: "No matching gestures")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: MGStyle.Spacing.sm) {
                        ForEach(filteredGestures, id: \.id) { gesture in
                            GestureCardView(
                                gesture: gesture,
                                isExpanded: expandedGesture == gesture.id,
                                onToggleExpand: { toggleExpand(gesture) },
                                onEdit: { activeSheet = .editGesture(gesture) },
                                onDelete: { deleteGesture(gesture) },
                                onToggleEnabled: { enabled in toggleGestureEnabled(gesture, enabled: enabled) }
                            )
                        }
                    }
                    .padding(MGStyle.Spacing.xl)
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
            }
        }
        .alert("Reset Gestures", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { uiServices.resetToDefaultProfiles() }
        } message: {
            Text("This will reset the current profile's gestures to factory defaults. This action cannot be undone.")
        }
        .sheet(isPresented: $showingResetToTemplate) {
            ResetToTemplateSheet { type in
                uiServices.resetCurrentProfileToTemplate(type)
            }
        }
        .onAppear { uiServices.loadData() }
    }
    
    // MARK: - Empty State

    private var gestureEmptyState: some View {
        VStack(spacing: MGStyle.Spacing.xl) {
            Spacer()
            Image(systemName: "hand.draw")
                .font(.system(size: 48, weight: .thin))
                .foregroundColor(.secondary.opacity(0.5))
            VStack(spacing: MGStyle.Spacing.sm) {
                Text("No gestures configured")
                    .font(.system(size: MGStyle.FontSize.heading, weight: .medium))
                Text("Add gestures to trigger actions with mouse zones, modifier keys, and more.")
                    .font(.system(size: MGStyle.FontSize.caption))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: MGStyle.Spacing.lg) {
                Button(action: { activeSheet = .addGesture }) {
                    Label("Add Gesture", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button(action: { showingResetToTemplate = true }) {
                    Label("Import Template", systemImage: "doc.badge.arrow.up")
                }
            }
            Spacer()
        }
        .padding(MGStyle.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inline Profile Switcher
    
    private var profileSwitcher: some View {
        Menu {
            ForEach(uiServices.profiles.sorted(by: { $0.name < $1.name })) { profile in
                Button(action: { uiServices.switchToProfile(profile.id) }) {
                    HStack {
                        Text(profile.name)
                        if profile.id == uiServices.activeProfileId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: MGStyle.Spacing.sm) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(activeProfileName)
                    .font(.system(size: MGStyle.FontSize.caption))
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, MGStyle.Spacing.md)
            .padding(.vertical, MGStyle.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: MGStyle.Corner.sm)
                    .fill(MGStyle.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MGStyle.Corner.sm)
                    .stroke(MGStyle.Colors.separator.opacity(0.5), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
    
    // MARK: - Helpers
    
    private func toggleExpand(_ gesture: Gesture) {
        withAnimation(.easeInOut(duration: 0.2)) {
            expandedGesture = expandedGesture == gesture.id ? nil : gesture.id
        }
    }
    
    private func deleteGesture(_ gesture: Gesture) {
        _ = uiServices.removeGesture(gesture)
    }
    
    private func clearAllGestures() {
        uiServices.clearAllGestures()
    }
    
    private func toggleGestureEnabled(_ gesture: Gesture, enabled: Bool) {
        var updated = gesture
        updated.isEnabled = enabled
        _ = uiServices.updateGesture(oldGesture: gesture, newGesture: updated)
    }
}

// MARK: - Gesture Card View

struct GestureCardView: View {
    let gesture: Gesture
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleEnabled: (Bool) -> Void
    
    @State private var isHovered = false
    @State private var isEnabled: Bool
    @State private var showDeleteConfirm = false
    
    init(gesture: Gesture, isExpanded: Bool,
         onToggleExpand: @escaping () -> Void, onEdit: @escaping () -> Void,
         onDelete: @escaping () -> Void, onToggleEnabled: @escaping (Bool) -> Void) {
        self.gesture = gesture
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onToggleEnabled = onToggleEnabled
        self._isEnabled = State(initialValue: gesture.isEnabled)
    }
    
    private var actionDef: PluginAction? {
        UIServices.shared.getActionDefinition(for: gesture.actionIdentifier)
    }
    
    /// Build a concise trigger summary string from enabled components
    private var triggerSummary: String {
        return gesture.components.previewString
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: MGStyle.Spacing.lg) {
                // Action icon
                ZStack {
                    RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                        .fill(isEnabled ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: actionDef?.icon ?? "bolt")
                        .font(.system(size: 14))
                        .foregroundColor(isEnabled ? .accentColor : .secondary)
                }
                
                // Enable toggle
                Toggle("", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .onChange(of: isEnabled) { v in onToggleEnabled(v) }
                
                // Info block
                VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                    let displayName = gesture.name?.isEmpty == false ? gesture.name! : (actionDef?.name ?? gesture.actionIdentifier)
                    Text(displayName)
                        .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                        .lineLimit(1)
                        .opacity(isEnabled ? 1 : 0.5)
                    HStack(spacing: MGStyle.Spacing.sm) {
                        if gesture.name?.isEmpty == false {
                            Text(actionDef?.name ?? gesture.actionIdentifier)
                                .font(.system(size: MGStyle.FontSize.badge))
                                .foregroundColor(.secondary.opacity(0.6))
                                .lineLimit(1)
                        }
                        Text(triggerSummary)
                            .font(.system(size: MGStyle.FontSize.caption))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .opacity(isEnabled ? 0.8 : 0.4)
                }
                
                Spacer()
                
                // Timing indicators
                HStack(spacing: MGStyle.Spacing.sm) {
                    if gesture.timing.repeatOnHold {
                        Image(systemName: "repeat")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                            .help("Repeats on hold")
                    }
                    if gesture.timing.longPressEnabled {
                        Image(systemName: "timer")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                            .help("Long press")
                    }
                }
                
                // Hover actions with expanded hit targets
                MGRowActions(actions: [
                    .init("pencil", help: "Edit gesture") { onEdit() },
                    .init("trash", help: "Delete gesture", destructive: true) { showDeleteConfirm = true }
                ])
                
                // Expand chevron
                MGActionButton("chevron.right", help: "Show details") { onToggleExpand() }
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, MGStyle.Spacing.lg)
            .padding(.vertical, MGStyle.Spacing.lg)
            
            // Expanded detail area
            if isExpanded {
                Divider()
                    .padding(.horizontal, MGStyle.Spacing.lg)
                
                expandedContent
                    .padding(.horizontal, MGStyle.Spacing.lg)
                    .padding(.vertical, MGStyle.Spacing.lg)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .mgListCard(isHovered: isHovered, isExpanded: isExpanded)
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovered = h } }
        .onTapGesture(count: 2) { onEdit() }
        .onTapGesture { onToggleExpand() }
        .contextMenu {
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
            Divider()
            Button(action: { isEnabled.toggle(); onToggleEnabled(isEnabled) }) {
                Label(isEnabled ? "Disable" : "Enable", systemImage: isEnabled ? "pause.circle" : "play.circle")
            }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
        .confirmationDialog("Delete Gesture?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove this gesture.")
        }
    }
    
    // MARK: - Expanded Content
    
    private var expandedContent: some View {
        let details = gesture.components.enabledComponentDetails
        
        return HStack(alignment: .top, spacing: MGStyle.Spacing.xxl) {
            // Trigger details
            VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                Text("Trigger")
                    .font(.system(size: MGStyle.FontSize.caption, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                ForEach(details.indices, id: \.self) { i in
                    detailLine(details[i].label, details[i].value)
                }
            }
            .frame(minWidth: 160, alignment: .leading)
            
            Divider()
                .frame(height: 80)
            
            // Action details
            VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                Text("Action")
                    .font(.system(size: MGStyle.FontSize.caption, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                if let def = actionDef {
                    detailLine("Name", def.name)
                    if !def.description.isEmpty {
                        Text(def.description)
                            .font(.system(size: MGStyle.FontSize.caption))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    detailLine("ID", gesture.actionIdentifier)
                }
                
                // Display parameters with type hints
                if !gesture.parameters.isEmpty {
                    ForEach(Array(gesture.parameters.keys.sorted()), id: \.self) { key in
                        if let val = gesture.parameters[key] {
                            parameterDetailLine(key: key, value: val)
                        }
                    }
                }
            }
            .frame(minWidth: 180, alignment: .leading)
            
            // Timing (if applicable)
            if gesture.timing.repeatOnHold || gesture.timing.longPressEnabled {
                Divider()
                    .frame(height: 80)
                
                VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                    Text("Timing")
                        .font(.system(size: MGStyle.FontSize.caption, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    
                    if gesture.timing.repeatOnHold {
                        detailLine("Repeat", "On Hold")
                        detailLine("Delay", String(format: "%.1fs", gesture.timing.repeatInitialDelay))
                        detailLine("Interval", String(format: "%.1fs", gesture.timing.repeatInterval))
                    }
                    if gesture.timing.longPressEnabled {
                        detailLine("Long Press", String(format: "%.1fs", gesture.timing.longPressThreshold))
                    }
                }
                .frame(minWidth: 120, alignment: .leading)
            }
            
            Spacer()
        }
    }
    
    private func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MGStyle.Spacing.md) {
            Text(label)
                .font(.system(size: MGStyle.FontSize.caption))
                .foregroundColor(.secondary)
                .frame(minWidth: 60, alignment: .leading)
            Text(value)
                .font(.system(size: MGStyle.FontSize.caption, weight: .medium))
        }
    }
    
    /// Show a parameter with its value and a type/format hint
    @ViewBuilder
    private func parameterDetailLine(key: String, value: AnyCodable) -> some View {
        let label = formatParameterKey(key)
        let display = formatParameterValue(value)
        
        HStack(alignment: .firstTextBaseline, spacing: MGStyle.Spacing.md) {
            Text(label)
                .font(.system(size: MGStyle.FontSize.caption))
                .foregroundColor(.secondary)
                .frame(minWidth: 60, alignment: .leading)
            
            Text(display)
                .font(.system(size: MGStyle.FontSize.caption, weight: .medium))
                .lineLimit(1)
        }
    }
    
    /// Format a parameter key into a readable label
    private func formatParameterKey(_ key: String) -> String {
        let spaced = key.replacingOccurrences(of: "_", with: " ")
        let words = spaced.unicodeScalars.reduce("") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar) && !result.isEmpty {
                return result + " " + String(scalar)
            }
            return result + String(scalar)
        }
        return words.prefix(1).uppercased() + words.dropFirst()
    }
    
    /// Format a parameter value for display, avoiding raw data dumps
    private func formatParameterValue(_ value: AnyCodable) -> String {
        if let str = value.value as? String {
            return str.count > 60 ? String(str.prefix(57)) + "..." : str
        } else if let num = value.value as? NSNumber {
            return num.stringValue
        } else if let bool = value.value as? Bool {
            return bool ? "Yes" : "No"
        } else if value.value is NSNull {
            return "—"
        } else if let arr = value.value as? [Any] {
            return "\(arr.count) item\(arr.count == 1 ? "" : "s")"
        } else if let dict = value.value as? [String: Any] {
            return "\(dict.count) field\(dict.count == 1 ? "" : "s")"
        } else {
            return "Configured"
        }
    }
    
}

// MARK: - Profile Picker Sheet (kept for potential reuse)

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
            
            MGSheetFooter("Select", disabled: selectedProfileId == nil, action: {
                if let profileId = selectedProfileId {
                    uiServices.switchToProfile(profileId)
                    dismiss()
                }
            }, cancel: { dismiss() }) {
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

// MARK: - Reset to Template Sheet

struct ResetToTemplateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: DefaultProfileType?
    @State private var showingConfirm = false
    let onReset: (DefaultProfileType) -> Void

    var body: some View {
        VStack(spacing: 0) {
            MGSheetHeader("Reset to Template", subtitle: "Replace current gestures with a template")

            ScrollView {
                VStack(spacing: MGStyle.Spacing.lg) {
                    ForEach(DefaultProfileType.allCases, id: \.self) { type in
                        TemplateProfileCard(
                            type: type,
                            isSelected: selectedType == type,
                            onSelect: { selectedType = selectedType == type ? nil : type }
                        )
                    }
                }
                .padding(MGStyle.Spacing.xl)
            }

            MGSheetFooter("Replace", disabled: selectedType == nil, action: {
                showingConfirm = true
            }, cancel: { dismiss() })
        }
        .frame(width: 540, height: 560)
        .alert("Replace Gestures?", isPresented: $showingConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                if let type = selectedType { onReset(type) }
                dismiss()
            }
        } message: {
            Text("This will replace all gestures in the current profile with the \"\(selectedType?.rawValue ?? "")\" template. This cannot be undone.")
        }
    }
}
