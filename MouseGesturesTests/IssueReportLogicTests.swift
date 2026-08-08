import XCTest

/// Tests for the pure half of the in-app "Report an Issue" flow:
/// ``IssueReportRedactor`` (scrubbing) and ``IssueReportLogic`` (log tail
/// bounds, report layout, `mailto:` construction).
///
/// Redaction is the reason this logic was split out of `IssueReportService` at
/// all. The report is assembled automatically from whatever the app happened to
/// log and then mailed to a stranger, so a leak here is a real privacy bug, not
/// a cosmetic one — these tests are the thing standing between a user's home
/// path / license key and a support inbox.
///
/// Everything below is deterministic: no filesystem, no UserDefaults, no
/// AppKit. The home directory and user name are always passed explicitly so the
/// results don't depend on whoever runs the suite.
final class IssueReportLogicTests: XCTestCase {

    private let home = "/Users/testuser"
    private let user = "testuser"

    private func scrub(_ text: String) -> String {
        return IssueReportRedactor.redact(text, homeDirectory: home, userName: user)
    }

    // MARK: - Home directory / user name

    func testHomeDirectoryBecomesTilde() {
        let out = scrub("Loaded config from /Users/testuser/Library/Application Support/MouseGestures/gestures.json")
        XCTAssertTrue(out.contains("~/Library/Application Support/MouseGestures/gestures.json"), out)
        XCTAssertFalse(out.contains("/Users/testuser"), out)
    }

    func testHomeDirectoryWithTrailingSlashStillMatches() {
        let out = IssueReportRedactor.redact("path=/Users/testuser/Desktop/a.txt",
                                             homeDirectory: "/Users/testuser/",
                                             userName: user)
        XCTAssertFalse(out.contains("testuser"), out)
    }

    func testOtherUsersHomePathIsAlsoRedacted() {
        let out = scrub("Copied to /Users/someoneelse/Documents/report.txt")
        XCTAssertFalse(out.contains("someoneelse"), out)
        XCTAssertTrue(out.contains("/Users/<user>"), out)
    }

    /// The `/Users/<user>` marker the redactor writes must not itself look like
    /// another `/Users/<name>` path, or a second pass would mangle it.
    func testRedactionIsIdempotent() {
        let raw = "opened /Users/testuser/Desktop and mailed testuser@example.com from 10.0.0.4"
        let once = scrub(raw)
        XCTAssertEqual(scrub(once), once)
    }

    func testBareUserNameIsRedacted() {
        let out = scrub("Front app window title: testuser — Notes")
        XCTAssertFalse(out.lowercased().contains("testuser"), out)
        XCTAssertTrue(out.contains("<user>"), out)
    }

    func testUserNameMatchIsWholeWordOnly() {
        // "testuser" must not be clipped out of the middle of a longer token.
        let out = scrub("plugin com.example.testuserland.plugin loaded")
        XCTAssertTrue(out.contains("testuserland"), out)
    }

    func testVeryShortUserNameIsNotWordMatched() {
        // A 2-character name would carpet-bomb ordinary log text; the path
        // rules still cover the case that actually matters.
        let out = IssueReportRedactor.redact("an ax is not a user name", homeDirectory: "/Users/ax", userName: "ax")
        XCTAssertEqual(out, "an ax is not a user name")
    }

    func testRootHomeDirectoryDoesNotRewriteEveryPath() {
        // A "/" home would otherwise turn every absolute path into "~".
        let out = IssueReportRedactor.redact("/Applications/Safari.app", homeDirectory: "/", userName: "root")
        XCTAssertEqual(out, "/Applications/Safari.app")
    }

    func testTemporaryDirectoryIsRedacted() {
        let out = scrub("wrote /var/folders/2x/ab12cd34ef/T/MouseGestures/tmp.json")
        XCTAssertFalse(out.contains("ab12cd34ef"), out)
        XCTAssertTrue(out.contains("/var/folders/<redacted>"), out)
    }

    // MARK: - License keys

    func testOfflineLicenseKeyIsRedacted() {
        // Same shape LicenseKey.generate() produces: MGPRO + payload + signature.
        let out = scrub("activated key MGPROORDER12345ABCD1234 successfully")
        XCTAssertFalse(out.contains("MGPROORDER12345ABCD1234"), out)
        XCTAssertTrue(out.contains("<redacted-license-key>"), out)
    }

    func testFormattedLicenseKeyIsRedacted() {
        // LicenseKey.format() renders keys as dash-separated groups of five.
        let out = scrub("stored MGPRO-ORDER-12345-ABCD-1234 for this Mac")
        XCTAssertFalse(out.contains("ORDER"), out)
        XCTAssertTrue(out.contains("<redacted-license-key>"), out)
    }

