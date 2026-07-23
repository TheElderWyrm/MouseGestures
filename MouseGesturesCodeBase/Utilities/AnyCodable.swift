import Foundation

// Type-erased Codable wrapper for userInfo dictionary
public struct AnyCodable: Codable, Equatable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

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
            value = dictValue.mapValues { $0.value }
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
    /// is kept distinct from numeric 1 via the CFBoolean type check.
    private static func equals(_ lhs: Any, _ rhs: Any) -> Bool {
        // Bool first (before NSNumber), so true != 1.
        if let l = lhs as? Bool, let r = rhs as? Bool { return l == r }
        // Numbers: bridge both to Double for comparison.
        if let l = lhs as? NSNumber, let r = rhs as? NSNumber {
            // Distinguish Bool from numeric — NSNumber bridged from Bool reports
            // objCType "c"; treat as Bool, not number, and only equal to another Bool.
            let lIsBool = CFGetTypeID(l) == CFBooleanGetTypeID()
            let rIsBool = CFGetTypeID(r) == CFBooleanGetTypeID()
            if lIsBool || rIsBool {
                return lIsBool && rIsBool && l.boolValue == r.boolValue
            }
            return l.doubleValue == r.doubleValue
        }
        if let l = lhs as? String, let r = rhs as? String { return l == r }
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
