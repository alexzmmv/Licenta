import StoreKit
import Observation

@Observable
final class EntitlementManager {

    static let insightsProductID = "com.gjournal.insights"

    var hasInsights: Bool = false
    var isLoading: Bool = false
    var product: Product?
    var purchaseError: String?

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
        do {
            let products = try await Product.products(for: [Self.insightsProductID])
            product = products.first
        } catch {
            AppLogger.error("[EntitlementManager] Failed to load products: \(error)")
        }
    }

    func purchase() async {
        guard let product else { return }
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    await refreshEntitlements()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
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
        } catch {
            purchaseError = "Restore failed. Please try again."
        }
    }
}
