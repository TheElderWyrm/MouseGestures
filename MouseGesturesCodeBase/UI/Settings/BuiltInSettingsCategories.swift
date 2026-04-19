import SwiftUI
import UniformTypeIdentifiers

// MARK: - Well-Known Category Descriptors

enum SettingsCategories {
    static let general = SettingsCategoryDescriptor(id: "general", title: "General", icon: "gear", order: 0)
    static let detection = SettingsCategoryDescriptor(id: "detection", title: "Detection", icon: "hand.tap", order: 10)
    static let license = SettingsCategoryDescriptor(id: "license", title: "License", icon: "checkmark.seal", order: 70)
    static let about = SettingsCategoryDescriptor(id: "about", title: "About", icon: "info.circle", order: 80)
}

// MARK: - Well-Known Subcategory Descriptors

// MARK: - Built-In Settings Provider

/// Core app settings that don't belong to any particular plugin.
struct BuiltInSettingsProvider: SettingsProvider {
    var settingsEntries: [SettingsEntry] {
        [
            // Enable Gestures toggle
            SettingsEntry(
                category: SettingsCategories.general,
                order: 0,
                searchableItems: [
                    SearchableSettingItem(title: "Enable Mouse Gestures", description: "Master switch to enable or disable all gesture recognition", keywords: ["enable", "disable", "gestures", "toggle", "on", "off"])
                ],
                viewBuilder: { _ in AnyView(EnableGesturesSettingView()) }
            ),
            
            // Notification on activation
            SettingsEntry(
                category: SettingsCategories.general,
                order: 5,
                searchableItems: [
                    SearchableSettingItem(title: "Notification on Activation", description: "Show a banner notification when a gesture fires", keywords: ["notification", "banner", "activation", "gesture", "notify"])
                ],
                viewBuilder: { _ in AnyView(NotificationOnActivationSettingView()) }
            ),

            // Developer Mode toggle (advanced, but always shown when enabled)
            SettingsEntry(
                category: SettingsCategories.general,
                order: 900,
                isAdvanced: !UIServices.shared.isDeveloperModeEnabled(),
                searchableItems: [
                    SearchableSettingItem(title: "Developer Mode", description: "Show Developer tab with logging, plugins, performance, services, and diagnostics", keywords: ["developer", "debug", "advanced", "dev"])
                ],
                viewBuilder: { _ in AnyView(DeveloperModeSettingView()) }
            ),
            
            // Data Management
            SettingsEntry(
                category: SettingsCategories.about,
                order: 1,
                searchableItems: [
                    SearchableSettingItem(title: "Export Settings", description: "Export all application settings to a file", keywords: ["export", "backup", "save", "settings", "file"]),
                    SearchableSettingItem(title: "Import Settings", description: "Import application settings from a file", keywords: ["import", "restore", "load", "settings", "file"]),
                    SearchableSettingItem(title: "Reset Application", description: "Reset all settings, profiles, and gestures to factory defaults", keywords: ["reset", "factory", "default", "clear", "wipe"])
                ],
                viewBuilder: { _ in AnyView(DataManagementSettingsView()) }
            ),
            
            // About
            SettingsEntry(
                category: SettingsCategories.about,
                order: 0,
                searchableItems: [
                    SearchableSettingItem(title: "Version Information", description: "Current app version and build number", keywords: ["version", "build", "number", "about"]),
                    SearchableSettingItem(title: "Check for Updates", description: "Check for the latest version of MouseGestures", keywords: ["update", "check", "latest", "new", "version"])
                ],
                viewBuilder: { _ in AnyView(AboutSettingsView()) }
            )
        ]
    }
}

/// Settings provider for license and pro features.
struct LicenseSettingsProvider: SettingsProvider {
    var settingsEntries: [SettingsEntry] {
        [
            SettingsEntry(
                category: SettingsCategories.license,
                order: 0,
                searchableItems: [
                    SearchableSettingItem(title: "License Status", description: "View your current license status and upgrade to Pro", keywords: ["license", "pro", "upgrade", "trial", "payment", "buy"])
                ],
                viewBuilder: { _ in AnyView(LicenseSettingsView()) }
            )
        ]
    }
}

// MARK: - Well-Known Detection Subcategory Descriptors

enum DetectionSubcategories {
    static let general = SettingsSubcategoryDescriptor(id: "general", title: "General", icon: "gearshape", order: 0)
    static let zones = SettingsSubcategoryDescriptor(id: "zones", title: "Zone Detection", icon: "hand.tap", order: 1)
    static let appProfiles = SettingsSubcategoryDescriptor(id: "appProfiles", title: "App Profiles", icon: "app.badge", order: 2)
}

// MARK: - Detection Plugin Settings Provider

