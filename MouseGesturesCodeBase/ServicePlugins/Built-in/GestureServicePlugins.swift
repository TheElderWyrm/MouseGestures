import Foundation
import SwiftUI

// MARK: - Simple Gesture Service Plugins
// These are all simple singleton wrappers — created via SimpleServicePlugin<T> in ServicePluginManager.
// No custom logic needed, so no class definitions here.

// Factory functions to create simple service plugins for gesture-related services
enum GestureServicePluginFactory {
    static func gestureConfiguration() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.gestureconfig",
                           name: "Gesture Configuration Service",
                           description: "Manages gesture creation, modification, and validation",
                           category: .gesture,
                           factory: { GestureConfigurationService.shared })
    }
    
    static func profileManagement() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.profilemanagement",
                           name: "Profile Management Service",
                           description: "Manages configuration profiles and profile switching",
                           category: .profile,
                           factory: { ProfileManagementService.shared })
    }
    
    static func profileImportExport() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.profileimportexport",
                           name: "Profile Import/Export Service",
                           description: "Handles importing and exporting of configuration profiles",
                           category: .importExport,
                           permissions: .basic,
                           factory: { ProfileImportExportService.shared })
    }
    
    static func gestureSearch() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.gesturesearch",
                           name: "Gesture Search Service",
                           description: "Provides search and filtering capabilities for gestures",
                           category: .gesture,
                           factory: { GestureSearchService.shared })
    }
    
    static func savedActionsSort() -> ServicePlugin {
        SimpleServicePlugin(id: "com.mousegestures.service.savedactionssort",
                           name: "Saved Actions Sort Service",
                           description: "Manages sorting and filtering of saved actions",
                           category: .data,
                           factory: { SavedActionsSortService.shared })
    }
}
