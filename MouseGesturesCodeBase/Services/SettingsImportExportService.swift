import Foundation
import AppKit

// MARK: - SettingsImportExportService
// Single-purpose service for importing and exporting settings

class SettingsImportExportService {
    static let shared = SettingsImportExportService()

    private let configuration = Configuration.shared

    private init() {}

    // MARK: - Export

    func exportSettings() -> Data? {
        return configuration.exportGlobalSettings()
    }

    func exportSettings(to url: URL) -> Bool {
        guard let data = exportSettings() else { return false }

        do {
            try data.write(to: url)
            log.log("Settings exported to: \(url.path)")
            return true
        } catch {
            log.log("Failed to export settings: \(error)")
            return false
        }
    }

    // MARK: - Import

    func importSettings(from data: Data, mergeProfiles: Bool = false) -> (success: Bool, error: String?) {
        let result = configuration.importGlobalSettings(from: data, mergeProfiles: mergeProfiles)

        if result.success {
            log.log("Settings imported successfully (merge: \(mergeProfiles))")

            NotificationCenter.default.post(
                name: Notification.Name("settingsImported"),
                object: nil
            )
        } else {
            log.log("Failed to import settings: \(result.error ?? "Unknown error")")
        }

        return result
    }

    func importSettings(from url: URL, mergeProfiles: Bool = false) -> (success: Bool, error: String?) {
        do {
            let data = try Data(contentsOf: url)
            return importSettings(from: data, mergeProfiles: mergeProfiles)
        } catch {
            let errorMessage = "Failed to read settings file: \(error.localizedDescription)"
            log.log(errorMessage)
            return (false, errorMessage)
        }
    }
}
