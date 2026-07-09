import Foundation

// MARK: - Simple Developer Service Plugins
// Simple singleton wrappers — created via SimpleServicePlugin<T> in ServicePluginManager.
enum DeveloperServicePluginFactory {
    static func logFile() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.logfile",
                           name: "Log File Service",
                           description: "Manages log file creation, rotation, and export",
                           category: .developer, permissions: .basic,
                           factory: { LogFileService.shared })
    }

    static func applicationReset() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.appreset",
                           name: "Application Reset Service",
                           description: "Resets application to default settings",
                           category: .utility,
                           factory: { ApplicationResetService.shared })
    }

    static func settingsImportExport() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.settingsimportexport",
                           name: "Settings Import/Export Service",
                           description: "Handles importing and exporting application settings",
                           category: .importExport, permissions: .basic,
                           factory: { SettingsImportExportService.shared })
    }

    static func systemInformation() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.systeminfo",
                           name: "System Information Service",
                           description: "Provides system metrics and performance data",
                           category: .monitoring,
                           factory: { SystemInformationService.shared })
    }

    static func applicationDiscovery() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.appdiscovery",
                           name: "Application Discovery Service",
                           description: "Discovers and catalogs installed applications",
                           category: .system, permissions: .basic,
                           factory: { ApplicationDiscoveryService.shared })
    }

    static func debugReport() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.debugreport",
                           name: "Debug Report Service",
                           description: "Generates comprehensive debug reports",
                           category: .developer,
                           factory: { DebugReportService.shared })
    }

    static func developerModeToggle() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.devmode",
                           name: "Developer Mode Service",
                           description: "Enables developer features and debugging tools",
                           category: .developer,
                           factory: { DeveloperModeToggleService.shared })
    }

    static func pluginManagement() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.pluginmanagement",
                           name: "Plugin Management Service",
                           description: "Manages action and detection plugins",
                           category: .plugin,
                           factory: { PluginManagementService.shared })
    }

    static func windowTargeting() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.windowtargeting",
                           name: "Window Targeting Service",
                           description: "Identifies and targets specific windows for actions",
                           category: .automation, permissions: .accessibility,
                           factory: { WindowTargeting.shared })
    }
}

// MARK: - Debug Logging Service Plugin (has custom configuration options)
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

    override func getServiceInstance() -> Any? { return service }

    override func getConfigurationOptions() -> [ServiceConfigOption] {
        [
            ServiceConfigOption(key: "enabled", label: "Enable Debug Logging", type: .boolean,
                              defaultValue: false, description: "Enable detailed debug logging"),
            ServiceConfigOption(key: "logLevel", label: "Log Level",
                              type: .selection(options: ["Verbose", "Debug", "Info", "Warning", "Error"]),
                              defaultValue: "Info", description: "Minimum log level to record"),
            ServiceConfigOption(key: "maxLogSize", label: "Max Log Size (MB)",
                              type: .integer(min: 1, max: 100),
                              defaultValue: 10, description: "Maximum size of log files before rotation")
        ]
    }
}

// MARK: - Performance Monitor Service Plugin (has custom cleanup + configuration)
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

    override func getServiceInstance() -> Any? { return service }

    override func getConfigurationOptions() -> [ServiceConfigOption] {
        [
            ServiceConfigOption(key: "enabled", label: "Enable Performance Monitoring", type: .boolean,
                              defaultValue: false, description: "Track performance metrics"),
            ServiceConfigOption(key: "sampleInterval", label: "Sample Interval (seconds)",
                              type: .integer(min: 1, max: 60),
                              defaultValue: 5, description: "Seconds between performance samples")
        ]
    }
}
