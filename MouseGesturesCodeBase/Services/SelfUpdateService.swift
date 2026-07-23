import Foundation
import AppKit

/// Errors that can occur during the in-app self-update flow.
public enum SelfUpdateError: LocalizedError {
    case destinationNotWritable
    case invalidDownloadURL
    case downloadFailed(String)
    case httpError(Int)
    case emptyDownload
    case mountFailed(String)
    case appNotFound
    case scriptWriteFailed(String)
    case scriptLaunchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .destinationNotWritable:
            return "MouseGestures isn't installed somewhere it can update itself. Move it to your Applications folder and try again."
        case .invalidDownloadURL:
            return "The update feed did not contain a valid download link."
        case .downloadFailed(let reason):
            return "The update download failed: \(reason)"
        case .httpError(let code):
            return "The update server returned an error (HTTP \(code))."
        case .emptyDownload:
            return "The downloaded update file was empty or corrupted."
        case .mountFailed(let reason):
            return "Couldn't open the downloaded disk image: \(reason)"
        case .appNotFound:
            return "Couldn't find MouseGestures.app inside the downloaded disk image."
        case .scriptWriteFailed(let reason):
            return "Couldn't prepare the installer: \(reason)"
        case .scriptLaunchFailed(let reason):
            return "Couldn't launch the installer: \(reason)"
        }
    }
}

/// Current stage of an in-progress self-update, for UI display.
public enum SelfUpdateStage: Equatable {
    case idle
    case downloading(progress: Double)
    case mounting
    case installing
    case relaunching
    case failed(String)
}

/// Downloads the latest MouseGestures DMG, mounts it, replaces the running
/// app bundle in place, and relaunches -- without requiring the user to
/// manually download/install from a browser.
///
/// This is the standard non-Sparkle self-update pattern used by direct-
/// distribution Mac apps: the running process can't overwrite its own
/// bundle, so it hands off to a small detached helper script that waits for
/// this process to exit, performs the copy, and relaunches the app.
public class SelfUpdateService: NSObject, ObservableObject {

    // MARK: - Singleton
    public static let shared = SelfUpdateService()

    // MARK: - Published state
    @Published public private(set) var stage: SelfUpdateStage = .idle

    public var isUpdating: Bool {
        switch stage {
        case .idle, .failed:
            return false
        default:
            return true
        }
    }

