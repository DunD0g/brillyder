import SwiftUI
import BrillyDerCore

// MARK: - Frozen Woodpecker Cycles Panel

public struct WoodpeckerCyclePanel: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var board: ChessBoard = ChessBoard()
    @State private var wrongOnCurrent = false
    @State private var solvedCurrent = false
    @State private var feedback = "Solve each frozen tactic fast on the 1st try."

    private var activePuzzle: MistakePuzzle? {
        guard let cycle = store.woodpeckerCycle,
              cycle.activeIndex < cycle.puzzleIds.count else { return nil }
        let targetId = cycle.puzzleIds[cycle.activeIndex]
        return store.mistakeDeck.first { $0.id == targetId }
    }

    public var body: some View {
        VStack(spacing: 14) {
            if let cycle = store.woodpeckerCycle {
                // Active Cycle Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Cycle #\(cycle.currentCycle) · \(cycle.activeIndex + 1) / \(max(1, cycle.puzzleIds.count))")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        Spacer()
                        Button("New Batch") {
                            store.woodpeckerCycle = nil
                            store.persistToDisk()
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.blunderRose)
                        .buttonStyle(.plain)
                    }
                    ProgressView(value: Double(cycle.activeIndex), total: Double(max(1, cycle.puzzleIds.count)))
                        .tint(BrillyPalette.brillyTeal)
                    if cycle.isOnCooldown {
                        Label("24h memory consolidation window active (you can still train early).", systemImage: "moon.zzz.fill")
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.goldAmber)
                    }
                }
                .padding(14)
                .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.brillyTeal)

                if let puzzle = activePuzzle {
                    InteractiveChessBoardView(
                        board: board,
                        orientation: puzzle.playerColor,
                        theme: store.boardTheme,
                        surfaceStyle: store.surfaceStyle,
                        interactive: !solvedCurrent
                    ) { move in
                        if move.uci == puzzle.bestMoveUci {
                            _ = try? board.apply(move)
                            solvedCurrent = true
                            feedback = "Clean! \(puzzle.bestMoveSan) solved."
                            store.triggerHaptic(.success)
                        } else {
                            wrongOnCurrent = true
                            feedback = "Missed — try again (best is \(puzzle.bestMoveSan.prefix(2))…)"
                            store.triggerHaptic(.error)
                        }
                    }

                    Text(feedback)
                        .font(.subheadline)
                        .foregroundStyle(solvedCurrent ? BrillyPalette.brillyTeal : BrillyPalette.inkPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .brillySurface(store.surfaceStyle, cornerRadius: 14)

                    Button(solvedCurrent ? "Next Puzzle" : "Reveal & Advance") {
                        store.recordWoodpeckerStep(firstTry: solvedCurrent && !wrongOnCurrent, solved: solvedCurrent)
                        loadActivePuzzle()
                    }
                    .font(.headline)
                    .foregroundStyle(solvedCurrent ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(solvedCurrent ? BrillyPalette.brillyTeal : Color.white.opacity(0.10)))
                    .buttonStyle(.plain)
                }

                // Completed Cycles Speed-Up History
                if !cycle.completedCycles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cycle Speed-Up Log")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        ForEach(cycle.completedCycles) { c in
                            HStack {
                                Text("Cycle #\(c.cycleNumber)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                                Spacer()
                                Text("\(c.elapsedSeconds)s · \(c.firstTryPct)% 1st-try")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                            }
                        }
                    }
                    .padding(14)
                    .brillySurface(store.surfaceStyle, cornerRadius: 16)
                }
            } else {
                // Start Frozen Cycle
                VStack(alignment: .leading, spacing: 12) {
                    Text("Frozen Woodpecker Cycles")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                    Text("Freeze a set of your own game blunders & mistakes and repeat Cycles #1–7 until recognition becomes instant.")
                        .font(.subheadline)
                        .foregroundStyle(BrillyPalette.inkSecondary)

                    if store.mistakeDeck.isEmpty {
                        Text("Run Batch Analyze in the Games tab first to populate your personal mistake deck.")
                            .font(.caption)
                            .foregroundStyle(BrillyPalette.goldAmber)
                    } else {
                        Text("\(store.mistakeDeck.count) personal puzzles available")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        HStack(spacing: 8) {
                            ForEach([30, 50, 100], id: \.self) { size in
                                Button("Freeze \(min(size, store.mistakeDeck.count))") {
                                    store.startWoodpeckerCycle(batchSize: size)
                                    loadActivePuzzle()
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.voidBg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Capsule().fill(BrillyPalette.brillyTeal))
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
                .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.warpPurple)
            }
        }
        .onAppear { loadActivePuzzle() }
    }

    private func loadActivePuzzle() {
        wrongOnCurrent = false
        solvedCurrent = false
        if let p = activePuzzle {
            board = (try? ChessBoard(fen: p.fen)) ?? ChessBoard()
            feedback = "You played \(p.playedSan) vs \(p.opponentName). Find the tactical refutation!"
        }
    }
}

