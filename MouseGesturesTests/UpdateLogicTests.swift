import XCTest

/// Smoke tests for the pure update-feed rules in `UpdateLogic`.
///
/// These exercise the version-compare and version.json parsing logic that
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

    func testParseFeedDecodesValidVersionJSON() throws {
        let json = """
            {
                "version": "1.0.0",
                "releaseNotes": "Initial public release.",
                "downloadURL": "https://github.com/TheElderWyrm/MouseGestures/releases/latest/download/MouseGestures.dmg"
            }
            """
        let feed = try UpdateLogic.parseFeed(Data(json.utf8))
        XCTAssertEqual(feed.version, "1.0.0")
        XCTAssertEqual(feed.releaseNotes, "Initial public release.")
        XCTAssertEqual(feed.downloadURL, "https://github.com/TheElderWyrm/MouseGestures/releases/latest/download/MouseGestures.dmg")
    }

    func testParseFeedThrowsOnMalformedJSON() {
        let malformed = Data("{ not valid json".utf8)
        XCTAssertThrowsError(try UpdateLogic.parseFeed(malformed))
    }

    func testParseFeedThrowsOnMissingRequiredField() {
        let missingVersion = Data("""
            { "releaseNotes": "notes", "downloadURL": "https://example.com/a.dmg" }
            """.utf8)
        XCTAssertThrowsError(try UpdateLogic.parseFeed(missingVersion))
    }
}
