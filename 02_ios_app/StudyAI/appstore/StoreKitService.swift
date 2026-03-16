//
//  StoreKitService.swift
//  StudyAI
//
//  Manages StoreKit 2 product loading, purchase flow, and receipt validation.
//  After a successful purchase, calls the backend to update the user's tier.
//

import Foundation
import Combine
import StoreKit

@MainActor
class StoreKitService: ObservableObject {
    static let shared = StoreKitService()

    // Product IDs must match App Store Connect + StudyAI.storekit local config
    let productIDs = ["com.studyai.premium.monthly", "com.studyai.ultra.monthly"]

    @Published var products: [Product] = []
    @Published var purchaseInProgress = false
    @Published var purchaseError: String?

    /// DEBUG only — when true, StoreKit renewals won't overwrite the manually set tier.
    #if DEBUG
    var debugTierOverrideActive = false
    #endif

    private var transactionListenerTask: Task<Void, Never>?

    private init() {
        transactionListenerTask = listenForTransactions()
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        #if DEBUG
        print("🛒 [StoreKit] loadProducts() called — fetching IDs: \(productIDs)")
        #endif
        do {
            let fetched = try await Product.products(for: productIDs)
            #if DEBUG
            print("🛒 [StoreKit] Fetched \(fetched.count) product(s): \(fetched.map { "\($0.id) (\($0.displayPrice))" })")
            #endif
            // Sort so premium comes before ultra in UI
            products = fetched.sorted { $0.price < $1.price }
            #if DEBUG
            if fetched.isEmpty {
                print("⚠️ [StoreKit] No products returned — check App Store Connect product IDs and In-App Purchase capability")
            }
            #endif
        } catch {
            #if DEBUG
            print("❌ [StoreKit] Failed to load products: \(error)")
            #endif
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        guard !purchaseInProgress else {
            #if DEBUG
            print("⚠️ [StoreKit] Purchase already in progress, ignoring")
            #endif
            return
        }
        #if DEBUG
        print("🛒 [StoreKit] Starting purchase for: \(product.id)")
        #endif
        purchaseInProgress = true
        purchaseError = nil
        defer { purchaseInProgress = false }

        do {
            #if DEBUG
            print("🛒 [StoreKit] Calling product.purchase()...")
            #endif
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                #if DEBUG
                print("✅ [StoreKit] Purchase succeeded, verifying transaction...")
                #endif
                let transaction = try checkVerified(verification)
                #if DEBUG
                print("✅ [StoreKit] Transaction verified: id=\(transaction.id)")
                #endif
                await handlePurchasedTransaction(transaction, productId: product.id)
                await transaction.finish()
                #if DEBUG
                print("✅ [StoreKit] Transaction finished")
                #endif

            case .pending:
                #if DEBUG
                print("⏳ [StoreKit] Purchase pending (Ask to Buy)")
                #endif

            case .userCancelled:
                #if DEBUG
                print("🚫 [StoreKit] User cancelled purchase")
                #endif

            @unknown default:
                #if DEBUG
                print("⚠️ [StoreKit] Unknown purchase result")
                #endif
            }
        } catch {
            purchaseError = error.localizedDescription
            #if DEBUG
            print("❌ [StoreKit] Purchase error: \(error)")
            #endif
        }
    }

    // MARK: - Restore Purchases (App Store guidelines requirement)

    func restorePurchases() async {
        do {
            try await AppStore.sync()
        } catch {
            #if DEBUG
            print("❌ [StoreKit] Restore error: \(error)")
            #endif
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
                    #if DEBUG
                    print("❌ [StoreKit] Unverified transaction: \(error)")
                    #endif
                }
            }
        }
    }

    // MARK: - Verify + send receipt to backend

    private func handlePurchasedTransaction(_ transaction: Transaction, productId: String) async {
        let expiresDateMs = transaction.expirationDate.map { Int64($0.timeIntervalSince1970 * 1000) }
        #if DEBUG
        print("💳 [StoreKit] handlePurchasedTransaction: productId=\(productId) txId=\(transaction.id)")
        #endif

        let result = await NetworkService.shared.validateReceipt(
            transactionId: String(transaction.id),
            originalTransactionId: String(transaction.originalID),
            productId: productId,
            expiresDateMs: expiresDateMs
        )
        #if DEBUG
        print("💳 [StoreKit] validateReceipt result: success=\(result.success) tier=\(result.tier ?? "nil") error=\(result.error ?? "nil")")
        #endif

        if result.success, let tier = result.tier {
            #if DEBUG
            if debugTierOverrideActive {
                print("🛑 [StoreKit] Skipping tier update (\(tier)) — debug override active")
                return
            }
            #endif
            updateLocalUserTier(tier)
        } else {
            #if DEBUG
            print("⚠️ [StoreKit] Backend receipt validation failed: \(result.error ?? "unknown")")
            #endif
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
        let currentUser = AuthenticationService.shared.currentUser
        #if DEBUG
        print("💳 [StoreKit] updateLocalUserTier(\(tierString)) — userId=\(currentUser?.id ?? "nil") parsedTier=\(String(describing: UserTier(rawValue: tierString)))")
        #endif
        guard let user = currentUser,
              let newTier = UserTier(rawValue: tierString) else {
            #if DEBUG
            print("⚠️ [StoreKit] updateLocalUserTier FAILED — user=\(String(describing: currentUser?.id)) tier=\(String(describing: UserTier(rawValue: tierString)))")
            #endif
            return
        }

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
        #if DEBUG
        print("✅ [StoreKit] currentUser.tier updated to \(newTier) — isPaid=\(newTier.isPaid)")
        #endif
    }
}
