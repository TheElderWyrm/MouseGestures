import SwiftUI
import AppKit

// MARK: - App Profile Rule Type
enum AppProfileRuleType: String, CaseIterable {
    case useProfile = "Use Specific Profile"
    case disabled = "Disable Gestures"
    
    var description: String {
        switch self {
        case .useProfile:
            return "Use a specific profile when this app is active"
        case .disabled:
            return "Disable all gestures when this app is active"
        }
    }
}

// MARK: - App Profiles Tab
struct AppProfilesView: View {
    @StateObject private var uiServices = UIServices.shared
    @State private var appMappings: [AppProfileMapping] = []
    @State private var disabledApps: [DisabledApp] = []
    @State private var selectedApp: String = ""
    @State private var showingAddSheet = false
    @State private var showingEditSheet = false
    @State private var editingMapping: AppProfileMapping?
    @State private var editingDisabledApp: DisabledApp?
    @State private var searchText = ""
    @State private var showDeleteConfirmation = false
    @State private var itemToDelete: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Search bar
            searchBar
                .padding(.horizontal)
                .padding(.vertical, 10)
            
            // Content
            if appMappings.isEmpty && disabledApps.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Profile Mappings Section
                        if !filteredMappings.isEmpty {
                            profileMappingsSection
                        }
                        
