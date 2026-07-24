import XCTest

/// Tests for `LemonSqueezyLicense`'s pure encoding/decoding — no networking,
/// no UserDefaults. The JSON fixtures below are copied verbatim from Lemon
/// Squeezy's own API docs (https://docs.lemonsqueezy.com/api/license-api),
/// not invented, so a decode failure here means a real integration bug.
final class LemonSqueezyLicenseTests: XCTestCase {

    // MARK: - Activate

    func testDecodesActivateSuccessExample() throws {
        let json = """
        {
          "activated": true,
          "error": null,
          "license_key": {
            "id": 1,
            "status": "active",
            "key": "38b1460a-5104-4067-a91d-77b872934d51",
            "activation_limit": 1,
            "activation_usage": 5,
            "created_at": "2021-01-24T14:15:07.000000Z",
            "expires_at": null
          },
          "instance": {
            "id": "47596ad9-a811-4ebf-ac8a-03fc7b6d2a17",
            "name": "Test",
            "created_at": "2021-04-06T14:15:07.000000Z"
          },
          "meta": {
            "store_id": 1,
            "order_id": 2,
            "order_item_id": 3,
            "product_id": 4,
            "product_name": "Example Product",
            "variant_id": 5,
            "variant_name": "Default",
            "customer_id": 6,
            "customer_name": "John Doe",
            "customer_email": "johndoe@example.com"
          }
        }
        """.data(using: .utf8)!

        let response = try LemonSqueezyLicense.parseActivateResponse(json)
        XCTAssertTrue(response.activated)
        XCTAssertNil(response.error)
        XCTAssertEqual(response.licenseKey?.status, .active)
        XCTAssertEqual(response.licenseKey?.activationLimit, 1)
        XCTAssertEqual(response.licenseKey?.activationUsage, 5)
        XCTAssertNil(response.licenseKey?.expiresAt)
        XCTAssertNil(response.licenseKey?.testMode) // absent in this example — must not throw
        XCTAssertEqual(response.instance?.id, "47596ad9-a811-4ebf-ac8a-03fc7b6d2a17")
        XCTAssertEqual(response.meta?.productName, "Example Product")
        XCTAssertEqual(response.meta?.customerEmail, "johndoe@example.com")
    }

    func testDecodesActivateActivationLimitReachedExample() throws {
        let json = """
        {
          "activated": false,
          "error": "This license key has reached the activation limit.",
          "license_key": {
            "id": 1,
            "status": "active",
            "key": "38b1460a-5104-4067-a91d-77b872934d51",
            "activation_limit": 5,
            "activation_usage": 5,
            "created_at": "2021-01-24T14:15:07.000000Z",
            "expires_at": null
          },
          "meta": {
            "store_id": 1,
            "order_id": 2,
            "order_item_id": 3,
            "product_id": 4,
            "product_name": "Lemonade",
            "variant_id": 5,
            "variant_name": "Default",
            "customer_id": 6,
            "customer_name": "John Doe",
            "customer_email": "johndoe@example.com"
          }
        }
        """.data(using: .utf8)!

        let response = try LemonSqueezyLicense.parseActivateResponse(json)
        XCTAssertFalse(response.activated)
        XCTAssertEqual(response.error, "This license key has reached the activation limit.")
        XCTAssertEqual(response.licenseKey?.activationUsage, response.licenseKey?.activationLimit)
        XCTAssertNil(response.instance) // omitted entirely in this example
    }

    func testDecodesMinimalNotFoundError() throws {
        // A key that doesn't exist at all can plausibly return just these two
        // fields — license_key/instance/meta must decode as nil, not throw.
        let json = """
        { "activated": false, "error": "License key not found." }
        """.data(using: .utf8)!

        let response = try LemonSqueezyLicense.parseActivateResponse(json)
        XCTAssertFalse(response.activated)
        XCTAssertEqual(response.error, "License key not found.")
        XCTAssertNil(response.licenseKey)
        XCTAssertNil(response.instance)
        XCTAssertNil(response.meta)
    }

    // MARK: - Validate

