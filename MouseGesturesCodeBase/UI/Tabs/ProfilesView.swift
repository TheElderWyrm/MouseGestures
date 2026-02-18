import SwiftUI
import UniformTypeIdentifiers

// MARK: - Profiles Tab
struct ProfilesView: View {
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedProfileIds = Set<UUID>()
    enum ActiveSheet: Identifiable {
        case addProfile
        case importTemplates
        case editGesture(UUID, Gesture)
        case addGesture(UUID)
        
        var id: String {
            switch self {
            case .addProfile: return "add"
            case .importTemplates: return "import"
            case .editGesture(let pid, let g): return "editG-\(pid)-\(g.id)"
            case .addGesture(let pid): return "addG-\(pid)"
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
    
    @State private var primaryProfileId: UUID?
    
    private var primaryProfile: ConfigurationProfile? {
        guard let id = primaryProfileId else { return nil }
        return uiServices.profiles.first { $0.id == id }
    }
    
    private var multipleSelected: Bool { selectedProfileIds.count > 1 }
    
    var body: some View {
        VStack(spacing: 0) {
            MGCompactHeader(
                "Profiles",
                subtitle: "\(uiServices.profiles.count) profile\(uiServices.profiles.count == 1 ? "" : "s") configured",
                menuItems: [
                    MGMenuItem("Import Templates", icon: "square.grid.2x2") { activeSheet = .importTemplates },
                    .divider,
                    MGMenuItem("Export Selected", icon: "square.and.arrow.up", disabled: selectedProfileIds.isEmpty) { exportSelectedProfiles() },
                    MGMenuItem("Export All Profiles", icon: "square.and.arrow.up.on.square", disabled: uiServices.profiles.isEmpty) { exportAllProfiles() },
                    .divider,
                    MGMenuItem("Import Profile", icon: "square.and.arrow.down") { importProfile() },
                    MGMenuItem("Import Profile Bundle", icon: "square.and.arrow.down.on.square") { importMultipleProfiles() },
                    .divider,
                    MGMenuItem("Duplicate Selected", icon: "plus.square.on.square", disabled: selectedProfileIds.isEmpty) { duplicateSelectedProfiles() },
                    MGMenuItem("Delete Selected", icon: "trash", disabled: selectedProfileIds.isEmpty, destructive: true) { showingDeleteConfirmation = true }
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
            
            if multipleSelected {
                selectionBar
            }
            
            HSplitView {
                profileListView
                    .frame(minWidth: MGStyle.Layout.sidebarMinWidth, idealWidth: 280, maxWidth: 350)
                
                if let profile = primaryProfile {
                    ProfileDetailEditor(
                        profile: profile,
                        isActive: profile.id == uiServices.activeProfileId,
                        onActivate: { setActiveProfile(profile.id) },
                        onDuplicate: { duplicateProfile(profile.id) },
                        onExport: { exportSingleProfile(profile.id) },
                        onDelete: {
                            selectedProfileIds = [profile.id]
                            showingDeleteConfirmation = true
                        },
                        onEditGesture: { gesture in
                            activeSheet = .editGesture(profile.id, gesture)
                        },
                        onAddGesture: {
                            activeSheet = .addGesture(profile.id)
                        }
                    )
                    .frame(minWidth: 450)
                } else if multipleSelected {
                    multiSelectionDetailView
                        .frame(minWidth: 450)
                } else {
                    MGEmptyState(icon: "person.2.square.stack", title: "Select a profile", description: "Choose a profile from the list to view and edit its settings")
                        .frame(minWidth: 450)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addProfile:
                AddEditProfileSheet(mode: .add, onSave: { newProfile in
                    selectedProfileIds = [newProfile.id]
                    primaryProfileId = newProfile.id
                }, onImportTemplate: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        activeSheet = .importTemplates
                    }
                })
            case .importTemplates:
                ImportTemplatesSheet()
            case .editGesture(let profileId, let gesture):
                EditProfileGestureSheet(profileId: profileId, gesture: gesture)
            case .addGesture(let profileId):
                AddProfileGestureSheet(profileId: profileId)
            }
        }
        .alert("Delete Profile\(selectedProfileIds.count > 1 ? "s" : "")", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteSelectedProfiles() }
        } message: {
            let count = selectedProfileIds.count
            let hasActive = selectedProfileIds.contains(uiServices.activeProfileId ?? UUID())
            if count == 1, let profile = uiServices.profiles.first(where: { selectedProfileIds.contains($0.id) }) {
                if hasActive {
                    Text("Are you sure you want to delete the active profile '\(profile.name)'? A new profile will be activated automatically.")
                } else {
                    Text("Are you sure you want to delete '\(profile.name)'? This action cannot be undone.")
                }
            } else {
                Text("Are you sure you want to delete \(count) profiles? This action cannot be undone.")
            }
        }
        .alert("Import Error", isPresented: $showingImportError) {
            Button("OK") {}
        } message: {
            Text(importError ?? "Failed to import profile")
        }
        .onAppear {
            uiServices.loadData()
            if primaryProfileId == nil { primaryProfileId = uiServices.activeProfileId }
            if let pid = primaryProfileId { selectedProfileIds = [pid] }
        }
    }
    
    // MARK: - Selection Bar
    
    private var selectionBar: some View {
        HStack(spacing: MGStyle.Spacing.lg) {
            Text("\(selectedProfileIds.count) profiles selected")
                .font(.system(size: MGStyle.FontSize.caption, weight: .medium))
                .foregroundColor(.accentColor)
            
            Spacer()
            
            Button(action: duplicateSelectedProfiles) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .controlSize(.small)
            
            Button(action: exportSelectedProfiles) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .controlSize(.small)
            
            Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                Label("Delete", systemImage: "trash")
            }
            .controlSize(.small)
            
            Button("Clear Selection") {
                if let pid = primaryProfileId {
                    selectedProfileIds = [pid]
                } else {
                    selectedProfileIds.removeAll()
                }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, MGStyle.Spacing.xl)
        .padding(.vertical, MGStyle.Spacing.md)
        .background(Color.accentColor.opacity(0.08))
    }
    
    // MARK: - Multi-Selection Detail View
    
    private var multiSelectionDetailView: some View {
        let selected = uiServices.profiles.filter { selectedProfileIds.contains($0.id) }
        let totalGestures = selected.reduce(0) { $0 + $1.gestures.count }
        
        return VStack(spacing: MGStyle.Spacing.xxl) {
            Image(systemName: "person.2.square.stack")
                .font(.system(size: MGStyle.IconSize.emptyState))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("\(selected.count) Profiles Selected")
                .font(.headline)
            
            Text("\(totalGestures) total gestures across selected profiles")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: MGStyle.Spacing.lg) {
                Button(action: duplicateSelectedProfiles) {
                    Label("Duplicate All", systemImage: "plus.square.on.square")
                }
                
                Button(action: exportSelectedProfiles) {
                    Label("Export All", systemImage: "square.and.arrow.up")
                }
                
                Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                    Label("Delete All", systemImage: "trash")
                }
            }
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(MGStyle.Spacing.xxl)
    }
    
    // MARK: - Profile List View
    
    private var profileListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(spacing: MGStyle.Spacing.sm) {
                    ForEach(filteredProfiles) { profile in
                        ProfileListRow(
                            profile: profile,
                            isActive: profile.id == uiServices.activeProfileId,
                            isSelected: selectedProfileIds.contains(profile.id),
                            isPrimary: profile.id == primaryProfileId,
                            onSelect: { event in handleProfileSelect(profile.id, event: event) },
                            onSetActive: { setActiveProfile(profile.id) },
                            onDuplicate: { duplicateProfile(profile.id) },
                            onDelete: {
                                selectedProfileIds = [profile.id]
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
        .background(MGStyle.Colors.windowBackground)
    }
    
    // MARK: - Selection Logic
    
    private func handleProfileSelect(_ profileId: UUID, event: SelectionEvent) {
        switch event {
        case .click:
            selectedProfileIds = [profileId]
            primaryProfileId = profileId
        case .commandClick:
            if selectedProfileIds.contains(profileId) {
                selectedProfileIds.remove(profileId)
                if primaryProfileId == profileId {
                    primaryProfileId = selectedProfileIds.first
                }
            } else {
                selectedProfileIds.insert(profileId)
                primaryProfileId = profileId
            }
        case .shiftClick:
            let sorted = filteredProfiles
            if let currentIdx = sorted.firstIndex(where: { $0.id == primaryProfileId }),
               let targetIdx = sorted.firstIndex(where: { $0.id == profileId }) {
                let range = min(currentIdx, targetIdx)...max(currentIdx, targetIdx)
                for i in range { selectedProfileIds.insert(sorted[i].id) }
            } else {
                selectedProfileIds.insert(profileId)
            }
            primaryProfileId = profileId
        }
    }
    
    // MARK: - Helper Methods
    
    private func setActiveProfile(_ profileId: UUID) {
        uiServices.switchToProfile(profileId)
    }
    
    private func deleteSelectedProfiles() {
        var toDelete = Array(selectedProfileIds)
        if let activeId = uiServices.activeProfileId, toDelete.contains(activeId) {
            let remaining = uiServices.profiles.filter { !toDelete.contains($0.id) }
            if let next = remaining.first {
                uiServices.switchToProfile(next.id)
            } else {
                if let replacement = uiServices.createProfile(name: "Default") {
                    uiServices.switchToProfile(replacement.id)
                }
            }
            toDelete.removeAll { $0 == activeId }
            toDelete.append(activeId)
        }
        for profileId in toDelete {
            if profileId == uiServices.configuration.activeProfileId { continue }
            _ = uiServices.deleteProfile(profileId)
        }
        selectedProfileIds.removeAll()
        primaryProfileId = uiServices.activeProfileId
        if let pid = primaryProfileId { selectedProfileIds = [pid] }
        uiServices.loadData()
    }
    
    private func duplicateProfile(_ profileId: UUID) {
        if let newProfile = uiServices.duplicateProfile(profileId) {
            selectedProfileIds = [newProfile.id]
            primaryProfileId = newProfile.id
        }
    }
    
    private func duplicateSelectedProfiles() {
        var newIds: [UUID] = []
        for profileId in selectedProfileIds {
            if let dup = uiServices.duplicateProfile(profileId) { newIds.append(dup.id) }
        }
        if let first = newIds.first {
            selectedProfileIds = Set(newIds)
            primaryProfileId = first
        }
    }
    
    private func exportSelectedProfiles() {
        let selected = uiServices.profiles.filter { selectedProfileIds.contains($0.id) }
        guard !selected.isEmpty else { return }
        if selected.count == 1, let profile = selected.first {
            exportSingleProfile(profile.id)
        } else {
            let savePanel = NSSavePanel()
            savePanel.title = "Export \(selected.count) Profiles"
            savePanel.nameFieldStringValue = "MouseGestures_Profiles.mousebundle"
            savePanel.allowedContentTypes = [UTType(filenameExtension: "mousebundle") ?? .json]
            if savePanel.runModal() == .OK, let url = savePanel.url {
                let exportData = ProfileBundleExportData(profiles: selected)
                do {
                    let encoder = JSONEncoder(); encoder.outputFormatting = .prettyPrinted
                    let data = try encoder.encode(exportData)
                    try data.write(to: url)
                } catch {
                    importError = "Failed to export profiles: \(error.localizedDescription)"
                    showingImportError = true
                }
            }
        }
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
                let encoder = JSONEncoder(); encoder.outputFormatting = .prettyPrinted
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
                selectedProfileIds = [importedProfile.id]
                primaryProfileId = importedProfile.id
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
                        importName = "\(profile.name) (\(counter))"; counter += 1
                    }
                    profile.name = importName
                    if uiServices.createProfile(name: profile.name, basedOn: profile) != nil { importedCount += 1 }
                }
                if importedCount > 0 { uiServices.loadData() }
                else { importError = "No profiles were imported"; showingImportError = true }
            } catch {
                importError = "Failed to import profiles: \(error.localizedDescription)"
                showingImportError = true
            }
        }
    }
}

// MARK: - Selection Event

enum SelectionEvent {
    case click, commandClick, shiftClick
}

// MARK: - Profile List Row

struct ProfileListRow: View {
    let profile: ConfigurationProfile
    let isActive: Bool
    let isSelected: Bool
    let isPrimary: Bool
    let onSelect: (SelectionEvent) -> Void
    let onSetActive: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: MGStyle.Spacing.lg) {
            // Selection checkbox
            Button(action: { onSelect(.commandClick) }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : (isHovered ? .secondary.opacity(0.6) : .secondary.opacity(0.25)))
            }
            .buttonStyle(.plain)
            
