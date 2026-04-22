//
//  StoreKitService.swift
//  sleep
//
//

import Foundation
import os
import StoreKit

// MARK: - Subscription Tier

enum SubscriptionTier: String, Sendable {
    case free
    case premium
}

// MARK: - StoreKit Error

enum StoreKitError: LocalizedError {
    case verificationFailed
    case purchaseCancelled
    case purchasePending
    case unknown

    var errorDescription: String? {
        switch self {
        case .verificationFailed: "Transaction verification failed."
        case .purchaseCancelled: "Purchase was cancelled."
        case .purchasePending: "Purchase is pending approval."
        case .unknown: "An unknown error occurred."
        }
    }
}

@Observable
@MainActor
final class StoreKitService {

    // MARK: - Product IDs

    static let monthlyID = "com.smarterpillow.sleep.monthly"
    static let yearlyID = "com.smarterpillow.sleep.yearly"
    static let lifetimeID = "com.smarterpillow.sleep.lifetime"

    private static let allProductIDs: Set<String> = [
        monthlyID,
        yearlyID,
        lifetimeID
    ]

    // MARK: - Observable State

    var currentTier: SubscriptionTier = .free
    var availableProducts: [Product] = []
    var purchaseInProgress = false

    var isPremium: Bool { true }

    // MARK: - Private

    @ObservationIgnored
    private nonisolated(unsafe) var transactionListener: Task<Void, Never>?

    // MARK: - Init

    init() {
        transactionListener = listenForTransactions()

        Task {
            await loadProducts()
            await checkEntitlements()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: Self.allProductIDs)
            await MainActor.run {
                self.availableProducts = products.sorted { $0.price < $1.price }
            }
            AppLogger.storeKit.info("Loaded \(products.count) products")
        } catch {
            AppLogger.storeKit.error("Failed to load products: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws {
        AppLogger.storeKit.info("🛒 Purchasing product: \(product.id)")
        await MainActor.run { purchaseInProgress = true }
        defer { Task { @MainActor in purchaseInProgress = false } }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerification(verification)
            await transaction.finish()
            await checkEntitlements()

        case .userCancelled:
            throw StoreKitError.purchaseCancelled

        case .pending:
            throw StoreKitError.purchasePending

        @unknown default:
            throw StoreKitError.unknown
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        try? await AppStore.sync()
        await checkEntitlements()
    }

    // MARK: - Check Entitlements

    func checkEntitlements() async {
        var foundPremium = false

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerification(result) else { continue }

            if Self.allProductIDs.contains(transaction.productID) {
                if transaction.revocationDate == nil {
                    foundPremium = true
                }
            }
        }

        let tier: SubscriptionTier = foundPremium ? .premium : .free
        AppLogger.storeKit.info("Entitlement check — premium: \(foundPremium)")
        await MainActor.run {
            currentTier = tier
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self = self else { return }
                if let transaction = try? self.checkVerification(result) {
                    await transaction.finish()
                    await self.checkEntitlements()
                }
            }
        }
    }

    // MARK: - Verification

    nonisolated private func checkVerification<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Helpers

    func product(for identifier: String) -> Product? {
        availableProducts.first { $0.id == identifier }
    }

    var monthlyProduct: Product? { product(for: Self.monthlyID) }
    var yearlyProduct: Product? { product(for: Self.yearlyID) }
    var lifetimeProduct: Product? { product(for: Self.lifetimeID) }

    // MARK: - Purchase by Plan Name

    func purchaseMonthly() async throws {
        guard let product = monthlyProduct else { throw StoreKitError.unknown }
        try await purchase(product)
    }

    func purchaseYearly() async throws {
        guard let product = yearlyProduct else { throw StoreKitError.unknown }
        try await purchase(product)
    }

    func purchaseLifetime() async throws {
        guard let product = lifetimeProduct else { throw StoreKitError.unknown }
        try await purchase(product)
    }
}
