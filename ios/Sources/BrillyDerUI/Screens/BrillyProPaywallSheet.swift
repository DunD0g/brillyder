import SwiftUI
import StoreKit
import BrillyDerCore

/// Production StoreKit 2 Brilly/Der Pro upgrade sheet complying with Apple App Store Guideline 3.1.2:
/// - Live localized prices fetched via `Product.products(for:)`
/// - Dynamic 7-day introductory offer eligibility via `subscription.isEligibleForIntroOffer`
/// - Real `Product.purchase()`, `Transaction.currentEntitlements`, `AppStore.sync()` Restore Purchases
/// - Full auto-renewable subscription disclosure, Privacy Policy & Terms of Use links
public struct BrillyProPaywallSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    public let highlightedFeature: String?
    @State private var selectedTier: BrillyProProductID = .annual
    @State private var showingPrivacySheet = false
    @State private var showingTermsSheet = false

    private static let privacyURL = URL(string: "https://dund0g.github.io/brillyder/privacy.html")!
    private static let termsURL = URL(string: "https://dund0g.github.io/brillyder/terms.html")!

    public init(highlightedFeature: String? = nil) {
        self.highlightedFeature = highlightedFeature
    }

    private var storeKit: BrillyStoreKitManager { store.storeKit }

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollView {
                    VStack(spacing: 16) {
                        heroHeader
                        benefitsCard
                        pricingTiersSection
                        actionButtonsSection
                        legalFooterSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Brilly/Der Pro")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                if !storeKit.hasLoadedProducts {
                    await storeKit.loadProducts()
                } else {
                    await storeKit.refreshEntitlements()
                }
            }
            .sheet(isPresented: $showingPrivacySheet) {
                BrillyPrivacySheet(surfaceStyle: store.surfaceStyle)
            }
            .sheet(isPresented: $showingTermsSheet) {
                BrillyTermsSheet(surfaceStyle: store.surfaceStyle)
            }
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                BrillyLogoMark(size: 42, circular: true)
                BrillyWordmarkView(fontSize: 28, uppercase: false, showSlash: true)
                Text("PRO")
                    .font(.caption.weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(BrillyPalette.voidBg)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [BrillyPalette.brillyTeal, BrillyPalette.warpPurple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
            }

            if store.edition == .founderAdmin && store.hasProAccess {
                Label("Founder Admin Edition · Permanently Unlocked", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(BrillyPalette.brillyTeal)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(BrillyPalette.brillyTeal.opacity(0.16))
                            .overlay(Capsule().strokeBorder(BrillyPalette.brillyTeal.opacity(0.42), lineWidth: 1))
                    )
            } else if storeKit.hasProEntitlement {
                Label("\(storeKit.activePlanTitle) Active", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(BrillyPalette.brillyTeal)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(BrillyPalette.brillyTeal.opacity(0.16))
                            .overlay(Capsule().strokeBorder(BrillyPalette.brillyTeal.opacity(0.42), lineWidth: 1))
                    )
            } else if let highlightedFeature {
                Text("Unlock \(highlightedFeature) & the complete on-device chess cockpit.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Unlimited on-device analysis, full opening repertoire, Woodpecker cycles & Endgame Labs.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Free vs Pro Highlights

    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            benefitRow(
                "infinity",
                tint: BrillyPalette.brillyTeal,
                title: "Unlimited Game & Batch Analysis",
                subtitle: "Remove the 5/day Free limit · batch-analyze your full Lichess & Chess.com archive offline"
            )
            benefitRow(
                "clock.badge.checkmark.fill",
                tint: BrillyPalette.warpPurpleText,
                title: "15m & 25m Orbit Coach + Woodpecker Cycles",
                subtitle: "Extended FSRS opening sessions, Advantage Conversion & tactical speed cycles"
            )
            benefitRow(
                "book.closed.fill",
                tint: BrillyPalette.goldAmber,
                title: "All 8 Starter Openings + Custom PGN Imports",
                subtitle: "Unlock every built-in repertoire course & build unlimited custom PGN lines"
            )
            benefitRow(
                "crown.fill",
                tint: BrillyPalette.blunderRose,
                title: "Endgame & Vision Labs + All 4 Retina Piece Sets",
                subtitle: "12 theoretical Syzygy endgames, Board Vision, Puzzle Rush, Chessnut, Spatial & Kiwen"
            )
            benefitRow(
                "face.smiling.fill",
                tint: BrillyPalette.brillyTeal,
                title: "Pro Emoji Packs & Custom Share Card Captions",
                subtitle: "Unlock 🔥/💀, 👍/🤡 & 👑/🫠 reaction packs plus custom wording on your 3x Share Cards"
            )
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20)
    }

    // MARK: - Pricing Tiers (Live StoreKit 2 Products)

    private var pricingTiersSection: some View {
        VStack(spacing: 10) {
            if storeKit.isLoadingProducts && !storeKit.hasLoadedProducts {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(BrillyPalette.brillyTeal)
                    Text("Loading App Store plans…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .brillySurface(store.surfaceStyle, cornerRadius: 18)
            } else if !storeKit.hasLoadedProducts {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(BrillyPalette.goldAmber)
                    Text(storeKit.errorMessage ?? "App Store plans could not be loaded right now.")
                        .font(.caption)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await storeKit.loadProducts() }
                    } label: {
                        Label("Retry Loading Plans", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.voidBg)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(BrillyPalette.brillyTeal))
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .brillySurface(store.surfaceStyle, cornerRadius: 18)
            } else {
                if let annual = storeKit.product(for: .annual) {
                    let equiv = storeKit.annualMonthlyEquivalentText()
                    let detail = storeKit.isEligibleForAnnualTrial
                        ? "\(equiv.map { "\($0)/mo · " } ?? "")7-day free trial, then \(annual.displayPrice)/year"
                        : "\(equiv.map { "\($0)/mo · " } ?? "")Billed annually at \(annual.displayPrice)/year"
                    tierCard(
                        tier: .annual,
                        title: annual.displayName.isEmpty ? "Annual" : annual.displayName,
                        price: annual.displayPrice,
                        cadence: "/ year",
                        detail: detail,
                        badge: storeKit.isEligibleForAnnualTrial ? "BEST VALUE · 7-DAY FREE TRIAL" : "BEST VALUE",
                        accent: BrillyPalette.brillyTeal
                    )
                }

                if let monthly = storeKit.product(for: .monthly) {
                    tierCard(
                        tier: .monthly,
                        title: monthly.displayName.isEmpty ? "Monthly" : monthly.displayName,
                        price: monthly.displayPrice,
                        cadence: "/ month",
                        detail: "Flexible monthly subscription · cancel anytime",
                        badge: nil,
                        accent: BrillyPalette.warpPurpleText
                    )
                }

                if let lifetime = storeKit.product(for: .lifetime) {
                    tierCard(
                        tier: .lifetime,
                        title: lifetime.displayName.isEmpty ? "Lifetime" : lifetime.displayName,
                        price: lifetime.displayPrice,
                        cadence: "one-time",
                        detail: "Pay once, unlock Brilly/Der Pro permanently",
                        badge: "ONE-TIME PURCHASE",
                        accent: BrillyPalette.goldAmber
                    )
                }
            }
        }
    }

    // MARK: - Purchase & Restore Actions

    private var actionButtonsSection: some View {
        VStack(spacing: 10) {
            if let status = storeKit.statusMessage {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.brillyTeal)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(BrillyPalette.brillyTeal.opacity(0.14)))
            }

            if let err = storeKit.errorMessage, storeKit.hasLoadedProducts {
                Text(err)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.blunderRose)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(BrillyPalette.blunderRose.opacity(0.14)))
            }

            if store.edition == .founderAdmin && store.hasProAccess {
                Button {
                    dismiss()
                } label: {
                    Text("Continue with Founder Admin")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BrillyPalette.voidBg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(BrillyPalette.brillyTeal)
                        )
                }
                .buttonStyle(BrillyPressScaleStyle())
            } else if storeKit.hasProEntitlement {
                if storeKit.hasAutoRenewingSubscription {
                    Button {
                        Task { await storeKit.openManageSubscriptions() }
                    } label: {
                        Label("Manage Subscription in App Store", systemImage: "creditcard")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrillyPalette.voidBg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(BrillyPalette.brillyTeal)
                            )
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                }
            } else {
                Button {
                    Task {
                        let outcome = await storeKit.purchase(selectedTier)
                        switch outcome {
                        case .purchased:
                            store.triggerHaptic(.success)
                            dismiss()
                        case .pending:
                            store.triggerHaptic(.move)
                        case .cancelled:
                            break
                        case .unavailable, .failed:
                            store.triggerHaptic(.error)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if storeKit.isPurchasing {
                            ProgressView()
                                .tint(BrillyPalette.voidBg)
                        }
                        Text(storeKit.isPurchasing ? "Confirming with App Store…" : primaryCtaLabel)
                            .font(.headline.weight(.bold))
                    }
                    .foregroundStyle(BrillyPalette.voidBg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [BrillyPalette.brillyTeal, Color(hex: 0x06B6D4)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .opacity(storeKit.hasLoadedProducts && !storeKit.isPurchasing ? 1.0 : 0.55)
                }
                .buttonStyle(BrillyPressScaleStyle())
                .disabled(!storeKit.hasLoadedProducts || storeKit.isPurchasing || storeKit.isRestoring)
            }

            // Restore Purchases (Required by App Store Guideline 3.1.1)
            Button {
                Task {
                    let restored = await storeKit.restorePurchases()
                    if restored {
                        store.triggerHaptic(.success)
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if storeKit.isRestoring {
                        ProgressView()
                            .controlSize(.small)
                            .tint(BrillyPalette.inkSecondary)
                    }
                    Text(storeKit.isRestoring ? "Restoring Purchases…" : "Restore Purchases")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                }
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(BrillyPressScaleStyle())
            .disabled(storeKit.isRestoring || storeKit.isPurchasing)
        }
    }

    // MARK: - Legal Disclosure (Required by App Store Guideline 3.1.2)

    private var legalFooterSection: some View {
        VStack(spacing: 8) {
            Text(
                "Payment will be charged to your Apple Account at confirmation of purchase (or at the end of the 7-day free trial for eligible Annual plans). Auto-renewable subscriptions renew automatically unless canceled at least 24 hours before the end of the current period. Manage or cancel anytime in App Store Account Settings."
            )
            .font(.caption2)
            .foregroundStyle(BrillyPalette.inkSecondary)
            .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Privacy Policy") {
                    showingPrivacySheet = true
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BrillyPalette.brillyTeal)

                Text("·")
                    .font(.caption2)
                    .foregroundStyle(BrillyPalette.inkSecondary)

                Button("Terms of Use") {
                    showingTermsSheet = true
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BrillyPalette.brillyTeal)

                Text("·")
                    .font(.caption2)
                    .foregroundStyle(BrillyPalette.inkSecondary)

                Link("Apple EULA", destination: Self.termsURL)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }
            .padding(.top, 2)
        }
    }

    private var primaryCtaLabel: String {
        guard let product = storeKit.product(for: selectedTier) else {
            return "Continue"
        }
        switch selectedTier {
        case .annual:
            if storeKit.isEligibleForAnnualTrial {
                return "Start 7-Day Free Trial · \(product.displayPrice)/yr"
            }
            return "Subscribe Annual · \(product.displayPrice)/yr"
        case .monthly:
            return "Subscribe Monthly · \(product.displayPrice)/mo"
        case .lifetime:
            return "Unlock Lifetime · \(product.displayPrice)"
        }
    }

    private func benefitRow(_ icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func tierCard(
        tier: BrillyProProductID,
        title: String,
        price: String,
        cadence: String,
        detail: String,
        badge: String?,
        accent: Color
    ) -> some View {
        let isSelected = selectedTier == tier
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                selectedTier = tier
            }
            store.triggerHaptic(.move)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(BrillyPalette.voidBg)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accent))
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                    }
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(price)
                            .font(.title3.monospacedDigit().weight(.black))
                            .foregroundStyle(isSelected ? accent : BrillyPalette.inkPrimary)
                        Text(cadence)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BrillyPalette.inkSecondary)
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.09 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                isSelected ? accent : Color.white.opacity(0.10),
                                lineWidth: isSelected ? 1.8 : 1.0
                            )
                    )
            )
        }
        .buttonStyle(BrillyPressScaleStyle())
    }
}

