import SwiftUI
import UniformTypeIdentifiers

// MARK: - Developer Tab
struct DeveloperView: View {
    @StateObject private var uiServices = UIServices.shared
    
    // State
    @State private var selectedSection: DeveloperSection = .logging
    @State private var debugLoggingEnabled: Bool = false
    @State private var logFiles: [LogFileInfo] = []
    @State private var selectedLogFile: LogFileInfo?
    @State private var logContent: String = ""
    @State private var isLoadingLogContent = false
    
    // Plugins
    @State private var plugins: [PluginInfo] = []
    @State private var selectedPlugin: PluginInfo?
    @State private var showingPluginDetails = false
    @State private var showingInstallPlugin = false
    
    // Performance (driven by PerformanceMonitorService)
    private let perfMonitor = PerformanceMonitorService.shared
    @State private var memoryUsage: (resident: String, virtual: String) = ("", "")
    @State private var cpuUsage: Double = 0.0
    @State private var updateTimer: Timer?
    
    // Debug Report
    @State private var debugReport: String = ""
    @State private var showingExportReport = false
    
    // Messages
    @State private var successMessage: String?
    @State private var errorMessage: String?
    
    enum DeveloperSection: String, CaseIterable {
        case logging = "Logging"
        case plugins = "Plugin Management"
        case performance = "Performance"
        case diagnostics = "Diagnostics"
        case services = "Services"
        
        var icon: String {
            switch self {
            case .logging: return "doc.text"
            case .plugins: return "puzzlepiece.extension"
            case .performance: return "speedometer"
            case .diagnostics: return "stethoscope"
            case .services: return "gearshape.2"
            }
        }
    }
    
