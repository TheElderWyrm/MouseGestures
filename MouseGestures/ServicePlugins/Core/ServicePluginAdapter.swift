import Foundation

// MARK: - Service Plugin Adapter
/// Provides compatibility layer for transitioning from direct service access to plugin-based access
public class ServicePluginAdapter {
    
    private let pluginManager = ServicePluginManager.shared
    
    // Service cache to maintain singletons
    private var serviceCache: [String: Any] = [:]
    
    // MARK: - Service Getters with Fallback
    
    func getGestureConfigurationService() -> GestureConfigurationService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.gestureconfig", type: GestureConfigurationService.self) {
            return service
        }
        // Fallback to direct access if plugin not loaded
        return GestureConfigurationService.shared
    }
    
    func getProfileManagementService() -> ProfileManagementService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.profilemanagement", type: ProfileManagementService.self) {
            return service
        }
        return ProfileManagementService.shared
    }
    
    func getProfileImportExportService() -> ProfileImportExportService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.profileimportexport", type: ProfileImportExportService.self) {
            return service
        }
        return ProfileImportExportService.shared
    }
    
    func getHapticFeedbackService() -> HapticFeedbackService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.haptic", type: HapticFeedbackService.self) {
            return service
        }
        return HapticFeedbackService.shared
    }
    
    func getZoneVisualizationService() -> ZoneVisualizationService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.zonevisualization", type: ZoneVisualizationService.self) {
            return service
        }
        return ZoneVisualizationService.shared
    }
    
    func getDeveloperModeToggleService() -> DeveloperModeToggleService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.devmode", type: DeveloperModeToggleService.self) {
            return service
        }
        return DeveloperModeToggleService.shared
    }
    
    func getDebugLoggingService() -> DebugLoggingService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.debuglogging", type: DebugLoggingService.self) {
            return service
        }
        return DebugLoggingService.shared
    }
    
    func getSettingsImportExportService() -> SettingsImportExportService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.settingsimportexport", type: SettingsImportExportService.self) {
            return service
        }
        return SettingsImportExportService.shared
    }
    
    func getApplicationResetService() -> ApplicationResetService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.appreset", type: ApplicationResetService.self) {
            return service
        }
        return ApplicationResetService.shared
    }
    
    func getUpdateCheckService() -> UpdateCheckService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.updatecheck", type: UpdateCheckService.self) {
            return service
        }
        return UpdateCheckService.shared
    }
    
    func getAccessibilityPermissionService() -> AccessibilityPermissionService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.accessibility", type: AccessibilityPermissionService.self) {
            return service
        }
        return AccessibilityPermissionService.shared
    }
    
    func getMenuBarVisibilityService() -> MenuBarVisibilityService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.menubar", type: MenuBarVisibilityService.self) {
            return service
        }
        return MenuBarVisibilityService.shared
    }
    
    func getLogFileService() -> LogFileService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.logfile", type: LogFileService.self) {
            return service
        }
        return LogFileService.shared
    }
    
    func getPluginManagementService() -> PluginManagementService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.pluginmanagement", type: PluginManagementService.self) {
            return service
        }
        return PluginManagementService.shared
    }
    
    func getPerformanceMonitorService() -> PerformanceMonitorService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.perfmonitor", type: PerformanceMonitorService.self) {
            return service
        }
        return PerformanceMonitorService.shared
    }
    
    func getDebugReportService() -> DebugReportService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.debugreport", type: DebugReportService.self) {
            return service
        }
        return DebugReportService.shared
    }
    
    func getGestureSearchService() -> GestureSearchService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.gesturesearch", type: GestureSearchService.self) {
            return service
        }
        return GestureSearchService.shared
    }
    
    func getSavedActionsSortService() -> SavedActionsSortService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.savedactionssort", type: SavedActionsSortService.self) {
            return service
        }
        return SavedActionsSortService.shared
    }
    
    func getSystemInformationService() -> SystemInformationService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.systeminfo", type: SystemInformationService.self) {
            return service
        }
        return SystemInformationService.shared
    }
    
    func getApplicationDiscoveryService() -> ApplicationDiscoveryService {
        if let service = pluginManager.getService(identifier: "com.mousegestures.service.appdiscovery", type: ApplicationDiscoveryService.self) {
            return service
        }
        return ApplicationDiscoveryService.shared
    }
}
