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
//
// MODIFIER CONVENTION (shared across the profiles below):
//   ⌘⌃ (Command+Control) = "Main" layer   — the profile's primary actions
//   ⌘⌥ (Command+Option)  = "Secondary" layer — a second layer of actions on the same zones
//   Shift                = a modifier ON TOP of Main/Secondary that changes direction/magnitude
//                           (e.g. seek 10s -> 30s, new tab -> reopen last tab)
struct DefaultProfiles {

    // Window Management Profile - Main layer for window/display controls,
    // Secondary layer for region snapping. Snapping the same region twice in a
    // row (Secondary layer) restores the window's previous position/size
    // instead of re-snapping (see WindowManagementPlugin.snapWindow).
    static func createWindowManagementProfile() -> ConfigurationProfile {
        let gestures = [
            // Main (⌘⌃)
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.close_window", name: "Close Window"),
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.fullscreen", name: "Fullscreen"),
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.quit_app", name: "Quit Application"),
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.move_to_display", parameters: ["display": AnyCodable("previous")], name: "Move to Previous Display"),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.move_to_display", parameters: ["display": AnyCodable("next")], name: "Move to Next Display"),
            Gesture(zone: .bottomLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.app_expose", name: "App Exposé"),
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.minimize", name: "Minimize"),
            Gesture(zone: .bottomRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.mission_control", name: "Mission Control"),

            // Secondary (⌘⌥) - region snapping
            Gesture(zone: .topLeft, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("top_left")], name: "Top Left"),
            Gesture(zone: .top, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("maximize")], name: "Maximize"),
            Gesture(zone: .topRight, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("top_right")], name: "Top Right"),
            Gesture(zone: .left, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("left_half")], name: "Left Half"),
            Gesture(zone: .right, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("right_half")], name: "Right Half"),
            Gesture(zone: .bottomLeft, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("bottom_left")], name: "Bottom Left"),
            Gesture(zone: .bottom, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("center")], name: "Center"),
            Gesture(zone: .bottomRight, modifiers: [.command, .option], actionIdentifier: "com.mousegestures.window.snap_window", parameters: ["position": AnyCodable("bottom_right")], name: "Bottom Right")
        ]

        return ConfigurationProfile(
            name: "Window Management",
            gestures: gestures,
            isDefault: false
        )
    }

    // Application Management Profile - app lifecycle, spaces, and exposé
    static func createApplicationManagementProfile() -> ConfigurationProfile {
        let gestures = [
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.close_window", name: "Close Window"),
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.window.fullscreen", name: "Fullscreen"),
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.quit_app", name: "Quit App"),
            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("previous")], name: "Previous Space"),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.cycle_space", parameters: ["direction": AnyCodable("next")], name: "Next Space"),
            Gesture(zone: .bottomLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.app_expose", name: "App Exposé"),
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.hide_app", name: "Hide App"),
            Gesture(zone: .bottomRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.mission_control", name: "Mission Control")
        ]

        return ConfigurationProfile(
            name: "Application Management",
            gestures: gestures,
            isDefault: false
        )
    }

    // Media Control Profile - playback, seek, and volume.
    // Volume Up/Down repeat automatically while held (repeatOnHold); holding
    // Shift on the seek gestures jumps 30 seconds instead of 10.
    static func createMediaControlProfile() -> ConfigurationProfile {
        let gestures = [
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.track_skip", parameters: ["direction": AnyCodable("previous")], name: "Previous Track"),
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.play_pause", name: "Play/Pause"),
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.track_skip", parameters: ["direction": AnyCodable("next")], name: "Next Track"),

            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.seek", parameters: ["direction": AnyCodable("backward"), "seconds": AnyCodable(10)], name: "10 Seconds Back"),
            Gesture(zone: .left, modifiers: [.command, .control, .shift], actionIdentifier: "com.mousegestures.media.seek", parameters: ["direction": AnyCodable("backward"), "seconds": AnyCodable(30)], name: "30 Seconds Back"),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.seek", parameters: ["direction": AnyCodable("forward"), "seconds": AnyCodable(10)], name: "10 Seconds Forward"),
            Gesture(zone: .right, modifiers: [.command, .control, .shift], actionIdentifier: "com.mousegestures.media.seek", parameters: ["direction": AnyCodable("forward"), "seconds": AnyCodable(30)], name: "30 Seconds Forward"),

            Gesture(zone: .bottomLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.volume", parameters: ["mode": AnyCodable("down")], name: "Volume Down", timing: TimingSettings(repeatOnHold: true)),
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.volume", parameters: ["mode": AnyCodable("mute")], name: "Mute"),
            Gesture(zone: .bottomRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.media.volume", parameters: ["mode": AnyCodable("up")], name: "Volume Up", timing: TimingSettings(repeatOnHold: true))
        ]

        return ConfigurationProfile(
            name: "Media Control",
            gestures: gestures,
            isDefault: false
        )
    }

    // Browser Navigation Profile - page/tab navigation via the Browser Actions
    // plugin (com.mousegestures.browser). Holding Shift on New Tab reopens the
    // last closed tab instead.
    static func createBrowserNavigationProfile() -> ConfigurationProfile {
        // Keyboard shortcut modifiers stored as CGEventFlags UInt values:
        //   maskCommand = 1048576 (0x100000)
        let cmdMask = UInt(1048576)

        let gestures = [
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.browser.navigation", parameters: ["action": AnyCodable("refresh")], name: "Reload"),
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.browser.tab_management", parameters: ["action": AnyCodable("new_tab")], name: "New Tab"),
            Gesture(zone: .top, modifiers: [.command, .control, .shift], actionIdentifier: "com.mousegestures.browser.tab_management", parameters: ["action": AnyCodable("reopen_closed_tab")], name: "Reopen Last Tab"),
            Gesture(
                zone: .topRight, modifiers: [.command, .control],
                actionIdentifier: "com.mousegestures.automation.keyboard_shortcut",
                parameters: ["shortcut": AnyCodable(["keyCode": UInt16(37), "modifiers": cmdMask, "displayString": "⌘L"] as [String: Any])],
                name: "Focus Address Bar"
            ),

            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.browser.navigation", parameters: ["action": AnyCodable("back")], name: "Back"),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.browser.navigation", parameters: ["action": AnyCodable("forward")], name: "Forward"),

            Gesture(zone: .bottomLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.browser.tab_management", parameters: ["action": AnyCodable("previous_tab")], name: "Previous Tab"),
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.browser.tab_management", parameters: ["action": AnyCodable("close_tab")], name: "Close Tab"),
            Gesture(zone: .bottomRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.browser.tab_management", parameters: ["action": AnyCodable("next_tab")], name: "Next Tab")
        ]

        return ConfigurationProfile(
            name: "Browser Navigation",
            gestures: gestures,
            isDefault: false
        )
    }

    // System Profile - brightness, display, and quick system toggles.
    // Brightness gestures repeat automatically while held.
    static func createSystemProfile() -> ConfigurationProfile {
        let gestures = [
            Gesture(zone: .topLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.system.toggle_do_not_disturb", name: "Do Not Disturb"),
            Gesture(zone: .top, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.system.display_brightness", parameters: ["direction": AnyCodable("up")], name: "Brightness Up", timing: TimingSettings(repeatOnHold: true)),
            Gesture(zone: .topRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.system.toggle_dark_mode", name: "Dark Mode"),

            Gesture(zone: .left, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.system.keyboard_brightness", parameters: ["direction": AnyCodable("down")], name: "Keyboard Brightness Down", timing: TimingSettings(repeatOnHold: true)),
            Gesture(zone: .right, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.system.keyboard_brightness", parameters: ["direction": AnyCodable("up")], name: "Keyboard Brightness Up", timing: TimingSettings(repeatOnHold: true)),

            Gesture(zone: .bottomLeft, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.core.lock_screen", name: "Lock Screen"),
            Gesture(zone: .bottom, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.system.display_brightness", parameters: ["direction": AnyCodable("down")], name: "Brightness Down", timing: TimingSettings(repeatOnHold: true)),
            Gesture(zone: .bottomRight, modifiers: [.command, .control], actionIdentifier: "com.mousegestures.system.screenshot", parameters: ["type": AnyCodable("selection")], name: "Screenshot")
        ]

        return ConfigurationProfile(
            name: "System",
            gestures: gestures,
            isDefault: false
        )
    }

    // Get all default profiles
    static func getAllDefaultProfiles() -> [ConfigurationProfile] {
        return [
            createWindowManagementProfile(),
            createApplicationManagementProfile(),
            createMediaControlProfile(),
            createBrowserNavigationProfile(),
            createSystemProfile()
        ]
    }

    /// Gets a specific default profile by type
    static func getProfile(for type: DefaultProfileType) -> ConfigurationProfile? {
        switch type {
        case .windowManagement:
            return createWindowManagementProfile()
        case .applicationManagement:
            return createApplicationManagementProfile()
        case .mediaControl:
            return createMediaControlProfile()
        case .browserNavigation:
            return createBrowserNavigationProfile()
        case .system:
            return createSystemProfile()
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