/// Bridges detection plugin settings into the unified settings system.
/// Partitions settings into subcategories: General, Zone Detection, App Profiles, Appearance, Performance.
struct DetectionPluginSettingsProvider: SettingsProvider {
    var settingsEntries: [SettingsEntry] {
        let allSettings = DetectionPluginManager.shared.getAllSettingsDefinitions()
        let allItems = allSettings.values.flatMap { $0 }
        guard !allItems.isEmpty else { return [] }
        
        // Partition items into subcategories
        var appProfileItems: [(plugin: DetectionPlugin, definition: PluginSettingDefinition)] = []
        var zoneItems: [(plugin: DetectionPlugin, definition: PluginSettingDefinition)] = []
        var generalItems: [(plugin: DetectionPlugin, definition: PluginSettingDefinition)] = []
        
        for item in allItems {
            switch item.plugin.identifier {
            case AppConfigurationDetectorPlugin.pluginIdentifier:
                appProfileItems.append(item)
            case ScreenZoneDetectorPlugin.pluginIdentifier:
                zoneItems.append(item)
            default:
                generalItems.append(item)
            }
        }
        
        var entries: [SettingsEntry] = []
        
        func makeEntry(_ sub: SettingsSubcategoryDescriptor,
                       _ items: [(plugin: DetectionPlugin, definition: PluginSettingDefinition)]) -> SettingsEntry {
            SettingsEntry(
                category: SettingsCategories.detection,
                subcategory: sub,
                order: sub.order,
                searchableItems: items.map {
                    SearchableSettingItem(title: $0.definition.displayName,
                                         description: $0.definition.description ?? "",
                                         keywords: ["detection", $0.plugin.name.lowercased()])
                },
                viewBuilder: { showAdvanced in
                    AnyView(DetectionSubcategoryView(items: items, showAdvanced: showAdvanced))
                }
            )
        }
        
        if !generalItems.isEmpty     { entries.append(makeEntry(DetectionSubcategories.general, generalItems)) }
        if !zoneItems.isEmpty        { entries.append(makeEntry(DetectionSubcategories.zones, zoneItems)) }
        if !appProfileItems.isEmpty  { entries.append(makeEntry(DetectionSubcategories.appProfiles, appProfileItems)) }
        return entries
    }
}

// MARK: - Detection Subcategory View

/// Renders all PluginSettingRows for a single detection subcategory.
struct DetectionSubcategoryView: View {
    let items: [(plugin: DetectionPlugin, definition: PluginSettingDefinition)]
    @Binding var showAdvanced: Bool
    @State private var visibilityTrigger = UUID()
    
    private var visibleItems: [(plugin: DetectionPlugin, definition: PluginSettingDefinition)] {
        items.filter { !$0.definition.isAdvanced || showAdvanced }
    }
    
    var body: some View {
        if visibleItems.isEmpty {
            Text("No settings available")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, MGStyle.Spacing.xxl)
        } else {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xl) {
                ForEach(visibleItems, id: \.definition.key) { item in
                    PluginSettingRow(
                        plugin: item.plugin,
                        definition: item.definition,
                        visibilityTrigger: $visibilityTrigger
                    )
                }
            }
            .id(visibilityTrigger)
        }
    }
}

// MARK: - Built-In Setting Views

private struct EnableGesturesSettingView: View {
    @State private var gesturesEnabled = true

    var body: some View {
        settingsToggle(
            isOn: $gesturesEnabled,
            title: "Enable Mouse Gestures",
            description: "Master switch to enable or disable all gesture recognition"
        ) { UIServices.shared.setGesturesEnabled($0) }
        .onAppear { gesturesEnabled = UIServices.shared.isGesturesEnabled() }
    }
}

private struct NotificationOnActivationSettingView: View {
    @State private var notificationEnabled = false

    var body: some View {
        settingsToggle(
            isOn: $notificationEnabled,
            title: "Notification on Activation",
            description: "Show a banner notification when a gesture fires"
        ) { UIServices.shared.setNotificationOnActivation($0) }
        .onAppear { notificationEnabled = UIServices.shared.isNotificationOnActivation() }
    }
}

private struct DeveloperModeSettingView: View {
    @State private var developerModeEnabled = false
    
    var body: some View {
        Toggle(isOn: $developerModeEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MGStyle.Spacing.md) {
                    Text("Developer Mode")
                        .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                    Text("Advanced")
                        .font(.system(size: 9))
                        .padding(.horizontal, MGStyle.Spacing.sm)
                        .padding(.vertical, MGStyle.Spacing.xs)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(MGStyle.Corner.sm)
                }
                Text("Show Developer tab with logging, plugins, performance, services, and diagnostics")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: developerModeEnabled) { newValue in
            UIServices.shared.setDeveloperModeEnabled(newValue)
        }
        .onAppear { developerModeEnabled = UIServices.shared.isDeveloperModeEnabled() }
    }
}

// MARK: - Data Management View

struct DataManagementSettingsView: View {
    @StateObject private var uiServices = UIServices.shared
    
