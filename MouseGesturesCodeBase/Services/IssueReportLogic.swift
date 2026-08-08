import Foundation

// MARK: - Snapshot

/// Everything the in-app issue report says about this install, as plain data.
///
/// Deliberately a value type with no references to services, so the report text
/// can be composed (and asserted on) without touching Configuration, the
/// license service, the plugin managers, or the filesystem.
///
/// Note what is *absent*: the license key. `licenseState` carries only the
/// coarse state ("Free" / "Trial (12 days remaining)" / "Pro"). The key is never
/// read into a report in the first place — `IssueReportRedactor` scrubbing keys
/// out of the log tail is a second line of defence, not the only one.
public struct IssueReportSnapshot: Equatable {
    public var generatedAt: Date
    public var appVersion: String
    public var buildNumber: String
    public var macOSVersion: String
    public var hardwareModel: String
    public var architecture: String
    public var accessibilityGranted: Bool
    public var licenseState: String
    public var gesturesEnabled: Bool
    public var activeProfileName: String
    public var profileCount: Int
    public var gestureCount: Int
    public var debugLoggingEnabled: Bool
    public var enabledPlugins: [String]
    /// File name only — never the full path, which would embed the home directory.
    public var logFileName: String?
    public var logTail: String

    public init(generatedAt: Date = Date(),
                appVersion: String = "Unknown",
                buildNumber: String = "Unknown",
                macOSVersion: String = "Unknown",
                hardwareModel: String = "Unknown",
                architecture: String = "Unknown",
                accessibilityGranted: Bool = false,
                licenseState: String = "Unknown",
                gesturesEnabled: Bool = false,
                activeProfileName: String = "None",
                profileCount: Int = 0,
                gestureCount: Int = 0,
                debugLoggingEnabled: Bool = false,
                enabledPlugins: [String] = [],
                logFileName: String? = nil,
                logTail: String = "") {
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.macOSVersion = macOSVersion
        self.hardwareModel = hardwareModel
        self.architecture = architecture
        self.accessibilityGranted = accessibilityGranted
        self.licenseState = licenseState
        self.gesturesEnabled = gesturesEnabled
        self.activeProfileName = activeProfileName
        self.profileCount = profileCount
        self.gestureCount = gestureCount
        self.debugLoggingEnabled = debugLoggingEnabled
        self.enabledPlugins = enabledPlugins
        self.logFileName = logFileName
        self.logTail = logTail
    }
}

// MARK: - Mail composition result

/// The outcome of turning a report into a `mailto:` URL.
public struct IssueReportMail: Equatable {
    /// The `mailto:` URL string, already percent-encoded.
    public let urlString: String
    /// True when the report was too long to survive a `mailto:` URL and the
    /// caller must put the full report on the clipboard instead (the body then
    /// tells the user to paste it).
    public let needsClipboardFallback: Bool

    public init(urlString: String, needsClipboardFallback: Bool) {
        self.urlString = urlString
        self.needsClipboardFallback = needsClipboardFallback
    }
}

// MARK: - Report logic

/// Pure, dependency-free rules for building the in-app issue report.
///
/// This is the single source of truth for the report's text layout, the log
/// tail bound, and `mailto:` URL construction. It deliberately depends on
/// nothing but `Foundation` (no AppKit, filesystem, Configuration, or license
/// service), so it can be unit-tested in isolation — the same split
/// `LicenseLogic`/`LicenseService` and `UpdateLogic`/`UpdateService` use.
/// `IssueReportService` wires these rules to the live app state and disk.
public enum IssueReportLogic {

    /// The advertised support address. Kept in one place so the menu, the
    /// report sheet, and `LicenseSettingsView`'s activation-error copy can't
    /// drift apart.
    public static let supportEmail = "support@mousegestures.app"

    /// Most lines of the app's own log to include.
    public static let logTailMaxLines = 200

    /// Hard byte ceiling on the log tail, applied after the line limit. A single
    /// pathological log line can be far longer than a normal one, so the line
    /// count alone is not a bound on report size.
    public static let logTailMaxBytes = 16_000

    /// Conservative ceiling on a `mailto:` URL. The spec sets no limit, but
    /// real handlers do: several mail clients (and the system URL machinery
    /// that hands the URL to them) silently truncate somewhere in the low
    /// thousands of characters, which would ship a half-report. Anything above
    /// this goes to the clipboard instead, where nothing can truncate it.
    public static let mailtoLengthLimit = 1800

    // MARK: - Log tail

