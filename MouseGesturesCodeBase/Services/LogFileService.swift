import Foundation
import AppKit

// MARK: - LogFileService
// Single-purpose service for managing log files

class LogFileService {
    static let shared = LogFileService()

    private let logsDirectory: URL

    private init() {
        logsDirectory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs")
            .appendingPathComponent("MouseGestures")

        // Ensure logs directory exists
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Log File Operations

    func getLogFiles() -> [LogFileInfo] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: logsDirectory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )

            return files
                .filter { $0.pathExtension == "log" }
                .compactMap { url -> LogFileInfo? in
                    let attributes = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])

                    return LogFileInfo(
                        url: url,
                        name: url.lastPathComponent,
                        size: Int64(attributes?.fileSize ?? 0),
                        creationDate: attributes?.creationDate ?? Date()
                    )
                }
                .sorted { $0.creationDate > $1.creationDate }
        } catch {
            log.log("Failed to get log files: \(error)")
            return []
        }
    }

    func readLogFile(_ url: URL) throws -> String {
        return try String(contentsOf: url, encoding: .utf8)
    }

    func deleteLogFile(_ url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            log.log("Deleted log file: \(url.lastPathComponent)")
            return true
        } catch {
            log.log("Failed to delete log file: \(error)")
            return false
        }
    }

    func clearAllLogs() -> Bool {
        let logs = getLogFiles()
        var success = true

        for logInfo in logs {
            if !deleteLogFile(logInfo.url) {
                success = false
            }
        }

        return success
    }

    func exportLogs(to url: URL) -> Bool {
        let logs = getLogFiles()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Copy all log files to temp directory
            for logInfo in logs {
                let destination = tempDir.appendingPathComponent(logInfo.name)
                try FileManager.default.copyItem(at: logInfo.url, to: destination)
            }

            // Remove any pre-existing archive at the destination first. `zip -r`
            // *updates* an existing archive in place rather than replacing it,
            // so exporting twice to the same path would otherwise leave stale
            // entries from the previous export mixed into the new one.
            try? FileManager.default.removeItem(at: url)

            // Create zip archive
            let task = Process()
            task.launchPath = "/usr/bin/zip"
            task.arguments = ["-r", url.path, "."]
            task.currentDirectoryPath = tempDir.path
            task.launch()
            task.waitUntilExit()

            // Clean up temp directory
            try? FileManager.default.removeItem(at: tempDir)

            return task.terminationStatus == 0
        } catch {
            log.log("Failed to export logs: \(error)")
            try? FileManager.default.removeItem(at: tempDir)
            return false
        }
    }

    func openLogsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logsDirectory.path)
    }

    // MARK: - Helper Types

    struct LogFileInfo {
        let url: URL
        let name: String
        let size: Int64
        let creationDate: Date

        var formattedSize: String {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }

        var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: creationDate)
        }
    }
}
