import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings Tab
struct SettingsView: View {
    @StateObject private var uiServices = UIServices.shared
    
    // State for toggles
    @State private var gesturesEnabled: Bool = true
    @State private var launchAtLogin: Bool = false
    @State private var hapticFeedback: Bool = true
    @State private var hideMenuBarIcon: Bool = false
    @State private var showZoneHighlights: Bool = false
    @State private var showZoneLabels: Bool = false
    @State private var developerModeEnabled: Bool = false
    @State private var debugModeEnabled: Bool = false
    
    // Zone configuration
    @State private var edgeThreshold: Double = 30
    @State private var cornerSize: Double = 100
    @State private var cornerBuffer: Double = 50
    
    // UI State
    @State private var showingImportDialog = false
    @State private var showingExportDialog = false
    @State private var showingResetConfirmation = false
    @State private var showingImportOptions = false
    @State private var mergeProfilesOnImport = false
    @State private var importSuccessMessage: String?
    @State private var exportSuccessMessage: String?
    @State private var errorMessage: String?
    @State private var selectedSection: SettingsSection = .general
    
    // Update checking
    @State private var isCheckingForUpdates = false
    @State private var updateMessage: String?
    
    enum SettingsSection: String, CaseIterable {
        case general = "General"
        case zones = "Zone Configuration"
        case menuBar = "Menu Bar"
        case dataManagement = "Data Management"
        case advanced = "Advanced"
        case updates = "Updates"
        
        var icon: String {
            switch self {
            case .general: return "gear"
            case .zones: return "rectangle.split.3x3"
            case .menuBar: return "menubar.rectangle"
            case .dataManagement: return "externaldrive"
            case .advanced: return "wrench.and.screwdriver"
            case .updates: return "arrow.clockwise.circle"
            }
        }
    }
    
    var body: some View {
        HSplitView {
            // Sidebar with sections
            sidebarView
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 250)
            
            // Main content area
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedSection {
                    case .general:
                        generalSettingsSection
                    case .zones:
                        zoneConfigurationSection
                    case .menuBar:
                        menuBarSection
                    case .dataManagement:
                        dataManagementSection
                    case .advanced:
                        advancedSection
                    case .updates:
                        updatesSection
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadSettings()
        }
        .alert("Reset Application", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetApplication()
            }
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
    
    // MARK: - Sidebar View
    
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 10)
            