    /// Returns at most `maxLines` trailing lines of `contents`, additionally
    /// capped at `maxBytes` of UTF-8, newest-biased (the end of the log is the
    /// part describing the failure). Prefixes a marker when anything was
    /// dropped so the reader knows the log is partial.
    public static func logTail(_ contents: String,
                               maxLines: Int = logTailMaxLines,
                               maxBytes: Int = logTailMaxBytes) -> String {
        guard maxLines > 0, maxBytes > 0 else { return "" }

        var lines = contents.components(separatedBy: "\n")
        // A trailing newline yields a final empty component that isn't a line.
        if lines.last == "" { lines.removeLast() }
        guard !lines.isEmpty else { return "" }

        var kept: [String] = []
        var bytes = 0
        for line in lines.reversed() {
            if kept.count >= maxLines { break }
            let cost = line.utf8.count + 1  // +1 for the joining newline
            if bytes + cost > maxBytes && !kept.isEmpty { break }
            kept.append(line)
            bytes += cost
        }

        let omitted = lines.count - kept.count
        var out = kept.reversed().joined(separator: "\n")

        // A single line can still blow the byte budget (nothing was kept yet,
        // so the loop above admitted it unconditionally). Clamp it from the
        // front, dropping whole Characters so the result stays valid UTF-8.
        while out.utf8.count > maxBytes && !out.isEmpty {
            out.removeFirst(max(1, out.count / 8))
        }

        if omitted > 0 {
            out = "… \(omitted) earlier log line\(omitted == 1 ? "" : "s") omitted …\n" + out
        }
        return out
    }

    // MARK: - Report text

    /// Renders the technical half of the report. Callers are expected to run
    /// the result through ``IssueReportRedactor`` before showing or sending it.
    public static func diagnostics(from snapshot: IssueReportSnapshot) -> String {
        var out = "=== MouseGestures Diagnostics ===\n"
        out += "Generated: \(timestampFormatter.string(from: snapshot.generatedAt))\n"
        out += "App Version: \(snapshot.appVersion) (\(snapshot.buildNumber))\n"
        out += "macOS: \(snapshot.macOSVersion)\n"
        out += "Mac Model: \(snapshot.hardwareModel)\n"
        out += "Architecture: \(snapshot.architecture)\n"
        out += "Accessibility Permission: \(snapshot.accessibilityGranted ? "Granted" : "Not granted")\n"
        out += "License: \(snapshot.licenseState)\n"
        out += "Gestures Enabled: \(snapshot.gesturesEnabled ? "Yes" : "No")\n"
        out += "Active Profile: \(snapshot.activeProfileName)\n"
        out += "Profiles: \(snapshot.profileCount)\n"
        out += "Gestures in Active Profile: \(snapshot.gestureCount)\n"
        out += "Debug Logging: \(snapshot.debugLoggingEnabled ? "On" : "Off")\n"

        out += "\n--- Enabled Plugins (\(snapshot.enabledPlugins.count)) ---\n"
        if snapshot.enabledPlugins.isEmpty {
            out += "(none)\n"
        } else {
            for plugin in snapshot.enabledPlugins {
                out += "- \(plugin)\n"
            }
        }

        if let name = snapshot.logFileName, !snapshot.logTail.isEmpty {
            out += "\n--- Log (\(name), last \(logTailMaxLines) lines) ---\n"
            out += snapshot.logTail
            if !snapshot.logTail.hasSuffix("\n") { out += "\n" }
        } else {
            out += "\n--- Log ---\n"
            out += "(No log available. MouseGestures only writes a log file while Debug Logging is on.)\n"
        }

        return out
    }

    /// Assembles the complete report exactly as it will be copied, saved, or
    /// mailed. The sheet shows this string verbatim — there is deliberately no
    /// second, different rendering for the "sent" path, so what the user
    /// reviews is what leaves the machine.
    public static func fullReport(description: String, diagnostics: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = "MouseGestures — Issue Report\n\n"
        out += "--- What happened ---\n"
        out += trimmed.isEmpty ? "(No description provided.)\n" : trimmed + "\n"
        out += "\n"
        out += diagnostics
        return out
    }

    /// Subject line for the support email.
    public static func mailSubject(appVersion: String, buildNumber: String) -> String {
        return "MouseGestures Issue Report — \(appVersion) (\(buildNumber))"
    }

    // MARK: - mailto:

