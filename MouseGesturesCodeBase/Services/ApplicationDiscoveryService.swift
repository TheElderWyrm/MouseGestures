import Foundation
import AppKit

// MARK: - Application Discovery Service
// Single-purpose service for discovering and managing installed applications

class ApplicationDiscoveryService {
    static let shared = ApplicationDiscoveryService()

    private init() {}

    // MARK: - Application Discovery

    func getAllInstalledApplications() -> [(bundleId: String, name: String, icon: NSImage?)] {
        var apps: [(bundleId: String, name: String, icon: NSImage?)] = []

        let workspace = NSWorkspace.shared
        let applicationsFolders = getApplicationFolders()

        for folder in applicationsFolders {
            let folderURL = URL(fileURLWithPath: folder)
            apps.append(contentsOf: scanFolderForApplications(folderURL: folderURL, workspace: workspace))
        }

        // Remove duplicates and sort
        let uniqueApps = removeDuplicateApplications(apps)
        return sortApplicationsByName(uniqueApps)
    }

    func searchApplications(query: String) -> [(bundleId: String, name: String, icon: NSImage?)] {
        let allApps = getAllInstalledApplications()

        guard !query.isEmpty else { return allApps }

        let lowercasedQuery = query.lowercased()
        return allApps.filter { app in
            app.name.lowercased().contains(lowercasedQuery) ||
            app.bundleId.lowercased().contains(lowercasedQuery)
        }
    }

    // MARK: - Private Helpers

    private func getApplicationFolders() -> [String] {
        return [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications",
            "/Applications/Utilities",
            "/System/Applications/Utilities"
        ]
    }

    private func scanFolderForApplications(folderURL: URL, workspace: NSWorkspace) -> [(bundleId: String, name: String, icon: NSImage?)] {
        var apps: [(bundleId: String, name: String, icon: NSImage?)] = []

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isApplicationKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return apps
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "app" {
                if let appInfo = extractApplicationInfo(from: fileURL, workspace: workspace) {
                    apps.append(appInfo)
                }
            }
        }

        return apps
    }

    private func extractApplicationInfo(from url: URL, workspace: NSWorkspace) -> (bundleId: String, name: String, icon: NSImage?)? {
        guard let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else {
            return nil
        }

        // Try to get the display name, falling back to bundle name
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        let icon = workspace.icon(forFile: url.path)

        return (bundleId: bundleId, name: appName, icon: icon)
    }

    private func removeDuplicateApplications(_ apps: [(bundleId: String, name: String, icon: NSImage?)]) -> [(bundleId: String, name: String, icon: NSImage?)] {
        var uniqueApps: [(bundleId: String, name: String, icon: NSImage?)] = []
        var seenBundleIds = Set<String>()

        for app in apps {
            if !seenBundleIds.contains(app.bundleId) {
                uniqueApps.append(app)
                seenBundleIds.insert(app.bundleId)
            }
        }

        return uniqueApps
    }

    private func sortApplicationsByName(_ apps: [(bundleId: String, name: String, icon: NSImage?)]) -> [(bundleId: String, name: String, icon: NSImage?)] {
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Application Validation

    func isApplicationInstalled(bundleId: String) -> Bool {
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }

    func getApplicationInfo(bundleId: String) -> (name: String, icon: NSImage?)? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
              let bundle = Bundle(url: appURL) else {
            return nil
        }

        let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? appURL.deletingPathExtension().lastPathComponent

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)

        return (name: appName, icon: icon)
    }
}
