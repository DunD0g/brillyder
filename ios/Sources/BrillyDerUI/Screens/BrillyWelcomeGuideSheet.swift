import SwiftUI
import BrillyDerCore

/// First-install Welcome Guide & Interactive Theme Picker shown once on fresh install
/// (and re-openable anytime from Settings -> Quick Start & Theme Guide).
public struct BrillyWelcomeGuideSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var page: Int = 0
    @State private var handleInput: String = ""

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                VStack(spacing: 0) {
                    // Compact step progress indicator
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { idx in
                            Capsule()
                                .fill(idx <= page ? BrillyPalette.brillyTeal : Color.white.opacity(0.16))
                                .frame(height: 4)
                                .animation(.snappy(duration: 0.25), value: page)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                    ScrollView {
                        VStack(spacing: 16) {
                            switch page {
                            case 0:
                                welcomeOverviewPage
                            case 1:
                                mascotAndThemePage
                            default:
                                readyToPlayPage
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                    }

                    // Bottom Navigation Bar
                    HStack(spacing: 10) {
                        if page > 0 {
                            Button {
                                withAnimation(.snappy(duration: 0.25)) {
                                    page -= 1
                                }
                                store.triggerHaptic(.move)
                            } label: {
                                Text("Back")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                    .padding(.horizontal, 18)
                                    .frame(height: 48)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                            }
                            .buttonStyle(BrillyPressScaleStyle())
                        }

                        Button {
                            if page < 2 {
                                withAnimation(.snappy(duration: 0.25)) {
                                    page += 1
                                }
                                store.triggerHaptic(.move)
                            } else {
                                finishAndSyncIfEntered()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(primaryButtonTitle)
                                    .font(.headline.weight(.bold))
                                Image(systemName: page < 2 ? "arrow.right" : "checkmark")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(BrillyPalette.voidBg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                                    LinearGradient(
                                        colors: [BrillyPalette.brillyTeal, Color(hex: 0x06B6D4)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            )
                        }
                        .buttonStyle(BrillyPressScaleStyle())
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color(hex: 0x090E1A).opacity(0.86))
                }
            }
            .navigationTitle(pageTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        store.completeOnboarding()
                        dismiss()
                    }
                    .foregroundStyle(BrillyPalette.inkSecondary)
                }
            }
            .onAppear {
                handleInput = store.activeUsername ?? ""
            }
        }
    }

    private var pageTitle: String {
        switch page {
        case 0: return "Welcome"
        case 1: return "Choose Your Style"
        default: return "Ready to Play"
        }
    }

    private var primaryButtonTitle: String {
        switch page {
        case 0: return "Customize Style"
        case 1: return "Next: Quick Setup"
        default:
            let cleaned = handleInput.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "Start Exploring" : "Sync & Launch"
        }
    }

    // MARK: - Page 1: Quick App Guide

    private var welcomeOverviewPage: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    BrillyLogoMark(size: 52, circular: true)
                    BrillyGhibliBuddyView(mood: .brilliant, size: 58, emojiPack: store.emojiPack)
                }

                BrillyWordmarkView(fontSize: 32, uppercase: false, showSlash: true)

                Text("Your private, on-device chess analyzer, opening trainer, and highlight studio.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)

            VStack(spacing: 10) {
                guideCard(
                    icon: "sparkles",
                    tint: BrillyPalette.brillyTeal,
                    title: "Analyze Games On-Device",
                    detail: "Sync your Lichess or Chess.com games in the Games tab and inspect every move offline with move ratings, eval graph & auto-play."
                )
                guideCard(
                    icon: "brain.head.profile",
                    tint: BrillyPalette.warpPurpleText,
                    title: "Daily Coach & Custom FSRS Openings",
                    detail: "Build your daily streak in Train. Tap Daily or press & hold any course in Openings to pick the exact openings you want drilled."
                )
                guideCard(
                    icon: "square.and.arrow.up",
                    tint: BrillyPalette.goldAmber,
                    title: "Brilly Vault & Move Highlight Cards",
                    detail: "Tap the top-right !! counter anytime to revisit your best moves and export 3x social highlight cards."
                )
            }
        }
    }

    // MARK: - Page 2: Interactive Mascot, Vibe & Board Theme Picker

    private var mascotAndThemePage: some View {
        @Bindable var bindableStore = store
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PICK YOUR MASCOT & CALLOUTS")
                    .font(.caption.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(BrillyPalette.brillyTeal)
                Text("Choose how Brilly/Der celebrates brilliant moves and blunders.")
                    .font(.caption)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }

            VStack(spacing: 9) {
                mascotOptionRow(
                    style: .brillyDer,
                    badge: "DEFAULT",
                    title: "Brilly/Der (\(store.emojiPack.pairLabel))",
                    subtitle: "Playful emoji badges shouting \"Very nice, Brilly!!\" & \"Blun-DER!!\""
                ) {
                    BrillyGhibliBuddyView(mood: .brilliant, size: 46, emojiPack: store.emojiPack)
                }

                if store.calloutStyle == .brillyDer {
                    HStack(spacing: 8) {
                        ForEach(BrillyEmojiPack.allCases) { pack in
                            let unlocked = store.isEmojiPackUnlocked(pack)
                            let selected = store.effectiveEmojiPack == pack
                            Button {
                                if !unlocked {
                                    store.triggerHaptic(.move)
                                    return
                                }
                                withAnimation(.snappy(duration: 0.2)) {
                                    store.emojiPack = pack
                                }
                                store.triggerHaptic(.move)
                            } label: {
                                HStack(spacing: 3) {
                                    Text(pack.pairLabel)
                                        .font(.subheadline)
                                    if !unlocked {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundStyle(BrillyPalette.warpPurpleText)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(Color.white.opacity(selected ? 0.14 : 0.05))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                                .strokeBorder(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.08), lineWidth: 1.2)
                                        )
                                )
                            }
                            .buttonStyle(BrillyPressScaleStyle())
                        }
                    }
                }

                mascotOptionRow(
                    style: .standard,
                    badge: nil,
                    title: "Standard (Classic Diamond)",
                    subtitle: "Clean diamond icon and classic tournament chess callouts"
                ) {
                    ZStack {
                        Circle()
                            .fill(BrillyPalette.brillyTeal.opacity(0.18))
                            .frame(width: 46, height: 46)
                        BrillyGemIcon(size: 24, color: BrillyPalette.brillyTeal)
                    }
                }

                mascotOptionRow(
                    style: .cosmicAlien,
                    badge: nil,
                    title: "Alien UFO (Cosmic Probe)",
                    subtitle: "Retro UFO saucer with tractor beam & space-probe reactions"
                ) {
                    BrillyAlienUFOView(mood: .brilliant, size: 48, showBeam: false)
                }
            }

            // Live Preview Toast so the user immediately sees their selected theme!
            AlienCelebrationBanner(
                event: CelebrationEvent(
                    kind: .brilliant,
                    vibe: store.vibeMode,
                    calloutStyle: store.calloutStyle,
                    emojiPack: store.emojiPack
                ),
                surfaceStyle: store.surfaceStyle,
                onDismiss: {}
            )
            .allowsHitTesting(false)

            // Coach Copy Style + Board Swatches
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Coach Copy Vibe")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                    Picker("Coach Copy Vibe", selection: $bindableStore.vibeMode) {
                        Text("Classic Chess").tag(VibeMode.classic)
                        Text("Cosmic Cockpit").tag(VibeMode.cosmic)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Board Color")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                    HStack(spacing: 10) {
                        ForEach(BoardThemeID.allCases) { theme in
                            let selected = store.boardTheme == theme
                            Button {
                                withAnimation(.snappy(duration: 0.2)) {
                                    store.boardTheme = theme
                                }
                                store.triggerHaptic(.move)
                            } label: {
                                VStack(spacing: 5) {
                                    HStack(spacing: 0) {
                                        theme.lightSquare
                                        theme.darkSquare
                                    }
                                    .frame(height: 26)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.14), lineWidth: selected ? 2 : 1)
                                    )
                                    Text(theme.title)
                                        .font(.caption2.weight(selected ? .bold : .medium))
                                        .foregroundStyle(selected ? BrillyPalette.brillyTeal : BrillyPalette.inkSecondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)

            // Tip showing exactly where to find Settings later!
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BrillyPalette.brillyTeal)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(BrillyPalette.brillyTeal.opacity(0.16)))
                Text("Tap the **Sliders icon** in the top-right bar anytime to switch mascots, UI surface (`Liquid Glass` / `Cosmic`), piece sets, sound, or daily openings.")
                    .font(.caption)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }
            .padding(12)
            .brillySurface(store.surfaceStyle, cornerRadius: 16, tint: BrillyPalette.brillyTeal)
        }
    }

    // MARK: - Page 3: Optional Account Sync & Launch

    private var readyToPlayPage: some View {
        @Bindable var bindableStore = store
        return VStack(spacing: 16) {
            VStack(spacing: 10) {
                switch store.calloutStyle {
                case .brillyDer:
                    BrillyGhibliBuddyView(mood: .brilliant, size: 78, emojiPack: store.emojiPack)
                case .cosmicAlien:
                    BrillyAlienUFOView(mood: .brilliant, size: 84, showBeam: true)
                case .standard:
                    ZStack {
                        Circle()
                            .fill(BrillyPalette.brillyTeal.opacity(0.2))
                            .frame(width: 74, height: 74)
                        BrillyGemIcon(size: 38, color: BrillyPalette.brillyTeal)
                    }
                }

                Text("You're All Set!")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(BrillyPalette.inkPrimary)

                Text("Optionally enter your Lichess or Chess.com username to pull in your recent games right away — or skip and explore sample games & opening courses first.")
                    .font(.subheadline)
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 12) {
                Picker("Platform", selection: $bindableStore.syncPlatform) {
                    Text("Lichess").tag(GameSource.lichess)
                    Text("Chess.com").tag(GameSource.chesscom)
                }
                .pickerStyle(.segmented)

                TextField(
                    store.syncPlatform == .lichess ? "Lichess username (optional)" : "Chess.com username (optional)",
                    text: $handleInput
                )
                .textFieldStyle(.plain)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                #endif
                .foregroundStyle(BrillyPalette.inkPrimary)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))

                Text("100% private & local-first: zero accounts required, no servers, no tracking.")
                    .font(.caption2)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }
            .padding(16)
            .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.brillyTeal)

            // Compact default launch screen preference
            VStack(alignment: .leading, spacing: 10) {
                Text("OPEN BRILLYDER ON")
                    .font(.caption2.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(BrillyPalette.brillyTeal)

                HStack(spacing: 8) {
                    ForEach([BrillyTab.train, .analyze, .openings, .insights]) { tab in
                        let selected = store.defaultLaunchTab == tab
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                store.defaultLaunchTab = tab
                            }
                            store.triggerHaptic(.move)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tab.systemImage)
                                    .font(.caption.weight(.bold))
                                Text(tab.title)
                                    .font(.caption2.weight(.bold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(selected ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.09), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(BrillyPressScaleStyle())
                    }
                }

                Text("Pro tip: enable Auto-Sync on Open in Settings to jump straight into your latest game after playing.")
                    .font(.caption2)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)
        }
    }

    // MARK: - Helpers

    private func finishAndSyncIfEntered() {
        let cleaned = handleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        store.completeOnboarding(applyDefaultTab: cleaned.isEmpty)
        if !cleaned.isEmpty {
            if store.syncPlatform == .lichess {
                store.lichessUsername = cleaned
            } else {
                store.chessComUsername = cleaned
            }
            store.lockHandle(for: store.syncPlatform)
            store.selectedTab = .games
            Task {
                await store.syncRecentGames()
            }
        }
        store.triggerHaptic(.success)
        dismiss()
    }

    private func guideCard(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .brillySurface(store.surfaceStyle, cornerRadius: 18)
    }

    private func mascotOptionRow<Mascot: View>(
        style: CalloutStyle,
        badge: String?,
        title: String,
        subtitle: String,
        @ViewBuilder mascot: () -> Mascot
    ) -> some View {
        let selected = store.calloutStyle == style
        return Button {
            withAnimation(.snappy(duration: 0.22)) {
                store.calloutStyle = style
                if style == .cosmicAlien {
                    store.vibeMode = .cosmic
                }
            }
            store.triggerHaptic(.move)
        } label: {
            HStack(spacing: 12) {
                mascot()

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 8.5, weight: .black, design: .rounded))
                                .foregroundStyle(BrillyPalette.voidBg)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(BrillyPalette.brillyTeal))
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? BrillyPalette.brillyTeal : BrillyPalette.inkSecondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.10 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selected ? BrillyPalette.brillyTeal.opacity(0.75) : Color.white.opacity(0.09), lineWidth: selected ? 1.6 : 1.0)
                    )
            )
        }
        .buttonStyle(BrillyPressScaleStyle())
    }
}