            // Active indicator dot
            Circle()
                .fill(isActive ? Color.green : Color.clear)
                .frame(width: 6, height: 6)
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                Text(profile.name)
                    .font(.system(size: MGStyle.FontSize.body, weight: isActive ? .semibold : .medium))
                    .lineLimit(1)
                
                HStack(spacing: MGStyle.Spacing.md) {
                    Text("\(profile.gestures.count) gestures · \(profile.gestures.filter { $0.isEnabled }.count) active")
                        .font(.system(size: MGStyle.FontSize.badge))
                        .foregroundColor(.secondary)
                    
                    if let shortcut = profile.keyboardShortcut {
                        Text(shortcut.displayString)
                            .font(.system(size: MGStyle.FontSize.badge, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            }
            
            Spacer()
            
            // Hover actions
            HStack(spacing: MGStyle.Spacing.xs) {
                if !isActive {
                    MGActionButton("checkmark.circle", help: "Set as active") { onSetActive() }
                }
                MGActionButton("plus.square.on.square", help: "Duplicate") { onDuplicate() }
                MGActionButton("trash", help: "Delete", destructive: true) { onDelete() }
            }
        }
        .mgListRow(isSelected: isSelected, isHovered: isHovered, showBorder: isPrimary)
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering } }
        .gesture(
            TapGesture(count: 1).modifiers(.command).onEnded { _ in onSelect(.commandClick) }
        )
        .gesture(
            TapGesture(count: 1).modifiers(.shift).onEnded { _ in onSelect(.shiftClick) }
        )
        .onTapGesture(count: 2) { onSetActive() }
        .onTapGesture { onSelect(.click) }
        .contextMenu {
            if !isActive {
                Button(action: onSetActive) { Label("Set as Active", systemImage: "checkmark.circle") }
                Divider()
            }
            Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: - Profile Detail Editor

struct ProfileDetailEditor: View {
    let profile: ConfigurationProfile
    let isActive: Bool
    let onActivate: () -> Void
    let onDuplicate: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    let onEditGesture: (Gesture) -> Void
    let onAddGesture: () -> Void
    
    @StateObject private var uiServices = UIServices.shared
    
    @State private var editingName = false
    @State private var nameText = ""
    @State private var showNameError = false
    @State private var showDeleteGestureConfirm = false
    @State private var gestureToDelete: Gesture?
    @State private var editingShortcut: KeyboardTrigger?
    @State private var editingShortcutInline = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xl) {
                profileHeader
                actionBar
                gestureEditorCard
            }
            .padding(MGStyle.Spacing.xl)
        }
        .onAppear { loadProfileData() }
        .onChange(of: profile.id) { _ in loadProfileData() }
        .onChange(of: editingShortcut) { newShortcut in
            _ = uiServices.updateProfileKeyboardShortcut(profile.id, shortcut: newShortcut)
        }
        .alert("Invalid Name", isPresented: $showNameError) { Button("OK") {} } message: {
            Text("A profile with this name already exists.")
        }
        .confirmationDialog("Delete Gesture?", isPresented: $showDeleteGestureConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteGesture() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove this gesture from the profile.")
        }
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
            // Row 1: name + shortcut + set active button
            HStack(alignment: .center, spacing: MGStyle.Spacing.lg) {
                // Name
                if editingName {
                    HStack(spacing: MGStyle.Spacing.md) {
                        TextField("Profile name", text: $nameText, onCommit: commitNameEdit)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)
                            .frame(maxWidth: 240)
                        Button(action: commitNameEdit) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        Button(action: { editingName = false }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: MGStyle.Spacing.md) {
                        Text(profile.name).font(.title3).fontWeight(.semibold)
                        Button(action: { nameText = profile.name; editingName = true }) {
                            Image(systemName: "pencil").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Rename profile")
                    }
                }
                
                // Shortcut (inline)
                shortcutInlineView
                
                Spacer()
                
                if !isActive {
                    Button(action: onActivate) {
                        Label("Set Active", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            
            // Row 2: status metadata
            HStack(spacing: MGStyle.Spacing.xl) {
                if isActive {
                    HStack(spacing: MGStyle.Spacing.sm) {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                        Text("Active").font(.system(size: MGStyle.FontSize.caption)).foregroundColor(.green)
                    }
                }
                HStack(spacing: MGStyle.Spacing.sm) {
                    Image(systemName: "hand.draw").font(.system(size: 10)).foregroundColor(.secondary)
                    Text("\(profile.gestures.count) gestures · \(profile.gestures.filter { $0.isEnabled }.count) active")
                        .font(.system(size: MGStyle.FontSize.caption)).foregroundColor(.secondary)
                }
                Text("Modified \(profile.modifiedDate, formatter: dateFormatter)")
                    .font(.system(size: MGStyle.FontSize.caption)).foregroundColor(.secondary.opacity(0.6))
            }
        }
    }
    
    // Inline shortcut: text when idle, field when editing
    @ViewBuilder
    private var shortcutInlineView: some View {
        if editingShortcutInline {
            HStack(spacing: MGStyle.Spacing.sm) {
                Image(systemName: "keyboard").font(.system(size: 10)).foregroundColor(.secondary)
                KeyboardShortcutFieldView(shortcut: $editingShortcut)
                    .frame(width: 180, height: 22)
                if editingShortcut != nil {
                    Button("Clear") {
                        editingShortcut = nil
                    }
                    .buttonStyle(.link)
                    .font(.system(size: MGStyle.FontSize.badge))
                    .controlSize(.small)
                }
                Button(action: { editingShortcutInline = false }) {
                    Image(systemName: "checkmark").font(.system(size: 10)).foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Done")
            }
            .transition(.opacity)
        } else {
            Button(action: { editingShortcutInline = true }) {
                HStack(spacing: MGStyle.Spacing.sm) {
                    Image(systemName: "keyboard").font(.system(size: 10)).foregroundColor(.secondary)
                    if let shortcut = editingShortcut {
                        Text(shortcut.displayString)
                            .font(.system(size: MGStyle.FontSize.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Add shortcut")
                            .font(.system(size: MGStyle.FontSize.caption))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Edit quick switch shortcut")
            .transition(.opacity)
        }
    }
    
    // MARK: - Quick Actions
    
    private var actionBar: some View {
        HStack(spacing: MGStyle.Spacing.lg) {
            Button(action: onDuplicate) { Label("Duplicate", systemImage: "plus.square.on.square") }
                .controlSize(.small)
            Button(action: onExport) { Label("Export", systemImage: "square.and.arrow.up") }
                .controlSize(.small)
            Spacer()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
                .controlSize(.small)
        }
        .padding(MGStyle.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                .fill(MGStyle.Colors.cardBackground.opacity(0.5))
        )
    }
    
    // MARK: - Editable Gesture List
    
    private var gestureEditorCard: some View {
        MGDetailSection("Gestures", icon: "hand.tap") {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onAddGesture) { Label("Add Gesture", systemImage: "plus") }
                        .controlSize(.small)
                }
                .padding(.bottom, MGStyle.Spacing.md)
                
                if profile.gestures.isEmpty {
                    Text("No gestures configured")
                        .font(.system(size: MGStyle.FontSize.caption))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, MGStyle.Spacing.xl)
                } else {
                    VStack(spacing: MGStyle.Spacing.xs) {
                        ForEach(profile.gestures, id: \.id) { gesture in
                            ProfileGestureRow(
                                gesture: gesture,
                                onEdit: { onEditGesture(gesture) },
                                onDelete: { gestureToDelete = gesture; showDeleteGestureConfirm = true },
                                onToggleEnabled: { enabled in toggleGestureEnabled(gesture, enabled: enabled) }
                            )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func loadProfileData() {
        nameText = profile.name
        editingShortcut = profile.keyboardShortcut
    }
    
    private func commitNameEdit() {
        let trimmed = nameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { editingName = false; return }
        if trimmed != profile.name {
            if uiServices.profiles.contains(where: { $0.name == trimmed && $0.id != profile.id }) {
                showNameError = true; return
            }
            _ = uiServices.renameProfile(profile.id, to: trimmed)
        }
        editingName = false
    }
    
    private func toggleGestureEnabled(_ gesture: Gesture, enabled: Bool) {
        var gestures = profile.gestures
        if let idx = gestures.firstIndex(where: { $0.id == gesture.id }) {
            gestures[idx].genericActivation.isEnabled = enabled
            _ = uiServices.updateProfileGestures(profile.id, gestures: gestures)
        }
    }
    
    private func deleteGesture() {
        guard let gesture = gestureToDelete else { return }
        var gestures = profile.gestures
        gestures.removeAll { $0.id == gesture.id }
        _ = uiServices.updateProfileGestures(profile.id, gestures: gestures)
        gestureToDelete = nil
    }
    
    private var dateFormatter: DateFormatter {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }
}

// MARK: - Profile Gesture Row

struct ProfileGestureRow: View {
    let gesture: Gesture
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleEnabled: (Bool) -> Void
    
    @State private var isEnabled: Bool
    @State private var isHovered = false
    
    init(gesture: Gesture, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void, onToggleEnabled: @escaping (Bool) -> Void) {
        self.gesture = gesture; self.onEdit = onEdit; self.onDelete = onDelete; self.onToggleEnabled = onToggleEnabled
        self._isEnabled = State(initialValue: gesture.isEnabled)
    }
    
    private var actionDef: PluginAction? { UIServices.shared.getActionDefinition(for: gesture.actionIdentifier) }
    
    var body: some View {
        HStack(spacing: MGStyle.Spacing.md) {
            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                .onChange(of: isEnabled) { v in onToggleEnabled(v) }
            
            Image(systemName: actionDef?.icon ?? "bolt")
                .font(.system(size: 10))
                .foregroundColor(isEnabled ? .accentColor : .secondary)
                .frame(width: 16)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(actionDef?.name ?? gesture.actionIdentifier)
                    .font(.system(size: MGStyle.FontSize.caption, weight: .medium))
                    .lineLimit(1).opacity(isEnabled ? 1 : 0.5)
                Text(gesture.displayDescription)
                    .font(.system(size: MGStyle.FontSize.badge))
                    .foregroundColor(.secondary).lineLimit(1).opacity(isEnabled ? 0.8 : 0.4)
            }
            
            Spacer()
            
            MGRowActions(actions: [
                .init("pencil", help: "Edit gesture") { onEdit() },
                .init("trash", help: "Delete gesture", destructive: true) { onDelete() }
            ])
        }
        .padding(.horizontal, MGStyle.Spacing.md)
        .padding(.vertical, MGStyle.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.sm)
                .fill(isHovered ? MGStyle.Colors.hoveredRow : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovered = h } }
        .onTapGesture(count: 2) { onEdit() }
        .contextMenu {
            Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
            Button(action: { isEnabled.toggle(); onToggleEnabled(isEnabled) }) {
                Label(isEnabled ? "Disable" : "Enable", systemImage: isEnabled ? "pause.circle" : "play.circle")
            }
            Divider()
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: - Edit Profile Gesture Sheet

struct EditProfileGestureSheet: View {
    let profileId: UUID
    let gesture: Gesture
    @StateObject private var uiServices = UIServices.shared
    
    var body: some View {
        GestureConfigurationSheet(mode: .edit, existingGesture: gesture) { updated in
            var gestures = uiServices.profiles.first(where: { $0.id == profileId })?.gestures ?? []
            if let idx = gestures.firstIndex(where: { $0.id == gesture.id }) {
                gestures[idx] = updated
                _ = uiServices.updateProfileGestures(profileId, gestures: gestures)
            }
        }
    }
}

// MARK: - Add Profile Gesture Sheet

struct AddProfileGestureSheet: View {
    let profileId: UUID
    @StateObject private var uiServices = UIServices.shared
    
    var body: some View {
        GestureConfigurationSheet(mode: .add) { newGesture in
            var gestures = uiServices.profiles.first(where: { $0.id == profileId })?.gestures ?? []
            gestures.append(newGesture)
            _ = uiServices.updateProfileGestures(profileId, gestures: gestures)
        }
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
    var onImportTemplate: (() -> Void)? = nil
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    
    @State private var profileName: String = ""
    @State private var basedOnProfileId: UUID?
    @State private var keyboardShortcut: KeyboardTrigger?
    @State private var showingNameError = false
    
    init(mode: Mode, onSave: @escaping (ConfigurationProfile) -> Void, onImportTemplate: (() -> Void)? = nil) {
        self.mode = mode; self.onSave = onSave; self.onImportTemplate = onImportTemplate
        if case .edit(let profile) = mode {
            _profileName = State(initialValue: profile.name)
            _keyboardShortcut = State(initialValue: profile.keyboardShortcut)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            MGSheetHeader(mode.title)
            
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
            
            MGSheetFooter(mode.buttonTitle, disabled: profileName.isEmpty, action: { saveProfile() }, cancel: { dismiss() }) {
                if case .add = mode, let onImportTemplate = onImportTemplate {
                    Button(action: { dismiss(); onImportTemplate() }) {
                        Label("Import from Template", systemImage: "square.grid.2x2")
                    }
                }
            }
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
            let nameChanged = uiServices.renameProfile(existingProfile.id, to: profileName)
            _ = uiServices.updateProfileKeyboardShortcut(existingProfile.id, shortcut: keyboardShortcut)
            if nameChanged { onSave(existingProfile); dismiss() }
        } else {
            if uiServices.profiles.contains(where: { $0.name == profileName }) {
                showingNameError = true; return
            }
            var newProfile: ConfigurationProfile?
            if let baseId = basedOnProfileId, let baseProfile = uiServices.profiles.first(where: { $0.id == baseId }) {
                newProfile = uiServices.createProfile(name: profileName, basedOn: baseProfile)
            } else {
                newProfile = uiServices.createProfile(name: profileName)
            }
            if let profile = newProfile {
                _ = uiServices.updateProfileKeyboardShortcut(profile.id, shortcut: keyboardShortcut)
                onSave(profile); dismiss()
            }
        }
    }
}

// MARK: - Import Templates Sheet

struct ImportTemplatesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedTypes: Set<DefaultProfileType> = []
    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var importSuccess = false
    
    var body: some View {
        VStack(spacing: 0) {
            MGSheetHeader("Import Template Profiles", subtitle: "Choose pre-configured profile templates to import")
            
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
            
            if let msg = importMessage {
                HStack(spacing: MGStyle.Spacing.md) {
                    Image(systemName: importSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(importSuccess ? .green : .orange)
                    Text(msg).font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, MGStyle.Spacing.xl)
                .padding(.vertical, MGStyle.Spacing.md)
            }
            
            MGSheetFooter("Import Selected", disabled: selectedTypes.isEmpty || isImporting, action: {
                importSelectedTemplates()
            }, cancel: { dismiss() }) {
                HStack(spacing: MGStyle.Spacing.lg) {
                    if !selectedTypes.isEmpty && !isImporting {
                        Text("\(selectedTypes.count) template\(selectedTypes.count == 1 ? "" : "s") selected")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if isImporting {
                        ProgressView().scaleEffect(0.8).padding(.horizontal, MGStyle.Spacing.md)
                    }
                }
            }
        }
        .frame(width: 600, height: 520)
    }
    
    private func importSelectedTemplates() {
        isImporting = true
        importMessage = nil
        var successCount = 0
        var failCount = 0
        
        DispatchQueue.global(qos: .userInitiated).async {
            for type in selectedTypes {
                if UIServices.shared.importDefaultProfile(type: type) { successCount += 1 }
                else { failCount += 1 }
            }
            DispatchQueue.main.async {
                isImporting = false
                UIServices.shared.loadData()
                if failCount == 0 {
                    importSuccess = true
                    importMessage = "Imported \(successCount) template\(successCount == 1 ? "" : "s") successfully"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
                } else {
                    importSuccess = successCount > 0
                    importMessage = successCount > 0
                        ? "Imported \(successCount), \(failCount) failed (name conflicts)"
                        : "\(failCount) import\(failCount == 1 ? "" : "s") failed (name conflicts)"
                }
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
                .font(.system(size: 24))
                .foregroundColor(.accentColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                Text(type.rawValue).font(.system(size: MGStyle.FontSize.heading, weight: .medium))
                Text(type.description).font(.caption).foregroundColor(.secondary).lineLimit(2)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor).font(.system(size: 16))
            }
        }
        .padding(MGStyle.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                .fill(isSelected ? Color.accentColor.opacity(0.06) : MGStyle.Colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                        .stroke(isSelected ? Color.accentColor.opacity(0.3) : MGStyle.Colors.separator.opacity(0.3), lineWidth: isSelected ? 1 : 0.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}