    func testLemonSqueezyUUIDKeyIsRedacted() {
        // A Lemon Squeezy license key is a bare UUID and is indistinguishable
        // from any other UUID by shape, so all UUIDs go.
        let out = scrub("license 38b1460a-5104-4067-a91d-77b872934d51 verified")
        XCTAssertFalse(out.lowercased().contains("38b1460a"), out)
        XCTAssertTrue(out.contains("<redacted-id>"), out)
    }

    func testLabelledSecretsLoseTheirValue() {
        for line in ["licenseKey: MGPROABCDEFGH1234",
                     "license_key=hunter2trustme",
                     "token: sk_live_abcdef123456",
                     "password = correct-horse",
                     "apiKey:  ZXhhbXBsZQ"] {
            let out = scrub(line)
            XCTAssertTrue(out.contains("<redacted>"), "not redacted: \(line) -> \(out)")
        }
    }

    func testLabelledSecretKeepsItsLabel() {
        // The label is diagnostically useful; only the value is a secret.
        let out = scrub("token: sk_live_abcdef123456")
        XCTAssertTrue(out.lowercased().hasPrefix("token"), out)
        XCTAssertFalse(out.contains("sk_live_abcdef123456"), out)
    }

    func testLongMixedTokenIsRedacted() {
        let out = scrub("bearer aGVsbG8xMjM0NTY3ODkwYWJjZGVmZ2hpams=")
        XCTAssertTrue(out.contains("<redacted>"), out)
    }

    func testOrdinaryLogLineSurvivesIntact() {
        // The generic high-entropy rule must not eat normal diagnostics: log
        // file names, bundle identifiers and version strings all have to
        // survive or the report stops being readable.
        let line = "[2026-08-08 12:00:00.123] [INFO] [MenuIcon.swift:100] show(): registered com.mousegestures.core.window v1.0"
        XCTAssertEqual(scrub(line), line)
    }

    func testLogFileNameSurvivesIntact() {
        let name = "MouseGestures_2026-08-08T12-00-00Z.log"
        XCTAssertEqual(scrub(name), name)
    }

    // MARK: - Other identifiers

    func testEmailAddressIsRedacted() {
        let out = scrub("purchaser jane.doe+mg@example.co.uk")
        XCTAssertFalse(out.contains("jane.doe"), out)
        XCTAssertTrue(out.contains("<redacted-email>"), out)
    }

    func testIPv4AddressIsRedacted() {
        let out = scrub("connected from 192.168.1.42")
        XCTAssertFalse(out.contains("192.168.1.42"), out)
    }

    func testThreeComponentVersionIsNotMistakenForAnIP() {
        let out = scrub("App Version: 1.0.1 (12)")
        XCTAssertEqual(out, "App Version: 1.0.1 (12)")
    }

    // MARK: - Executable end-to-end assertion
    //
    // Rather than eyeballing individual rules, assert against a literal:
    // a report built out of every sensitive shape at once must come back with
    // none of them, checked by an independent detector.

    func testNoSensitiveMaterialSurvivesACompositeReport() {
        let raw = """
        [2026-08-08 12:00:00.001] [INFO] [Configuration.swift:12] load(): reading /Users/testuser/Library/Application Support/MouseGestures/gestures.json
        [2026-08-08 12:00:00.002] [INFO] [LicenseService.swift:99] activate(): licenseKey: MGPROORDER12345ABCD1234
        [2026-08-08 12:00:00.003] [INFO] [LicenseService.swift:120] activate(): instance 38b1460a-5104-4067-a91d-77b872934d51 for testuser@example.com
        [2026-08-08 12:00:00.004] [INFO] [MenuIcon.swift:7] show(): hello testuser
        """
        let out = scrub(raw)

        XCTAssertFalse(IssueReportRedactor.containsSensitiveMaterial(out, homeDirectory: home, userName: user),
                       "sensitive material survived redaction:\n\(out)")

        // And spot-check that the *structure* survived, so a rule that simply
        // deleted everything would still fail this test.
        XCTAssertTrue(out.contains("[LicenseService.swift:99]"), out)
        XCTAssertTrue(out.contains("~/Library/Application Support/MouseGestures/gestures.json"), out)
    }

    func testDetectorItselfFiresOnUnredactedInput() {
        // Control: the detector used above must actually be capable of failing,
        // otherwise the assertion is vacuous.
        let raw = "opened /Users/testuser/Desktop"
        XCTAssertTrue(IssueReportRedactor.containsSensitiveMaterial(raw, homeDirectory: home, userName: user))
    }

    // MARK: - Log tail

    private func makeLog(lines: Int) -> String {
        return (1...lines).map { "line \($0)" }.joined(separator: "\n") + "\n"
    }