    @State private var showingImportDialog = false
    @State private var showingExportDialog = false
    @State private var showingResetConfirmation = false
    @State private var showingImportOptions = false
    @State private var mergeProfilesOnImport = false
    @State private var importSuccessMessage: String?
    @State private var exportSuccessMessage: String?
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                Text("Settings Backup")
                    .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                
                Text("Export or import all application settings, including profiles, gestures, and preferences")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: MGStyle.Spacing.lg) {
                    Button(action: { showingExportDialog = true }) {
                        Label("Export Settings", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: { showingImportOptions = true }) {
                        Label("Import Settings", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                }
                
                if let msg = importSuccessMessage {
                    Label(msg, systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green)
                }
                if let msg = exportSuccessMessage {
                    Label(msg, systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green)
                }
                if let err = errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundColor(.red)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                Text("Reset Application")
                    .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                Text("Reset all settings, profiles, and gestures to factory defaults")
                    .font(.caption).foregroundColor(.secondary)
                
                Button(action: { showingResetConfirmation = true }) {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .foregroundColor(.white).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.regular).tint(.red)
            }
        }
        .alert("Reset Application", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) { resetApplication() }
        } message: {
            Text("This will reset all settings, profiles, and gestures to their default values. This action cannot be undone.")
        }
        .alert("Import Settings", isPresented: $showingImportOptions) {
            Button("Replace All") { mergeProfilesOnImport = false; showingImportDialog = true }
            Button("Merge Profiles") { mergeProfilesOnImport = true; showingImportDialog = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Would you like to replace all existing settings or merge the imported profiles with your current ones?")
        }
        .fileImporter(isPresented: $showingImportDialog, allowedContentTypes: [UTType.json], allowsMultipleSelection: false) { result in
            handleImport(result: result)
        }
        .fileExporter(
            isPresented: $showingExportDialog,
            document: SettingsExportDocument(data: uiServices.configuration.exportGlobalSettings() ?? Data()),
            contentType: UTType.json,
            defaultFilename: "MouseGestures_Settings_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).json"
        ) { result in handleExport(result: result) }
    }
    
    private func handleImport(result: Result<[URL], Error>) {
        errorMessage = nil; importSuccessMessage = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if uiServices.importAppSettings(from: url, mergeProfiles: mergeProfilesOnImport) {
                importSuccessMessage = mergeProfilesOnImport ? "Settings merged successfully" : "Settings imported successfully"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { importSuccessMessage = nil }
            } else { errorMessage = uiServices.errorMessage ?? "Import failed" }
        case .failure(let error):
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }
    
    private func handleExport(result: Result<URL, Error>) {
        errorMessage = nil; exportSuccessMessage = nil
        switch result {
        case .success:
            exportSuccessMessage = "Settings exported successfully"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exportSuccessMessage = nil }
        case .failure(let error):
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }
    
    private func resetApplication() {
        uiServices.resetAppToDefaults()
        errorMessage = nil
        importSuccessMessage = "Application reset to defaults"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { importSuccessMessage = nil }
    }
}

// MARK: - About View

struct AboutSettingsView: View {
    @ObservedObject var updateService = UpdateService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                Text("Version Information").font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Current Version:").font(.system(size: MGStyle.FontSize.body))
                            Text(updateService.currentVersion)
                                .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                        }
                        HStack {
                            Text("Build Number:").font(.system(size: MGStyle.FontSize.body))
                            Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                                .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                        }
                    }
                    
                    Divider().frame(height: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        if updateService.isChecking {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Checking for updates...").font(.caption).foregroundColor(.secondary)
                            }
                        } else if let lastCheck = updateService.lastCheckDate {
                            Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Never checked for updates")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Button(action: {
                    updateService.checkForUpdates()
                }) {
                    Label("Check for Updates", systemImage: "arrow.clockwise")
                }
                .disabled(updateService.isChecking)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                Text("Automatic Updates").font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                
                Toggle(isOn: Binding(
                    get: { updateService.isAutoUpdateEnabled },
                    set: { updateService.isAutoUpdateEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Download and install updates automatically")
                        Text("Requires app restart to apply").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Shared Helpers

func settingsToggle(isOn: Binding<Bool>, title: String, description: String, onChange: @escaping (Bool) -> Void) -> some View {
    Toggle(isOn: isOn) {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
            Text(title).font(.system(size: MGStyle.FontSize.body, weight: .medium))
            Text(description).font(.caption).foregroundColor(.secondary)
        }
    }
    .onChange(of: isOn.wrappedValue) { newValue in onChange(newValue) }
}

// MARK: - Settings Export Document

struct SettingsExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Settings Registration

/// Registers all settings: built-in core + detection plugins + service plugins.
func registerAllSettings() {
    let registry = SettingsCategoryRegistry.shared
    registry.clear()
    
    // Core app entries
    registry.register(BuiltInSettingsProvider())
    
    // License and Pro features
    registry.register(LicenseSettingsProvider())
    
    // Detection plugin settings (bridged from PluginSettingDefinition system)
    registry.register(DetectionPluginSettingsProvider())
    
    // Service plugins that provide settings
    for pluginInfo in ServicePluginManager.shared.getAllPlugins() {
        guard let plugin = ServicePluginManager.shared.getPlugin(identifier: pluginInfo.identifier) else { continue }
        if let provider = plugin as? SettingsProvider {
            registry.register(provider)
        }
    }
}