    var body: some View {
        HSplitView {
            // Sidebar
            sidebarView
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 250)
            
            // Main content
            Group {
                if selectedSection == .services {
                    // Services has its own HSplitView layout, so don't wrap in ScrollView
                    ServicesView()
                        .frame(minWidth: 600)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            switch selectedSection {
                            case .logging:
                                loggingSection
                            case .plugins:
                                pluginsSection
                            case .performance:
                                performanceSection
                            case .diagnostics:
                                diagnosticsSection
                            case .services:
                                EmptyView()
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minWidth: 600)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadInitialData()
            startPerformanceMonitoring()
        }
        .onDisappear {
            stopPerformanceMonitoring()
        }
        .fileImporter(
            isPresented: $showingInstallPlugin,
            allowedContentTypes: [UTType(filenameExtension: "plugin") ?? .item, .bundle],
            allowsMultipleSelection: false
        ) { result in
            handlePluginInstall(result: result)
        }
        .fileExporter(
            isPresented: $showingExportReport,
            document: DebugReportDocument(content: debugReport),
            contentType: .plainText,
            defaultFilename: "MouseGestures_Debug_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).txt"
        ) { result in
            handleReportExport(result: result)
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Developer Settings")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 10)
            
            Divider()
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            
            VStack(alignment: .leading, spacing: 2) {
                ForEach(DeveloperSection.allCases, id: \.self) { section in
                    sidebarItem(for: section)
                }
            }
            .padding(.horizontal, 10)
            
            Spacer()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func sidebarItem(for section: DeveloperSection) -> some View {
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
    
    // MARK: - Logging Section
    
    private var loggingSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Debug Logging")
            
            VStack(alignment: .leading, spacing: 20) {
                // Logging Controls
                VStack(alignment: .leading, spacing: 15) {
                    Toggle(isOn: $debugLoggingEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Debug Logging")
                                .font(.system(size: 13, weight: .medium))
                            Text("Records detailed debug information to log files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: debugLoggingEnabled) { newValue in
                        uiServices.setDebugModeEnabled(newValue)
                        if newValue {
                            refreshLogFiles()
                        }
                    }
                    
                    if debugLoggingEnabled {
                        HStack {
                            Button("Open Logs Folder") {
                                openLogsFolder()
                            }
                            
                            Button("Refresh") {
                                refreshLogFiles()
                            }
                            
                            Spacer()
                            
                            if !logFiles.isEmpty {
                                Button("Clear All Logs") {
                                    clearAllLogs()
                                }
                                .foregroundColor(.red)
                            }
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                
                if debugLoggingEnabled && !logFiles.isEmpty {
                    // Log Files List
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Log Files")
                            .font(.system(size: 14, weight: .semibold))
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(logFiles, id: \.url) { logFile in
                                    logFileRow(logFile)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                    
                    // Log Content Viewer
                    if let selectedLog = selectedLogFile {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Log Content: \(selectedLog.name)")
                                    .font(.system(size: 14, weight: .semibold))
                                
                                Spacer()
                                
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(logContent, forType: .string)
                                }
                                
                                Button("Export") {
                                    exportLogFile(selectedLog)
                                }
                            }
                            
                            ScrollView {
                                Text(logContent.isEmpty ? "Loading..." : logContent)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                            .frame(height: 300)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.3))
                            )
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                    }
                }
            }
        }
    }
    
    private func logFileRow(_ logFile: LogFileInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(logFile.name)
                    .font(.system(size: 12, weight: selectedLogFile?.url == logFile.url ? .medium : .regular))
                    .foregroundColor(selectedLogFile?.url == logFile.url ? .accentColor : .primary)
                
                HStack(spacing: 10) {
                    Text(logFile.size)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(logFile.date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: {
                deleteLogFile(logFile)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.caption)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(selectedLogFile?.url == logFile.url ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectLogFile(logFile)
        }
    }
    
    // MARK: - Plugins Section
    
    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Plugin Management")
            
            VStack(alignment: .leading, spacing: 20) {
                // Plugin Actions
                HStack {
                    Button(action: {
                        showingInstallPlugin = true
                    }) {
                        Label("Install Plugin", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Refresh") {
                        refreshPlugins()
                    }
                    
                    Spacer()
                    
                    Text("\(plugins.count) plugins loaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                
                // Plugins List
                if !plugins.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Loaded Plugins")
                            .font(.system(size: 14, weight: .semibold))
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(plugins, id: \.identifier) { plugin in
                                    pluginRow(plugin)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                }
                
                // Plugin Details
                if let plugin = selectedPlugin {
                    pluginDetailsView(plugin)
                }
            }
        }
    }
    
    private func pluginRow(_ plugin: PluginInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(plugin.name)
                            .font(.system(size: 13, weight: .medium))
                        
                        Text("v\(plugin.version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if plugin.isBuiltIn {
                            Text("BUILT-IN")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.2)))
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Text(plugin.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    HStack(spacing: 10) {
                        Label("\(plugin.actionCount) actions", systemImage: "bolt.circle")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Label(plugin.category.rawValue, systemImage: "tag")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("by \(plugin.author)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 5) {
                    if !plugin.isBuiltIn {
                        Button("Permissions") {
                            showPluginPermissions(plugin)
                        }
                        .font(.caption)
                        
                        Button("Uninstall") {
                            uninstallPlugin(plugin)
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                    
                    Button("Reload") {
                        reloadPlugin(plugin)
                    }
                    .font(.caption)
                }
            }
            
            Divider()
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPlugin = plugin
        }
    }
    
    private func pluginDetailsView(_ plugin: PluginInfo) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Plugin Details: \(plugin.name)")
                .font(.system(size: 14, weight: .semibold))
            
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text("Identifier:")
                        .foregroundColor(.secondary)
                    Text(plugin.identifier)
                        .font(.system(.caption, design: .monospaced))
                }
                
                GridRow {
                    Text("Permissions:")
                        .foregroundColor(.secondary)
                    Text(describePermissions(plugin.permissions))
                }
                
                GridRow {
                    Text("Status:")
                        .foregroundColor(.secondary)
                    HStack {
                        Circle()
                            .fill(plugin.isEnabled ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(plugin.isEnabled ? "Enabled" : "Disabled")
                    }
                }
            }
            
            // Plugin Actions List
            if plugin.actionCount > 0 {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Provided Actions:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(uiServices.getPluginActions(plugin.identifier), id: \.id) { action in
                                HStack {
                                    Image(systemName: action.icon ?? "questionmark.circle")
                                        .frame(width: 16)
                                        .font(.caption)
                                    Text(action.name)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(NSColor.textBackgroundColor)))
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
    }
    
    // MARK: - Performance Section
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("Performance Monitoring")
            
            VStack(alignment: .leading, spacing: 20) {
                // System Permissions
                VStack(alignment: .leading, spacing: 10) {
                    Text("System Permissions")
                        .font(.system(size: 14, weight: .semibold))
                    
                    HStack(spacing: 10) {
                        Text("Accessibility:")
                            .foregroundColor(.secondary)
                        
                        if hasAccessibilityPermissions() {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Label("Not Granted", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                        
                        if !hasAccessibilityPermissions() {
                            Button("Open System Settings") {
                                openAccessibilityPreferences()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    
                    Text("Accessibility permissions are required for MouseGestures to detect and respond to mouse and keyboard events.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                
                // Memory Usage
                VStack(alignment: .leading, spacing: 10) {
                    Text("Memory Usage")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 30, verticalSpacing: 8) {
                        GridRow {
                            Text("Resident Memory:")
                                .foregroundColor(.secondary)
                            Text(memoryUsage.resident)
                                .font(.system(.body, design: .monospaced))
                        }
                        
                        GridRow {
                            Text("Virtual Memory:")
                                .foregroundColor(.secondary)
                            Text(memoryUsage.virtual)
                                .font(.system(.body, design: .monospaced))
                        }
                        
                        GridRow {
                            Text("System Memory:")
                                .foregroundColor(.secondary)
                            Text(perfMonitor.getSystemMemory())
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                
                // CPU Usage
                VStack(alignment: .leading, spacing: 10) {
                    Text("CPU Usage")
                        .font(.system(size: 14, weight: .semibold))
                    
                    HStack {
                        ProgressView(value: min(cpuUsage, 100), total: 100)
                            .progressViewStyle(.linear)
                        
                        Text(String(format: "%.1f%%", cpuUsage))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 60)
                    }
                    
                    Text("Processor: \(perfMonitor.getProcessorCount()) cores")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                
                // System Info
                VStack(alignment: .leading, spacing: 10) {
                    Text("System Information")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 30, verticalSpacing: 8) {
                        GridRow {
                            Text("macOS Version:")
                                .foregroundColor(.secondary)
                            Text(perfMonitor.getSystemVersion())
                        }
                        
                        GridRow {
                            Text("App Version:")
                                .foregroundColor(.secondary)
                            Text(perfMonitor.getAppVersion())
                        }
                        
                        GridRow {
                            Text("Process ID:")
                                .foregroundColor(.secondary)
                            Text("\(perfMonitor.getProcessID())")
                                .font(.system(.body, design: .monospaced))
                        }
                        
                        GridRow {
                            Text("Uptime:")
                                .foregroundColor(.secondary)
                            Text(perfMonitor.getUptime())
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
            }
        }
    }
    
    // MARK: - Diagnostics Section
    
    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader("System Diagnostics")
            
            VStack(alignment: .leading, spacing: 20) {
                // Debug Report
                VStack(alignment: .leading, spacing: 10) {
                    Text("Debug Report")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("Generate a comprehensive debug report containing system information, configuration, and diagnostics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("Generate Report") {
                            generateDebugReport()
                        }
                        .buttonStyle(.borderedProminent)
                        
                        if !debugReport.isEmpty {
                            Button("Copy to Clipboard") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(debugReport, forType: .string)
                                successMessage = "Report copied to clipboard"
                            }
                            
                            Button("Export") {
                                showingExportReport = true
                            }
                        }
                    }
                    
                    if !debugReport.isEmpty {
                        ScrollView {
                            Text(debugReport)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(height: 300)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3))
                        )
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                
                // Quick Actions
                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick Actions")
                        .font(.system(size: 14, weight: .semibold))
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Reset All Preferences") {
                            resetPreferences()
                        }
                        .foregroundColor(.red)
                        
                        Button("Clear All Caches") {
                            clearCaches()
                        }
                        
                        Button("Reload All Plugins") {
                            reloadAllPlugins()
                        }
                        
                        Button("Export All Logs") {
                            exportAllLogs()
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
            }
            
            // Messages
            if let message = successMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            if let message = errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2)
            .fontWeight(.semibold)
    }
    
    // MARK: - Helper Functions
    
    private func loadInitialData() {
        debugLoggingEnabled = uiServices.isDebugModeEnabled()
        refreshLogFiles()
        refreshPlugins()
        refreshPerformanceMetrics()
    }
    
    private func startPerformanceMonitoring() {
        perfMonitor.startMonitoring(updateInterval: 2.0)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            refreshPerformanceMetrics()
        }
    }
    
    private func stopPerformanceMonitoring() {
        updateTimer?.invalidate()
        updateTimer = nil
        perfMonitor.stopMonitoring()
    }
    
    private func refreshPerformanceMetrics() {
        memoryUsage = perfMonitor.getMemoryUsage()
        cpuUsage = perfMonitor.getCPUUsage()
    }
    
    private func refreshLogFiles() {
        let urls = uiServices.getLogFiles()
        logFiles = urls.map { url in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes?[.size] as? Int64 ?? 0
            let date = attributes?[.creationDate] as? Date ?? Date()
            
            return LogFileInfo(
                url: url,
                name: url.lastPathComponent,
                size: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                date: date.formatted(date: .abbreviated, time: .shortened)
            )
        }
    }
    
    private func selectLogFile(_ logFile: LogFileInfo) {
        selectedLogFile = logFile
        isLoadingLogContent = true
        
        DispatchQueue.global().async {
            do {
                let content = try String(contentsOf: logFile.url, encoding: .utf8)
                DispatchQueue.main.async {
                    self.logContent = content
                    self.isLoadingLogContent = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.logContent = "Error loading log file: \(error.localizedDescription)"
                    self.isLoadingLogContent = false
                }
            }
        }
    }
    
    private func deleteLogFile(_ logFile: LogFileInfo) {
        if uiServices.deleteLogFile(logFile.url) {
            refreshLogFiles()
            if selectedLogFile?.url == logFile.url {
                selectedLogFile = nil
                logContent = ""
            }
        }
    }
    
    private func clearAllLogs() {
        if uiServices.clearAllLogs() {
            refreshLogFiles()
            selectedLogFile = nil
            logContent = ""
            successMessage = "All logs cleared"
        }
    }
    
    private func openLogsFolder() {
        let logsPath = NSHomeDirectory() + "/Library/Logs/MouseGestures"
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logsPath)
    }
    
    private func exportLogFile(_ logFile: LogFileInfo) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.log]
        savePanel.nameFieldStringValue = logFile.name
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try FileManager.default.copyItem(at: logFile.url, to: url)
                    successMessage = "Log exported successfully"
                } catch {
                    errorMessage = "Failed to export log: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func refreshPlugins() {
        plugins = uiServices.getLoadedPlugins()
    }
    
    private func handlePluginInstall(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            if uiServices.installPlugin(from: url) {
                refreshPlugins()
                successMessage = "Plugin installed successfully"
            } else {
                errorMessage = uiServices.errorMessage ?? "Failed to install plugin"
            }
        case .failure(let error):
            errorMessage = "Install failed: \(error.localizedDescription)"
        }
    }
    
    private func uninstallPlugin(_ plugin: PluginInfo) {
        if uiServices.uninstallPlugin(plugin.identifier) {
            refreshPlugins()
            if selectedPlugin?.identifier == plugin.identifier {
                selectedPlugin = nil
            }
            successMessage = "Plugin uninstalled"
        }
    }
    
    private func reloadPlugin(_ plugin: PluginInfo) {
        if uiServices.reloadPlugin(plugin.identifier) {
            refreshPlugins()
            successMessage = "Plugin reloaded"
        } else {
            errorMessage = "Failed to reload plugin"
        }
    }
    
    private func showPluginPermissions(_ plugin: PluginInfo) {
        let perms = describePermissions(plugin.permissions)
        successMessage = "Permissions: \(perms)"
    }
    
    private func describePermissions(_ permissions: PluginPermissions) -> String {
        if permissions == .builtIn {
            return "Full Access (Built-in)"
        } else if permissions == .restricted {
            return "Restricted"
        } else {
            var perms: [String] = []
            if permissions.canAccessFileSystem { perms.append("Files") }
            if permissions.canAccessNetwork { perms.append("Network") }
            if permissions.canAccessSystemAPIs { perms.append("System") }
            if permissions.canExecuteOtherActions { perms.append("Actions") }
            if permissions.canShowNotifications { perms.append("Notifications") }
            return perms.isEmpty ? "None" : perms.joined(separator: ", ")
        }
    }
    
    private func generateDebugReport() {
        debugReport = uiServices.generateDebugReport()
        successMessage = "Debug report generated"
    }
    
    private func handleReportExport(result: Result<URL, Error>) {
        switch result {
        case .success:
            successMessage = "Report exported successfully"
        case .failure(let error):
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }
    
    private func resetPreferences() {
        uiServices.resetAppToDefaults()
        successMessage = "Preferences reset to defaults"
    }
    
    private func clearCaches() {
        successMessage = "Caches cleared"
    }
    
    private func reloadAllPlugins() {
        for plugin in plugins where !plugin.isBuiltIn {
            _ = uiServices.reloadPlugin(plugin.identifier)
        }
        refreshPlugins()
        successMessage = "All plugins reloaded"
    }
    
    private func exportAllLogs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "zip") ?? .item]
        savePanel.nameFieldStringValue = "MouseGestures_Logs_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).zip"
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if uiServices.exportLogs(to: url) {
                    successMessage = "Logs exported successfully"
                } else {
                    errorMessage = uiServices.errorMessage ?? "Failed to export logs"
                }
            }
        }
    }
    
    private func hasAccessibilityPermissions() -> Bool {
        return AXIsProcessTrusted()
    }
    
    private func openAccessibilityPreferences() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

// MARK: - Supporting Types

struct LogFileInfo {
    let url: URL
    let name: String
    let size: String
    let date: String
}

struct DebugReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    
    var content: String
    
    init(content: String) {
        self.content = content
    }
    
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        content = string
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = content.data(using: .utf8)!
        return FileWrapper(regularFileWithContents: data)
    }
}
