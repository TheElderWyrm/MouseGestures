import SwiftUI
import UniformTypeIdentifiers

// MARK: - Profiles Tab
struct ProfilesView: View {
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedProfileId: UUID?
    // Sheet presentation - using single enum to avoid multiple .sheet modifier bug
    enum ActiveSheet: Identifiable {
        case addProfile
        case editProfile(ConfigurationProfile)
        case importTemplates
        
        var id: String {
            switch self {
            case .addProfile: return "add"
            case .editProfile(let p): return "edit-\(p.id)"
            case .importTemplates: return "import"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var showingDeleteConfirmation = false
    @State private var searchText = ""
    @State private var importError: String?
    @State private var showingImportError = false
    
    private var filteredProfiles: [ConfigurationProfile] {
        if searchText.isEmpty {
            return uiServices.profiles.sorted { $0.name < $1.name }
        }
        return uiServices.profiles
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.name < $1.name }
    }
    
    private var selectedProfile: ConfigurationProfile? {
        guard let id = selectedProfileId else { return nil }
        return uiServices.profiles.first { $0.id == id }
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
                // Profile List
                profileListView
                    .frame(minWidth: 300, idealWidth: 400)
                
                // Detail View
                if let profile = selectedProfile {
                    profileDetailView(profile: profile)
                        .frame(minWidth: 400)
                } else {
                    emptyDetailView
                        .frame(minWidth: 400)
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
            case .editProfile(let profile):
                AddEditProfileSheet(mode: .edit(profile)) { _ in
                    uiServices.loadData()
                }
            case .importTemplates:
                ImportTemplatesSheet()
            }
        }
        .alert("Delete Profile", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let profileId = selectedProfileId {
                    deleteProfile(profileId)
                }
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
            if selectedProfileId == nil {
                selectedProfileId = uiServices.activeProfileId
            }
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profiles")
                    .font(.largeTitle)
                    .bold()
                
                Text("\(uiServices.profiles.count) profile\(uiServices.profiles.count == 1 ? "" : "s") configured")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search profiles...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .frame(width: 200)
                
                Divider()
                    .frame(height: 20)
                
                // Import Templates
                Button(action: { activeSheet = .importTemplates }) {
                    Label("Templates", systemImage: "square.grid.2x2")
                }
                
                // Add Profile
                Button(action: { activeSheet = .addProfile }) {
                    Label("Add Profile", systemImage: "plus")
                }
                
                // Import/Export Menu
                Menu {
                    Button(action: exportProfile) {
                        Label("Export Profile...", systemImage: "square.and.arrow.up")
                    }
                    .disabled(selectedProfile == nil)
                    
                    Button(action: exportAllProfiles) {
                        Label("Export All Profiles...", systemImage: "square.and.arrow.up.on.square")
                    }
                    .disabled(uiServices.profiles.isEmpty)
                    
                    Divider()
                    
                    Button(action: importProfile) {
                        Label("Import Profile...", systemImage: "square.and.arrow.down")
                    }
                    
                    Button(action: importMultipleProfiles) {
                        Label("Import Profile Bundle...", systemImage: "square.and.arrow.down.on.square")
                    }
                } label: {
                    Label("Import/Export", systemImage: "arrow.up.arrow.down")
                }
            }
        }
    }
    
    // MARK: - Profile List View
    
