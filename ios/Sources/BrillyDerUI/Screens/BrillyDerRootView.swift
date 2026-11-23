import SwiftUI
import BrillyDerCore

public struct BrillyDerRootView: View {
    @Environment(BrillyAppStore.self) private var store

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

                NavigationStack {
                    GamesTabView()
                        .toolbar { cockpitToolbar }
                }
                .tabItem {
                    Label(BrillyTab.games.title, systemImage: BrillyTab.games.systemImage)
                }
                .tag(BrillyTab.games)

                NavigationStack {
                    AnalyzeTabView()
                        .toolbar { cockpitToolbar }
                }
                .tabItem {
                    Label(BrillyTab.analyze.title, systemImage: BrillyTab.analyze.systemImage)
                }
                .tag(BrillyTab.analyze)

                NavigationStack {
                    OpeningsTabView()
                        .toolbar { cockpitToolbar }
                }
                .tabItem {
                    Label(BrillyTab.openings.title, systemImage: BrillyTab.openings.systemImage)
                }
                .tag(BrillyTab.openings)

                NavigationStack {
                    InsightsTabView()
                        .toolbar { cockpitToolbar }
                }
                .tabItem {
                    Label(BrillyTab.insights.title, systemImage: BrillyTab.insights.systemImage)
                }
                .tag(BrillyTab.insights)
            }
            .tint(BrillyPalette.brillyTeal)
        }
        // Safe-area-aware floating HUD banners (never obscured by Dynamic Island or notch)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                if let celebration = store.activeCelebration {
                    AlienCelebrationBanner(event: celebration, surfaceStyle: store.surfaceStyle) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            store.activeCelebration = nil
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                }

                if store.isBatchAnalyzing && store.selectedTab != .games {
                    globalBatchPill
                        .padding(.horizontal, 16)
                        .padding(.top, store.activeCelebration == nil ? 6 : 0)
                }
            }
        }
        .sheet(isPresented: $bindableStore.showingSettings) {
            CockpitSettingsSheet()
                .environment(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $bindableStore.showingVault) {
            BrillyVaultSheet()
                .environment(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
        if store.dailyStreakDays > 0 {
            ToolbarItem(placement: .automatic) {
                Button {
                    store.selectedTrainMode = .daily
                    store.selectedTab = .train
                } label: {
                    Label("\(store.dailyStreakDays)d", systemImage: "flame.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.goldAmber)
                }
                .accessibilityLabel("Daily training streak: \(store.dailyStreakDays) days")
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
