import Foundation

// MARK: - Service Plugin Adapter
/// Provides compatibility layer for transitioning from direct service access to plugin-based access.
/// Uses a single generic method instead of per-service boilerplate.
public class ServicePluginAdapter {
    
    private let pluginManager = ServicePluginManager.shared
    
    // MARK: - Generic Service Lookup
    
    /// Retrieve a service by plugin identifier, falling back to a default instance.
    func getService<T>(identifier: String, fallback: @autoclosure () -> T) -> T {
        return pluginManager.getService(identifier: identifier, type: T.self) ?? fallback()
    }
    
    // MARK: - Typed Accessors (thin wrappers over generic lookup)
    
    func getGestureConfigurationService() -> GestureConfigurationService {
        getService(identifier: "com.mousegestures.service.gestureconfig", fallback: GestureConfigurationService.shared)
    }
    
    func getProfileManagementService() -> ProfileManagementService {
        getService(identifier: "com.mousegestures.service.profilemanagement", fallback: ProfileManagementService.shared)
    }
    
    func getProfileImportExportService() -> ProfileImportExportService {
        getService(identifier: "com.mousegestures.service.profileimportexport", fallback: ProfileImportExportService.shared)
    }
    
    func getHapticFeedbackService() -> HapticFeedbackService {
        getService(identifier: "com.mousegestures.service.haptic", fallback: HapticFeedbackService.shared)
    }
    
    func getZoneVisualizationService() -> ZoneVisualizationService {
        getService(identifier: "com.mousegestures.service.zonevisualization", fallback: ZoneVisualizationService.shared)
    }
    
    func getDeveloperModeToggleService() -> DeveloperModeToggleService {
        getService(identifier: "com.mousegestures.service.devmode", fallback: DeveloperModeToggleService.shared)
    }
    
    func getDebugLoggingService() -> DebugLoggingService {
        getService(identifier: "com.mousegestures.service.debuglogging", fallback: DebugLoggingService.shared)
    }
    
    func getSettingsImportExportService() -> SettingsImportExportService {
        getService(identifier: "com.mousegestures.service.settingsimportexport", fallback: SettingsImportExportService.shared)
    }
    
    func getApplicationResetService() -> ApplicationResetService {
        getService(identifier: "com.mousegestures.service.appreset", fallback: ApplicationResetService.shared)
    }
    
    func getAccessibilityPermissionService() -> AccessibilityPermissionService {
        getService(identifier: "com.mousegestures.service.accessibility", fallback: AccessibilityPermissionService.shared)
    }
    
    func getMenuBarVisibilityService() -> MenuBarVisibilityService {
        getService(identifier: "com.mousegestures.service.menubar", fallback: MenuBarVisibilityService.shared)
    }
    
    func getLogFileService() -> LogFileService {
        getService(identifier: "com.mousegestures.service.logfile", fallback: LogFileService.shared)
    }
    
    func getPluginManagementService() -> PluginManagementService {
        getService(identifier: "com.mousegestures.service.pluginmanagement", fallback: PluginManagementService.shared)
    }
    
    func getPerformanceMonitorService() -> PerformanceMonitorService {
        getService(identifier: "com.mousegestures.service.perfmonitor", fallback: PerformanceMonitorService.shared)
    }
    
    func getDebugReportService() -> DebugReportService {
        getService(identifier: "com.mousegestures.service.debugreport", fallback: DebugReportService.shared)
    }
    
    func getGestureSearchService() -> GestureSearchService {
        getService(identifier: "com.mousegestures.service.gesturesearch", fallback: GestureSearchService.shared)
    }
    
    func getSavedActionsSortService() -> SavedActionsSortService {
        getService(identifier: "com.mousegestures.service.savedactionssort", fallback: SavedActionsSortService.shared)
    }
    
    func getSystemInformationService() -> SystemInformationService {
        getService(identifier: "com.mousegestures.service.systeminfo", fallback: SystemInformationService.shared)
    }
    
    func getApplicationDiscoveryService() -> ApplicationDiscoveryService {
        getService(identifier: "com.mousegestures.service.appdiscovery", fallback: ApplicationDiscoveryService.shared)
    }
}
