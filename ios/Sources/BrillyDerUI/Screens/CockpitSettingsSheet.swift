import SwiftUI
import UniformTypeIdentifiers
import BrillyDerCore
#if canImport(UIKit)
import UIKit
#endif

private struct BrillyBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

public struct CockpitSettingsSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportDoc: BrillyBackupDocument? = nil
    @State private var backupNotice: String? = nil
    @State private var backupError: Bool = false
    @State private var previewCelebration: CelebrationEvent? = nil
    @State private var showingDailyOpeningsPicker = false
    @State private var showingLocalProSheet = false
    @State private var localProFeature: String? = nil
    @State private var showingPrivacySheet = false
    @State private var showingTermsSheet = false
    @State private var showingLicensesSheet = false

    public var body: some View {
        @Bindable var bindableStore = store

        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollView {
                    VStack(spacing: 16) {
                        // MARK: - 1. Surface Appearance (Liquid Glass | Cosmic Minimalist)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("UI SURFACE STYLE")
                                .font(.caption.weight(.bold))
                                .tracking(1.0)
                                .foregroundStyle(BrillyPalette.brillyTeal)

                            ForEach(SurfaceStyle.allCases) { style in
                                let selected = store.surfaceStyle == style
                                Button {
                                    withAnimation(.spring(duration: 0.35)) {
                                        store.surfaceStyle = style
                                    }
                                    store.triggerHaptic(.move)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: style == .liquidGlass ? "sparkles.rectangle.stack.fill" : "moon.stars.fill")
                                            .font(.title3)
                                            .foregroundStyle(selected ? BrillyPalette.brillyTeal : BrillyPalette.inkSecondary)
                                            .frame(width: 30)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(style.title)
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(BrillyPalette.inkPrimary)
                                            Text(style.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(BrillyPalette.inkSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected ? BrillyPalette.brillyTeal : BrillyPalette.inkSecondary)
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.white.opacity(selected ? 0.10 : 0.04))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .strokeBorder(selected ? BrillyPalette.brillyTeal.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.brillyTeal)

                        // MARK: - 2. Copy Vibe, Engine Depth, Sound, Haptics & Celebrations
                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Coach Vibe")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                Picker("Vibe", selection: $bindableStore.vibeMode) {
                                    ForEach(VibeMode.allCases) { v in
                                        Text(v.title).tag(v)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Mascot & Move Callouts")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                Picker("Move Callouts", selection: $bindableStore.calloutStyle) {
                                    ForEach(CalloutStyle.allCases) { style in
                                        Text(style.title).tag(style)
                                    }
                                }
                                .pickerStyle(.segmented)
                                Text(store.calloutStyle.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(BrillyPalette.inkSecondary)

                                if store.calloutStyle == .brillyDer {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Brilly/Der Emoji Pair")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(BrillyPalette.brillyTeal)
                                            Spacer()
                                            if !store.hasProAccess {
                                                Text("Extra packs · PRO")
                                                    .font(.caption2.weight(.bold))
                                                    .foregroundStyle(BrillyPalette.warpPurpleText)
                                            }
                                        }
                                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                            ForEach(BrillyEmojiPack.allCases) { pack in
                                                let unlocked = store.isEmojiPackUnlocked(pack)
                                                let selected = store.effectiveEmojiPack == pack
                                                Button {
                                                    if !unlocked {
                                                        localProFeature = "Custom Emoji Packs & Share Card Captions"
                                                        showingLocalProSheet = true
                                                        return
                                                    }
                                                    withAnimation(.snappy(duration: 0.2)) {
                                                        store.emojiPack = pack
                                                    }
                                                    store.triggerHaptic(.move)
                                                    if let existing = previewCelebration {
                                                        previewCelebration = CelebrationEvent(
                                                            kind: existing.kind,
                                                            vibe: store.vibeMode,
                                                            calloutStyle: store.effectiveCalloutStyle,
                                                            emojiPack: pack
                                                        )
                                                    }
                                                } label: {
                                                    HStack(spacing: 5) {
                                                        Text(pack.pairLabel)
                                                            .font(.subheadline)
                                                        Text(pack.title)
                                                            .font(.caption2.weight(.bold))
                                                            .foregroundStyle(selected ? BrillyPalette.brillyTeal : BrillyPalette.inkPrimary)
                                                            .lineLimit(1)
                                                        if !unlocked {
                                                            Image(systemName: "lock.fill")
                                                                .font(.system(size: 9, weight: .bold))
                                                                .foregroundStyle(BrillyPalette.warpPurpleText)
                                                        }
                                                    }
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 8)
                                                    .padding(.horizontal, 8)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                            .fill(Color.white.opacity(selected ? 0.12 : 0.05))
                                                            .overlay(
                                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                                    .strokeBorder(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.08), lineWidth: 1.2)
                                                            )
                                                    )
                                                }
                                                .buttonStyle(BrillyPressScaleStyle())
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }

                            Divider().overlay(Color.white.opacity(0.1))

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Analysis Depth")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                Picker("Depth", selection: $bindableStore.analysisPreset) {
                                    ForEach(AnalysisDepthPreset.allCases) { p in
                                        Text(p.title).tag(p)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            Divider().overlay(Color.white.opacity(0.1))

                            Toggle(isOn: $bindableStore.soundEnabled) {
                                Text("Board & Coach Audio")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                            }
                            .tint(BrillyPalette.brillyTeal)

                            Toggle(isOn: $bindableStore.hapticsEnabled) {
                                Text("Tactile Haptics")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                            }
                            .tint(BrillyPalette.brillyTeal)

                            Toggle(isOn: $bindableStore.celebrationsEnabled) {
                                Text("Move Celebrations")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                            }
                            .tint(BrillyPalette.brillyTeal)

                            // Live Celebration Toast Previewer right inside Settings
                            HStack(spacing: 8) {
                                Button {
                                    if store.soundEnabled {
                                        BrillySoundEngine.shared.play(.brilliant)
                                    }
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                                        previewCelebration = CelebrationEvent(
                                            kind: .brilliant,
                                            vibe: store.vibeMode,
                                            calloutStyle: store.effectiveCalloutStyle,
                                            emojiPack: store.effectiveEmojiPack
                                        )
                                    }
                                } label: {
                                    Label(
                                        store.effectiveCalloutStyle == .brillyDer ? "Preview Brilly!!" : "Preview !!",
                                        systemImage: "sparkles"
                                    )
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    if store.soundEnabled {
                                        BrillySoundEngine.shared.play(.blunder)
                                    }
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                                        previewCelebration = CelebrationEvent(
                                            kind: .blunder,
                                            vibe: store.vibeMode,
                                            calloutStyle: store.effectiveCalloutStyle,
                                            emojiPack: store.effectiveEmojiPack
                                        )
                                    }
                                } label: {
                                    Label(
                                        store.effectiveCalloutStyle == .brillyDer ? "Preview Blun-DER" : "Preview ??",
                                        systemImage: "exclamationmark.triangle.fill"
                                    )
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.blunderRose)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.blunderRose)
                                }
                                .buttonStyle(.plain)
                            }

                            if let previewCelebration {
                                AlienCelebrationBanner(
                                    event: previewCelebration,
                                    surfaceStyle: store.surfaceStyle
                                ) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        self.previewCelebration = nil
                                    }
                                }
                            }
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20)

                        // MARK: - 3. Piece Style Picker (4 Pro Retina Sets)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CHESS PIECE STYLE")
                                .font(.caption.weight(.bold))
                                .tracking(1.0)
                                .foregroundStyle(BrillyPalette.brillyTeal)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(PieceSetID.allCases) { set in
                                    let selected = store.effectivePieceSet == set
                                    let locked = !store.isPieceSetUnlocked(set)
                                    Button {
                                        if locked {
                                            localProFeature = "All 4 Retina Piece Sets"
                                            showingLocalProSheet = true
                                            return
                                        }
                                        withAnimation(.snappy) {
                                            store.pieceSet = set
                                        }
                                        store.triggerHaptic(.move)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(spacing: 8) {
                                                HStack(spacing: 0) {
                                                    ZStack {
                                                        store.boardTheme.lightSquare
                                                        ChessPieceView(piece: Piece(color: .white, type: .knight), squareSize: 34, pieceSet: set)
                                                    }
                                                    .frame(width: 38, height: 38)
                                                    ZStack {
                                                        store.boardTheme.darkSquare
                                                        ChessPieceView(piece: Piece(color: .black, type: .queen), squareSize: 34, pieceSet: set)
                                                    }
                                                    .frame(width: 38, height: 38)
                                                }
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                                Spacer()
                                                if locked {
                                                    Label("PRO", systemImage: "lock.fill")
                                                        .font(.system(size: 9.5, weight: .black))
                                                        .foregroundStyle(BrillyPalette.warpPurpleText)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 3)
                                                        .background(Capsule().fill(BrillyPalette.warpPurple.opacity(0.18)))
                                                } else if selected {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.subheadline)
                                                        .foregroundStyle(BrillyPalette.brillyTeal)
                                                }
                                            }

                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(set.title)
                                                    .font(.subheadline.weight(.bold))
                                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                                Text(set.subtitle)
                                                    .font(.caption2)
                                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(Color.white.opacity(selected ? 0.12 : 0.04))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                        .strokeBorder(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.08), lineWidth: 1.2)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.brillyTeal)

                        // MARK: - 4. Board Theme Swatches
                        VStack(alignment: .leading, spacing: 10) {
                            Text("BOARD THEME")
                                .font(.caption.weight(.bold))
                                .tracking(1.0)
                                .foregroundStyle(BrillyPalette.inkSecondary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(BoardThemeID.allCases) { theme in
                                    let selected = store.boardTheme == theme
                                    Button {
                                        store.boardTheme = theme
                                        store.triggerHaptic(.move)
                                    } label: {
                                        HStack(spacing: 10) {
                                            HStack(spacing: 0) {
                                                theme.lightSquare.frame(width: 16, height: 24)
                                                theme.darkSquare.frame(width: 16, height: 24)
                                            }
                                            .clipShape(RoundedRectangle(cornerRadius: 6))

                                            Text(theme.title)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(BrillyPalette.inkPrimary)
                                            Spacer()
                                            if selected {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(theme.accent)
                                            }
                                        }
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(selected ? 0.12 : 0.04))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .strokeBorder(selected ? theme.accent : Color.white.opacity(0.08), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20)

                        // MARK: - 4. Port Data From Web App (JSON Backup Export / Import / Paste)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("PORT DATA FROM WEB APP (JSON BACKUP)")
                                .font(.caption.weight(.bold))
                                .tracking(1.0)
                                .foregroundStyle(BrillyPalette.brillyTeal)

                            Text("In BrillyDer Web → Settings → Export JSON, save to Files (or AirDrop to iPhone), then tap Import File below to merge analyzed games, FSRS opening progress, custom courses, Woodpecker cycles, bookmarks & streaks.")
                                .font(.caption)
                                .foregroundStyle(BrillyPalette.inkSecondary)

                            HStack(spacing: 10) {
                                Button {
                                    showingImporter = true
                                } label: {
                                    Label("Import File", systemImage: "square.and.arrow.down")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(BrillyPalette.voidBg)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(Capsule().fill(BrillyPalette.brillyTeal))
                                }
                                .buttonStyle(.plain)

                                Button {
                                    do {
                                        let data = try store.exportBackupData()
                                        exportDoc = BrillyBackupDocument(data: data)
                                        showingExporter = true
                                    } catch {
                                        backupError = true
                                        backupNotice = "Export failed: \(error.localizedDescription)"
                                    }
                                } label: {
                                    Label("Export JSON", systemImage: "square.and.arrow.up")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                                }
                                .buttonStyle(.plain)
                            }

                            #if os(iOS)
                            PasteButton(payloadType: String.self) { pasted in
                                guard let text = pasted.first,
                                      let data = text.data(using: .utf8) else {
                                    backupError = true
                                    backupNotice = "Clipboard does not contain a BrillyDer JSON backup."
                                    return
                                }
                                do {
                                    let summary = try store.importBackupData(data)
                                    backupError = false
                                    backupNotice = summary.humanSummary
                                } catch {
                                    backupError = true
                                    backupNotice = error.localizedDescription
                                }
                            }
                            .buttonBorderShape(.roundedRectangle(radius: 12))
                            .tint(BrillyPalette.brillyTeal)
                            .frame(maxWidth: .infinity)
                            #endif

                            if let notice = backupNotice {
                                Text(notice)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(backupError ? BrillyPalette.blunderRose : BrillyPalette.brillyTeal)
                            }
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.brillyTeal)

                        // MARK: - Daily FSRS Openings Shortcut
                        VStack(alignment: .leading, spacing: 10) {
                            Text("DAILY FSRS REPERTOIRE")
                                .font(.caption.weight(.bold))
                                .tracking(1.0)
                                .foregroundStyle(BrillyPalette.brillyTeal)

                            Button {
                                showingDailyOpeningsPicker = true
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Choose Daily Openings")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(BrillyPalette.inkPrimary)
                                        Text("\(store.dailyOpeningCourseIds.count) of \(store.allCourses.count) openings active in Orbit Coach & Gravity Check")
                                            .font(.caption)
                                            .foregroundStyle(BrillyPalette.inkSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(BrillyPalette.brillyTeal)
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
                            }
                            .buttonStyle(BrillyPressScaleStyle())
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20)

                        // MARK: - Brilly/Der Pro Membership & StoreKit 2 Controls
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(store.edition == .founderAdmin ? "FOUNDER ADMIN EDITION" : "BRILLY/DER PRO")
                                    .font(.caption.weight(.bold))
                                    .tracking(1.0)
                                    .foregroundStyle(BrillyPalette.warpPurpleText)
                                Spacer()
                                Label(
                                    store.edition == .founderAdmin
                                        ? (store.hasProAccess ? "Admin Unlocked" : "Free Preview")
                                        : (store.hasProAccess ? "Pro Active" : "Free Plan"),
                                    systemImage: store.hasProAccess ? "checkmark.seal.fill" : "sparkles"
                                )
                                .font(.caption2.weight(.bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(store.hasProAccess ? BrillyPalette.brillyTeal : BrillyPalette.goldAmber)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill((store.hasProAccess ? BrillyPalette.brillyTeal : BrillyPalette.goldAmber).opacity(0.16))
                                )
                            }

                            if store.edition == .founderAdmin {
                                Text("Personal Founder build (`com.brillyder.admin`) — all Pro features unlocked permanently and updated alongside the App Store edition.")
                                    .font(.caption)
                                    .foregroundStyle(BrillyPalette.inkSecondary)

                                Button {
                                    localProFeature = nil
                                    showingLocalProSheet = true
                                } label: {
                                    Label("Inspect StoreKit 2 Paywall", systemImage: "crown.fill")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                                }
                                .buttonStyle(BrillyPressScaleStyle())

                                Toggle(isOn: $bindableStore.simulateFreeTierInAdmin) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Simulate Free Tier Locks")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(BrillyPalette.inkPrimary)
                                        Text("Admin build only — test the Free experience & paywall gates anytime.")
                                            .font(.caption2)
                                            .foregroundStyle(BrillyPalette.inkSecondary)
                                    }
                                }
                                .tint(BrillyPalette.warpPurple)
                            } else {
                                if store.hasProAccess {
                                    Text(store.storeKit.activePlanTitle)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                    if let exp = store.storeKit.activeExpirationDate {
                                        Text("Renews \(exp.formatted(date: .abbreviated, time: .omitted)) via Apple App Store.")
                                            .font(.caption)
                                            .foregroundStyle(BrillyPalette.inkSecondary)
                                    } else {
                                        Text("Lifetime Pro unlocked on this Apple Account.")
                                            .font(.caption)
                                            .foregroundStyle(BrillyPalette.inkSecondary)
                                    }
                                } else {
                                    Text("Free Plan · \(store.remainingFreeAnalysesToday) of \(BrillyEntitlementPolicy.freeDailyAnalysisLimit) daily game analyses left today. Upgrade for unlimited batch analysis, all 8 openings, Woodpecker, Labs & all 4 piece sets.")
                                        .font(.caption)
                                        .foregroundStyle(BrillyPalette.inkSecondary)
                                }

                                HStack(spacing: 10) {
                                    if store.hasProAccess && store.storeKit.hasAutoRenewingSubscription {
                                        Button {
                                            Task { await store.storeKit.openManageSubscriptions() }
                                        } label: {
                                            Label("Manage Plan", systemImage: "creditcard")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(BrillyPalette.voidBg)
                                                .frame(maxWidth: .infinity, minHeight: 40)
                                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BrillyPalette.brillyTeal))
                                        }
                                        .buttonStyle(BrillyPressScaleStyle())
                                    } else if !store.hasProAccess {
                                        Button {
                                            localProFeature = nil
                                            showingLocalProSheet = true
                                        } label: {
                                            Label("Upgrade to Pro", systemImage: "crown.fill")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(BrillyPalette.voidBg)
                                                .frame(maxWidth: .infinity, minHeight: 40)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(
                                                        LinearGradient(
                                                            colors: [BrillyPalette.brillyTeal, BrillyPalette.warpPurple],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                                )
                                        }
                                        .buttonStyle(BrillyPressScaleStyle())
                                    }

                                    Button {
                                        Task {
                                            let restored = await store.storeKit.restorePurchases()
                                            if restored { store.triggerHaptic(.success) }
                                        }
                                    } label: {
                                        Label(store.storeKit.isRestoring ? "Restoring…" : "Restore", systemImage: "arrow.clockwise")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(BrillyPalette.inkPrimary)
                                            .frame(maxWidth: .infinity, minHeight: 40)
                                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                                    }
                                    .buttonStyle(BrillyPressScaleStyle())
                                    .disabled(store.storeKit.isRestoring)
                                }

                                if let status = store.storeKit.statusMessage {
                                    Text(status)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(BrillyPalette.brillyTeal)
                                }
                                if let err = store.storeKit.errorMessage {
                                    Text(err)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(BrillyPalette.blunderRose)
                                }
                            }
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.warpPurple)

                        // MARK: - About, Privacy Policy, Terms & Open-Source Licenses (App Store Guidelines 3.1.2, 5.1.1 & 5.2.1)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("ABOUT & PRIVACY")
                                    .font(.caption.weight(.bold))
                                    .tracking(1.0)
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                                Spacer()
                                Text(appVersionString)
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                            }

                            Text(
                                store.edition == .founderAdmin
                                    ? "BrillyDer Founder Admin · BrillyNative Swift Engine · 100% On-Device"
                                    : "BrillyDer · BrillyNative Swift Engine · 100% On-Device & Local-First"
                            )
                            .font(.caption)
                            .foregroundStyle(BrillyPalette.inkSecondary)

                            Button {
                                dismiss()
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(350))
                                    store.showingWelcomeGuide = true
                                }
                            } label: {
                                Label("Quick Start & Theme Guide", systemImage: "sparkles.rectangle.stack")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BrillyPalette.brillyTeal.opacity(0.12)))
                            }
                            .buttonStyle(BrillyPressScaleStyle())

                            HStack(spacing: 8) {
                                Button {
                                    showingPrivacySheet = true
                                } label: {
                                    Label("Privacy", systemImage: "hand.raised.fill")
                                        .font(.caption.weight(.bold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                                }
                                .buttonStyle(BrillyPressScaleStyle())

                                Button {
                                    showingTermsSheet = true
                                } label: {
                                    Label("Terms", systemImage: "doc.plaintext")
                                        .font(.caption.weight(.bold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                                }
                                .buttonStyle(BrillyPressScaleStyle())

                                Button {
                                    showingLicensesSheet = true
                                } label: {
                                    Label("Licenses", systemImage: "doc.text.fill")
                                        .font(.caption.weight(.bold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                                }
                                .buttonStyle(BrillyPressScaleStyle())
                            }
                        }
                        .padding(16)
                        .brillySurface(store.surfaceStyle, cornerRadius: 20)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .sheet(isPresented: $showingDailyOpeningsPicker) {
                DailyOpeningsPickerSheet()
                    .environment(store)
            }
            .sheet(isPresented: $showingLocalProSheet) {
                BrillyProPaywallSheet(highlightedFeature: localProFeature)
                    .environment(store)
            }
            .sheet(isPresented: $showingPrivacySheet) {
                BrillyPrivacySheet(surfaceStyle: store.surfaceStyle)
            }
            .sheet(isPresented: $showingTermsSheet) {
                BrillyTermsSheet(surfaceStyle: store.surfaceStyle)
            }
            .sheet(isPresented: $showingLicensesSheet) {
                BrillyLicensesSheet(surfaceStyle: store.surfaceStyle)
            }
            .navigationTitle(store.copy(cosmic: "Cockpit Settings", classic: "Settings"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDoc,
                contentType: .json,
                defaultFilename: "brillyder-backup"
            ) { result in
                switch result {
                case .success:
                    backupError = false
                    backupNotice = "Backup exported cleanly."
                case .failure(let err):
                    backupError = true
                    backupNotice = "Export failed: \(err.localizedDescription)"
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    do {
                        let data = try Data(contentsOf: url)
                        let summary = try store.importBackupData(data)
                        backupError = false
                        backupNotice = summary.humanSummary
                    } catch {
                        backupError = true
                        backupNotice = "Import failed: \(error.localizedDescription)"
                    }
                case .failure(let err):
                    backupError = true
                    backupNotice = "Import cancelled: \(err.localizedDescription)"
                }
            }
        }
    }

    private var appVersionString: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.11.0"
        let bld = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "14"
        return "v\(ver) (\(bld))"
    }
}

// MARK: - In-App Privacy Policy Sheet (App Store Guideline 5.1.1)

public struct BrillyPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss
    public let surfaceStyle: SurfaceStyle

    public init(surfaceStyle: SurfaceStyle) {
        self.surfaceStyle = surfaceStyle
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: surfaceStyle)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        policyCard(
                            title: "100% Local-First & Private",
                            body: "BrillyDer stores all analyzed games, FSRS opening progress, mistake decks, bookmarks, and preferences strictly on your device. We operate zero developer servers, require no account sign-in, and collect zero personal or behavioral tracking data."
                        )
                        policyCard(
                            title: "Optional Public Chess API Lookups",
                            body: "When you choose to sync games, scout an opponent, or probe <=7-piece endgames, your device connects directly over HTTPS to public third-party chess APIs: lichess.org, api.chess.com, and tablebase.lichess.ovh. No developer proxy is involved."
                        )
                        policyCard(
                            title: "Photo Library Permission",
                            body: "Add-Only Photo Library access is requested solely if you tap Save Photo on a Share Card. BrillyDer never reads or accesses your existing photos."
                        )

                        if let url = URL(string: "https://dund0g.github.io/brillyder/privacy.html") {
                            Link(destination: url) {
                                Label("Open Full Online Privacy Policy", systemImage: "safari.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BrillyPalette.voidBg)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Capsule().fill(BrillyPalette.brillyTeal))
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Privacy Policy")
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

    private func policyCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BrillyPalette.brillyTeal)
            Text(body)
                .font(.caption)
                .foregroundStyle(BrillyPalette.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .brillySurface(surfaceStyle, cornerRadius: 16)
    }
}

// MARK: - In-App Third-Party Licenses & Open-Source Credits Sheet (BSD-3, Apache-2.0, MIT, CC BY 4.0)

private struct BrillyLicensesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let surfaceStyle: SurfaceStyle

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: surfaceStyle)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("BrillyDer's native iOS app embeds zero GPL dependencies. All bundled chess piece artwork is permissively licensed:")
                            .font(.caption)
                            .foregroundStyle(BrillyPalette.inkSecondary)

                        licenseCard(
                            name: "Classic Piece Set (cburnett)",
                            license: "BSD-3-Clause",
                            author: "Colin M.L. Burnett (Wikimedia Commons)",
                            notice: "Redistribution and use in source and binary forms, with or without modification, are permitted under the 3-Clause BSD License provided copyright notice and disclaimer are retained. Provided \"AS IS\" without warranty."
                        )
                        licenseCard(
                            name: "Chessnut Piece Set",
                            license: "Apache License 2.0",
                            author: "Alexis Luengas (Chessnut)",
                            notice: "Licensed under the Apache License, Version 2.0 (apache.org/licenses/LICENSE-2.0). Distributed on an \"AS IS\" basis without warranties or conditions of any kind."
                        )
                        licenseCard(
                            name: "Spatial Piece Set",
                            license: "MIT License",
                            author: "Maurizio Monge",
                            notice: "Permission is hereby granted, free of charge, under the MIT License to use, copy, modify, and distribute the artwork, subject to the above copyright notice. Provided \"AS IS\"."
                        )
                        licenseCard(
                            name: "Minimal Piece Set (kiwen-suwi)",
                            license: "CC BY 4.0",
                            author: "neverRare (Creative Commons Attribution 4.0 International)",
                            notice: "Artwork licensed under CC BY 4.0 (creativecommons.org/licenses/by/4.0/). Converted to high-resolution PNG sprites for native rendering."
                        )
                        licenseCard(
                            name: "Chess Engine, Spaced Repetition & Tablebase Credits",
                            license: "Permissive / Public API",
                            author: "BrillyNative Swift Engine · FSRS · PeSTO · Lichess Syzygy",
                            notice: "On-device analysis uses BrillyNative (pure Swift, MIT) inspired by PeSTO tapered piece-square evaluation tables; opening scheduling implements FSRS-6; optional <=7-piece lookups query Lichess's public Syzygy Tablebase API."
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Licenses & Credits")
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

    private func licenseCard(name: String, license: String, author: String, notice: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                Spacer(minLength: 6)
                Text(license)
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(BrillyPalette.brillyTeal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(BrillyPalette.brillyTeal.opacity(0.16)))
            }
            Text(author)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BrillyPalette.inkSecondary)
            Text(notice)
                .font(.caption2)
                .foregroundStyle(Color(hex: 0xCBD5E1))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .brillySurface(surfaceStyle, cornerRadius: 16)
    }
}
