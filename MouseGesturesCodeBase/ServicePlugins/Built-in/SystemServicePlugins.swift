import Foundation
import AppKit
import SwiftUI

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
        #if !os(macOS)
        return .failure("This service requires macOS")
        #endif
        
        if !AXIsProcessTrusted() {
            return .warning("Accessibility permissions not granted. Some features may not work.")
        }
        
        return .success
    }
}

// MARK: - Launch at Login Service Plugin

class LaunchAtLoginServicePlugin: BaseServicePlugin, SettingsItemContributor {
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
    
    // MARK: - Settings Contribution
    
    var settingsContributions: [SettingsContribution] {
        [SettingsContribution(
            targetCategoryId: "general",
            order: 10,
            searchableItems: [
                SearchableSettingItem(
                    title: "Launch at Login",
                    description: "Automatically start MouseGestures when you log in",
                    keywords: ["launch", "login", "startup", "boot", "autostart", "automatic"]
                )
            ],
            viewBuilder: { AnyView(LaunchAtLoginSettingView()) }
        )]
    }
}

/// Setting view provided by LaunchAtLoginServicePlugin
private struct LaunchAtLoginSettingView: View {
    @State private var launchAtLogin = false
    
    var body: some View {
        settingsToggle(
            isOn: $launchAtLogin,
            title: "Launch at Login",
            description: "Automatically start MouseGestures when you log in"
        ) { UIServices.shared.setLaunchAtLoginEnabled($0) }
        .onAppear { launchAtLogin = UIServices.shared.isLaunchAtLoginEnabled() }
    }
}

// MARK: - Haptic Feedback Service Plugin

class HapticFeedbackServicePlugin: BaseServicePlugin, SettingsItemContributor {
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
        if !NSHapticFeedbackManager.defaultPerformer.isKind(of: NSHapticFeedbackManager.self) {
            return .warning("Haptic feedback may not be available on this device")
        }
        return .success
    }
    
    // MARK: - Settings Contribution
    
    var settingsContributions: [SettingsContribution] {
        [SettingsContribution(
            targetCategoryId: "general",
            order: 20,
            searchableItems: [
                SearchableSettingItem(
                    title: "Haptic Feedback",
                    description: "Provide haptic feedback when gestures are recognized",
                    keywords: ["haptic", "feedback", "vibration", "force touch", "trackpad", "tactile"]
                )
            ],
            viewBuilder: { AnyView(HapticFeedbackSettingView()) }
        )]
    }
}

/// Setting view provided by HapticFeedbackServicePlugin
private struct HapticFeedbackSettingView: View {
    @State private var hapticFeedback = true
    
    var body: some View {
        settingsToggle(
            isOn: $hapticFeedback,
            title: "Haptic Feedback",
            description: "Provide haptic feedback when gestures are recognized (MacBooks with Force Touch)"
        ) { UIServices.shared.setHapticFeedbackEnabled($0) }
        .onAppear { hapticFeedback = UIServices.shared.isHapticFeedbackEnabled() }
    }
}

// MARK: - Menu Bar Visibility Service Plugin

class MenuBarVisibilityServicePlugin: BaseServicePlugin, SettingsItemContributor {
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
    
    // MARK: - Settings Contribution
    
    var settingsContributions: [SettingsContribution] {
        [SettingsContribution(
            targetCategoryId: "general",
            order: 30,
            searchableItems: [
                SearchableSettingItem(
                    title: "Show Menu Bar Icon",
                    description: "Display MouseGestures icon in the menu bar for quick access",
                    keywords: ["menu", "bar", "icon", "tray", "status", "menubar"]
                )
            ],
            viewBuilder: { AnyView(MenuBarSettingView()) }
        )]
    }
}

/// Setting view provided by MenuBarVisibilityServicePlugin
private struct MenuBarSettingView: View {
    @State private var hideMenuBarIcon = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                UIServices.shared.setMenuBarIconHidden(newValue)
            }
            
            if hideMenuBarIcon {
                Label("You can still access settings through the dock icon", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.leading, 20)
            }
        }
        .onAppear { hideMenuBarIcon = UIServices.shared.isMenuBarIconHidden() }
    }
}

// MARK: - Zone Visualization Service Plugin

class ZoneVisualizationServicePlugin: BaseServicePlugin {
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
        
        if let savedConfig = loadConfiguration() {
            if let colors = savedConfig["customColors"] as? [String: String] {
                customColors = colors
                log.log("ZoneVisualizationServicePlugin: Loaded \(colors.count) custom colors")
            }
            if let duration = savedConfig["animationDuration"] as? Double {
                animationDuration = duration
            }
            if let delay = savedConfig["fadeOutDelay"] as? Double {
                fadeOutDelay = delay
            }
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
        if let duration = config["animationDuration"] as? Double {
            animationDuration = duration
        }
        if let delay = config["fadeOutDelay"] as? Double {
            fadeOutDelay = delay
        }
        if let colors = config["customColors"] as? [String: String] {
            customColors = colors
        }
        
        saveConfiguration(config)
    }
    
    func setZoneColor(for zone: String, color: String) {
        customColors[zone] = color
        var config = loadConfiguration() ?? [:]
        config["customColors"] = customColors
        saveConfiguration(config)
        log.log("ZoneVisualizationServicePlugin: Set color \(color) for zone \(zone)")
    }
    
    func getAnimationSettings() -> (duration: Double, fadeOutDelay: Double) {
        return (animationDuration, fadeOutDelay)
    }
}
