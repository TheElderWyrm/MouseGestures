import SwiftUI
import UniformTypeIdentifiers

// MARK: - Profiles Tab
struct ProfilesView: View {
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedProfileId: UUID?
    enum ActiveSheet: Identifiable {
        case addProfile
        case importTemplates
        
        var id: String {
            switch self {
            case .addProfile: return "add"
            case .importTemplates: return "import"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var showingDeleteConfirmation = false
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var importError: String?
    @State private var showingImportError = false
    
    private var filteredProfiles: [ConfigurationProfile] {
        let sorted = uiServices.profiles.sorted { $0.name < $1.name }
        if searchText.isEmpty { return sorted }
        return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var selectedProfile: ConfigurationProfile? {
        guard let id = selectedProfileId else { return nil }
        return uiServices.profiles.first { $0.id == id }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            MGCompactHeader(
                "Profiles",
                subtitle: "\(uiServices.profiles.count) profile\(uiServices.profiles.count == 1 ? "" : "s") configured",
                menuItems: [
                    MGMenuItem("Import Templates", icon: "square.grid.2x2") { activeSheet = .importTemplates },
                    .divider,
                    MGMenuItem("Export Profile", icon: "square.and.arrow.up", disabled: selectedProfile == nil) { exportProfile() },
                    MGMenuItem("Export All Profiles", icon: "square.and.arrow.up.on.square", disabled: uiServices.profiles.isEmpty) { exportAllProfiles() },
                    .divider,
                    MGMenuItem("Import Profile", icon: "square.and.arrow.down") { importProfile() },
                    MGMenuItem("Import Profile Bundle", icon: "square.and.arrow.down.on.square") { importMultipleProfiles() }
                ]
            ) {
                if showSearch {
                    MGSearchField("Search profiles...", text: $searchText)
                        .frame(width: MGStyle.Layout.searchFieldWidth)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSearch.toggle() } }) {
                    Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                
                Button(action: { activeSheet = .addProfile }) {
                    Label("New Profile", systemImage: "plus")
                }
            }
            
            Divider()
            
            HSplitView {
                profileListView
                    .frame(minWidth: MGStyle.Layout.sidebarMinWidth, idealWidth: 280, maxWidth: 350)
                
                if let profile = selectedProfile {
                    ProfileDetailEditor(
                        profile: profile,
                        isActive: profile.id == uiServices.activeProfileId,
                        onActivate: { setActiveProfile(profile.id) },
                        onDuplicate: { duplicateProfile(profile.id) },
                        onExport: { exportSingleProfile(profile.id) },
                        onDelete: { showingDeleteConfirmation = true }
                    )
                    .frame(minWidth: 450)
                } else {
                    MGEmptyState(icon: "person.2.square.stack", title: "Select a profile", description: "Choose a profile from the list to view and edit its settings")
                        .background(MGStyle.Colors.contentBackground)
                        .frame(minWidth: 450)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addProfile:
                AddEditProfileSheet(mode: .add) { newProfile in
                    selectedProfileId = newProfile.id
                }
            case .importTemplates:
                ImportTemplatesSheet()
            }
        }
        .alert("Delete Profile", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let profileId = selectedProfileId { deleteProfile(profileId) }
            }
        } message: {
            if let profile = selectedProfile {
                Text("Are you sure you want to delete the profile '\(profile.name)'? This action cannot be undone.")
            }
        }
        .alert("Import Error", isPresented: $showingImportError) {
            Button("OK") {}
        } message: {
            Text(importError ?? "Failed to import profile")
        }
        .onAppear {
            uiServices.loadData()
            if selectedProfileId == nil { selectedProfileId = uiServices.activeProfileId }
        }
    }
    
    // MARK: - Profile List View
    
    private var profileListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(spacing: MGStyle.Spacing.sm) {
                    ForEach(filteredProfiles) { profile in
                        ProfileListRow(
                            profile: profile,
                            isActive: profile.id == uiServices.activeProfileId,
                            isSelected: profile.id == selectedProfileId,
                            onSelect: { selectedProfileId = profile.id },
                            onSetActive: { setActiveProfile(profile.id) },
                            onDuplicate: { duplicateProfile(profile.id) },
                            onDelete: {
                                selectedProfileId = profile.id
                                showingDeleteConfirmation = true
                            }
                        )
                    }
                    
                    if filteredProfiles.isEmpty {
                        MGEmptyState(
                            icon: searchText.isEmpty ? "folder" : "magnifyingglass",
                            title: searchText.isEmpty ? "No profiles" : "No matching profiles",
                            actionLabel: searchText.isEmpty ? "Create Profile" : nil,
                            action: searchText.isEmpty ? { activeSheet = .addProfile } : nil
                        )
                        .padding(.vertical, 40)
                    }
                }
                .padding(MGStyle.Spacing.lg)
            }
        }
        .background(MGStyle.Colors.contentBackground)
    }
    
    // MARK: - Helper Methods
    
    private func setActiveProfile(_ profileId: UUID) {
        uiServices.switchToProfile(profileId)
    }
    
    private func deleteProfile(_ profileId: UUID) {
        if uiServices.deleteProfile(profileId) { selectedProfileId = uiServices.activeProfileId }
    }
    
    private func duplicateProfile(_ profileId: UUID) {
        if let newProfile = uiServices.duplicateProfile(profileId) { selectedProfileId = newProfile.id }
    }
    
    private func exportProfile() {
        guard let profileId = selectedProfileId else { return }
        exportSingleProfile(profileId)
    }
    
    private func exportSingleProfile(_ profileId: UUID) {
        guard let profile = uiServices.profiles.first(where: { $0.id == profileId }) else { return }
        let savePanel = NSSavePanel()
        savePanel.title = "Export Profile"
        savePanel.nameFieldStringValue = "\(profile.name).mouseprofile"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "mouseprofile") ?? .json]
        if savePanel.runModal() == .OK, let url = savePanel.url {
            _ = uiServices.exportProfile(profileId, to: url)
        }
    }
    
    private func exportAllProfiles() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export All Profiles"
        savePanel.nameFieldStringValue = "MouseGestures_Profiles.mousebundle"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "mousebundle") ?? .json]
        if savePanel.runModal() == .OK, let url = savePanel.url {
            let exportData = ProfileBundleExportData(profiles: uiServices.profiles)
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(exportData)
                try data.write(to: url)
            } catch {
                importError = "Failed to export profiles: \(error.localizedDescription)"
                showingImportError = true
            }
        }
    }
    
    private func importProfile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import Profile"
        openPanel.allowedContentTypes = [UTType(filenameExtension: "mouseprofile") ?? .json]
        if openPanel.runModal() == .OK, let url = openPanel.url {
            if let importedProfile = uiServices.importProfile(from: url) {
                selectedProfileId = importedProfile.id
            } else {
                importError = "Failed to import profile from the selected file"
                showingImportError = true
            }
        }
    }
    
    private func importMultipleProfiles() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import Profile Bundle"
        openPanel.allowedContentTypes = [UTType(filenameExtension: "mousebundle") ?? .json]
        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let bundle = try decoder.decode(ProfileBundleExportData.self, from: data)
                var importedCount = 0
                for var profile in bundle.profiles {
                    profile.id = UUID()
                    var importName = profile.name
                    var counter = 2
                    while uiServices.profiles.contains(where: { $0.name == importName }) {
                        importName = "\(profile.name) (\(counter))"
                        counter += 1
                    }
                    profile.name = importName
                    if uiServices.createProfile(name: profile.name, basedOn: profile) != nil { importedCount += 1 }
                }
                if importedCount > 0 { uiServices.loadData() }
                else {
                    importError = "No profiles were imported"
                    showingImportError = true
                }
            } catch {
                importError = "Failed to import profiles: \(error.localizedDescription)"
                showingImportError = true
            }
        }
    }
}

