//
//  StoreKitService.swift
//  StudyAI
//
//  Manages StoreKit 2 product loading, purchase flow, and receipt validation.
//  After a successful purchase, calls the backend to update the user's tier.
//

import Foundation
import StoreKit

@MainActor
class StoreKitService: ObservableObject {
    static let shared = StoreKitService()

    // Product IDs must match App Store Connect + StudyAI.storekit local config
    let productIDs = ["com.studyai.premium.monthly", "com.studyai.ultra.monthly"]

    @Published var products: [Product] = []
    @Published var purchaseInProgress = false
    @Published var purchaseError: String?

    private var transactionListenerTask: Task<Void, Never>?

    private init() {
        transactionListenerTask = listenForTransactions()
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: productIDs)
            // Sort so premium comes before ultra in UI
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            print("❌ [StoreKit] Failed to load products: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        guard !purchaseInProgress else { return }
        purchaseInProgress = true
        purchaseError = nil
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await handlePurchasedTransaction(transaction, productId: product.id)
                await transaction.finish()

            case .pending:
                // Awaiting approval (e.g. Ask to Buy) — tier will update via listener
                break

            case .userCancelled:
                break

            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
            print("❌ [StoreKit] Purchase error: \(error)")
        }
    }

    // MARK: - Restore Purchases (App Store guidelines requirement)

    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            print("❌ [StoreKit] Restore error: \(error)")
        }
    }

    // MARK: - Transaction Listener (handles renewals, deferred purchases)

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await verification in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try self.checkVerified(verification)
                    await self.handlePurchasedTransaction(transaction, productId: transaction.productID)
                    await transaction.finish()
                } catch {
                    print("❌ [StoreKit] Unverified transaction: \(error)")
                }
            }
        }
    }

    // MARK: - Verify + send receipt to backend

    private func handlePurchasedTransaction(_ transaction: Transaction, productId: String) async {
        // Build expiry from transaction
        let expiresDateMs = transaction.expirationDate.map { Int64($0.timeIntervalSince1970 * 1000) }

        let result = await NetworkService.shared.validateReceipt(
            transactionId: String(transaction.id),
            originalTransactionId: String(transaction.originalID),
            productId: productId,
            expiresDateMs: expiresDateMs
        )

        if result.success, let tier = result.tier {
            // Update Keychain and in-memory user
            updateLocalUserTier(tier)
            print("✅ [StoreKit] Tier updated to \(tier)")
        } else {
            print("⚠️ [StoreKit] Backend receipt validation failed: \(result.error ?? "unknown")")
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Update local user tier after purchase

    private func updateLocalUserTier(_ tierString: String) {
        guard let user = AuthenticationService.shared.currentUser,
              let newTier = UserTier(rawValue: tierString) else { return }

        let updated = User(
            id: user.id,
            email: user.email,
            name: user.name,
            profileImageURL: user.profileImageURL,
            authProvider: user.authProvider,
            createdAt: user.createdAt,
            lastLoginAt: user.lastLoginAt,
            tier: newTier,
            isAnonymous: user.isAnonymous
        )

        AuthenticationService.shared.currentUser = updated
        try? KeychainService.shared.saveUser(updated)
    }
}
