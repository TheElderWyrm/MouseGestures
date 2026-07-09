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

public class Logger {
    public static let shared = Logger()

    private var logFileURL: URL?
    private let dateFormatter: DateFormatter

    // Control logging for performance
    var isDebugEnabled: Bool = false {  // Set to true for logging
        didSet {
            if isDebugEnabled && logFileURL == nil {
                // Create log file only when debug mode is enabled
                createLogFile()
            }
        }
    }

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        // Don't create log file on init - wait until debug mode is enabled
    }

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

        logFileURL = logsDirectory.appendingPathComponent("MouseGestures_\(timestamp).log")

        // Write header
        if let fileURL = logFileURL {
            let header = "MouseGestures Log - Started \(Date())\n" + String(repeating: "=", count: 50) + "\n"
            try? header.write(to: fileURL, atomically: true, encoding: .utf8)
        }
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
        if isDebugEnabled {
            // Ensure log file exists
            if logFileURL == nil {
                createLogFile()
            }

            let timestamp = dateFormatter.string(from: Date())
            let fileName = URL(fileURLWithPath: file).lastPathComponent
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
