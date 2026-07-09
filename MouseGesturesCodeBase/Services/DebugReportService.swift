import Foundation
import AppKit

// MARK: - DebugReportService
// Single-purpose service for generating debug reports

class DebugReportService {
    static let shared = DebugReportService()

    private let configuration = Configuration.shared
    private let performanceMonitor = PerformanceMonitorService.shared

    private init() {}

    func generateReport() -> String {
        var report = "MouseGestures Debug Report\n"
        report += "Generated: \(Date())\n"
        report += String(repeating: "=", count: 60) + "\n\n"

        // System Information
        report += "=== System Information ===\n"
        report += "App Version: \(performanceMonitor.getAppVersion())\n"
        report += "macOS Version: \(performanceMonitor.getSystemVersion())\n"
        report += "Process ID: \(performanceMonitor.getProcessID())\n"
        report += "Uptime: \(performanceMonitor.getUptime())\n"
        report += "\n"

        // Configuration
        report += "=== Configuration ===\n"
        report += "Gestures Enabled: \(configuration.isEnabled)\n"
        report += "Profiles Count: \(configuration.profiles.count)\n"
        report += "Active Profile: \(configuration.activeProfile?.name ?? "None")\n"
        report += "Gestures Count: \(configuration.gestures.count)\n"
        report += "App Mappings: \(configuration.appProfileMappings.count)\n"
        report += "Disabled Apps: \(configuration.disabledApps.count)\n"
        report += "Haptic Feedback: \(configuration.hapticFeedbackEnabled)\n"
        report += "Show Zone Highlights: \(configuration.showZoneHighlights)\n"
        report += "Show Zone Labels: \(configuration.showZoneLabels)\n"
        report += "Developer Mode: \(configuration.developerModeEnabled)\n"
        report += "Debug Mode: \(configuration.debugModeEnabled)\n"
        report += "\n"

        // Zone Configuration
        report += "=== Zone Configuration ===\n"
        report += "Edge Threshold: \(configuration.edgeThreshold) pixels\n"
        report += "Corner Size: \(configuration.cornerSize) pixels\n"
        report += "Corner Buffer: \(configuration.cornerBuffer) pixels\n"
        report += "\n"

        // Plugins
        report += "=== Loaded Plugins ===\n"
        let plugins = PluginManagementService.shared.getLoadedPlugins()
        for plugin in plugins {
            report += "- \(plugin.name) v\(plugin.version) (\(plugin.identifier))\n"
            report += "  Actions: \(plugin.actionCount), Built-in: \(plugin.isBuiltIn)\n"
        }
        report += "\n"

        // Memory Usage
        report += "=== Memory Usage ===\n"
        report += "Physical Memory: \(performanceMonitor.getSystemMemory())\n"
        let memoryUsage = performanceMonitor.getMemoryUsage()
        report += "App Resident Memory: \(memoryUsage.resident)\n"
        report += "App Virtual Memory: \(memoryUsage.virtual)\n"
        report += "\n"

        // Accessibility
        report += "=== Accessibility ===\n"
        report += "Permissions: \(AccessibilityPermissionService.shared.getPermissionStatus())\n"
        report += "\n"

        // Active Profiles
        if !configuration.profiles.isEmpty {
            report += "=== Profiles ===\n"
            for profile in configuration.profiles {
                let isActive = profile.id == configuration.activeProfileId
                report += "- \(profile.name)\(isActive ? " (Active)" : "")\n"
            }
            report += "\n"
        }

        // Recent Gestures (if available)
        if !configuration.gestures.isEmpty {
            report += "=== Recent Gestures (First 10) ===\n"
            for (index, gesture) in configuration.gestures.prefix(10).enumerated() {
                report += "\(index + 1). Zone: \(gesture.zone), "
                report += "Action: \(gesture.actionIdentifier)\n"
            }
            report += "\n"
        }

        report += "=== End of Report ===\n"

        return report
    }

    func exportReport(to url: URL) -> Bool {
        let report = generateReport()

        do {
            try report.write(to: url, atomically: true, encoding: .utf8)
            log.log("Debug report exported to: \(url.path)")
            return true
        } catch {
            log.log("Failed to export debug report: \(error)")
            return false
        }
    }

    func copyReportToClipboard() {
        let report = generateReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)

        log.log("Debug report copied to clipboard")
    }
}
