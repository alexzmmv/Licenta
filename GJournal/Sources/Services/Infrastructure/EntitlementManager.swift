import StoreKit
import Observation

@Observable
final class EntitlementManager {

    static let insightsProductID = "com.gjournal.insights"

    var hasInsights: Bool = false
    var isLoading: Bool = false
    var product: Product?
    var purchaseError: String?

    /// Set when `Product.products(for:)` fails or returns nothing. The paywall
    /// must not offer a purchase button we cannot fulfil.
    var productLoadFailed: Bool = false

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let tx) = result {
                    await tx.finish()
                    await self.refreshEntitlements()
                }
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func refreshEntitlements() async {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "bypassPaywall") {
            hasInsights = true
            return
        }
        #endif

        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.productID == Self.insightsProductID {
                found = true
                break
            }
        }
        hasInsights = found
    }

    func loadProducts() async {
        purchaseError = nil
        do {
            let products = try await Product.products(for: [Self.insightsProductID])
            product = products.first
            // An empty result is a real failure mode — a product ID that isn't
            // configured in App Store Connect returns success with no products.
            productLoadFailed = (product == nil)
            if productLoadFailed {
                AppLogger.error("[EntitlementManager] No product returned for \(Self.insightsProductID)")
            }
        } catch {
            product = nil
            productLoadFailed = true
            AppLogger.error("[EntitlementManager] Failed to load products: \(error)")
        }
    }

    func purchase() async {
        guard let product else {
            // Previously a silent no-op behind a live "Unlock Insights" button.
            purchaseError = "The store is unavailable right now. Please check your connection and try again."
            productLoadFailed = true
            return
        }
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let tx):
                    await tx.finish()
                    await refreshEntitlements()
                case .unverified(_, let error):
                    // The user has been charged but StoreKit could not verify the
                    // signature. Never finish an unverified transaction — leaving
                    // it open lets Transaction.updates retry it — but we must say
                    // something rather than returning to idle as if nothing happened.
                    AppLogger.error("[EntitlementManager] Unverified transaction: \(error)")
                    purchaseError = "We couldn't verify your purchase. If you were charged, use Restore Purchases — you won't be charged twice."
                }
            case .userCancelled:
                break
            case .pending:
                // Ask to Buy / Strong Customer Authentication: the purchase is
                // awaiting approval and will arrive later via Transaction.updates.
                purchaseError = "Your purchase is pending approval. Insights will unlock automatically once it's approved."
            @unknown default:
                purchaseError = "Something unexpected happened. Please try again."
            }
        } catch {
            AppLogger.error("[EntitlementManager] Purchase failed: \(error)")
            purchaseError = "Purchase failed. Please try again."
        }
    }

    func restore() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !hasInsights {
                // Distinguish "nothing to restore" from "restore broke" — otherwise
                // the sheet just closes and the user retries forever.
                purchaseError = "No previous purchase found for this Apple Account."
            }
        } catch {
            AppLogger.error("[EntitlementManager] Restore failed: \(error)")
            purchaseError = "Restore failed. Please try again."
        }
    }
}
