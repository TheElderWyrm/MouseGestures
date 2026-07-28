import XCTest

/// Smoke tests for the pure update-comparison and GitHub-release-parsing
/// rules in `UpdateLogic`.
///
/// These exercise the version-compare and release-selection logic that
/// `UpdateService` runs in production, but without URLSession / UserDefaults
/// side effects, so they are deterministic and fast.
final class UpdateLogicTests: XCTestCase {

    func testOlderCurrentVersionHasUpdateAvailable() {
        XCTAssertTrue(UpdateLogic.isUpdateAvailable(current: "1.0.0", remote: "1.1.0"))
    }

    func testSameVersionHasNoUpdateAvailable() {
        XCTAssertFalse(UpdateLogic.isUpdateAvailable(current: "1.0.0", remote: "1.0.0"))
    }

    func testNewerCurrentVersionHasNoUpdateAvailable() {
        XCTAssertFalse(UpdateLogic.isUpdateAvailable(current: "1.1.0", remote: "1.0.0"))
    }

    func testNumericComparisonHandlesMultiDigitSegments() {
        XCTAssertTrue(UpdateLogic.isUpdateAvailable(current: "1.9.0", remote: "1.10.0"))
    }

    // MARK: - Component-count-tolerant comparison (shipped false-self-update regression)
    //
    // The v1.0.0 build shipped with CFBundleShortVersionString "1.0" (2
    // components) while the GitHub release tag was "v1.0.0" -> "1.0.0" (3
    // components). A naive numeric string compare treats "1.0" as older
    // than "1.0.0" once it runs out of shared components, so the app
    // falsely offered a self-update in an infinite loop. These pin the
    // fix: mismatched component counts must still compare as equal when
    // the numeric value is the same.

    func testShortCurrentVersionMatchesLongerRemoteEquivalent() {
        XCTAssertFalse(UpdateLogic.isUpdateAvailable(current: "1.0", remote: "1.0.0"))
    }

    func testLongCurrentVersionMatchesShorterRemoteEquivalent() {
        XCTAssertFalse(UpdateLogic.isUpdateAvailable(current: "1.0.0", remote: "1.0"))
    }

    func testShortCurrentVersionDetectsRealUpgrade() {
        XCTAssertTrue(UpdateLogic.isUpdateAvailable(current: "1.0", remote: "1.1"))
    }

    func testParseGitHubReleaseDecodesValidResponse() throws {
        let json = """
            {
                "tag_name": "v1.2.3",
                "draft": false,
                "prerelease": false,
                "body": "Release notes here.",
                "assets": [
                    { "name": "MouseGestures.dmg",
                      "browser_download_url": "https://github.com/TheElderWyrm/MouseGestures/releases/download/v1.2.3/MouseGestures.dmg",
                      "size": 12345678 }
                ]
            }
            """
        let release = try UpdateLogic.parseGitHubRelease(Data(json.utf8))
        XCTAssertEqual(release.tagName, "v1.2.3")
        XCTAssertFalse(release.draft)
        XCTAssertFalse(release.prerelease)
        XCTAssertEqual(release.body, "Release notes here.")
        XCTAssertEqual(release.assets.first?.name, "MouseGestures.dmg")
    }

    func testParseGitHubReleaseThrowsOnMalformedJSON() {
        let malformed = Data("{ not valid json".utf8)
        XCTAssertThrowsError(try UpdateLogic.parseGitHubRelease(malformed))
    }

    func testParseGitHubReleaseThrowsOnMissingRequiredField() {
        let missingTag = Data("""
            { "draft": false, "prerelease": false, "assets": [] }
            """.utf8)
        XCTAssertThrowsError(try UpdateLogic.parseGitHubRelease(missingTag))
    }

    func testVersionStringStripsLeadingV() {
        XCTAssertEqual(UpdateLogic.versionString(fromTag: "v1.2.3"), "1.2.3")
        XCTAssertEqual(UpdateLogic.versionString(fromTag: "1.2.3"), "1.2.3")
    }

    func testDownloadAssetFindsDMGCaseInsensitively() {
        let release = GitHubRelease(tagName: "v1.0.0", draft: false, prerelease: false, body: nil, assets: [
            GitHubReleaseAsset(name: "checksums.txt", browserDownloadURL: "https://example.com/checksums.txt", size: 100),
            GitHubReleaseAsset(name: "MouseGestures.DMG", browserDownloadURL: "https://example.com/MouseGestures.DMG", size: 999)
        ])
        XCTAssertEqual(UpdateLogic.downloadAsset(from: release)?.name, "MouseGestures.DMG")
    }

