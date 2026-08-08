import Foundation
import AppKit

// MARK: - IssueReportService
// Single-purpose service backing the in-app "Report an Issue" flow.

/// Collects the diagnostics that accompany a user-filed issue report.
///
/// The split mirrors `LicenseService`/`LicenseLogic` and `UpdateService`/`UpdateLogic`:
/// every decision about *what the report says* and *what gets scrubbed* lives in
/// the pure `IssueReportLogic` / `IssueReportRedactor` (unit-tested); this type
/// only reads live app state and the log file off disk.
///
/// Threading contract: ``gatherDiagnostics(completion:)`` must be called on the
/// main thread. The in-memory state it reads is either main-thread-owned
/// (`LicenseService`'s `@Published` properties) or queue-synchronized
/// (`Configuration`, the plugin managers), and it is all cheap. The one
/// genuinely slow part -- reading the tail of a log file -- is pushed to a
/// private queue, and the completion is delivered back on main, so opening the
/// report sheet never stalls the UI on disk I/O.
class IssueReportService {
    static let shared = IssueReportService()

    private let ioQueue = DispatchQueue(label: "com.mousegestures.issuereport", qos: .userInitiated)

    /// Most bytes read off the end of a log file before the line/byte tail rules
    /// are applied. Log files can grow large; reading the whole thing to keep
    /// 200 lines would be pointless I/O.
    private static let logReadWindowBytes = 256 * 1024

    private init() {}

    // MARK: - Public API

    /// Builds the redacted diagnostics text.
    ///
    /// - Parameter completion: called on the main thread with the finished,
    ///   already-redacted text. Never called with anything that has not been
    ///   through `IssueReportRedactor`.
    func gatherDiagnostics(completion: @escaping (String) -> Void) {
        // Snapshot the in-memory state synchronously on the caller's (main)
        // thread. Hopping to a background queue first and reading `LicenseService`
        // there would touch `@Published` storage off-main.
        let base = makeSnapshot()

        ioQueue.async {
            var snapshot = base
            let (name, contents) = Self.readNewestLogTailFromDisk()
            snapshot.logFileName = name
            snapshot.logTail = IssueReportLogic.logTail(contents)

            let text = IssueReportRedactor.redact(IssueReportLogic.diagnostics(from: snapshot))
            DispatchQueue.main.async { completion(text) }
        }
    }

    /// App version and build, used for the mail subject line.
    var versionInfo: (version: String, build: String) {
        return (Self.bundleString("CFBundleShortVersionString"), Self.bundleString("CFBundleVersion"))
    }

    // MARK: - Snapshot (main thread)

    /// Reads everything except the log file. Must be called on the main thread.
    private func makeSnapshot() -> IssueReportSnapshot {
        // One coherent read of the profile/gesture state through `configQueue`
        // -- `profiles`/`activeProfileId` are plain stored properties mutated
        // under a barrier elsewhere, so reading them directly races that writer
        // (the same reason `DebugReportService` goes through `profilesState`).
        let configuration = Configuration.shared
        let (allProfiles, activeId) = configuration.profilesState
        let activeGestures = configuration.gestures
        let activeProfileName = allProfiles.first { $0.id == activeId }?.name ?? "None"

        return IssueReportSnapshot(
            generatedAt: Date(),
            appVersion: Self.bundleString("CFBundleShortVersionString"),
            buildNumber: Self.bundleString("CFBundleVersion"),
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hardwareModel: Self.hardwareModel(),
            architecture: Self.architecture(),
            accessibilityGranted: AXIsProcessTrusted(),
            licenseState: Self.licenseState(),
            gesturesEnabled: configuration.isEnabled,
            activeProfileName: activeProfileName,
            profileCount: allProfiles.count,
            gestureCount: activeGestures.count,
            debugLoggingEnabled: log.isDebugEnabled,
            enabledPlugins: Self.enabledPlugins()
        )
    }

    // MARK: - Individual facts

    private static func bundleString(_ key: String) -> String {
        return Bundle.main.infoDictionary?[key] as? String ?? "Unknown"
    }

    /// Coarse license state only. The stored key is deliberately never read
    /// here -- it must not be able to reach a report even by accident.
    private static func licenseState() -> String {
        let service = LicenseService.shared
        switch service.status {
        case .pro:
            return "Pro"
        case .trial:
            return "Trial (\(service.trialDaysRemaining) day\(service.trialDaysRemaining == 1 ? "" : "s") remaining)"
        case .expired, .free:
            return "Free"
        }
    }

    /// Marketing-ish machine identifier, e.g. "Mac14,2".
    private static func hardwareModel() -> String {
        return sysctlString("hw.model") ?? "Unknown"
    }

    /// The architecture this process is actually running as, plus a Rosetta
    /// note when it is being translated -- a translated build behaves
    /// differently enough (event taps, timing) to be worth knowing in a report.
    private static func architecture() -> String {
        var info = utsname()
        guard uname(&info) == 0 else { return "Unknown" }
        // `withUnsafeBytes(of:)` takes a copy rather than an inout borrow --
        // reading `info.machine`'s size inside a `withUnsafePointer(to: &...)`
        // closure is an exclusivity violation and does not compile.
        let machine = withUnsafeBytes(of: info.machine) { raw -> String in
            guard let base = raw.baseAddress else { return "" }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }

        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let ok = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0
        if ok && translated == 1 {
            return "\(machine) (running under Rosetta)"
        }
        return machine.isEmpty ? "Unknown" : machine
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// Action plugins plus any enabled service plugins, as display strings.
    private static func enabledPlugins() -> [String] {
        var names: [String] = []

        for plugin in PluginManagementService.shared.getLoadedPlugins() where plugin.isEnabled {
            names.append("\(plugin.name) v\(plugin.version) (\(plugin.identifier))\(plugin.isBuiltIn ? "" : " [external]")")
        }

        for plugin in ServicePluginManager.shared.getAllPlugins() where plugin.isEnabled {
            names.append("\(plugin.name) v\(plugin.version) (\(plugin.identifier))\(plugin.isBuiltIn ? "" : " [external]")")
        }

        return names.sorted()
    }

    // MARK: - Log tail (background queue)

    /// Reads the tail of the newest log file. Must not be called on the main
    /// thread. Returns the file's *name* only -- its full path would embed the
    /// home directory.
    private static func readNewestLogTailFromDisk() -> (name: String?, contents: String) {
        guard let newest = LogFileService.shared.getLogFiles().first else { return (nil, "") }

        guard let handle = try? FileHandle(forReadingFrom: newest.url) else { return (newest.name, "") }
        defer { try? handle.close() }

        let size = newest.size
        let offset = max(0, size - Int64(logReadWindowBytes))
        if offset > 0 {
            try? handle.seek(toOffset: UInt64(offset))
        }

        let data = (try? handle.readToEnd()) ?? Data()
        guard !data.isEmpty else { return (newest.name, "") }

        // A window read from the middle of the file can start mid-codepoint;
        // decode leniently rather than dropping the whole tail.
        let text = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        return (newest.name, text)
    }
}
