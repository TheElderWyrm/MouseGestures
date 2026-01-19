import Cocoa
import Carbon
import UserNotifications
import SwiftUI
import Foundation

/// A helper view that listens for a notification and opens the Settings scene.
@available(macOS 14.0, *)
struct SettingsActionHandler: View {
    @Environment(\.openSettings) var openSettings

    var body: some View {
        // This view is completely hidden. Its only job is to listen.
        EmptyView()
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsWindow)) { _ in
                // When the notification is received, call the official SwiftUI action.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var menuIcon: MenuIcon!
    var detectionPluginManager: DetectionPluginManager!
    var accessibilityManager: AccessibilityPermissionManager!
    var hiddenWindow: NSWindow?
    
    override init() {
        super.init()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When app is reopened (e.g., from dock or Launchpad), show preferences
        showPreferences()
        return true
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            if let error = error {
                log.log("Notification permission error: \(error)")
            }
        }
        
        // Ensure no restoration of windows
        UserDefaults.standard.set(true, forKey: "NSQuitAlwaysKeepsWindows")
        
        // Initialize accessibility manager
        accessibilityManager = AccessibilityPermissionManager(delegate: self)
        
        // Initialize detection plugin manager (but don't start it yet)
        detectionPluginManager = DetectionPluginManager.shared
        detectionPluginManager.delegate = self
        
        // Initialize menu icon
        menuIcon = MenuIcon(delegate: self)
        
        // Check current permission status and start monitoring if needed
        if accessibilityManager.checkPermission(prompt: false) {
            // We already have permissions - start gesture monitoring
            startGestureMonitoring()
        } else {
            // No permissions yet - start monitoring for permission changes
            accessibilityManager.startMonitoring()
            // Request permissions with prompt
            accessibilityManager.requestPermissions()
        }
        
        // Check if app should show preferences initially
        let config = Configuration.shared
        if config.hideFromMenuBar {
            // Don't create menu bar item, just show preferences
            showPreferences()
        }
        
        if #available(macOS 14.0, *) {
            // Create a hidden window to host the SettingsActionHandler,
            // which is needed to programmatically open the Settings scene.
            let handlerView = SettingsActionHandler()
            let window = NSWindow(
                contentRect: NSRect(x: -1, y: -1, width: 1, height: 1), // Position off-screen
                styleMask: .borderless,
                backing: .buffered,
                defer: false)
            window.contentView = NSHostingView(rootView: handlerView)
            window.alphaValue = 0.0 // Make it completely invisible
            self.hiddenWindow = window // Keep a strong reference
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Stop accessibility monitoring
        accessibilityManager?.stopMonitoring()
        accessibilityManager = nil
        
        // Stop detection plugin monitoring
        detectionPluginManager?.stop()
        detectionPluginManager = nil
        
        // Force save any pending configuration changes
        Configuration.shared.saveImmediate()
        
        // Remove all observers
        NotificationCenter.default.removeObserver(self)
        
        // Clean up menu icon
        menuIcon = nil
        
        // Clean up any remaining UI elements
        // Note: UI cleanup is handled internally by the app lifecycle
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return false  // Disable state restoration
    }
    
    // Replace the showPreferences function in AppDelegate.swift with this
    @objc func showPreferences() {
        // Post a notification that our SwiftUI view will be listening for.
        NotificationCenter.default.post(name: .openSettingsWindow, object: nil)
        log.log("Posted notification to open preferences window")
    }
    
    // MARK: - Private Methods
    
    private func startGestureMonitoring() {
        // Only start if gestures are enabled in configuration
        if Configuration.shared.isEnabled {
            detectionPluginManager.start()
            log.log("AppDelegate: Started detection plugin monitoring")
        } else {
            log.log("AppDelegate: Detection plugin monitoring disabled in configuration")
        }
    }
    
    private func stopGestureMonitoring() {
        detectionPluginManager.stop()
        log.log("AppDelegate: Stopped detection plugin monitoring")
    }
}

// MARK: - AccessibilityPermissionManagerDelegate

extension AppDelegate: AccessibilityPermissionManagerDelegate {
    
    func accessibilityPermissionGranted() {
        // Start gesture monitoring now that we have permissions
        startGestureMonitoring()
        
        // Update preferences window if it's open
        // if let prefsWindow = preferencesWindow {
        //     prefsWindow.updateAccessibilityStatus(hasPermission: true)
        // }
        
        // Update menu icon state
        menuIcon?.updateAccessibilityState(hasPermission: true)
    }
    
