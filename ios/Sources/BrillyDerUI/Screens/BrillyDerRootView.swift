import SwiftUI
import StoreKit
import BrillyDerCore

public struct BrillyDerRootView: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.requestReview) private var requestReview

    public init() {}

    public var body: some View {
        @Bindable var bindableStore = store

        ZStack {
            CosmicVoidBackdrop(style: store.surfaceStyle)

            TabView(selection: $bindableStore.selectedTab) {
                NavigationStack {
                    TrainTabView()
                        .toolbar { cockpitToolbar }
                }
                .tabItem {
                    Label(BrillyTab.train.title, systemImage: BrillyTab.train.systemImage)
                }
                .tag(BrillyTab.train)
                .brillyTabBarChrome(store.surfaceStyle)

                NavigationStack {
                    GamesTabView()
                        .toolbar { cockpitToolbar }
                }
                .tabItem {
                    Label(BrillyTab.games.title, systemImage: BrillyTab.games.systemImage)
                }
                .tag(BrillyTab.games)
                .brillyTabBarChrome(store.surfaceStyle)

                NavigationStack {
                    AnalyzeTabView()
                        .toolbar { cockpitToolbar }
                }
                .tabItem {
                    Label(BrillyTab.analyze.title, systemImage: BrillyTab.analyze.systemImage)
                }
                .tag(BrillyTab.analyze)
                .brillyTabBarChrome(store.surfaceStyle)

                NavigationStack {
                    OpeningsTabView()
                        .toolbar { cockpitToolbar }
                }
                .tabItem {
                    Label(BrillyTab.openings.title, systemImage: BrillyTab.openings.systemImage)
                }
                .tag(BrillyTab.openings)
                .brillyTabBarChrome(store.surfaceStyle)

                NavigationStack {
                    InsightsTabView()
                        .toolbar { cockpitToolbar }
                }
                .tabItem {
                    Label(BrillyTab.insights.title, systemImage: BrillyTab.insights.systemImage)
                }
                .tag(BrillyTab.insights)
                .brillyTabBarChrome(store.surfaceStyle)
            }
            .tint(BrillyPalette.brillyTeal)
        }
        // Safe-area-aware floating HUD banners positioned cleanly below the navigation toolbar
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if let celebration = store.activeCelebration {
                    AlienCelebrationBanner(event: celebration, surfaceStyle: store.surfaceStyle) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            store.activeCelebration = nil
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 52)
                }

                if store.isBatchAnalyzing && store.selectedTab != .games {
                    globalBatchPill
                        .padding(.horizontal, 16)
                        .padding(.top, store.activeCelebration == nil ? 52 : 0)
                }
            }
        }
        .environment(\.brillyPieceSet, store.effectivePieceSet)
        .sheet(isPresented: $bindableStore.showingSettings) {
            CockpitSettingsSheet()
                .environment(store)
                .environment(\.brillyPieceSet, store.effectivePieceSet)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $bindableStore.showingVault) {
            BrillyVaultSheet()
                .environment(store)
                .environment(\.brillyPieceSet, store.effectivePieceSet)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $bindableStore.showingProPaywall) {
            BrillyProPaywallSheet(highlightedFeature: store.proPaywallFeature)
                .environment(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $bindableStore.showingWelcomeGuide, onDismiss: {
            if !store.hasCompletedOnboarding {
                store.completeOnboarding()
            }
        }) {
            BrillyWelcomeGuideSheet()
                .environment(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: store.pendingReviewRequestVersion) { _, _ in
            attemptPendingReviewPrompt()
        }
        .onChange(of: store.showingSettings) { _, _ in
            attemptPendingReviewPrompt()
        }
        .onChange(of: store.showingVault) { _, _ in
            attemptPendingReviewPrompt()
        }
        .onChange(of: store.showingProPaywall) { _, _ in
            attemptPendingReviewPrompt()
        }
        .onChange(of: store.showingWelcomeGuide) { _, _ in
            attemptPendingReviewPrompt()
        }
    }

    private func attemptPendingReviewPrompt() {
        guard let version = store.pendingReviewRequestVersion,
              !store.showingSettings,
              !store.showingVault,
              !store.showingProPaywall,
              !store.showingWelcomeGuide else { return }
        store.markReviewPrompted(version: version)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            requestReview()
        }
    }

    private var globalBatchPill: some View {
        let pct = Int((store.batchProgress * 100).rounded())
        return HStack(spacing: 10) {
            Button {
                store.selectedTab = .games
            } label: {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(BrillyPalette.brillyTeal)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.copy(cosmic: "Batch Scan · \(pct)%", classic: "Batch Analyzing · \(pct)%"))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        Text(store.batchCurrentLabel)
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Button("Stop") {
                store.cancelBatchAnalysis()
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(BrillyPalette.blunderRose)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(BrillyPalette.blunderRose.opacity(0.18)))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .brillySurface(store.surfaceStyle, cornerRadius: 16, tint: BrillyPalette.brillyTeal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ToolbarContentBuilder
    private var cockpitToolbar: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button {
                withAnimation(.snappy) {
                    store.selectedTab = .train
                    store.selectedTrainMode = .daily
                }
                store.triggerHaptic(.move)
            } label: {
                BrillyLogoMark(size: 30, circular: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("BrillyDer Home")
        }
        #else
        ToolbarItem(placement: .navigation) {
            Button {
                store.selectedTab = .train
                store.selectedTrainMode = .daily
            } label: {
                BrillyLogoMark(size: 28, circular: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("BrillyDer Home")
        }
        #endif

        if store.dailyStreakDays > 0 {
            ToolbarItem(placement: .automatic) {
                Button {
                    store.selectedTrainMode = .daily
                    store.selectedTab = .train
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.goldAmber)
                        Text("\(store.dailyStreakDays)d")
                            .font(.caption.monospacedDigit().weight(.black))
                            .foregroundStyle(BrillyPalette.goldAmber)
                    }
                }
                .accessibilityLabel("Daily training streak")
                .accessibilityValue("\(store.dailyStreakDays) days")
            }
        }

        ToolbarItem(placement: .automatic) {
            Button {
                store.showingVault = true
            } label: {
                HStack(spacing: 5) {
                    BrillyGemIcon(size: 16, color: BrillyPalette.brillyTeal)
                    Text("\(store.vaultCollection.headlineBrilliantCount)")
                        .font(.caption.monospacedDigit().weight(.black))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                }
            }
            .accessibilityLabel(store.copy(cosmic: "Brilly Vault", classic: "Trophy Vault"))
            .accessibilityValue("\(store.vaultCollection.headlineBrilliantCount) brilliant moves")
        }

        ToolbarItem(placement: .automatic) {
            Button {
                store.showingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
            }
            .accessibilityLabel(store.copy(cosmic: "Cockpit Settings", classic: "Settings"))
        }
    }
}
