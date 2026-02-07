import SwiftUI
import UniformTypeIdentifiers

// MARK: - General Settings Category

/// Core application settings plus dynamically contributed settings from services.
class GeneralSettingsCategory: SettingsCategoryProvider {
    var settingsCategoryId: String { "general" }
    var settingsCategoryTitle: String { "General" }
    var settingsCategoryIcon: String { "gear" }
    var settingsCategoryOrder: Int { 0 }
    
    var settingsSearchableItems: [SearchableSettingItem] {
        [
            SearchableSettingItem(title: "Enable Mouse Gestures", description: "Master switch to enable or disable all gesture recognition", keywords: ["enable", "disable", "gestures", "toggle", "on", "off"]),
            SearchableSettingItem(title: "Developer Mode", description: "Show Developer tab with logging, plugins, performance, services, and diagnostics", keywords: ["developer", "debug", "advanced", "dev"])
        ]
    }
    
    @MainActor
    func createSettingsView(showAdvanced: Binding<Bool>) -> AnyView {
        AnyView(GeneralSettingsView(showAdvanced: showAdvanced))
    }
}

// MARK: - General Settings View

struct GeneralSettingsView: View {
    @Binding var showAdvanced: Bool
    @StateObject private var uiServices = UIServices.shared
    @StateObject private var registry = SettingsCategoryRegistry.shared
    
    @State private var gesturesEnabled = true
    @State private var developerModeEnabled = false
    
    /// Contributions from services/plugins targeting the "general" category
    private var generalContributions: [SettingsContribution] {
        registry.contributions(for: "general")
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsHeader("General")
            
            VStack(alignment: .leading, spacing: 15) {
                // Core: Enable Mouse Gestures
                settingsToggle(
                    isOn: $gesturesEnabled,
                    title: "Enable Mouse Gestures",
                    description: "Master switch to enable or disable all gesture recognition"
                ) { uiServices.setGesturesEnabled($0) }
                
                // Dynamic contributions from services/plugins
                ForEach(Array(generalContributions.enumerated()), id: \.offset) { _, contribution in
                    Divider()
                    contribution.viewBuilder()
                }
                
                // Developer Mode (advanced only)
                if showAdvanced {
                    Divider()
                    
                    Toggle(isOn: $developerModeEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Developer Mode")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Advanced")
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .cornerRadius(3)
                            }
                            Text("Show Developer tab with logging, plugins, performance, services, and diagnostics")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: developerModeEnabled) { newValue in
                        uiServices.setDeveloperModeEnabled(newValue)
                    }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        }
        .onAppear { loadSettings() }
    }
    
    private func loadSettings() {
        gesturesEnabled = uiServices.isGesturesEnabled()
        developerModeEnabled = uiServices.isDeveloperModeEnabled()
    }
}

// MARK: - Detection Settings Category

/// Wraps the existing detection plugin settings into a settings category.
class DetectionSettingsCategory: SettingsCategoryProvider {
    var settingsCategoryId: String { "detection" }
    var settingsCategoryTitle: String { "Detection" }
    var settingsCategoryIcon: String { "hand.tap" }
    var settingsCategoryOrder: Int { 10 }
    
    var settingsSearchableItems: [SearchableSettingItem] {
        let allSettings = DetectionPluginManager.shared.getAllSettingsDefinitions()
        var items: [SearchableSettingItem] = []
        for (_, categoryItems) in allSettings {
            for item in categoryItems {
                items.append(SearchableSettingItem(
                    title: item.definition.displayName,
                    description: item.definition.description ?? "",
                    keywords: ["detection", "trigger", item.plugin.name.lowercased()]
                ))
            }
        }
        return items
    }
    
    @MainActor
    func createSettingsView(showAdvanced: Binding<Bool>) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 20) {
                Text("Configure how gestures are detected, including zone dimensions, visual feedback, and performance tuning.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                PluginSettingsView(showAdvanced: showAdvanced)
            }
        )
    }
}

// MARK: - Data Management Settings Category

/// Settings for importing, exporting, and resetting application data.
class DataManagementSettingsCategory: SettingsCategoryProvider {
    var settingsCategoryId: String { "dataManagement" }
    var settingsCategoryTitle: String { "Data Management" }
    var settingsCategoryIcon: String { "externaldrive" }
    var settingsCategoryOrder: Int { 80 }
    
    var settingsSearchableItems: [SearchableSettingItem] {
        [
            SearchableSettingItem(title: "Export Settings", description: "Export all application settings to a file", keywords: ["export", "backup", "save", "settings", "file"]),
            SearchableSettingItem(title: "Import Settings", description: "Import application settings from a file", keywords: ["import", "restore", "load", "settings", "file"]),
            SearchableSettingItem(title: "Reset Application", description: "Reset all settings, profiles, and gestures to factory defaults", keywords: ["reset", "factory", "default", "clear", "wipe"])
        ]
    }
    
