import SwiftUI
import BrillyDerCore

/// First-install 4-step Welcome Guide & Interactive Setup shown once on fresh install
/// (and re-openable anytime from Settings -> Quick Start & Theme Guide).
public struct BrillyWelcomeGuideSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var page: Int = 0
    @State private var lichessInput: String = ""
    @State private var chessComInput: String = ""
    @State private var previewMoveTick: Int = 0
    @State private var lockedHintMessage: String? = nil

    private static let totalPages = 4
    private static let previewBaseBoard: ChessBoard = (try? ChessBoard(fen: "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQkq - 0 5")) ?? ChessBoard()

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                VStack(spacing: 0) {
                    // Compact 4-step progress bar
                    HStack(spacing: 6) {
                        ForEach(0..<Self.totalPages, id: \.self) { idx in
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
                                boardAndAppearancePage
                            case 2:
                                mascotAndStylePage
                            default:
                                quickSetupPage
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)

                    // Bottom Navigation Bar
                    HStack(spacing: 10) {
                        if page > 0 {
                            Button {
                                withAnimation(.snappy(duration: 0.25)) {
                                    lockedHintMessage = nil
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
                            if page < Self.totalPages - 1 {
                                withAnimation(.snappy(duration: 0.25)) {
                                    lockedHintMessage = nil
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
                                Image(systemName: page < Self.totalPages - 1 ? "arrow.right" : "checkmark")
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
                    Button(store.hasCompletedOnboarding ? "Done" : "Skip") {
                        store.completeOnboarding()
                        dismiss()
                    }
                    .foregroundStyle(BrillyPalette.inkSecondary)
                }
            }
            .onAppear {
                lichessInput = store.lichessUsername
                chessComInput = store.chessComUsername
            }
        }
    }

    private var pageTitle: String {
        switch page {
        case 0: return "Welcome"
        case 1: return "Board & Look"
        case 2: return "Mascot & Style"
        default: return "Quick Setup"
        }
    }

    private var primaryButtonTitle: String {
        switch page {
        case 0: return "Customize Board"
        case 1: return "Next: Mascot & Style"
        case 2: return "Next: Quick Setup"
        default:
            let hasAnyHandle = !lichessInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !chessComInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasAnyHandle ? "Sync & Launch" : "Start Exploring"
        }
    }

    // MARK: - Step 1: Welcome Overview

    private var welcomeOverviewPage: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    BrillyLogoMark(size: 52, circular: true)
                    BrillyGhibliBuddyView(mood: .brilliant, size: 58, emojiPack: store.effectiveEmojiPack)
                }

                BrillyWordmarkView(fontSize: 32, uppercase: false, showSlash: true)

                Text("Your private, on-device chess analyzer, FSRS opening coach, and highlight studio.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 4)

            VStack(spacing: 10) {
                guideCard(
                    icon: "cpu.fill",
                    tint: BrillyPalette.brillyTeal,
                    title: "BrillyChess NNUE Offline (~2650–3300+ Elo)",
                    detail: "Sync Lichess or Chess.com games and inspect every move 100% offline with Super-GM NNUE eval graphs. Pro unlocks Ultra (~3300+ Elo), Threat Arrows & Hybrid Stockfish 16 Cloud (~3500 Elo)."
                )
                guideCard(
                    icon: "brain.head.profile",
                    tint: BrillyPalette.warpPurpleText,
                    title: "FSRS Openings, Mistakes & Labs",
                    detail: "Build your daily streak in Train → FSRS, drill your own blunders, or tap Daily on any of the \(store.starterCourses.count) courses in Openings to customize your repertoire."
                )
                guideCard(
                    icon: "square.and.arrow.up",
                    tint: BrillyPalette.goldAmber,
                    title: "Brilly Vault & 3x Story Share Cards",
                    detail: "Tap the top-right !! counter anytime to revisit your best moves and export 3x Card or 9:16 Story highlights."
                )
            }
        }
    }

    // MARK: - Step 2: Live Board Preview, Surface & All 10 Board Themes

    private var boardAndAppearancePage: some View {
        @Bindable var bindableStore = store
        let previewFen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQkq - \(previewMoveTick % 12) \(5 + previewMoveTick)"
        let previewBoard = (try? ChessBoard(fen: previewFen)) ?? Self.previewBaseBoard

        return VStack(alignment: .leading, spacing: 14) {
            // Live Mini-Board Preview
            VStack(spacing: 10) {
                HStack {
                    Text("LIVE BOARD PREVIEW")
                        .font(.caption2.weight(.bold))
                        .tracking(1.0)
                        .foregroundStyle(BrillyPalette.brillyTeal)
                    Spacer()
                    if store.effectiveBoardTheme == .prismChaos {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                previewMoveTick += 1
                            }
                            store.triggerHaptic(.move)
                        } label: {
                            Label("Shift Color", systemImage: "sparkles")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(BrillyPalette.voidBg)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(BrillyPalette.brillyTeal))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(store.effectiveBoardTheme.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BrillyPalette.inkSecondary)
                    }
                }

                InteractiveChessBoardView(
                    board: previewBoard,
                    orientation: .white,
                    theme: store.effectiveBoardTheme,
                    surfaceStyle: store.surfaceStyle,
                    interactive: false,
                    lastMove: (Square(unchecked: 5), Square(unchecked: 26))
                )
                .frame(width: 172, height: 172)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 20)

            // UI Surface Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("UI SURFACE STYLE")
                    .font(.caption2.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(BrillyPalette.brillyTeal)
                Picker("UI Surface", selection: $bindableStore.surfaceStyle) {
                    ForEach(SurfaceStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)

            // All 10 Board Themes in a balanced 5x2 grid
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("BOARD THEME")
                        .font(.caption2.weight(.bold))
                        .tracking(1.0)
                        .foregroundStyle(BrillyPalette.brillyTeal)
                    Spacer()
                    if !store.hasProAccess {
                        Text("4 Free · 6 Pro")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BrillyPalette.warpPurpleText)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(BoardThemeID.allCases) { theme in
                        let unlocked = store.isBoardThemeUnlocked(theme)
                        let selected = store.effectiveBoardTheme == theme
                        Button {
                            if !unlocked {
                                lockedHintMessage = "\(theme.title) is a Brilly/Der Pro board theme — unlock anytime in Settings."
                                store.triggerHaptic(.move)
                                return
                            }
                            lockedHintMessage = nil
                            withAnimation(.snappy(duration: 0.2)) {
                                store.boardTheme = theme
                            }
                            store.triggerHaptic(.move)
                        } label: {
                            HStack(spacing: 8) {
                                HStack(spacing: 0) {
                                    theme.lightSquare.frame(width: 14, height: 22)
                                    theme.darkSquare.frame(width: 14, height: 22)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                Text(theme.title)
                                    .font(.caption.weight(selected ? .bold : .semibold))
                                    .foregroundStyle(selected ? BrillyPalette.brillyTeal : BrillyPalette.inkPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                if !unlocked {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(BrillyPalette.warpPurpleText)
                                } else if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(BrillyPalette.brillyTeal)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(selected ? 0.12 : 0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.08), lineWidth: selected ? 1.4 : 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let msg = lockedHintMessage {
                    Label(msg, systemImage: "crown.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrillyPalette.warpPurpleText)
                }
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)
        }
    }

    // MARK: - Step 3: Mascot & Emoji Pack

    private var mascotAndStylePage: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                    title: "Brilly/Der (\(store.effectiveEmojiPack.pairLabel))",
                    subtitle: "Playful emoji badges shouting \"Very nice, Brilly!!\" & \"Blun-DER!!\""
                ) {
                    BrillyGhibliBuddyView(mood: .brilliant, size: 46, emojiPack: store.effectiveEmojiPack)
                }

                if store.calloutStyle == .brillyDer {
                    HStack(spacing: 8) {
                        ForEach(BrillyEmojiPack.allCases) { pack in
                            let unlocked = store.isEmojiPackUnlocked(pack)
                            let selected = store.effectiveEmojiPack == pack
                            Button {
                                if !unlocked {
                                    lockedHintMessage = "\(pack.pairLabel) is a Pro Emoji Pack — unlock anytime in Settings."
                                    store.triggerHaptic(.move)
                                    return
                                }
                                lockedHintMessage = nil
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

                    if let msg = lockedHintMessage {
                        Label(msg, systemImage: "crown.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BrillyPalette.warpPurpleText)
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

            // Live Preview Toast
            AlienCelebrationBanner(
                event: CelebrationEvent(
                    kind: .brilliant,
                    vibe: store.vibeMode,
                    calloutStyle: store.calloutStyle,
                    emojiPack: store.effectiveEmojiPack
                ),
                surfaceStyle: store.surfaceStyle,
                onDismiss: {}
            )
            .allowsHitTesting(false)
        }
    }

    // MARK: - Step 4: Dual Accounts, Default Engine & Launch Tab

    private var quickSetupPage: some View {
        @Bindable var bindableStore = store
        return VStack(spacing: 14) {
            // Dual Chess Accounts (Lichess & Chess.com both supported without losing input)
            VStack(alignment: .leading, spacing: 10) {
                Text("CHESS ACCOUNTS (OPTIONAL)")
                    .font(.caption2.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(BrillyPalette.brillyTeal)

                HStack(spacing: 8) {
                    Text("Lichess")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                        .frame(width: 72, alignment: .leading)
                    TextField("Lichess username", text: $lichessInput)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                }

                HStack(spacing: 8) {
                    Text("Chess.com")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                        .frame(width: 72, alignment: .leading)
                    TextField("Chess.com username", text: $chessComInput)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))
                }

                Text("100% private & local-first: zero sign-in required, no servers, no tracking.")
                    .font(.caption2)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.brillyTeal)

            // Default Engine Strength
            VStack(alignment: .leading, spacing: 8) {
                Text("DEFAULT ENGINE STRENGTH")
                    .font(.caption2.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(BrillyPalette.brillyTeal)

                HStack(spacing: 8) {
                    let offlinePresets: [AnalysisDepthPreset] = [.fast, .balanced, .deep, .ultra]
                    let activeOfflinePreset: AnalysisDepthPreset = store.effectiveAnalysisPreset == .cloudUltra ? .ultra : store.effectiveAnalysisPreset
                    ForEach(offlinePresets) { preset in
                        let locked = preset == .ultra && !store.hasProAccess
                        let selected = activeOfflinePreset == preset
                        Button {
                            if locked {
                                lockedHintMessage = "Ultra Offline NNUE (~3300+ Elo) is a Brilly/Der Pro engine mode — unlock anytime in Settings."
                                store.triggerHaptic(.move)
                                return
                            }
                            lockedHintMessage = nil
                            withAnimation(.snappy(duration: 0.2)) {
                                store.analysisPreset = preset
                            }
                            store.triggerHaptic(.move)
                        } label: {
                            VStack(spacing: 2) {
                                HStack(spacing: 3) {
                                    Text(preset.title)
                                        .font(.caption.weight(.bold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    if locked {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 8.5, weight: .bold))
                                            .foregroundStyle(BrillyPalette.warpPurpleText)
                                    }
                                }
                                Text(preset.eloEstimate)
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .opacity(0.85)
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

                if let msg = lockedHintMessage {
                    Label(msg, systemImage: "crown.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrillyPalette.warpPurpleText)
                }

                Text("All 4 tiers run 100% offline on-device. Pro also unlocks ☁️ Cloud SF16 (~3500 Elo on Wi-Fi) inside Analyze.")
                    .font(.caption2)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)

            // Default Launch Tab (all 5 tabs) + Pro Auto-Sync
            VStack(alignment: .leading, spacing: 10) {
                Text("OPEN BRILLYDER ON")
                    .font(.caption2.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(BrillyPalette.brillyTeal)

                HStack(spacing: 6) {
                    ForEach(BrillyTab.allCases) { tab in
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
                                    .font(.system(size: 10, weight: .bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundStyle(selected ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .strokeBorder(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.09), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(BrillyPressScaleStyle())
                    }
                }

                if store.hasProAccess {
                    Toggle(isOn: $bindableStore.autoSyncOnLaunch) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Auto-Sync Latest Game on Open")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            Text("Quietly fetches new games when you open the app")
                                .font(.caption2)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                        }
                    }
                    .tint(BrillyPalette.brillyTeal)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.warpPurpleText)
                        Text("Pro tip: enable Auto-Sync on Open in Settings to jump straight into your latest game.")
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                    }
                }
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)
        }
    }

    // MARK: - Helpers

    private func finishAndSyncIfEntered() {
        let cleanLichess = lichessInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanChessCom = chessComInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAny = !cleanLichess.isEmpty || !cleanChessCom.isEmpty

        if !cleanLichess.isEmpty {
            store.lichessUsername = cleanLichess
            store.lockHandle(for: .lichess)
        }
        if !cleanChessCom.isEmpty {
            store.chessComUsername = cleanChessCom
            store.lockHandle(for: .chesscom)
        }
        if cleanLichess.isEmpty && !cleanChessCom.isEmpty {
            store.syncPlatform = .chesscom
        } else if !cleanLichess.isEmpty {
            store.syncPlatform = .lichess
        }

        store.completeOnboarding(applyDefaultTab: true)

        if hasAny {
            Task { @MainActor in
                if !cleanLichess.isEmpty && !cleanChessCom.isEmpty {
                    store.syncPlatform = .lichess
                    await store.syncRecentGames()
                    store.syncPlatform = .chesscom
                    await store.syncRecentGames()
                    store.syncPlatform = .lichess
                } else {
                    await store.syncRecentGames()
                }
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
                    .foregroundStyle(selected ? BrillyPalette.brillyTeal : BrillyPalette.inkSecondary.opacity(0.6))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.11 : 0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selected ? BrillyPalette.brillyTeal.opacity(0.75) : Color.white.opacity(0.08), lineWidth: selected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(BrillyPressScaleStyle())
    }
}
