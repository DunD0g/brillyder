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

            // Non-blocking floating Alien / Classic celebration toast
            if let celebration = store.activeCelebration {
                VStack {
                    AlienCelebrationBanner(event: celebration, surfaceStyle: store.surfaceStyle) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            store.activeCelebration = nil
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 56)
                    Spacer()
                }
                .zIndex(10)
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

    @ToolbarContentBuilder
    private var cockpitToolbar: some ToolbarContent {
        if store.dailyStreakDays > 0 {
            ToolbarItem(placement: .automatic) {
                Label("\(store.dailyStreakDays)d", systemImage: "flame.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrillyPalette.goldAmber)
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
            .accessibilityLabel("Brilly Vault")
        }

        ToolbarItem(placement: .automatic) {
            Button {
                store.showingSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
            }
            .accessibilityLabel("Cockpit Settings")
        }
    }
}
