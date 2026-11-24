import Foundation
import Observation
import StoreKit
import BrillyDerCore
#if canImport(UIKit) && os(iOS)
import UIKit
#endif

/// Production StoreKit 2 manager handling product discovery, verified purchases,
/// introductory 7-day trial eligibility, real-time `Transaction.updates`,
/// `Transaction.currentEntitlements`, and `AppStore.sync()` restore flows.
@MainActor
@Observable
public final class BrillyStoreKitManager {
    public enum PurchaseOutcome: Equatable, Sendable {
        case purchased
        case cancelled
        case pending
        case unavailable
        case failed(String)
    }

    public private(set) var productsByID: [BrillyProProductID: Product] = [:]
    public private(set) var activeProductIDs: Set<BrillyProProductID> = []
    public private(set) var activeExpirationDate: Date? = nil
    public private(set) var isEligibleForAnnualTrial: Bool = false

    public private(set) var isLoadingProducts: Bool = false
    public private(set) var isPurchasing: Bool = false
    public private(set) var isRestoring: Bool = false
    public private(set) var statusMessage: String? = nil
    public private(set) var errorMessage: String? = nil

    @ObservationIgnored
    nonisolated(unsafe) private var updatesTask: Task<Void, Never>?

    public var hasProEntitlement: Bool {
        !activeProductIDs.isEmpty
    }

    public var hasLifetimeEntitlement: Bool {
        activeProductIDs.contains(.lifetime)
    }

    public var hasAutoRenewingSubscription: Bool {
        activeProductIDs.contains(.annual) || activeProductIDs.contains(.monthly)
    }

    public var activePlanTitle: String {
        if activeProductIDs.contains(.lifetime) { return BrillyProProductID.lifetime.planTitle }
        if activeProductIDs.contains(.annual) { return BrillyProProductID.annual.planTitle }
        if activeProductIDs.contains(.monthly) { return BrillyProProductID.monthly.planTitle }
        return "Free Plan"
    }

    public var hasLoadedProducts: Bool {
        !productsByID.isEmpty
    }

    public init() {
        startTransactionListener()
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Product Loading

    public func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        errorMessage = nil
        defer { isLoadingProducts = false }

        do {
            let fetched = try await Product.products(for: BrillyProProductID.allRawValues)
            var mapped: [BrillyProProductID: Product] = [:]
            for product in fetched {
                if let pid = BrillyProProductID(rawValue: product.id) {
                    mapped[pid] = product
                }
            }
            self.productsByID = mapped

            if let annual = mapped[.annual], let sub = annual.subscription {
                self.isEligibleForAnnualTrial = await sub.isEligibleForIntroOffer
            } else {
                self.isEligibleForAnnualTrial = false
            }

            if mapped.isEmpty {
                self.errorMessage = "App Store plans are temporarily unavailable. Please check your connection and tap Retry."
            }
        } catch {
            self.errorMessage = "Could not load App Store plans: \(error.localizedDescription)"
        }
    }

    public func product(for id: BrillyProProductID) -> Product? {
        productsByID[id]
    }

    /// Computes formatted monthly equivalent for the Annual plan using Apple's exact `Decimal` price & locale format.
    public func annualMonthlyEquivalentText() -> String? {
        guard let annual = productsByID[.annual] else { return nil }
        let monthlyPrice = annual.price / Decimal(12)
        return monthlyPrice.formatted(annual.priceFormatStyle)
    }

    // MARK: - Purchasing

    public func purchase(_ productID: BrillyProProductID) async -> PurchaseOutcome {
        errorMessage = nil
        statusMessage = nil

        if productsByID[productID] == nil {
            await loadProducts()
        }
        guard let product = productsByID[productID] else {
            let msg = "This plan could not be loaded from the App Store yet. Please retry in a moment."
            errorMessage = msg
            return .unavailable
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.verify(verification)
                await refreshEntitlements()
                await transaction.finish()
                statusMessage = "Welcome to \(productID.planTitle)!"
                return .purchased
            case .userCancelled:
                return .cancelled
            case .pending:
                statusMessage = "Purchase is pending approval. Pro access will unlock automatically once approved."
                return .pending
            @unknown default:
                let msg = "Unexpected App Store purchase response."
                errorMessage = msg
                return .failed(msg)
            }
        } catch {
            let msg = error.localizedDescription
            errorMessage = msg
            return .failed(msg)
        }
    }

    // MARK: - Entitlements & Restore

    public func refreshEntitlements() async {
        var unlocked: Set<BrillyProProductID> = []
        var latestExpiration: Date? = nil
        let now = Date()

        for await verification in Transaction.currentEntitlements {
            guard let transaction = try? Self.verify(verification),
                  let pid = BrillyProProductID(rawValue: transaction.productID) else {
                continue
            }
            if transaction.revocationDate != nil { continue }
            if let exp = transaction.expirationDate, exp <= now { continue }

            unlocked.insert(pid)
            if let exp = transaction.expirationDate {
                if latestExpiration == nil || exp > latestExpiration! {
                    latestExpiration = exp
                }
            }
        }

        self.activeProductIDs = unlocked
        self.activeExpirationDate = unlocked.contains(.lifetime) ? nil : latestExpiration

        if let annual = productsByID[.annual], let sub = annual.subscription {
            self.isEligibleForAnnualTrial = await sub.isEligibleForIntroOffer
        }
    }

    @discardableResult
    public func restorePurchases() async -> Bool {
        guard !isRestoring else { return hasProEntitlement }
        isRestoring = true
        errorMessage = nil
        statusMessage = nil
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if hasProEntitlement {
                statusMessage = "Restored \(activePlanTitle)!"
                return true
            } else {
                statusMessage = "No active Brilly/Der Pro purchases were found for this Apple Account."
                return false
            }
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
            return false
        }
    }

    public func openManageSubscriptions() async {
        #if canImport(UIKit) && os(iOS)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        do {
            try await AppStore.showManageSubscriptions(in: scene)
            await refreshEntitlements()
        } catch {
            errorMessage = "Unable to open App Store subscription settings."
        }
        #endif
    }

    public func clearNotices() {
        statusMessage = nil
        errorMessage = nil
    }

    // MARK: - Real-Time Transaction Listener

    private func startTransactionListener() {
        updatesTask?.cancel()
        updatesTask = Task(priority: .background) { [weak self] in
            for await verification in Transaction.updates {
                guard !Task.isCancelled else { break }
                if let transaction = try? Self.verify(verification) {
                    await self?.refreshEntitlements()
                    await transaction.finish()
                }
            }
        }
    }

    private nonisolated static func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }
}
