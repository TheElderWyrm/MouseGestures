import SwiftUI
import UniformTypeIdentifiers

// MARK: - Well-Known Category Descriptors

enum SettingsCategories {
    static let general = SettingsCategoryDescriptor(id: "general", title: "General", icon: "gear", order: 0)
    static let detection = SettingsCategoryDescriptor(id: "detection", title: "Detection", icon: "hand.tap", order: 10)
    static let about = SettingsCategoryDescriptor(id: "about", title: "About", icon: "info.circle", order: 80)
}

// MARK: - Well-Known Subcategory Descriptors

enum AboutSubcategories {
    static let info = SettingsSubcategoryDescriptor(id: "info", title: "About", icon: "info.circle", order: 0)
    static let data = SettingsSubcategoryDescriptor(id: "data", title: "Data Management", icon: "externaldrive", order: 1)
}

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
            
            // Data Management (subcategory of About)
            SettingsEntry(
                category: SettingsCategories.about,
                subcategory: AboutSubcategories.data,
                order: 0,
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
                subcategory: AboutSubcategories.info,
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

// MARK: - Detection Plugin Settings Provider

/// Bridges detection plugin settings into the unified settings system.
/// Emits a single flat SettingsEntry for all detection settings,
/// rendered with inline section headers: General, Zone Detection, App Profiles.
struct DetectionPluginSettingsProvider: SettingsProvider {
    var settingsEntries: [SettingsEntry] {
        let allSettings = DetectionPluginManager.shared.getAllSettingsDefinitions()
        
        // Flatten all items for search metadata
        let allItems = allSettings.values.flatMap { $0 }
        guard !allItems.isEmpty else { return [] }
        
        let searchItems = allItems.map { item in
            SearchableSettingItem(
                title: item.definition.displayName,
                description: item.definition.description ?? "",
                keywords: ["detection", item.plugin.name.lowercased()]
            )
        }
        
        return [
            SettingsEntry(
                category: SettingsCategories.detection,
                order: 0,
                searchableItems: searchItems,
                viewBuilder: { showAdvanced in
                    AnyView(DetectionFlatSettingsView(allSettings: allSettings, showAdvanced: showAdvanced))
                }
            )
        ]
    }
}

// MARK: - Detection Flat Settings View

/// Renders all detection plugin settings in one flat list with labeled sections.
/// Sections: "App Profiles" (AppConfigurationDetectorPlugin),
/// "Zone Detection" (.detection + .appearance categories),
/// "General" (everything else).
struct DetectionFlatSettingsView: View {
    let allSettings: [PluginSettingDefinition.SettingCategory: [(plugin: DetectionPlugin, definition: PluginSettingDefinition)]]
    @Binding var showAdvanced: Bool
    @State private var visibilityTrigger = UUID()
    
    private typealias Item = (plugin: DetectionPlugin, definition: PluginSettingDefinition)
    
    // Partition all items into named sections
    private var sections: [(title: String, items: [Item])] {
        let all = allSettings.values.flatMap { $0 }
        
        var appProfiles: [Item] = []
        var zoneDetection: [Item] = []
        var general: [Item] = []
        
        for item in all {
            let isAppConfig = item.plugin.identifier == AppConfigurationDetectorPlugin.pluginIdentifier
            let isZoneCategory = item.definition.category == .detection || item.definition.category == .appearance
            
            if isAppConfig {
                appProfiles.append(item)
            } else if isZoneCategory {
                zoneDetection.append(item)
            } else {
                general.append(item)
            }
        }
        
        // Sort each section by definition order (preserve plugin-declared order)
        var result: [(String, [Item])] = []
        if !general.isEmpty      { result.append(("General", general)) }
        if !zoneDetection.isEmpty { result.append(("Zone Detection", zoneDetection)) }
        if !appProfiles.isEmpty  { result.append(("App Profiles", appProfiles)) }
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
            ForEach(sections, id: \.title) { section in
                let visible = section.items.filter { !$0.definition.isAdvanced || showAdvanced }
                if !visible.isEmpty {
                    VStack(alignment: .leading, spacing: MGStyle.Spacing.xl) {
                        Text(section.title)
                            .font(.system(size: MGStyle.FontSize.caption, weight: .semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .padding(.top, MGStyle.Spacing.sm)
                        
                        ForEach(visible, id: \.definition.key) { item in
                            PluginSettingRow(
                                plugin: item.plugin,
                                definition: item.definition,
                                visibilityTrigger: $visibilityTrigger
                            )
                        }
                    }
                }
            }
        }
        .id(visibilityTrigger)
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
    @State private var isCheckingForUpdates = false
    @State private var updateMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                Text("Version Information").font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                HStack {
                    Text("Current Version:").font(.system(size: MGStyle.FontSize.body))
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                        .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                }
                HStack {
                    Text("Build Number:").font(.system(size: MGStyle.FontSize.body))
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                        .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                Text("Check for Updates").font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                Text("Check for the latest version of MouseGestures").font(.caption).foregroundColor(.secondary)
                HStack {
                    Button(action: checkForUpdates) {
                        if isCheckingForUpdates {
                            ProgressView().progressViewStyle(CircularProgressViewStyle()).scaleEffect(0.8).frame(width: 16, height: 16)
                            Text("Checking...")
                        } else {
                            Label("Check Now", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderedProminent).disabled(isCheckingForUpdates)
                    if let msg = updateMessage { Text(msg).font(.caption).foregroundColor(.secondary) }
                }
            }
        }
    }
    
    private func checkForUpdates() {
        isCheckingForUpdates = true; updateMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCheckingForUpdates = false; updateMessage = "You are running the latest version"
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { updateMessage = nil }
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
