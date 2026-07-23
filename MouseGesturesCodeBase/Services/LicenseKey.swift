import Foundation
import CryptoKit

/// Offline license-key validation for the direct-distribution (non–App-Store) build.
///
/// This replaces the StoreKit in-app-purchase flow, which cannot function in a
/// notarized DMG distributed outside the App Store. It is a symmetric,
/// self-contained scheme: the app both mints and verifies keys using an embedded
/// secret, so activation works with no network and no server round-trip.
///
/// A key is `PREFIX + PAYLOAD + SIGNATURE`, where `SIGNATURE` is the leading
/// `signatureLength` hex characters of `HMAC-SHA256(secret, PREFIX + PAYLOAD)`.
/// Verification recomputes the signature over the payload and compares.
///
/// Threat model: this deters casual key-sharing, typos, and tampering. It is not
/// resistant to a determined attacker who extracts the embedded secret from the
/// binary — that would require asymmetric signing plus a licensing server, which
/// is out of scope for an offline single-binary distribution. The type is pure
/// (Foundation + CryptoKit only, no UserDefaults / UI / notifications) so it can
/// be unit-tested in the no-host logic bundle.
public enum LicenseKey {

    /// Embedded verification secret. Changing it invalidates all previously issued keys.
    static let secret = "MouseGestures-Pro-offline-license-v1"

    /// Marks a key as a MouseGestures Pro license and namespaces the HMAC input.
    static let prefix = "MGPRO"

    /// Number of leading hex signature characters carried by a key.
    static let signatureLength = 8

    /// Normalizes user input to the canonical comparison form: uppercased,
    /// with all non-alphanumeric characters (spaces, dashes, tabs) stripped.
    public static func normalize(_ raw: String) -> String {
        return raw.uppercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init)
            .reduce(into: "") { $0.append($1) }
    }

    /// The HMAC-SHA256 signature (leading `signatureLength` uppercase hex chars) for a core string.
    static func signature(for core: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(core.utf8), using: key)
        let hex = mac.map { String(format: "%02X", $0) }.joined()
        return String(hex.prefix(signatureLength))
    }

    /// Mints a valid, canonical (normalized) license key for a given seed
    /// (e.g. an order id or purchaser email). Used by tests and the key-issuing tool.
    public static func generate(seed: String) -> String {
        let core = prefix + normalize(seed)
        return core + signature(for: core)
    }

    /// Formats a canonical key into dash-separated groups of five for display
    /// (e.g. `MGPRO-ABCDE-12345-...`). Validation is format-insensitive.
    public static func format(_ key: String) -> String {
        let normalized = normalize(key)
        var groups: [String] = []
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let end = normalized.index(index, offsetBy: 5, limitedBy: normalized.endIndex) ?? normalized.endIndex
            groups.append(String(normalized[index..<end]))
            index = end
        }
        return groups.joined(separator: "-")
    }

    /// Validates a license key offline. Returns `true` only if the input is
    /// well-formed (correct prefix, non-empty payload, present signature) and the
    /// signature matches the recomputed HMAC. Whitespace and dashes are ignored.
    public static func isValid(_ raw: String) -> Bool {
        let normalized = normalize(raw)
        guard normalized.hasPrefix(prefix) else { return false }
        // Must contain the prefix, at least one payload character, and the signature.
        guard normalized.count > prefix.count + signatureLength else { return false }

        let providedSignature = String(normalized.suffix(signatureLength))
        let core = String(normalized.dropLast(signatureLength))
        let computedSignature = signature(for: core)
        // Constant-time comparison: Swift `==` on String short-circuits on the
        // first differing character, leaking how many leading bytes of the
        // signature are correct via response time. XOR-accumulate over the
        // whole signature so every byte always contributes to the result.
        return constantTimeEquals(computedSignature, providedSignature)
    }

    /// Compare two equal-length hex strings in constant time. Returns `false`
    /// immediately when the lengths differ (length is not a secret here — both
    /// sides derive from `signatureLength`, which is public).
    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aScalars = Array(a.unicodeScalars)
        let bScalars = Array(b.unicodeScalars)
        guard aScalars.count == bScalars.count else { return false }

        var diff: UInt32 = 0
        for (x, y) in zip(aScalars, bScalars) {
            diff |= x.value ^ y.value
        }
        return diff == 0
    }
}
