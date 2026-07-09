import Foundation
import AppKit

// MARK: - AccessibilityPermissionService
// Single-purpose service for managing accessibility permissions

class AccessibilityPermissionService {
    static let shared = AccessibilityPermissionService()

    private init() {}

    // MARK: - Permission Checking

    func hasPermissions() -> Bool {
        return AXIsProcessTrusted()
    }

    func checkPermissions(prompt: Bool = false) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            return AXIsProcessTrustedWithOptions(options as CFDictionary)
        } else {
            return AXIsProcessTrusted()
        }
    }

    // MARK: - System Preferences

    func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)

        log.log("Opening Accessibility preferences")
    }

    func getPermissionStatus() -> String {
        return hasPermissions() ? "Granted ✓" : "Not Granted"
    }

    // MARK: - Permission Instructions

    func getInstructionText() -> String {
        return """
        MouseGestures needs accessibility permissions to:
        • Monitor mouse movements and clicks
        • Detect keyboard shortcuts
        • Control windows and applications

        Please grant permission in System Preferences > Security & Privacy > Privacy > Accessibility
        """
    }
}