                        // Disabled Apps Section
                        if !filteredDisabledApps.isEmpty {
                            disabledAppsSection
                        }
                    }
                    .padding()
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadData()
        }
        .sheet(isPresented: $showingAddSheet) {
            AddAppRuleSheet(
                onAdd: { bundleId, appName, ruleType, profileId in
                    addAppRule(bundleId: bundleId, appName: appName, ruleType: ruleType, profileId: profileId)
                    showingAddSheet = false
                },
                onCancel: {
                    showingAddSheet = false
                }
            )
        }
        .sheet(isPresented: $showingEditSheet) {
            if let mapping = editingMapping {
                EditAppRuleSheet(
                    mapping: mapping,
                    onSave: { profileId in
                        updateMapping(mapping: mapping, newProfileId: profileId)
                        showingEditSheet = false
                    },
                    onCancel: {
                        showingEditSheet = false
                    }
                )
            } else if let disabledApp = editingDisabledApp {
                EditDisabledAppSheet(
                    disabledApp: disabledApp,
                    onSave: {
                        // Convert to profile mapping
                        if let profile = uiServices.profiles.first {
                            uiServices.removeDisabledApp(bundleId: disabledApp.appBundleIdentifier)
                            uiServices.addAppProfileMapping(
                                bundleId: disabledApp.appBundleIdentifier,
                                appName: disabledApp.appName,
                                profileId: profile.id
                            )
                            loadData()
                        }
                        showingEditSheet = false
                    },
                    onCancel: {
                        showingEditSheet = false
                    }
                )
            }
        }
        .alert("Delete App Rule", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let bundleId = itemToDelete {
                    deleteAppRule(bundleId: bundleId)
                }
            }
        } message: {
            Text("Are you sure you want to delete this app rule?")
        }
    }
    
    // MARK: - View Components
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("App Profiles")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Configure profile rules for specific applications")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: { showingAddSheet = true }) {
                Label("Add Rule", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search applications...", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No App Rules Configured")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add rules to use specific profiles or disable gestures for certain applications")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Button(action: { showingAddSheet = true }) {
                Label("Add First Rule", systemImage: "plus.circle")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var profileMappingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Profile Mappings", systemImage: "square.stack.3d.up")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(filteredMappings.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(10)
            }
            
            VStack(spacing: 8) {
                ForEach(filteredMappings, id: \.id) { mapping in
                    AppMappingRow(
                        mapping: mapping,
                        profileName: uiServices.profiles.first(where: { $0.id == mapping.profileId })?.name ?? "Unknown",
                        onEdit: {
                            editingMapping = mapping
                            editingDisabledApp = nil
                            showingEditSheet = true
                        },
                        onDelete: {
                            itemToDelete = mapping.appBundleIdentifier
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    private var disabledAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Disabled Apps", systemImage: "nosign")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(filteredDisabledApps.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(10)
            }
            
            VStack(spacing: 8) {
                ForEach(filteredDisabledApps, id: \.id) { disabledApp in
                    DisabledAppRow(
                        disabledApp: disabledApp,
                        onEdit: {
                            editingDisabledApp = disabledApp
                            editingMapping = nil
                            showingEditSheet = true
                        },
                        onDelete: {
                            itemToDelete = disabledApp.appBundleIdentifier
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
    
    // MARK: - Computed Properties
    
    private var filteredMappings: [AppProfileMapping] {
        if searchText.isEmpty {
            return appMappings
        }
        return appMappings.filter { mapping in
            mapping.appName.localizedCaseInsensitiveContains(searchText) ||
            mapping.appBundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var filteredDisabledApps: [DisabledApp] {
        if searchText.isEmpty {
            return disabledApps
        }
        return disabledApps.filter { app in
            app.appName.localizedCaseInsensitiveContains(searchText) ||
            app.appBundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // MARK: - Methods
    
    private func loadData() {
        appMappings = uiServices.getAppProfileMappings()
        disabledApps = uiServices.getDisabledApps()
    }
    
    private func addAppRule(bundleId: String, appName: String, ruleType: AppProfileRuleType, profileId: UUID?) {
        switch ruleType {
        case .useProfile:
            if let profileId = profileId {
                uiServices.addAppProfileMapping(bundleId: bundleId, appName: appName, profileId: profileId)
            }
        case .disabled:
            uiServices.addDisabledApp(bundleId: bundleId, appName: appName)
        }
        loadData()
    }
    
    private func updateMapping(mapping: AppProfileMapping, newProfileId: UUID) {
        uiServices.addAppProfileMapping(
            bundleId: mapping.appBundleIdentifier,
            appName: mapping.appName,
            profileId: newProfileId
        )
        loadData()
    }
    
    private func deleteAppRule(bundleId: String) {
        // Check if it's a mapping or disabled app
        if appMappings.contains(where: { $0.appBundleIdentifier == bundleId }) {
            uiServices.removeAppProfileMapping(bundleId: bundleId)
        } else if disabledApps.contains(where: { $0.appBundleIdentifier == bundleId }) {
            uiServices.removeDisabledApp(bundleId: bundleId)
        }
        loadData()
    }
}

// MARK: - App Mapping Row
struct AppMappingRow: View {
    let mapping: AppProfileMapping
    let profileName: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mapping.appBundleIdentifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.appName)
                    .font(.system(size: 13, weight: .medium))
                
                Text(mapping.appBundleIdentifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Profile badge
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.caption)
                Text(profileName)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(6)
            
            // Action buttons
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                .help("Edit rule")
                
                Button(action: onDelete) {
                    Image(systemName: "trash.circle")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .help("Delete rule")
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Disabled App Row
struct DisabledAppRow: View {
    let disabledApp: DisabledApp
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: disabledApp.appBundleIdentifier) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 24))
                    .frame(width: 32, height: 32)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(disabledApp.appName)
                    .font(.system(size: 13, weight: .medium))
                
                Text(disabledApp.appBundleIdentifier)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Disabled badge
            HStack(spacing: 4) {
                Image(systemName: "nosign")
                    .font(.caption)
                Text("Disabled")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red.opacity(0.1))
            .foregroundColor(.red)
            .cornerRadius(6)
            
            // Action buttons
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                .help("Convert to profile mapping")
                
                Button(action: onDelete) {
                    Image(systemName: "trash.circle")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                .help("Delete rule")
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Add App Rule Sheet
struct AddAppRuleSheet: View {
    @StateObject private var uiServices = UIServices.shared
    @State private var selectedApp: (bundleId: String, name: String, icon: NSImage?)? = nil
    @State private var ruleType: AppProfileRuleType = .useProfile
    @State private var selectedProfileId: UUID?
    @State private var searchText = ""
    @State private var installedApps: [(bundleId: String, name: String, icon: NSImage?)] = []
    @State private var isLoadingApps = true
    
    let onAdd: (String, String, AppProfileRuleType, UUID?) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add App Rule")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider()
            
            // Content
            VStack(spacing: 20) {
                // App selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Application")
                        .font(.headline)
                    
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search applications...", text: $searchText)
                            .textFieldStyle(.plain)
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // App list
                    if isLoadingApps {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.8)
                            Spacer()
                        }
                        .frame(height: 200)
                    } else {
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(filteredApps, id: \.bundleId) { app in
                                    AppSelectionRow(
                                        app: app,
                                        isSelected: selectedApp?.bundleId == app.bundleId,
                                        isDisabled: isAppAlreadyConfigured(bundleId: app.bundleId),
                                        onSelect: {
                                            if !isAppAlreadyConfigured(bundleId: app.bundleId) {
                                                selectedApp = app
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(4)
                        }
                        .frame(height: 200)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                
                // Rule type selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rule Type")
                        .font(.headline)
                    
                    Picker("", selection: $ruleType) {
                        ForEach(AppProfileRuleType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    
                    Text(ruleType.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Profile selection (if applicable)
                if ruleType == .useProfile {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Profile")
                            .font(.headline)
                        
                        Picker("", selection: $selectedProfileId) {
                            Text("Select a profile...").tag(nil as UUID?)
                            ForEach(uiServices.profiles, id: \.id) { profile in
                                Text(profile.name).tag(profile.id as UUID?)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
            .padding()
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Button("Add Rule") {
                    if let app = selectedApp {
                        onAdd(app.bundleId, app.name, ruleType, selectedProfileId)
                    }
                }
                .keyboardShortcut(.return)
                .disabled(!canAddRule)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadInstalledApps()
            if let firstProfile = uiServices.profiles.first {
                selectedProfileId = firstProfile.id
            }
        }
    }
    
    private var filteredApps: [(bundleId: String, name: String, icon: NSImage?)] {
        if searchText.isEmpty {
            return installedApps
        }
        return installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText) ||
            app.bundleId.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var canAddRule: Bool {
        guard let app = selectedApp else { return false }
        if isAppAlreadyConfigured(bundleId: app.bundleId) { return false }
        if ruleType == .useProfile && selectedProfileId == nil { return false }
        return true
    }
    
    private func isAppAlreadyConfigured(bundleId: String) -> Bool {
        return uiServices.getAppProfileMappings().contains { $0.appBundleIdentifier == bundleId } ||
               uiServices.getDisabledApps().contains { $0.appBundleIdentifier == bundleId }
    }
    
    private func loadInstalledApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = uiServices.getAllInstalledApps()
            DispatchQueue.main.async {
                self.installedApps = apps
                self.isLoadingApps = false
            }
        }
    }
}

// MARK: - App Selection Row
struct AppSelectionRow: View {
    let app: (bundleId: String, name: String, icon: NSImage?)
    let isSelected: Bool
    let isDisabled: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 18))
                    .frame(width: 24, height: 24)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                
                Text(app.bundleId)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isDisabled {
                Text("Configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.2) : (isDisabled ? Color.gray.opacity(0.1) : Color.clear))
        .cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDisabled {
                onSelect()
            }
        }
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}

// MARK: - Edit App Rule Sheet
struct EditAppRuleSheet: View {
    @StateObject private var uiServices = UIServices.shared
    let mapping: AppProfileMapping
    @State private var selectedProfileId: UUID
    
    let onSave: (UUID) -> Void
    let onCancel: () -> Void
    
    init(mapping: AppProfileMapping, onSave: @escaping (UUID) -> Void, onCancel: @escaping () -> Void) {
        self.mapping = mapping
        self._selectedProfileId = State(initialValue: mapping.profileId)
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit App Rule")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider()
            
            // Content
            VStack(spacing: 20) {
                // App info
                HStack(spacing: 12) {
                    if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: mapping.appBundleIdentifier) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                    } else {
                        Image(systemName: "app")
                            .font(.system(size: 36))
                            .frame(width: 48, height: 48)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mapping.appName)
                            .font(.headline)
                        
                        Text(mapping.appBundleIdentifier)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Profile selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Profile")
                        .font(.headline)
                    
                    Picker("", selection: $selectedProfileId) {
                        ForEach(uiServices.profiles, id: \.id) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            .padding()
            
            Spacer()
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Button("Save") {
                    onSave(selectedProfileId)
                }
                .keyboardShortcut(.return)
                .disabled(selectedProfileId == mapping.profileId)
            }
            .padding()
        }
        .frame(width: 400, height: 300)
    }
}

// MARK: - Edit Disabled App Sheet
struct EditDisabledAppSheet: View {
    let disabledApp: DisabledApp
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Convert to Profile Mapping")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider()
            
            // Content
            VStack(spacing: 20) {
                // App info
                HStack(spacing: 12) {
                    if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: disabledApp.appBundleIdentifier) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                    } else {
                        Image(systemName: "app")
                            .font(.system(size: 36))
                            .frame(width: 48, height: 48)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(disabledApp.appName)
                            .font(.headline)
                        
                        Text(disabledApp.appBundleIdentifier)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                Text("This will convert the disabled app rule to use a specific profile instead.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            
            Spacer()
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Button("Convert") {
                    onSave()
                }
                .keyboardShortcut(.return)
            }
            .padding()
        }
        .frame(width: 400, height: 250)
    }
}
