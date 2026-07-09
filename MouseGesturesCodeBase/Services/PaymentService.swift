import Foundation
import StoreKit

/// Handles In-App Purchases using StoreKit 2
public class PaymentService: ObservableObject {
    public static let shared = PaymentService()

    private let productIDs = [
        "com.mousegestures.pro.onetime",
        "com.mousegestures.pro.subscription"
    ]

    @Published public private(set) var products: [Product] = []
    @Published public private(set) var purchasedProductIDs: Set<String> = []
    @Published public private(set) var activeSubscriptionExpirationDate: Date?
    @Published public private(set) var isSubscriptionAutoRenewable: Bool = false

    private var transactionListener: Task<Void, Error>?

    private init() {
        // Listen for transactions that happen outside the app
        transactionListener = listenForTransactions()

        Task {
            // Load products and current entitlements
            await loadProducts()
            await updateCustomerProductStatus()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    /// True if the user has purchased any Pro product
    public var isProUnlocked: Bool {
        return !purchasedProductIDs.isEmpty
    }

    /// Fetches product details from the App Store
    @MainActor
    public func loadProducts() async {
        do {
            self.products = try await Product.products(for: productIDs)
            log.log("PaymentService: Successfully loaded \(products.count) products")
        } catch {
            log.log("PaymentService: Failed to load products: \(error)")
        }
    }

    /// Purchases a specific product
    public func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            // Check if the transaction is verified
            let transaction = try checkVerified(verification)

            // Update the UI with the new purchase
            await updateCustomerProductStatus()

            // Always finish the transaction
            await transaction.finish()
            return true

        case .userCancelled:
            return false

        case .pending:
            return false

        @unknown default:
            return false
        }
    }

    /// Syncs with the App Store to restore previous purchases
    public func restorePurchases() async {
        try? await AppStore.sync()
        await updateCustomerProductStatus()
    }

    /// Updates the list of currently owned products
    @MainActor
    public func updateCustomerProductStatus() async {
        var purchasedIDs: Set<String> = []
        var expirationDate: Date?
        var autoRenew: Bool = false

        // Manual override for testing
        if UserDefaults.standard.bool(forKey: "MGFootprintForcedFree") {
            self.purchasedProductIDs = []
            self.activeSubscriptionExpirationDate = nil
            self.isSubscriptionAutoRenewable = false
            return
        }

        // Iterate through all of the user's purchased products
        for await result in Transaction.currentEntitlements {
            do {
                // Check if the transaction is verified
                let transaction = try checkVerified(result)

                // Only non-consumables and subscriptions grant Pro status
                if transaction.productType == .nonConsumable || transaction.productType == .autoRenewable {
                    purchasedIDs.insert(transaction.productID)

                    if transaction.productType == .autoRenewable {
                        expirationDate = transaction.expirationDate
                        // Note: Transaction doesn't directly tell us about auto-renew state in StoreKit 2 Transaction
                        // That information is in Product.SubscriptionInfo.Status
                        // For now we assume if it's an autoRenewable transaction and not expired, it's active.
                    }
                }
            } catch {
                log.log("PaymentService: Entitlement verification failed: \(error)")
            }
        }

        // To get auto-renew status we'd need to check SubscriptionInfo.Status
        // This is a bit more complex, but let's at least get expiration date if available.

        self.purchasedProductIDs = purchasedIDs
        self.activeSubscriptionExpirationDate = expirationDate
        // We'll set autoRenew to true if we have an expiration date for now
        self.isSubscriptionAutoRenewable = expirationDate != nil
    }

    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            // Iterate through any transactions that come in through the listener
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)

                    // Update the customer's product status
                    await self.updateCustomerProductStatus()

                    // Always finish the transaction
                    await transaction.finish()
                } catch {
                    log.log("PaymentService: Transaction update verification failed: \(error)")
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        // Check if the StoreKit verification result is valid
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}

public enum StoreError: Error {
    case failedVerification
}
