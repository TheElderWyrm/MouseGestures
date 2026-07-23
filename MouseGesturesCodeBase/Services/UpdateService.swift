import Foundation
import SwiftUI

/// Service for checking app updates and managing versions
public class UpdateService: ObservableObject {

    // MARK: - Singleton
    public static let shared = UpdateService()

    // MARK: - Constants
    private let updateURL = URL(string: "https://raw.githubusercontent.com/TheElderWyrm/MouseGestures/main/version.json")
    private let lastCheckKey = "MGLastUpdateCheck"
    private let autoUpdateKey = "MGAutoUpdateEnabled"

    // MARK: - Properties
    @Published public var currentVersion: String = ""
    @Published public var latestVersion: String = ""
    @Published public var isUpdateAvailable: Bool = false
    @Published public var updateReleaseNotes: String = ""
    @Published public var updateDownloadURLString: String = ""
    @Published public var isChecking: Bool = false
    @Published public var lastCheckDate: Date?

    private init() {
        currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        lastCheckDate = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    }

    // MARK: - Public API

    /// Check for updates manually
    public func checkForUpdates(quietly: Bool = false) {
        guard !isChecking else { return }
        guard let url = updateURL else { return }

        isChecking = true

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false
                self.lastCheckDate = Date()
                UserDefaults.standard.set(self.lastCheckDate, forKey: self.lastCheckKey)

                // On any network or parse failure, silently leave
                // isUpdateAvailable as-is (default false) -- no false positives.
                guard error == nil, let data = data,
                      let feed = try? UpdateLogic.parseFeed(data) else {
                    return
                }

                self.latestVersion = feed.version
                self.updateReleaseNotes = feed.releaseNotes
                self.updateDownloadURLString = feed.downloadURL
                self.isUpdateAvailable = UpdateLogic.isUpdateAvailable(current: self.currentVersion, remote: feed.version)

                if self.isUpdateAvailable && !quietly {
                    self.showUpdateNotification()
                }
            }
        }.resume()
    }

    /// Returns true if auto-update is enabled
    public var isAutoUpdateEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: autoUpdateKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoUpdateKey) }
    }

    // MARK: - Helper Methods

    private func showUpdateNotification() {
        NotificationCenter.default.post(
            name: NSNotification.Name("MGUpdateAvailable"),
            object: self
        )

        // Also show a system notification if configured
        if Configuration.shared.notificationOnActivation {
            PluginManager.shared.showPluginNotification(
                title: "Update Available",
                message: "MouseGestures v\(latestVersion) is now available.",
                style: .info,
                pluginId: "com.mousegestures.system"
            )
        }
    }
}