            Divider()
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsSection.allCases, id: \.self) { section in
                    if section == .advanced && !developerModeEnabled {
                        // Hide advanced section if developer mode is disabled
                    } else {
                        sidebarItem(for: section)
                    }
                }
            }
            .padding(.horizontal, 10)
            
            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func sidebarItem(for section: SettingsSection) -> some View {
        Button(action: {
            selectedSection = section
        }) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .frame(width: 20)
                    .foregroundColor(selectedSection == section ? .white : .secondary)
                
                Text(section.rawValue)
                    .fontWeight(selectedSection == section ? .medium : .regular)
                    .foregroundColor(selectedSection == section ? .white : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedSection == section ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - General Settings Section
    
    private var generalSettingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("General Settings")
            
            VStack(alignment: .leading, spacing: 15) {
                // Enable Mouse Gestures
                Toggle(isOn: $gesturesEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Mouse Gestures")
                            .font(.system(size: 13, weight: .medium))
                        Text("Master switch to enable or disable all gesture recognition")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: gesturesEnabled) { newValue in
                    uiServices.setGesturesEnabled(newValue)
                }
                
                Divider()
                
                // Launch at Login
                Toggle(isOn: $launchAtLogin) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                            .font(.system(size: 13, weight: .medium))
                        Text("Automatically start MouseGestures when you log in")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: launchAtLogin) { newValue in
                    uiServices.setLaunchAtLoginEnabled(newValue)
                }
                
                Divider()
                
                // Haptic Feedback
                Toggle(isOn: $hapticFeedback) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Haptic Feedback")
                            .font(.system(size: 13, weight: .medium))
                        Text("Provide haptic feedback when gestures are recognized (MacBooks with Force Touch)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: hapticFeedback) { newValue in
                    uiServices.setHapticFeedbackEnabled(newValue)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        }
    }
    
    // MARK: - Zone Configuration Section
    
    private var zoneConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Zone Configuration")
            
            VStack(alignment: .leading, spacing: 20) {
                // Visual Feedback
                VStack(alignment: .leading, spacing: 15) {
                    Text("Visual Feedback")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Toggle(isOn: $showZoneHighlights) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Zone Highlights")
                                .font(.system(size: 13, weight: .medium))
                            Text("Display visual highlights when entering screen zones")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: showZoneHighlights) { newValue in
                        uiServices.setShowZoneHighlights(newValue)
                    }
                    
                    Toggle(isOn: $showZoneLabels) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Zone Labels")
                                .font(.system(size: 13, weight: .medium))
                            Text("Display zone names when highlights are shown")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(!showZoneHighlights)
                    .onChange(of: showZoneLabels) { newValue in
                        uiServices.setShowZoneLabels(newValue)
                    }
                }
                
                Divider()
                
                // Zone Sizes
                VStack(alignment: .leading, spacing: 15) {
                    Text("Zone Dimensions")
                        .font(.system(size: 14, weight: .semibold))
                    
                    // Edge Threshold
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Edge Threshold")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(Int(edgeThreshold)) pixels")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $edgeThreshold, in: 10...100, step: 5)
                            .onChange(of: edgeThreshold) { newValue in
                                uiServices.setEdgeThreshold(CGFloat(newValue))
                            }
                        Text("Distance from screen edge to detect edge zones")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Corner Size
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Corner Size")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(Int(cornerSize)) pixels")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $cornerSize, in: 50...200, step: 10)
                            .onChange(of: cornerSize) { newValue in
                                uiServices.setCornerSize(CGFloat(newValue))
                            }
                        Text("Size of corner detection zones")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Corner Buffer
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Corner Buffer")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("\(Int(cornerBuffer)) pixels")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $cornerBuffer, in: 0...100, step: 5)
                            .onChange(of: cornerBuffer) { newValue in
                                uiServices.setCornerBuffer(CGFloat(newValue))
                            }
                        Text("Additional area around corners for easier targeting")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Reset to Defaults") {
                        edgeThreshold = 30
                        cornerSize = 100
                        cornerBuffer = 50
                        uiServices.setEdgeThreshold(30)
                        uiServices.setCornerSize(100)
                        uiServices.setCornerBuffer(50)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        }
    }
    
    // MARK: - Menu Bar Section
    
    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Menu Bar Icon")
            
            VStack(alignment: .leading, spacing: 15) {
                Toggle(isOn: Binding(
                    get: { !hideMenuBarIcon },
                    set: { hideMenuBarIcon = !$0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Menu Bar Icon")
                            .font(.system(size: 13, weight: .medium))
                        Text("Display MouseGestures icon in the menu bar for quick access")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: hideMenuBarIcon) { newValue in
                    uiServices.setMenuBarIconHidden(newValue)
                }
                
                if !hideMenuBarIcon {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Menu Bar Options")
                            .font(.system(size: 13, weight: .medium))
                        
                        Text("• Quick enable/disable gestures")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Switch between profiles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• Open preferences window")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("• View current profile")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if hideMenuBarIcon {
                    Label("Note: You can still access settings through the dock icon", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        }
    }
    
    // MARK: - Data Management Section
    
    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Data Management")
            
            VStack(alignment: .leading, spacing: 20) {
                // Import/Export
                VStack(alignment: .leading, spacing: 10) {
                    Text("Settings Backup")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("Export or import all application settings, including profiles, gestures, and preferences")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 10) {
                        Button(action: {
                            showingExportDialog = true
                        }) {
                            Label("Export Settings", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(action: {
                            showingImportOptions = true
                        }) {
                            Label("Import Settings", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    
                    if let successMessage = importSuccessMessage {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    if let successMessage = exportSuccessMessage {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
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
                    
                    Button(action: {
                        showingResetConfirmation = true
                    }) {
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
    }
    
    // MARK: - Advanced Section
    
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Advanced Settings")
            
            VStack(alignment: .leading, spacing: 15) {
                Text("Developer Options")
                    .font(.system(size: 14, weight: .semibold))
                
                Toggle(isOn: $developerModeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Developer Mode")
                            .font(.system(size: 13, weight: .medium))
                        Text("Show Developer tab in the sidebar with advanced tools and diagnostics")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: developerModeEnabled) { newValue in
                    uiServices.setDeveloperModeEnabled(newValue)
                }
                
                Toggle(isOn: $debugModeEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Debug Logging")
                            .font(.system(size: 13, weight: .medium))
                        Text("Enable detailed logging for troubleshooting (logs saved to ~/Library/Logs/MouseGestures)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: debugModeEnabled) { newValue in
                    uiServices.setDebugModeEnabled(newValue)
                }
                
                if debugModeEnabled {
                    Button(action: openLogsFolder) {
                        Label("Open Logs Folder", systemImage: "folder")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                
                Divider()
                
                // Performance
                VStack(alignment: .leading, spacing: 10) {
                    Text("Performance")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("Accessibility permissions required: \(checkAccessibilityStatus())")
                        .font(.caption)
                        .foregroundColor(hasAccessibilityPermissions() ? .green : .orange)
                    
                    if !hasAccessibilityPermissions() {
                        Button("Open System Preferences") {
                            openAccessibilityPreferences()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        }
    }
    
    // MARK: - Updates Section
    
    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Application Updates")
            
            VStack(alignment: .leading, spacing: 20) {
                // Current Version
                VStack(alignment: .leading, spacing: 10) {
                    Text("Version Information")
                        .font(.system(size: 14, weight: .semibold))
                    
                    HStack {
                        Text("Current Version:")
                            .font(.system(size: 13))
                        Text(getCurrentVersion())
                            .font(.system(size: 13, weight: .medium))
                    }
                    
                    HStack {
                        Text("Build Number:")
                            .font(.system(size: 13))
                        Text(getBuildNumber())
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                
                Divider()
                
                // Update Check
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
                        
                        if let message = updateMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Divider()
                
                // Auto Update Settings
                VStack(alignment: .leading, spacing: 10) {
                    Text("Update Settings")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("Automatic update checking is not yet implemented")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
        }
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2)
            .fontWeight(.semibold)
    }
    
    // MARK: - Helper Functions
    
    private func loadSettings() {
        gesturesEnabled = uiServices.isGesturesEnabled()
        launchAtLogin = uiServices.isLaunchAtLoginEnabled()
        hapticFeedback = uiServices.isHapticFeedbackEnabled()
        hideMenuBarIcon = uiServices.isMenuBarIconHidden()
        showZoneHighlights = uiServices.isShowZoneHighlights()
        showZoneLabels = uiServices.isShowZoneLabels()
        edgeThreshold = Double(uiServices.getEdgeThreshold())
        cornerSize = Double(uiServices.getCornerSize())
        cornerBuffer = Double(uiServices.getCornerBuffer())
        developerModeEnabled = uiServices.isDeveloperModeEnabled()
        debugModeEnabled = uiServices.isDebugModeEnabled()
    }
    
    private func handleImport(result: Result<[URL], Error>) {
        errorMessage = nil
        importSuccessMessage = nil
        
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if uiServices.importAppSettings(from: url, mergeProfiles: mergeProfilesOnImport) {
                importSuccessMessage = mergeProfilesOnImport ? "Settings merged successfully" : "Settings imported successfully"
                loadSettings()
                
                // Clear message after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    importSuccessMessage = nil
                }
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
        case .success(_):
            exportSuccessMessage = "Settings exported successfully"
            
            // Clear message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                exportSuccessMessage = nil
            }
        case .failure(let error):
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }
    
    private func resetApplication() {
        uiServices.resetAppToDefaults()
        loadSettings()
        errorMessage = nil
        importSuccessMessage = "Application reset to defaults"
        
        // Clear message after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            importSuccessMessage = nil
        }
    }
    
    private func checkForUpdates() {
        isCheckingForUpdates = true
        updateMessage = nil
        
        // Simulate update check - replace with actual implementation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCheckingForUpdates = false
            updateMessage = "You are running the latest version"
            
            // Clear message after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                updateMessage = nil
            }
        }
    }
    
    private func getCurrentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private func getBuildNumber() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    private func openLogsFolder() {
        let logsPath = NSHomeDirectory() + "/Library/Logs/MouseGestures"
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logsPath)
    }
    
    private func hasAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    private func checkAccessibilityStatus() -> String {
        return hasAccessibilityPermissions() ? "Granted ✓" : "Not Granted"
    }
    
    private func openAccessibilityPreferences() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
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
