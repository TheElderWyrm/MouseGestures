import Foundation
import SwiftUI

/// Service for checking app updates and managing versions
public class UpdateService: ObservableObject {

    // MARK: - Singleton
    public static let shared = UpdateService()

    // MARK: - Constants

    /// GitHub's "latest release" API -- the live source of truth for what's
    /// actually published, so there's no separate version.json to keep in
    /// sync by hand after cutting a release.
    private let releaseAPIURL = URL(string: "https://api.github.com/repos/TheElderWyrm/MouseGestures/releases/latest")
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
        guard let url = releaseAPIURL else { return }

        isChecking = true

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false
                self.lastCheckDate = Date()
                UserDefaults.standard.set(self.lastCheckDate, forKey: self.lastCheckKey)

                // On any network/parse failure, a release that isn't really
                // published yet (draft/prerelease), or one with no macOS
                // disk image attached, silently leave isUpdateAvailable as-is
                // (default false) -- no false positives, and never offer an
                // update we couldn't actually install.
                guard error == nil, let data = data,
                      let release = try? UpdateLogic.parseGitHubRelease(data),
                      UpdateLogic.isEligible(release),
                      let asset = UpdateLogic.downloadAsset(from: release) else {
                    return
                }

                let remoteVersion = UpdateLogic.versionString(fromTag: release.tagName)
                self.latestVersion = remoteVersion
                self.updateReleaseNotes = release.body ?? ""
                self.updateDownloadURLString = asset.browserDownloadURL
                self.isUpdateAvailable = UpdateLogic.isUpdateAvailable(current: self.currentVersion, remote: remoteVersion)

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
