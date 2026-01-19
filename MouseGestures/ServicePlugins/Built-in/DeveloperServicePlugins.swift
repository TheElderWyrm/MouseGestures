import Foundation

// MARK: - Debug Logging Service Plugin
class DebugLoggingServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.debuglogging" }
    override var name: String { "Debug Logging Service" }
    override var description: String { "Manages debug logging and log level configuration" }
    override var category: ServiceCategory { .developer }
    
    private var service: DebugLoggingService?
    
    override func initialize() throws {
        service = DebugLoggingService.shared
        log.log("DebugLoggingServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("DebugLoggingServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
    
    override func getConfigurationOptions() -> [ServiceConfigOption] {
        return [
            ServiceConfigOption(
                key: "enabled",
                label: "Enable Debug Logging",
                type: .boolean,
                defaultValue: false,
                description: "Enable detailed debug logging"
            ),
            ServiceConfigOption(
                key: "logLevel",
                label: "Log Level",
                type: .selection(options: ["Verbose", "Debug", "Info", "Warning", "Error"]),
                defaultValue: "Info",
                description: "Minimum log level to record"
            ),
            ServiceConfigOption(
                key: "maxLogSize",
                label: "Max Log Size (MB)",
                type: .integer(min: 1, max: 100),
                defaultValue: 10,
                description: "Maximum size of log files before rotation"
            )
        ]
    }
}

// MARK: - Log File Service Plugin
class LogFileServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.logfile" }
    override var name: String { "Log File Service" }
    override var description: String { "Manages log file creation, rotation, and export" }
    override var category: ServiceCategory { .developer }
    override var requiredPermissions: ServicePermissions { .basic }
    
    private var service: LogFileService?
    
    override func initialize() throws {
        service = LogFileService.shared
        log.log("LogFileServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("LogFileServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - Update Check Service Plugin
class UpdateCheckServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.updatecheck" }
    override var name: String { "Update Check Service" }
    override var description: String { "Checks for application updates" }
    override var category: ServiceCategory { .system }
    override var requiredPermissions: ServicePermissions { 
        ServicePermissions(requiresNetworkAccess: true)
    }
    
    private var service: UpdateCheckService?
    
    override func initialize() throws {
        service = UpdateCheckService.shared
        log.log("UpdateCheckServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("UpdateCheckServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
    
    override func getConfigurationOptions() -> [ServiceConfigOption] {
        return [
            ServiceConfigOption(
                key: "autoCheck",
                label: "Automatic Update Check",
                type: .boolean,
                defaultValue: true,
                description: "Automatically check for updates on launch"
            ),
            ServiceConfigOption(
                key: "checkInterval",
                label: "Check Interval (days)",
                type: .integer(min: 1, max: 30),
                defaultValue: 7,
                description: "Days between automatic update checks"
            )
        ]
    }
}

// MARK: - Application Reset Service Plugin
class ApplicationResetServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.appreset" }
    override var name: String { "Application Reset Service" }
    override var description: String { "Resets application to default settings" }
    override var category: ServiceCategory { .utility }
    
    private var service: ApplicationResetService?
    
    override func initialize() throws {
        service = ApplicationResetService.shared
        log.log("ApplicationResetServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("ApplicationResetServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - Settings Import Export Service Plugin
class SettingsImportExportServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.settingsimportexport" }
    override var name: String { "Settings Import/Export Service" }
    override var description: String { "Handles importing and exporting application settings" }
    override var category: ServiceCategory { .importExport }
    override var requiredPermissions: ServicePermissions { .basic }
    
    private var service: SettingsImportExportService?
    
    override func initialize() throws {
        service = SettingsImportExportService.shared
        log.log("SettingsImportExportServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("SettingsImportExportServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - System Information Service Plugin
class SystemInformationServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.systeminfo" }
    override var name: String { "System Information Service" }
    override var description: String { "Provides system metrics and performance data" }
    override var category: ServiceCategory { .monitoring }
    
    private var service: SystemInformationService?
    
    override func initialize() throws {
        service = SystemInformationService.shared
        log.log("SystemInformationServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("SystemInformationServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - Performance Monitor Service Plugin
class PerformanceMonitorServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.perfmonitor" }
    override var name: String { "Performance Monitor Service" }
    override var description: String { "Monitors application performance metrics" }
    override var category: ServiceCategory { .monitoring }
    
    private var service: PerformanceMonitorService?
    
    override func initialize() throws {
        service = PerformanceMonitorService.shared
        log.log("PerformanceMonitorServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service?.stopMonitoring()
        service = nil
        log.log("PerformanceMonitorServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
    
    override func getConfigurationOptions() -> [ServiceConfigOption] {
        return [
            ServiceConfigOption(
                key: "enabled",
                label: "Enable Performance Monitoring",
                type: .boolean,
                defaultValue: false,
                description: "Track performance metrics"
            ),
            ServiceConfigOption(
                key: "sampleInterval",
                label: "Sample Interval (seconds)",
                type: .integer(min: 1, max: 60),
                defaultValue: 5,
                description: "Seconds between performance samples"
            )
        ]
    }
}

// MARK: - Application Discovery Service Plugin
class ApplicationDiscoveryServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.appdiscovery" }
    override var name: String { "Application Discovery Service" }
    override var description: String { "Discovers and catalogs installed applications" }
    override var category: ServiceCategory { .system }
    override var requiredPermissions: ServicePermissions { .basic }
    
    private var service: ApplicationDiscoveryService?
    
    override func initialize() throws {
        service = ApplicationDiscoveryService.shared
        log.log("ApplicationDiscoveryServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("ApplicationDiscoveryServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - Debug Report Service Plugin
class DebugReportServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.debugreport" }
    override var name: String { "Debug Report Service" }
    override var description: String { "Generates comprehensive debug reports" }
    override var category: ServiceCategory { .developer }
    
    private var service: DebugReportService?
    
    override func initialize() throws {
        service = DebugReportService.shared
        log.log("DebugReportServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("DebugReportServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - Developer Mode Toggle Service Plugin
class DeveloperModeToggleServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.devmode" }
    override var name: String { "Developer Mode Service" }
    override var description: String { "Enables developer features and debugging tools" }
    override var category: ServiceCategory { .developer }
    
    private var service: DeveloperModeToggleService?
    
    override func initialize() throws {
        service = DeveloperModeToggleService.shared
        log.log("DeveloperModeToggleServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("DeveloperModeToggleServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - Plugin Management Service Plugin
class PluginManagementServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.pluginmanagement" }
    override var name: String { "Plugin Management Service" }
    override var description: String { "Manages action and detection plugins" }
    override var category: ServiceCategory { .plugin }
    
    private var service: PluginManagementService?
    
    override func initialize() throws {
        service = PluginManagementService.shared
        log.log("PluginManagementServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("PluginManagementServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - Window Targeting Service Plugin
class WindowTargetingServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.windowtargeting" }
    override var name: String { "Window Targeting Service" }
    override var description: String { "Identifies and targets specific windows for actions" }
    override var category: ServiceCategory { .automation }
    override var requiredPermissions: ServicePermissions { .accessibility }
    
    private var service: WindowTargeting?
    
    override func initialize() throws {
        service = WindowTargeting.shared
        log.log("WindowTargetingServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("WindowTargetingServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}
