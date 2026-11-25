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

    // Sandbox / Explore / Bot Play-Out State (with cancellable generation-guarded tasks)
    @State private var botActive: Bool = false
    @State private var sandboxBoard: ChessBoard = ChessBoard()
    @State private var sandboxHistory: [(fen: String, move: (Square, Square)?)] = []
    @State private var sandboxCursor: Int = 0
    @State private var sandboxEval: EngineEval? = nil
    @State private var botThinking: Bool = false
    @State private var botStatusNotice: String? = nil
    @State private var botTask: Task<Void, Never>? = nil
    @State private var evalTask: Task<Void, Never>? = nil
    @State private var botGeneration: Int = 0
    @State private var evalGeneration: Int = 0

    // Cached Deviation, Syzygy Tablebase, Auto-Play & Copy Toast
    @State private var cachedDeviation: OpeningDeviationReport? = nil
    @State private var syzygyResult: SyzygyProbeResult? = nil
    @State private var copiedNotice: String? = nil
    @State private var boostedDeviationCardId: String? = nil
    @State private var activeShareCard: BrillyShareCardPayload? = nil
    @State private var isAutoPlaying: Bool = false
    @State private var autoPlaySpeed: Int = 1 // 1 = 1x, 2 = 2x, 3 = 3x
    @State private var isTurboScrubbing: Bool = false
    @State private var showThreatArrow: Bool = false
    @State private var threatArrow: BoardArrow? = nil
    @State private var showingMoveListSheet: Bool = false
    @State private var showingMistakeReview: Bool = false
    @State private var opponentProfileTarget: OpponentProfileTarget? = nil

    private struct OpponentProfileTarget: Identifiable {
        let id = UUID()
        let username: String
        let platform: GameSource
    }

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
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
            guard !isTurboScrubbing,
                  !retryMode && !botActive,
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
                sandboxHistory = [(fen: newFen, move: nil)]
                sandboxCursor = 0
                botActive = false
                botStatusNotice = nil
                evaluateSandbox(fen: newFen)
            }
        }
        .sheet(item: $activeShareCard) { payload in
            BrillyShareCardSheet(payload: payload, surfaceStyle: store.surfaceStyle)
                .environment(store)
        }
        .task(id: isAutoPlaying) {
            guard isAutoPlaying else { return }
            while !Task.isCancelled && isAutoPlaying {
                guard let ag = store.activeAnalyzedGame, !retryMode, !botActive else {
                    isAutoPlaying = false
                    break
                }
                let baseMs: Int = switch autoPlaySpeed {
                case 3: 280
                case 2: 520
                default: 1020
                }
                let currentCls = (currentPlyIndex > 0 && currentPlyIndex <= ag.plies.count)
                    ? ag.plies[currentPlyIndex - 1].classification
                    : nil
                let holdExtraMs: Int = (autoPlaySpeed == 1 && (currentCls == .brilliant || currentCls == .blunder)) ? 1300 : 0
                try? await Task.sleep(for: .milliseconds(baseMs + holdExtraMs))
                guard !Task.isCancelled && isAutoPlaying else { break }
                guard let liveAg = store.activeAnalyzedGame, !retryMode, !botActive else {
                    isAutoPlaying = false
                    break
                }
                if currentPlyIndex < liveAg.plies.count {
                    currentPlyIndex += 1
                    let stepped = liveAg.plies[currentPlyIndex - 1]
                    if stepped.classification != .brilliant && stepped.classification != .blunder {
                        store.triggerHaptic(stepped.san.contains("x") ? .capture : .move)
                    }
                } else {
                    isAutoPlaying = false
                    break
                }
            }
        }
        .sheet(item: $opponentProfileTarget) { target in
            OpponentProfileSheet(username: target.username, initialPlatform: target.platform)
                .environment(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingMoveListSheet) {
            if let ag = store.activeAnalyzedGame {
                AnalyzeMoveListSheet(ag: ag, currentPly: currentPlyIndex) { chosenPly in
                    goToPly(chosenPly, maxPly: ag.plies.count)
                    showingMoveListSheet = false
                }
                .environment(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingMistakeReview) {
            if let ag = store.activeAnalyzedGame {
                GuidedMistakeReviewSheet(ag: ag)
                    .environment(store)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .task(id: "\(showThreatArrow)::\(store.activeAnalyzedGame?.id ?? "")::\(currentPlyIndex)") {
            guard showThreatArrow, store.hasProAccess, let ag = store.activeAnalyzedGame else {
                threatArrow = nil
                return
            }
            let clamped = max(0, min(currentPlyIndex, ag.plies.count))
            let fen = clamped == 0 ? ChessBoard.initialFEN : ag.plies[clamped - 1].afterFen
            guard let flipped = flippedTurnFENIfSafe(fen) else {
                threatArrow = nil
                return
            }
            if let threatMove = await store.computeBotReply(fen: flipped, depth: 4), !Task.isCancelled {
                threatArrow = BoardArrow(from: threatMove.from.algebraic, to: threatMove.to.algebraic, color: .threat)
            } else {
                threatArrow = nil
            }
        }
    }

    /// Flips side-to-move in a FEN to probe what the opponent threatens if the mover passes.
    /// Returns `nil` if the mover is currently in check (passing is illegal).
    private func flippedTurnFENIfSafe(_ fen: String) -> String? {
        guard let b = try? ChessBoard(fen: fen), !b.isInCheck(b.turn) else { return nil }
        var parts = fen.split(separator: " ").map(String.init)
        guard parts.count >= 4 else { return nil }
        parts[1] = (parts[1] == "w") ? "b" : "w"
        parts[3] = "-" // Clear en passant when passing turn
        let candidate = parts.joined(separator: " ")
        guard (try? ChessBoard(fen: candidate)) != nil else { return nil }
        return candidate
    }

    private func cancelLiveTasks() {
        isAutoPlaying = false
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
                        .blur(radius: store.effectiveCreatorNameMask == .blurred ? 5 : 0)
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

    // MARK: - Explore / Variation Sandbox View

    private func sandboxView(startFen: String) -> some View {
        let canUndo = sandboxCursor > 0
        let canRedo = sandboxCursor + 1 < sandboxHistory.count
        let activeLastMove: (from: Square, to: Square)? = {
            guard sandboxCursor >= 0 && sandboxCursor < sandboxHistory.count,
                  let pair = sandboxHistory[sandboxCursor].move else { return nil }
            return (from: pair.0, to: pair.1)
        }()

        let sandboxMaterial = sandboxBoard.materialBalance
        return ScrollView {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Label(
                        store.activeAnalyzedGame != nil ? "Explore Variation" : "Position Explorer",
                        systemImage: "arrow.triangle.branch"
                    )
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(BrillyPalette.brillyTeal)
                    .lineLimit(1)

                    if let wBadge = sandboxMaterial.compactBadgeText(for: .white) {
                        Text("W \(wBadge)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    } else if let bBadge = sandboxMaterial.compactBadgeText(for: .black) {
                        Text("B \(bBadge)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                    }

                    Spacer(minLength: 4)
                    Button(store.activeAnalyzedGame != nil ? "Back to Game" : "Exit Explore") {
                        cancelLiveTasks()
                        botActive = false
                        store.activeSandboxFen = nil
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrillyPalette.blunderRose)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(BrillyPalette.blunderRose.opacity(0.14)))
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
                    lastMove: activeLastMove,
                    arrows: sandboxBestArrow
                ) { move in
                    applyExploreMove(move, triggerBotIfActive: true)
                }

                // Undo / Redo / Reset / Bot / Flip Controls
                HStack(spacing: 8) {
                    Button {
                        stepSandboxHistory(to: sandboxCursor - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(canUndo ? BrillyPalette.inkPrimary : BrillyPalette.inkSecondary.opacity(0.4))
                            .frame(width: 44, height: 40)
                            .brillySurface(store.surfaceStyle, cornerRadius: 12, interactive: canUndo)
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                    .disabled(!canUndo)
                    .accessibilityLabel("Undo explore move")

                    Button {
                        stepSandboxHistory(to: sandboxCursor + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(canRedo ? BrillyPalette.inkPrimary : BrillyPalette.inkSecondary.opacity(0.4))
                            .frame(width: 44, height: 40)
                            .brillySurface(store.surfaceStyle, cornerRadius: 12, interactive: canRedo)
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                    .disabled(!canRedo)
                    .accessibilityLabel("Redo explore move")

                    Button {
                        stepSandboxHistory(to: 0)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(canUndo ? BrillyPalette.inkPrimary : BrillyPalette.inkSecondary.opacity(0.4))
                            .frame(width: 40, height: 40)
                            .brillySurface(store.surfaceStyle, cornerRadius: 12, interactive: canUndo)
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                    .disabled(!canUndo)
                    .accessibilityLabel("Reset to branch start")

                    Button {
                        botActive.toggle()
                        if botActive && sandboxBoard.outcome == .ongoing && sandboxBoard.turn != orientation {
                            triggerBotReply()
                        } else if !botActive {
                            cancelLiveTasks()
                        }
                    } label: {
                        Label(botActive ? "Bot: ON" : "Bot", systemImage: "cpu")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(botActive ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(Capsule().fill(botActive ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(BrillyPressScaleStyle())

                    Button {
                        orientation = orientation.opposite
                        store.triggerHaptic(.move)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .frame(width: 40, height: 40)
                            .brillySurface(store.surfaceStyle, cornerRadius: 12, interactive: true)
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                    .accessibilityLabel("Flip board")
                }

                if let botStatusNotice {
                    Text(botStatusNotice)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrillyPalette.goldAmber)
                }

                if let ev = sandboxEval {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("BrillyNative Engine (Depth \(ev.depth)) · \(ev.score.display)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                            Spacer()
                            Button {
                                copyText(sandboxBoard.fen, label: "FEN copied!")
                            } label: {
                                Label("FEN", systemImage: "doc.on.doc")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(Array(ev.lines.prefix(3).enumerated()), id: \.offset) { idx, line in
                            let pv = ChessMath.uciLineToSAN(fen: sandboxBoard.fen, uciMoves: line.pv, maxMoves: 5)
                            Button {
                                if let firstUci = line.pv.first, let move = ChessMove(uci: firstUci) {
                                    applyExploreMove(move, triggerBotIfActive: true)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("#\(idx + 1)")
                                        .font(.caption2.monospacedDigit().weight(.black))
                                        .foregroundStyle(idx == 0 ? BrillyPalette.brillyTeal : BrillyPalette.inkSecondary)
                                    Text(line.score.display)
                                        .font(.caption.monospacedDigit().weight(.bold))
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                        .frame(width: 44, alignment: .leading)
                                    Text(pv.joined(separator: " "))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(BrillyPalette.inkSecondary)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        Text("Tap any engine line to play its move on the board.")
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.inkSecondary.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .brillySurface(store.surfaceStyle, cornerRadius: 16)
                }

                if let copiedNotice {
                    Text(copiedNotice)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                }

                syzygyCardIfEligible(fen: sandboxBoard.fen)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 36)
            .onAppear {
                if sandboxHistory.isEmpty, let b = try? ChessBoard(fen: startFen) {
                    sandboxBoard = b
                    sandboxHistory = [(fen: startFen, move: nil)]
                    sandboxCursor = 0
                    evaluateSandbox(fen: startFen)
                }
            }
        }
        .brillySoftScrollEdge()
    }

    private func applyExploreMove(_ move: ChessMove, triggerBotIfActive: Bool) {
        guard (try? sandboxBoard.apply(move)) != nil else { return }
        // Truncate any redo branch when playing a new variation move
        if sandboxCursor + 1 < sandboxHistory.count {
            sandboxHistory = Array(sandboxHistory.prefix(sandboxCursor + 1))
        }
        sandboxHistory.append((fen: sandboxBoard.fen, move: (move.from, move.to)))
        sandboxCursor = sandboxHistory.count - 1
        store.triggerHaptic(.move)
        updateSandboxOutcomeNotice()
        evaluateSandbox(fen: sandboxBoard.fen)
        if triggerBotIfActive && botActive && sandboxBoard.outcome == .ongoing {
            triggerBotReply()
        }
    }

    private func stepSandboxHistory(to index: Int) {
        guard index >= 0 && index < sandboxHistory.count,
              let b = try? ChessBoard(fen: sandboxHistory[index].fen) else { return }
        cancelLiveTasks()
        sandboxBoard = b
        sandboxCursor = index
        store.triggerHaptic(.move)
        updateSandboxOutcomeNotice()
        evaluateSandbox(fen: b.fen)
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

        let maskedWhite = store.maskedPlayerName(ag.game.white.name, opponent: ag.game.black.name, side: .white)
        let maskedBlack = store.maskedPlayerName(ag.game.black.name, opponent: ag.game.white.name, side: .black)
        let exhibitionTheme = store.effectiveExhibitionTheme
        let broadcastRibbon = store.resolvedBroadcastRibbon(forPgn: ag.game.pgn)

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
                pieceSet: store.effectivePieceSet,
                vibe: store.vibeMode,
                calloutStyle: store.effectiveCalloutStyle,
                emojiPack: store.effectiveEmojiPack,
                moveNotation: notation,
                classification: activePly?.classification,
                title: "\(maskedWhite.text) vs \(maskedBlack.text)",
                coachingLine: detail,
                evalDisplay: score.display,
                evalScore: score,
                whiteName: maskedWhite.text,
                blackName: maskedBlack.text,
                whiteAccuracy: ag.whiteSummary.accuracy,
                blackAccuracy: ag.blackSummary.accuracy,
                activeSide: moverSide,
                accuracyTag: accTag,
                openingName: ag.openingLineDetected ?? ag.game.openingName,
                lastMove: lastMovePair,
                showMoveArrow: true,
                quipIndex: Int.random(in: 0..<12),
                blurPlayerNames: maskedWhite.isBlurred || maskedBlack.isBlurred,
                exhibitionTheme: exhibitionTheme,
                broadcastRibbon: broadcastRibbon,
                showCreatorHandle: store.effectiveShowCreatorHandle
            )
        }

        ScrollView {
            VStack(spacing: 10) {
                // 0. Compact Analyze Header + Depth Pill + Jump/Flip/Menu Controls
                HStack(spacing: 8) {
                    Text("Analyze")
                        .font(.title2.weight(.black))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .lineLimit(1)

                    let activePreset = store.analysisPreset
                    let depthPillTint: Color = activePreset.usesCloudEval
                        ? BrillyPalette.warpPurpleText
                        : (activePreset == .ultra ? BrillyPalette.goldAmber : BrillyPalette.brillyTeal)

                    Menu {
                        ForEach(AnalysisDepthPreset.batchPresets) { preset in
                            Button {
                                store.reanalyzeActiveGame(preset: preset, currentPly: clampedPly)
                                store.triggerHaptic(.move)
                            } label: {
                                Label(
                                    "\(preset.title) · \(preset.eloEstimate)",
                                    systemImage: activePreset == preset ? "checkmark" : preset.sfSymbol
                                )
                            }
                        }
                        Divider()
                        ForEach([AnalysisDepthPreset.ultra, .cloudUltra]) { preset in
                            Button {
                                store.reanalyzeActiveGame(preset: preset, currentPly: clampedPly)
                                store.triggerHaptic(.move)
                            } label: {
                                let labelText = store.hasProAccess
                                    ? "\(preset.title) · \(preset.eloEstimate)"
                                    : "\(preset.title) · \(preset.eloEstimate) (Pro)"
                                Label(
                                    labelText,
                                    systemImage: !store.hasProAccess ? "lock.fill" : (activePreset == preset ? "checkmark" : preset.sfSymbol)
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: activePreset.sfSymbol)
                                .font(.system(size: 10, weight: .bold))
                            Text(activePreset.title)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(depthPillTint)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(depthPillTint.opacity(0.15))
                                .overlay(Capsule().strokeBorder(depthPillTint.opacity(0.40), lineWidth: 0.9))
                        )
                    }
                    .accessibilityLabel("Engine preset \(activePreset.title), \(activePreset.eloEstimate). Tap to change depth and re-analyze.")

                    Spacer(minLength: 4)

                    HStack(spacing: 6) {
                        headerIconBtn(
                            "backward.end.fill",
                            label: "First move (hold for previous key moment)",
                            onTap: { goToPly(0, maxPly: ag.plies.count) },
                            onHold: { jumpToKeyMoment(in: ag, forward: false) }
                        )
                        .opacity(clampedPly == 0 ? 0.35 : 1.0)
                        .disabled(clampedPly == 0)

                        headerIconBtn(
                            "forward.end.fill",
                            label: "Last move (hold for next key moment)",
                            onTap: { goToPly(ag.plies.count, maxPly: ag.plies.count) },
                            onHold: { jumpToKeyMoment(in: ag, forward: true) }
                        )
                        .opacity(clampedPly >= ag.plies.count ? 0.35 : 1.0)
                        .disabled(clampedPly >= ag.plies.count)
                        headerIconBtn("arrow.up.arrow.down", label: "Flip board", onTap: {
                            orientation = orientation.opposite
                        })

                        Menu {
                            if let ap = activePly {
                                let isSaved = store.isBookmarked(gameId: ag.game.id, ply: ap.ply)
                                Button {
                                    store.toggleBookmark(ply: ap, game: ag.game)
                                    store.triggerHaptic(.move)
                                } label: {
                                    Label(isSaved ? "Remove Bookmark" : "Bookmark Position", systemImage: isSaved ? "bookmark.slash" : "bookmark.fill")
                                }
                            }
                            Button {
                                activeShareCard = sharePayload()
                            } label: {
                                Label("Share Move Card", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                showingMoveListSheet = true
                                store.triggerHaptic(.move)
                            } label: {
                                Label("Move List (\(ag.plies.count) plies)", systemImage: "list.number")
                            }
                            Divider()
                            Button {
                                if !store.hasProAccess {
                                    store.openProPaywall(feature: "Guided Mistake Review")
                                    return
                                }
                                showingMistakeReview = true
                                store.triggerHaptic(.move)
                            } label: {
                                Label(
                                    store.hasProAccess ? "Review My Mistakes" : "Review My Mistakes (Pro)",
                                    systemImage: store.hasProAccess ? "target" : "lock.fill"
                                )
                            }
                            Button {
                                if !store.hasProAccess {
                                    store.openProPaywall(feature: "Live Engine Threat Arrow")
                                    return
                                }
                                showThreatArrow.toggle()
                                if !showThreatArrow { threatArrow = nil }
                                store.triggerHaptic(.move)
                            } label: {
                                Label(
                                    showThreatArrow ? "Hide Threat Arrow" : (store.hasProAccess ? "Show Threat Arrow" : "Show Threat Arrow (Pro)"),
                                    systemImage: showThreatArrow ? "exclamationmark.triangle.fill" : (store.hasProAccess ? "exclamationmark.triangle" : "lock.fill")
                                )
                            }
                            Divider()
                            Button {
                                copyText(displayFen, label: "FEN copied")
                            } label: {
                                Label("Copy FEN", systemImage: "doc.on.doc")
                            }
                            Button {
                                copyText(ag.game.pgn, label: "PGN copied")
                            } label: {
                                Label("Copy PGN", systemImage: "text.alignleft")
                            }
                            Divider()
                            Button {
                                cancelLiveTasks()
                                isAutoPlaying = false
                                retryMode = false
                                botActive = false
                                botStatusNotice = nil
                                sandboxBoard = board
                                sandboxHistory = [(fen: displayFen, move: nil)]
                                sandboxCursor = 0
                                store.activeSandboxFen = displayFen
                                evaluateSandbox(fen: displayFen)
                                store.triggerHaptic(.move)
                            } label: {
                                Label("Explore from Here", systemImage: "arrow.triangle.branch")
                            }
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
                                Label(botActive ? "Stop Play Bot" : "Play Bot from Here", systemImage: "cpu")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .frame(width: 38, height: 36)
                                .brillySurface(store.surfaceStyle, cornerRadius: 12, interactive: true)
                        }
                        .accessibilityLabel("More game actions")
                    }
                }

                // Optional Exhibition Broadcast Ribbon (Founder Admin Creator Studio)
                if let broadcastRibbon, exhibitionTheme != .none {
                    HStack(spacing: 6) {
                        Image(systemName: exhibitionTheme == .worldChampionship ? "crown.fill" : "bolt.fill")
                            .font(.system(size: 10, weight: .black))
                        Text(broadcastRibbon)
                            .font(.system(size: 10.5, weight: .black, design: .rounded))
                            .tracking(1.2)
                            .lineLimit(1)
                    }
                    .foregroundStyle(BrillyPalette.voidBg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 12)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [exhibitionTheme.accentColor, exhibitionTheme.secondaryAccent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
                }

                // 1. Accuracy, Live Clock & Live Material Summary Strip
                let material = board.materialBalance
                let whiteClock = latestClock(in: ag, upToPly: clampedPly, for: .white)
                let blackClock = latestClock(in: ag, upToPly: clampedPly, for: .black)
                let gameOngoingAtPly = clampedPly < ag.plies.count
                HStack(spacing: 10) {
                    playerSummaryPill(
                        name: maskedWhite.text,
                        rawName: ag.game.white.name,
                        isBlurred: maskedWhite.isBlurred,
                        acc: ag.whiteSummary.accuracy,
                        elo: ag.whiteSummary.estimatedElo,
                        isWhite: true,
                        materialBadge: material.compactBadgeText(for: .white),
                        clockDisplay: whiteClock?.display,
                        clockSeconds: whiteClock?.seconds,
                        isClockActive: gameOngoingAtPly && board.turn == .white,
                        exhibitionTheme: exhibitionTheme
                    )
                    playerSummaryPill(
                        name: maskedBlack.text,
                        rawName: ag.game.black.name,
                        isBlurred: maskedBlack.isBlurred,
                        acc: ag.blackSummary.accuracy,
                        elo: ag.blackSummary.estimatedElo,
                        isWhite: false,
                        materialBadge: material.compactBadgeText(for: .black),
                        clockDisplay: blackClock?.display,
                        clockSeconds: blackClock?.seconds,
                        isClockActive: gameOngoingAtPly && board.turn == .black,
                        exhibitionTheme: exhibitionTheme
                    )
                }

                // 2. Live Eval Bar
                EvalBarView(score: score, orientation: orientation)

                // 3. Interactive Board
                let combinedArrows: [BoardArrow] = {
                    var list = bestArrow
                    if showThreatArrow, let threat = threatArrow, !retryMode && !botActive {
                        list.append(threat)
                    }
                    return list
                }()
                InteractiveChessBoardView(
                    board: board,
                    orientation: orientation,
                    theme: store.effectiveBoardTheme,
                    surfaceStyle: store.surfaceStyle,
                    interactive: retryMode || (botActive && !botThinking && sandboxBoard.outcome == .ongoing),
                    lastMove: lastMovePair,
                    arrows: combinedArrows,
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

                // 4. Spacious Un-Squished Transport Bar (< Hold-Turbo | AUTO/PAUSE | > Hold-Turbo | 1x/2x/3x)
                let atStartOfGame = clampedPly <= 0
                let atEndOfGame = clampedPly >= ag.plies.count
                BrillyGlassCluster(style: store.surfaceStyle, spacing: 8) {
                    HStack(spacing: 8) {
                        turboTransportBtn(
                            icon: "chevron.left",
                            turboIcon: "chevron.left.2",
                            label: "Previous move (hold to rewind quickly)",
                            delta: -1,
                            maxPly: ag.plies.count
                        )
                        .opacity(atStartOfGame ? 0.30 : 1.0)
                        .allowsHitTesting(!atStartOfGame)

                        Button {
                            if !isAutoPlaying {
                                retryMode = false
                                botActive = false
                                if clampedPly >= ag.plies.count {
                                    currentPlyIndex = 0
                                }
                                isAutoPlaying = true
                            } else {
                                isAutoPlaying = false
                            }
                            store.triggerHaptic(.move)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isAutoPlaying ? "pause.fill" : "play.fill")
                                    .font(.caption.weight(.black))
                                Text(isAutoPlaying ? "PAUSE" : "AUTO")
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                    .tracking(0.6)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .foregroundStyle(isAutoPlaying ? BrillyPalette.voidBg : BrillyPalette.brillyTeal)
                            .padding(.horizontal, 18)
                            .frame(minWidth: 112, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(isAutoPlaying ? BrillyPalette.brillyTeal : BrillyPalette.brillyTeal.opacity(0.16))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(BrillyPalette.brillyTeal.opacity(0.50), lineWidth: 1.2)
                                    )
                            )
                        }
                        .buttonStyle(BrillyPressScaleStyle())
                        .layoutPriority(1)
                        .accessibilityLabel(isAutoPlaying ? "Pause auto-play" : "Start auto-play")

                        turboTransportBtn(
                            icon: "chevron.right",
                            turboIcon: "chevron.right.2",
                            label: atEndOfGame ? "End of game" : "Next move (hold to turbo forward)",
                            delta: 1,
                            maxPly: ag.plies.count
                        )
                        .opacity(atEndOfGame ? 0.30 : 1.0)
                        .allowsHitTesting(!atEndOfGame)

                        Text("\(autoPlaySpeed)x")
                            .font(.subheadline.monospacedDigit().weight(.black))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(autoPlaySpeed > 1 ? BrillyPalette.brillyTeal : BrillyPalette.inkPrimary)
                            .frame(minWidth: 48, minHeight: 44)
                            .brillySurface(store.surfaceStyle, cornerRadius: 14, tint: autoPlaySpeed > 1 ? BrillyPalette.brillyTeal : nil, interactive: true)
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .onTapGesture {
                                autoPlaySpeed = (autoPlaySpeed % 3) + 1
                                store.triggerHaptic(.move)
                            }
                            .onLongPressGesture(minimumDuration: 0.35) {
                                autoPlaySpeed = 1
                                store.triggerHaptic(.move)
                                flashNotice("Speed reset to 1x")
                            }
                            .accessibilityLabel("Auto-play speed \(autoPlaySpeed)x. Tap to cycle 1x, 2x, 3x; hold to reset.")
                            .accessibilityAddTraits(.isButton)
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
                        HStack(spacing: 8) {
                            Button {
                                showingMoveListSheet = true
                                store.triggerHaptic(.move)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("\(ap.moveNumber)\(ap.color == .white ? "." : "...") \(ap.san)")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                        .lineLimit(1)
                                    Image(systemName: "list.bullet")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(BrillyPalette.inkSecondary.opacity(0.75))
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open move list at move \(ap.moveNumber) \(ap.san)")
                            Text(store.classificationLabel(ap.classification))
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .foregroundStyle(BrillyPalette.badgeForeground(for: ap.classification))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(BrillyPalette.color(for: ap.classification)))

                            if let spent = ap.timeSpentSeconds {
                                let spentText = formatMoveDuration(spent)
                                let isImpulse = ap.clockTag == "impulse"
                                let isTimeTrouble = ap.clockTag == "time-trouble"
                                let pillText = isImpulse
                                    ? "⚡ \(spentText) · Impulse"
                                    : (isTimeTrouble ? "⏱ \(spentText) · Time Trouble" : "⏱ \(spentText)")
                                let pillColor: Color = isTimeTrouble
                                    ? BrillyPalette.blunderRose
                                    : (isImpulse ? BrillyPalette.goldAmber : BrillyPalette.inkSecondary)

                                Text(pillText)
                                    .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .foregroundStyle(pillColor)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        Capsule()
                                            .fill(pillColor.opacity(isTimeTrouble || isImpulse ? 0.16 : 0.10))
                                            .overlay(Capsule().strokeBorder(pillColor.opacity(0.28), lineWidth: 0.7))
                                    )
                            }
                            Spacer(minLength: 4)
                            if ap.classification == .blunder || ap.classification == .mistake {
                                Button(retryMode ? "Exit Retry" : "Retry") {
                                    retryMode.toggle()
                                    botActive = false
                                    retrySolvedBoard = nil
                                    retrySolvedLastMove = nil
                                    retryFeedback = retryMode ? "Find the better move instead of \(ap.san)." : nil
                                }
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .foregroundStyle(BrillyPalette.brillyTeal)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                                .buttonStyle(BrillyPressScaleStyle())
                            }
                        }

                        Text(retryFeedback ?? ap.coaching.headline)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrillyPalette.inkPrimary)

                        Text(ap.coaching.detail)
                            .font(.caption)
                            .foregroundStyle(BrillyPalette.inkSecondary)

                        if clampedPly == ag.plies.count && !retryMode {
                            let endBannerText: String = {
                                switch ag.game.resultString {
                                case "1-0": return "Final Move · White Wins (1–0)"
                                case "0-1": return "Final Move · Black Wins (0–1)"
                                case "1/2-1/2": return "Final Move · Game Drawn (½–½)"
                                default: return "Final Move · End of Recorded Game"
                                }
                            }()
                            HStack(spacing: 6) {
                                Image(systemName: "flag.checkered")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(BrillyPalette.goldAmber)
                                Text(endBannerText)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.goldAmber)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(BrillyPalette.goldAmber.opacity(0.13))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(BrillyPalette.goldAmber.opacity(0.32), lineWidth: 0.8)
                                    )
                            )
                        }

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
                                            .frame(minWidth: 44, alignment: .leading)
                                            .fixedSize(horizontal: true, vertical: false)
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

                    if let ap = activePly {
                        let isSaved = store.isBookmarked(gameId: ag.game.id, ply: ap.ply)
                        Button {
                            store.toggleBookmark(ply: ap, game: ag.game)
                            store.triggerHaptic(.move)
                        } label: {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(isSaved ? BrillyPalette.goldAmber : BrillyPalette.inkPrimary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(isSaved ? BrillyPalette.goldAmber.opacity(0.18) : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isSaved ? "Remove bookmark" : "Bookmark position")
                    }

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

                // 10. Horizontal Move Strip (auto-scrolls smoothly to active ply during AUTO-play!)
                ScrollViewReader { proxy in
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
                                                .foregroundStyle(selected ? BrillyPalette.voidBg.opacity(0.78) : BrillyPalette.inkSecondary)
                                        }
                                        Text(ply.san)
                                            .fontWeight(selected ? .bold : .medium)
                                            .foregroundStyle(selected ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                        if ply.classification == .brilliant || ply.classification == .blunder || ply.classification == .mistake {
                                            Circle()
                                                .fill(BrillyPalette.color(for: ply.classification))
                                                .frame(width: 7, height: 7)
                                                .overlay(
                                                    Circle().strokeBorder(selected ? BrillyPalette.voidBg : Color.clear, lineWidth: 1)
                                                )
                                        }
                                    }
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 8)
                                    .background(Capsule().fill(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
                                }
                                .buttonStyle(.plain)
                                .id(ply.ply)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onChange(of: clampedPly) { _, newTarget in
                        if newTarget > 0 {
                            withAnimation(.snappy(duration: 0.2)) {
                                proxy.scrollTo(newTarget, anchor: .center)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 36)
        }
        .brillySoftScrollEdge()
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(res.moves.prefix(3)) { m in
                                Text("\(m.san) (\(m.category))")
                                    .font(.caption2.monospaced().weight(.semibold))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                            }
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
                if store.activeSandboxFen != nil {
                    applyExploreMove(reply, triggerBotIfActive: false)
                } else {
                    _ = try? sandboxBoard.apply(reply)
                    store.triggerHaptic(.move)
                    updateSandboxOutcomeNotice()
                    evaluateSandbox(fen: sandboxBoard.fen)
                }
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
        flashNotice(label)
        store.triggerHaptic(.success)
    }

    private func flashNotice(_ label: String) {
        copiedNotice = label
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if copiedNotice == label { copiedNotice = nil }
        }
    }

    private func jumpToKeyMoment(in ag: AnalyzedGame, forward: Bool) {
        let keyClasses: Set<MoveClassification> = [.brilliant, .blunder, .mistake]
        let clamped = max(0, min(currentPlyIndex, ag.plies.count))
        let match: AnalyzedPly?
        if forward {
            match = ag.plies.first { $0.ply > clamped && keyClasses.contains($0.classification) }
        } else {
            match = ag.plies.last { $0.ply < clamped && keyClasses.contains($0.classification) }
        }
        if let target = match {
            goToPly(target.ply, maxPly: ag.plies.count)
            let sym = target.classification.symbol
            flashNotice("Key moment: \(target.moveNumber)\(target.color == .white ? "." : "...") \(target.san)\(sym)")
        } else {
            store.triggerHaptic(.move)
            flashNotice(forward ? "No later key moment" : "No earlier key moment")
        }
    }

    private func playerSummaryPill(
        name: String,
        rawName: String,
        isBlurred: Bool = false,
        acc: Double,
        elo: Int,
        isWhite: Bool,
        materialBadge: String? = nil,
        clockDisplay: String? = nil,
        clockSeconds: Double? = nil,
        isClockActive: Bool = false,
        exhibitionTheme: CreatorExhibitionTheme = .none
    ) -> some View {
        let targetSide: PieceColor = isWhite ? .white : .black
        let isFocused = orientation == targetSide
        let pillTint: Color? = {
            if exhibitionTheme != .none {
                return exhibitionTheme.accentColor
            }
            return isFocused ? BrillyPalette.brillyTeal : nil
        }()
        let clockTint: Color = {
            if let secs = clockSeconds {
                if secs < 30 { return BrillyPalette.blunderRose }
                if secs < 60 { return BrillyPalette.goldAmber }
            }
            return isClockActive ? BrillyPalette.brillyTeal : BrillyPalette.inkPrimary
        }()
        return HStack(spacing: 7) {
            Circle()
                .fill(isWhite ? Color.white : Color(hex: 0x1E293B))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .frame(width: 13, height: 13)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                    .lineLimit(1)
                    .blur(radius: isBlurred ? 5 : 0)
                Text("\(String(format: "%.1f", acc))% · ~\(elo)")
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(exhibitionTheme != .none ? exhibitionTheme.accentColor : BrillyPalette.brillyTeal)
            }
            Spacer(minLength: 2)
            if clockDisplay != nil || materialBadge != nil {
                VStack(alignment: .trailing, spacing: 3) {
                    if let clockDisplay {
                        let isLowTime = (clockSeconds ?? 999) < 60
                        Text(clockDisplay)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(clockTint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isLowTime || isClockActive ? clockTint.opacity(0.16) : Color.white.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(
                                                isLowTime || isClockActive ? clockTint.opacity(0.45) : Color.white.opacity(0.12),
                                                lineWidth: isClockActive || isLowTime ? 0.9 : 0.6
                                            )
                                    )
                            )
                    }
                    if let materialBadge {
                        Text(materialBadge)
                            .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.11))
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7))
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .brillySurface(store.surfaceStyle, cornerRadius: 14, tint: pillTint)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    exhibitionTheme != .none ? exhibitionTheme.accentColor.opacity(0.55) : Color.clear,
                    lineWidth: exhibitionTheme != .none ? 1.2 : 0
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            let cleanRaw = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowerHandles = Set(store.userHandles.map { $0.lowercased() })
            let isOwnHandle = lowerHandles.contains(cleanRaw.lowercased())
            let isLookupEligible = !isOwnHandle
                && !cleanRaw.isEmpty
                && cleanRaw.lowercased() != "white"
                && cleanRaw.lowercased() != "black"
                && cleanRaw.lowercased() != "anonymous"
                && !cleanRaw.contains(" ")

            if isLookupEligible {
                if !store.hasProAccess {
                    store.openProPaywall(feature: "Quick Opponent Profile & Recent Games")
                    return
                }
                let src = store.activeAnalyzedGame?.game.source ?? store.syncPlatform
                let resolvedPlatform: GameSource = (src == .chesscom) ? .chesscom : .lichess
                opponentProfileTarget = OpponentProfileTarget(username: cleanRaw, platform: resolvedPlatform)
                store.triggerHaptic(.move)
            } else if orientation != targetSide {
                orientation = targetSide
                store.triggerHaptic(.move)
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            copyText(rawName, label: "Copied \(name)")
        }
        .accessibilityLabel("\(name), \(String(format: "%.1f", acc)) percent accuracy\(materialBadge.map { ", up \($0)" } ?? ""). Tap to view from \(isWhite ? "White" : "Black") side.")
    }

    private func headerIconBtn(
        _ icon: String,
        label: String,
        onTap: @escaping () -> Void,
        onHold: (() -> Void)? = nil
    ) -> some View {
        Image(systemName: icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(BrillyPalette.inkPrimary)
            .frame(width: 38, height: 36)
            .brillySurface(store.surfaceStyle, cornerRadius: 12, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                store.triggerHaptic(.move)
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.35) {
                if let onHold {
                    store.triggerHaptic(.move)
                    onHold()
                }
            }
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }

    private func turboTransportBtn(
        icon: String,
        turboIcon: String,
        label: String,
        delta: Int,
        maxPly: Int
    ) -> some View {
        BrillyTurboStepButton(
            onSingleStep: {
                store.triggerHaptic(.move)
                goToPly(currentPlyIndex + delta, maxPly: maxPly)
            },
            onTurboStep: { tick in
                let next = max(0, min(maxPly, currentPlyIndex + delta))
                guard next != currentPlyIndex else { return false }
                goToPly(next, maxPly: maxPly)
                if tick % 3 == 0 {
                    store.triggerHaptic(.move)
                }
                return true
            },
            onTurboStateChanged: { active in
                isTurboScrubbing = active
            }
        ) { isTurbo in
            Image(systemName: isTurbo ? turboIcon : icon)
                .font(.subheadline.weight(isTurbo ? .black : .semibold))
                .foregroundStyle(isTurbo ? BrillyPalette.brillyTeal : BrillyPalette.inkPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .brillySurface(store.surfaceStyle, cornerRadius: 14, tint: isTurbo ? BrillyPalette.brillyTeal : nil, interactive: true)
        }
        .accessibilityLabel(label)
    }

    // MARK: - Live Chess Clock Helpers

    private func latestClock(
        in ag: AnalyzedGame,
        upToPly: Int,
        for color: PieceColor
    ) -> (seconds: Double?, display: String)? {
        let hasAnyClock = ag.plies.contains { $0.clockSeconds != nil || $0.clockText != nil }
        guard hasAnyClock else { return nil }

        let clamped = max(0, min(upToPly, ag.plies.count))
        for ply in ag.plies.prefix(clamped).reversed() where ply.color == color {
            if let secs = ply.clockSeconds {
                return (secs, formatChessClock(secs))
            }
            if let txt = ply.clockText, !txt.isEmpty {
                return (nil, txt)
            }
        }

        // Before this side's first move (ply 0 or ply 1 for Black), show initial time control or first recorded clock
        if let firstSidePly = ag.plies.first(where: { $0.color == color && ($0.clockSeconds != nil || $0.clockText != nil) }) {
            if let secs = firstSidePly.clockSeconds {
                return (secs, formatChessClock(secs))
            }
            if let txt = firstSidePly.clockText, !txt.isEmpty {
                return (nil, txt)
            }
        }
        return nil
    }

    private func formatChessClock(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        if clamped >= 3600 {
            let total = Int(clamped.rounded(.down))
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            return String(format: "%d:%02d:%02d", h, m, s)
        } else if clamped < 20 {
            let totalTenths = Int((clamped * 10).rounded(.down))
            let s = totalTenths / 10
            let d = totalTenths % 10
            return String(format: "0:%02d.%d", s, d)
        } else {
            let total = Int(clamped.rounded(.down))
            let m = total / 60
            let s = total % 60
            return String(format: "%d:%02d", m, s)
        }
    }

    private func formatMoveDuration(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        if clamped < 60 {
            let rounded = Int(clamped.rounded())
            return "\(rounded)s"
        }
        let total = Int(clamped.rounded())
        let m = total / 60
        let s = total % 60
        return s == 0 ? "\(m)m" : "\(m)m \(s)s"
    }
}

// MARK: - Tappable 2-Column Move List Sheet

private struct AnalyzeMoveListSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let ag: AnalyzedGame
    let currentPly: Int
    let onSelectPly: (Int) -> Void

    private var moveRows: [(moveNumber: Int, white: AnalyzedPly?, black: AnalyzedPly?)] {
        var rows: [(Int, AnalyzedPly?, AnalyzedPly?)] = []
        var idx = 0
        while idx < ag.plies.count {
            let p = ag.plies[idx]
            if p.color == .white {
                let nextBlack = (idx + 1 < ag.plies.count && ag.plies[idx + 1].color == .black) ? ag.plies[idx + 1] : nil
                rows.append((p.moveNumber, p, nextBlack))
                idx += (nextBlack != nil) ? 2 : 1
            } else {
                rows.append((p.moveNumber, nil, p))
                idx += 1
            }
        }
        return rows
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(moveRows, id: \.moveNumber) { row in
                                HStack(spacing: 8) {
                                    Text("\(row.moveNumber).")
                                        .font(.caption.monospacedDigit().weight(.bold))
                                        .foregroundStyle(BrillyPalette.inkSecondary)
                                        .frame(width: 30, alignment: .trailing)

                                    moveCell(row.white)
                                    moveCell(row.black)
                                }
                                .id(row.moveNumber)
                            }
                        }
                        .padding(14)
                    }
                    .onAppear {
                        if currentPly > 0, currentPly <= ag.plies.count {
                            let moveNum = ag.plies[currentPly - 1].moveNumber
                            proxy.scrollTo(moveNum, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle("Move List")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func moveCell(_ ply: AnalyzedPly?) -> some View {
        if let ply {
            let isSelected = ply.ply == currentPly
            let clsColor = BrillyPalette.color(for: ply.classification)
            let isNotable = ply.classification == .brilliant || ply.classification == .great
                || ply.classification == .blunder || ply.classification == .mistake || ply.classification == .inaccuracy
            Button {
                onSelectPly(ply.ply)
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isNotable ? clsColor : Color.white.opacity(0.20))
                        .frame(width: 7, height: 7)
                    Text(ply.san)
                        .font(.subheadline.monospaced().weight(isSelected ? .black : .semibold))
                        .foregroundStyle(isSelected ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(ply.evalAfter.display)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(isSelected ? BrillyPalette.voidBg.opacity(0.85) : BrillyPalette.inkSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? BrillyPalette.brillyTeal : Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isSelected ? BrillyPalette.brillyTeal : Color.white.opacity(0.08), lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(.plain)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 34)
        }
    }
}

// MARK: - Guided "Review My Mistakes" Mode (Pro)

private struct GuidedMistakeReviewSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let ag: AnalyzedGame

    @State private var index: Int = 0
    @State private var board: ChessBoard = ChessBoard()
    @State private var solvedCurrent: Bool = false
    @State private var revealedCurrent: Bool = false
    @State private var nailedCount: Int = 0
    @State private var totalEvalSavedCp: Int = 0
    @State private var feedback: String = ""
    @State private var feedbackIsError: Bool = false
    @State private var finished: Bool = false

    private var userSide: PieceColor? {
        ag.game.resolvedUserColor(handles: store.userHandles)
    }

    private var mistakes: [AnalyzedPly] {
        ag.plies.filter { ap in
            let isMistakeOrBlunder = ap.classification == .blunder || ap.classification == .mistake
            if let side = userSide {
                return isMistakeOrBlunder && ap.color == side
            }
            return isMistakeOrBlunder
        }
    }

    private var currentMistake: AnalyzedPly? {
        guard index >= 0 && index < mistakes.count else { return nil }
        return mistakes[index]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                if mistakes.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        Text("Zero Mistakes to Review!")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Text("Clean game — no blunders or mistakes detected for your side.")
                            .font(.subheadline)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                } else if finished {
                    VStack(spacing: 16) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(BrillyPalette.goldAmber)
                        Text("Mistake Review Complete!")
                            .font(.title2.weight(.black))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Text("You nailed \(nailedCount) of \(mistakes.count) critical moment\(mistakes.count == 1 ? "" : "s") and saved +\(String(format: "%.1f", Double(totalEvalSavedCp) / 100.0)) pawns of eval.")
                            .font(.subheadline)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                        Button("Done") { dismiss() }
                            .font(.headline.weight(.bold))
                            .foregroundStyle(BrillyPalette.voidBg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Capsule().fill(BrillyPalette.brillyTeal))
                            .buttonStyle(BrillyPressScaleStyle())
                            .padding(.top, 6)
                    }
                    .padding(24)
                    .brillySurface(store.surfaceStyle, cornerRadius: 22, tint: BrillyPalette.brillyTeal)
                    .padding(20)
                } else if let ap = currentMistake {
                    ScrollView {
                        VStack(spacing: 14) {
                            HStack {
                                Text("Mistake \(index + 1) of \(mistakes.count)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                                Spacer()
                                Text("Nailed \(nailedCount)")
                                    .font(.caption.monospacedDigit().weight(.black))
                                    .foregroundStyle(BrillyPalette.goldAmber)
                            }

                            InteractiveChessBoardView(
                                board: board,
                                orientation: ap.color,
                                theme: store.effectiveBoardTheme,
                                surfaceStyle: store.surfaceStyle,
                                interactive: !solvedCurrent && !revealedCurrent,
                                arrows: (solvedCurrent || revealedCurrent) ? bestArrowFor(ap) : []
                            ) { move in
                                handleMove(move, for: ap)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Move \(ap.moveNumber): You played \(ap.san) (\(store.classificationLabel(ap.classification)))")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BrillyPalette.color(for: ap.classification))

                                if !feedback.isEmpty {
                                    Text(feedback)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(feedbackIsError ? BrillyPalette.blunderRose : BrillyPalette.brillyTeal)
                                } else {
                                    Text("Find the stronger move on the board!")
                                        .font(.subheadline)
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .brillySurface(store.surfaceStyle, cornerRadius: 16)

                            HStack(spacing: 10) {
                                if solvedCurrent || revealedCurrent {
                                    Button {
                                        advanceToNext()
                                    } label: {
                                        Text(index + 1 < mistakes.count ? "Next Mistake →" : "Finish Review")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(BrillyPalette.voidBg)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Capsule().fill(BrillyPalette.brillyTeal))
                                    }
                                    .buttonStyle(BrillyPressScaleStyle())
                                } else {
                                    Button("Reveal Best Move") {
                                        revealedCurrent = true
                                        feedbackIsError = false
                                        feedback = "Best was \(ap.bestMoveSan). \(ap.coaching.headline)"
                                        store.triggerHaptic(.move)
                                    }
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BrillyPalette.goldAmber)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Review My Mistakes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { loadCurrentMistake() }
        }
    }

    private func bestArrowFor(_ ap: AnalyzedPly) -> [BoardArrow] {
        guard let m = ChessMove(uci: ap.bestMoveUci) else { return [] }
        return [BoardArrow(from: m.from.algebraic, to: m.to.algebraic, color: .best)]
    }

    private func loadCurrentMistake() {
        guard let ap = currentMistake else { return }
        board = (try? ChessBoard(fen: ap.beforeFen)) ?? ChessBoard()
        solvedCurrent = false
        revealedCurrent = false
        feedback = ""
        feedbackIsError = false
    }

    private func handleMove(_ move: ChessMove, for ap: AnalyzedPly) {
        if move.uci == ap.bestMoveUci {
            var next = board
            if (try? next.apply(move)) != nil {
                board = next
            }
            solvedCurrent = true
            feedbackIsError = false
            nailedCount += 1
            let saved = max(50, abs(ap.evalBefore.cpWhite - ap.evalAfter.cpWhite))
            totalEvalSavedCp += min(saved, 600)
            feedback = "Nailed it! \(ap.bestMoveSan) was the top engine move."
            store.recordTrainingActivity()
            store.triggerHaptic(.success)
        } else {
            feedbackIsError = true
            feedback = "Not \(move.uci) — try looking for a sharper tactic or stronger defense!"
            store.triggerHaptic(.error)
        }
    }

    private func advanceToNext() {
        if index + 1 < mistakes.count {
            index += 1
            loadCurrentMistake()
        } else {
            finished = true
            store.triggerHaptic(.success)
        }
    }
}
