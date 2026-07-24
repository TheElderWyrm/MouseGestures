import XCTest

/// Round-trip and equality smoke tests for the type-erased `AnyCodable` wrapper
/// used to persist gesture/action `userInfo` payloads.
final class AnyCodableTests: XCTestCase {

    private func roundTrip(_ value: AnyCodable) throws -> AnyCodable {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(AnyCodable.self, from: data)
    }

    func testIntRoundTrip() throws {
        let decoded = try roundTrip(AnyCodable(42))
        XCTAssertEqual(decoded.value as? Int, 42)
        XCTAssertEqual(AnyCodable(42), decoded)
    }

    func testStringRoundTrip() throws {
        let decoded = try roundTrip(AnyCodable("hello"))
        XCTAssertEqual(decoded.value as? String, "hello")
    }

    func testBoolRoundTrip() throws {
        let decoded = try roundTrip(AnyCodable(true))
        XCTAssertEqual(decoded.value as? Bool, true)
    }

    // A fractional Double is used deliberately: a whole-number Double encodes to a
    // JSON integer and would decode back as `Int` (Int is tried before Double).
    func testDoubleRoundTrip() throws {
        let decoded = try roundTrip(AnyCodable(3.5))
        XCTAssertEqual(decoded.value as? Double, 3.5)
    }

    func testDictionaryRoundTrip() throws {
        let original = AnyCodable(["name": "gesture", "count": 3] as [String: Any])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let dict = try XCTUnwrap(decoded.value as? [String: Any])
        XCTAssertEqual(dict["name"] as? String, "gesture")
        XCTAssertEqual(dict["count"] as? Int, 3)
    }

    // Data has no native JSON representation; without a dedicated case,
    // encode(to:) fell through to `encodeNil()` and silently dropped any
    // Data-valued parameter to null on every save (found via
    // BundleActionsPlugin's conditionData). It's wrapped as a tagged
    // single-key object rather than a bare base64 string so it can't decode
    // back as a plain String.
    func testDataRoundTrip() throws {
        let original = Data([0x00, 0x01, 0xFF, 0x10, 0x42])
        let decoded = try roundTrip(AnyCodable(original))
        XCTAssertEqual(decoded.value as? Data, original)
    }

    func testEmptyDataRoundTrip() throws {
        let decoded = try roundTrip(AnyCodable(Data()))
        XCTAssertEqual(decoded.value as? Data, Data())
    }

    // The tagged wrapper must not collide with an ordinary one-key dictionary
    // whose value happens to be a plain string.
    func testSingleKeyStringDictionaryIsNotMistakenForData() throws {
        let decoded = try roundTrip(AnyCodable(["name": "gesture"] as [String: Any]))
        let dict = try XCTUnwrap(decoded.value as? [String: Any])
        XCTAssertEqual(dict["name"] as? String, "gesture")
        XCTAssertNil(decoded.value as? Data)
    }

    func testArrayRoundTrip() throws {
        let original = AnyCodable([1, 2, 3] as [Any])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let arr = try XCTUnwrap(decoded.value as? [Any])
        XCTAssertEqual(arr.count, 3)
        XCTAssertEqual(arr.first as? Int, 1)
    }

    func testEqualityIsTypeAndValueSensitive() {
        XCTAssertEqual(AnyCodable(1), AnyCodable(1))
        XCTAssertNotEqual(AnyCodable(1), AnyCodable(2))
        // Different underlying types are never equal.
        XCTAssertNotEqual(AnyCodable(1), AnyCodable("1"))
    }

    // Deep equality for containers. The old `==` returned `false` for any dict
    // or array, so two gestures with dict-valued parameters always compared
    // unequal — spurious config diffs and re-saves.
    func testDictionaryEqualityIsDeep() {
        let a: [String: Any] = ["name": "g", "count": 3, "nested": ["x": 1]]
        let b: [String: Any] = ["count": 3, "name": "g", "nested": ["x": 1]]
        XCTAssertEqual(AnyCodable(a), AnyCodable(b), "Equal dicts (any key order) must be equal")
        XCTAssertNotEqual(AnyCodable(a), AnyCodable(["name": "g", "count": 4] as [String: Any]))
    }

    func testArrayEqualityIsDeep() {
        XCTAssertEqual(AnyCodable([1, 2, 3] as [Any]), AnyCodable([1, 2, 3] as [Any]))
        XCTAssertNotEqual(AnyCodable([1, 2, 3] as [Any]), AnyCodable([1, 2, 4] as [Any]))
    }

    // JSON `1` and `1.0` decode to Int and Double respectively; they should
    // compare equal numerically (avoids false diffs on round-trip).
    func testNumericEqualityAcrossIntAndDouble() {
        XCTAssertEqual(AnyCodable(1), AnyCodable(1.0))
    }

    // Bool must stay distinct from numeric 1 (don't let NSNumber bridging
    // collapse true == 1).
    func testBoolNotEqualToNumericOne() {
        XCTAssertNotEqual(AnyCodable(true), AnyCodable(1))
    }

    // Regression: a *boxed numeric* NSNumber(1) (as opposed to a Swift Int) must
    // still not equal a Bool `true`. `NSNumber(1) as? Bool` succeeds (returns
    // true), so the old equality — which cast to Bool first — reported these
    // equal. Equality must key off the CFBoolean type, not the Bool bridge.
    func testBoxedNumericOneNotEqualToBoolTrue() {
        XCTAssertNotEqual(AnyCodable(NSNumber(value: 1)), AnyCodable(true))
        XCTAssertNotEqual(AnyCodable(NSNumber(value: 0)), AnyCodable(false))
        // ...but a boxed numeric 1 still equals a plain Int 1 (numeric coercion).
        XCTAssertEqual(AnyCodable(NSNumber(value: 1)), AnyCodable(1))
    }

    // The Bool/number distinction must also hold when nested inside a container
    // (this is where gesture parameters actually live).
    func testBoolVsNumberDistinctInsideDictionary() {
        XCTAssertEqual(AnyCodable(["flag": true] as [String: Any]),
                       AnyCodable(["flag": true] as [String: Any]))
        XCTAssertNotEqual(AnyCodable(["flag": true] as [String: Any]),
                          AnyCodable(["flag": 1] as [String: Any]))
    }

    func testDataEquality() {
        XCTAssertEqual(AnyCodable(Data([1, 2, 3])), AnyCodable(Data([1, 2, 3])))
        XCTAssertNotEqual(AnyCodable(Data([1, 2, 3])), AnyCodable(Data([1, 2, 4])))
    }

    // NSNull compares equal only to another NSNull, never to a numeric/other value.
    func testNullEquality() {
        XCTAssertEqual(AnyCodable(NSNull()), AnyCodable(NSNull()))
        XCTAssertNotEqual(AnyCodable(NSNull()), AnyCodable(0))
        XCTAssertNotEqual(AnyCodable(NSNull()), AnyCodable(""))
    }
}
