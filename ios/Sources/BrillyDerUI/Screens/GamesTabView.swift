import SwiftUI
import BrillyDerCore

public struct GamesTabView: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var searchText: String = ""
    @State private var resultFilter: String = "All" // All | W | D | L | Unanalyzed
    @State private var showingPgnSheet: Bool = false
    @State private var showingPositionEditor: Bool = false
    @State private var showingScoutSheet: Bool = false
    @State private var pgnDraft: String = ""
    @State private var pgnError: String? = nil
    @State private var scoutDraft: String = ""
    @State private var scoutPlatform: GameSource = .lichess

    private var filteredGames: [GameRecord] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let analyzedIds = Set(store.analyzedGames.map(\.id))
        let handles = store.userHandles
        return store.recentGames.filter { g in
            if resultFilter == "Unanalyzed" && analyzedIds.contains(g.id) { return false }
            if ["W", "D", "L"].contains(resultFilter) && g.userResult(handles: handles) != resultFilter {
                return false
            }
            guard !q.isEmpty else { return true }
            return g.white.name.lowercased().contains(q)
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
                    // MARK: - 1. Platform Sync Card
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
                            .submitLabel(.go)
                            #endif
                            .onSubmit {
                                store.persistToDisk()
                                Task { await store.syncRecentGames() }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                            .foregroundStyle(BrillyPalette.inkPrimary)

                            Button {
                                store.persistToDisk()
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

                        // Compact Tools Row: Paste PGN | Board Editor | Scout
                        HStack(spacing: 8) {
                            toolChip("Paste PGN", icon: "doc.on.clipboard") {
                                pgnError = nil
                                showingPgnSheet = true
                            }
                            toolChip("Board Editor", icon: "square.grid.3x3.topleft.filled") { showingPositionEditor = true }
                            toolChip(store.isScouting ? "Scouting…" : "Scout", icon: "binoculars.fill") { showingScoutSheet = true }
                        }

                        if store.isScouting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(BrillyPalette.warpPurple)
                                Text("Scouting opponent's recent games…")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.warpPurple)
                                Spacer()
                            }
                        }

                        if let err = store.syncErrorMessage {
                            Text(err)
                                .font(.caption)
                                .foregroundStyle(BrillyPalette.blunderRose)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.brillyTeal)

                    // MARK: - 2. Batch Analyze Control Card
                    batchAnalyzeCard

                    // MARK: - 3. Search & Filter Chips
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(BrillyPalette.inkSecondary)
                        TextField("Filter by opponent or opening…", text: $searchText)
                            .textFieldStyle(.plain)
                            #if os(iOS)
                            .autocorrectionDisabled()
                            #endif
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .brillySurface(store.surfaceStyle, cornerRadius: 14)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["All", "Unanalyzed", "W", "D", "L"], id: \.self) { f in
                                let sel = resultFilter == f
                                Button(f == "W" ? "Wins" : (f == "D" ? "Draws" : (f == "L" ? "Losses" : f))) {
                                    resultFilter = f
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(sel ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(sel ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // MARK: - 4. Game List
                    if filteredGames.isEmpty {
                        VStack(spacing: 10) {
                            Text("No games match this filter")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            Text("Try clearing your search or switching back to All games.")
                                .font(.caption)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                            Button("Reset Filters") {
                                searchText = ""
                                resultFilter = "All"
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .brillySurface(store.surfaceStyle, cornerRadius: 18)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredGames) { game in
                                gameRow(game)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 84)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Games")
        .sheet(isPresented: $showingPgnSheet) { pgnSheet }
        .sheet(isPresented: $showingPositionEditor) {
            PositionEditorSheet().environment(store)
        }
        .sheet(isPresented: $showingScoutSheet) { scoutSheet }
    }

    // MARK: - Batch Analyze Card

    @ViewBuilder
    private var batchAnalyzeCard: some View {
        let pending = store.unanalyzedRecentGames.count
        if store.isBatchAnalyzing {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(store.copy(cosmic: "Batch Telemetry Scan", classic: "Batch Analyzing"), systemImage: "cpu")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                    Spacer()
                    Text("\(Int((store.batchProgress * 100).rounded()))%")
                        .font(.caption.monospacedDigit().weight(.black))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                    Button("Stop") { store.cancelBatchAnalysis() }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.blunderRose)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(BrillyPalette.blunderRose.opacity(0.18)))
                        .buttonStyle(.plain)
                }
                TractorBeamProgressBar(progress: store.batchProgress, height: 10)
                Text(store.batchCurrentLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .lineLimit(1)
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.brillyTeal)
        } else if pending > 0 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Batch Analyze")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Text("\(pending) unanalyzed game\(pending == 1 ? "" : "s") ready to feed Insights, Mistakes & Vault.")
                            .font(.caption)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                    }
                    Spacer()
                }
                HStack(spacing: 8) {
                    batchButton("Analyze \(min(5, pending))", count: 5)
                    if pending > 5 {
                        batchButton("Analyze \(min(10, pending))", count: 10)
                    }
                    if pending > 10 {
                        batchButton("All (\(pending))", count: pending)
                    }
                }
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.warpPurple)
        }
    }

    private func batchButton(_ title: String, count: Int) -> some View {
        Button {
            store.startBatchAnalysis(maxCount: count)
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(BrillyPalette.voidBg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(
                        LinearGradient(
                            colors: [BrillyPalette.brillyTeal, BrillyPalette.warpPurple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toolChip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BrillyPalette.brillyTeal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private var pgnSheet: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)
                VStack(spacing: 14) {
                    Text("Paste raw PGN text OR a public Lichess game URL (e.g. lichess.org/AbCdEfGh).")
                        .font(.caption)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextEditor(text: $pgnDraft)
                        .scrollContentBackground(.hidden)
                        .font(.system(.callout, design: .monospaced))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .padding(12)
                        .brillySurface(store.surfaceStyle, cornerRadius: 16)

                    if let pgnError {
                        Label(pgnError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrillyPalette.blunderRose)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        let draft = pgnDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        let looksLikeLichess = draft.lowercased().contains("lichess.org/")
                            || ((draft.count == 8 || draft.count == 12) && draft.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }))
                        if looksLikeLichess {
                            showingPgnSheet = false
                            pgnDraft = ""
                            pgnError = nil
                            Task { await store.importLichessGameURL(draft) }
                        } else {
                            if store.importAndAnalyzePGN(draft) {
                                showingPgnSheet = false
                                pgnDraft = ""
                                pgnError = nil
                            } else {
                                pgnError = store.syncErrorMessage ?? "Invalid PGN format."
                            }
                        }
                    } label: {
                        Text("Import & Analyze")
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
            .navigationTitle("Paste PGN / Lichess URL")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingPgnSheet = false }
                }
            }
        }
    }

    private var scoutSheet: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)
                VStack(spacing: 16) {
                    Text("Scout an opponent's recent public games to uncover their favorite openings and softest targets.")
                        .font(.subheadline)
                        .foregroundStyle(BrillyPalette.inkSecondary)

                    Picker("Platform", selection: $scoutPlatform) {
                        Text("Lichess").tag(GameSource.lichess)
                        Text("Chess.com").tag(GameSource.chesscom)
                    }
                    .pickerStyle(.segmented)

                    TextField("Opponent username", text: $scoutDraft)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        #endif
                        .onSubmit { triggerScout() }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                        .foregroundStyle(BrillyPalette.inkPrimary)

                    Button {
                        triggerScout()
                    } label: {
                        Label("Build Scout Gameplan", systemImage: "binoculars.fill")
                            .font(.headline)
                            .foregroundStyle(BrillyPalette.voidBg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 14).fill(BrillyPalette.warpPurple))
                    }
                    .buttonStyle(.plain)
                    .disabled(scoutDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isScouting)

                    Spacer()
                }
                .padding(18)
            }
            .navigationTitle("Scout Opponent")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingScoutSheet = false }
                }
            }
        }
    }

    private func triggerScout() {
        let handle = scoutDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !handle.isEmpty else { return }
        let plat = scoutPlatform
        showingScoutSheet = false
        Task { await store.runScout(opponent: handle, platform: plat) }
    }

    private func gameRow(_ game: GameRecord) -> some View {
        let handles = store.userHandles
        let res = game.userResult(handles: handles)
        let accent: Color = res == "W" ? Color(hex: 0x22C55E) : (res == "L" ? BrillyPalette.blunderRose : BrillyPalette.inkSecondary)
        let cached = store.analyzedGames.first(where: { $0.id == game.id })
        let userSide = game.resolvedUserColor(handles: handles)

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
                            let acc = (userSide == .black ? cached.blackSummary : cached.whiteSummary).accuracy
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
