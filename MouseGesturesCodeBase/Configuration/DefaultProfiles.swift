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
            Gesture(zone: .topLeft,     modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.maximize",    name: "Maximize"),
            Gesture(zone: .topRight,    modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.close_window", name: "Close Window"),
            Gesture(zone: .top,         modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.fullscreen",   name: "Fullscreen"),
            Gesture(zone: .bottom,      modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.minimize",     name: "Minimize"),
            Gesture(zone: .left,  modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("left_half")],    name: "Left Half"),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("right_half")],   name: "Right Half"),
            Gesture(zone: .topLeft,     modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("top_left")],     name: "Top Left"),
            Gesture(zone: .topRight,    modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("top_right")],    name: "Top Right"),
            Gesture(zone: .bottomLeft,  modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("bottom_left")],  name: "Bottom Left"),
            Gesture(zone: .bottomRight, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("bottom_right")], name: "Bottom Right"),
            Gesture(zone: .left,  modifiers: [.command, .shift], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("previous")], name: "Previous Space"),
            Gesture(zone: .right, modifiers: [.command, .shift], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("next")],     name: "Next Space"),
            Gesture(zone: .bottom, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("backward")], name: "Previous Window"),
            Gesture(zone: .top,   modifiers: [.command, .option], actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("forward")],  name: "Next Window"),
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
            Gesture(zone: .bottom,   modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.play_pause",                                                        name: "Play/Pause"),
            Gesture(zone: .left,     modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.track_skip", parameters: ["direction": AnyCodable("previous")],    name: "Previous Track"),
            Gesture(zone: .right,    modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.track_skip", parameters: ["direction": AnyCodable("next")],         name: "Next Track"),
            Gesture(zone: .top,      modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.volume",     parameters: ["mode": AnyCodable("up")],               name: "Volume Up"),
            Gesture(zone: .bottom,   modifiers: [.command, .option],  actionIdentifier: "com.mousegestures.media.volume",     parameters: ["mode": AnyCodable("down")],             name: "Volume Down"),
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.volume",     parameters: ["mode": AnyCodable("mute")],             name: "Mute"),
            Gesture(zone: .top,      modifiers: [.control, .option],  actionIdentifier: "com.mousegestures.system.display_brightness", parameters: ["direction": AnyCodable("up")], name: "Brightness Up"),
            Gesture(zone: .bottom,   modifiers: [.control, .option],  actionIdentifier: "com.mousegestures.system.display_brightness", parameters: ["direction": AnyCodable("down")], name: "Brightness Down"),
            Gesture(zone: .topLeft,  modifiers: [.command, .shift],   actionIdentifier: "com.mousegestures.system.screenshot", parameters: ["type": AnyCodable("full")],            name: "Full Screenshot"),
            Gesture(zone: .topRight, modifiers: [.command, .shift],   actionIdentifier: "com.mousegestures.system.screenshot", parameters: ["type": AnyCodable("selection")],       name: "Screenshot Selection"),
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
            Gesture(zone: .top,         modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.mission_control",                                                     name: "Mission Control"),
            Gesture(zone: .bottom,      modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.show_desktop",                                                        name: "Show Desktop"),
            Gesture(zone: .left,        modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("previous")],     name: "Previous Space"),
            Gesture(zone: .right,       modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("next")],          name: "Next Space"),
            Gesture(zone: .topLeft,     modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.app_expose",                                                          name: "App Exposé"),
            Gesture(zone: .topRight,    modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.app_expose",                                                          name: "App Exposé"),
            Gesture(zone: .bottomLeft,  modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.mission_control",                                                     name: "Mission Control"),
            Gesture(zone: .bottomRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.mission_control",                                                     name: "Mission Control"),
            Gesture(zone: .topLeft,     modifiers: [.command, .option],  actionIdentifier: "com.mousegestures.core.show_desktop",                                                        name: "Show Desktop"),
            Gesture(zone: .topRight,    modifiers: [.command, .option],  actionIdentifier: "com.mousegestures.core.mission_control",                                                     name: "Mission Control"),
            Gesture(zone: .bottom,      modifiers: [.command, .option],  actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("backward")],    name: "Previous Window"),
            Gesture(zone: .top,         modifiers: [.command, .option],  actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("forward")],     name: "Next Window"),
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
            Gesture(zone: .topRight,    modifiers: [.command, .control],           actionIdentifier: "com.mousegestures.window.close_window",                                                      name: "Close Window"),
            Gesture(zone: .top,         modifiers: [.command, .control],           actionIdentifier: "com.mousegestures.window.fullscreen",                                                        name: "Fullscreen"),
            Gesture(zone: .bottom,      modifiers: [.command, .control],           actionIdentifier: "com.mousegestures.window.minimize",                                                          name: "Minimize"),
            Gesture(zone: .left,        modifiers: [.command, .control],           actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("backward")],    name: "Previous Window"),
            Gesture(zone: .right,       modifiers: [.command, .control],           actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("forward")],     name: "Next Window"),
            Gesture(zone: .topLeft,     modifiers: [.command, .control],           actionIdentifier: "com.mousegestures.core.mission_control",                                                     name: "Mission Control"),
            Gesture(zone: .bottomLeft,  modifiers: [.command, .control],           actionIdentifier: "com.mousegestures.core.hide_app",                                                            name: "Hide App"),
            Gesture(zone: .bottomRight, modifiers: [.command, .control],           actionIdentifier: "com.mousegestures.core.show_desktop",                                                        name: "Show Desktop"),
            Gesture(zone: .topLeft,     modifiers: [.control, .option],            actionIdentifier: "com.mousegestures.system.toggle_do_not_disturb",                                             name: "Do Not Disturb"),
            Gesture(zone: .topRight,    modifiers: [.control, .option],            actionIdentifier: "com.mousegestures.system.toggle_dark_mode",                                                  name: "Dark Mode"),
            Gesture(zone: .bottom,      modifiers: [.command, .option, .control],  actionIdentifier: "com.mousegestures.core.lock_screen",                                                         name: "Lock Screen"),
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
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.quit_app",          name: "Quit App"),
            Gesture(zone: .topLeft,  modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.close_window",    name: "Close Window"),
            Gesture(zone: .top,      modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.fullscreen",      name: "Fullscreen"),
            Gesture(zone: .bottom,   modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.minimize",        name: "Minimize"),
            Gesture(zone: .left,     modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("previous")], name: "Previous Space"),
            Gesture(zone: .right,    modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("next")],      name: "Next Space"),
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
            Gesture(zone: .left,        modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("left_half")],  name: "Left Half"),
            Gesture(zone: .right,       modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("right_half")], name: "Right Half"),
            Gesture(zone: .top,         modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.maximize",                                                          name: "Maximize"),
            Gesture(zone: .topRight,    modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.close_window",                                                      name: "Close Window"),
            Gesture(zone: .topLeft,     modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.quit_app",                                                            name: "Quit App"),
            Gesture(zone: .bottomLeft,  modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("backward")],    name: "Previous Window"),
            Gesture(zone: .bottomRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_window", parameters: ["direction": AnyCodable("forward")],     name: "Next Window"),
            Gesture(zone: .left,        modifiers: [.command, .option],  actionIdentifier: "com.mousegestures.core.cycle_space",   parameters: ["direction": AnyCodable("previous")],   name: "Previous Space"),
            Gesture(zone: .right,       modifiers: [.command, .option],  actionIdentifier: "com.mousegestures.core.cycle_space",   parameters: ["direction": AnyCodable("next")],        name: "Next Space"),
            Gesture(zone: .top,         modifiers: [.command, .option],  actionIdentifier: "com.mousegestures.core.mission_control",                                                     name: "Mission Control"),
            Gesture(zone: .bottom,      modifiers: [.command, .option],  actionIdentifier: "com.mousegestures.core.app_expose",                                                          name: "App Exposé"),
            Gesture(zone: .topLeft,     modifiers: [.command, .shift],   actionIdentifier: "com.mousegestures.system.screenshot", parameters: ["type": AnyCodable("selection")],        name: "Screenshot"),
            Gesture(zone: .bottomLeft,  modifiers: [.command, .option],  actionIdentifier: "com.mousegestures.core.show_desktop",                                                        name: "Show Desktop"),
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