    /// Builds a `mailto:` URL for the report, falling back to a short
    /// "it's on your clipboard" body when the full report would exceed
    /// ``mailtoLengthLimit``.
    public static func composeMail(to recipient: String = supportEmail,
                                   subject: String,
                                   description: String,
                                   diagnostics: String,
                                   limit: Int = mailtoLengthLimit) -> IssueReportMail {
        let full = fullReport(description: description, diagnostics: diagnostics)
        let fullURL = mailtoURLString(to: recipient, subject: subject, body: full)
        if fullURL.count <= limit {
            return IssueReportMail(urlString: fullURL, needsClipboardFallback: false)
        }

        // Too long: send the user's own words plus an instruction, and let the
        // caller put the full report on the clipboard.
        var short = shortBody(description: description)
        var shortURL = mailtoURLString(to: recipient, subject: subject, body: short)
        if shortURL.count > limit {
            // Pathological: the description alone overflows. Trim it until the
            // URL fits so we still open a usable draft.
            var truncatedDescription = description
            while shortURL.count > limit && !truncatedDescription.isEmpty {
                truncatedDescription.removeLast(max(1, truncatedDescription.count / 8))
                short = shortBody(description: truncatedDescription + "…")
                shortURL = mailtoURLString(to: recipient, subject: subject, body: short)
            }
        }
        return IssueReportMail(urlString: shortURL, needsClipboardFallback: true)
    }

    /// The body used when the full report can't ride along in the URL.
    public static func shortBody(description: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = "MouseGestures — Issue Report\n\n"
        out += "--- What happened ---\n"
        out += trimmed.isEmpty ? "(No description provided.)\n" : trimmed + "\n"
        out += "\n"
        out += "The diagnostics were too long to fit in this link, so they have been\n"
        out += "copied to your clipboard. Please paste them below this line (Cmd-V)\n"
        out += "before sending — they're what makes the report useful.\n"
        out += "\n"
        out += "----------------------------------------------------------------\n"
        return out
    }

    /// Percent-encodes a `mailto:` URL. Everything outside the RFC 3986
    /// unreserved set is escaped — including `&`, `?`, `=`, `+`, spaces and
    /// newlines — so a report containing any of them can't terminate the query
    /// early or be reinterpreted as extra headers.
    public static func mailtoURLString(to recipient: String, subject: String, body: String) -> String {
        let to = recipient.addingPercentEncoding(withAllowedCharacters: unreserved) ?? recipient
        let s = subject.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        let b = body.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        return "mailto:\(to)?subject=\(s)&body=\(b)"
    }

    /// A filename for "Save to File…" that sorts sensibly and contains no
    /// user-identifying text.
    public static func suggestedFileName(for date: Date = Date()) -> String {
        return "MouseGestures_Issue_Report_\(fileNameFormatter.string(from: date)).txt"
    }

    // MARK: - Formatters

    /// Fixed locale/timezone so the report reads the same everywhere and the
    /// composition rules stay deterministic under test.
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return f
    }()

    private static let fileNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }()

    /// RFC 3986 unreserved characters.
    private static let unreserved: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        set.insert(charactersIn: "0123456789")
        set.insert(charactersIn: "-._~")
        return set
    }()
}

// MARK: - Redaction

/// Pure scrubbing of personally identifying and secret material from a report.
///
/// Treated as a correctness requirement rather than a nicety: the report is
/// composed automatically and mailed to a stranger, so anything the app happens
/// to have logged travels with it. The app's log lines carry file paths and
/// application names, and a support-issued license key is a plausible thing for
/// a user to have pasted somewhere that ends up quoted back.
///
/// Rules are applied in a fixed order (see ``redact(_:homeDirectory:userName:)``)
/// because several of them would otherwise chew up each other's replacement
/// markers. Everything here is pure `Foundation` string work so it is directly
/// unit-testable; `IssueReportService` never renders a report without running
/// it through this first.
public enum IssueReportRedactor {

    public static let userPlaceholder = "<user>"
    public static let redactedPlaceholder = "<redacted>"

