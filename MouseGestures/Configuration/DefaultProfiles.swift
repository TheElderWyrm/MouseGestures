import Foundation

// DefaultProfiles.swift - Pre-configured profiles for common use cases
struct DefaultProfiles {
    
    // Window Management Profile - Focused on window control actions
    static func createWindowManagementProfile() -> ConfigurationProfile {
        let gestures = [
            // Window sizing
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.maximize"),
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.close_window"),
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.fullscreen"),
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.minimize"),
            
            // Window positioning
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.left_half"),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.right_half"),
            Gesture(zone: .topLeft, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.top_left"),
            Gesture(zone: .topRight, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.top_right"),
            Gesture(zone: .bottomLeft, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.bottom_left"),
            Gesture(zone: .bottomRight, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.bottom_right"),
            
            // Spaces
            Gesture(zone: .left, modifiers: [.command, .shift], actionIdentifier: "com.mousegestures.core.previous_space"),
            Gesture(zone: .right, modifiers: [.command, .shift], actionIdentifier: "com.mousegestures.core.next_space"),
            
            // Window cycling
            Gesture(zone: .bottom, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.previous_window"),
            Gesture(zone: .top, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.next_window")
        ]
        
        return ConfigurationProfile(
            name: "Window Management",
            gestures: gestures,
            hapticFeedbackEnabled: true,
            edgeThreshold: 30,
            cornerSize: 100,
            cornerBuffer: 50,
            isDefault: false
        )
    }
    
    // Media Control Profile - Focused on media playback
    static func createMediaControlProfile() -> ConfigurationProfile {
        let gestures = [
            // Playback controls
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.play_pause"),
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.previous_track"),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.next_track"),
            
            // Volume controls
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.volume_up"),
            Gesture(zone: .bottom, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.media.volume_down"),
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.mute"),
            
            // Brightness controls
            Gesture(zone: .top, modifiers: [.control, .option], actionIdentifier: "com.mousegestures.system.brightness_up"),
            Gesture(zone: .bottom, modifiers: [.control, .option], actionIdentifier: "com.mousegestures.system.brightness_down"),
            
            // Screenshot
            Gesture(zone: .topLeft, modifiers: [.command, .shift], actionIdentifier: "com.mousegestures.system.screenshot_full"),
            Gesture(zone: .topRight, modifiers: [.command, .shift], actionIdentifier: "com.mousegestures.system.screenshot_selection")
        ]
        
        return ConfigurationProfile(
            name: "Media Control",
            gestures: gestures,
            hapticFeedbackEnabled: true,
            edgeThreshold: 30,
            cornerSize: 100,
            cornerBuffer: 50,
            isDefault: false
        )
    }
    
    // System Navigation Profile - Focused on macOS navigation
    static func createSystemNavigationProfile() -> ConfigurationProfile {
        let gestures = [
            // Mission Control & Spaces
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.mission_control"),
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.show_desktop"),
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.previous_space"),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.next_space"),
            
            // Expose & App Windows
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.app_expose"),
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.app_expose"),
            
            // Launchpad & Spotlight
            Gesture(zone: .bottomLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.mission_control"),
            Gesture(zone: .bottomRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.automation.search_finder"),
            
            // Notification Center & Control Center
            Gesture(zone: .topLeft, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.show_desktop"),
            Gesture(zone: .topRight, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.mission_control"),
            
            // App Cycling
            Gesture(zone: .bottom, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.previous_window"),
            Gesture(zone: .top, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.next_window")
        ]
        
        return ConfigurationProfile(
            name: "System Navigation",
            gestures: gestures,
            hapticFeedbackEnabled: true,
            edgeThreshold: 30,
            cornerSize: 100,
            cornerBuffer: 50,
            isDefault: false
        )
    }
    
    // Productivity Profile - Focused on productivity shortcuts
    static func createProductivityProfile() -> ConfigurationProfile {
        let gestures = [
            // Window management essentials
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.close_window"),
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.fullscreen"),
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.minimize"),
            
            // Quick app switching
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.previous_window"),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.next_window"),
            
            // System controls
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.automation.search_finder"),
            Gesture(zone: .bottomLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.hide_app"),
            Gesture(zone: .bottomRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.show_desktop"),
            
            // Do Not Disturb & Dark Mode toggles
            Gesture(zone: .topLeft, modifiers: [.control, .option], actionIdentifier: "com.mousegestures.system.toggle_do_not_disturb"),
            Gesture(zone: .topRight, modifiers: [.control, .option], actionIdentifier: "com.mousegestures.system.toggle_dark_mode"),
            
            // Lock screen for security
            Gesture(zone: .bottom, modifiers: [.command, .option, .control], actionIdentifier: "com.mousegestures.core.lock_screen")
        ]
        
        return ConfigurationProfile(
            name: "Productivity",
            gestures: gestures,
            hapticFeedbackEnabled: true,
            edgeThreshold: 30,
            cornerSize: 100,
            cornerBuffer: 50,
            isDefault: false
        )
    }
    
    // Minimal Profile - Basic essential gestures only
    static func createMinimalProfile() -> ConfigurationProfile {
        let gestures = [
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.quit_app"),
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.close_window"),
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.fullscreen"),
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.minimize"),
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.previous_space"),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.next_space")
        ]
        
        return ConfigurationProfile(
            name: "Minimal",
            gestures: gestures,
            hapticFeedbackEnabled: false,
            edgeThreshold: 30,
            cornerSize: 100,
            cornerBuffer: 50,
            isDefault: false
        )
    }
    
    // Developer Profile - Focused on development workflows
    static func createDeveloperProfile() -> ConfigurationProfile {
        let gestures = [
            // Window management
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.left_half"),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.right_half"),
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.maximize"),
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.close_window"),
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.quit_app"),
            
            // Quick app switching (Terminal, IDE, Browser)
            Gesture(zone: .bottomLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.previous_window"),
            Gesture(zone: .bottomRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.next_window"),
            
            // Spaces for different projects
            Gesture(zone: .left, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.previous_space"),
            Gesture(zone: .right, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.next_space"),
            
            // Mission Control for overview
            Gesture(zone: .top, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.mission_control"),
            Gesture(zone: .bottom, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.app_expose"),
            
            // Screenshot for documentation
            Gesture(zone: .topLeft, modifiers: [.command, .shift], actionIdentifier: "com.mousegestures.system.screenshot_selection"),
            
            // Hide distractions
            Gesture(zone: .bottomLeft, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.show_desktop")
        ]
        
        return ConfigurationProfile(
            name: "Developer",
            gestures: gestures,
            hapticFeedbackEnabled: true,
            edgeThreshold: 25,
            cornerSize: 80,
            cornerBuffer: 40,
            isDefault: false
        )
    }
    
    // Get all default profiles
    static func getAllDefaultProfiles() -> [ConfigurationProfile] {
        return [
            createWindowManagementProfile(),
            createMediaControlProfile(),
            createSystemNavigationProfile(),
            createProductivityProfile(),
            createMinimalProfile(),
            createDeveloperProfile()
        ]
    }

    /// Gets a specific default profile by type
    static func getProfile(for type: DefaultProfileType) -> ConfigurationProfile? {
        switch type {
        case .windowManagement:
            return createWindowManagementProfile()
        case .mediaControl:
            return createMediaControlProfile()
        case .systemNavigation:
            return createSystemNavigationProfile()
        case .productivity:
            return createProductivityProfile()
        case .minimal:
            return createMinimalProfile()
        case .developer:
            return createDeveloperProfile()
        }
    }
    
    // Export default profiles to a file for distribution
    static func exportDefaultProfilesToFile() -> Data? {
        let profiles = getAllDefaultProfiles()
        let exportData = ProfileBundleExportData(profiles: profiles)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(exportData)
        } catch {
            log.log("Error encoding default profiles: \(error)")
            return nil
        }
    }
}
extension Configuration {
    static var defaultGestures: [Gesture] {
        return DefaultProfiles.createWindowManagementProfile().gestures
    }
}
