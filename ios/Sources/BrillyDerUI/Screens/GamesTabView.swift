import SwiftUI
import BrillyDerCore

public struct GamesTabView: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var searchText: String = ""
    @State private var showingPgnSheet: Bool = false
    @State private var pgnDraft: String = ""

    private var filteredGames: [GameRecord] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.recentGames }
        return store.recentGames.filter { g in
            g.white.name.lowercased().contains(q)
                || g.black.name.lowercased().contains(q)
                || g.openingName.lowercased().contains(q)
                || g.openingEco.lowercased().contains(q)
        }
    }

    public var body: some View {
        @Bindable var bindableStore = store

        ZStack {
            CosmicVoidBackdrop(style: store.surfaceStyle)

            ScrollView {
                VStack(spacing: 14) {
                    // MARK: - Platform Sync Card
                    VStack(spacing: 12) {
                        Picker("Platform", selection: $bindableStore.syncPlatform) {
                            Text("Lichess").tag(GameSource.lichess)
                            Text("Chess.com").tag(GameSource.chesscom)
                        }
                        .pickerStyle(.segmented)

                        HStack(spacing: 10) {
                            TextField(
                                store.syncPlatform == .chesscom ? "Chess.com username" : "Lichess username",
                                text: store.syncPlatform == .chesscom ? $bindableStore.chessComUsername : $bindableStore.lichessUsername
                            )
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                            .foregroundStyle(BrillyPalette.inkPrimary)

                            Button {
                                Task { await store.syncRecentGames() }
                            } label: {
                                if store.isSyncing {
                                    ProgressView()
                                        .tint(BrillyPalette.voidBg)
                                        .frame(width: 72, height: 40)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(BrillyPalette.brillyTeal))
                                } else {
                                    Text("Sync")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(BrillyPalette.voidBg)
                                        .frame(width: 72, height: 40)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(BrillyPalette.brillyTeal))
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isSyncing)
                        }

                        HStack {
                            Button {
                                showingPgnSheet = true
                            } label: {
                                Label("Paste PGN", systemImage: "doc.on.clipboard")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            if let err = store.syncErrorMessage {
                                Text(err)
                                    .font(.caption)
                                    .foregroundStyle(BrillyPalette.blunderRose)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(16)
                    .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.brillyTeal)

                    // MARK: - Search Field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(BrillyPalette.inkSecondary)
                        TextField("Filter by opponent or opening…", text: $searchText)
                            .textFieldStyle(.plain)
                            .foregroundStyle(BrillyPalette.inkPrimary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .brillySurface(store.surfaceStyle, cornerRadius: 14)

                    // MARK: - Game List
                    LazyVStack(spacing: 10) {
                        ForEach(filteredGames) { game in
                            gameRow(game)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Games")
        .sheet(isPresented: $showingPgnSheet) {
            NavigationStack {
                ZStack {
                    CosmicVoidBackdrop(style: store.surfaceStyle)
                    VStack(spacing: 14) {
                        TextEditor(text: $pgnDraft)
                            .scrollContentBackground(.hidden)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .padding(12)
                            .brillySurface(store.surfaceStyle, cornerRadius: 16)

                        Button {
                            let draft = pgnDraft
                            showingPgnSheet = false
                            pgnDraft = ""
                            store.importAndAnalyzePGN(draft)
                        } label: {
                            Text("Analyze PGN")
                                .font(.headline)
                                .foregroundStyle(BrillyPalette.voidBg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(RoundedRectangle(cornerRadius: 14).fill(BrillyPalette.brillyTeal))
                        }
                        .buttonStyle(.plain)
                        .disabled(pgnDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(16)
                }
                .navigationTitle("Paste PGN")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingPgnSheet = false }
                    }
                }
            }
        }
    }

    private func gameRow(_ game: GameRecord) -> some View {
        let userHandle = store.syncPlatform == .chesscom ? store.chessComUsername : store.lichessUsername
        let res = game.userResult(for: userHandle)
        let accent: Color = res == "W" ? Color(hex: 0x22C55E) : (res == "L" ? BrillyPalette.blunderRose : BrillyPalette.inkSecondary)
        let cached = store.analyzedGames.first(where: { $0.id == game.id })

        return Button {
            store.startAnalysis(for: game)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent)
                    .frame(width: 4, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(game.white.name) vs \(game.black.name)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(game.timeControlLabel)
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(BrillyPalette.inkSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }

                    HStack(spacing: 6) {
                        Text(game.openingName)
                            .font(.caption)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                            .lineLimit(1)
                        Spacer()
                        if let cached {
                            let acc = (game.userColor == .black ? cached.blackSummary : cached.whiteSummary).accuracy
                            Text("\(String(format: "%.0f", acc))% acc")
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                        } else {
                            Label("Analyze", systemImage: "sparkles")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                        }
                    }
                }
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18, interactive: true)
        }
        .buttonStyle(.plain)
    }
}
