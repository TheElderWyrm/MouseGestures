import XCTest

/// Tests for the offline license-key validation in `LicenseKey`.
///
/// These exercise the HMAC-signed key scheme that replaced StoreKit IAP for
/// direct (non–App-Store) distribution, without any UserDefaults / UI / network
/// dependencies, so they run in the no-host logic bundle.
final class LicenseKeyTests: XCTestCase {

    func testGeneratedKeyIsValid() {
        let key = LicenseKey.generate(seed: "order-12345")
        XCTAssertTrue(LicenseKey.isValid(key))
    }

    func testGeneratedKeyCarriesProPrefix() {
        let key = LicenseKey.generate(seed: "customer@example.com")
        XCTAssertTrue(key.hasPrefix(LicenseKey.prefix))
    }

    func testValidationIgnoresDashesAndWhitespace() {
        let key = LicenseKey.generate(seed: "abc")
        let formatted = LicenseKey.format(key)
        XCTAssertTrue(formatted.contains("-"))
        XCTAssertTrue(LicenseKey.isValid(formatted))
        XCTAssertTrue(LicenseKey.isValid("  \(formatted)  "))
    }

    func testValidationIsCaseInsensitive() {
        let key = LicenseKey.generate(seed: "MixedCaseSeed")
        XCTAssertTrue(LicenseKey.isValid(key.lowercased()))
    }

    func testTamperedSignatureFails() {
        let key = LicenseKey.generate(seed: "order-999")
        // Flip the last character of the signature to a different hex digit.
        let last = key.last!
        let replacement: Character = last == "0" ? "1" : "0"
        let tampered = key.dropLast() + String(replacement)
        XCTAssertFalse(LicenseKey.isValid(String(tampered)))
    }

    func testTamperedPayloadFails() {
        // A valid key's payload can't be edited without recomputing the signature.
        let key = LicenseKey.generate(seed: "seedA")
        let core = String(key.dropLast(LicenseKey.signatureLength))
        let signature = String(key.suffix(LicenseKey.signatureLength))
        let forged = core + "X" + signature // extra payload char, stale signature
        XCTAssertFalse(LicenseKey.isValid(forged))
    }

    func testWrongPrefixFails() {
        // Same HMAC scheme but a key that does not start with the Pro prefix.
        let key = LicenseKey.generate(seed: "x")
        let withoutPrefix = String(key.dropFirst(LicenseKey.prefix.count))
        XCTAssertFalse(LicenseKey.isValid(withoutPrefix))
    }

    func testEmptyAndGarbageFail() {
        XCTAssertFalse(LicenseKey.isValid(""))
        XCTAssertFalse(LicenseKey.isValid("   "))
        XCTAssertFalse(LicenseKey.isValid("not-a-license-key"))
        XCTAssertFalse(LicenseKey.isValid(LicenseKey.prefix)) // prefix only, no payload/signature
    }

    func testPrefixPlusSignatureButNoPayloadFails() {
        // A well-formed prefix and a real-looking signature length but zero payload.
        let core = LicenseKey.prefix
        let signature = LicenseKey.signature(for: core)
        XCTAssertFalse(LicenseKey.isValid(core + signature))
    }

    func testDifferentSeedsProduceDifferentKeys() {
        let a = LicenseKey.generate(seed: "seed-a")
        let b = LicenseKey.generate(seed: "seed-b")
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(LicenseKey.isValid(a))
        XCTAssertTrue(LicenseKey.isValid(b))
    }

    func testNormalizeStripsFormatting() {
        XCTAssertEqual(LicenseKey.normalize("mgpro-abc 12"), "MGPROABC12")
    }
}
