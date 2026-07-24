import Foundation

// MARK: - Log Level

public enum LogLevel: Int, Comparable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    var prefix: String {
        switch self {
        case .verbose: return "[VERBOSE]"
        case .debug: return "[DEBUG]"
        case .info: return "[INFO]"
        case .warning: return "[WARNING]"
        case .error: return "[ERROR]"
        }
    }
}

// Global logger instance for all files to use
public let log = Logger.shared

/// Thread-safe application logger.
///
/// Logging can be invoked from literally any thread (mouse/keyboard detection
/// callbacks, action execution, UI), so all shared state is synchronized:
///
///  * `isDebugEnabled` is guarded by a lightweight `NSLock`. The flag is read
///    on the hot detection path (`if log.isDebugEnabled { ... }`) on every
///    event, so it deliberately avoids a serial-queue hop (which would also be
///    a re-entrancy/deadlock hazard) -- an uncontended lock/unlock is a few
///    nanoseconds.
///  * The log file (`logFileURL`, its lazy creation, and every append) is
///    serialized on a private serial `ioQueue`, and writes are dispatched
///    asynchronously. This means (a) two threads can never interleave/clobber
///    a `FileHandle` append (which previously silently lost/corrupted lines
///    because each thread seeked to the same end-of-file offset), and (b) the
///    calling thread is never blocked on disk I/O -- important precisely
///    because logging fires from timing-sensitive detection callbacks.
public class Logger {
    public static let shared = Logger()

    /// How many timestamped log files to keep on disk. A new file is created
    /// each time debug logging is switched on, so without pruning they would
    /// accumulate forever in ~/Library/Logs/MouseGestures/.
    static let maxRetainedLogFiles = 10

    // Serializes all log-file I/O (creation + appends). `logFileURL` is only
    // ever touched from this queue.
    private let ioQueue = DispatchQueue(label: "com.mousegestures.logger")
    private var logFileURL: URL?
    private let dateFormatter: DateFormatter

    // Guards `_isDebugEnabled` only. Never held across the ioQueue or any file
    // I/O, so it can't deadlock and stays cheap on the hot read path.
    private let stateLock = NSLock()
    private var _isDebugEnabled: Bool = false

    /// Control logging for performance. Thread-safe.
    public var isDebugEnabled: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isDebugEnabled
        }
        set {
            stateLock.lock()
            _isDebugEnabled = newValue
            stateLock.unlock()

            // Create the log file the first time debug mode is enabled. Done on
            // the io queue so `logFileURL` is only ever touched there.
            if newValue {
                ioQueue.async { [self] in
                    if logFileURL == nil { createLogFile() }
                }
            }
        }
    }

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        // Don't create log file on init - wait until debug mode is enabled
    }

    /// Must be called on `ioQueue`.
    private func createLogFile() {
        // Create logs directory in the correct location: ~/Library/Logs/MouseGestures/
        let logsDirectory = FileManager.default.urls(for: .libraryDirectory,
                                                     in: .userDomainMask).first!
            .appendingPathComponent("Logs")
            .appendingPathComponent("MouseGestures")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: logsDirectory,
                                                withIntermediateDirectories: true)

        // Create log file with timestamp
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")

        let fileURL = logsDirectory.appendingPathComponent("MouseGestures_\(timestamp).log")
        logFileURL = fileURL

        // Write header
        let header = "MouseGestures Log - Started \(Date())\n" + String(repeating: "=", count: 50) + "\n"
        try? header.write(to: fileURL, atomically: true, encoding: .utf8)

        // Keep only the most recent N log files so they don't accumulate forever.
        pruneOldLogFiles(in: logsDirectory)
    }

    /// Deletes the oldest log files in `directory`, keeping the most recent
    /// `maxRetainedLogFiles`. Must be called on `ioQueue`.
    private func pruneOldLogFiles(in directory: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        let dated: [(url: URL, date: Date)] = contents
            .filter { $0.pathExtension == "log" }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return (url, date)
            }

        for url in Logger.logFilesToPrune(dated, keeping: Logger.maxRetainedLogFiles) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Pure retention rule: given the current log files and how many to keep,
    /// returns the ones to delete (everything older than the newest `keeping`).
    /// Factored out so the off-by-one / sort-direction logic is unit-testable
    /// without touching the filesystem.
    static func logFilesToPrune(_ files: [(url: URL, date: Date)], keeping: Int) -> [URL] {
        guard keeping >= 0, files.count > keeping else { return [] }
        return files
            .sorted { $0.date > $1.date }   // newest first
            .dropFirst(keeping)             // keep the newest `keeping`
            .map { $0.url }
    }

    public func log(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    public func verbose(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .verbose, file: file, function: function, line: line)
    }

    public func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    public func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }

    public func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }

    public func log(_ message: String, level: LogLevel, file: String = #file, function: String = #function, line: Int = #line) {
        // Cheap, race-free fast-out when debug logging is off (the common case).
        guard isDebugEnabled else { return }

        // Capture the timestamp and file name on the calling thread so they
        // reflect when the event happened, not when the async write runs.
        let now = Date()
        let fileName = URL(fileURLWithPath: file).lastPathComponent

        // All file access happens on the serial ioQueue: writes are ordered and
        // can't interleave, and the caller isn't blocked on disk I/O.
        ioQueue.async { [self] in
            // Ensure log file exists
            if logFileURL == nil {
                createLogFile()
            }

            let timestamp = dateFormatter.string(from: now)
            let logMessage = "[\(timestamp)] \(level.prefix) [\(fileName):\(line)] \(function): \(message)\n"

            // Append to file if URL exists
            if let fileURL = logFileURL, let data = logMessage.data(using: .utf8) {
                if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                } else {
                    try? logMessage.write(to: fileURL, atomically: true, encoding: .utf8)
                }
            }

            print(logMessage.trimmingCharacters(in: .newlines))
        }
    }
}