    func testLogTailKeepsWholeLogWhenUnderLimit() {
        let log = makeLog(lines: 10)
        let tail = IssueReportLogic.logTail(log, maxLines: 200, maxBytes: 16_000)
        XCTAssertEqual(tail, "line 1\nline 2\nline 3\nline 4\nline 5\nline 6\nline 7\nline 8\nline 9\nline 10")
        XCTAssertFalse(tail.contains("omitted"), tail)
    }

    func testLogTailKeepsNewestLinesAndMarksTheDrop() {
        let tail = IssueReportLogic.logTail(makeLog(lines: 500), maxLines: 200, maxBytes: 16_000)
        let body = tail.components(separatedBy: "\n").filter { !$0.contains("omitted") }
        XCTAssertEqual(body.count, 200)
        XCTAssertEqual(body.last, "line 500")
        XCTAssertEqual(body.first, "line 301")
        XCTAssertTrue(tail.hasPrefix("… 300 earlier log lines omitted …"), tail)
    }

    func testLogTailRespectsByteCeilingEvenUnderTheLineLimit() {
        // 50 lines of 100 bytes = ~5 KB, but only 1 KB is allowed.
        let fat = (1...50).map { _ in String(repeating: "x", count: 100) }.joined(separator: "\n")
        let tail = IssueReportLogic.logTail(fat, maxLines: 200, maxBytes: 1000)
        XCTAssertLessThanOrEqual(tail.utf8.count, 1000 + 64, "byte ceiling blown: \(tail.utf8.count)")
        XCTAssertTrue(tail.contains("omitted"), tail)
    }

    func testLogTailClampsASingleOversizedLine() {
        // The line-count rule alone is not a size bound: one pathological line
        // has to be cut too.
        let monster = String(repeating: "y", count: 5000)
        let tail = IssueReportLogic.logTail(monster, maxLines: 200, maxBytes: 1000)
        XCTAssertLessThanOrEqual(tail.utf8.count, 1000)
    }

    func testLogTailOnEmptyInput() {
        XCTAssertEqual(IssueReportLogic.logTail(""), "")
        XCTAssertEqual(IssueReportLogic.logTail("\n"), "")
    }

    func testLogTailPreservesMultibyteText() {
        let tail = IssueReportLogic.logTail("héllo wörld ✓\n", maxLines: 200, maxBytes: 16_000)
        XCTAssertEqual(tail, "héllo wörld ✓")
    }

    // MARK: - Report layout

    private func sampleSnapshot() -> IssueReportSnapshot {
        return IssueReportSnapshot(
            generatedAt: Date(timeIntervalSince1970: 0),
            appVersion: "1.0.1",
            buildNumber: "12",
            macOSVersion: "Version 15.0 (Build 24A335)",
            hardwareModel: "Mac14,2",
            architecture: "arm64",
            accessibilityGranted: true,
            licenseState: "Trial (12 days remaining)",
            gesturesEnabled: true,
            activeProfileName: "Default",
            profileCount: 3,
            gestureCount: 12,
            debugLoggingEnabled: false,
            enabledPlugins: ["Window Management v1.0 (com.mousegestures.core.window)"],
            logFileName: "MouseGestures_2026-08-08.log",
            logTail: "line 1\nline 2"
        )
    }

    func testDiagnosticsIsDeterministicAcrossTimeZones() {
        // Fixed UTC formatter, so the same snapshot renders identically no
        // matter where the suite runs.
        let text = IssueReportLogic.diagnostics(from: sampleSnapshot())
        XCTAssertTrue(text.contains("Generated: 1970-01-01 00:00:00 UTC"), text)
    }

    func testDiagnosticsContainsEveryRequiredFact() {
        let text = IssueReportLogic.diagnostics(from: sampleSnapshot())
        for expected in ["App Version: 1.0.1 (12)",
                         "macOS: Version 15.0 (Build 24A335)",
                         "Mac Model: Mac14,2",
                         "Architecture: arm64",
                         "Accessibility Permission: Granted",
                         "License: Trial (12 days remaining)",
                         "Active Profile: Default",
                         "Profiles: 3",
                         "Gestures in Active Profile: 12",
                         "Window Management v1.0 (com.mousegestures.core.window)",
                         "line 2"] {
            XCTAssertTrue(text.contains(expected), "missing \(expected) in:\n\(text)")
        }
    }

    func testDiagnosticsNeverCarriesALicenseKeyField() {
        // The snapshot type has no place to put one; this pins that.
        let text = IssueReportLogic.diagnostics(from: sampleSnapshot())
        XCTAssertFalse(text.lowercased().contains("mgpro"), text)
        XCTAssertFalse(text.lowercased().contains("license key"), text)
    }

