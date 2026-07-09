import Cocoa
import Carbon

/// Manages accessibility permission checking and user guidance
class AccessibilityPermissionManager {

    // MARK: - Properties

    private var checkTimer: Timer?
    private weak var delegate: AccessibilityPermissionManagerDelegate?
    private var isCheckingPermissions = false
    private var lastPermissionStatus = false

    // MARK: - Initialization

    init(delegate: AccessibilityPermissionManagerDelegate) {
        self.delegate = delegate
    }

    deinit {
        stopPermissionCheckTimer()
    }

    // MARK: - Public Methods

    /// Checks if the app has accessibility permissions
    /// - Parameter prompt: Whether to show the system prompt for permissions
    /// - Returns: True if permissions are granted
    func checkPermission(prompt: Bool = false) -> Bool {
        // Create options dictionary for AXIsProcessTrustedWithOptions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary

        // Check if we're trusted with the option to prompt
        let trusted = AXIsProcessTrustedWithOptions(options)

        // Also try the simple check as a fallback
        let simpleTrusted = AXIsProcessTrusted()

        // Log the result for debugging
        if prompt || lastPermissionStatus != (trusted || simpleTrusted) {
            log.log("Accessibility check - Options: \(trusted), Simple: \(simpleTrusted)")
        }

        lastPermissionStatus = trusted || simpleTrusted
        return lastPermissionStatus
    }

    /// Requests accessibility permissions with system prompt
    func requestPermissions() {
        _ = checkPermission(prompt: true)
    }

    /// Starts periodic checking for permission changes
    func startMonitoring() {
        // First check if we already have permissions
        let hasPermission = checkPermission(prompt: false)

        if hasPermission {
            log.log("Accessibility permissions already granted - not starting monitor")
            stopPermissionCheckTimer()
            delegate?.accessibilityPermissionGranted()
            return
        }

        // Don't start a new timer if one is already running
        if checkTimer != nil && checkTimer!.isValid {
            log.log("Accessibility permission monitor already running")
            return
        }

        log.log("Starting accessibility permission monitor (every 2 seconds)")
        isCheckingPermissions = true

        // Create timer that checks every 2 seconds
        checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.checkPermissionStatus()
        }

        // Fire immediately for first check
        checkTimer?.fire()
    }

    /// Stops periodic permission checking
    func stopMonitoring() {
        stopPermissionCheckTimer()
    }

    /// Shows an alert explaining why permissions are needed
    func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
        MouseGestures needs accessibility permissions to:

        • Monitor keyboard modifiers (Cmd, Ctrl, Option, Shift)
        • Control window positions and states
        • Trigger system actions

        Please grant permission in System Settings.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            openSystemPreferences()

            // Show instructions after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.showInstructionsWindow()
            }
        }
    }

    /// Shows an alert confirming permissions are granted
    func showPermissionGrantedAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permissions Granted"
        alert.informativeText = "MouseGestures has the required accessibility permissions."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Opens System Preferences to the Accessibility pane
    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Handles the "Check Permissions" menu action
    func handleCheckPermissionsAction() {
        // Force re-check with fresh state
        let trusted = checkPermission(prompt: true)

        if trusted {
            showPermissionGrantedAlert()
            delegate?.accessibilityPermissionGranted()
        } else {
            // Start checking for permissions if not already checking
            startMonitoring()
        }
    }

    // MARK: - Private Methods

    private func checkPermissionStatus() {
        // Force re-check with fresh state
        let hasPermission = checkPermission(prompt: false)

        // If we have permission, stop the timer and notify delegate
        if hasPermission {
            stopPermissionCheckTimer()
            log.log("Accessibility permissions granted - stopping permission monitor")

            // Notify delegate that permissions were granted
            delegate?.accessibilityPermissionGranted()
        } else {
            // Notify delegate that permissions are still not granted
            delegate?.accessibilityPermissionDenied()
        }
    }

    private func stopPermissionCheckTimer() {
        if let timer = checkTimer {
            timer.invalidate()
            checkTimer = nil
            isCheckingPermissions = false
            log.log("Stopped accessibility permission monitor")
        }
    }

    private func showInstructionsWindow() {
        let instructionAlert = NSAlert()
        instructionAlert.messageText = "Grant Accessibility Permission"
        instructionAlert.informativeText = """
        To enable MouseGestures:

        1. Find "MouseGestures" in the list
        2. Click the toggle switch to enable it
        3. You may need to enter your password
        4. MouseGestures will start working immediately

        If you don't see MouseGestures in the list:
        1. Click the "+" button
        2. Navigate to Applications folder
        3. Select MouseGestures.app
        """
        instructionAlert.alertStyle = .informational
        instructionAlert.addButton(withTitle: "Got It")
        instructionAlert.runModal()
    }
}

// MARK: - AccessibilityPermissionManagerDelegate Protocol

protocol AccessibilityPermissionManagerDelegate: AnyObject {
    /// Called when accessibility permissions are granted
    func accessibilityPermissionGranted()

    /// Called when accessibility permissions are checked and found to be denied
    func accessibilityPermissionDenied()
}

// MARK: - Convenience Extensions

extension AccessibilityPermissionManager {
    /// Static method to quickly check permission status without creating an instance
    static func hasPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) || AXIsProcessTrusted()
    }

    /// Static method to request permissions without creating an instance
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
