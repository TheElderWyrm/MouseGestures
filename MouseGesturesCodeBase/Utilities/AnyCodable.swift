import Foundation

// Type-erased Codable wrapper for userInfo dictionary
public struct AnyCodable: Codable, Equatable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    /// JSON has no native binary type, so a `Data` value is wrapped as a
    /// single-key object `{tag: base64}` rather than a bare base64 string —
    /// a bare string would be indistinguishable from a real String value on
    /// decode, silently turning a `Data` parameter into a `String` one across
    /// a save/reload cycle. The tag is namespaced so it can't collide with a
    /// real user/plugin dictionary that happens to have one string-valued key.
    /// Without this case at all, `encode(to:)`'s `default: encodeNil()` was
    /// silently dropping any `Data`-valued action parameter to `null` on
    /// every save (found via BundleActionsPlugin's `conditionData`, which
    /// worked around it locally with its own base64 `String` field — this is
    /// the general fix so no other Data-valued parameter hits the same loss).
    private static let dataTagKey = "__AnyCodable.Data.base64__"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            if dictValue.count == 1,
               let base64 = dictValue[AnyCodable.dataTagKey]?.value as? String,
               let data = Data(base64Encoded: base64) {
                value = data
            } else {
                value = dictValue.mapValues { $0.value }
            }
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let dataValue as Data:
            try container.encode([AnyCodable.dataTagKey: dataValue.base64EncodedString()])
        case let dictValue as [String: Any]:
            let codableDict = dictValue.mapValues { AnyCodable($0) }
            try container.encode(codableDict)
        case let arrayValue as [Any]:
            let codableArray = arrayValue.map { AnyCodable($0) }
            try container.encode(codableArray)
        default:
            try container.encodeNil()
        }
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        return AnyCodable.equals(lhs.value, rhs.value)
    }

    /// Deep structural equality used by `==`. The previous implementation only
    /// handled scalar Int/Double/String/Bool and returned `false` for any
    /// dictionary or array — so two gestures with dict/array-valued parameters
    /// always compared unequal, triggering spurious config diffs and re-saves.
    /// This walks containers element-wise. NSNumber is coerced so that an Int 1
    /// and a Double 1.0 compare equal (JSON `1` vs `1.0` round-trip), while Bool
    /// is kept distinct from any numeric value via the CFBoolean type check.
    private static func equals(_ lhs: Any, _ rhs: Any) -> Bool {
        // Numbers AND Bools both bridge to NSNumber, so handle them together and
        // disambiguate Bool via the CFBoolean type id. This MUST come before any
        // plain `as? Bool` path: `NSNumber(1) as? Bool` succeeds (returns true),
        // so a leading Bool cast would incorrectly report a numeric 1 equal to a
        // real `true`. Here a Bool is only ever equal to another Bool, and a
        // numeric value is compared by doubleValue (Int 1 == Double 1.0).
        if let l = lhs as? NSNumber, let r = rhs as? NSNumber {
            let lIsBool = CFGetTypeID(l) == CFBooleanGetTypeID()
            let rIsBool = CFGetTypeID(r) == CFBooleanGetTypeID()
            if lIsBool != rIsBool { return false }        // one Bool, one number
            if lIsBool { return l.boolValue == r.boolValue }
            return l.doubleValue == r.doubleValue
        }
        if let l = lhs as? String, let r = rhs as? String { return l == r }
        if let l = lhs as? Data, let r = rhs as? Data { return l == r }
        if let l = lhs as? [String: Any], let r = rhs as? [String: Any] {
            guard l.count == r.count else { return false }
            for (k, lv) in l {
                guard let rv = r[k], equals(lv, rv) else { return false }
            }
            return true
        }
        if let l = lhs as? [Any], let r = rhs as? [Any] {
            guard l.count == r.count else { return false }
            for (lv, rv) in zip(l, r) where !equals(lv, rv) { return false }
            return true
        }
        // NSNull vs NSNull
        if lhs is NSNull && rhs is NSNull { return true }
        return false
    }
}