    private var profileListView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // List Header
            HStack {
                Text("Available Profiles")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(filteredProfiles) { profile in
                        ProfileListRow(
                            profile: profile,
                            isActive: profile.id == uiServices.activeProfileId,
                            isSelected: profile.id == selectedProfileId,
                            onSelect: { selectedProfileId = profile.id },
                            onSetActive: { setActiveProfile(profile.id) },
                            onEdit: { 
                                selectedProfileId = profile.id
                                activeSheet = .editProfile(profile)
                            },
                            onDuplicate: { duplicateProfile(profile.id) },
                            onDelete: {
                                selectedProfileId = profile.id
                                showingDeleteConfirmation = true
                            }
                        )
                    }
                    
                    if filteredProfiles.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: searchText.isEmpty ? "folder" : "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary.opacity(0.5))
                            
                            Text(searchText.isEmpty ? "No profiles configured" : "No matching profiles")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            if searchText.isEmpty {
                                Button(action: { activeSheet = .addProfile }) {
                                    Label("Create Your First Profile", systemImage: "plus.circle")
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
    
    // MARK: - Profile Detail View
    
    private func profileDetailView(profile: ConfigurationProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(profile.name)
                            .font(.title2)
                            .bold()
                        
                        if profile.id == uiServices.activeProfileId {
                            Text("Active")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                        
                        if profile.isDefault {
                            Text("Default")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    
                    Text("Created: \(profile.createdDate, formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Modified: \(profile.modifiedDate, formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Statistics
                GroupBox("Statistics") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Total Gestures:") {
                            Text("\(profile.gestures.count)")
                                .fontWeight(.medium)
                        }
                        
                        LabeledContent("Enabled Gestures:") {
                            Text("\(profile.gestures.filter { $0.isEnabled }.count)")
                                .fontWeight(.medium)
                        }
                        
                        LabeledContent("Haptic Feedback:") {
                            Text(profile.hapticFeedbackEnabled ? "Enabled" : "Disabled")
                                .fontWeight(.medium)
                        }
                        
                        if let shortcut = profile.keyboardShortcut {
                            LabeledContent("Quick Switch:") {
                                Text(shortcut.displayString)
                                    .fontWeight(.medium)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Settings
                GroupBox("Zone Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Edge Threshold:") {
                            Text("\(Int(profile.edgeThreshold)) px")
                                .fontWeight(.medium)
                        }
                        
                        LabeledContent("Corner Size:") {
                            Text("\(Int(profile.cornerSize)) px")
                                .fontWeight(.medium)
                        }
                        
                        LabeledContent("Corner Buffer:") {
                            Text("\(Int(profile.cornerBuffer)) px")
                                .fontWeight(.medium)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // Gesture Summary
                if !profile.gestures.isEmpty {
                    GroupBox("Configured Gestures") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(profile.gestures.prefix(5)), id: \.id) { gesture in
                                HStack {
                                    Image(systemName: gesture.isEnabled ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(gesture.isEnabled ? .green : .gray)
                                        .font(.caption)
                                    
                                    Text(gesture.displayDescription)
                                        .font(.caption)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                }
                            }
                            
                            if profile.gestures.count > 5 {
                                Text("... and \(profile.gestures.count - 5) more")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Actions
                HStack {
                    if profile.id != uiServices.activeProfileId {
                        Button(action: { setActiveProfile(profile.id) }) {
                            Label("Set Active", systemImage: "checkmark.circle")
                        }
                    }
                    
                    Button(action: { 
                        selectedProfileId = profile.id
                        activeSheet = .editProfile(profile)
                    }) {
                        Label("Edit", systemImage: "pencil")
                    }
                    
                    Button(action: { duplicateProfile(profile.id) }) {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    
                    Button(action: { exportSingleProfile(profile.id) }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    
                    if profile.id != uiServices.activeProfileId && !profile.isDefault {
                        Button(action: { 
                            selectedProfileId = profile.id
                            showingDeleteConfirmation = true
                        }) {
                            Label("Delete", systemImage: "trash")
                                .foregroundColor(.red)
                        }
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
            Image(systemName: "person.2.square.stack")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Select a profile to view details")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Helper Methods
    
    private func setActiveProfile(_ profileId: UUID) {
        uiServices.switchToProfile(profileId)
    }
    
    private func deleteProfile(_ profileId: UUID) {
        if uiServices.deleteProfile(profileId) {
            selectedProfileId = uiServices.activeProfileId
        }
    }
    
    private func duplicateProfile(_ profileId: UUID) {
        if let newProfile = uiServices.duplicateProfile(profileId) {
            selectedProfileId = newProfile.id
        }
    }
    
    private func exportProfile() {
        guard let profileId = selectedProfileId else { return }
        exportSingleProfile(profileId)
    }
    
    private func exportSingleProfile(_ profileId: UUID) {
        guard let profile = uiServices.profiles.first(where: { $0.id == profileId }) else { return }
        
        let savePanel = NSSavePanel()
        savePanel.title = "Export Profile"
        savePanel.message = "Choose where to save the profile"
        savePanel.nameFieldStringValue = "\(profile.name).mouseprofile"
        savePanel.allowedContentTypes = [UTType(filenameExtension: "mouseprofile") ?? .json]
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            _ = uiServices.exportProfile(profileId, to: url)
        }
    }
    
    private func exportAllProfiles() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export All Profiles"
        savePanel.message = "Choose where to save the profile bundle"
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
        openPanel.message = "Choose a profile file to import"
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
        openPanel.message = "Choose a profile bundle file to import"
        openPanel.allowedContentTypes = [UTType(filenameExtension: "mousebundle") ?? .json]
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let bundle = try decoder.decode(ProfileBundleExportData.self, from: data)
                
                var importedCount = 0
                for var profile in bundle.profiles {
                    profile.id = UUID() // Generate new ID
                    
                    // Check for name conflicts
                    var importName = profile.name
                    var counter = 2
                    while uiServices.profiles.contains(where: { $0.name == importName }) {
                        importName = "\(profile.name) (\(counter))"
                        counter += 1
                    }
                    profile.name = importName
                    
                    // Create the profile
                    if uiServices.createProfile(name: profile.name, basedOn: profile) != nil {
                        importedCount += 1
                    }
                }
                
                if importedCount > 0 {
                    uiServices.loadData()
                } else {
                    importError = "No profiles were imported"
                    showingImportError = true
                }
            } catch {
                importError = "Failed to import profiles: \(error.localizedDescription)"
                showingImportError = true
            }
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

// MARK: - Profile List Row

struct ProfileListRow: View {
    let profile: ConfigurationProfile
    let isActive: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onSetActive: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(profile.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                    
                    if profile.isDefault {
                        Text("Default")
                            .font(.system(size: 10))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
                
                HStack(spacing: 12) {
                    Text("\(profile.gestures.count) gestures")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if profile.hapticFeedbackEnabled {
                        Image(systemName: "waveform")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    if profile.keyboardShortcut != nil {
                        Image(systemName: "keyboard")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if isHovered {
                HStack(spacing: 8) {
                    if !isActive {
                        Button(action: onSetActive) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .help("Set as active profile")
                    }
                    
                    Menu {
                        Button(action: onEdit) {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button(action: onDuplicate) {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        
                        if !isActive && !profile.isDefault {
                            Divider()
                            
                            Button(action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 11))
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

// MARK: - Add/Edit Profile Sheet

struct AddEditProfileSheet: View {
    enum Mode {
        case add
        case edit(ConfigurationProfile)
        
        var title: String {
            switch self {
            case .add: return "Create New Profile"
            case .edit: return "Edit Profile"
            }
        }
        
        var buttonTitle: String {
            switch self {
            case .add: return "Create"
            case .edit: return "Save"
            }
        }
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
        
        // Initialize state from existing profile if editing
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
            // Header
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
            
            Divider()
            
            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Basic Settings
                    GroupBox("Basic Settings") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("Name:") {
                                TextField("Profile name", text: $profileName)
                                    .frame(width: 250)
                            }
                            
                            if case .add = mode {
                                LabeledContent("Based on:") {
                                    Picker("", selection: $basedOnProfileId) {
                                        Text("Empty Profile").tag(nil as UUID?)
                                        ForEach(uiServices.profiles.sorted { $0.name < $1.name }) { profile in
                                            Text(profile.name).tag(profile.id as UUID?)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 250)
                                }
                            }
                            
                            Toggle("Haptic Feedback", isOn: $hapticFeedbackEnabled)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Zone Settings
                    GroupBox("Zone Detection Settings") {
                        VStack(alignment: .leading, spacing: 12) {
                            LabeledContent("Edge Threshold:") {
                                HStack {
                                    Slider(value: $edgeThreshold, in: 10...100, step: 5)
                                        .frame(width: 150)
                                    Text("\(Int(edgeThreshold)) px")
                                        .frame(width: 50, alignment: .trailing)
                                }
                            }
                            
                            LabeledContent("Corner Size:") {
                                HStack {
                                    Slider(value: $cornerSize, in: 50...200, step: 10)
                                        .frame(width: 150)
                                    Text("\(Int(cornerSize)) px")
                                        .frame(width: 50, alignment: .trailing)
                                }
                            }
                            
                            LabeledContent("Corner Buffer:") {
                                HStack {
                                    Slider(value: $cornerBuffer, in: 20...100, step: 5)
                                        .frame(width: 150)
                                    Text("\(Int(cornerBuffer)) px")
                                        .frame(width: 50, alignment: .trailing)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Quick Switch
                    GroupBox("Quick Switch (Optional)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Set a keyboard shortcut to quickly switch to this profile")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            LabeledContent("Keyboard Shortcut:") {
                                KeyboardShortcutFieldView(shortcut: $keyboardShortcut)
                                    .frame(width: 200, height: 24)
                            }
                            
                            if keyboardShortcut != nil {
                                Button("Clear Shortcut") {
                                    keyboardShortcut = nil
                                }
                                .buttonStyle(.link)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button(mode.buttonTitle) {
                    saveProfile()
                }
                .keyboardShortcut(.return)
                .disabled(profileName.isEmpty)
            }
            .padding()
        }
        .frame(width: 550, height: 500)
        .alert("Invalid Name", isPresented: $showingNameError) {
            Button("OK") {}
        } message: {
            Text("A profile with this name already exists. Please choose a different name.")
        }
    }
    
    private func saveProfile() {
        // Check for name conflicts (except when editing the same profile)
        if case .edit(let existingProfile) = mode {
            // When editing, only check if name changed
            if existingProfile.name != profileName {
                if uiServices.profiles.contains(where: { $0.name == profileName }) {
                    showingNameError = true
                    return
                }
            }
            
            // Update the existing profile
            if uiServices.renameProfile(existingProfile.id, to: profileName) {
                // Update other properties if needed (would require extending UIServices)
                onSave(existingProfile)
                dismiss()
            }
        } else {
            // Check for name conflicts when adding
            if uiServices.profiles.contains(where: { $0.name == profileName }) {
                showingNameError = true
                return
            }
            
            // Create new profile
            var newProfile: ConfigurationProfile?
            
            if let baseId = basedOnProfileId,
               let baseProfile = uiServices.profiles.first(where: { $0.id == baseId }) {
                newProfile = uiServices.createProfile(name: profileName, basedOn: baseProfile)
            } else {
                newProfile = uiServices.createProfile(name: profileName)
            }
            
            if let profile = newProfile {
                onSave(profile)
                dismiss()
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
    @State private var importResults: [(type: DefaultProfileType, success: Bool, message: String)] = []
    @State private var showingResults = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import Template Profiles")
                        .font(.title2)
                        .bold()
                    
                    Text("Choose pre-configured profile templates to import")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            
            Divider()
            
            // Selection controls
            HStack {
                Button(selectedTypes.count == DefaultProfileType.allCases.count ? "Deselect All" : "Select All") {
                    if selectedTypes.count == DefaultProfileType.allCases.count {
                        selectedTypes.removeAll()
                    } else {
                        selectedTypes = Set(DefaultProfileType.allCases)
                    }
                }
                .buttonStyle(.link)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.vertical, 8)
            
            // Template List
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(DefaultProfileType.allCases, id: \.self) { type in
                        TemplateProfileCard(
                            type: type,
                            isSelected: selectedTypes.contains(type),
                            onSelect: {
                                if selectedTypes.contains(type) {
                                    selectedTypes.remove(type)
                                } else {
                                    selectedTypes.insert(type)
                                }
                            }
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                if !selectedTypes.isEmpty {
                    Text("\(selectedTypes.count) template\(selectedTypes.count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if isImporting {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.horizontal, 8)
                }
                
                Button("Import Selected") {
                    importSelectedTemplates()
                }
                .keyboardShortcut(.return)
                .disabled(selectedTypes.isEmpty || isImporting)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showingResults) {
            ImportResultsSheet(results: importResults) {
                dismiss()
            }
        }
    }
    
    private func importSelectedTemplates() {
        isImporting = true
        importResults.removeAll()
        
        DispatchQueue.global(qos: .userInitiated).async {
            for type in selectedTypes {
                let success = UIServices.shared.importDefaultProfile(type: type)
                let message = success ? "Successfully imported" : "Failed to import (name conflict or error)"
                
                DispatchQueue.main.async {
                    importResults.append((type: type, success: success, message: message))
                }
            }
            
            DispatchQueue.main.async {
                isImporting = false
                if !importResults.isEmpty {
                    showingResults = true
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
        HStack(spacing: 16) {
            Image(systemName: type.iconName)
                .font(.system(size: 32))
                .foregroundColor(.accentColor)
                .frame(width: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(type.rawValue)
                    .font(.headline)
                
                Text(type.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Import Results Sheet

struct ImportResultsSheet: View {
    let results: [(type: DefaultProfileType, success: Bool, message: String)]
    let onDone: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Import Results")
                        .font(.title2)
                        .bold()
                    
                    Text("\(results.filter { $0.success }.count) of \(results.count) templates imported successfully")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Results List
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(results, id: \.type) { result in
                        HStack(spacing: 12) {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(result.success ? .green : .red)
                                .font(.system(size: 20))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.type.rawValue)
                                    .font(.system(size: 14, weight: .medium))
                                
                                Text(result.message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(result.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Done") {
                    onDone()
                }
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 450, height: 400)
    }
}