    func accessibilityPermissionDenied() {
        // Update preferences window if it's open
        // if let prefsWindow = preferencesWindow {
        //     prefsWindow.updateAccessibilityStatus(hasPermission: false)
        // }
        
        // Disable gestures if permissions are revoked
        if detectionPluginManager?.isEnabled == true {
            stopGestureMonitoring()
        }
        
        // Update menu icon state
        menuIcon?.updateAccessibilityState(hasPermission: false)
    }
}

// MARK: - DetectionManagerDelegate

extension AppDelegate: DetectionManagerDelegate {
    
    func detectionManager(_ manager: Any, executeGesture gesture: Gesture, fromZone zone: ScreenZone, withDragState dragState: DragModifier, modifiers: NSEvent.ModifierFlags) {
        // Route to ActionExecutionManager
        ActionExecutionManager.shared.executeGesture(
            gesture,
            fromZone: zone,
            withDragState: dragState,
            modifiers: modifiers
        )
    }
    
    func detectionManager(_ manager: Any, executeRepeatedGesture gesture: Gesture) {
        // Route to ActionExecutionManager
        ActionExecutionManager.shared.executeRepeatedGesture(gesture)
    }
    
    func detectionManager(_ manager: Any, executeKeyboardTriggeredGesture gesture: Gesture, trigger: KeyboardTrigger) {
        // Route to ActionExecutionManager
        ActionExecutionManager.shared.executeKeyboardTriggeredGesture(gesture, trigger: trigger)
    }
    
    func detectionManager(_ manager: Any, executeMouseButtonTriggeredGesture gesture: Gesture, button: MouseButtonTrigger.MouseButton, modifiers: NSEvent.ModifierFlags) {
        // Route to ActionExecutionManager
        ActionExecutionManager.shared.executeMouseButtonTriggeredGesture(
            gesture,
            button: button,
            modifiers: modifiers
        )
    }
    
    func detectionManager(_ manager: Any, executeProfileSwitch profile: ConfigurationProfile) {
        // Route to ActionExecutionManager
        ActionExecutionManager.shared.executeProfileSwitch(profile)
    }
}

// MARK: - MenuIconDelegate

extension AppDelegate: MenuIconDelegate {
    
    func menuIconDidSelectPreferences() {
        showPreferences()
    }
    
    func menuIconDidToggleGestures() {
        // Toggle the enabled state in configuration
        let newState = !Configuration.shared.isEnabled
        Configuration.shared.isEnabled = newState
        Configuration.shared.save()
        
        // Start or stop monitoring based on new state
        if newState && accessibilityManager.checkPermission(prompt: false) {
            startGestureMonitoring()
        } else {
            stopGestureMonitoring()
        }
        
        menuIcon?.updateGestureToggleState()
        menuIcon?.updateAppearance()
    }
    
    func menuIconDidSelectCheckPermissions() {
        accessibilityManager.handleCheckPermissionsAction()
    }
    
    func menuIconRequestsAccessibilityStatus() -> Bool {
        return accessibilityManager.checkPermission(prompt: false)
    }
    
    func menuIconRequestsAccessibilityAlert() {
        accessibilityManager.showPermissionAlert()
        // Start checking for permissions if not already checking
        accessibilityManager.startMonitoring()
    }
    
    func menuIconRequestsGestureEnabledState() -> Bool {
        // Return the configuration state, not the monitoring state
        // The menu shows whether gestures are enabled in settings
        return Configuration.shared.isEnabled
    }
}

// Add this extension at the bottom of AppDelegate.swift
extension Notification.Name {
    /// A notification to programmatically open the Settings scene.
    static let openSettingsWindow = Notification.Name("com.mousegestures.openSettings")
}

/// Configuration for app-specific gesture behaviors
struct AppConfiguration: Codable, Equatable {
    let appName: String
    let bundleId: String
    let profileId: UUID?
    let isDisabled: Bool
    
    init(appName: String, bundleId: String, profileId: UUID?, isDisabled: Bool) {
        self.appName = appName
        self.bundleId = bundleId
        self.profileId = profileId
        self.isDisabled = isDisabled
    }
}