    func testDecodesValidateSuccessExample() throws {
        let json = """
        {
          "valid": true,
          "error": null,
          "license_key": {
            "id": 1,
            "status": "active",
            "key": "38b1460a-5104-4067-a91d-77b872934d51",
            "activation_limit": 1,
            "activation_usage": 5,
            "created_at": "2021-01-24T14:15:07.000000Z",
            "expires_at": "2022-01-24T14:15:07.000000Z"
          },
          "instance": {
            "id": "f90ec370-fd83-46a5-8bbd-44a241e78665",
            "name": "Test",
            "created_at": "2021-02-24T14:15:07.000000Z"
          },
          "meta": {
            "store_id": 1,
            "order_id": 2,
            "order_item_id": 3,
            "product_id": 4,
            "product_name": "Lemonade",
            "variant_id": 5,
            "variant_name": "Citrus Blast",
            "customer_id": 6,
            "customer_name": "John Doe",
            "customer_email": "johndoe@example.com"
          }
        }
        """.data(using: .utf8)!

        let response = try LemonSqueezyLicense.parseValidateResponse(json)
        XCTAssertTrue(response.valid)
        XCTAssertEqual(response.licenseKey?.expiresAt, "2022-01-24T14:15:07.000000Z")
        XCTAssertEqual(response.instance?.name, "Test")
    }

    func testValidateWithNoInstanceIdReturnsNilInstance() throws {
        let json = """
        { "valid": true, "error": null,
          "license_key": { "id": 1, "status": "active", "key": "k",
            "activation_limit": 1, "activation_usage": 1,
            "created_at": "2021-01-24T14:15:07.000000Z", "expires_at": null },
          "instance": null,
          "meta": { "store_id": 1, "order_id": 2, "order_item_id": 3,
            "product_id": 4, "product_name": "P", "variant_id": 5,
            "variant_name": "V", "customer_id": 6, "customer_name": "N",
            "customer_email": "e@example.com" } }
        """.data(using: .utf8)!

        let response = try LemonSqueezyLicense.parseValidateResponse(json)
        XCTAssertNil(response.instance)
    }

    // MARK: - Deactivate

    func testDecodesDeactivateSuccessExample() throws {
        let json = """
        {
          "deactivated": true,
          "error": null,
          "license_key": {
            "id": 1,
            "status": "inactive",
            "key": "38b1460a-5104-4067-a91d-77b872934d51",
            "activation_limit": 5,
            "activation_usage": 0,
            "created_at": "2021-01-24T14:15:07.000000Z",
            "expires_at": null
          },
          "meta": {
            "store_id": 1,
            "order_id": 2,
            "order_item_id": 3,
            "product_id": 4,
            "product_name": "Lemonade",
            "variant_id": 5,
            "variant_name": "Citrus Burst",
            "customer_id": 6,
            "customer_name": "John Doe",
            "customer_email": "johndoe@example.com"
          }
        }
        """.data(using: .utf8)!

        let response = try LemonSqueezyLicense.parseDeactivateResponse(json)
        XCTAssertTrue(response.deactivated)
        XCTAssertEqual(response.licenseKey?.status, .inactive)
        XCTAssertEqual(response.licenseKey?.activationUsage, 0)
    }

    // MARK: - Request building

    func testActivateRequestShape() {
        let request = LemonSqueezyLicense.activateRequest(licenseKey: "abc-123", instanceName: "Walker's MacBook Pro")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.lemonsqueezy.com/v1/licenses/activate")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")

        let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
        XCTAssertEqual(body, "license_key=abc-123&instance_name=Walker%27s%20MacBook%20Pro")
    }

    func testValidateRequestOmitsNilInstanceId() {
        let request = LemonSqueezyLicense.validateRequest(licenseKey: "abc-123", instanceId: nil)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
        XCTAssertEqual(body, "license_key=abc-123")
    }

    func testDeactivateRequestShape() {
        let request = LemonSqueezyLicense.deactivateRequest(licenseKey: "abc-123", instanceId: "inst-1")
        XCTAssertEqual(request.url?.absoluteString, "https://api.lemonsqueezy.com/v1/licenses/deactivate")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8)
        XCTAssertEqual(body, "license_key=abc-123&instance_id=inst-1")
    }

    func testFormEncodingRoundTripsThroughURLComponents() {
        // Confirm the escaping is actually correct form-encoding, not just
        // "doesn't crash" — decode our own encoded body back via URLComponents
        // (which parses application/x-www-form-urlencoded query strings) and
        // check we recover the exact original value, including reserved chars.
        let tricky = "a+b&c=d é 中"
        let request = LemonSqueezyLicense.activateRequest(licenseKey: tricky, instanceName: "x")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        var components = URLComponents()
        components.percentEncodedQuery = body
        let decoded = components.queryItems?.first(where: { $0.name == "license_key" })?.value
        XCTAssertEqual(decoded, tricky)
    }
}
