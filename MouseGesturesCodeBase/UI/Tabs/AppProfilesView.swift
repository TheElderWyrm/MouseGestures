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
            switch self { case .addRule: return "add" }
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
            
            if allRules.isEmpty {
                MGEmptyState(
                    icon: "app.badge.checkmark",
                    title: "No App Rules Configured",
                    description: "Add rules to use specific profiles or disable gestures for certain applications",
                    actionLabel: "Add First Rule",
                    action: { activeSheet = .addRule }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: MGStyle.Spacing.sm) {
                        ForEach(filteredRules, id: \.bundleId) { rule in
                            UnifiedAppRuleRow(
                                rule: rule,
                                onChangeToProfile: { profileId in
                                    // Remove from disabled if it was there, add as mapping
                                    uiServices.removeDisabledApp(bundleId: rule.bundleId)
                                    uiServices.addAppProfileMapping(bundleId: rule.bundleId, appName: rule.appName, profileId: profileId)
                                    loadData()
                                },
                                onChangeToDisabled: {
                                    // Remove from mappings if it was there, add as disabled
                                    uiServices.removeAppProfileMapping(bundleId: rule.bundleId)
                                    uiServices.addDisabledApp(bundleId: rule.bundleId, appName: rule.appName)
                                    loadData()
                                },
                                onDelete: {
                                    itemToDelete = rule.bundleId
                                    showDeleteConfirmation = true
                                }
                            )
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
                if let bundleId = itemToDelete { deleteAppRule(bundleId: bundleId) }
            }
        } message: {
            Text("Are you sure you want to delete this app rule?")
        }
    }
    
    // MARK: - Unified Rule Model
    
    struct AppRule {
        let bundleId: String
        let appName: String
        let profileId: UUID?   // nil = disabled
        let profileName: String?
    }
    
    private var allRules: [AppRule] {
        let mappingRules = appMappings.map { m in
            AppRule(
                bundleId: m.appBundleIdentifier,
                appName: m.appName,
                profileId: m.profileId,
                profileName: uiServices.profiles.first(where: { $0.id == m.profileId })?.name
            )
        }
        let disabledRules = disabledApps.map { d in
            AppRule(bundleId: d.appBundleIdentifier, appName: d.appName, profileId: nil, profileName: nil)
        }
        return (mappingRules + disabledRules)
            .sorted { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
    }
    
    private var filteredRules: [AppRule] {
        if searchText.isEmpty { return allRules }
        return allRules.filter {
            $0.appName.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleId.localizedCaseInsensitiveContains(searchText)
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
    
    private func deleteAppRule(bundleId: String) {
        uiServices.removeAppProfileMapping(bundleId: bundleId)
        uiServices.removeDisabledApp(bundleId: bundleId)
        loadData()
    }
}

// MARK: - Unified App Rule Row (with inline dropdown including Disable option)

struct UnifiedAppRuleRow: View {
    let rule: AppProfilesView.AppRule
    let onChangeToProfile: (UUID) -> Void
    let onChangeToDisabled: () -> Void
    let onDelete: () -> Void
    
    @StateObject private var uiServices = UIServices.shared
    @State private var isHovered = false
    
    /// Sentinel UUID for the "Disable" option in the picker
    private static let disableSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    private var pickerSelection: Binding<UUID> {
        Binding(
            get: { rule.profileId ?? Self.disableSentinel },
            set: { newValue in
                if newValue == Self.disableSentinel {
                    onChangeToDisabled()
                } else {
                    onChangeToProfile(newValue)
                }
            }
        )
    }
    
    var body: some View {
        HStack(spacing: MGStyle.Spacing.lg) {
            // App icon
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleId) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 20))
                    .frame(width: 28, height: 28)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                Text(rule.appName)
                    .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                    .lineLimit(1)
                Text(rule.bundleId)
                    .font(.system(size: MGStyle.FontSize.badge))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Unified dropdown: profiles + disable option
            Picker("", selection: pickerSelection) {
                ForEach(uiServices.profiles.sorted(by: { $0.name < $1.name }), id: \.id) { profile in
                    Text(profile.name).tag(profile.id)
                }
                Divider()
                Text("Disable Gestures").tag(Self.disableSentinel)
            }
            .pickerStyle(.menu)
            .frame(width: 160)
            
            MGActionButton("trash", help: "Remove rule", destructive: true) { onDelete() }
                .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, MGStyle.Spacing.lg)
        .padding(.vertical, MGStyle.Spacing.md)
        .mgListCard(isHovered: isHovered)
        .onHover { h in withAnimation(.easeInOut(duration: 0.15)) { isHovered = h } }
        .contextMenu {
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
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
                    MGDetailSection("Select Application", icon: "app.badge") {
                        VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                            HStack(spacing: MGStyle.Spacing.md) {
                                MGSearchField("Search applications...", text: $searchText)
                                
                                Button(action: browseForApp) {
                                    Label("Browse...", systemImage: "folder")
                                }
                                .controlSize(.small)
                                .help("Select an application from Finder")
                            }
                            
                            if isLoadingApps {
                                HStack {
                                    Spacer()
                                    ProgressView().progressViewStyle(.circular).scaleEffect(0.8)
                                    Spacer()
                                }
                                .frame(height: 180)
                            } else {
                                ScrollView {
                                    VStack(spacing: MGStyle.Spacing.xs) {
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
                                .frame(height: 180)
                                .background(MGStyle.Colors.cardBackground)
                                .cornerRadius(MGStyle.Corner.lg)
                            }
                            
                            // Selected app indicator
                            if let app = selectedApp {
                                HStack(spacing: MGStyle.Spacing.md) {
                                    if let icon = app.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 20, height: 20)
                                    }
                                    Text("Selected: **\(app.name)**")
                                        .font(.system(size: MGStyle.FontSize.caption))
                                    
                                    Text("(\(app.bundleId))")
                                        .font(.system(size: MGStyle.FontSize.badge))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(MGStyle.Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: MGStyle.Corner.sm)
                                        .fill(Color.accentColor.opacity(0.08))
                                )
                            }
                        }
                    }
                    
                    // Rule type as radio buttons with inline profile dropdown
                    MGDetailSection("Rule Configuration", icon: "gearshape") {
                        VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                            // Option 1: Use specific profile (with inline dropdown)
                            HStack(spacing: MGStyle.Spacing.md) {
                                RadioButton(isSelected: ruleType == .useProfile) {
                                    ruleType = .useProfile
                                }
                                
                                Text("Use specific profile:")
                                    .font(.system(size: MGStyle.FontSize.body))
                                    .onTapGesture { ruleType = .useProfile }
                                
                                Picker("", selection: $selectedProfileId) {
                                    Text("Select...").tag(nil as UUID?)
                                    ForEach(uiServices.profiles.sorted(by: { $0.name < $1.name }), id: \.id) { profile in
                                        Text(profile.name).tag(profile.id as UUID?)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .frame(width: 180)
                                .disabled(ruleType != .useProfile)
                                .opacity(ruleType == .useProfile ? 1 : 0.5)
                            }
                            
                            // Option 2: Disable gestures
                            HStack(spacing: MGStyle.Spacing.md) {
                                RadioButton(isSelected: ruleType == .disabled) {
                                    ruleType = .disabled
                                }
                                
                                Text("Disable gestures")
                                    .font(.system(size: MGStyle.FontSize.body))
                                    .onTapGesture { ruleType = .disabled }
                            }
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
        .frame(width: 550, height: 600)
        .onAppear {
            loadInstalledApps()
            if let firstProfile = uiServices.profiles.first {
                selectedProfileId = firstProfile.id
            }
        }
    }
    
    private var filteredApps: [(bundleId: String, name: String, icon: NSImage?)] {
        let sorted = installedApps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if searchText.isEmpty { return sorted }
        return sorted.filter { app in
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
    
    private func browseForApp() {
        let panel = NSOpenPanel()
        panel.title = "Select Application"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an application to create a rule for"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                let name = bundle.infoDictionary?["CFBundleName"] as? String
                    ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                selectedApp = (bundleId: bundleId, name: name, icon: icon)
            }
        }
    }
}

// MARK: - Radio Button

struct RadioButton: View {
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .buttonStyle(.plain)
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
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "app")
                    .font(.system(size: 16))
                    .frame(width: 22, height: 22)
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
        .padding(.vertical, MGStyle.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.sm)
                .fill(isSelected ? MGStyle.Colors.selectedRow :
                      (isDisabled ? Color.gray.opacity(0.1) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { if !isDisabled { onSelect() } }
        .opacity(isDisabled ? 0.6 : 1.0)
    }
}
