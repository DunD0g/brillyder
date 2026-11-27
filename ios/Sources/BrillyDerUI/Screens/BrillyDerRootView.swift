import SwiftUI
import StoreKit
import BrillyDerCore

public struct BrillyDerRootView: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @State private var reviewPromptTask: Task<Void, Never>? = nil

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

            if store.isShowingLaunchOverlay && store.hasCompletedOnboarding {
                BrillyLaunchTransitionOverlay(
                    statusText: store.launchOverlayStatusText,
                    surfaceStyle: store.surfaceStyle
                ) {
                    withAnimation(.easeOut(duration: 0.24)) {
                        store.dismissLaunchOverlay()
                    }
                }
                .transition(.opacity)
                .zIndex(99)
                .task {
                    try? await Task.sleep(for: .milliseconds(1200))
                    withAnimation(.easeOut(duration: 0.28)) {
                        store.dismissLaunchOverlay()
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.28), value: store.isShowingLaunchOverlay)
        // Safe-area-aware floating HUD banners
        .overlay(alignment: .top) {
            if let celebration = store.activeCelebration {
                AlienCelebrationBanner(event: celebration, surfaceStyle: store.surfaceStyle) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        store.dismissCelebration()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 52)
            }
        }
        // Position persistent Batch Scan pill cleanly above the tab bar so it never covers large navigation titles
        .overlay(alignment: .bottom) {
            if store.isBatchAnalyzing && store.selectedTab != .games {
                globalBatchPill
                    .padding(.horizontal, 16)
                    .padding(.bottom, 70)
            }
        }
        .environment(\.brillyPieceSet, store.effectivePieceSet)
        .environment(\.brillyShowCoordinates, store.showBoardCoordinates)
        .sheet(isPresented: $bindableStore.showingSettings) {
            CockpitSettingsSheet()
                .environment(store)
                .environment(\.brillyPieceSet, store.effectivePieceSet)
                .environment(\.brillyShowCoordinates, store.showBoardCoordinates)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $bindableStore.showingVault) {
            BrillyVaultSheet(initialTab: store.vaultInitialTab)
                .environment(store)
                .environment(\.brillyPieceSet, store.effectivePieceSet)
                .environment(\.brillyShowCoordinates, store.showBoardCoordinates)
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
                .environment(\.brillyPieceSet, store.effectivePieceSet)
                .environment(\.brillyShowCoordinates, store.showBoardCoordinates)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: store.pendingReviewRequestVersion) { _, _ in
            attemptPendingReviewPrompt()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                attemptPendingReviewPrompt()
            } else {
                reviewPromptTask?.cancel()
                reviewPromptTask = nil
            }
        }
        .onChange(of: store.showingSettings) { _, showing in
            if showing { store.dismissCelebration() }
            attemptPendingReviewPrompt()
        }
        .onChange(of: store.showingVault) { _, showing in
            if showing { store.dismissCelebration() }
            attemptPendingReviewPrompt()
        }
        .onChange(of: store.showingProPaywall) { _, showing in
            if showing { store.dismissCelebration() }
            attemptPendingReviewPrompt()
        }
        .onChange(of: store.showingWelcomeGuide) { _, showing in
            if showing { store.dismissCelebration() }
            attemptPendingReviewPrompt()
        }
        .onChange(of: store.selectedTab) { _, newTab in
            store.dismissCelebration()
            if newTab == .analyze && !store.hasPinnedManualGameSelection {
                store.autoLoadLatestGameIfAppropriate(switchToAnalyze: false)
            }
        }
    }

    private func attemptPendingReviewPrompt() {
        reviewPromptTask?.cancel()
        reviewPromptTask = nil
        guard scenePhase == .active,
              let version = store.pendingReviewRequestVersion,
              !store.showingSettings,
              !store.showingVault,
              !store.showingProPaywall,
              !store.showingWelcomeGuide else { return }
        reviewPromptTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled,
                  scenePhase == .active,
                  store.pendingReviewRequestVersion == version,
                  !store.showingSettings,
                  !store.showingVault,
                  !store.showingProPaywall,
                  !store.showingWelcomeGuide else { return }
            store.markReviewPrompted(version: version)
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
                            .contentTransition(.numericText())
                            .animation(.snappy(duration: 0.2), value: pct)
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

            Button {
                store.cancelBatchAnalysis()
            } label: {
                Text("Stop")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BrillyPalette.blunderRose)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(BrillyPalette.blunderRose.opacity(0.18)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .brillySurface(store.surfaceStyle, cornerRadius: 16, tint: BrillyPalette.brillyTeal)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                            .contentTransition(.numericText())
                            .foregroundStyle(BrillyPalette.goldAmber)
                    }
                }
                .accessibilityLabel("Daily training streak")
                .accessibilityValue("\(store.dailyStreakDays) days")
            }
        }

        ToolbarItem(placement: .automatic) {
            Button {
                store.openVault(tab: .brilliant)
            } label: {
                HStack(spacing: 4) {
                    Text("!!")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                    Text("\(store.vaultCollection.headlineBrilliantCount)")
                        .font(.caption.monospacedDigit().weight(.black))
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.22), value: store.vaultCollection.headlineBrilliantCount)
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

private struct BrillyLaunchTransitionOverlay: View {
    let statusText: String
    let surfaceStyle: SurfaceStyle
    let onDismiss: () -> Void

    @State private var pulseExpanded: Bool = false

    var body: some View {
        ZStack {
            CosmicVoidBackdrop(style: surfaceStyle)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(BrillyPalette.brillyTeal.opacity(pulseExpanded ? 0.16 : 0.06))
                        .frame(width: pulseExpanded ? 116 : 86, height: pulseExpanded ? 116 : 86)
                        .blur(radius: 12)

                    Circle()
                        .strokeBorder(BrillyPalette.brillyTeal.opacity(pulseExpanded ? 0.45 : 0.15), lineWidth: 1.5)
                        .frame(width: pulseExpanded ? 96 : 78, height: pulseExpanded ? 96 : 78)

                    BrillyLogoMark(size: 70, circular: true)
                }

                BrillyWordmarkView(fontSize: 28)

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(BrillyPalette.brillyTeal)
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }
                .padding(.top, 2)
            }
            .padding(24)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                pulseExpanded = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("BrillyDer launching. \(statusText)")
        .accessibilityHint("Tap to dismiss")
    }
}
