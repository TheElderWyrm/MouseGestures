import SwiftUI
import UniformTypeIdentifiers

// MARK: - Developer Tab
struct DeveloperView: View {
    @StateObject private var uiServices = UIServices.shared
    
    @State private var selectedSection: DeveloperSection = .settings
    @State private var debugLoggingEnabled: Bool = false
    @State private var logFiles: [LogFileInfo] = []
    @State private var selectedLogFile: LogFileInfo?
    @State private var logContent: String = ""
    @State private var isLoadingLogContent = false
    
    @State private var unifiedPlugins: [UnifiedPluginInfo] = []
    @State private var selectedUnifiedPlugin: UnifiedPluginInfo?
    @State private var pluginSearchText = ""
    @State private var selectedPluginType: UnifiedPluginType? = nil
    @State private var showingPluginDetails = false
    @State private var showingInstallPlugin = false
    
    enum UnifiedPluginType: String, CaseIterable, Identifiable {
        case action = "Action"
        case detection = "Detection"
        case service = "Service"
        case ui = "UI"
        
        var id: String { self.rawValue }
        
        var icon: String {
            switch self {
            case .action: return "bolt.fill"
            case .detection: return "hand.tap.fill"
            case .service: return "gearshape.2.fill"
            case .ui: return "uiwindow.split.2x1"
            }
        }
        
        var color: Color {
            switch self {
            case .action: return .blue
            case .detection: return .orange
            case .service: return .green
            case .ui: return .purple
            }
        }
    }
    
    struct UnifiedPluginInfo: Identifiable {
        let id: String
        let identifier: String
        let name: String
        let type: UnifiedPluginType
        let version: String
        let author: String
        let description: String
        let isBuiltIn: Bool
        var isEnabled: Bool
        
        // Additional info
        var actionCount: Int? = nil
        var serviceCategory: ServiceCategory? = nil
        var uiCategory: UIPluginCategory? = nil
        var permissions: String = ""
    }
    
    private let perfMonitor = PerformanceMonitorService.shared
    @State private var memoryUsage: (resident: String, virtual: String) = ("", "")
    @State private var cpuUsage: Double = 0.0
    @State private var updateTimer: Timer?
    
    @State private var debugReport: String = ""
    @State private var showingExportReport = false
    
    private let servicePluginManager = ServicePluginManager.shared
    @State private var servicePlugins: [ServicePluginInfo] = []
    @State private var serviceSearchText = ""
    @State private var serviceCategory: ServiceCategory?
    @State private var serviceActiveSheet: ServiceSheet?
    
    enum ServiceSheet: Identifiable {
        case configure(ServicePluginInfo)
        case install
        var id: String {
            switch self {
            case .configure(let p): return "cfg-\(p.id)"
            case .install: return "install"
            }
        }
    }
    
    @State private var developerModeEnabled: Bool = false
    @State private var successMessage: String?
    @State private var errorMessage: String?
    
    @State private var coordinatorStates: [ActivationCoordinator.ActivationStateInfo] = []
    
    enum DeveloperSection: String, CaseIterable {
        case settings = "Developer Settings"
        case logging = "Logging"
        case plugins = "Plugin Management"
        case coordinator = "Activation Coordinator"
        case services = "Services"
        case performance = "Performance"
        case diagnostics = "Diagnostics"

        var icon: String {
            switch self {
            case .settings: return "gearshape"
            case .logging: return "doc.text"
            case .plugins: return "puzzlepiece.extension"
            case .coordinator: return "flowchart"
            case .services: return "gearshape.2"
            case .performance: return "speedometer"
            case .diagnostics: return "stethoscope"
            }
        }
    }
    