    // MARK: - Internal state
    private var session: URLSession?
    private var downloadCompletion: ((Result<URL, SelfUpdateError>) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Returns false if the app bundle's parent directory isn't writable by
    /// the current user (e.g. running from a read-only volume, or a
    /// location requiring admin rights). Callers should skip straight to
    /// the manual "Open Download Page" fallback in that case rather than
    /// attempting an install that will fail partway through.
    public func canSelfUpdateInPlace() -> Bool {
        let appPath = Bundle.main.bundlePath
        let parent = (appPath as NSString).deletingLastPathComponent
        return FileManager.default.isWritableFile(atPath: parent)
    }

    /// Resets state back to idle so the UI can offer a retry.
    public func reset() {
        stage = .idle
    }

    /// Kicks off the full download -> mount -> install -> relaunch flow.
    /// Progress and failures are reported via `stage`. On success, this
    /// process is terminated (via `NSApp.terminate`) once the installer
    /// script has been handed off, so the caller should not assume it will
    /// keep running.
    public func startSelfUpdate(downloadURLString: String) {
        guard !isUpdating else { return }

        guard canSelfUpdateInPlace() else {
            stage = .failed(SelfUpdateError.destinationNotWritable.errorDescription ?? "Update failed.")
            return
        }
        guard let url = URL(string: downloadURLString) else {
            stage = .failed(SelfUpdateError.invalidDownloadURL.errorDescription ?? "Update failed.")
            return
        }

        stage = .downloading(progress: 0)

        download(url) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.stage = .failed(error.errorDescription ?? "Update failed.")
                }
            case .success(let dmgURL):
                self.mountAndInstall(dmgURL: dmgURL)
            }
        }
    }

    // MARK: - Download

    private func download(_ url: URL, completion: @escaping (Result<URL, SelfUpdateError>) -> Void) {
        downloadCompletion = completion
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.downloadTask(with: url)
        task.resume()
    }

    // MARK: - Mount + Install

    private func mountAndInstall(dmgURL: URL) {
        DispatchQueue.main.async { self.stage = .mounting }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let mountResult = self.attachDMG(at: dmgURL)
            switch mountResult {
            case .failure(let error):
                try? FileManager.default.removeItem(at: dmgURL)
                DispatchQueue.main.async {
                    self.stage = .failed(error.errorDescription ?? "Update failed.")
                }

            case .success(let mountPoint):
                guard let appURL = self.findApp(inVolume: mountPoint) else {
                    self.detach(mountPoint: mountPoint)
                    try? FileManager.default.removeItem(at: dmgURL)
                    DispatchQueue.main.async {
                        self.stage = .failed(SelfUpdateError.appNotFound.errorDescription ?? "Update failed.")
                    }
                    return
                }

                DispatchQueue.main.async { self.stage = .installing }

                do {
                    try self.writeAndLaunchInstallerScript(newAppPath: appURL.path, mountPoint: mountPoint, dmgPath: dmgURL.path)
                    DispatchQueue.main.async {
                        self.stage = .relaunching
                        // The detached script is now waiting for this
                        // process to exit before it replaces the bundle.
                        NSApp.terminate(nil)
                    }
                } catch {
                    self.detach(mountPoint: mountPoint)
                    try? FileManager.default.removeItem(at: dmgURL)
                    let message = (error as? SelfUpdateError)?.errorDescription ?? error.localizedDescription
                    DispatchQueue.main.async { self.stage = .failed(message) }
                }
            }
        }
    }

    /// Runs `hdiutil attach -nobrowse -plist` on the given DMG and parses
    /// the mount point out of its plist output, rather than assuming a
    /// fixed/derived path.
    private func attachDMG(at dmgURL: URL) -> Result<String, SelfUpdateError> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["attach", dmgURL.path, "-nobrowse", "-plist"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
        } catch {
            return .failure(.mountFailed(error.localizedDescription))
        }
        task.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        guard task.terminationStatus == 0 else {
            let errString = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.mountFailed(errString?.isEmpty == false ? errString! : "hdiutil exited with status \(task.terminationStatus)."))
        }

        guard let plist = try? PropertyListSerialization.propertyList(from: outData, options: [], format: nil) as? [String: Any],
              let systemEntities = plist["system-entities"] as? [[String: Any]] else {
            return .failure(.mountFailed("Couldn't parse hdiutil output."))
        }

        // A DMG can contain multiple system-entities (e.g. an EFI/HFS
        // wrapper) -- not all of them have a mount point, so scan for the
        // first one that does.
        for entity in systemEntities {
            if let mountPoint = entity["mount-point"] as? String, !mountPoint.isEmpty {
                return .success(mountPoint)
            }
        }

        return .failure(.mountFailed("No mount point reported for the disk image."))
    }

    private func findApp(inVolume mountPoint: String) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: mountPoint) else {
            return nil
        }
        guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            return nil
        }
        return URL(fileURLWithPath: mountPoint).appendingPathComponent(appName)
    }

    private func detach(mountPoint: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["detach", mountPoint, "-quiet"]
        try? task.run()
        task.waitUntilExit()
    }

    /// Writes a small shell script that:
    ///  1. Waits (up to 30s) for this process, by PID, to exit.
    ///  2. Replaces the installed app bundle with the one from the mounted DMG.
    ///  3. Detaches the DMG and deletes the downloaded temp file.
    ///  4. Relaunches the app.
    ///  5. Deletes itself.
    /// The script is then launched as a detached background process; the
    /// caller is responsible for terminating this app immediately after.
    private func writeAndLaunchInstallerScript(newAppPath: String, mountPoint: String, dmgPath: String) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let installedAppPath = Bundle.main.bundlePath

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mg-selfupdate-\(UUID().uuidString).sh")

        // Every path is shell-quoted individually so spaces/special
        // characters (e.g. "/Applications/MouseGestures.app") survive.
        let script = """
        #!/bin/bash
        set -e

        PID=\(pid)
        OLD_APP=\(shellQuote(installedAppPath))
        NEW_APP=\(shellQuote(newAppPath))
        MOUNT_POINT=\(shellQuote(mountPoint))
        DMG_PATH=\(shellQuote(dmgPath))

        # Wait up to ~30s for the running app to fully quit before touching
        # its bundle on disk.
        for i in $(seq 1 300); do
            if ! kill -0 "$PID" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done

        # Move the old bundle aside instead of deleting it up front, so a
        # failed copy (e.g. disk full) doesn't leave the user with no app at
        # all -- restore the backup on failure, remove it on success.
        BACKUP_APP="${OLD_APP}.mg-backup"
        rm -rf -- "$BACKUP_APP"
        mv -- "$OLD_APP" "$BACKUP_APP"
        if cp -R -- "$NEW_APP" "$OLD_APP"; then
            rm -rf -- "$BACKUP_APP"
        else
            rm -rf -- "$OLD_APP"
            mv -- "$BACKUP_APP" "$OLD_APP"
        fi

        hdiutil detach "$MOUNT_POINT" -quiet || true
        rm -f -- "$DMG_PATH"

        open -- "$OLD_APP"

        rm -- "$0"
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            throw SelfUpdateError.scriptWriteFailed(error.localizedDescription)
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptURL.path]
        // Fully detach: no pipes kept open on our end, and we never wait on it.
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            throw SelfUpdateError.scriptLaunchFailed(error.localizedDescription)
        }
    }

    private func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - URLSessionDownloadDelegate

extension SelfUpdateService: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [weak self] in
            self?.stage = .downloading(progress: progress)
        }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // `location` is deleted as soon as this delegate method returns, so
        // it must be moved to a location we control synchronously here.
        let completion = downloadCompletion
        downloadCompletion = nil

        if let httpResponse = downloadTask.response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            completion?(.failure(.httpError(httpResponse.statusCode)))
            return
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("MouseGestures-update-\(UUID().uuidString).dmg")

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)

            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else {
                try? FileManager.default.removeItem(at: destination)
                completion?(.failure(.emptyDownload))
                return
            }

            completion?(.success(destination))
        } catch {
            completion?(.failure(.downloadFailed(error.localizedDescription)))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Called for both success (error == nil, already handled above) and
        // network-level failures that happen before a download ever
        // finishes (e.g. connection dropped, DNS failure).
        guard let error = error else { return }
        let completion = downloadCompletion
        downloadCompletion = nil
        completion?(.failure(.downloadFailed(error.localizedDescription)))
    }
}