    /// Scrubs `text`.
    ///
    /// Order matters:
    /// 1. The literal home directory becomes `~` (the most common leak, and it
    ///    contains the short user name).
    /// 2. Any other `/Users/<name>` becomes `/Users/<user>` (covers other
    ///    accounts and paths built from a stale home directory).
    /// 3. `/var/folders/...` temp paths become opaque.
    /// 4. Labelled secrets (`licenseKey: ...`, `token=...`, `password: ...`)
    ///    lose their value. Done *before* the shape-based rules below so those
    ///    don't half-eat the value and leave a mangled fragment behind.
    /// 5. MouseGestures' own `MGPRO…` license keys.
    /// 6. UUIDs — a Lemon Squeezy license key *is* a UUID, and there is no way
    ///    to tell one from a profile id by looking, so all of them go.
    /// 7. Any remaining long mixed-case/digit token (defence in depth against
    ///    key shapes that don't exist yet).
    /// 8. Email addresses.
    /// 9. IPv4 addresses.
    /// 10. The bare short user name, last — by now it should only survive
    ///    outside of a path (e.g. an app's window title).
    public static func redact(_ text: String,
                              homeDirectory: String = NSHomeDirectory(),
                              userName: String = NSUserName()) -> String {
        var out = text

        // 1. Literal home directory -> ~
        let home = normalizedHome(homeDirectory)
        if !home.isEmpty {
            out = out.replacingOccurrences(of: home, with: "~")
        }

        // 2. Any other /Users/<name>. The character class excludes "<" so the
        //    "/Users/<user>" this rule writes can never be re-matched.
        out = replacing(out, #"/Users/[^/\s"'<>,;:)\]}]+"#, with: "/Users/" + userPlaceholder)

        // 3. Per-user temporary directories.
        out = replacing(out, #"(/private)?/var/folders/[A-Za-z0-9_+/\-]+"#, with: "/var/folders/" + redactedPlaceholder)

        // 4. Labelled secrets: keep the label, drop the value.
        out = replacing(out,
                        #"(?i)\b(licen[cs]e[ _-]?key|api[ _-]?key|access[ _-]?token|auth[ _-]?token|token|secret|password|passwd|pwd)\b\s*[:=]\s*[^\s,;)"']+"#,
                        with: "$1: " + redactedPlaceholder)

        // 5. This app's own offline license keys (see LicenseKey.swift).
        out = replacing(out, #"(?i)\bMGPRO[A-Z0-9]{6,}\b"#, with: "<redacted-license-key>")
        // ...and the dash-grouped display form (MGPRO-ABCDE-12345-…).
        out = replacing(out, #"(?i)\bMGPRO(-[A-Z0-9]{1,5}){2,}\b"#, with: "<redacted-license-key>")

        // 6. UUIDs (Lemon Squeezy license keys, profile ids, gesture ids).
        out = replacing(out,
                        #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#,
                        with: "<redacted-id>")

        // 7. Long tokens that mix letters and digits. "-" is deliberately not in
        //    the character class: it would swallow ordinary things like
        //    timestamped log file names for no security benefit, since every
        //    key format this app actually issues is handled above.
        out = replacing(out,
                        #"\b(?=[A-Za-z0-9+/_=]*[A-Za-z])(?=[A-Za-z0-9+/_=]*[0-9])[A-Za-z0-9+/_=]{24,}\b"#,
                        with: redactedPlaceholder)

        // 8. Email addresses.
        out = replacing(out, #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, with: "<redacted-email>")

        // 9. IPv4 addresses.
        out = replacing(out, #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, with: "<redacted-ip>")

        // 10. Bare short user name. Skipped for very short names, where a
        //     word-boundary match would hit ordinary English far more often
        //     than it would hit the user.
        let trimmedUser = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUser.count >= 3 {
            let escaped = NSRegularExpression.escapedPattern(for: trimmedUser)
            out = replacing(out, #"(?i)\b"# + escaped + #"\b"#, with: userPlaceholder)
        }

        return out
    }

    /// True when `text` still contains anything this redactor is supposed to
    /// remove. Used by the tests as an executable assertion that the rules
    /// actually bite, rather than eyeballing the output.
    public static func containsSensitiveMaterial(_ text: String,
                                                 homeDirectory: String = NSHomeDirectory(),
                                                 userName: String = NSUserName()) -> Bool {
        let home = normalizedHome(homeDirectory)
        if !home.isEmpty && text.contains(home) { return true }
        let trimmedUser = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUser.count >= 3 && matches(text, #"(?i)\b"# + NSRegularExpression.escapedPattern(for: trimmedUser) + #"\b"#) {
            return true
        }
        if matches(text, #"(?i)\bMGPRO[A-Z0-9]{6,}\b"#) { return true }
        if matches(text, #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b"#) { return true }
        if matches(text, #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#) { return true }
        return false
    }

    // MARK: - Helpers

    private static func normalizedHome(_ homeDirectory: String) -> String {
        var home = homeDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        while home.count > 1 && home.hasSuffix("/") { home.removeLast() }
        // "/" alone would rewrite every absolute path in the report to "~".
        return home == "/" ? "" : home
    }

    private static func replacing(_ text: String, _ pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text,
                                              options: [],
                                              range: NSRange(text.startIndex..., in: text),
                                              withTemplate: template)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }
}