// MARK: - Tractor Beam Advantage Conversion Panel

public struct AdvantageConversionPanel: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var activeLead: BlownLeadPosition? = nil

    public var body: some View {
        let leads = store.blownLeads
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.copy(cosmic: "Tractor Beam Conversion", classic: "Advantage Conversion"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                Text("Replay winning (+2.5 or better) positions from your games that slipped away — lock in the win against the native engine.")
                    .font(.caption)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.goldAmber)

            if leads.isEmpty {
                Text("No blown leads detected yet — analyze more games in the Games tab!")
                    .font(.subheadline)
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .brillySurface(store.surfaceStyle, cornerRadius: 18)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(leads) { lead in
                        let converted = store.convertedAdvantageIds.contains(lead.id)
                        Button {
                            activeLead = lead
                        } label: {
                            HStack(spacing: 12) {
                                InteractiveChessBoardView(
                                    board: (try? ChessBoard(fen: lead.fen)) ?? ChessBoard(),
                                    orientation: lead.userColor,
                                    theme: store.boardTheme,
                                    surfaceStyle: store.surfaceStyle,
                                    interactive: false
                                )
                                .frame(width: 66, height: 66)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Peak \(lead.peakEvalDisplay)")
                                            .font(.caption2.monospacedDigit().weight(.bold))
                                            .foregroundStyle(BrillyPalette.goldAmber)
                                        Spacer()
                                        if converted {
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundStyle(BrillyPalette.brillyTeal)
                                        }
                                    }
                                    Text("vs \(lead.opponentName) · Move \(lead.moveNumber)")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                    Text(lead.openingName)
                                        .font(.caption2)
                                        .foregroundStyle(BrillyPalette.inkSecondary)
                                }
                            }
                            .padding(12)
                            .brillySurface(store.surfaceStyle, cornerRadius: 16, interactive: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $activeLead) { lead in
            ConversionPlaySheet(lead: lead).environment(store)
        }
    }
}

private struct ConversionPlaySheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let lead: BlownLeadPosition
    @State private var board: ChessBoard = ChessBoard()
    @State private var historyFens: [String] = []
    @State private var liveScore: EngineScore = ChessMath.buildEngineScore(cpWhite: 0)
    @State private var status = "Convert your winning advantage cleanly!"
    @State private var thinking = false

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)
                VStack(spacing: 14) {
                    EvalBarView(score: liveScore, orientation: lead.userColor)

                    InteractiveChessBoardView(
                        board: board,
                        orientation: lead.userColor,
                        theme: store.boardTheme,
                        surfaceStyle: store.surfaceStyle,
                        interactive: !thinking && board.turn == lead.userColor && board.outcome == .ongoing
                    ) { move in
                        historyFens.append(board.fen)
                        guard (try? board.apply(move)) != nil else { return }
                        store.triggerHaptic(.move)
                        handleAfterUserMove()
                    }

                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .brillySurface(store.surfaceStyle, cornerRadius: 16)

                    HStack(spacing: 10) {
                        Button("Rewind Turn") {
                            if let prev = historyFens.popLast(), let b = try? ChessBoard(fen: prev) {
                                board = b
                                status = "Rewound — try a cleaner conversion plan!"
                            }
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BrillyPalette.goldAmber)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                        .buttonStyle(.plain)
                        .disabled(historyFens.isEmpty)

                        Button("Reset") { reset() }
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                            .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle("Convert vs \(lead.opponentName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear { reset() }
        }
    }

    private func reset() {
        board = (try? ChessBoard(fen: lead.fen)) ?? ChessBoard()
        historyFens = []
        status = "Hold >= +2.0 and push to +7.0 or checkmate to lock the win!"
    }

    private func handleAfterUserMove() {
        if case .checkmate(let w) = board.outcome, w == lead.userColor {
            status = "Checkmate! Advantage converted cleanly!"
            store.markAdvantageConverted(lead.id)
            return
        }
        thinking = true
        let fen = board.fen
        Task {
            if let ev = try? await store.engine.analyze(fen: fen, depth: 4, multiPV: 1, maxTimeMs: 320) {
                liveScore = ev.score
                let userCp = lead.userColor == .white ? ev.score.cpWhite : -ev.score.cpWhite
                if userCp >= 700 || (ev.score.mateWhite != nil && ((lead.userColor == .white && ev.score.mateWhite! > 0) || (lead.userColor == .black && ev.score.mateWhite! < 0))) {
                    status = "Winning position locked in (\(ev.score.display))! Conversion mastered!"
                    store.markAdvantageConverted(lead.id)
                } else if userCp < 150 {
                    status = "Careful — advantage slipped to \(ev.score.display). Tap Rewind Turn to try a cleaner move!"
                } else {
                    status = "Solid technique (\(ev.score.display)) — keep squeezing!"
                }
                if let m = ChessMove(uci: ev.bestMoveUci), board.outcome == .ongoing {
                    _ = try? board.apply(m)
                }
            }
            thinking = false
        }
    }
}

