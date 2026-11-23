import SwiftUI
import BrillyDerCore
#if canImport(UIKit)
import UIKit
#endif

public struct AnalyzeTabView: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var currentPlyIndex: Int = 0
    @State private var orientation: PieceColor = .white
    @State private var retryMode: Bool = false
    @State private var retryFeedback: String? = nil
    @State private var retrySolvedBoard: ChessBoard? = nil
    @State private var retrySolvedLastMove: (from: Square, to: Square)? = nil

    // Sandbox / Bot Play-Out State (with cancellable generation-guarded tasks)
    @State private var botActive: Bool = false
    @State private var sandboxBoard: ChessBoard = ChessBoard()
    @State private var sandboxEval: EngineEval? = nil
    @State private var botThinking: Bool = false
    @State private var botStatusNotice: String? = nil
    @State private var botTask: Task<Void, Never>? = nil
    @State private var evalTask: Task<Void, Never>? = nil
    @State private var botGeneration: Int = 0
    @State private var evalGeneration: Int = 0

    // Cached Deviation, Syzygy Tablebase & Copy Toast
    @State private var cachedDeviation: OpeningDeviationReport? = nil
    @State private var syzygyResult: SyzygyProbeResult? = nil
    @State private var copiedNotice: String? = nil
    @State private var boostedDeviationCardId: String? = nil
    @State private var activeShareCard: BrillyShareCardPayload? = nil

    public var body: some View {
        ZStack {
            CosmicVoidBackdrop(style: store.surfaceStyle)

            if store.isAnalyzing {
                analyzingHud
            } else if let customFen = store.activeSandboxFen {
                sandboxView(startFen: customFen)
            } else if let analyzed = store.activeAnalyzedGame {
                analyzedBody(analyzed)
            } else {
                emptyState
            }
        }
        .navigationTitle("Analyze")
        .onAppear {
            applyPendingNavigation(resetIfNewGame: false)
            refreshCachedDeviation()
        }
        .onDisappear {
            cancelLiveTasks()
        }
        .onChange(of: store.activeAnalyzedGame?.id) { _, _ in
            applyPendingNavigation(resetIfNewGame: true)
            refreshCachedDeviation()
        }
        .onChange(of: store.pendingAnalyzePly) { _, _ in
            applyPendingNavigation(resetIfNewGame: false)
        }
        .onChange(of: store.customCourses.count) { _, _ in
            refreshCachedDeviation()
        }
        .onChange(of: currentPlyIndex) { _, newPly in
            guard !retryMode && !botActive,
                  let ag = store.activeAnalyzedGame,
                  newPly > 0 && newPly <= ag.plies.count else { return }
            let ply = ag.plies[newPly - 1]
            if ply.classification == .brilliant {
                store.triggerCelebration(.brilliant)
            } else if ply.classification == .blunder {
                store.triggerCelebration(.blunder)
            }
        }
        .onChange(of: store.activeSandboxFen) { _, newFen in
            cancelLiveTasks()
            if let newFen, let b = try? ChessBoard(fen: newFen) {
                sandboxBoard = b
                orientation = b.turn
                botActive = false
                botStatusNotice = nil
                evaluateSandbox(fen: newFen)
            }
        }
        .sheet(item: $activeShareCard) { payload in
            BrillyShareCardSheet(payload: payload, surfaceStyle: store.surfaceStyle)
        }
    }

    private func cancelLiveTasks() {
        botGeneration &+= 1
        evalGeneration &+= 1
        botTask?.cancel()
        botTask = nil
        evalTask?.cancel()
        evalTask = nil
        botThinking = false
    }

    private func goToPly(_ target: Int, maxPly: Int) {
        cancelLiveTasks()
        currentPlyIndex = max(0, min(target, maxPly))
        retryMode = false
        botActive = false
        retryFeedback = nil
        retrySolvedBoard = nil
        retrySolvedLastMove = nil
        botStatusNotice = nil
    }

    private func applyPendingNavigation(resetIfNewGame: Bool) {
        guard let ag = store.activeAnalyzedGame else { return }
        cancelLiveTasks()
        if let jump = store.pendingAnalyzePly {
            currentPlyIndex = max(0, min(jump, ag.plies.count))
            store.pendingAnalyzePly = nil
        } else if resetIfNewGame || currentPlyIndex == 0 || currentPlyIndex > ag.plies.count {
            currentPlyIndex = min(1, ag.plies.count)
        }
        orientation = ag.game.resolvedUserColor(handles: store.userHandles) ?? .white
        retryMode = false
        botActive = false
        retryFeedback = nil
        retrySolvedBoard = nil
        retrySolvedLastMove = nil
        botStatusNotice = nil
        if resetIfNewGame {
            boostedDeviationCardId = nil
        }
    }

    private func refreshCachedDeviation() {
        guard let ag = store.activeAnalyzedGame else {
            cachedDeviation = nil
            return
        }
        cachedDeviation = DeviationDetector.detect(
            analyzedGame: ag,
            courses: store.allCourses,
            fsrsCards: store.fsrsCards,
            handles: store.userHandles
        )
    }

    private var analyzingHud: some View {
        let pct = Int((store.analysisProgress * 100).rounded())
        return VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(BrillyPalette.brillyTeal.opacity(0.22), lineWidth: 3)
                    .frame(width: 66, height: 66)
                Circle()
                    .trim(from: 0, to: max(0.08, CGFloat(store.analysisProgress)))
                    .stroke(
                        LinearGradient(
                            colors: [BrillyPalette.brillyTeal, BrillyPalette.warpPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 66, height: 66)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.25), value: store.analysisProgress)
                BrillyGemIcon(size: 26, color: BrillyPalette.brillyTeal)
            }

            VStack(spacing: 4) {
                if !store.analyzingMatchupTitle.isEmpty {
                    Text(store.analyzingMatchupTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .lineLimit(1)
                }
                Text("\(store.analysisStatusText) · \(pct)%")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(BrillyPalette.brillyTeal)
                Text("On-device native \(store.analysisPreset.title) engine")
                    .font(.caption)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }

            TractorBeamProgressBar(progress: store.analysisProgress, height: 11)
                .padding(.horizontal, 6)

            Button {
                store.cancelAnalysis()
            } label: {
                Text("Cancel Analysis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrillyPalette.blunderRose)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(BrillyPalette.blunderRose.opacity(0.14))
                            .overlay(Capsule().strokeBorder(BrillyPalette.blunderRose.opacity(0.55), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(26)
        .frame(maxWidth: 340)
        .brillySurface(store.surfaceStyle, cornerRadius: 26, tint: BrillyPalette.brillyTeal)
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(BrillyPalette.brillyTeal)
            Text("Pick a Game to Analyze")
                .font(.title3.weight(.bold))
                .foregroundStyle(BrillyPalette.inkPrimary)
            Text("Sync Lichess or Chess.com, run Batch Analyze, paste a PGN, or open Board Editor.")
                .font(.subheadline)
                .foregroundStyle(BrillyPalette.inkSecondary)
                .multilineTextAlignment(.center)
            if let sample = store.recentGames.first {
                Button("Analyze Showcase Game") {
                    store.startAnalysis(for: sample)
                }
                .font(.headline)
                .foregroundStyle(BrillyPalette.voidBg)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(Capsule().fill(BrillyPalette.brillyTeal))
                .buttonStyle(.plain)
            }
        }
        .padding(26)
        .brillySurface(store.surfaceStyle, cornerRadius: 24)
        .padding()
    }

    // MARK: - Custom FEN Sandbox View

    private func sandboxView(startFen: String) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    Label("Custom Position Sandbox", systemImage: "square.grid.3x3")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                    Spacer()
                    Button("Exit Sandbox") {
                        cancelLiveTasks()
                        store.activeSandboxFen = nil
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrillyPalette.blunderRose)
                    .buttonStyle(.plain)
                }

                if let ev = sandboxEval {
                    EvalBarView(score: ev.score, orientation: orientation)
                }

                InteractiveChessBoardView(
                    board: sandboxBoard,
                    orientation: orientation,
                    theme: store.boardTheme,
                    surfaceStyle: store.surfaceStyle,
                    interactive: !botThinking && sandboxBoard.outcome == .ongoing,
                    arrows: sandboxBestArrow
                ) { move in
                    guard (try? sandboxBoard.apply(move)) != nil else { return }
                    store.triggerHaptic(.move)
                    updateSandboxOutcomeNotice()
                    evaluateSandbox(fen: sandboxBoard.fen)
                    if botActive && sandboxBoard.outcome == .ongoing {
                        triggerBotReply()
                    }
                }

                if let botStatusNotice {
                    Text(botStatusNotice)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrillyPalette.goldAmber)
                }

                HStack(spacing: 8) {
                    Button {
                        botActive.toggle()
                        if botActive && sandboxBoard.outcome == .ongoing && sandboxBoard.turn != orientation {
                            triggerBotReply()
                        } else if !botActive {
                            cancelLiveTasks()
                        }
                    } label: {
                        Label(botActive ? "Bot: ON" : "Play vs Bot", systemImage: "cpu")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(botActive ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(botActive ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        orientation = orientation.opposite
                    } label: {
                        Label("Flip", systemImage: "arrow.up.arrow.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                    }
                    .buttonStyle(.plain)

                    Button {
                        copyText(sandboxBoard.fen, label: "FEN copied!")
                    } label: {
                        Label("FEN", systemImage: "doc.on.doc")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                    }
                    .buttonStyle(.plain)
                }

                if let ev = sandboxEval {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Live Native Engine (Depth \(ev.depth)) · Eval \(ev.score.display)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        ForEach(Array(ev.lines.prefix(3).enumerated()), id: \.offset) { idx, line in
                            let pv = ChessMath.uciLineToSAN(fen: sandboxBoard.fen, uciMoves: line.pv, maxMoves: 5)
                            Text("#\(idx + 1) [\(line.score.display)] \(pv.joined(separator: " "))")
                                .font(.caption.monospaced())
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .brillySurface(store.surfaceStyle, cornerRadius: 16)
                }

                syzygyCardIfEligible(fen: sandboxBoard.fen)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 84)
            .onAppear {
                if let b = try? ChessBoard(fen: startFen) {
                    sandboxBoard = b
                    orientation = b.turn
                    evaluateSandbox(fen: startFen)
                }
            }
        }
    }

    private var sandboxBestArrow: [BoardArrow] {
        guard let uci = sandboxEval?.bestMoveUci, let m = ChessMove(uci: uci) else { return [] }
        return [BoardArrow(from: m.from.algebraic, to: m.to.algebraic, color: .best)]
    }

    // MARK: - Full Game Analysis View

    @ViewBuilder
    private func analyzedBody(_ ag: AnalyzedGame) -> some View {
        let clampedPly = max(0, min(currentPlyIndex, ag.plies.count))
        let activePly: AnalyzedPly? = clampedPly > 0 ? ag.plies[clampedPly - 1] : nil
        let initialBoardFen = ag.plies.first?.beforeFen ?? ChessBoard.initialFEN
        let displayFen: String = {
            if botActive { return sandboxBoard.fen }
            if let solved = retrySolvedBoard { return solved.fen }
            if retryMode, let ap = activePly { return ap.beforeFen }
            if let ap = activePly { return ap.afterFen }
            return initialBoardFen
        }()
        let board: ChessBoard = {
            if botActive { return sandboxBoard }
            if let solved = retrySolvedBoard { return solved }
            return (try? ChessBoard(fen: displayFen)) ?? ChessBoard()
        }()
        let score: EngineScore = {
            if botActive, let ev = sandboxEval { return ev.score }
            return activePly?.evalAfter ?? ag.initialEval
        }()
        let lastMovePair: (from: Square, to: Square)? = {
            if let solvedMove = retrySolvedLastMove { return solvedMove }
            guard !retryMode && !botActive, let ap = activePly,
                  let f = Square(algebraic: ap.from),
                  let t = Square(algebraic: ap.to) else { return nil }
            return (f, t)
        }()
        let badge: MoveBadgeOverlay? = {
            guard retrySolvedBoard == nil && !retryMode && !botActive,
                  let ap = activePly,
                  let sq = Square(algebraic: ap.to) else { return nil }
            return MoveBadgeOverlay(square: sq, classification: ap.classification)
        }()
        let bestArrow: [BoardArrow] = {
            guard retrySolvedBoard == nil && !retryMode && !botActive, let ap = activePly,
                  ap.classification == .blunder || ap.classification == .mistake || ap.classification == .inaccuracy,
                  let m = ChessMove(uci: ap.bestMoveUci) else { return [] }
            return [BoardArrow(from: m.from.algebraic, to: m.to.algebraic, color: .best)]
        }()

        let sharePayload: () -> BrillyShareCardPayload = {
            let moverSide = activePly?.color ?? orientation
            let summary = moverSide == .white ? ag.whiteSummary : ag.blackSummary
            let accTag = "\(String(format: "%.1f", summary.accuracy))% · ~\(summary.estimatedElo)"
            let notation = activePly.map { "\($0.moveNumber)\($0.color == .white ? "." : "...") \($0.san)" }
            let detail = activePly?.coaching.detail ?? activePly?.coaching.headline ?? (ag.openingLineDetected ?? ag.game.openingName)
            return BrillyShareCardPayload(
                fen: displayFen,
                orientation: orientation,
                theme: store.boardTheme,
                pieceSet: store.pieceSet,
                vibe: store.vibeMode,
                moveNotation: notation,
                classification: activePly?.classification,
                title: "\(ag.game.white.name) vs \(ag.game.black.name)",
                coachingLine: detail,
                evalDisplay: score.display,
                evalScore: score,
                whiteName: ag.game.white.name,
                blackName: ag.game.black.name,
                activeSide: moverSide,
                accuracyTag: accTag,
                openingName: ag.openingLineDetected ?? ag.game.openingName,
                lastMove: lastMovePair,
                showMoveArrow: true,
                quipIndex: Int.random(in: 0..<12)
            )
        }

        ScrollView {
            VStack(spacing: 10) {
                // 1. Accuracy Summary Strip
                HStack(spacing: 10) {
                    playerSummaryPill(name: ag.game.white.name, acc: ag.whiteSummary.accuracy, elo: ag.whiteSummary.estimatedElo, isWhite: true)
                    playerSummaryPill(name: ag.game.black.name, acc: ag.blackSummary.accuracy, elo: ag.blackSummary.estimatedElo, isWhite: false)
                }

                // 2. Live Eval Bar
                EvalBarView(score: score, orientation: orientation)

                // 3. Interactive Board
                InteractiveChessBoardView(
                    board: board,
                    orientation: orientation,
                    theme: store.boardTheme,
                    surfaceStyle: store.surfaceStyle,
                    interactive: retryMode || (botActive && !botThinking && sandboxBoard.outcome == .ongoing),
                    lastMove: lastMovePair,
                    arrows: bestArrow,
                    moveBadge: badge
                ) { move in
                    if botActive {
                        guard (try? sandboxBoard.apply(move)) != nil else { return }
                        store.triggerHaptic(.move)
                        updateSandboxOutcomeNotice()
                        evaluateSandbox(fen: sandboxBoard.fen)
                        if sandboxBoard.outcome == .ongoing {
                            triggerBotReply()
                        }
                        return
                    }
                    guard retryMode, let ap = activePly else { return }
                    if move.uci == ap.bestMoveUci {
                        var solved = board
                        if (try? solved.apply(move)) != nil {
                            retrySolvedBoard = solved
                            retrySolvedLastMove = (move.from, move.to)
                        }
                        retryFeedback = "Nailed it! \(ap.bestMoveSan) was the best move."
                        retryMode = false
                        store.triggerHaptic(.success)
                    } else {
                        retryFeedback = "Not \(move.uci) — keep hunting for a stronger continuation!"
                        store.triggerHaptic(.error)
                    }
                }

                // 4. Transport Scrubber Bar
                BrillyGlassCluster(style: store.surfaceStyle, spacing: 8) {
                    HStack(spacing: 8) {
                        transportBtn("backward.end.fill", label: "First move") { goToPly(0, maxPly: ag.plies.count) }
                        transportBtn("chevron.left", label: "Previous move") { goToPly(clampedPly - 1, maxPly: ag.plies.count) }
                        transportBtn("chevron.right", label: "Next move") { goToPly(clampedPly + 1, maxPly: ag.plies.count) }
                        transportBtn("forward.end.fill", label: "Last move") { goToPly(ag.plies.count, maxPly: ag.plies.count) }
                        transportBtn("arrow.up.arrow.down", label: "Flip board") { orientation = orientation.opposite }
                        if let ap = activePly {
                            let isSaved = store.isBookmarked(gameId: ag.game.id, ply: ap.ply)
                            transportBtn(isSaved ? "bookmark.fill" : "bookmark", label: isSaved ? "Remove bookmark" : "Bookmark position") {
                                store.toggleBookmark(ply: ap, game: ag.game)
                            }
                        }
                    }
                }

                // 5. Coach Card (immediately visible above the floating tab bar on iPhone!)
                if let botStatusNotice, botActive {
                    Text(botStatusNotice)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.goldAmber)
                }

                if let ap = activePly {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(ap.moveNumber)\(ap.color == .white ? "." : "...") \(ap.san)")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            Text(ap.classification.label)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.badgeForeground(for: ap.classification))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(BrillyPalette.color(for: ap.classification)))
                            Spacer()
                            if ap.classification == .blunder || ap.classification == .mistake {
                                Button(retryMode ? "Exit Retry" : "Retry Mistake") {
                                    retryMode.toggle()
                                    botActive = false
                                    retrySolvedBoard = nil
                                    retrySolvedLastMove = nil
                                    retryFeedback = retryMode ? "Find the better move instead of \(ap.san)." : nil
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                                .buttonStyle(.plain)
                            }
                        }

                        Text(retryFeedback ?? ap.coaching.headline)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrillyPalette.inkPrimary)

                        Text(ap.coaching.detail)
                            .font(.caption)
                            .foregroundStyle(BrillyPalette.inkSecondary)

                        if let lines = ap.topLines, !lines.isEmpty, !retryMode {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(lines.prefix(2).enumerated()), id: \.offset) { idx, line in
                                    HStack(spacing: 6) {
                                        Text("#\(idx + 1)")
                                            .font(.caption2.monospacedDigit().weight(.bold))
                                            .foregroundStyle(BrillyPalette.brillyTeal)
                                        Text(line.evalDisplay)
                                            .font(.caption2.monospacedDigit().weight(.bold))
                                            .foregroundStyle(BrillyPalette.inkPrimary)
                                            .frame(width: 44, alignment: .leading)
                                        Text(line.pvSan.joined(separator: " "))
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(BrillyPalette.inkSecondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(14)
                    .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.color(for: ap.classification))
                }

                // 6. Utility Action Row: Play Bot | Copy FEN | Copy PGN | Lazy Share Card
                HStack(spacing: 8) {
                    Button {
                        if botActive {
                            cancelLiveTasks()
                            botActive = false
                            botStatusNotice = nil
                        } else {
                            sandboxBoard = board
                            botActive = true
                            retryMode = false
                            retrySolvedBoard = nil
                            retrySolvedLastMove = nil
                            botStatusNotice = nil
                            evaluateSandbox(fen: sandboxBoard.fen)
                            if sandboxBoard.outcome == .ongoing && sandboxBoard.turn != orientation {
                                triggerBotReply()
                            }
                        }
                    } label: {
                        Label(botActive ? "Stop Bot" : "Play Bot", systemImage: "cpu")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(botActive ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(botActive ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    Button { copyText(displayFen, label: "FEN copied") } label: {
                        Text("FEN")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    Button { copyText(ag.game.pgn, label: "PGN copied") } label: {
                        Text("PGN")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        activeShareCard = sharePayload()
                    } label: {
                        Label("Card", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                    }
                    .buttonStyle(.plain)
                }

                if let copiedNotice {
                    Text(copiedNotice)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                }

                // 7. Tappable Eval Graph
                if !ag.plies.isEmpty {
                    EvalGraphView(plies: ag.plies, selectedPly: clampedPly) { target in
                        goToPly(target, maxPly: ag.plies.count)
                    }
                }

                // 8. Live 7-Piece Syzygy Tablebase Bar (when <= 7 pieces)
                syzygyCardIfEligible(fen: displayFen)

                // 9. Opening Deviation ("Leak Patcher") Card
                if let dev = cachedDeviation {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(
                                dev.kind == .userDeviation ? "Opening Leak Detected" : (dev.kind == .opponentNovelty ? "Opponent Novelty" : "Repertoire Followed"),
                                systemImage: dev.kind == .userDeviation ? "exclamationmark.triangle.fill" : "book.closed.fill"
                            )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(dev.kind == .userDeviation ? BrillyPalette.blunderRose : BrillyPalette.brillyTeal)
                            Spacer()
                            Button("Jump Move \(dev.moveNumber)") {
                                goToPly(dev.ply, maxPly: ag.plies.count)
                            }
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                            .buttonStyle(.plain)
                        }

                        if dev.kind == .userDeviation {
                            Text("In \(dev.courseName), move \(dev.moveNumber): you played \(dev.playedSan) instead of course move \(dev.expectedSan).")
                                .font(.caption)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                            if let cardId = dev.matchingCardId {
                                Button {
                                    store.boostCardDueNow(cardId: cardId)
                                    boostedDeviationCardId = cardId
                                } label: {
                                    Text(boostedDeviationCardId == cardId ? "Boosted to Today's FSRS Queue ✓" : "Boost \(dev.expectedSan) to Today's FSRS Queue")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(BrillyPalette.voidBg)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(Capsule().fill(BrillyPalette.brillyTeal))
                                }
                                .buttonStyle(.plain)
                            }
                        } else if dev.kind == .opponentNovelty {
                            Text("Opponent deviated on move \(dev.moveNumber) with \(dev.playedSan) (course covers \(dev.expectedSan)).")
                                .font(.caption)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                        } else {
                            Text("Stayed inside \(dev.courseName) theory cleanly through move \(dev.moveNumber).")
                                .font(.caption)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .brillySurface(store.surfaceStyle, cornerRadius: 16, tint: dev.kind == .userDeviation ? BrillyPalette.blunderRose : BrillyPalette.brillyTeal)
                }

                // 10. Horizontal Move Strip
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ag.plies) { ply in
                            let selected = ply.ply == clampedPly
                            Button {
                                goToPly(ply.ply, maxPly: ag.plies.count)
                            } label: {
                                HStack(spacing: 4) {
                                    if ply.color == .white {
                                        Text("\(ply.moveNumber).")
                                            .foregroundStyle(BrillyPalette.inkSecondary)
                                    }
                                    Text(ply.san)
                                        .fontWeight(selected ? .bold : .medium)
                                        .foregroundStyle(selected ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                    if ply.classification == .brilliant || ply.classification == .blunder || ply.classification == .mistake {
                                        Circle()
                                            .fill(BrillyPalette.color(for: ply.classification))
                                            .frame(width: 6, height: 6)
                                    }
                                }
                                .font(.caption.monospaced())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 84)
        }
        .task(id: displayFen) {
            if SyzygyClient.isEligible(fen: displayFen) {
                syzygyResult = await SyzygyClient.shared.probe(fen: displayFen)
            } else {
                syzygyResult = nil
            }
        }
    }

    @ViewBuilder
    private func syzygyCardIfEligible(fen: String) -> some View {
        if let res = syzygyResult, SyzygyClient.isEligible(fen: fen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("7-Piece Syzygy Tablebase", systemImage: "crown.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.goldAmber)
                    Spacer()
                    Text(res.humanLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                }
                if !res.moves.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(res.moves.prefix(3)) { m in
                            Text("\(m.san) (\(m.category))")
                                .font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .brillySurface(store.surfaceStyle, cornerRadius: 14, tint: BrillyPalette.goldAmber)
        }
    }

    private func evaluateSandbox(fen: String) {
        evalTask?.cancel()
        evalGeneration &+= 1
        let gen = evalGeneration
        let engine = store.interactiveEngine
        evalTask = Task {
            if let ev = try? await engine.analyze(fen: fen, depth: 5, multiPV: 3, maxTimeMs: 350),
               !Task.isCancelled, self.evalGeneration == gen {
                self.sandboxEval = ev
            }
            if SyzygyClient.isEligible(fen: fen) {
                let res = await SyzygyClient.shared.probe(fen: fen)
                if !Task.isCancelled && self.evalGeneration == gen {
                    self.syzygyResult = res
                }
            } else if self.evalGeneration == gen {
                self.syzygyResult = nil
            }
        }
    }

    private func triggerBotReply() {
        botTask?.cancel()
        botGeneration &+= 1
        let gen = botGeneration
        botThinking = true
        let fenNow = sandboxBoard.fen
        botTask = Task {
            let reply = await store.computeBotReply(fen: fenNow, depth: 4)
            guard !Task.isCancelled && self.botGeneration == gen else { return }
            if let reply {
                _ = try? sandboxBoard.apply(reply)
                store.triggerHaptic(.move)
                updateSandboxOutcomeNotice()
                evaluateSandbox(fen: sandboxBoard.fen)
            }
            botThinking = false
        }
    }

    private func updateSandboxOutcomeNotice() {
        switch sandboxBoard.outcome {
        case .ongoing:
            botStatusNotice = nil
        case .checkmate(let winner):
            botStatusNotice = "Checkmate — \(winner.displayName) wins!"
        case .stalemate:
            botStatusNotice = "Draw by stalemate."
        case .insufficientMaterial:
            botStatusNotice = "Draw by insufficient material."
        case .fiftyMoveRule:
            botStatusNotice = "Draw by 50-move rule."
        }
    }

    private func copyText(_ text: String, label: String) {
        #if canImport(UIKit) && os(iOS)
        UIPasteboard.general.string = text
        #endif
        copiedNotice = label
        store.triggerHaptic(.success)
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedNotice == label { copiedNotice = nil }
        }
    }

    private func playerSummaryPill(name: String, acc: Double, elo: Int, isWhite: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isWhite ? Color.white : Color(hex: 0x1E293B))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                    .lineLimit(1)
                Text("\(String(format: "%.1f", acc))% · ~\(elo)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(BrillyPalette.brillyTeal)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .brillySurface(store.surfaceStyle, cornerRadius: 14)
    }

    private func transportBtn(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            store.triggerHaptic(.move)
            action()
        } label: {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrillyPalette.inkPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .brillySurface(store.surfaceStyle, cornerRadius: 14, interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
