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
}