    func testDiagnosticsExplainsAMissingLog() {
        var snapshot = sampleSnapshot()
        snapshot.logFileName = nil
        snapshot.logTail = ""
        let text = IssueReportLogic.diagnostics(from: snapshot)
        XCTAssertTrue(text.contains("No log available"), text)
    }

    func testFullReportIncludesDescriptionAndDiagnostics() {
        let report = IssueReportLogic.fullReport(description: "  corner gesture stops firing  ",
                                                 diagnostics: "=== MouseGestures Diagnostics ===\n")
        XCTAssertTrue(report.contains("--- What happened ---\ncorner gesture stops firing\n"), report)
        XCTAssertTrue(report.contains("=== MouseGestures Diagnostics ==="), report)
    }

    func testFullReportMarksAnEmptyDescription() {
        let report = IssueReportLogic.fullReport(description: "   \n  ", diagnostics: "d")
        XCTAssertTrue(report.contains("(No description provided.)"), report)
    }

    // MARK: - mailto:

    func testMailtoEncodesReservedCharacters() {
        let url = IssueReportLogic.mailtoURLString(to: "support@mousegestures.app",
                                                   subject: "a&b=c",
                                                   body: "line 1\nline 2 ?&=+")
        XCTAssertTrue(url.hasPrefix("mailto:support%40mousegestures.app?subject="), url)
        // Exactly two unencoded delimiters: the "?" and the "&" this builds.
        XCTAssertEqual(url.filter { $0 == "?" }.count, 1, url)
        XCTAssertEqual(url.filter { $0 == "&" }.count, 1, url)
        XCTAssertFalse(url.contains(" "), url)
        XCTAssertFalse(url.contains("\n"), url)
    }

    func testShortReportRidesAlongInTheURL() {
        let mail = IssueReportLogic.composeMail(subject: "S", description: "it broke", diagnostics: "small")
        XCTAssertFalse(mail.needsClipboardFallback)
        XCTAssertTrue(mail.urlString.count <= IssueReportLogic.mailtoLengthLimit)
        XCTAssertNotNil(URL(string: mail.urlString))
    }

    func testLongReportFallsBackToTheClipboard() {
        // A real report with a 200-line log tail is far past any safe mailto
        // length; it must not be silently truncated by the mail client.
        let big = String(repeating: "diagnostic line\n", count: 500)
        let mail = IssueReportLogic.composeMail(subject: "S", description: "it broke", diagnostics: big)
        XCTAssertTrue(mail.needsClipboardFallback)
        XCTAssertLessThanOrEqual(mail.urlString.count, IssueReportLogic.mailtoLengthLimit)
        XCTAssertNotNil(URL(string: mail.urlString))
    }

    func testFallbackBodyStillCarriesTheUsersOwnWords() {
        let big = String(repeating: "diagnostic line\n", count: 500)
        let mail = IssueReportLogic.composeMail(subject: "S", description: "corner gesture broke", diagnostics: big)
        let decoded = mail.urlString.removingPercentEncoding ?? ""
        XCTAssertTrue(decoded.contains("corner gesture broke"), decoded)
        XCTAssertTrue(decoded.contains("copied to your clipboard"), decoded)
    }

    func testAbsurdlyLongDescriptionStillProducesAUsableURL() {
        // Pathological input: even the short body overflows. The URL must still
        // come back under the limit rather than looping or emitting a monster.
        let mail = IssueReportLogic.composeMail(subject: "S",
                                                description: String(repeating: "z", count: 50_000),
                                                diagnostics: String(repeating: "d", count: 50_000))
        XCTAssertTrue(mail.needsClipboardFallback)
        XCTAssertLessThanOrEqual(mail.urlString.count, IssueReportLogic.mailtoLengthLimit)
        XCTAssertNotNil(URL(string: mail.urlString))
    }

    func testMailSubjectCarriesTheVersion() {
        XCTAssertEqual(IssueReportLogic.mailSubject(appVersion: "1.0.1", buildNumber: "12"),
                       "MouseGestures Issue Report — 1.0.1 (12)")
    }

    func testSupportAddressMatchesTheOneAdvertisedElsewhere() {
        // LicenseSettingsView's activation-error copy and the website footer
        // both name this address; it must not drift.
        XCTAssertEqual(IssueReportLogic.supportEmail, "support@mousegestures.app")
    }

    func testSuggestedFileNameIsSortableAndAnonymous() {
        let name = IssueReportLogic.suggestedFileName(for: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(name.hasPrefix("MouseGestures_Issue_Report_"), name)
        XCTAssertTrue(name.hasSuffix(".txt"), name)
    }
}
