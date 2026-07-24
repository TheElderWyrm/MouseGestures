import XCTest

/// Regression tests for the numeric coercion that `ActionParameters.number(for:)`
/// relies on.
///
/// `AnyCodable` decodes `Int` *before* `Double`, so a whole-number JSON value
/// (e.g. a repeat count of `10` or a brightness of `30`) is boxed as `Int`.
/// `number(for:)` previously did `value as? Double`, which returns `nil` for an
/// `Int`-boxed value (Swift does not bridge `Int`→`Double` through `as?`), so
/// callers silently fell back to their defaults — repeat counts always ran 3
/// times, brightness always set to 50, window-age always targeted frontmost.
///
/// These tests pin the root-cause behavior (Int-boxed whole numbers do NOT
/// bridge to Double via `as?`) and validate the coercion recipe now used by
/// `number(for:)` (Int → Double(i), plus NSNumber fallback).
final class ActionParametersNumberCoercionTests: XCTestCase {

    /// The exact coercion logic mirrored from `ActionParameters.number(for:)`.
    /// Keeping a copy here lets the no-host logic target (which does not link
    /// `ActionParameters`) still pin the behavior contract.
    private func coerce(_ any: Any?) -> Double? {
        guard let any = any else { return nil }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let f = any as? Float { return Double(f) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    private func decode(_ json: String) -> AnyCodable {
        let data = json.data(using: .utf8)!
        return try! JSONDecoder().decode(AnyCodable.self, from: data)
    }

    func testWholeNumberJSONDecodesAsIntNotDouble() {
        // This is the root cause: AnyCodable tries Int before Double.
        let v = decode("10")
        XCTAssertEqual(v.value as? Int, 10)
        XCTAssertNil(v.value as? Double, "Int-boxed value must NOT bridge to Double via as? (the bug)")
    }

    func testCoercionRecoversIntBoxedWholeNumbers() {
        // After the fix, number(for:) coerces Int → Double instead of returning nil.
        for literal in [0, 1, 5, 10, 30, 100, 255] {
            let v = decode(String(literal))
            XCTAssertEqual(coerce(v.value), Double(literal),
                          "Whole number \(literal) must coerce to \(Double(literal))")
        }
    }

    func testFractionalDoublesCoerceDirectly() {
        let v = decode("0.3")
        XCTAssertEqual(v.value as? Double, 0.3)
        XCTAssertEqual(coerce(v.value), 0.3)
    }

    func testCoercionReturnsNilForNonNumeric() {
        XCTAssertNil(coerce(decode("\"hello\"").value))
        XCTAssertNil(coerce(nil))
    }

    func testRoundTrippedDictionaryPreservesWholeNumberAsInt() {
        // The persistence path: a dict with a whole-number value survives as Int.
        let data = "{\"count\": 10, \"level\": 0.5}".data(using: .utf8)!
        let dict = try! JSONDecoder().decode([String: AnyCodable].self, from: data)
        XCTAssertEqual(dict["count"]?.value as? Int, 10)
        XCTAssertEqual(coerce(dict["count"]?.value), 10.0)
        XCTAssertEqual(coerce(dict["level"]?.value), 0.5)
    }
}

/// Regression tests for the bundle sub-action `conditionData` persistence fix in
/// `BundleActionsPlugin`.
///
/// `AnyCodable.encode(to:)` has no `Data` case, so a raw `Data` value falls
/// through to `encodeNil()`. A `BundledAction.conditionData` stored as `Data`
/// inside the persisted `[[String: Any]]` bundle blob was therefore written as
/// `null` and silently lost on the next save/reload — a sub-action's condition
/// vanished when the app restarted. The plugin now persists `conditionData` as a
/// base64 `String` (which AnyCodable *does* encode) and decodes both the Data
/// and base64-String forms. These tests pin the root cause and the fix recipe
/// using only `AnyCodable` (matching this target's no-host logic style).
final class BundleConditionDataPersistenceTests: XCTestCase {

    /// Encode a value inside a dict under "conditionData" (mirroring the real
    /// persisted bundle-blob shape), JSON round-trip it, and return the decoded
    /// value.
    private func roundTripConditionData(_ value: Any) -> Any {
        let dict: [String: AnyCodable] = ["conditionData": AnyCodable(value)]
        let data = try! JSONEncoder().encode(dict)
        let decoded = try! JSONDecoder().decode([String: AnyCodable].self, from: data)
        return decoded["conditionData"]!.value
    }

    func testRawDataConditionNowRoundTripsViaAnyCodable() {
        // AnyCodable gained native Data support this same session (see
        // AnyCodableTests.swift's dataTagKey-wrapped encoding), so the
        // original silent-drop-to-NSNull bug is now fixed at that layer too.
        // BundleActionsPlugin still persists conditionData as a base64
        // String of its own (tested below) rather than relying on this, for
        // backward compatibility with gestures.json files saved before
        // AnyCodable supported Data directly.
        let original = "cond-blob".data(using: .utf8)!
        XCTAssertEqual(roundTripConditionData(original) as? Data, original,
                      "AnyCodable now natively round-trips Data")
    }

    func testBase64StringConditionSurvivesPersist() {
        // Fix: persist as base64 String, which survives and decodes back to Data.
        let original = "cond-blob".data(using: .utf8)!
        let restored = roundTripConditionData(original.base64EncodedString())
        XCTAssertEqual((restored as? String).flatMap { Data(base64Encoded: $0) }, original,
                       "base64-String conditionData must survive persistence and decode back to Data")
    }
}