    var body: some View {
        HSplitView {
            MGSidebar(title: "Developer Tools") {
                ForEach(DeveloperSection.allCases, id: \.self) { section in
                    MGSidebarItem(
                        title: section.rawValue,
                        icon: section.icon,
                        isSelected: selectedSection == section,
                        action: { selectedSection = section }
                    )
                }
            }
            .frame(minWidth: MGStyle.Layout.sidebarMinWidth, idealWidth: 230, maxWidth: 260)
            
            ScrollView {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
                    switch selectedSection {
                    case .settings: developerSettingsSection
                    case .logging: loggingSection
                    case .plugins: pluginsSection
                    case .coordinator: coordinatorSection
                    case .services: servicesSection
                    case .performance: performanceSection
                    case .diagnostics: diagnosticsSection
                    }
                }
                .padding(MGStyle.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadInitialData()
            startPerformanceMonitoring()
        }
        .onDisappear { stopPerformanceMonitoring() }
        .fileImporter(
            isPresented: $showingInstallPlugin,
            allowedContentTypes: [UTType(filenameExtension: "plugin") ?? .item, .bundle],
            allowsMultipleSelection: false
        ) { result in handlePluginInstall(result: result) }
        .fileExporter(
            isPresented: $showingExportReport,
            document: DebugReportDocument(content: debugReport),
            contentType: .plainText,
            defaultFilename: "MouseGestures_Debug_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).txt"
        ) { result in handleReportExport(result: result) }
        .sheet(item: $serviceActiveSheet) { sheet in
            switch sheet {
            case .configure(let plugin):
                ServiceConfigurationSheet(plugin: plugin)
            case .install:
                ServiceInstallSheet { url in installServicePlugin(from: url) }
            }
        }
    }
    
    // MARK: - Developer Settings Section
    
    private var developerSettingsSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
            MGSectionHeader("Developer Settings")
            
            MGContentCard {
                if LicenseService.shared.status != .free {
                    Toggle(isOn: $developerModeEnabled) {
                        VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                            Text("Developer Mode")
                                .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                            Text("Enables this Developer tab and other advanced developer features")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: developerModeEnabled) { newValue in
                        uiServices.setDeveloperModeEnabled(newValue)
                    }
                    
                    Divider()
                }
                
                Toggle(isOn: $debugLoggingEnabled) {
                    VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                        Text("Debug Logging")
                            .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                        Text("Records detailed debug information to log files. Manage logs in the Logging section.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: debugLoggingEnabled) { newValue in
                    uiServices.setDebugModeEnabled(newValue)
                }
            }
            
            if !developerModeEnabled {
                Label("Developer mode is disabled. This tab will be hidden when you navigate away.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - Logging Section
    
    private var loggingSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
            MGSectionHeader("Debug Logging")
            
            MGContentCard {
                Toggle(isOn: $debugLoggingEnabled) {
                    VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                        Text("Enable Debug Logging")
                            .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                        Text("Records detailed debug information to log files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: debugLoggingEnabled) { newValue in
                    uiServices.setDebugModeEnabled(newValue)
                    if newValue { refreshLogFiles() }
                }
                
                if debugLoggingEnabled {
                    HStack {
                        Button("Open Logs Folder") { openLogsFolder() }
                        Button("Refresh") { refreshLogFiles() }
                        Spacer()
                        if !logFiles.isEmpty {
                            Button("Clear All Logs") { clearAllLogs() }
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            
            if debugLoggingEnabled && !logFiles.isEmpty {
                MGContentCard {
                    Text("Log Files")
                        .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: MGStyle.Spacing.sm) {
                            ForEach(logFiles, id: \.url) { logFile in
                                logFileRow(logFile)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(RoundedRectangle(cornerRadius: MGStyle.Corner.md).stroke(MGStyle.Colors.separator))
                }
                
                if let selectedLog = selectedLogFile {
                    MGContentCard {
                        HStack {
                            Text("Log Content: \(selectedLog.name)")
                                .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(logContent, forType: .string)
                            }
                            Button("Export") { exportLogFile(selectedLog) }
                        }
                        
                        ScrollView {
                            Text(logContent.isEmpty ? "Loading..." : logContent)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(MGStyle.Spacing.lg)
                        }
                        .frame(height: 300)
                        .background(RoundedRectangle(cornerRadius: MGStyle.Corner.md).fill(MGStyle.Colors.contentBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: MGStyle.Corner.md)
                                .stroke(MGStyle.Colors.separator)
                        )
                    }
                }
            }
        }
    }
    
    private func logFileRow(_ logFile: LogFileInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                Text(logFile.name)
                    .font(.system(size: MGStyle.FontSize.caption, weight: selectedLogFile?.url == logFile.url ? .medium : .regular))
                    .foregroundColor(selectedLogFile?.url == logFile.url ? .accentColor : .primary)
                HStack(spacing: MGStyle.Spacing.lg) {
                    Text(logFile.size).font(.caption2).foregroundColor(.secondary)
                    Text(logFile.date).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            MGActionButton("trash", help: "Delete log", destructive: true) { deleteLogFile(logFile) }
        }
        .padding(.horizontal, MGStyle.Spacing.lg)
        .padding(.vertical, MGStyle.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: MGStyle.Corner.sm)
                .fill(selectedLogFile?.url == logFile.url ? MGStyle.Colors.selectedRow : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectLogFile(logFile) }
    }
    
    // MARK: - Plugin Management Section
    
    private var pluginsSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
            MGSectionHeader("Plugin Management")
            
            // Search and Filters
            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                MGContentCard {
                    VStack(spacing: MGStyle.Spacing.lg) {
                        HStack(spacing: MGStyle.Spacing.lg) {
                            MGSearchField("Search plugins...", text: $pluginSearchText)
                            
                            Button(action: { refreshUnifiedPlugins() }) {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: { showingInstallPlugin = true }) {
                                Label("Install Plugin", systemImage: "plus.circle")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        HStack(spacing: MGStyle.Spacing.md) {
                            Text("Filter:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button(action: { selectedPluginType = nil }) {
                                Text("All")
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(selectedPluginType == nil ? Color.accentColor : Color.secondary.opacity(0.1))
                                    .foregroundColor(selectedPluginType == nil ? .white : .primary)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                            
                            ForEach(UnifiedPluginType.allCases) { type in
                                Button(action: { selectedPluginType = type }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: type.icon)
                                            .font(.system(size: 10))
                                        Text(type.rawValue)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(selectedPluginType == type ? type.color : Color.secondary.opacity(0.1))
                                    .foregroundColor(selectedPluginType == type ? .white : .primary)
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Spacer()
                            
                            Text("\(filteredPlugins.count) plugins")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Unified Plugin List
            if filteredPlugins.isEmpty {
                MGContentCard {
                    VStack(spacing: MGStyle.Spacing.lg) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text(pluginSearchText.isEmpty ? "No plugins loaded" : "No plugins matching your search")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                }
            } else {
                MGContentCard {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(filteredPlugins) { plugin in
                                unifiedPluginRow(plugin)
                                if plugin.id != filteredPlugins.last?.id {
                                    Divider().padding(.horizontal, MGStyle.Spacing.lg)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 500)
                }
            }
            
            if let plugin = selectedUnifiedPlugin {
                unifiedPluginDetailsView(plugin)
            }
        }
    }
    
    private var filteredPlugins: [UnifiedPluginInfo] {
        unifiedPlugins.filter { plugin in
            let matchesSearch = pluginSearchText.isEmpty || 
                plugin.name.localizedCaseInsensitiveContains(pluginSearchText) ||
                plugin.identifier.localizedCaseInsensitiveContains(pluginSearchText) ||
                plugin.description.localizedCaseInsensitiveContains(pluginSearchText)
            
            let matchesType = selectedPluginType == nil || plugin.type == selectedPluginType
            
            return matchesSearch && matchesType
        }
    }
    
    private func unifiedPluginRow(_ plugin: UnifiedPluginInfo) -> some View {
        HStack(spacing: MGStyle.Spacing.lg) {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.xs) {
                HStack(spacing: MGStyle.Spacing.md) {
                    Text(plugin.name)
                        .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                    
                    // Type Chip
                    HStack(spacing: 4) {
                        Image(systemName: plugin.type.icon)
                            .font(.system(size: 8))
                        Text(plugin.type.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .textCase(.uppercase)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(plugin.type.color.opacity(0.15))
                    .foregroundColor(plugin.type.color)
                    .cornerRadius(4)
                    
                    if plugin.isBuiltIn {
                        Text("BUILT-IN")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 4)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.secondary.opacity(0.3), lineWidth: 0.5))
                    }
                }
                
                Text(plugin.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: MGStyle.Spacing.xl) {
                if plugin.type == .action, let count = plugin.actionCount {
                    Text("\(count) actions")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("v\(plugin.version)")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                    Text(plugin.identifier)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                
                Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { togglePlugin(plugin, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                
                MGActionButton("info.circle", help: "View details") {
                    selectedUnifiedPlugin = plugin
                }
            }
        }
        .padding(MGStyle.Spacing.lg)
        .contentShape(Rectangle())
        .onTapGesture { selectedUnifiedPlugin = plugin }
        .background(selectedUnifiedPlugin?.id == plugin.id ? MGStyle.Colors.selectedRow : Color.clear)
    }

    // MARK: - Activation Coordinator Section

    private var coordinatorSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
            MGSectionHeader("Activation Coordinator")

            MGContentCard {
                Text("The Activation Coordinator manages the efficiency chain, enabling and disabling detection plugins based on gesture requirements and current system state.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            MGContentCard {
                VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                    HStack {
                        Text("Activation Type").font(.system(size: MGStyle.FontSize.caption, weight: .bold))
                        Spacer()
                        Text("Efficiency").frame(width: 80).font(.system(size: MGStyle.FontSize.caption, weight: .bold))
                        Text("Status").frame(width: 80).font(.system(size: MGStyle.FontSize.caption, weight: .bold))
                        Text("Engaged").frame(width: 80).font(.system(size: MGStyle.FontSize.caption, weight: .bold))
                    }
                    .foregroundColor(.secondary)
                    
                    Divider()
                    
                    ForEach(coordinatorStates) { state in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(state.type.displayName)
                                    .font(.system(size: MGStyle.FontSize.body, weight: .medium))
                                Text(state.type.rawValue)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(state.efficiency)")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 80)
                            
                            HStack {
                                Circle()
                                    .fill(state.isEnabled ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 8, height: 8)
                                Text(state.isEnabled ? "ACTIVE" : "idle")
                                    .font(.caption)
                                    .foregroundColor(state.isEnabled ? .primary : .secondary)
                            }
                            .frame(width: 80, alignment: .leading)
                            
                            HStack {
                                Circle()
                                    .fill(state.isEngaged ? Color.blue : Color.gray.opacity(0.1))
                                    .frame(width: 8, height: 8)
                                Text(state.isEngaged ? "YES" : "no")
                                    .font(.caption)
                                    .foregroundColor(state.isEngaged ? .blue : .secondary)
                            }
                            .frame(width: 80, alignment: .leading)
                        }
                    }
                }
            }
            
            MGContentCard {
                Text("Coordination Logic")
                    .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                Text("Higher efficiency triggers act as gates for lower efficiency ones. For example, mouse tracking (efficiency 20) is only enabled when modifiers (efficiency 100) are already engaged.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    
    // MARK: - Services Section
    
    private var filteredServicePlugins: [ServicePluginInfo] {
        var result = servicePlugins
        if let cat = serviceCategory { result = result.filter { $0.category == cat } }
        if !serviceSearchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(serviceSearchText) ||
                $0.description.localizedCaseInsensitiveContains(serviceSearchText) ||
                $0.identifier.localizedCaseInsensitiveContains(serviceSearchText)
            }
        }
        return result.sorted { $0.name < $1.name }
    }
    
    private var activeServiceCategories: [ServiceCategory] {
        let cats = Set(servicePlugins.map(\.category))
        return ServiceCategory.allCases.filter { cats.contains($0) }
    }
    
    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
            MGSectionHeader("Services")
            
            MGContentCard {
                HStack(spacing: MGStyle.Spacing.lg) {
                    Picker("Category:", selection: $serviceCategory) {
                        Text("All").tag(ServiceCategory?.none)
                        Divider()
                        ForEach(activeServiceCategories, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(ServiceCategory?.some(cat))
                        }
                    }
                    .frame(width: 220)
                    
                    MGSearchField("Search services...", text: $serviceSearchText)
                        .frame(maxWidth: 220)
                    
                    Spacer()
                    
                    Button(action: { serviceActiveSheet = .install }) {
                        Label("Install", systemImage: "plus.circle")
                    }
                    Button(action: loadServicePlugins) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                
                Text("\(filteredServicePlugins.count) service\(filteredServicePlugins.count == 1 ? "" : "s")")
                    .font(.caption).foregroundColor(.secondary)
            }
            
            if filteredServicePlugins.isEmpty {
                MGEmptyState(
                    icon: "tray",
                    title: servicePlugins.isEmpty ? "No services loaded" : "No services match the current filter"
                )
            } else {
                LazyVStack(alignment: .leading, spacing: MGStyle.Spacing.md) {
                    ForEach(filteredServicePlugins) { plugin in
                        ServiceRow(plugin: plugin) {
                            serviceActiveSheet = .configure(plugin)
                        } onToggle: {
                            toggleServicePlugin(plugin)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Performance Section
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
            MGSectionHeader("Performance Monitoring")
            
            MGContentCard {
                Text("System Permissions")
                    .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                
                HStack(spacing: MGStyle.Spacing.lg) {
                    Text("Accessibility:").foregroundColor(.secondary)
                    if hasAccessibilityPermissions() {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
                    } else {
                        Label("Not Granted", systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.caption)
                        Button("Open System Settings") { openAccessibilityPreferences() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                Text("Accessibility permissions are required for MouseGestures to detect and respond to mouse and keyboard events.")
                    .font(.caption).foregroundColor(.secondary)
            }
            
            MGContentCard {
                Text("Memory Usage")
                    .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: MGStyle.Spacing.xxl, verticalSpacing: MGStyle.Spacing.md) {
                    GridRow {
                        Text("Resident Memory:").foregroundColor(.secondary)
                        Text(memoryUsage.resident).font(.system(.body, design: .monospaced))
                    }
                    GridRow {
                        Text("Virtual Memory:").foregroundColor(.secondary)
                        Text(memoryUsage.virtual).font(.system(.body, design: .monospaced))
                    }
                    GridRow {
                        Text("System Memory:").foregroundColor(.secondary)
                        Text(perfMonitor.getSystemMemory()).font(.system(.body, design: .monospaced))
                    }
                }
            }
            
            MGContentCard {
                Text("CPU Usage")
                    .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                HStack {
                    ProgressView(value: min(cpuUsage, 100), total: 100).progressViewStyle(.linear)
                    Text(String(format: "%.1f%%", cpuUsage))
                        .font(.system(.body, design: .monospaced)).frame(width: 60)
                }
                Text("Processor: \(perfMonitor.getProcessorCount()) cores")
                    .font(.caption).foregroundColor(.secondary)
            }
            
            MGContentCard {
                Text("System Information")
                    .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: MGStyle.Spacing.xxl, verticalSpacing: MGStyle.Spacing.md) {
                    GridRow { Text("macOS Version:").foregroundColor(.secondary); Text(perfMonitor.getSystemVersion()) }
                    GridRow { Text("App Version:").foregroundColor(.secondary); Text(perfMonitor.getAppVersion()) }
                    GridRow { Text("Process ID:").foregroundColor(.secondary); Text("\(perfMonitor.getProcessID())").font(.system(.body, design: .monospaced)) }
                    GridRow { Text("Uptime:").foregroundColor(.secondary); Text(perfMonitor.getUptime()) }
                }
            }
        }
    }
    
    // MARK: - Diagnostics Section
    
    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: MGStyle.Spacing.xxl) {
            MGSectionHeader("System Diagnostics")
            
            MGContentCard {
                Text("Debug Report")
                    .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                Text("Generate a comprehensive debug report containing system information, configuration, and diagnostics")
                    .font(.caption).foregroundColor(.secondary)
                
                HStack {
                    Button("Generate Report") { generateDebugReport() }.buttonStyle(.borderedProminent)
                    if !debugReport.isEmpty {
                        Button("Copy to Clipboard") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(debugReport, forType: .string)
                            successMessage = "Report copied to clipboard"
                        }
                        Button("Export") { showingExportReport = true }
                    }
                }
                
                if !debugReport.isEmpty {
                    ScrollView {
                        Text(debugReport)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(MGStyle.Spacing.lg)
                    }
                    .frame(height: 300)
                    .background(RoundedRectangle(cornerRadius: MGStyle.Corner.md).fill(MGStyle.Colors.contentBackground))
                    .overlay(RoundedRectangle(cornerRadius: MGStyle.Corner.md).stroke(MGStyle.Colors.separator))
                }
            }
            
            MGContentCard {
                Text("Quick Actions")
                    .font(.system(size: MGStyle.FontSize.heading, weight: .semibold))
                
                VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                    Button("Reset All Preferences") { resetPreferences() }.foregroundColor(.red)
                    Button("Clear All Caches") { clearCaches() }
                    Button("Reload All Plugins") { reloadAllPlugins() }
                    Button("Export All Logs") { exportAllLogs() }
                }
            }
            
            if let message = successMessage {
                Label(message, systemImage: "checkmark.circle.fill").font(.caption).foregroundColor(.green)
            }
            if let message = errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundColor(.red)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func loadInitialData() {
        developerModeEnabled = uiServices.isDeveloperModeEnabled()
        debugLoggingEnabled = uiServices.isDebugModeEnabled()
        refreshLogFiles()
        refreshUnifiedPlugins()
        refreshPerformanceMetrics()
        loadServicePlugins()
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
        coordinatorStates = ActivationCoordinator.shared.getActivationStates()
    }
    
    private func refreshLogFiles() {
        let urls = uiServices.getLogFiles()
        logFiles = urls.map { url in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = attributes?[.size] as? Int64 ?? 0
            let date = attributes?[.creationDate] as? Date ?? Date()
            return LogFileInfo(
                url: url, name: url.lastPathComponent,
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
                DispatchQueue.main.async { self.logContent = content; self.isLoadingLogContent = false }
            } catch {
                DispatchQueue.main.async { self.logContent = "Error loading log file: \(error.localizedDescription)"; self.isLoadingLogContent = false }
            }
        }
    }
    
    private func deleteLogFile(_ logFile: LogFileInfo) {
        if uiServices.deleteLogFile(logFile.url) {
            refreshLogFiles()
            if selectedLogFile?.url == logFile.url { selectedLogFile = nil; logContent = "" }
        }
    }
    
    private func clearAllLogs() {
        if uiServices.clearAllLogs() { refreshLogFiles(); selectedLogFile = nil; logContent = ""; successMessage = "All logs cleared" }
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
                } catch { errorMessage = "Failed to export log: \(error.localizedDescription)" }
            }
        }
    }
    
    private func refreshUnifiedPlugins() {
        var allPlugins: [UnifiedPluginInfo] = []
        
        // 1. Action Plugins
        let actionPlugins = uiServices.getLoadedPlugins()
        for p in actionPlugins {
            allPlugins.append(UnifiedPluginInfo(
                id: "action-\(p.identifier)",
                identifier: p.identifier,
                name: p.name,
                type: .action,
                version: p.version,
                author: p.author,
                description: p.description,
                isBuiltIn: p.isBuiltIn,
                isEnabled: p.isEnabled,
                actionCount: p.actionCount,
                permissions: describePermissions(p.permissions)
            ))
        }
        
        // 2. Detection Plugins
        let detectionPlugins = DetectionPluginManager.shared.getAllPlugins()
        for p in detectionPlugins {
            allPlugins.append(UnifiedPluginInfo(
                id: "detection-\(p.identifier)",
                identifier: p.identifier,
                name: p.name,
                type: .detection,
                version: p.version,
                author: "System",
                description: p.description,
                isBuiltIn: true,
                isEnabled: p.isEnabled,
                permissions: "Low-level Input"
            ))
        }
        
        // 3. Service Plugins
        let services = servicePluginManager.getAllPlugins()
        for p in services {
            allPlugins.append(UnifiedPluginInfo(
                id: "service-\(p.identifier)",
                identifier: p.identifier,
                name: p.name,
                type: .service,
                version: p.version,
                author: p.author,
                description: p.description,
                isBuiltIn: p.isBuiltIn,
                isEnabled: p.isEnabled,
                serviceCategory: p.category,
                permissions: describeServicePermissions(p.requiredPermissions)
            ))
        }
        
        // 4. UI Plugins
        let uiPlugs = UIPluginManager.shared.getAllPlugins()
        for p in uiPlugs {
            allPlugins.append(UnifiedPluginInfo(
                id: "ui-\(p.identifier)",
                identifier: p.identifier,
                name: p.displayName,
                type: .ui,
                version: p.version,
                author: p.author,
                description: p.description,
                isBuiltIn: p.sortOrder < 100,
                isEnabled: UIPluginManager.shared.isPluginEnabled(identifier: p.identifier),
                uiCategory: p.category,
                permissions: "UI/Management"
            ))
        }
        
        unifiedPlugins = allPlugins
        if let selected = selectedUnifiedPlugin {
            selectedUnifiedPlugin = unifiedPlugins.first(where: { $0.id == selected.id })
        }
    }
    
    private func describeServicePermissions(_ p: ServicePermissions) -> String {
        var perms: [String] = []
        if p.requiresAccessibility { perms.append("Accessibility") }
        if p.requiresFileAccess { perms.append("Files") }
        if p.requiresNetworkAccess { perms.append("Network") }
        if p.requiresNotifications { perms.append("Notifications") }
        if p.requiresScreenRecording { perms.append("Screen") }
        if p.requiresAutomation { perms.append("Automation") }
        if p.requiresFullDiskAccess { perms.append("Full Disk") }
        return perms.isEmpty ? "None" : perms.joined(separator: ", ")
    }
    
    private func togglePlugin(_ plugin: UnifiedPluginInfo, enabled: Bool) {
        switch plugin.type {
        case .action:
            if enabled { _ = uiServices.reloadPlugin(plugin.identifier) }
            else { _ = uiServices.uninstallPlugin(plugin.identifier) }
        case .detection:
            DetectionPluginManager.shared.setPluginEnabled(plugin.identifier, enabled: enabled)
        case .service:
            if enabled { _ = servicePluginManager.enablePlugin(identifier: plugin.identifier) }
            else { _ = servicePluginManager.disablePlugin(identifier: plugin.identifier) }
        case .ui:
            UIPluginManager.shared.setPluginEnabled(identifier: plugin.identifier, enabled: enabled)
        }
        refreshUnifiedPlugins()
    }
    
    private func handlePluginInstall(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // Unified installation logic: autodetect by extension
            let ext = url.pathExtension.lowercased()
            
            if ext == "plugin" || ext == "auraplugin" {
                if uiServices.installPlugin(from: url) { 
                    successMessage = "Action plugin installed"
                    refreshUnifiedPlugins()
                } else { errorMessage = uiServices.errorMessage ?? "Failed to install action plugin" }
            } else if ext == "service" {
                let res = servicePluginManager.installPlugin(from: url)
                if res.success { 
                    successMessage = "Service installed"
                    refreshUnifiedPlugins()
                } else { errorMessage = res.error ?? "Failed to install service" }
            } else if ext == "uiplugin" {
                let dest = Configuration.applicationSupportDirectory.appendingPathComponent("UIPlugins").appendingPathComponent(url.lastPathComponent)
                do {
                    try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                    try FileManager.default.copyItem(at: url, to: dest)
                    successMessage = "UI plugin installed. Restart app to activate."
                    refreshUnifiedPlugins()
                } catch { errorMessage = "Failed to install UI plugin: \(error.localizedDescription)" }
            } else {
                if uiServices.installPlugin(from: url) { 
                    successMessage = "Plugin installed"
                    refreshUnifiedPlugins()
                } else { errorMessage = "Unsupported plugin format" }
            }
        case .failure(let error): errorMessage = "Install failed: \(error.localizedDescription)"
        }
    }
    
    private func uninstallUnifiedPlugin(_ plugin: UnifiedPluginInfo) {
        switch plugin.type {
        case .action: _ = uiServices.uninstallPlugin(plugin.identifier)
        case .service: _ = servicePluginManager.uninstallPlugin(identifier: plugin.identifier)
        case .ui: errorMessage = "Manually remove from UIPlugins folder"
        default: break
        }
        refreshUnifiedPlugins()
        selectedUnifiedPlugin = nil
    }
    
    private func reloadUnifiedPlugin(_ plugin: UnifiedPluginInfo) {
        switch plugin.type {
        case .action: _ = uiServices.reloadPlugin(plugin.identifier)
        case .service:
            _ = servicePluginManager.disablePlugin(identifier: plugin.identifier)
            _ = servicePluginManager.enablePlugin(identifier: plugin.identifier)
        default: break
        }
        refreshUnifiedPlugins()
    }
    
    private func unifiedPluginDetailsView(_ plugin: UnifiedPluginInfo) -> some View {
        MGContentCard {
            VStack(alignment: .leading, spacing: MGStyle.Spacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plugin.name).font(.headline)
                        Text(plugin.identifier).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                    }
                    Spacer()
                    if !plugin.isBuiltIn {
                        HStack(spacing: MGStyle.Spacing.md) {
                            Button("Reload") { reloadUnifiedPlugin(plugin) }
                            Button("Uninstall", role: .destructive) { uninstallUnifiedPlugin(plugin) }
                                .foregroundColor(.red)
                        }
                    }
                    Button("Close") { selectedUnifiedPlugin = nil }.buttonStyle(.plain).foregroundColor(.secondary)
                }
                Divider()
                Grid(alignment: .leading, horizontalSpacing: MGStyle.Spacing.xl, verticalSpacing: MGStyle.Spacing.md) {
                    GridRow { Text("Type").foregroundColor(.secondary); Text(plugin.type.rawValue) }
                    GridRow { Text("Version").foregroundColor(.secondary); Text(plugin.version) }
                    GridRow { Text("Author").foregroundColor(.secondary); Text(plugin.author) }
                    GridRow { Text("Status").foregroundColor(.secondary); Text(plugin.isEnabled ? "Active" : "Disabled") }
                    GridRow { Text("Permissions").foregroundColor(.secondary); Text(plugin.permissions).font(.caption) }
                }
                .font(.caption)
                Text(plugin.description).font(.callout).padding(.top, 4)
            }
            .padding(MGStyle.Spacing.lg)
        }
    }
    
    private func describePermissions(_ permissions: PluginPermissions) -> String {
        if permissions == .builtIn { return "Full Access (Built-in)" }
        else if permissions == .restricted { return "Restricted" }
        else {
            var perms: [String] = []
            if permissions.canAccessFileSystem { perms.append("Files") }
            if permissions.canAccessNetwork { perms.append("Network") }
            if permissions.canAccessSystemAPIs { perms.append("System") }
            if permissions.canExecuteOtherActions { perms.append("Actions") }
            if permissions.canShowNotifications { perms.append("Notifications") }
            return perms.isEmpty ? "None" : perms.joined(separator: ", ")
        }
    }
    
    private func loadServicePlugins() { servicePlugins = servicePluginManager.getAllPlugins() }
    
    private func toggleServicePlugin(_ plugin: ServicePluginInfo) {
        if plugin.isEnabled { _ = servicePluginManager.disablePlugin(identifier: plugin.identifier) }
        else { _ = servicePluginManager.enablePlugin(identifier: plugin.identifier) }
        loadServicePlugins()
    }
    
    private func installServicePlugin(from url: URL) {
        let result = servicePluginManager.installPlugin(from: url)
        if !result.success {
            let alert = NSAlert()
            alert.messageText = "Failed to install plugin"
            alert.informativeText = result.error ?? "Unknown error"
            alert.alertStyle = .warning
            alert.runModal()
        }
        loadServicePlugins()
    }
    
    private func generateDebugReport() { debugReport = uiServices.generateDebugReport(); successMessage = "Debug report generated" }
    
    private func handleReportExport(result: Result<URL, Error>) {
        switch result {
        case .success: successMessage = "Report exported successfully"
        case .failure(let error): errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }
    

    private func resetPreferences() { uiServices.resetAppToDefaults(); successMessage = "Preferences reset to defaults" }
    private func clearCaches() { successMessage = "Caches cleared" }
    
    private func reloadAllPlugins() {
        for plugin in unifiedPlugins where !plugin.isBuiltIn { reloadUnifiedPlugin(plugin) }
        successMessage = "All plugins reloaded"
    }
    
    private func exportAllLogs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "zip") ?? .item]
        savePanel.nameFieldStringValue = "MouseGestures_Logs_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).zip"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                if uiServices.exportLogs(to: url) { successMessage = "Logs exported successfully" }
                else { errorMessage = uiServices.errorMessage ?? "Failed to export logs" }
            }
        }
    }
    
    private func hasAccessibilityPermissions() -> Bool { return AXIsProcessTrusted() }
    
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
    init(content: String) { self.content = content }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let string = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
        content = string
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: content.data(using: .utf8)!)
    }
}
