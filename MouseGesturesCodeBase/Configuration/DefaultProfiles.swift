import Foundation

// DefaultProfiles.swift - Pre-configured profiles for common use cases
//
// NOTE: All gestures in default profiles use the new GenericActivation system.
// The Gesture convenience initializer automatically creates GenericActivation
// internally, so no explicit migration is needed. These zone-based gestures
// don't require keyboard or mouse button triggers.
//
// The gestures below create GenericActivation with empty detectionConfigs
// since they only use zone + modifiers (no additional detection plugins).
//
// EXAMPLE: If you wanted to add keyboard/mouse triggers:
// let gesture = Gesture(
//     zone: .topRight,
//     modifiers: [.command],
//     actionIdentifier: "com.mousegestures.window.close_window",
//     keyboardTrigger: KeyboardTrigger(keyCode: 17, modifiers: [.command], displayString: "⌘T"),
//     mouseButtonTrigger: MouseButtonTrigger(button: .middle, modifiers: [])
// )
// This automatically creates GenericActivation and stores triggers in detectionConfigs.
struct DefaultProfiles {
    
    // Window Management Profile - Focused on window control actions
    static func createWindowManagementProfile() -> ConfigurationProfile {
        let gestures = [
            // Window sizing
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.maximize"),
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.close_window"),
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.fullscreen"),
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.minimize"),
            
            // Window positioning
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("left_half")]),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("right_half")]),
            Gesture(zone: .topLeft, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("top_left")]),
            Gesture(zone: .topRight, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("top_right")]),
            Gesture(zone: .bottomLeft, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("bottom_left")]),
            Gesture(zone: .bottomRight, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("bottom_right")]),
            
            // Spaces
            Gesture(zone: .left, modifiers: [.command, .shift], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("previous")]),
            Gesture(zone: .right, modifiers: [.command, .shift], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("next")]),
            
            // Window cycling
            Gesture(zone: .bottom, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("backward")]),
            Gesture(zone: .top, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("forward")])
        ]
        
        return ConfigurationProfile(
            name: "Window Management",
            gestures: gestures,
            isDefault: false
        )
    }
    
    // Media Control Profile - Focused on media playback
    static func createMediaControlProfile() -> ConfigurationProfile {
        let gestures = [
            // Playback controls
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.play_pause"),
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.track_skip", parameters: ["direction": AnyCodable("previous")]),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.track_skip", parameters: ["direction": AnyCodable("next")]),
            
            // Volume controls
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.volume", parameters: ["mode": AnyCodable("up")]),
            Gesture(zone: .bottom, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.media.volume", parameters: ["mode": AnyCodable("down")]),
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.volume", parameters: ["mode": AnyCodable("mute")]),
            
            // Brightness controls
            Gesture(zone: .top, modifiers: [.control, .option], actionIdentifier: "com.mousegestures.system.display_brightness", parameters: ["direction": AnyCodable("up")]),
            Gesture(zone: .bottom, modifiers: [.control, .option], actionIdentifier: "com.mousegestures.system.display_brightness", parameters: ["direction": AnyCodable("down")]),
            
            // Screenshot
            Gesture(zone: .topLeft, modifiers: [.command, .shift], actionIdentifier: "com.mousegestures.system.screenshot", parameters: ["type": AnyCodable("full")]),
            Gesture(zone: .topRight, modifiers: [.command, .shift], actionIdentifier: "com.mousegestures.system.screenshot", parameters: ["type": AnyCodable("selection")])
        ]
        
        return ConfigurationProfile(
            name: "Media Control",
            gestures: gestures,
            isDefault: false
        )
    }
    
    // System Navigation Profile - Focused on macOS navigation
    static func createSystemNavigationProfile() -> ConfigurationProfile {
        let gestures = [
            // Mission Control & Spaces
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.mission_control"),
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.show_desktop"),
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("previous")]),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("next")]),
            
            // Expose & App Windows
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.app_expose"),
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.app_expose"),
            
            // Launchpad & Spotlight
            Gesture(zone: .bottomLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.mission_control"),
            Gesture(zone: .bottomRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.mission_control"),
            
            // Notification Center & Control Center
            Gesture(zone: .topLeft, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.show_desktop"),
            Gesture(zone: .topRight, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.mission_control"),
            
            // App Cycling
            Gesture(zone: .bottom, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("backward")]),
            Gesture(zone: .top, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("forward")])
        ]
        
        return ConfigurationProfile(
            name: "System Navigation",
            gestures: gestures,
            isDefault: false
        )
    }
    
    // Productivity Profile - Focused on productivity shortcuts
    static func createProductivityProfile() -> ConfigurationProfile {
        let gestures = [
            // Window management essentials
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.close_window"),
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.fullscreen"),
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.minimize"),
            
            // Quick app switching
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("backward")]),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("forward")]),
            
            // System controls
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.mission_control"),
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
            isDefault: false
        )
    }
    
    // Minimal Profile - Basic essential gestures only
    static func createMinimalProfile() -> ConfigurationProfile {
        let gestures = [
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.quit_app"),
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.close_window"),
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.fullscreen"),
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.minimize"),
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("previous")]),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("next")])
        ]
        
        return ConfigurationProfile(
            name: "Minimal",
            gestures: gestures,
            isDefault: false
        )
    }
    
    // Developer Profile - Focused on development workflows
    static func createDeveloperProfile() -> ConfigurationProfile {
        let gestures = [
            // Window management
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("left_half")]),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("right_half")]),
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.maximize"),
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.close_window"),
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.quit_app"),
            
            // Quick app switching (Terminal, IDE, Browser)
            Gesture(zone: .bottomLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("backward")]),
            Gesture(zone: .bottomRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("forward")]),
            
            // Spaces for different projects
            Gesture(zone: .left, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("previous")]),
            Gesture(zone: .right, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("next")]),
            
            // Mission Control for overview
            Gesture(zone: .top, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.mission_control"),
            Gesture(zone: .bottom, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.app_expose"),
            
            // Screenshot for documentation
            Gesture(zone: .topLeft, modifiers: [.command, .shift], actionIdentifier: "com.mousegestures.system.screenshot", parameters: ["type": AnyCodable("selection")]),
            
            // Hide distractions
            Gesture(zone: .bottomLeft, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.show_desktop")
        ]
        
        return ConfigurationProfile(
            name: "Developer",
            gestures: gestures,
            isDefault: false
        )
    }
    
    // Tab Navigation Profile — browser and app tab management
    static func createTabNavigationProfile() -> ConfigurationProfile {
        // Modifier: Cmd+Shift for tab actions
        // Keyboard shortcut modifiers stored as CGEventFlags UInt values:
        //   maskCommand  = 1048576  (0x100000)
        //   maskShift    =  131072  (0x20000)
        //   maskControl  =  262144  (0x40000)
        let cmdMask      = UInt(1048576)
        let shiftMask    = UInt(131072)
        let ctrlMask     = UInt(262144)

        func shortcut(keyCode: UInt16, mods: UInt, display: String) -> [String: AnyCodable] {
            ["shortcut": AnyCodable(["keyCode": keyCode, "modifiers": mods, "displayString": display] as [String: Any])]
        }

        func gest(zone: ScreenZone, name: String, keyCode: UInt16, mods: UInt, display: String) -> Gesture {
            var g = Gesture(zone: zone, modifiers: [.command, .shift],
                            actionIdentifier: "com.mousegestures.automation.keyboard_shortcut",
                            parameters: shortcut(keyCode: keyCode, mods: mods, display: display))
            g.name = name
            return g
        }

        let gestures = [
            gest(zone: .right,       name: "Next Tab",         keyCode: 48, mods: ctrlMask,            display: "⌃⇥"),
            gest(zone: .left,        name: "Previous Tab",     keyCode: 48, mods: ctrlMask | shiftMask, display: "⌃⇧⇥"),
            gest(zone: .top,         name: "New Tab",          keyCode: 17, mods: cmdMask,             display: "⌘T"),
            gest(zone: .bottom,      name: "Close Tab",        keyCode: 13, mods: cmdMask,             display: "⌘W"),
            gest(zone: .topRight,    name: "Reopen Tab",       keyCode: 17, mods: cmdMask | shiftMask, display: "⌘⇧T"),
            gest(zone: .topLeft,     name: "Back",             keyCode: 33, mods: cmdMask,             display: "⌘["),
            gest(zone: .bottomRight, name: "Forward",          keyCode: 30, mods: cmdMask,             display: "⌘]"),
            gest(zone: .bottomLeft,  name: "Focus Address Bar",keyCode: 37, mods: cmdMask,             display: "⌘L"),
        ]

        return ConfigurationProfile(name: "Tab Navigation", gestures: gestures, isDefault: false)
    }

    // Get all default profiles
    static func getAllDefaultProfiles() -> [ConfigurationProfile] {
        return [
            createWindowManagementProfile(),
            createMediaControlProfile(),
            createSystemNavigationProfile(),
            createProductivityProfile(),
            createMinimalProfile(),
            createDeveloperProfile(),
            createTabNavigationProfile()
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
        case .tabNavigation:
            return createTabNavigationProfile()
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