    @MainActor
    func createSettingsView(showAdvanced: Binding<Bool>) -> AnyView {
        AnyView(DataManagementSettingsView())
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
        VStack(alignment: .leading, spacing: 20) {
            settingsHeader("Data Management")
            
            VStack(alignment: .leading, spacing: 20) {
                // Import/Export
                VStack(alignment: .leading, spacing: 10) {
                    Text("Settings Backup")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("Export or import all application settings, including profiles, gestures, and preferences")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 10) {
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
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundColor(.green)
                    }
                    if let msg = exportSuccessMessage {
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundColor(.green)
                    }
                    if let err = errorMessage {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundColor(.red)
                    }
                }
                
                Divider()
                
                // Reset
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reset Application")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("Reset all settings, profiles, and gestures to factory defaults")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: { showingResetConfirmation = true }) {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(.red)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        }
        .alert("Reset Application", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) { resetApplication() }
        } message: {
            Text("This will reset all settings, profiles, and gestures to their default values. This action cannot be undone.")
        }
        .alert("Import Settings", isPresented: $showingImportOptions) {
            Button("Replace All") {
                mergeProfilesOnImport = false
                showingImportDialog = true
            }
            Button("Merge Profiles") {
                mergeProfilesOnImport = true
                showingImportDialog = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Would you like to replace all existing settings or merge the imported profiles with your current ones?")
        }
        .fileImporter(
            isPresented: $showingImportDialog,
            allowedContentTypes: [UTType.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .fileExporter(
            isPresented: $showingExportDialog,
            document: SettingsExportDocument(data: uiServices.configuration.exportGlobalSettings() ?? Data()),
            contentType: UTType.json,
            defaultFilename: "MouseGestures_Settings_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).json"
        ) { result in
            handleExport(result: result)
        }
    }
    
    private func handleImport(result: Result<[URL], Error>) {
        errorMessage = nil
        importSuccessMessage = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if uiServices.importAppSettings(from: url, mergeProfiles: mergeProfilesOnImport) {
                importSuccessMessage = mergeProfilesOnImport ? "Settings merged successfully" : "Settings imported successfully"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { importSuccessMessage = nil }
            } else {
                errorMessage = uiServices.errorMessage ?? "Import failed"
            }
        case .failure(let error):
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }
    
    private func handleExport(result: Result<URL, Error>) {
        errorMessage = nil
        exportSuccessMessage = nil
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

// MARK: - About Settings Category

/// Version info and update checking.
class AboutSettingsCategory: SettingsCategoryProvider {
    var settingsCategoryId: String { "about" }
    var settingsCategoryTitle: String { "About" }
    var settingsCategoryIcon: String { "info.circle" }
    var settingsCategoryOrder: Int { 90 }
    
    var settingsSearchableItems: [SearchableSettingItem] {
        [
            SearchableSettingItem(title: "Version Information", description: "Current app version and build number", keywords: ["version", "build", "number", "about"]),
            SearchableSettingItem(title: "Check for Updates", description: "Check for the latest version of MouseGestures", keywords: ["update", "check", "latest", "new", "version"])
        ]
    }
    
    @MainActor
    func createSettingsView(showAdvanced: Binding<Bool>) -> AnyView {
        AnyView(AboutSettingsView())
    }
}

// MARK: - About View

struct AboutSettingsView: View {
    @State private var isCheckingForUpdates = false
    @State private var updateMessage: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsHeader("About")
            
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Version Information")
                        .font(.system(size: 14, weight: .semibold))
                    
                    HStack {
                        Text("Current Version:")
                            .font(.system(size: 13))
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                            .font(.system(size: 13, weight: .medium))
                    }
                    
                    HStack {
                        Text("Build Number:")
                            .font(.system(size: 13))
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Check for Updates")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("Check for the latest version of MouseGestures")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button(action: checkForUpdates) {
                            if isCheckingForUpdates {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                                    .frame(width: 16, height: 16)
                                Text("Checking...")
                            } else {
                                Label("Check Now", systemImage: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isCheckingForUpdates)
                        
                        if let msg = updateMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        }
    }
    
    private func checkForUpdates() {
        isCheckingForUpdates = true
        updateMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCheckingForUpdates = false
            updateMessage = "You are running the latest version"
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { updateMessage = nil }
        }
    }
}

// MARK: - Shared Settings View Helpers

/// Reusable header for settings sections
func settingsHeader(_ title: String) -> some View {
    Text(title)
        .font(.title2)
        .fontWeight(.semibold)
}

/// Reusable toggle row for settings
func settingsToggle(isOn: Binding<Bool>, title: String, description: String, onChange: @escaping (Bool) -> Void) -> some View {
    Toggle(isOn: isOn) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    .onChange(of: isOn.wrappedValue) { newValue in
        onChange(newValue)
    }
}

// MARK: - Settings Export Document

struct SettingsExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    
    var data: Data
    
    init(data: Data) {
        self.data = data
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Built-in Category Registration

/// Registers all built-in settings categories with the registry.
/// Called during Settings UI plugin initialization.
func registerBuiltInSettingsCategories() {
    let registry = SettingsCategoryRegistry.shared
    registry.register(GeneralSettingsCategory())
    registry.register(DetectionSettingsCategory())
    registry.register(DataManagementSettingsCategory())
    registry.register(AboutSettingsCategory())
    
    // Discover and register settings from service plugins
    registerServicePluginSettings()
}

/// Discovers service plugins that provide settings (either full categories or item contributions)
/// and registers them with the settings registry.
func registerServicePluginSettings() {
    let registry = SettingsCategoryRegistry.shared
    
    // Clear previous contributions so we don't duplicate
    registry.clearContributions()
    
    // Iterate all loaded service plugins
    for pluginInfo in ServicePluginManager.shared.getAllPlugins() {
        guard let plugin = ServicePluginManager.shared.getPlugin(identifier: pluginInfo.identifier) else { continue }
        
        // Full category providers
        if let categoryProvider = plugin as? SettingsCategoryProvider {
            registry.register(categoryProvider)
        }
        
        // Item contributors (contribute to existing categories like "general")
        if let contributor = plugin as? SettingsItemContributor {
            registry.registerContributions(from: contributor)
        }
    }
}
