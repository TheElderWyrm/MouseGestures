import Foundation

/// Pure request/response types and encoding/decoding for Lemon Squeezy's
/// License API (`/v1/licenses/activate|validate|deactivate`).
///
/// This is the online counterpart to `LicenseKey` (this app's own offline HMAC
/// scheme, still used for manually-issued support/comp keys): a key from a
/// real Lemon Squeezy purchase is verified once against this API at
/// activation time, and `LicenseService` caches that result locally so
/// nothing here needs to run again afterward — the app works fully offline
/// from then on.
///
/// No API key is required for these three endpoints; they're designed to be
/// called directly from a distributed client, keyed by the license key
/// itself (see https://docs.lemonsqueezy.com/api/license-api). Kept
/// dependency-free (Foundation only) so parsing/encoding can be unit-tested
/// without networking, matching `UpdateLogic`'s split from `UpdateService`.
public enum LemonSqueezyLicense {

    public static let baseURL = URL(string: "https://api.lemonsqueezy.com")!

    // MARK: - Response types

    public enum KeyStatus: String, Codable, Equatable {
        case inactive, active, expired, disabled
    }

    public struct KeyInfo: Codable, Equatable {
        public let id: Int
        public let status: KeyStatus
        public let key: String
        public let activationLimit: Int
        public let activationUsage: Int
        public let createdAt: String
        public let expiresAt: String?
        public let testMode: Bool?

        enum CodingKeys: String, CodingKey {
            case id, status, key
            case activationLimit = "activation_limit"
            case activationUsage = "activation_usage"
            case createdAt = "created_at"
            case expiresAt = "expires_at"
            case testMode = "test_mode"
        }
    }

    public struct Instance: Codable, Equatable {
        public let id: String
        public let name: String
        public let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, name
            case createdAt = "created_at"
        }
    }

    public struct Meta: Codable, Equatable {
        public let storeId: Int?
        public let orderId: Int?
        public let orderItemId: Int?
        public let productId: Int?
        public let productName: String?
        public let variantId: Int?
        public let variantName: String?
        public let customerId: Int?
        public let customerName: String?
        public let customerEmail: String?

        enum CodingKeys: String, CodingKey {
            case storeId = "store_id"
            case orderId = "order_id"
            case orderItemId = "order_item_id"
            case productId = "product_id"
            case productName = "product_name"
            case variantId = "variant_id"
            case variantName = "variant_name"
            case customerId = "customer_id"
            case customerName = "customer_name"
            case customerEmail = "customer_email"
        }
    }

    /// license_key/instance/meta are all optional: a request for a key that
    /// doesn't exist at all can return just `{"activated": false, "error": "..."}`
    /// with no further detail, so decoding must not fail on their absence.
    public struct ActivateResponse: Codable, Equatable {
        public let activated: Bool
        public let error: String?
        public let licenseKey: KeyInfo?
        public let instance: Instance?
        public let meta: Meta?

        enum CodingKeys: String, CodingKey {
            case activated, error, instance, meta
            case licenseKey = "license_key"
        }
    }

    public struct ValidateResponse: Codable, Equatable {
        public let valid: Bool
        public let error: String?
        public let licenseKey: KeyInfo?
        public let instance: Instance?
        public let meta: Meta?

        enum CodingKeys: String, CodingKey {
            case valid, error, instance, meta
            case licenseKey = "license_key"
        }
    }

    /// No `instance` field — deactivation removes the instance rather than describing it.
    public struct DeactivateResponse: Codable, Equatable {
        public let deactivated: Bool
        public let error: String?
        public let licenseKey: KeyInfo?
        public let meta: Meta?

        enum CodingKeys: String, CodingKey {
            case deactivated, error, meta
            case licenseKey = "license_key"
        }
    }

    // MARK: - Request building (pure — no I/O)

    /// Percent-encodes one `application/x-www-form-urlencoded` field value.
    /// `CharacterSet.urlQueryAllowed` alone still leaves `+`/`&`/`=` unescaped,
    /// which would corrupt a form body, so this only allows the unreserved
    /// RFC 3986 set and escapes everything else (spaces included, as `%20`).
    static func formEncode(_ value: String) -> String {
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    static func formBody(_ params: [(String, String?)]) -> Data {
        let pairs = params.compactMap { key, value -> String? in
            guard let value = value else { return nil }
            return "\(formEncode(key))=\(formEncode(value))"
        }
        return pairs.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    private static func request(path: String, params: [(String, String?)]) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(params)
        return request
    }

    public static func activateRequest(licenseKey: String, instanceName: String) -> URLRequest {
        request(path: "/v1/licenses/activate",
                params: [("license_key", licenseKey), ("instance_name", instanceName)])
    }

    public static func validateRequest(licenseKey: String, instanceId: String?) -> URLRequest {
        request(path: "/v1/licenses/validate",
                params: [("license_key", licenseKey), ("instance_id", instanceId)])
    }

    public static func deactivateRequest(licenseKey: String, instanceId: String) -> URLRequest {
        request(path: "/v1/licenses/deactivate",
                params: [("license_key", licenseKey), ("instance_id", instanceId)])
    }

    // MARK: - Response parsing (pure — no I/O)

    public static func parseActivateResponse(_ data: Data) throws -> ActivateResponse {
        try JSONDecoder().decode(ActivateResponse.self, from: data)
    }

    public static func parseValidateResponse(_ data: Data) throws -> ValidateResponse {
        try JSONDecoder().decode(ValidateResponse.self, from: data)
    }

    public static func parseDeactivateResponse(_ data: Data) throws -> DeactivateResponse {
        try JSONDecoder().decode(DeactivateResponse.self, from: data)
    }
}