/// In-app Terms of Use & Subscription Terms sheet (App Store Guideline 3.1.2).
public struct BrillyTermsSheet: View {
    public let surfaceStyle: SurfaceStyle
    @Environment(\.dismiss) private var dismiss

    public init(surfaceStyle: SurfaceStyle) {
        self.surfaceStyle = surfaceStyle
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: surfaceStyle)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        termsBlock(
                            title: "Brilly/Der Pro Subscriptions & Lifetime",
                            body: "BrillyDer offers optional Monthly and Annual auto-renewable subscriptions (Annual includes a 7-day free trial for eligible new subscribers) and a one-time Lifetime In-App Purchase via Apple's App Store."
                        )
                        termsBlock(
                            title: "Auto-Renewal & Cancellation",
                            body: "Payment is charged to your Apple Account upon purchase confirmation (or after the free trial ends). Subscriptions renew automatically unless canceled at least 24 hours before the end of the billing period. Manage or cancel subscriptions anytime in your device's Apple Account settings."
                        )
                        termsBlock(
                            title: "Local-First Software",
                            body: "All chess analysis, spaced-repetition schedules, and backups are processed locally on your device. Optional Lichess, Chess.com, and Syzygy lookups depend on those third-party public services' availability."
                        )
                        termsBlock(
                            title: "Standard Apple EULA",
                            body: "Use of BrillyDer on iOS is also governed by Apple's Standard Licensed Application End User License Agreement (EULA). Full web copy is available at dund0g.github.io/brillyder/terms.html."
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Terms of Use")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func termsBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BrillyPalette.brillyTeal)
            Text(body)
                .font(.caption)
                .foregroundStyle(BrillyPalette.inkPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .brillySurface(surfaceStyle, cornerRadius: 16)
    }
}
