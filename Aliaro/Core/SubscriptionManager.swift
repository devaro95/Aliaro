import Foundation
import StoreKit

enum SubscriptionError: LocalizedError {
    case unverified
    case pending

    var errorDescription: String? {
        switch self {
        case .unverified:
            return "We couldn't verify this purchase. Please try again."
        case .pending:
            return "This purchase is awaiting approval and isn't active yet."
        }
    }
}

/// App Store product identifiers for Aliaro Premium.
enum SubscriptionProductID {
    static let monthly = "com.devaro.aliaro.premium.monthly"
    static let yearly = "com.devaro.aliaro.premium.yearly"
    static let all: [String] = [monthly, yearly]
}

/// Aliaro Premium subscription: loads the App Store products, purchases,
/// restores, and tracks the current entitlement via StoreKit 2. One
/// subscription unlocks every feature currently marked premium in
/// `PremiumConfig` — there's no per-feature purchase.
@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var products: [Product] = []
    @Published private(set) var isSubscribed = false
    @Published private(set) var isLoadingProducts = false

    /// Called every time `isSubscribed` is (re)computed — after `start()`,
    /// a purchase, a restore, or a `Transaction.updates` event — so
    /// `PremiumManager` can push the latest status up to the family group.
    var onEntitlementChanged: (() -> Void)?

    private var updatesTask: Task<Void, Never>?

    private init() {}

    var monthlyProduct: Product? { products.first { $0.id == SubscriptionProductID.monthly } }
    var yearlyProduct: Product? { products.first { $0.id == SubscriptionProductID.yearly } }

    func start() async {
        await loadProducts()
        await refreshEntitlement()
        listenForTransactionUpdates()
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: SubscriptionProductID.all)
        } catch {
            print("⚠️ Could not load subscription products (\(error))")
        }
    }

    /// - Parameter appAccountToken: the family member's id, passed through
    ///   to StoreKit so every transaction (and its renewals) carries it.
    ///   That's what lets `apple-subscription-webhook` -- which Apple calls
    ///   directly on renewal/cancellation/refund, without needing any
    ///   device to reopen the app -- know which family's
    ///   `premium_member_id` to update. No token, no family lookup: pass
    ///   it whenever the buyer has joined a family group.
    enum PurchaseOutcome { case success, cancelled }

    @discardableResult
    func purchase(_ product: Product, appAccountToken: UUID? = nil) async throws -> PurchaseOutcome {
        var options: Set<Product.PurchaseOption> = []
        if let appAccountToken {
            options.insert(.appAccountToken(appAccountToken))
        }
        let result = try await product.purchase(options: options)
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                // StoreKit couldn't verify the transaction (e.g. jailbroken
                // device, tampered receipt) -- surface this instead of
                // silently leaving the paywall open with no feedback.
                throw SubscriptionError.unverified
            }
            Track.logTransaction(transaction)
            await transaction.finish()
            await refreshEntitlement()
            return .success
        case .pending:
            // Awaiting approval (Ask to Buy, etc). Not an error, but the
            // entitlement isn't active yet, so tell the UI rather than
            // pretending the purchase finished.
            throw SubscriptionError.pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            throw SubscriptionError.unverified
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        var subscribed = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               SubscriptionProductID.all.contains(transaction.productID),
               transaction.revocationDate == nil {
                subscribed = true
            }
        }
        isSubscribed = subscribed
        onEntitlementChanged?()
        Track.refreshUserProperties()
    }

    private func listenForTransactionUpdates() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    Track.event("subscription_transaction_update", [
                        "product_id": transaction.productID,
                        "revoked": transaction.revocationDate != nil,
                        "is_upgraded": transaction.isUpgraded
                    ])
                    Track.logTransaction(transaction)
                    await transaction.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }
}
