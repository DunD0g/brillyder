import SwiftUI
import StoreKit
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
    @State private var accountStatusMessage: String? = nil
    @State private var showingTermsSheet = false
    @State private var showingLicensesSheet = false
    @State private var previewMoveTick: Int = 0
    @State private var editingLichessHandle = false
    @State private var editingChessComHandle = false

    private static let previewBoard: ChessBoard = (try? ChessBoard(fen: "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQkq - 0 5")) ?? ChessBoard()

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // 1. Membership Status (always easy to find at top)
                        membershipCard

                        // 2. Accounts & Startup
                        settingsGroupHeader("Accounts & Sync", icon: "person.crop.circle.fill")
                        chessAccountsCard
                        launchAndAutoSyncCard

                        // 3. Engine & Daily Training
                        settingsGroupHeader("Engine & Training", icon: "cpu")
                        engineDepthCard
                        dailyRepertoireCard

                        // 4. Board & Visual Appearance (Preview right above pickers)
                        settingsGroupHeader("Board & Appearance", icon: "checkerboard.rectangle")
                        liveBoardPreviewSection
                        boardThemeCard
                        pieceStyleCard
                        surfaceAppearanceCard

                        // 5. Coach, Audio & Feedback
                        settingsGroupHeader("Coach & Feedback", icon: "speaker.wave.2.fill")
                        coachAndFeedbackCard

                        // 6. Backup & Data Portability
                        settingsGroupHeader("Backup & Data", icon: "arrow.triangle.2.circlepath.doc.on.clipboard")
                        backupPortabilityCard

                        // 7. Founder Admin Creator Studio (Admin target only)
                        if store.edition == .founderAdmin {
                            settingsGroupHeader("Founder Creator Studio", icon: "video.badge.checkmark")
                            founderCreatorStudioCard
                        }

                        // 8. About, Help & Legal
                        settingsGroupHeader("About & Legal", icon: "info.circle.fill")
                        aboutAndLegalCard
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
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
            .scrollDismissesKeyboard(.interactively)
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

    private func settingsGroupHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(BrillyPalette.brillyTeal)
            Text(title.uppercased())
                .font(.caption2.weight(.black))
                .tracking(0.9)
                .foregroundStyle(BrillyPalette.inkSecondary)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
    }

    // MARK: - 1. Membership Card

    private var membershipCard: some View {
        @Bindable var bindableStore = store
        return VStack(alignment: .leading, spacing: 10) {
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
                Text("Personal Founder build (`com.brillyder.admin`) — all Pro features unlocked permanently.")
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
                        .padding(.vertical, 10)
                        .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                }
                .buttonStyle(BrillyPressScaleStyle())

                Toggle(isOn: $bindableStore.simulateFreeTierInAdmin) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Simulate Free Tier Locks")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Text("Admin build only — test Free gates & paywall anytime.")
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
                    Text("Free Plan · \(store.remainingFreeAnalysesToday) of \(BrillyEntitlementPolicy.freeDailyAnalysisLimit) daily game analyses left today. Upgrade for Ultra NNUE (~3300+ Elo) & Cloud SF16 review, unlimited batch analysis, all \(store.starterCourses.count) opening courses, Woodpecker, Never Give Up & Endgame Labs, and all 4 piece sets.")
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
    }

    // MARK: - 2. Accounts & Launch

    private var chessAccountsCard: some View {
        @Bindable var bindableStore = store
        return VStack(alignment: .leading, spacing: 12) {
            Text("CHESS ACCOUNTS")
                .font(.caption.weight(.bold))
                .tracking(1.0)
                .foregroundStyle(BrillyPalette.brillyTeal)

            VStack(alignment: .leading, spacing: 6) {
                Text("Lichess Username")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkSecondary)
                let cleanLichess = store.lichessUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                if store.effectiveCreatorNameMask != .off && !cleanLichess.isEmpty && !editingLichessHandle {
                    let masked = store.maskedProfileUsername(cleanLichess)
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Text(masked.text)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .lineLimit(1)
                                .blur(radius: masked.isBlurred ? 5 : 0)
                            Spacer(minLength: 4)
                            Image(systemName: masked.isBlurred ? "eye.slash.fill" : "theatermasks.fill")
                                .font(.caption2)
                                .foregroundStyle(BrillyPalette.goldAmber.opacity(0.8))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))

                        Button {
                            editingLichessHandle = true
                            store.triggerHaptic(.move)
                        } label: {
                            Text("Edit")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 8) {
                        TextField("Enter Lichess handle", text: $bindableStore.lichessUsername)
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            #endif
                            .onSubmit {
                                store.lockHandle(for: .lichess)
                                editingLichessHandle = false
                                accountStatusMessage = "Lichess handle saved"
                                store.triggerHaptic(.success)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                            .foregroundStyle(BrillyPalette.inkPrimary)

                        Button {
                            store.lockHandle(for: .lichess)
                            editingLichessHandle = false
                            accountStatusMessage = "Lichess handle saved"
                            store.triggerHaptic(.success)
                        } label: {
                            Text("Save")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.voidBg)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BrillyPalette.brillyTeal))
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        if !cleanLichess.isEmpty {
                            Button {
                                store.clearHandle(for: .lichess)
                                editingLichessHandle = false
                                accountStatusMessage = "Lichess handle cleared"
                                store.triggerHaptic(.move)
                            } label: {
                                Text("Clear")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.blunderRose)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BrillyPalette.blunderRose.opacity(0.14)))
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Chess.com Username")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkSecondary)
                let cleanChessCom = store.chessComUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                if store.effectiveCreatorNameMask != .off && !cleanChessCom.isEmpty && !editingChessComHandle {
                    let masked = store.maskedProfileUsername(cleanChessCom)
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Text(masked.text)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .lineLimit(1)
                                .blur(radius: masked.isBlurred ? 5 : 0)
                            Spacer(minLength: 4)
                            Image(systemName: masked.isBlurred ? "eye.slash.fill" : "theatermasks.fill")
                                .font(.caption2)
                                .foregroundStyle(BrillyPalette.goldAmber.opacity(0.8))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))

                        Button {
                            editingChessComHandle = true
                            store.triggerHaptic(.move)
                        } label: {
                            Text("Edit")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.12)))
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 8) {
                        TextField("Enter Chess.com handle", text: $bindableStore.chessComUsername)
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            #endif
                            .onSubmit {
                                store.lockHandle(for: .chesscom)
                                editingChessComHandle = false
                                accountStatusMessage = "Chess.com handle saved"
                                store.triggerHaptic(.success)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                            .foregroundStyle(BrillyPalette.inkPrimary)

                        Button {
                            store.lockHandle(for: .chesscom)
                            editingChessComHandle = false
                            accountStatusMessage = "Chess.com handle saved"
                            store.triggerHaptic(.success)
                        } label: {
                            Text("Save")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.voidBg)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10).fill(BrillyPalette.brillyTeal))
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        if !cleanChessCom.isEmpty {
                            Button {
                                store.clearHandle(for: .chesscom)
                                editingChessComHandle = false
                                accountStatusMessage = "Chess.com handle cleared"
                                store.triggerHaptic(.move)
                            } label: {
                                Text("Clear")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.blunderRose)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(BrillyPalette.blunderRose.opacity(0.14)))
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let msg = accountStatusMessage {
                Text(msg)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BrillyPalette.brillyTeal)
            } else {
                Text("Saved handles stay locked as a clean pill on the Games tab. Edit or clear them here anytime.")
                    .font(.caption2)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20)
    }

    private var launchAndAutoSyncCard: some View {
        @Bindable var bindableStore = store
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Default Launch Screen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                    Spacer()
                    Menu {
                        ForEach(BrillyTab.allCases) { tab in
                            Button {
                                store.defaultLaunchTab = tab
                                store.triggerHaptic(.move)
                            } label: {
                                Label(
                                    tab == .analyze ? "Analyze (Latest Game)" : (tab == .train ? "Train (Default)" : tab.title),
                                    systemImage: store.defaultLaunchTab == tab ? "checkmark" : tab.systemImage
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: store.defaultLaunchTab.systemImage)
                                .font(.caption.weight(.semibold))
                            Text(store.defaultLaunchTab == .analyze ? "Analyze (Latest)" : store.defaultLaunchTab.title)
                                .font(.caption.weight(.bold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(BrillyPalette.brillyTeal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(BrillyPalette.brillyTeal.opacity(0.14))
                                .overlay(Capsule().strokeBorder(BrillyPalette.brillyTeal.opacity(0.35), lineWidth: 1))
                        )
                    }
                }

                Text("Choose which tab BrillyDer opens on. Pick Analyze to jump straight into your latest game.")
                    .font(.caption2)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }

            Divider().overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 6) {
                if store.hasProAccess {
                    Toggle(isOn: $bindableStore.autoSyncOnLaunch) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Sync on Open")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            Text("Quietly fetches your latest Lichess/Chess.com games on launch & resume.")
                                .font(.caption2)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                        }
                    }
                    .tint(BrillyPalette.brillyTeal)
                } else {
                    Button {
                        localProFeature = "Instant Auto-Sync & Latest-Game Launch"
                        showingLocalProSheet = true
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Auto-Sync on Open")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                    Text("PRO")
                                        .font(.system(size: 9, weight: .black, design: .rounded))
                                        .foregroundStyle(BrillyPalette.voidBg)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(BrillyPalette.warpPurpleText))
                                }
                                Text("Quietly sync on launch & auto-load your latest game. Manual sync is always free.")
                                    .font(.caption2)
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "lock.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.warpPurpleText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20)
    }

    // MARK: - 3. Engine & Daily Training

    private var engineDepthCard: some View {
        let offlinePresets: [AnalysisDepthPreset] = [.fast, .balanced, .deep, .ultra]
        let offlineSelectionBinding = Binding<AnalysisDepthPreset>(
            get: {
                let eff = store.effectiveAnalysisPreset
                return eff == .cloudUltra ? .ultra : eff
            },
            set: { chosen in
                if chosen == .ultra && !store.hasProAccess {
                    localProFeature = "Ultra Offline NNUE (~3300+ Elo)"
                    showingLocalProSheet = true
                    return
                }
                store.analysisPreset = chosen
                store.triggerHaptic(.move)
            }
        )

        return VStack(alignment: .leading, spacing: 10) {
            Text("Default Offline Engine Depth")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrillyPalette.inkPrimary)

            Picker("Depth", selection: offlineSelectionBinding) {
                ForEach(offlinePresets) { p in
                    let label = (p == .ultra && !store.hasProAccess) ? "Ultra 🔒" : p.title
                    Text(label).tag(p)
                }
            }
            .pickerStyle(.segmented)

            if store.effectiveAnalysisPreset == .cloudUltra {
                Button {
                    store.analysisPreset = .ultra
                    store.triggerHaptic(.move)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "cloud.bolt.fill")
                            .font(.caption2.weight(.bold))
                        Text("Cloud SF active · Switch to Offline Ultra")
                            .font(.caption2.weight(.bold))
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(BrillyPalette.warpPurpleText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BrillyPalette.warpPurple.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(BrillyPalette.warpPurple.opacity(0.35), lineWidth: 0.9)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ENGINE STRENGTH GUIDE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(BrillyPalette.brillyTeal)

                ForEach(AnalysisDepthPreset.allCases) { preset in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: preset.sfSymbol)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(
                                preset.usesCloudEval ? BrillyPalette.warpPurpleText :
                                (preset == .ultra ? BrillyPalette.goldAmber : BrillyPalette.brillyTeal)
                            )
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(preset.title)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                Text("· \(preset.eloEstimate)")
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                                if preset.isSingleGameOnly {
                                    Text("PRO")
                                        .font(.system(size: 8.5, weight: .black, design: .rounded))
                                        .foregroundStyle(BrillyPalette.voidBg)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(BrillyPalette.warpPurpleText))
                                }
                            }
                            Text(preset.detailSummary)
                                .font(.system(size: 10.5))
                                .foregroundStyle(BrillyPalette.inkSecondary)
                        }
                    }
                }

                Text("All 4 defaults above run 100% offline with zero mobile data (Ultra uses Deep for multi-game batches to stay fast). Optional Cloud SF queries Lichess's public Stockfish 16 cloud cache when online — switch anytime via the depth pill next to Analyze.")
                    .font(.system(size: 10))
                    .foregroundStyle(BrillyPalette.inkSecondary.opacity(0.85))
                    .padding(.top, 2)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.brillyTeal)
    }

    private var dailyRepertoireCard: some View {
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
                        Text("\(store.activeDailyOpeningCourseIds.count) of \(store.allCourses.count) openings active in \(store.copy(cosmic: "Orbit Coach & Gravity Check", classic: "Daily Coach & 60s Warmup"))")
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
    }

    // MARK: - 4. Board & Visual Appearance

    private var boardThemeCard: some View {
        @Bindable var bindableStore = store
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BOARD THEME")
                    .font(.caption.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(BrillyPalette.inkSecondary)
                Spacer()
                if !store.hasProAccess {
                    Text("6 Extra · PRO")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BrillyPalette.warpPurpleText)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(BoardThemeID.allCases) { theme in
                    let unlocked = store.isBoardThemeUnlocked(theme)
                    let selected = store.effectiveBoardTheme == theme
                    Button {
                        if !unlocked {
                            localProFeature = "6 Premium Board Themes (Obsidian, Gold, Violet, Seasonal, Prism & Marble)"
                            showingLocalProSheet = true
                            return
                        }
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
                                .lineLimit(1)
                            Spacer()
                            if !unlocked {
                                Image(systemName: "lock.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(BrillyPalette.warpPurpleText)
                            } else if selected {
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

            Divider().overlay(Color.white.opacity(0.08))

            Toggle(isOn: $bindableStore.showBoardCoordinates) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Board Coordinates")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                    Text("Hide a–h / 1–8 labels for clean blindfold-style visualization.")
                        .font(.caption2)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }
            }
            .tint(BrillyPalette.brillyTeal)
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20)
    }

    private var pieceStyleCard: some View {
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
                                        store.effectiveBoardTheme.lightSquare
                                        ChessPieceView(piece: Piece(color: .white, type: .knight), squareSize: 34, pieceSet: set)
                                    }
                                    .frame(width: 38, height: 38)
                                    ZStack {
                                        store.effectiveBoardTheme.darkSquare
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
        .brillySurface(store.surfaceStyle, cornerRadius: 20)
    }

    private var surfaceAppearanceCard: some View {
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
        .brillySurface(store.surfaceStyle, cornerRadius: 20)
    }

    // MARK: - 5. Coach, Audio & Feedback

    private var coachAndFeedbackCard: some View {
        @Bindable var bindableStore = store
        return VStack(alignment: .leading, spacing: 14) {
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

            Divider().overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 6) {
                Text("Menu & Coach Labels")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                Picker("Vibe", selection: $bindableStore.vibeMode) {
                    ForEach(VibeMode.allCases) { v in
                        Text(v.title).tag(v)
                    }
                }
                .pickerStyle(.segmented)
                Text(
                    store.vibeMode == .classic
                        ? "Standard chess wording (e.g., Daily Improvement Plan, 60-Second Warmup, Time Management)."
                        : "Playful space-probe wording (e.g., Daily Flight Plan, 60s Gravity Check, Clock Leaks)."
                )
                .font(.caption2)
                .foregroundStyle(BrillyPalette.inkSecondary)
            }

            Divider().overlay(Color.white.opacity(0.08))

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
    }

    // MARK: - 6. Backup & Data Portability

    private var backupPortabilityCard: some View {
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
        .brillySurface(store.surfaceStyle, cornerRadius: 20)
    }

    // MARK: - 7. Founder Admin Creator & Exhibition Studio

    private var founderCreatorStudioCard: some View {
        @Bindable var bindableStore = store
        return VStack(alignment: .leading, spacing: 10) {
            Label("CREATOR & EXHIBITION STUDIO", systemImage: "video.badge.checkmark")
                .font(.caption.weight(.bold))
                .tracking(0.9)
                .foregroundStyle(BrillyPalette.goldAmber)

            VStack(alignment: .leading, spacing: 5) {
                Text("Player Name Masking")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                Picker("Name Masking", selection: $bindableStore.creatorNameMaskMode) {
                    ForEach(CreatorNameMaskMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(store.creatorNameMaskMode.subtitle)
                    .font(.caption2)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Exhibition Broadcast Theme")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                Picker("Exhibition Theme", selection: $bindableStore.creatorExhibitionTheme) {
                    ForEach(CreatorExhibitionTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            if store.creatorExhibitionTheme != .none {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Event Broadcast Ribbon")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrillyPalette.inkPrimary)

                    TextField("e.g. WORLD CHAMPIONSHIP 2026 (or AUTO)", text: $bindableStore.creatorEventRibbonText)
                        .textFieldStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08)))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach([
                                ("Auto PGN Event", "AUTO"),
                                ("WCC 2026", "WORLD CHAMPIONSHIP 2026"),
                                ("WCC Game 1", "WCC 2026 · GAME 1"),
                                ("Rapid & Blitz 2026", "WORLD RAPID & BLITZ 2026"),
                            ], id: \.0) { label, value in
                                Button {
                                    store.creatorEventRibbonText = value
                                    store.triggerHaptic(.move)
                                } label: {
                                    Text(label)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(store.creatorEventRibbonText == value ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule().fill(
                                                store.creatorEventRibbonText == value
                                                    ? BrillyPalette.goldAmber
                                                    : Color.white.opacity(0.08)
                                            )
                                        )
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Toggle(isOn: $bindableStore.creatorShowHandleOnCards) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Show @brillyder on Share Cards")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                    Text("Adds a crisp @brillyder handle pill to exported social cards.")
                        .font(.caption2)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }
            }
            .tint(BrillyPalette.goldAmber)
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.goldAmber)
    }

    // MARK: - 8. About, Help & Legal

    private var aboutAndLegalCard: some View {
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
                    ? "BrillyDer Founder Admin · BrillyChess NNUE (~3300+ Elo) · 100% On-Device"
                    : "BrillyDer · BrillyChess NNUE (~3300+ Elo) · 100% On-Device & Local-First"
            )
            .font(.caption)
            .foregroundStyle(BrillyPalette.inkSecondary)

            Group {
                switch store.effectiveCreatorNameMask {
                case .off:
                    Text("Crafted independently by Luke Dunwell")
                case .blurred:
                    HStack(spacing: 3) {
                        Text("Crafted independently by")
                        Text("Luke Dunwell")
                            .blur(radius: 5)
                    }
                case .anonymous, .brillyFun:
                    Text("Crafted independently by BrillyDer")
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(BrillyPalette.inkSecondary.opacity(0.85))

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
                if let mailURL = URL(string: "mailto:brillyder@gmail.com?subject=BrillyDer%20iOS%20Support") {
                    Link(destination: mailURL) {
                        Label("Contact Support", systemImage: "envelope.fill")
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                }

                if let supportURL = URL(string: "https://dund0g.github.io/brillyder/support.html") {
                    Link(destination: supportURL) {
                        Label("Help & FAQ", systemImage: "questionmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .foregroundStyle(BrillyPalette.brillyTeal)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BrillyPalette.brillyTeal.opacity(0.14)))
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                }
            }

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

    private var liveBoardPreviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LIVE BOARD PREVIEW")
                    .font(.caption.weight(.bold))
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
                    Text("\(store.effectiveBoardTheme.title) · \(store.effectivePieceSet.title)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }
            }

            HStack {
                Spacer()
                let previewFen = "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQkq - \(previewMoveTick % 12) \(5 + previewMoveTick)"
                let previewBoard = (try? ChessBoard(fen: previewFen)) ?? Self.previewBoard
                InteractiveChessBoardView(
                    board: previewBoard,
                    orientation: .white,
                    theme: store.effectiveBoardTheme,
                    surfaceStyle: store.surfaceStyle,
                    interactive: false,
                    lastMove: (Square(unchecked: 5), Square(unchecked: 26))
                )
                .frame(width: 210, height: 210)
                Spacer()
            }
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20)
    }

    private var appVersionString: String {
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.11.3"
        let bld = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "15"
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
                            body: "When you choose to sync games, scout an opponent, probe <=7-piece endgames, or use optional Cloud Eval mode, your device connects directly over HTTPS to public third-party chess APIs: lichess.org (including lichess.org/api/cloud-eval for board FEN lookups), api.chess.com, and tablebase.lichess.ovh. No developer proxy is involved."
                        )
                        policyCard(
                            title: "In-App Purchases (Apple StoreKit)",
                            body: "Optional Brilly/Der Pro subscriptions and Lifetime unlocks are processed solely by Apple through StoreKit 2. BrillyDer never receives your payment details or Apple Account credentials."
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

                        if let mailURL = URL(string: "mailto:brillyder@gmail.com?subject=BrillyDer%20Privacy%20%26%20Support") {
                            Link(destination: mailURL) {
                                Label("Contact Support (brillyder@gmail.com)", systemImage: "envelope.fill")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Capsule().fill(Color.white.opacity(0.10)))
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
                            name: "Renegade Chess Engine (v1.3.1 NNUE)",
                            license: "MIT License",
                            author: "Copyright © 2022–2026 Krisztián Peőcz",
                            notice: "On-device game analysis uses Renegade (C++20 ARM64 NEON with pure self-play NNUE weights, MIT License). Permission is hereby granted, free of charge, to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, subject to the MIT copyright and permission notice. Provided \"AS IS\" without warranty."
                        )
                        licenseCard(
                            name: "Fallback Engine, Spaced Repetition & Public Chess APIs",
                            license: "Permissive / Public API",
                            author: "BrillyChess Swift Fallback · FSRS · PeSTO · Lichess Public APIs",
                            notice: "Interactive bot/sandbox drills and automatic fallback use a pure-Swift engine inspired by PeSTO tapered piece-square tables; opening scheduling implements FSRS-6; optional <=7-piece endgame and Cloud Eval lookups query Lichess's public Syzygy Tablebase and Cloud Eval APIs."
                        )
                        licenseCard(
                            name: "Independent Software Notice",
                            license: "Trademarks",
                            author: "BrillyDer",
                            notice: "BrillyDer is an independent application and is not affiliated with, endorsed by, or sponsored by Lichess, Chess.com, or the Stockfish project."
                        )

                        HStack(spacing: 10) {
                            if let apacheURL = URL(string: "https://www.apache.org/licenses/LICENSE-2.0") {
                                Link(destination: apacheURL) {
                                    Label("Apache 2.0", systemImage: "safari")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(BrillyPalette.brillyTeal)
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                                }
                            }
                            if let ccURL = URL(string: "https://creativecommons.org/licenses/by/4.0/") {
                                Link(destination: ccURL) {
                                    Label("CC BY 4.0", systemImage: "safari")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(BrillyPalette.brillyTeal)
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                                }
                            }
                        }
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