// MARK: - Profile List Row

struct ProfileListRow: View {
    let profile: ConfigurationProfile
    let isActive: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onSetActive: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: MGStyle.Spacing.lg) {
            // Active indicator dot
            Circle()
                .fill(isActive ? Color.green : Color.clear)
                .frame(width: 6, height: 6)
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                HStack(spacing: MGStyle.Spacing.md) {
                    Text(profile.name)
                        .font(.system(size: MGStyle.FontSize.body, weight: isActive ? .semibold : .medium))
                        .lineLimit(1)
                    
                    if profile.isDefault { MGBadge("Default") }
                }
                
                HStack(spacing: MGStyle.Spacing.lg) {
                    Text("\(profile.gestures.count) gestures")
                        .font(.system(size: MGStyle.FontSize.caption))
                        .foregroundColor(.secondary)
                    
                    if profile.hapticFeedbackEnabled {
                        Image(systemName: "waveform")
                            .font(.system(size: MGStyle.FontSize.badge))
                            .foregroundColor(.secondary)
                    }
                    if profile.keyboardShortcut != nil {
                        Image(systemName: "keyboard")
                            .font(.system(size: MGStyle.FontSize.badge))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .mgListRow(isSelected: isSelected, isHovered: isHovered)
        .onHover { hovering in isHovered = hovering }
        .onTapGesture { onSelect() }
        .contextMenu {
            if !isActive {
                Button(action: onSetActive) { Label("Set as Active", systemImage: "checkmark.circle") }
                Divider()
            }
            Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
            if !isActive && !profile.isDefault {
                Divider()
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            }
        }
    }
}

// MARK: - Profile Detail Editor (Inline Editing)

struct ProfileDetailEditor: View {
    let profile: ConfigurationProfile
    let isActive: Bool
    let onActivate: () -> Void
    let onDuplicate: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    
    @StateObject private var uiServices = UIServices.shared
    
    // Editable state
    @State private var editingName = false
    @State private var nameText = ""
    @State private var hapticEnabled: Bool = true
    @State private var edgeThreshold: CGFloat = 30
    @State private var cornerSize: CGFloat = 100
    @State private var cornerBuffer: CGFloat = 50
    @State private var showNameError = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xl) {
                // Header with inline name editing
                profileHeader
                
                // Quick actions bar
                actionBar
                
                // Editable zone settings
                zoneSettingsCard
                
                // Gesture overview
                gestureOverviewCard
            }
            .padding(MGStyle.Spacing.xl)
        }
        .background(MGStyle.Colors.contentBackground)
        .onAppear { loadProfileData() }
        .onChange(of: profile.id) { _ in loadProfileData() }
        .alert("Invalid Name", isPresented: $showNameError) { Button("OK") {} } message: {
            Text("A profile with this name already exists.")
        }
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                // Editable name
                if editingName {
                    HStack(spacing: MGStyle.Spacing.md) {
                        TextField("Profile name", text: $nameText, onCommit: commitNameEdit)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                            .frame(maxWidth: 300)
                        
                        Button(action: commitNameEdit) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { editingName = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: MGStyle.Spacing.md) {
                        Text(profile.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Button(action: {
                            nameText = profile.name
                            editingName = true
                        }) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Rename profile")
                    }
                }
                
                HStack(spacing: MGStyle.Spacing.md) {
                    if isActive {
                        MGBadge("Active", color: .green, icon: "checkmark.circle")
                    }
                    if profile.isDefault { MGBadge("Default") }
                    
                    Text("Modified: \(profile.modifiedDate, formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if !isActive {
                Button(action: onActivate) {
                    Label("Set Active", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
    
    // MARK: - Quick Actions
    
    private var actionBar: some View {
        HStack(spacing: MGStyle.Spacing.lg) {
            Button(action: onDuplicate) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .controlSize(.small)
            
            Button(action: onExport) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .controlSize(.small)
            
            Spacer()
            
            if !isActive && !profile.isDefault {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
        .padding(MGStyle.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                .fill(MGStyle.Colors.cardBackground.opacity(0.5))
        )
    }
    
    // MARK: - Zone Settings (Inline Editable)
    
    private var zoneSettingsCard: some View {
        MGDetailSection("Zone Detection", icon: "square.grid.3x3") {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                // Edge Threshold
                HStack {
                    Text("Edge Threshold")
                        .font(.system(size: MGStyle.FontSize.body))
                        .frame(width: 120, alignment: .leading)
                    Slider(value: $edgeThreshold, in: 10...100, step: 5) { _ in saveZoneSettings() }
                    Text("\(Int(edgeThreshold)) px")
                        .font(.system(size: MGStyle.FontSize.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 45, alignment: .trailing)
                }
                
                // Corner Size
                HStack {
                    Text("Corner Size")
                        .font(.system(size: MGStyle.FontSize.body))
                        .frame(width: 120, alignment: .leading)
                    Slider(value: $cornerSize, in: 50...200, step: 10) { _ in saveZoneSettings() }
                    Text("\(Int(cornerSize)) px")
                        .font(.system(size: MGStyle.FontSize.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 45, alignment: .trailing)
                }
                
                // Corner Buffer
                HStack {
                    Text("Corner Buffer")
                        .font(.system(size: MGStyle.FontSize.body))
                        .frame(width: 120, alignment: .leading)
                    Slider(value: $cornerBuffer, in: 20...100, step: 5) { _ in saveZoneSettings() }
                    Text("\(Int(cornerBuffer)) px")
                        .font(.system(size: MGStyle.FontSize.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 45, alignment: .trailing)
                }
                
                Divider()
                
                // Haptic Feedback Toggle
                Toggle(isOn: $hapticEnabled) {
                    HStack(spacing: MGStyle.Spacing.md) {
                        Image(systemName: "waveform")
                            .foregroundColor(.secondary)
                        Text("Haptic Feedback")
                            .font(.system(size: MGStyle.FontSize.body))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: hapticEnabled) { _ in saveZoneSettings() }
            }
        }
    }
    
    // MARK: - Gesture Overview
    
    private var gestureOverviewCard: some View {
        MGDetailSection("Gestures", icon: "hand.tap") {
            // Stats row
            HStack(spacing: MGStyle.Spacing.xxl) {
                statBubble("\(profile.gestures.count)", label: "Total")
                statBubble("\(profile.gestures.filter { $0.isEnabled }.count)", label: "Active", color: .green)
                statBubble("\(profile.gestures.filter { !$0.isEnabled }.count)", label: "Disabled", color: .gray)
            }
            
            if !profile.gestures.isEmpty {
                Divider()
                
                // Compact gesture list
                VStack(spacing: MGStyle.Spacing.sm) {
                    ForEach(profile.gestures, id: \.id) { gesture in
                        HStack(spacing: MGStyle.Spacing.md) {
                            MGZoneIndicator(zone: gesture.zone)
                            
                            Circle()
                                .fill(gesture.isEnabled ? Color.green : Color.gray)
                                .frame(width: 6, height: 6)
                            
                            Text(gesture.displayDescription)
                                .font(.system(size: MGStyle.FontSize.caption))
                                .lineLimit(1)
                                .opacity(gesture.isEnabled ? 1 : 0.5)
                            
                            Spacer()
                            
                            if let def = UIServices.shared.getActionDefinition(for: gesture.actionIdentifier) {
                                Text(def.name)
                                    .font(.system(size: MGStyle.FontSize.badge))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, MGStyle.Spacing.xs)
                    }
                }
            }
            
            if profile.keyboardShortcut != nil {
                Divider()
                HStack(spacing: MGStyle.Spacing.md) {
                    Image(systemName: "keyboard")
                        .foregroundColor(.secondary)
                    Text("Quick Switch: \(profile.keyboardShortcut!.displayString)")
                        .font(.system(size: MGStyle.FontSize.caption))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func statBubble(_ value: String, label: String, color: Color = .accentColor) -> some View {
        VStack(spacing: MGStyle.Spacing.xs) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: MGStyle.FontSize.badge))
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 60)
        .padding(MGStyle.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                .fill(color.opacity(0.08))
        )
    }
    
    // MARK: - Helpers
    
    private func loadProfileData() {
        nameText = profile.name
        hapticEnabled = profile.hapticFeedbackEnabled
        edgeThreshold = profile.edgeThreshold
        cornerSize = profile.cornerSize
        cornerBuffer = profile.cornerBuffer
    }
    
    private func commitNameEdit() {
        let trimmed = nameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { editingName = false; return }
        
        if trimmed != profile.name {
            if uiServices.profiles.contains(where: { $0.name == trimmed && $0.id != profile.id }) {
                showNameError = true
                return
            }
            _ = uiServices.renameProfile(profile.id, to: trimmed)
        }
        editingName = false
    }
    
    private func saveZoneSettings() {
        // Zone settings are stored per-profile; save through the config system
        // For now, this uses the configuration directly since UIServices doesn't
        // expose per-profile zone setting updates
        if isActive {
            uiServices.setEdgeThreshold(edgeThreshold)
            uiServices.setCornerSize(cornerSize)
            uiServices.setCornerBuffer(cornerBuffer)
            uiServices.setHapticFeedbackEnabled(hapticEnabled)
        }
    }
    
    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }
}

// MARK: - Add/Edit Profile Sheet

struct AddEditProfileSheet: View {
    enum Mode {
        case add, edit(ConfigurationProfile)
        var title: String { if case .add = self { return "Create New Profile" }; return "Edit Profile" }
        var buttonTitle: String { if case .add = self { return "Create" }; return "Save" }
    }
    
    let mode: Mode
    let onSave: (ConfigurationProfile) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    
    @State private var profileName: String = ""
    @State private var basedOnProfileId: UUID?
    @State private var hapticFeedbackEnabled: Bool = true
    @State private var edgeThreshold: CGFloat = 30
    @State private var cornerSize: CGFloat = 100
    @State private var cornerBuffer: CGFloat = 50
    @State private var keyboardShortcut: KeyboardTrigger?
    @State private var showingNameError = false
    
    init(mode: Mode, onSave: @escaping (ConfigurationProfile) -> Void) {
        self.mode = mode
        self.onSave = onSave
        if case .edit(let profile) = mode {
            _profileName = State(initialValue: profile.name)
            _hapticFeedbackEnabled = State(initialValue: profile.hapticFeedbackEnabled)
            _edgeThreshold = State(initialValue: profile.edgeThreshold)
            _cornerSize = State(initialValue: profile.cornerSize)
            _cornerBuffer = State(initialValue: profile.cornerBuffer)
            _keyboardShortcut = State(initialValue: profile.keyboardShortcut)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            MGSheetHeader(mode.title, onCancel: { dismiss() })
            
            ScrollView {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
                    MGDetailSection("Basics", icon: "pencil") {
                        LabeledContent("Name:") {
                            TextField("Profile name", text: $profileName).frame(width: 250)
                        }
                        if case .add = mode {
                            LabeledContent("Based on:") {
                                Picker("", selection: $basedOnProfileId) {
                                    Text("Empty Profile").tag(nil as UUID?)
                                    ForEach(uiServices.profiles.sorted { $0.name < $1.name }) { profile in
                                        Text(profile.name).tag(profile.id as UUID?)
                                    }
                                }
                                .pickerStyle(.menu).frame(width: 250)
                            }
                        }
                        Toggle("Haptic Feedback", isOn: $hapticFeedbackEnabled)
                    }
                    
                    MGDetailSection("Zone Detection", icon: "square.grid.3x3") {
                        LabeledContent("Edge Threshold:") {
                            HStack {
                                Slider(value: $edgeThreshold, in: 10...100, step: 5).frame(width: 150)
                                Text("\(Int(edgeThreshold)) px").frame(width: 50, alignment: .trailing)
                            }
                        }
                        LabeledContent("Corner Size:") {
                            HStack {
                                Slider(value: $cornerSize, in: 50...200, step: 10).frame(width: 150)
                                Text("\(Int(cornerSize)) px").frame(width: 50, alignment: .trailing)
                            }
                        }
                        LabeledContent("Corner Buffer:") {
                            HStack {
                                Slider(value: $cornerBuffer, in: 20...100, step: 5).frame(width: 150)
                                Text("\(Int(cornerBuffer)) px").frame(width: 50, alignment: .trailing)
                            }
                        }
                    }
                    
                    MGDetailSection("Quick Switch", icon: "keyboard") {
                        Text("Set a keyboard shortcut to quickly switch to this profile")
                            .font(.caption).foregroundColor(.secondary)
                        LabeledContent("Keyboard Shortcut:") {
                            KeyboardShortcutFieldView(shortcut: $keyboardShortcut)
                                .frame(width: 200, height: 24)
                        }
                        if keyboardShortcut != nil {
                            Button("Clear Shortcut") { keyboardShortcut = nil }.buttonStyle(.link)
                        }
                    }
                }
                .padding(MGStyle.Spacing.xl)
            }
            
            MGSheetFooter(mode.buttonTitle, disabled: profileName.isEmpty) { saveProfile() }
        }
        .frame(width: 550, height: 520)
        .alert("Invalid Name", isPresented: $showingNameError) { Button("OK") {} } message: {
            Text("A profile with this name already exists. Please choose a different name.")
        }
    }
    
    private func saveProfile() {
        if case .edit(let existingProfile) = mode {
            if existingProfile.name != profileName {
                if uiServices.profiles.contains(where: { $0.name == profileName }) {
                    showingNameError = true; return
                }
            }
            if uiServices.renameProfile(existingProfile.id, to: profileName) {
                onSave(existingProfile); dismiss()
            }
        } else {
            if uiServices.profiles.contains(where: { $0.name == profileName }) {
                showingNameError = true; return
            }
            var newProfile: ConfigurationProfile?
            if let baseId = basedOnProfileId,
               let baseProfile = uiServices.profiles.first(where: { $0.id == baseId }) {
                newProfile = uiServices.createProfile(name: profileName, basedOn: baseProfile)
            } else {
                newProfile = uiServices.createProfile(name: profileName)
            }
            if let profile = newProfile { onSave(profile); dismiss() }
        }
    }
}

// MARK: - Import Templates Sheet

struct ImportTemplatesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedTypes: Set<DefaultProfileType> = []
    @State private var isImporting = false
    @State private var importResults: [(type: DefaultProfileType, success: Bool, message: String)] = []
    @State private var showingResults = false
    
    var body: some View {
        VStack(spacing: 0) {
            MGSheetHeader("Import Template Profiles", subtitle: "Choose pre-configured profile templates to import", onCancel: { dismiss() })
            
            HStack {
                Button(selectedTypes.count == DefaultProfileType.allCases.count ? "Deselect All" : "Select All") {
                    if selectedTypes.count == DefaultProfileType.allCases.count { selectedTypes.removeAll() }
                    else { selectedTypes = Set(DefaultProfileType.allCases) }
                }
                .buttonStyle(.link)
                .padding(.horizontal, MGStyle.Spacing.xl)
                Spacer()
            }
            .padding(.vertical, MGStyle.Spacing.md)
            
            ScrollView {
                VStack(spacing: MGStyle.Spacing.lg) {
                    ForEach(DefaultProfileType.allCases, id: \.self) { type in
                        TemplateProfileCard(
                            type: type,
                            isSelected: selectedTypes.contains(type),
                            onSelect: {
                                if selectedTypes.contains(type) { selectedTypes.remove(type) }
                                else { selectedTypes.insert(type) }
                            }
                        )
                    }
                }
                .padding(MGStyle.Spacing.xl)
            }
            
            MGSheetFooter("Import Selected", disabled: selectedTypes.isEmpty || isImporting) {
                importSelectedTemplates()
            } leading: {
                if !selectedTypes.isEmpty {
                    Text("\(selectedTypes.count) template\(selectedTypes.count == 1 ? "" : "s") selected")
                        .font(.caption).foregroundColor(.secondary)
                }
                if isImporting { ProgressView().scaleEffect(0.8).padding(.horizontal, MGStyle.Spacing.md) }
            }
        }
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showingResults) {
            ImportResultsSheet(results: importResults) { dismiss() }
        }
    }
    
    private func importSelectedTemplates() {
        isImporting = true
        importResults.removeAll()
        DispatchQueue.global(qos: .userInitiated).async {
            for type in selectedTypes {
                let success = UIServices.shared.importDefaultProfile(type: type)
                let message = success ? "Successfully imported" : "Failed to import (name conflict or error)"
                DispatchQueue.main.async { importResults.append((type: type, success: success, message: message)) }
            }
            DispatchQueue.main.async {
                isImporting = false
                if !importResults.isEmpty { showingResults = true }
            }
        }
    }
}

// MARK: - Template Profile Card

struct TemplateProfileCard: View {
    let type: DefaultProfileType
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: MGStyle.Spacing.xl) {
            Image(systemName: type.iconName)
                .font(.system(size: 32))
                .foregroundColor(.accentColor)
                .frame(width: 50)
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                Text(type.rawValue).font(.headline)
                Text(type.description).font(.caption).foregroundColor(.secondary).lineLimit(2)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
            }
        }
        .padding(MGStyle.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : MGStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

// MARK: - Import Results Sheet

struct ImportResultsSheet: View {
    let results: [(type: DefaultProfileType, success: Bool, message: String)]
    let onDone: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            MGSheetHeader(
                "Import Results",
                subtitle: "\(results.filter { $0.success }.count) of \(results.count) templates imported successfully"
            )
            
            ScrollView {
                VStack(spacing: MGStyle.Spacing.md) {
                    ForEach(results, id: \.type) { result in
                        HStack(spacing: MGStyle.Spacing.lg) {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.success ? .green : .red)
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                                Text(result.type.rawValue)
                                    .font(.system(size: MGStyle.FontSize.heading, weight: .medium))
                                Text(result.message).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(MGStyle.Spacing.lg)
                        .background(
                            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                                .fill(result.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        )
                    }
                }
                .padding(MGStyle.Spacing.xl)
            }
            
            MGSheetFooter("Done") { onDone() }
        }
        .frame(width: 450, height: 400)
    }
}
