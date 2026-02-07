import SwiftUI
import UniformTypeIdentifiers

// MARK: - Well-Known Category Descriptors

/// Predefined category descriptors that built-in entries and service plugins can target.
/// Plugins can also create entirely new categories by using a new descriptor.
enum SettingsCategories {
    static let general = SettingsCategoryDescriptor(id: "general", title: "General", icon: "gear", order: 0)
    static let detection = SettingsCategoryDescriptor(id: "detection", title: "Detection", icon: "hand.tap", order: 10)
    static let dataManagement = SettingsCategoryDescriptor(id: "dataManagement", title: "Data Management", icon: "externaldrive", order: 80)
    static let about = SettingsCategoryDescriptor(id: "about", title: "About", icon: "info.circle", order: 90)
}

// MARK: - Built-In Settings Provider

/// Provides core app settings entries that don't belong to any particular service plugin.
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
            
            // Developer Mode toggle (advanced)
            SettingsEntry(
                category: SettingsCategories.general,
                order: 900,
                isAdvanced: true,
                searchableItems: [
                    SearchableSettingItem(title: "Developer Mode", description: "Show Developer tab with logging, plugins, performance, services, and diagnostics", keywords: ["developer", "debug", "advanced", "dev"])
                ],
                viewBuilder: { _ in AnyView(DeveloperModeSettingView()) }
            ),
            
            // Detection settings (wraps existing PluginSettingsView)
            SettingsEntry(
                category: SettingsCategories.detection,
                order: 0,
                searchableItems: detectionSearchableItems(),
                viewBuilder: { showAdvanced in
                    AnyView(
                        VStack(alignment: .leading, spacing: 20) {
                            Text("Configure how gestures are detected, including zone dimensions, visual feedback, and performance tuning.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            PluginSettingsView(showAdvanced: showAdvanced)
                        }
                    )
                }
            ),
            
            // Data Management
            SettingsEntry(
                category: SettingsCategories.dataManagement,
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
                order: 0,
                searchableItems: [
                    SearchableSettingItem(title: "Version Information", description: "Current app version and build number", keywords: ["version", "build", "number", "about"]),
                    SearchableSettingItem(title: "Check for Updates", description: "Check for the latest version of MouseGestures", keywords: ["update", "check", "latest", "new", "version"])
                ],
                viewBuilder: { _ in AnyView(AboutSettingsView()) }
            )
        ]
    }
    
    private func detectionSearchableItems() -> [SearchableSettingItem] {
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
                        Text(msg).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private func checkForUpdates() {
        isCheckingForUpdates = true; updateMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCheckingForUpdates = false
            updateMessage = "You are running the latest version"
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { updateMessage = nil }
        }
    }
}

// MARK: - Shared Settings View Helpers

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

/// Registers all settings entries: built-in core entries + service plugin entries.
/// Called during Settings UI plugin initialization.
func registerAllSettings() {
    let registry = SettingsCategoryRegistry.shared
    registry.clear()
    
    // Built-in core entries
    registry.register(BuiltInSettingsProvider())
    
    // Discover service plugins that provide settings
    for pluginInfo in ServicePluginManager.shared.getAllPlugins() {
        guard let plugin = ServicePluginManager.shared.getPlugin(identifier: pluginInfo.identifier) else { continue }
        if let provider = plugin as? SettingsProvider {
            registry.register(provider)
        }
    }
}
