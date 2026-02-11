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
    enum ActiveSheet: Identifiable {
        case addRule
        
        var id: String {
            switch self {
            case .addRule: return "add"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showDeleteConfirmation = false
    @State private var itemToDelete: String?
    
    var body: some View {
        VStack(spacing: 0) {
            MGCompactHeader(
                "App Profiles",
                subtitle: "Configure profile rules for specific applications"
            ) {
                if showSearch {
                    MGSearchField("Search applications...", text: $searchText)
                        .frame(width: MGStyle.Layout.searchFieldWidth)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSearch.toggle() } }) {
                    Image(systemName: showSearch ? "xmark" : "magnifyingglass")
                        .font(.system(size: 13))
                }
                .buttonStyle(.borderless)
                .help("Search applications")
                
                Button(action: { activeSheet = .addRule }) {
                    Label("Add Rule", systemImage: "plus")
                }
            }
            
            Divider()
            
            if appMappings.isEmpty && disabledApps.isEmpty {
                MGEmptyState(
                    icon: "app.badge.checkmark",
                    title: "No App Rules Configured",
                    description: "Add rules to use specific profiles or disable gestures for certain applications",
                    actionLabel: "Add First Rule",
                    action: { activeSheet = .addRule }
                )
            } else {
                ScrollView {
                    VStack(spacing: MGStyle.Spacing.xl) {
                        if !filteredMappings.isEmpty {
                            profileMappingsSection
                        }
                        
                        if !filteredDisabledApps.isEmpty {
                            disabledAppsSection
                        }
                    }
                    .padding(MGStyle.Spacing.xl)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadData() }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .addRule:
                AddAppRuleSheet(
                    onAdd: { bundleId, appName, ruleType, profileId in
                        addAppRule(bundleId: bundleId, appName: appName, ruleType: ruleType, profileId: profileId)
                        activeSheet = nil
                    },
                    onCancel: { activeSheet = nil }
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
    
    private var profileMappingsSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
            MGListSectionHeader(
                "Profile Mappings",
                count: filteredMappings.count
            )
            
            VStack(spacing: MGStyle.Spacing.md) {
                ForEach(filteredMappings, id: \.id) { mapping in
                    AppMappingRow(
                        mapping: mapping,
                        profileName: uiServices.profiles.first(where: { $0.id == mapping.profileId })?.name ?? "Unknown",
                        onProfileChange: { newProfileId in
                            updateMapping(mapping: mapping, newProfileId: newProfileId)
                        },
                        onDelete: {
                            itemToDelete = mapping.appBundleIdentifier
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                .fill(MGStyle.Colors.cardBackground)
        )
    }
    
    private var disabledAppsSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
            MGListSectionHeader(
                "Disabled Apps",
                count: filteredDisabledApps.count
            )
            
            VStack(spacing: MGStyle.Spacing.md) {
                ForEach(filteredDisabledApps, id: \.id) { disabledApp in
                    DisabledAppRow(
                        disabledApp: disabledApp,
                        onDelete: {
                            itemToDelete = disabledApp.appBundleIdentifier
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                .fill(MGStyle.Colors.cardBackground)
        )
    }
    
    // MARK: - Computed Properties
    
    private var filteredMappings: [AppProfileMapping] {
        if searchText.isEmpty { return appMappings }
        return appMappings.filter { mapping in
            mapping.appName.localizedCaseInsensitiveContains(searchText) ||
            mapping.appBundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var filteredDisabledApps: [DisabledApp] {
        if searchText.isEmpty { return disabledApps }
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
    let onProfileChange: (UUID) -> Void
    let onDelete: () -> Void
    
    @StateObject private var uiServices = UIServices.shared
    @State private var isHovered = false
    @State private var selectedProfileId: UUID
    
    init(mapping: AppProfileMapping, profileName: String, onProfileChange: @escaping (UUID) -> Void, onDelete: @escaping () -> Void) {
        self.mapping = mapping
        self.profileName = profileName
        self.onProfileChange = onProfileChange
        self.onDelete = onDelete
        self._selectedProfileId = State(initialValue: mapping.profileId)
    }
    
    var body: some View {
        HStack(spacing: MGStyle.Spacing.lg) {
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
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                Text(mapping.appName)
                    .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                
                Text(mapping.appBundleIdentifier)
                    .font(.system(size: MGStyle.FontSize.caption))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Inline profile picker
            HStack(spacing: MGStyle.Spacing.sm) {
                Text("Profile:")
                    .font(.system(size: MGStyle.FontSize.caption))
                    .foregroundColor(.secondary)
                Picker("", selection: $selectedProfileId) {
                    ForEach(uiServices.profiles.sorted(by: { $0.name < $1.name }), id: \.id) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                .onChange(of: selectedProfileId) { newValue in
                    if newValue != mapping.profileId {
                        onProfileChange(newValue)
                    }
                }
            }
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: MGStyle.IconSize.row))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("Remove rule")
        }
        .padding(.horizontal, MGStyle.Spacing.lg)
        .padding(.vertical, MGStyle.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                .fill(isHovered ? MGStyle.Colors.hoveredRow : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - Disabled App Row
struct DisabledAppRow: View {
    let disabledApp: DisabledApp
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: MGStyle.Spacing.lg) {
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
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                Text(disabledApp.appName)
                    .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                
                Text(disabledApp.appBundleIdentifier)
                    .font(.system(size: MGStyle.FontSize.caption))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            MGBadge("Disabled", color: .red, icon: "nosign")
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: MGStyle.IconSize.row))
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
            .help("Remove rule")
        }
        .padding(.horizontal, MGStyle.Spacing.lg)
        .padding(.vertical, MGStyle.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.lg)
                .fill(isHovered ? MGStyle.Colors.hoveredRow : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
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
            MGSheetHeader("Add App Rule", onCancel: onCancel)
            
            ScrollView {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
                    // App selection
                    GroupBox("Select Application") {
                        VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                            MGSearchField("Search applications...", text: $searchText)
                            
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
                                    VStack(spacing: MGStyle.Spacing.sm) {
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
                                    .padding(MGStyle.Spacing.sm)
                                }
                                .frame(height: 200)
                                .background(MGStyle.Colors.cardBackground)
                                .cornerRadius(MGStyle.Corner.lg)
                            }
                        }
                        .padding(.vertical, MGStyle.Spacing.md)
                    }
                    
                    // Rule type selection
                    GroupBox("Rule Type") {
                        VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
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
                        .padding(.vertical, MGStyle.Spacing.md)
                    }
                    
                    // Profile selection
                    if ruleType == .useProfile {
                        GroupBox("Select Profile") {
                            Picker("", selection: $selectedProfileId) {
                                Text("Select a profile...").tag(nil as UUID?)
                                ForEach(uiServices.profiles, id: \.id) { profile in
                                    Text(profile.name).tag(profile.id as UUID?)
                                }
                            }
                            .labelsHidden()
                            .padding(.vertical, MGStyle.Spacing.md)
                        }
                    }
                }
                .padding(MGStyle.Spacing.xl)
            }
            
            MGSheetFooter("Add Rule", disabled: !canAddRule) {
                if let app = selectedApp {
                    onAdd(app.bundleId, app.name, ruleType, selectedProfileId)
                }
            }
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
        if searchText.isEmpty { return installedApps }
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
        HStack(spacing: MGStyle.Spacing.md) {
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
                    .font(.system(size: MGStyle.FontSize.body))
                    .lineLimit(1)
                
                Text(app.bundleId)
                    .font(.system(size: MGStyle.FontSize.badge))
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
        .padding(.horizontal, MGStyle.Spacing.md)
        .padding(.vertical, MGStyle.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.sm)
                .fill(isSelected ? MGStyle.Colors.selectedRow :
                      (isDisabled ? Color.gray.opacity(0.1) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDisabled { onSelect() }
        }
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}


