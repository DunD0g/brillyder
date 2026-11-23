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
        .sheet(isPresented: $bindableStore.showingSettings) {
            CockpitSettingsSheet()
                .environment(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    @ToolbarContentBuilder
    private var cockpitToolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            BrillyGlassCluster(style: store.surfaceStyle, spacing: 8) {
                HStack(spacing: 8) {
                    if store.dailyStreakDays > 0 {
                        Label("\(store.dailyStreakDays)d", systemImage: "flame.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.goldAmber)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                    }

                    Button {
                        store.showingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cockpit Settings")
                }
            }
        }
    }
}
