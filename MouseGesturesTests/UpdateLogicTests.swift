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
}
