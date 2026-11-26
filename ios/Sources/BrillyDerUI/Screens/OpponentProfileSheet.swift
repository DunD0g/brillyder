import SwiftUI
import BrillyDerCore

/// Pro-only Quick Opponent Profile & Recent Games lookup sheet, triggered by tapping an opponent pill in Analyze.
public struct OpponentProfileSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    public let username: String
    public let initialPlatform: GameSource

    @State private var platform: GameSource
    @State private var games: [GameRecord] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil

    public init(username: String, initialPlatform: GameSource) {
        self.username = username
        self.initialPlatform = initialPlatform == .chesscom ? .chesscom : .lichess
        _platform = State(initialValue: initialPlatform == .chesscom ? .chesscom : .lichess)
    }

    private var stats: (wins: Int, draws: Int, losses: Int, avgRating: Int?) {
        var w = 0, d = 0, l = 0
        var ratings: [Int] = []
        let handles = [username]
        for g in games {
            switch g.userResult(handles: handles) {
            case "W": w += 1
            case "D": d += 1
            case "L": l += 1
            default: break
            }
            let side = g.resolvedUserColor(handles: handles)
            if side == .white, let r = g.white.rating { ratings.append(r) }
            else if side == .black, let r = g.black.rating { ratings.append(r) }
        }
        let avg = ratings.isEmpty ? nil : ratings.reduce(0, +) / ratings.count
        return (w, d, l, avg)
    }

    private var topOpenings: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for g in games where !g.openingName.isEmpty && g.openingName != "Standard Game" {
            counts[g.openingName, default: 0] += 1
        }
        return counts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { ($0.key, $0.value) }
    }

    public var body: some View {
        let masked = store.maskedPlayerName(username, opponent: nil, side: .black)

        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollView {
                    VStack(spacing: 14) {
                        // Profile Header Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(BrillyPalette.warpPurple.opacity(0.22))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "person.fill.viewfinder")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(BrillyPalette.warpPurpleText)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(masked.text)
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                        .blur(radius: masked.isBlurred ? 5 : 0)
                                    HStack(spacing: 6) {
                                        Text(platform == .chesscom ? "Chess.com" : "Lichess")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(BrillyPalette.brillyTeal)
                                        if let rating = stats.avgRating {
                                            Text("· ~\(rating)")
                                                .font(.caption.monospacedDigit().weight(.bold))
                                                .foregroundStyle(BrillyPalette.inkSecondary)
                                        }
                                    }
                                }

                                Spacer()

                                Button {
                                    dismiss()
                                    Task {
                                        await store.runScout(opponent: username, platform: platform)
                                    }
                                } label: {
                                    Label("Full Scout", systemImage: "binoculars.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(BrillyPalette.voidBg)
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 7)
                                        .background(Capsule().fill(BrillyPalette.warpPurple))
                                }
                                .buttonStyle(BrillyPressScaleStyle())
                            }

                            Picker("Platform", selection: $platform) {
                                Text("Lichess").tag(GameSource.lichess)
                                Text("Chess.com").tag(GameSource.chesscom)
                            }
                            .pickerStyle(.segmented)

                            if !games.isEmpty {
                                HStack(spacing: 10) {
                                    recordPill("W", count: stats.wins, color: Color(hex: 0x22C55E))
                                    recordPill("D", count: stats.draws, color: BrillyPalette.goldAmber)
                                    recordPill("L", count: stats.losses, color: BrillyPalette.blunderRose)
                                }

                                if !topOpenings.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("FAVORITE OPENINGS")
                                            .font(.system(size: 10, weight: .bold))
                                            .tracking(0.8)
                                            .foregroundStyle(BrillyPalette.inkSecondary)
                                        ForEach(topOpenings, id: \.name) { item in
                                            HStack {
                                                Text(item.name)
                                                    .font(.caption.weight(.medium))
                                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Text("\(item.count)g")
                                                    .font(.caption2.monospacedDigit().weight(.bold))
                                                    .foregroundStyle(BrillyPalette.brillyTeal)
                                            }
                                        }
                                    }
                                    .padding(.top, 2)
                                }
                            }
                        }
                        .padding(14)
                        .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.warpPurple)

                        if isLoading {
                            HStack(spacing: 10) {
                                ProgressView().tint(BrillyPalette.brillyTeal)
                                Text("Fetching recent public games…")
                                    .font(.subheadline)
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(28)
                            .brillySurface(store.surfaceStyle, cornerRadius: 16)
                        } else if let errorMessage {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title3)
                                    .foregroundStyle(BrillyPalette.goldAmber)
                                Text(errorMessage)
                                    .font(.subheadline)
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(24)
                            .brillySurface(store.surfaceStyle, cornerRadius: 16)
                        } else if games.isEmpty {
                            Text("No recent standard games found on \(platform == .chesscom ? "Chess.com" : "Lichess"). Try switching platform above.")
                                .font(.subheadline)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(24)
                                .brillySurface(store.surfaceStyle, cornerRadius: 16)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("RECENT GAMES (\(games.count)) · TAP TO ANALYZE")
                                    .font(.caption2.weight(.bold))
                                    .tracking(0.8)
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                    .padding(.horizontal, 4)

                                ForEach(games) { g in
                                    let res = g.userResult(handles: [username])
                                    let resColor: Color = res == "W" ? Color(hex: 0x22C55E) : (res == "L" ? BrillyPalette.blunderRose : BrillyPalette.goldAmber)
                                    let wMasked = store.maskedPlayerName(g.white.name, opponent: g.black.name, side: .white)
                                    let bMasked = store.maskedPlayerName(g.black.name, opponent: g.white.name, side: .black)

                                    Button {
                                        let rebound = g.reboundUserColor(for: store.userHandles)
                                        dismiss()
                                        Task { @MainActor in
                                            try? await Task.sleep(for: .milliseconds(300))
                                            store.startAnalysis(for: rebound, isManualSelection: true, switchToAnalyze: true)
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(resColor)
                                                .frame(width: 4, height: 34)
                                            VStack(alignment: .leading, spacing: 3) {
                                                HStack(spacing: 4) {
                                                    Text(wMasked.text)
                                                        .blur(radius: wMasked.isBlurred ? 5 : 0)
                                                    Text("vs")
                                                        .foregroundStyle(BrillyPalette.inkSecondary)
                                                    Text(bMasked.text)
                                                        .blur(radius: bMasked.isBlurred ? 5 : 0)
                                                }
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(BrillyPalette.inkPrimary)
                                                .lineLimit(1)

                                                Text(g.openingName)
                                                    .font(.caption2)
                                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                                    .lineLimit(1)
                                            }
                                            Spacer(minLength: 4)
                                            VStack(alignment: .trailing, spacing: 2) {
                                                Text(g.resultString)
                                                    .font(.caption2.monospacedDigit().weight(.black))
                                                    .foregroundStyle(resColor)
                                                Text(g.timeControlLabel)
                                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                            }
                                        }
                                        .padding(11)
                                        .brillySurface(store.surfaceStyle, cornerRadius: 14, interactive: true)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Opponent Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: platform) {
                await loadOpponentGames()
            }
        }
    }

    private func recordPill(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2.weight(.black))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(BrillyPalette.inkPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.3), lineWidth: 0.8))
        )
    }

    private func loadOpponentGames() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched: [GameRecord]
            if platform == .chesscom {
                fetched = try await ChessComClient.fetchRecentGames(username: username, maxGames: 15)
            } else {
                fetched = try await LichessClient.fetchRecentGames(username: username, maxGames: 15)
            }
            guard !Task.isCancelled else { return }
            games = fetched
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            games = []
            isLoading = false
        }
    }
}
