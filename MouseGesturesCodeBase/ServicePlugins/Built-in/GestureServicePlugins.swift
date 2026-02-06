import Foundation
import SwiftUI

// MARK: - Gesture Configuration Service Plugin
class GestureConfigurationServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.gestureconfig" }
    override var name: String { "Gesture Configuration Service" }
    override var description: String { "Manages gesture creation, modification, and validation" }
    override var category: ServiceCategory { .gesture }
    
    private var service: GestureConfigurationService?
    
    override func initialize() throws {
        service = GestureConfigurationService.shared
        log.log("GestureConfigurationServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("GestureConfigurationServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - Profile Management Service Plugin
class ProfileManagementServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.profilemanagement" }
    override var name: String { "Profile Management Service" }
    override var description: String { "Manages configuration profiles and profile switching" }
    override var category: ServiceCategory { .profile }
    
    private var service: ProfileManagementService?
    
    override func initialize() throws {
        service = ProfileManagementService.shared
        log.log("ProfileManagementServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("ProfileManagementServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - Profile Import Export Service Plugin
class ProfileImportExportServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.profileimportexport" }
    override var name: String { "Profile Import/Export Service" }
    override var description: String { "Handles importing and exporting of configuration profiles" }
    override var category: ServiceCategory { .importExport }
    override var requiredPermissions: ServicePermissions { .basic }
    
    private var service: ProfileImportExportService?
    
    override func initialize() throws {
        service = ProfileImportExportService.shared
        log.log("ProfileImportExportServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("ProfileImportExportServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - Gesture Search Service Plugin
class GestureSearchServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.gesturesearch" }
    override var name: String { "Gesture Search Service" }
    override var description: String { "Provides search and filtering capabilities for gestures" }
    override var category: ServiceCategory { .gesture }
    
    private var service: GestureSearchService?
    
    override func initialize() throws {
        service = GestureSearchService.shared
        log.log("GestureSearchServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("GestureSearchServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - Saved Actions Sort Service Plugin
class SavedActionsSortServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.savedactionssort" }
    override var name: String { "Saved Actions Sort Service" }
    override var description: String { "Manages sorting and filtering of saved actions" }
    override var category: ServiceCategory { .data }
    
    private var service: SavedActionsSortService?
    
    override func initialize() throws {
        service = SavedActionsSortService.shared
        log.log("SavedActionsSortServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("SavedActionsSortServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}