    func testDownloadAssetReturnsNilWhenNoDMG() {
        let release = GitHubRelease(tagName: "v1.0.0", draft: false, prerelease: false, body: nil, assets: [
            GitHubReleaseAsset(name: "checksums.txt", browserDownloadURL: "https://example.com/checksums.txt", size: 100)
        ])
        XCTAssertNil(UpdateLogic.downloadAsset(from: release))
    }

    func testIsEligibleAcceptsPublishedRelease() {
        let release = GitHubRelease(tagName: "v1.0.0", draft: false, prerelease: false, body: nil, assets: [])
        XCTAssertTrue(UpdateLogic.isEligible(release))
    }

    func testIsEligibleRejectsDraft() {
        let release = GitHubRelease(tagName: "v1.0.0", draft: true, prerelease: false, body: nil, assets: [])
        XCTAssertFalse(UpdateLogic.isEligible(release))
    }

    func testIsEligibleRejectsPrerelease() {
        let release = GitHubRelease(tagName: "v1.0.0", draft: false, prerelease: true, body: nil, assets: [])
        XCTAssertFalse(UpdateLogic.isEligible(release))
    }

    // MARK: - Logger log-file retention
    //
    // `Logger.swift` (Services/) is not linked into this no-host logic
    // target, so `Logger.logFilesToPrune` itself isn't reachable here. This
    // is an exact copy of that pure retention rule (mirrors the
    // ActionParametersTests.swift "coercion-recipe copy" pattern) so the
    // off-by-one / sort-direction logic stays regression-tested without
    // needing Logger reachable from tests.
    private static func logFilesToPrune(_ files: [(url: URL, date: Date)], keeping: Int) -> [URL] {
        guard keeping >= 0, files.count > keeping else { return [] }
        return files
            .sorted { $0.date > $1.date }   // newest first
            .dropFirst(keeping)             // keep the newest `keeping`
            .map { $0.url }
    }

    /// Builds `count` (url, date) pairs, oldest first, one second apart.
    private func makeLogFiles(_ count: Int) -> [(url: URL, date: Date)] {
        (0..<count).map { i in
            (url: URL(fileURLWithPath: "/tmp/MouseGestures_\(i).log"),
             date: Date(timeIntervalSince1970: TimeInterval(i)))
        }
    }

    func testPruneKeepsAllWhenUnderLimit() {
        let files = makeLogFiles(3)
        XCTAssertTrue(Self.logFilesToPrune(files, keeping: 10).isEmpty)
    }

    func testPruneKeepsAllWhenExactlyAtLimit() {
        let files = makeLogFiles(10)
        XCTAssertTrue(Self.logFilesToPrune(files, keeping: 10).isEmpty)
    }

    func testPruneDeletesOldestBeyondLimit() {
        // 12 files, keep newest 10 -> the two oldest (indices 0 and 1) go.
        let files = makeLogFiles(12)
        let toDelete = Self.logFilesToPrune(files, keeping: 10)
        XCTAssertEqual(Set(toDelete), Set([
            URL(fileURLWithPath: "/tmp/MouseGestures_0.log"),
            URL(fileURLWithPath: "/tmp/MouseGestures_1.log")
        ]))
    }

    func testPruneIgnoresInputOrderAndDeletesByDate() {
        // Same set, shuffled: the decision must be date-driven, not order-driven.
        let files = makeLogFiles(12).shuffled()
        let toDelete = Self.logFilesToPrune(files, keeping: 10)
        XCTAssertEqual(Set(toDelete), Set([
            URL(fileURLWithPath: "/tmp/MouseGestures_0.log"),
            URL(fileURLWithPath: "/tmp/MouseGestures_1.log")
        ]))
    }

    func testPruneKeepingZeroDeletesEverything() {
        let files = makeLogFiles(4)
        XCTAssertEqual(Set(Self.logFilesToPrune(files, keeping: 0)), Set(files.map { $0.url }))
    }

    func testPruneEmptyInputDeletesNothing() {
        XCTAssertTrue(Self.logFilesToPrune([], keeping: 10).isEmpty)
    }
}
