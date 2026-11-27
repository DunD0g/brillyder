import SwiftUI
import BrillyDerCore

// MARK: - Frozen Woodpecker Cycles Panel

public struct WoodpeckerCyclePanel: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var board: ChessBoard = ChessBoard()
    @State private var lastMove: (from: Square, to: Square)? = nil
    @State private var wrongOnCurrent = false
    @State private var solvedCurrent = false
    @State private var revealedCurrent = false
    @State private var feedback = "Solve each frozen tactic fast on the 1st try."

    private var activePuzzle: MistakePuzzle? {
        guard let cycle = store.woodpeckerCycle,
              cycle.activeIndex < cycle.puzzleIds.count else { return nil }
        let targetId = cycle.puzzleIds[cycle.activeIndex]
        return store.mistakeDeck.first { $0.id == targetId }
    }

    private var uniqueBatchSizes: [Int] {
        let maxCount = store.mistakeDeck.count
        guard maxCount > 0 else { return [] }
        var out: [Int] = []
        for s in [30, 50, 100] {
            let clamped = min(s, maxCount)
            if !out.contains(clamped) { out.append(clamped) }
        }
        return out
    }

    public var body: some View {
        VStack(spacing: 14) {
            if let cycle = store.woodpeckerCycle {
                // Active Cycle Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Cycle #\(cycle.currentCycle) · \(min(cycle.activeIndex + 1, max(1, cycle.puzzleIds.count))) / \(max(1, cycle.puzzleIds.count))")
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

                    TractorBeamProgressBar(
                        progress: Double(cycle.activeIndex) / Double(max(1, cycle.puzzleIds.count)),
                        height: 8
                    )

                    if cycle.isOnCooldown {
                        Label("24h memory consolidation window active (you can still train early).", systemImage: "moon.zzz.fill")
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.goldAmber)
                    }
                }
                .padding(14)
                .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.brillyTeal)

                if let puzzle = activePuzzle {
                    let orientation = (try? ChessBoard(fen: puzzle.fen))?.turn ?? puzzle.playerColor

                    InteractiveChessBoardView(
                        board: board,
                        orientation: orientation,
                        theme: store.effectiveBoardTheme,
                        surfaceStyle: store.surfaceStyle,
                        interactive: !solvedCurrent && !revealedCurrent,
                        lastMove: lastMove,
                        arrows: revealedCurrent ? arrowFor(puzzle.bestMoveUci) : []
                    ) { move in
                        if move.uci == puzzle.bestMoveUci {
                            if (try? board.apply(move)) != nil {
                                lastMove = (move.from, move.to)
                            }
                            solvedCurrent = true
                            feedback = "Clean! \(puzzle.bestMoveSan) solved."
                            store.triggerHaptic(.success)
                        } else {
                            wrongOnCurrent = true
                            feedback = "Missed — try again (best starts with \(puzzle.bestMoveSan.prefix(2))…)"
                            store.triggerHaptic(.error)
                        }
                    }

                    Text(feedback)
                        .font(.subheadline)
                        .foregroundStyle(solvedCurrent ? BrillyPalette.brillyTeal : (revealedCurrent ? BrillyPalette.goldAmber : BrillyPalette.inkPrimary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .brillySurface(store.surfaceStyle, cornerRadius: 14)

                    if solvedCurrent || revealedCurrent {
                        Button {
                            store.recordWoodpeckerStep(firstTry: solvedCurrent && !wrongOnCurrent, solved: solvedCurrent)
                            loadActivePuzzle()
                        } label: {
                            Text("Next Puzzle")
                                .font(.headline)
                                .foregroundStyle(BrillyPalette.voidBg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(BrillyPalette.brillyTeal))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(BrillyPressScaleStyle())
                    } else {
                        Button {
                            wrongOnCurrent = true
                            revealedCurrent = true
                            feedback = "Best move was \(puzzle.bestMoveSan). Study the pattern, then tap Next Puzzle."
                            store.triggerHaptic(.move)
                        } label: {
                            Text("Reveal Solution")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(BrillyPalette.goldAmber)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(BrillyPressScaleStyle())
                    }
                } else {
                    // Graceful recovery if a cycle references a puzzle whose game was deleted or not yet imported
                    VStack(spacing: 12) {
                        Label("Puzzle Not Found in Current Deck", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrillyPalette.goldAmber)
                        Text("This frozen puzzle belongs to a game that is no longer in your analyzed library.")
                            .font(.caption)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 10) {
                            Button {
                                store.recordWoodpeckerStep(firstTry: false, solved: false)
                                loadActivePuzzle()
                            } label: {
                                Text("Skip Missing")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.voidBg)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Capsule().fill(BrillyPalette.brillyTeal))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(BrillyPressScaleStyle())

                            Button {
                                store.woodpeckerCycle = nil
                                store.persistToDisk()
                            } label: {
                                Text("Start Fresh Batch")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.blunderRose)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.blunderRose)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(BrillyPressScaleStyle())
                        }
                    }
                    .padding(16)
                    .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.goldAmber)
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
                        Text("\(store.mistakeDeck.count) personal puzzle\(store.mistakeDeck.count == 1 ? "" : "s") available")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        HStack(spacing: 8) {
                            ForEach(uniqueBatchSizes, id: \.self) { size in
                                Button {
                                    store.startWoodpeckerCycle(batchSize: size)
                                    loadActivePuzzle()
                                } label: {
                                    Text("Freeze \(size)")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(BrillyPalette.voidBg)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Capsule().fill(BrillyPalette.brillyTeal))
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(BrillyPressScaleStyle())
                            }
                        }
                    }
                }
                .padding(16)
                .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.warpPurple)
            }
        }
        .onAppear { loadActivePuzzle() }
        .onChange(of: store.woodpeckerCycle?.id) { _, _ in loadActivePuzzle() }
        .onChange(of: store.woodpeckerCycle?.activeIndex) { _, _ in loadActivePuzzle() }
    }

    private func loadActivePuzzle() {
        wrongOnCurrent = false
        solvedCurrent = false
        revealedCurrent = false
        lastMove = nil
        if let p = activePuzzle {
            board = (try? ChessBoard(fen: p.fen)) ?? ChessBoard()
            feedback = "You played \(p.playedSan) vs \(p.opponentName). Find the tactical refutation!"
        }
    }

    private func arrowFor(_ uci: String) -> [BoardArrow] {
        guard let m = ChessMove(uci: uci) else { return [] }
        return [BoardArrow(from: m.from.algebraic, to: m.to.algebraic, color: .best)]
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
                                    theme: store.effectiveBoardTheme,
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
    @State private var botTask: Task<Void, Never>? = nil
    @State private var generation: Int = 0
    @State private var awardedMastery: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)
                ScrollView {
                    VStack(spacing: 14) {
                        EvalBarView(score: liveScore, orientation: lead.userColor)

                        InteractiveChessBoardView(
                            board: board,
                            orientation: lead.userColor,
                            theme: store.effectiveBoardTheme,
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
                            Button {
                                cancelBot()
                                if let prev = historyFens.popLast(), let b = try? ChessBoard(fen: prev) {
                                    board = b
                                    status = "Rewound — try a cleaner conversion plan!"
                                }
                            } label: {
                                Text("Rewind Turn")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BrillyPalette.goldAmber)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(BrillyPressScaleStyle())
                            .disabled(historyFens.isEmpty)

                            Button {
                                reset()
                            } label: {
                                Text("Reset")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(BrillyPressScaleStyle())
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Convert vs \(lead.opponentName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .onAppear { reset() }
            .onDisappear { cancelBot() }
        }
    }

    private func cancelBot() {
        generation &+= 1
        botTask?.cancel()
        botTask = nil
        thinking = false
    }

    private func reset() {
        cancelBot()
        board = (try? ChessBoard(fen: lead.fen)) ?? ChessBoard()
        historyFens = []
        awardedMastery = false
        let initialCp = lead.userColor == .white ? 300 : -300
        liveScore = ChessMath.buildEngineScore(cpWhite: initialCp)
        status = "Hold >= +2.0 and push to +7.0 or checkmate to lock the win!"

        // Probe initial exact eval in background without blocking
        let gen = generation
        let fen = board.fen
        botTask = Task {
            if let ev = try? await store.interactiveEngine.analyze(fen: fen, depth: 4, multiPV: 1, maxTimeMs: 250),
               !Task.isCancelled, self.generation == gen {
                liveScore = ev.score
            }
        }
    }

    private func handleOutcomeCheck() -> Bool {
        switch board.outcome {
        case .ongoing:
            return false
        case .checkmate(let w):
            cancelBot()
            if w == lead.userColor {
                status = "Checkmate! Advantage converted cleanly!"
                if !awardedMastery {
                    awardedMastery = true
                    store.markAdvantageConverted(lead.id)
                }
            } else {
                status = "Checkmated — tap Rewind Turn or Reset to try again."
                store.triggerHaptic(.error)
            }
            return true
        case .stalemate, .insufficientMaterial, .fiftyMoveRule:
            cancelBot()
            status = "Game ended in a draw — tap Rewind Turn or Reset to convert the win!"
            store.triggerHaptic(.error)
            return true
        }
    }

    private func handleAfterUserMove() {
        if handleOutcomeCheck() { return }
        cancelBot()
        let gen = generation
        thinking = true
        let fen = board.fen
        botTask = Task {
            if let ev = try? await store.interactiveEngine.analyze(fen: fen, depth: 4, multiPV: 1, maxTimeMs: 320),
               !Task.isCancelled, self.generation == gen {
                liveScore = ev.score
                let userCp = lead.userColor == .white ? ev.score.cpWhite : -ev.score.cpWhite
                if userCp >= 700 || (ev.score.mateWhite != nil && ((lead.userColor == .white && ev.score.mateWhite! > 0) || (lead.userColor == .black && ev.score.mateWhite! < 0))) {
                    status = "Winning position locked in (\(ev.score.display))! Conversion mastered!"
                    if !awardedMastery {
                        awardedMastery = true
                        store.markAdvantageConverted(lead.id)
                    }
                } else if userCp < 150 {
                    status = "Careful — advantage slipped to \(ev.score.display). Tap Rewind Turn to try a cleaner move!"
                } else {
                    status = "Solid technique (\(ev.score.display)) — keep squeezing!"
                }
                if let m = ChessMove(uci: ev.bestMoveUci), board.outcome == .ongoing {
                    _ = try? board.apply(m)
                    store.triggerHaptic(.move)
                    _ = handleOutcomeCheck()
                }
            }
            if self.generation == gen {
                thinking = false
            }
        }
    }
}

// MARK: - Mistake Deck & Motif Filter Panel

public struct MistakeDeckPanel: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var selectedTag: String = "All"
    @State private var index: Int = 0
    @State private var board: ChessBoard = ChessBoard()
    @State private var lastMove: (from: Square, to: Square)? = nil
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
                        Button {
                            selectedTag = tag
                            index = 0
                            loadCurrent()
                        } label: {
                            Text(tag)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(sel ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(sel ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
                                .contentShape(Capsule())
                        }
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
                let safeIdx = min(index, filtered.count - 1)
                let p = filtered[safeIdx]
                let orientation = (try? ChessBoard(fen: p.fen))?.turn ?? p.playerColor

                HStack {
                    Text("\(p.tacticalTag) · Move \(p.moveNumber)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.blunderRose)
                    Spacer()
                    Text("\(safeIdx + 1) / \(filtered.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }

                InteractiveChessBoardView(
                    board: board,
                    orientation: orientation,
                    theme: store.effectiveBoardTheme,
                    surfaceStyle: store.surfaceStyle,
                    interactive: !solved,
                    lastMove: lastMove,
                    arrows: (showHint && !solved) ? arrowFor(p.bestMoveUci) : []
                ) { move in
                    if move.uci == p.bestMoveUci {
                        if (try? board.apply(move)) != nil {
                            lastMove = (move.from, move.to)
                        }
                        solved = true
                        message = "Spot on! \(p.bestMoveSan) fixes your \(p.playedSan) blunder."
                        store.recordTrainingActivity()
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
                    Button {
                        showHint = true
                    } label: {
                        Text("Hint")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrillyPalette.goldAmber)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                    .disabled(solved)

                    Button {
                        store.openGameAtPly(gameId: p.gameId, ply: p.ply)
                    } label: {
                        Text("Open Game")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(BrillyPressScaleStyle())

                    Button {
                        index = (safeIdx + 1) % filtered.count
                        loadCurrent()
                    } label: {
                        Text("Next")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrillyPalette.voidBg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(BrillyPalette.brillyTeal))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                }
            }
        }
        .onAppear {
            applyPreferredMotif()
            loadCurrent()
        }
        .onChange(of: store.preferredMotifFilter) { _, _ in
            applyPreferredMotif()
            loadCurrent()
        }
        .onChange(of: store.mistakeDeck.count) { _, _ in
            if !availableTags.contains(selectedTag) { selectedTag = "All" }
            index = 0
            loadCurrent()
        }
    }

    private func applyPreferredMotif() {
        if let filter = store.preferredMotifFilter, availableTags.contains(filter) {
            selectedTag = filter
            index = 0
            store.preferredMotifFilter = nil
        }
    }

    private func loadCurrent() {
        solved = false
        showHint = false
        message = ""
        lastMove = nil
        if !filtered.isEmpty {
            let safeIdx = min(index, filtered.count - 1)
            index = safeIdx
            let p = filtered[safeIdx]
            board = (try? ChessBoard(fen: p.fen)) ?? ChessBoard()
        }
    }

    private func arrowFor(_ uci: String) -> [BoardArrow] {
        guard let m = ChessMove(uci: uci) else { return [] }
        return [BoardArrow(from: m.from.algebraic, to: m.to.algebraic, color: .best)]
    }
}
