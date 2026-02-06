import Foundation
import AppKit

// MARK: - Accessibility Permission Service Plugin
class AccessibilityPermissionServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.accessibility" }
    override var name: String { "Accessibility Permission Service" }
    override var description: String { "Manages accessibility permissions required for mouse gesture detection" }
    override var category: ServiceCategory { .accessibility }
    override var requiredPermissions: ServicePermissions { .accessibility }
    
    private var service: AccessibilityPermissionService?
    
    override func initialize() throws {
        service = AccessibilityPermissionService.shared
        log.log("AccessibilityPermissionServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("AccessibilityPermissionServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
    
    override func validateEnvironment() -> ServiceValidationResult {
        // Check if we're running on macOS
        #if !os(macOS)
        return .failure("This service requires macOS")
        #endif
        
        // Check if accessibility permissions are available
        if !AXIsProcessTrusted() {
            return .warning("Accessibility permissions not granted. Some features may not work.")
        }
        
        return .success
    }
}

// MARK: - Launch at Login Service Plugin
class LaunchAtLoginServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.launchatlogin" }
    override var name: String { "Launch at Login Service" }
    override var description: String { "Manages automatic app launch at system login" }
    override var category: ServiceCategory { .system }
    
    private var service: LaunchAtLoginService?
    
    override func initialize() throws {
        service = LaunchAtLoginService.shared
        log.log("LaunchAtLoginServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("LaunchAtLoginServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - Haptic Feedback Service Plugin
class HapticFeedbackServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.haptic" }
    override var name: String { "Haptic Feedback Service" }
    override var description: String { "Provides haptic feedback for gesture interactions" }
    override var category: ServiceCategory { .ui }
    
    private var service: HapticFeedbackService?
    
    override func initialize() throws {
        service = HapticFeedbackService.shared
        log.log("HapticFeedbackServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("HapticFeedbackServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
    
    override func validateEnvironment() -> ServiceValidationResult {
        // Check if device supports haptic feedback
        if !NSHapticFeedbackManager.defaultPerformer.isKind(of: NSHapticFeedbackManager.self) {
            return .warning("Haptic feedback may not be available on this device")
        }
        return .success
    }
}

// MARK: - Menu Bar Visibility Service Plugin
class MenuBarVisibilityServicePlugin: BaseServicePlugin {
    override var identifier: String { "com.mousegestures.service.menubar" }
    override var name: String { "Menu Bar Visibility Service" }
    override var description: String { "Controls the visibility of the menu bar icon" }
    override var category: ServiceCategory { .ui }
    
    private var service: MenuBarVisibilityService?
    
    override func initialize() throws {
        service = MenuBarVisibilityService.shared
        log.log("MenuBarVisibilityServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service = nil
        log.log("MenuBarVisibilityServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
}

// MARK: - Zone Visualization Service Plugin
class ZoneVisualizationServicePlugin: BaseServicePlugin {
    // Store custom visualization preferences
    private var customColors: [String: String] = [:]
    private var animationDuration: Double = 0.2
    private var fadeOutDelay: Double = 1.0
    
    override var identifier: String { "com.mousegestures.service.zonevisualization" }
    override var name: String { "Zone Visualization Service" }
    override var description: String { "Provides visual feedback for screen zones and gesture areas" }
    override var category: ServiceCategory { .ui }
    override var requiredPermissions: ServicePermissions { 
        ServicePermissions(requiresScreenRecording: true)
    }
    
    private var service: ZoneVisualizationService?
    
    override func initialize() throws {
        service = ZoneVisualizationService.shared
        
        // Load any custom configuration stored for this plugin
        if let savedConfig = loadConfiguration() {
            // Load custom colors if saved
            if let colors = savedConfig["customColors"] as? [String: String] {
                customColors = colors
                log.log("ZoneVisualizationServicePlugin: Loaded \(colors.count) custom colors")
            }
            
            // Load animation settings
            if let duration = savedConfig["animationDuration"] as? Double {
                animationDuration = duration
            }
            
            if let delay = savedConfig["fadeOutDelay"] as? Double {
                fadeOutDelay = delay
            }
            
            // Apply loaded configuration to the service
            applyConfiguration(savedConfig)
        }
        
        log.log("ZoneVisualizationServicePlugin: Initialized")
    }
    
    override func cleanup() {
        service?.hideAllHighlights()
        service = nil
        log.log("ZoneVisualizationServicePlugin: Cleaned up")
    }
    
    override func getServiceInstance() -> Any? {
        return service
    }
    
    override func getConfigurationOptions() -> [ServiceConfigOption] {
        return [
            ServiceConfigOption(
                key: "showHighlights",
                label: "Show Zone Highlights",
                type: .boolean,
                defaultValue: true,
                description: "Display visual highlights when hovering over zones"
            ),
            ServiceConfigOption(
                key: "showLabels",
                label: "Show Zone Labels",
                type: .boolean,
                defaultValue: false,
                description: "Display text labels on zone highlights"
            ),
            ServiceConfigOption(
                key: "edgeThreshold",
                label: "Edge Threshold",
                type: .double(min: 10, max: 100),
                defaultValue: 40.0,
                description: "Pixel distance from edge to activate zones"
            ),
            ServiceConfigOption(
                key: "cornerSize",
                label: "Corner Size",
                type: .double(min: 50, max: 200),
                defaultValue: 100.0,
                description: "Size of corner zones in pixels"
            ),
            ServiceConfigOption(
                key: "animationDuration",
                label: "Animation Duration",
                type: .double(min: 0.1, max: 1.0),
                defaultValue: 0.2,
                description: "Duration of zone highlight animations in seconds"
            ),
            ServiceConfigOption(
                key: "fadeOutDelay",
                label: "Fade Out Delay",
                type: .double(min: 0.5, max: 5.0),
                defaultValue: 1.0,
                description: "Delay before zone highlights fade out"
            )
        ]
    }
    
    override func applyConfiguration(_ config: [String: Any]) {
        guard let service = service else { return }
        
        // Apply basic settings to the service
        if let showHighlights = config["showHighlights"] as? Bool {
            service.setShowZoneHighlights(showHighlights)
        }
        
        if let showLabels = config["showLabels"] as? Bool {
            service.setShowZoneLabels(showLabels)
        }
        
        if let edgeThreshold = config["edgeThreshold"] as? CGFloat {
            service.setEdgeThreshold(edgeThreshold)
        }
        
        if let cornerSize = config["cornerSize"] as? CGFloat {
            service.setCornerSize(cornerSize)
        }
        
        // Store custom configuration values
        if let duration = config["animationDuration"] as? Double {
            animationDuration = duration
        }
        
        if let delay = config["fadeOutDelay"] as? Double {
            fadeOutDelay = delay
        }
        
        if let colors = config["customColors"] as? [String: String] {
            customColors = colors
        }
        
        // Save the configuration persistently
        saveConfiguration(config)
    }
    
    /// Example method showing how to set a custom zone color
    func setZoneColor(for zone: String, color: String) {
        customColors[zone] = color
        
        // Save the updated configuration
        var config = loadConfiguration() ?? [:]
        config["customColors"] = customColors
        saveConfiguration(config)
        
        log.log("ZoneVisualizationServicePlugin: Set color \(color) for zone \(zone)")
    }
    
    /// Example method to get custom settings
    func getAnimationSettings() -> (duration: Double, fadeOutDelay: Double) {
        return (animationDuration, fadeOutDelay)
    }
}
