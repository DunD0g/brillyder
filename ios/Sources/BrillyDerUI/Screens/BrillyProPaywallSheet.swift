import SwiftUI

/// Non-intrusive Brilly/Der Pro upgrade modal displaying Monthly, Annual (Best Value + 7-day trial),
/// and Lifetime tiers. Owner/Founder access remains fully unlocked by default (`store.hasProAccess`).
public struct BrillyProPaywallSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    public enum ProTier: String, CaseIterable, Identifiable {
        case annual
        case monthly
        case lifetime

        public var id: String { rawValue }
    }

    public let highlightedFeature: String?
    @State private var selectedTier: ProTier = .annual

    public init(highlightedFeature: String? = nil) {
        self.highlightedFeature = highlightedFeature
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollView {
                    VStack(spacing: 16) {
                        // Hero Header
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

                            if store.hasProAccess {
                                Label("Founder Pro Active · Full Access Unlocked", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.bold))
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
                                Text("Master your openings, eliminate blunders, and train 100% offline on-device.")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(.top, 8)

                        // Pro Highlights List
                        VStack(alignment: .leading, spacing: 10) {
                            benefitRow("infinity", tint: BrillyPalette.brillyTeal, title: "Unlimited Game Sync & Batch Analysis", subtitle: "Deep Stockfish analysis across your full Lichess & Chess.com history")
                            benefitRow("clock.badge.checkmark.fill", tint: BrillyPalette.warpPurple, title: "25-Minute Orbit Coach & Woodpecker Cycles", subtitle: "Extended FSRS opening sessions, mistake rewinds & pattern sprints")
                            benefitRow("crown.fill", tint: BrillyPalette.goldAmber, title: "Endgame & Vision Labs + Syzygy Tablebase", subtitle: "12 theoretical drills, live 7-piece tablebase, Board Vision & Puzzle Rush")
                            benefitRow("sparkles", tint: BrillyPalette.blunderRose, title: "Custom PGN Repertoires & Retina Share Cards", subtitle: "Import any PGN/study + 3x Alien UFO move cards for Discord, Reddit & X")
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20)

                        // 3 Pricing Tiers: Monthly, Annual (Best Value), Lifetime
                        VStack(spacing: 10) {
                            tierCard(
                                tier: .annual,
                                title: "Annual",
                                price: "£24.99",
                                cadence: "/ year",
                                detail: "£2.08/mo · 7-day free trial included",
                                badge: "BEST VALUE · 7-DAY FREE TRIAL",
                                accent: BrillyPalette.brillyTeal
                            )
                            tierCard(
                                tier: .monthly,
                                title: "Monthly",
                                price: "£3.99",
                                cadence: "/ month",
                                detail: "Flexible monthly access · cancel anytime",
                                badge: nil,
                                accent: BrillyPalette.warpPurple
                            )
                            tierCard(
                                tier: .lifetime,
                                title: "Lifetime",
                                price: "£39.99",
                                cadence: "one-time",
                                detail: "Pay once, keep Brilly/Der Pro forever",
                                badge: "ONE-TIME",
                                accent: BrillyPalette.goldAmber
                            )
                        }

                        // Primary Action CTA
                        Button {
                            store.isFounderPro = true
                            store.previewFreeTier = false
                            store.triggerHaptic(.success)
                            dismiss()
                        } label: {
                            Text(store.hasProAccess ? "Continue with Founder Pro" : ctaLabel)
                                .font(.headline.weight(.bold))
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
                        }
                        .buttonStyle(BrillyPressScaleStyle())

                        Text("100% local-first · Zero servers · Full Founder Pro unlocked for your build.")
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
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
        }
    }

    private var ctaLabel: String {
        switch selectedTier {
        case .annual:   return "Start 7-Day Free Trial (£24.99/yr)"
        case .monthly:  return "Continue Monthly (£3.99/mo)"
        case .lifetime: return "Unlock Lifetime (£39.99)"
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
        tier: ProTier,
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