// MARK: - Mistake Deck & Motif Filter Panel

public struct MistakeDeckPanel: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var selectedTag: String = "All"
    @State private var index: Int = 0
    @State private var board: ChessBoard = ChessBoard()
    @State private var solved = false
    @State private var showHint = false
    @State private var message = ""

    private var availableTags: [String] {
        let tags = Set(store.mistakeDeck.map(\.tacticalTag))
        return ["All"] + tags.sorted()
    }

    private var filtered: [MistakePuzzle] {
        store.mistakeDeck.filter { selectedTag == "All" || $0.tacticalTag == selectedTag }
    }

    public var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableTags, id: \.self) { tag in
                        let sel = selectedTag == tag
                        Button(tag) {
                            selectedTag = tag
                            index = 0
                            loadCurrent()
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

            if filtered.isEmpty {
                Text("No personal mistakes yet — analyze games in the Games tab to fill your deck!")
                    .font(.subheadline)
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .brillySurface(store.surfaceStyle, cornerRadius: 18)
            } else {
                let p = filtered[min(index, filtered.count - 1)]
                HStack {
                    Text("\(p.tacticalTag) · Move \(p.moveNumber)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.blunderRose)
                    Spacer()
                    Text("\(index + 1) / \(filtered.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }

                InteractiveChessBoardView(
                    board: board,
                    orientation: p.playerColor,
                    theme: store.boardTheme,
                    surfaceStyle: store.surfaceStyle,
                    interactive: !solved,
                    arrows: showHint ? arrowFor(p.bestMoveUci) : []
                ) { move in
                    if move.uci == p.bestMoveUci {
                        _ = try? board.apply(move)
                        solved = true
                        message = "Spot on! \(p.bestMoveSan) fixes your \(p.playedSan) blunder."
                        store.triggerHaptic(.success)
                    } else {
                        message = "Try another candidate — you played \(p.playedSan) in the game."
                        store.triggerHaptic(.error)
                    }
                }

                Text(message.isEmpty ? "You played \(p.playedSan) vs \(p.opponentName). Find the best move!" : message)
                    .font(.subheadline)
                    .foregroundStyle(solved ? BrillyPalette.brillyTeal : BrillyPalette.inkPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .brillySurface(store.surfaceStyle, cornerRadius: 14)

                HStack(spacing: 10) {
                    Button("Hint") { showHint = true }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BrillyPalette.goldAmber)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                        .buttonStyle(.plain)

                    Button("Open Game") {
                        store.openGameAtPly(gameId: p.gameId, ply: p.ply)
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                    .buttonStyle(.plain)

                    Button("Next") {
                        index = (index + 1) % filtered.count
                        loadCurrent()
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BrillyPalette.voidBg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(BrillyPalette.brillyTeal))
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            if let filter = store.preferredMotifFilter, availableTags.contains(filter) {
                selectedTag = filter
                store.preferredMotifFilter = nil
            }
            loadCurrent()
        }
    }

    private func loadCurrent() {
        solved = false
        showHint = false
        message = ""
        if !filtered.isEmpty {
            let p = filtered[min(index, filtered.count - 1)]
            board = (try? ChessBoard(fen: p.fen)) ?? ChessBoard()
        }
    }

    private func arrowFor(_ uci: String) -> [BoardArrow] {
        guard let m = ChessMove(uci: uci) else { return [] }
        return [BoardArrow(from: m.from.algebraic, to: m.to.algebraic, color: .best)]
    }
}
