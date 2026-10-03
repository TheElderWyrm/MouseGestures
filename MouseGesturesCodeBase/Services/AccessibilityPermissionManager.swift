import Cocoa
import Carbon

/// Manages accessibility permission checking and user guidance
class AccessibilityPermissionManager {

    // MARK: - Properties

    private var checkTimer: Timer?
    private weak var delegate: AccessibilityPermissionManagerDelegate?
    private var isCheckingPermissions = false
    private var lastPermissionStatus = false
    private var helpPanel: NSPanel?

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
        let trusted = checkPermission(prompt: true)
        if !trusted { showHelpPanel() }
    }

    /// Starts periodic checking for permission changes
    func startMonitoring() {
        // First check if we already have permissions
        let hasPermission = checkPermission(prompt: false)

        if hasPermission {
            log.log("Accessibility permissions already granted - not starting monitor")
            stopPermissionCheckTimer()
            hideHelpPanel()
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

        If MouseGestures is already listed but still doesn't work (this can happen after an update), select it, click "–" to remove it, then re-add it with "+".
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
        // Menu-bar (accessory) apps must activate or windows can stay hidden behind others
        NSApp.activate(ignoringOtherApps: true)

        // Keep the system request; it is a silent no-op if the app already has a (possibly
        // stale) Accessibility entry, so also always show the help panel as visible feedback.
        let trusted = checkPermission(prompt: true)

        if trusted {
            hideHelpPanel()
            showPermissionGrantedAlert()
            delegate?.accessibilityPermissionGranted()
        } else {
            showHelpPanel()
            startMonitoring()
        }
    }

    // MARK: - Help Panel

    /// Shows a small floating window in the top-right corner listing the steps to grant access
    func showHelpPanel() {
        if let panel = helpPanel {
            panel.orderFrontRegardless()
            return
        }

        let width: CGFloat = 320
        let title = NSTextField(labelWithString: "Grant Accessibility Access")
        title.font = .boldSystemFont(ofSize: 14)

        let steps = NSTextField(wrappingLabelWithString: """
        1. Click "Open System Settings" below.
        2. Find "MouseGestures" in the Accessibility list.
        3. Turn its switch on (enter your password if asked).
        4. If it's already on but not working, select it, click "–" to remove it, then add it back with "+".

        This window closes automatically once access is granted.
        """)
        steps.font = .systemFont(ofSize: 12)
        steps.preferredMaxLayoutWidth = width - 32

        let open = NSButton(title: "Open System Settings", target: self, action: #selector(helpOpenSettings))
        open.bezelStyle = .rounded
        open.keyEquivalent = "\r"
        let close = NSButton(title: "Dismiss", target: self, action: #selector(helpDismiss))
        close.bezelStyle = .rounded
        let buttons = NSStackView(views: [open, close])
        buttons.spacing = 8

        let stack = NSStackView(views: [title, steps, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        stack.setFrameSize(NSSize(width: width, height: stack.fittingSize.height))

        let panel = NSPanel(contentRect: stack.frame,
                            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.title = "MouseGestures Setup"
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = stack

        let screen = NSScreen.main ?? NSScreen.screens.first
        if let vf = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 16, y: vf.maxY - size.height - 16))
        }
        panel.orderFrontRegardless()
        helpPanel = panel
    }

    func hideHelpPanel() {
        helpPanel?.close()
        helpPanel = nil
    }

    @objc private func helpOpenSettings() { openSystemPreferences() }
    @objc private func helpDismiss() { hideHelpPanel() }

    // MARK: - Private Methods

    private func checkPermissionStatus() {
        // Force re-check with fresh state
        let hasPermission = checkPermission(prompt: false)

        // If we have permission, stop the timer and notify delegate
        if hasPermission {
            stopPermissionCheckTimer()
            hideHelpPanel()
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
