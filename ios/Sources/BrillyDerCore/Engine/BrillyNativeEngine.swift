import Foundation

/// 100% original pure-Swift chess search engine (App Store spotless — zero GPL dependencies).
/// Features: PeSTO-inspired tapered middlegame/endgame evaluation, iterative deepening,
/// Negamax Alpha-Beta + PVS, Quiescence Search with MVV-LVA ordering, Transposition Table,
/// Killer move heuristics, and true MultiPV candidate extraction.
public actor BrillyNativeEngine: ChessEngine {
    public nonisolated let engineName = "BrillyNative Swift Engine"
    public nonisolated let engineLicense = "MIT (BrillyDer Original)"

    private enum Bound: UInt8 {
        case exact = 0
        case lower = 1
        case upper = 2
    }

    private struct TTEntry {
        var key: UInt64 = 0
        var depth: Int8 = -1
        var score: Int32 = 0
        var bound: Bound = .exact
        var bestMove: ChessMove? = nil
    }

    private static let mateScore = 29000
    private static let mateThreshold = 28000
    private static let ttMask = (1 << 17) - 1 // 131,072 entries (~4 MB RAM)
    private static let historyMax = 16_384

    /// Precomputed logarithmic Late Move Reductions table: `lmrTable[depth][moveIndex]`.
    private static let lmrTable: [[Int]] = {
        var table = Array(repeating: Array(repeating: 0, count: 64), count: 32)
        for d in 1..<32 {
            for m in 1..<64 {
                table[d][m] = max(0, Int(0.75 + log(Double(d)) * log(Double(m)) / 2.25))
            }
        }
        return table
    }()

    private var tt: [TTEntry]
    private var killers: [[ChessMove?]]
    private var history: [Int] // [color (0..1) * 4096 + from * 64 + to]
    private var countermoves: [ChessMove?] // [prevFrom * 64 + prevTo]
    private var staticEvalStack: [Int] // [ply] for `improving` flag
    private var pathHashes: [UInt64] = []
    private var nodesVisited: Int = 0
    private var deadline: ContinuousClock.Instant?
    private var enforceDeadline: Bool = false
    private var aborted: Bool = false

    public init() {
        self.tt = Array(repeating: TTEntry(), count: Self.ttMask + 1)
        self.killers = Array(repeating: [nil, nil], count: 64)
        self.history = Array(repeating: 0, count: 2 * 64 * 64)
        self.countermoves = Array(repeating: nil, count: 64 * 64)
        self.staticEvalStack = Array(repeating: 0, count: 64)
    }

    public func clearHash() {
        for i in 0..<tt.count {
            tt[i] = TTEntry()
        }
        for i in 0..<history.count {
            history[i] = 0
        }
        for i in 0..<countermoves.count {
            countermoves[i] = nil
        }
    }

    public func analyze(
        fen: String,
        depth: Int = 5,
        multiPV: Int = 2,
        maxTimeMs: Int? = 320
    ) async throws -> EngineEval {
        let board = try ChessBoard(fen: fen)
        let legal = board.legalMoves()

        // Terminal positions (checkmate / stalemate / draw)
        if legal.isEmpty {
            let inCheck = board.isInCheck()
            let score: EngineScore
            if inCheck {
                score = ChessMath.buildEngineScore(
                    cpWhite: board.turn == .white ? -10000 : 10000,
                    mateWhite: 0,
                    isCheckmate: true,
                    winnerColor: board.turn.opposite
                )
            } else {
                score = ChessMath.buildEngineScore(cpWhite: 0)
            }
            return EngineEval(fen: fen, depth: 0, bestMoveUci: "", pv: [], score: score, lines: [])
        }

        try Task.checkCancellation()
        let clampedDepth = max(1, min(20, depth))
        let requestedPV = max(1, min(multiPV, legal.count))
        let clock = ContinuousClock()
        self.deadline = maxTimeMs.map { clock.now.advanced(by: .milliseconds($0)) }
        self.aborted = false
        self.nodesVisited = 0
        self.killers = Array(repeating: [nil, nil], count: 64)
        // Age history table gently so cross-move knowledge persists without saturating
        for i in 0..<history.count where history[i] != 0 {
            history[i] /= 2
        }
        self.pathHashes = [board.zobristHash]

        var completedDepth = 0
        var bestLines: [MultiPvLine] = []
        var prevRootScore: Int? = nil

        for d in 1...clampedDepth {
            try Task.checkCancellation()
            if d > 1, let dl = deadline, clock.now >= dl { break }
            self.enforceDeadline = (d > 1)
            self.aborted = false

            var excluded: Set<ChessMove> = []
            var depthLines: [(sideScore: Int, line: MultiPvLine)] = []
            var depthFullyCompleted = true

            for pvIdx in 1...requestedPV {
                try Task.checkCancellation()
                let candidates = legal.filter { !excluded.contains($0) }
                if candidates.isEmpty { break }

                let useAspiration = (pvIdx == 1 && d >= 4 && prevRootScore != nil && abs(prevRootScore!) < Self.mateThreshold - 500)
                let aspWindow = useAspiration ? (prevRootScore! - 45, prevRootScore! + 45) : nil
                let (scoreSide, bestMove, pv, completedAnyMove) = searchRoot(
                    board: board,
                    candidates: candidates,
                    depth: d,
                    storeRootTT: (pvIdx == 1),
                    aspiration: aspWindow
                )

                if aborted || !completedAnyMove {
                    depthFullyCompleted = false
                    break
                }
                if pvIdx == 1 {
                    prevRootScore = scoreSide
                }

                let chosenMove = bestMove ?? candidates[0]
                excluded.insert(chosenMove)
                let whiteScore = scoreFromSideToWhite(scoreSide, turn: board.turn)
                let pvUci = pv.isEmpty ? [chosenMove.uci] : pv.map(\.uci)
                depthLines.append((
                    sideScore: scoreSide,
                    line: MultiPvLine(
                        multipv: pvIdx,
                        bestMoveUci: chosenMove.uci,
                        pv: pvUci,
                        score: whiteScore
                    )
                ))
            }

            if !depthLines.isEmpty {
                // Sort lines by side-to-move score descending so PV1 is always genuinely best
                let sorted = depthLines.sorted { $0.sideScore > $1.sideScore }
                let reindexed = sorted.enumerated().map { idx, item in
                    MultiPvLine(
                        multipv: idx + 1,
                        bestMoveUci: item.line.bestMoveUci,
                        pv: item.line.pv,
                        score: item.line.score
                    )
                }

                if depthFullyCompleted {
                    completedDepth = d
                    bestLines = reindexed
                    if let firstMate = reindexed.first?.score.mateWhite,
                       (requestedPV == 1 || d >= 3),
                       abs(firstMate) <= d / 2 + 1 {
                        break
                    }
                } else if bestLines.isEmpty && !reindexed.isEmpty {
                    // Only accept partial depth if no prior completed MultiPV depth exists (guarantees strict lines[0] >= lines[1] ordering)
                    completedDepth = max(completedDepth, d)
                    bestLines = reindexed
                    break
                } else {
                    break
                }
            } else {
                break
            }
        }

        try Task.checkCancellation()
        let top = bestLines.first ?? MultiPvLine(
            multipv: 1,
            bestMoveUci: legal[0].uci,
            pv: [legal[0].uci],
            score: ChessMath.buildEngineScore(cpWhite: 0)
        )

        return EngineEval(
            fen: fen,
            depth: max(1, completedDepth),
            bestMoveUci: top.bestMoveUci,
            pv: top.pv,
            score: top.score,
            lines: bestLines.isEmpty ? [top] : bestLines
        )
    }

    // MARK: - Search Core

    private func searchRoot(
        board: ChessBoard,
        candidates: [ChessMove],
        depth: Int,
        storeRootTT: Bool,
        aspiration: (Int, Int)? = nil
    ) -> (score: Int, bestMove: ChessMove?, pv: [ChessMove], completedAnyMove: Bool) {
        let ttSlot = Int(board.zobristHash & UInt64(Self.ttMask))
        let ttMove = (storeRootTT && tt[ttSlot].key == board.zobristHash) ? tt[ttSlot].bestMove : nil
        let ordered = orderMoves(candidates, board: board, ttMove: ttMove, ply: 0)

        var alpha = aspiration?.0 ?? (-Self.mateScore - 100)
        var beta = aspiration?.1 ?? (Self.mateScore + 100)
        var delta = 45

        while true {
            var localAlpha = alpha
            var bestScore = -Self.mateScore - 100
            var bestMove: ChessMove? = ordered.first
            var bestPV: [ChessMove] = []
            var completedAny = false

            for (index, move) in ordered.enumerated() {
                var next = board
                next.makeMoveUnchecked(move)
                pathHashes.append(next.zobristHash)

                var childPV: [ChessMove] = []
                let score: Int
                let prevKey = move.from.rawValue * 64 + move.to.rawValue
                if index == 0 {
                    score = -negamax(board: next, depth: depth - 1, alpha: -beta, beta: -localAlpha, ply: 1, allowNull: true, prevMoveKey: prevKey, pv: &childPV)
                } else {
                    var zeroPV: [ChessMove] = []
                    let probe = -negamax(board: next, depth: depth - 1, alpha: -localAlpha - 1, beta: -localAlpha, ply: 1, allowNull: true, prevMoveKey: prevKey, pv: &zeroPV)
                    if probe > localAlpha && !aborted {
                        score = -negamax(board: next, depth: depth - 1, alpha: -beta, beta: -localAlpha, ply: 1, allowNull: true, prevMoveKey: prevKey, pv: &childPV)
                    } else {
                        score = probe
                        childPV = zeroPV
                    }
                }

                pathHashes.removeLast()
                if aborted { break }
                completedAny = true

                if score > bestScore {
                    bestScore = score
                    bestMove = move
                    bestPV = [move] + childPV
                }
                if score > localAlpha {
                    localAlpha = score
                }
                if localAlpha >= beta {
                    break
                }
            }

            if aborted || !completedAny {
                return (bestScore, bestMove, bestPV, completedAny)
            }

            if aspiration != nil {
                if bestScore <= alpha && alpha > -Self.mateScore - 100 {
                    delta = min(Self.mateScore, delta * 3)
                    alpha = max(-Self.mateScore - 100, alpha - delta)
                    continue
                }
                if bestScore >= beta && beta < Self.mateScore + 100 {
                    delta = min(Self.mateScore, delta * 3)
                    beta = min(Self.mateScore + 100, beta + delta)
                    continue
                }
            }

            if storeRootTT, let bm = bestMove {
                storeTT(key: board.zobristHash, depth: depth, score: bestScore, bound: .exact, bestMove: bm)
            }
            return (bestScore, bestMove, bestPV, completedAny)
        }
    }

    private func negamax(
        board: ChessBoard,
        depth: Int,
        alpha origAlpha: Int,
        beta: Int,
        ply: Int,
        allowNull: Bool,
        prevMoveKey: Int,
        pv: inout [ChessMove]
    ) -> Int {
        nodesVisited += 1
        if (nodesVisited & 1023) == 0 {
            if Task.isCancelled {
                aborted = true
                return 0
            }
            if enforceDeadline, let dl = deadline, ContinuousClock().now >= dl {
                aborted = true
                return 0
            }
        }

        if board.halfmoveClock >= 100 || board.isInsufficientMaterial {
            return 0
        }

        // Repetition check against current search path (avoid repeating when winning / spot perpetual check!)
        if ply > 0 && pathHashes.count >= 3 {
            let hash = board.zobristHash
            for i in stride(from: pathHashes.count - 3, through: 0, by: -2) {
                if pathHashes[i] == hash {
                    return 0
                }
            }
        }

        let inCheck = board.isInCheck()
        var effectiveDepth = (inCheck && ply < 18) ? depth + 1 : depth
        let isPVNode = (beta - origAlpha) > 1

        var alpha = origAlpha
        let ttIndex = Int(board.zobristHash & UInt64(Self.ttMask))
        let entry = tt[ttIndex]
        var ttMove: ChessMove? = nil
        if entry.key == board.zobristHash {
            ttMove = entry.bestMove
            // Skip TT cutoffs on PV nodes so full PV lines never get truncated
            if !isPVNode && Int(entry.depth) >= effectiveDepth && ply > 0 {
                let s = adjustMateScoreFromTT(Int(entry.score), ply: ply)
                switch entry.bound {
                case .exact: return s
                case .lower:
                    if s >= beta { return s }
                    alpha = max(alpha, s)
                case .upper:
                    if s <= alpha { return s }
                }
            }
        }

        if effectiveDepth <= 0 {
            // Guard horizon stalemates (!inCheck with 0 legal moves) so K+Q vs K stalemates score 0 instead of standPat!
            if !inCheck && !board.hasAnyLegalMove() {
                return 0
            }
            return quiescence(board: board, alpha: alpha, beta: beta, ply: ply)
        }

        // Internal Iterative Reduction (IIR): if no TT move at deeper nodes, reduce by 1 ply to find a good move faster
        if ttMove == nil && effectiveDepth >= 4 && !inCheck {
            effectiveDepth -= 1
        }

        // Static eval + Improving flag for RFP, Razoring, NMP, Futility & LMP
        var staticEval: Int? = nil
        var improving = false
        if !inCheck {
            let ev = evaluate(board)
            staticEval = ev
            if ply < 64 {
                staticEvalStack[ply] = ev
                if ply >= 2 {
                    improving = ev > staticEvalStack[ply - 2]
                }
            }

            if !isPVNode && abs(beta) < Self.mateThreshold && abs(origAlpha) < Self.mateThreshold {
                // Reverse Futility Pruning (Static Null Move Pruning) — tighter when improving
                let rfpMargin = (improving ? 90 : 120) * effectiveDepth
                if effectiveDepth <= 4 && ev - rfpMargin >= beta {
                    return ev
                }

                // Razoring: if far below alpha at shallow depth, verify via quiescence
                if effectiveDepth <= 2 && ev + 260 * effectiveDepth < alpha {
                    let qScore = quiescence(board: board, alpha: alpha, beta: alpha + 1, ply: ply)
                    if aborted { return 0 }
                    if qScore <= alpha {
                        return qScore
                    }
                }

                // Dynamic Null-Move Pruning (NMP) — huge branching-factor reduction when side has non-pawn material
                if allowNull && effectiveDepth >= 3 && ev >= beta && board.hasNonPawnMaterial(for: board.turn) {
                    var nullBoard = board
                    nullBoard.makeNullMove()
                    let R = 2 + effectiveDepth / 4 + min(2, max(0, (ev - beta) / 220))
                    var nullPV: [ChessMove] = []
                    let nullScore = -negamax(
                        board: nullBoard,
                        depth: max(0, effectiveDepth - 1 - R),
                        alpha: -beta,
                        beta: -beta + 1,
                        ply: ply + 1,
                        allowNull: false,
                        prevMoveKey: -1,
                        pv: &nullPV
                    )
                    if aborted { return 0 }
                    if nullScore >= beta && nullScore < Self.mateThreshold {
                        return beta
                    }
                }
            }
        }

        var moves = board.legalMoves()
        if moves.isEmpty {
            return inCheck ? (-Self.mateScore + ply) : 0
        }

        let cm = (prevMoveKey >= 0 && prevMoveKey < 4096) ? countermoves[prevMoveKey] : nil
        var scores = scoreMoves(moves, board: board, ttMove: ttMove, countermove: cm, ply: ply)
        var bestScore = -Self.mateScore - 100
        var bestMove: ChessMove? = nil
        let colorIdx = board.turn == .white ? 0 : 1
        var quietCount = 0
        var triedQuiets: [ChessMove] = []
        triedQuiets.reserveCapacity(16)

        for index in 0..<moves.count {
            let move = pickNextMove(at: index, moves: &moves, scores: &scores)
            let isEp = board[move.from]?.type == .pawn && move.to == board.enPassantSquare
            let isCapture = board[move.to] != nil || isEp
            let isTactical = isCapture || move.promotion != nil

            var next = board
            next.makeMoveUnchecked(move)
            let givesCheck = next.isInCheck()

            // Futility Pruning & Late Move Pruning (LMP) — single board copy (no duplicate checkProbe!)
            if !isPVNode && !inCheck && !isTactical && !givesCheck && index > 0 {
                if effectiveDepth <= 2, let ev = staticEval, ev + 135 * effectiveDepth <= alpha {
                    quietCount += 1
                    continue
                }
                if effectiveDepth <= 3 {
                    let lmpLimit = improving ? (4 + effectiveDepth * effectiveDepth) : ((4 + effectiveDepth * effectiveDepth) / 2 + 1)
                    if quietCount >= lmpLimit {
                        continue
                    }
                }
            }

            if !isTactical {
                quietCount += 1
                triedQuiets.append(move)
            }

            pathHashes.append(next.zobristHash)

            var childPV: [ChessMove] = []
            let nextPrevKey = move.from.rawValue * 64 + move.to.rawValue
            let score: Int
            if index == 0 {
                score = -negamax(board: next, depth: effectiveDepth - 1, alpha: -beta, beta: -alpha, ply: ply + 1, allowNull: true, prevMoveKey: nextPrevKey, pv: &childPV)
            } else {
                // Logarithmic Late Move Reductions (LMR) modulated by improving/PV/history
                var reduction = 0
                if effectiveDepth >= 3 && index >= 3 && !inCheck && !isTactical && !givesCheck {
                    let dIdx = min(31, effectiveDepth)
                    let mIdx = min(63, index)
                    reduction = Self.lmrTable[dIdx][mIdx]
                    if isPVNode { reduction = max(0, reduction - 1) }
                    if !improving { reduction += 1 }
                    let hScore = history[colorIdx * 4096 + move.from.rawValue * 64 + move.to.rawValue]
                    if hScore > 4000 { reduction = max(0, reduction - 1) }
                    else if hScore < -4000 { reduction += 1 }
                    reduction = min(effectiveDepth - 2, max(0, reduction))
                }

                var zeroPV: [ChessMove] = []
                let reducedDepth = max(0, effectiveDepth - 1 - reduction)
                var probe = -negamax(board: next, depth: reducedDepth, alpha: -alpha - 1, beta: -alpha, ply: ply + 1, allowNull: true, prevMoveKey: nextPrevKey, pv: &zeroPV)

                // If reduced search beat alpha, re-search at full depth zero-window
                if reduction > 0 && probe > alpha && !aborted {
                    zeroPV.removeAll(keepingCapacity: true)
                    probe = -negamax(board: next, depth: effectiveDepth - 1, alpha: -alpha - 1, beta: -alpha, ply: ply + 1, allowNull: true, prevMoveKey: nextPrevKey, pv: &zeroPV)
                }

                // If zero-window beat alpha inside PV window, re-search full window
                if probe > alpha && probe < beta && !aborted {
                    score = -negamax(board: next, depth: effectiveDepth - 1, alpha: -beta, beta: -alpha, ply: ply + 1, allowNull: true, prevMoveKey: nextPrevKey, pv: &childPV)
                } else {
                    score = probe
                    childPV = zeroPV
                }
            }

            pathHashes.removeLast()
            if aborted { return 0 }

            if score > bestScore {
                bestScore = score
                bestMove = move
            }
            if score > alpha {
                alpha = score
                if isPVNode {
                    pv = [move] + childPV
                }
            }
            if alpha >= beta {
                if !isTactical && ply < 64 {
                    if killers[ply][0] != move {
                        killers[ply][1] = killers[ply][0]
                        killers[ply][0] = move
                    }
                    if prevMoveKey >= 0 && prevMoveKey < 4096 {
                        countermoves[prevMoveKey] = move
                    }
                    let bonus = min(2000, effectiveDepth * effectiveDepth * 16)
                    updateHistory(colorIdx: colorIdx, move: move, delta: bonus)
                    // History malus for previously tried quiet moves that failed to cause a cutoff
                    for prevQuiet in triedQuiets where prevQuiet != move {
                        updateHistory(colorIdx: colorIdx, move: prevQuiet, delta: -bonus / 2)
                    }
                }
                break
            }
        }

        let bound: Bound
        if bestScore <= origAlpha { bound = .upper }
        else if bestScore >= beta { bound = .lower }
        else { bound = .exact }
        // Store unextended `depth` in TT to prevent check-extension depth inflation
        storeTT(
            key: board.zobristHash,
            depth: depth,
            score: adjustMateScoreForTT(bestScore, ply: ply),
            bound: bound,
            bestMove: bestMove
        )
        return bestScore
    }

    @inline(__always)
    private func updateHistory(colorIdx: Int, move: ChessMove, delta: Int) {
        let hIdx = colorIdx * 4096 + move.from.rawValue * 64 + move.to.rawValue
        let cur = history[hIdx]
        // Gravity clamping keeps history values cleanly bounded in [-historyMax, +historyMax]
        history[hIdx] = cur + delta - (cur * abs(delta)) / Self.historyMax
    }

    private func quiescence(board: ChessBoard, alpha origAlpha: Int, beta: Int, ply: Int) -> Int {
        nodesVisited += 1
        if (nodesVisited & 1023) == 0 {
            if Task.isCancelled {
                aborted = true
                return 0
            }
            if enforceDeadline, let dl = deadline, ContinuousClock().now >= dl {
                aborted = true
                return 0
            }
        }

        var alpha = origAlpha
        let inCheck = board.isInCheck()

        // TT probe in Quiescence Search (depth 0) — cuts 20–35% of tactical capture tree nodes
        let ttIndex = Int(board.zobristHash & UInt64(Self.ttMask))
        let ttEntry = tt[ttIndex]
        if ttEntry.key == board.zobristHash && ttEntry.depth >= 0 {
            let s = adjustMateScoreFromTT(Int(ttEntry.score), ply: ply)
            switch ttEntry.bound {
            case .exact: return s
            case .lower:
                if s >= beta { return s }
            case .upper:
                if s <= alpha { return s }
            }
        }

        if inCheck {
            // Never stand pat while in check; search all legal evasions & detect checkmate
            var evasions = board.legalMoves()
            if evasions.isEmpty {
                return -Self.mateScore + ply
            }
            if ply >= 24 { return evaluate(board) }
            var scores = scoreMoves(evasions, board: board, ttMove: ttEntry.key == board.zobristHash ? ttEntry.bestMove : nil, countermove: nil, ply: min(ply, 63))
            var bestScore = -Self.mateScore - 100
            var bestMove: ChessMove? = nil
            for i in 0..<evasions.count {
                let move = pickNextMove(at: i, moves: &evasions, scores: &scores)
                var next = board
                next.makeMoveUnchecked(move)
                let score = -quiescence(board: next, alpha: -beta, beta: -alpha, ply: ply + 1)
                if aborted { return 0 }
                if score > bestScore {
                    bestScore = score
                    bestMove = move
                }
                if score >= beta {
                    storeTT(key: board.zobristHash, depth: 0, score: adjustMateScoreForTT(score, ply: ply), bound: .lower, bestMove: move)
                    return beta
                }
                if score > alpha { alpha = score }
            }
            storeTT(
                key: board.zobristHash,
                depth: 0,
                score: adjustMateScoreForTT(bestScore, ply: ply),
                bound: bestScore > origAlpha ? .exact : .upper,
                bestMove: bestMove
            )
            return alpha
        }

        let standPat = evaluate(board)
        if standPat >= beta { return beta }
        if standPat > alpha { alpha = standPat }
        if ply >= 24 { return standPat }

        var captures = board.legalMoves(capturesOnly: true)
        if captures.isEmpty { return standPat }

        var capScores: [Int] = []
        capScores.reserveCapacity(captures.count)
        for m in captures {
            capScores.append(captureScore(m, on: board))
        }

        var bestScore = standPat
        var bestMove: ChessMove? = nil
        for i in 0..<captures.count {
            let move = pickNextMove(at: i, moves: &captures, scores: &capScores)
            if move.promotion == nil, let victim = board[move.to] {
                // Delta pruning
                if standPat + victim.type.centipawnValue + 200 < alpha {
                    continue
                }
                // Static Exchange Evaluation (SEE) pruning: skip losing captures (e.g. QxP defended by pawn)
                if quickSEE(move, on: board) < 0 {
                    continue
                }
            }
            var next = board
            next.makeMoveUnchecked(move)
            let score = -quiescence(board: next, alpha: -beta, beta: -alpha, ply: ply + 1)
            if aborted { return 0 }
            if score > bestScore {
                bestScore = score
                bestMove = move
            }
            if score >= beta {
                storeTT(key: board.zobristHash, depth: 0, score: adjustMateScoreForTT(score, ply: ply), bound: .lower, bestMove: move)
                return beta
            }
            if score > alpha { alpha = score }
        }
        storeTT(
            key: board.zobristHash,
            depth: 0,
            score: adjustMateScoreForTT(bestScore, ply: ply),
            bound: bestScore > origAlpha ? .exact : .upper,
            bestMove: bestMove
        )
        return alpha
    }

    // MARK: - Incremental Selection Sort Move Ordering, SEE & TT Helpers

    private func orderMoves(_ moves: [ChessMove], board: ChessBoard, ttMove: ChessMove?, ply: Int) -> [ChessMove] {
        var list = moves
        var scores = scoreMoves(list, board: board, ttMove: ttMove, countermove: nil, ply: ply)
        for i in 0..<list.count {
            _ = pickNextMove(at: i, moves: &list, scores: &scores)
        }
        return list
    }

    private func scoreMoves(_ moves: [ChessMove], board: ChessBoard, ttMove: ChessMove?, countermove: ChessMove?, ply: Int) -> [Int] {
        let k0 = ply < 64 ? killers[ply][0] : nil
        let k1 = ply < 64 ? killers[ply][1] : nil
        let colorIdx = board.turn == .white ? 0 : 1
        var scores: [Int] = []
        scores.reserveCapacity(moves.count)
        for m in moves {
            scores.append(movePriority(m, board: board, ttMove: ttMove, k0: k0, k1: k1, countermove: countermove, colorIdx: colorIdx))
        }
        return scores
    }

    /// In-place incremental selection sort: picks the highest-scored remaining move in O(n),
    /// avoiding full O(n log n) sort when beta cutoffs happen on moves 1–3.
    @inline(__always)
    private func pickNextMove(at index: Int, moves: inout [ChessMove], scores: inout [Int]) -> ChessMove {
        var bestIdx = index
        var bestScore = scores[index]
        var j = index + 1
        let count = moves.count
        while j < count {
            if scores[j] > bestScore {
                bestScore = scores[j]
                bestIdx = j
            }
            j += 1
        }
        if bestIdx != index {
            moves.swapAt(index, bestIdx)
            scores.swapAt(index, bestIdx)
        }
        return moves[index]
    }

    /// Fast Static Exchange Evaluation approximation: returns >= 0 for winning/equal captures, < 0 for losing captures.
    @inline(__always)
    private func quickSEE(_ move: ChessMove, on board: ChessBoard) -> Int {
        guard let attacker = board[move.from] else { return 0 }
        let victimVal = board[move.to]?.type.centipawnValue ?? (move.to == board.enPassantSquare ? 100 : 0)
        let promoBonus = (move.promotion?.centipawnValue ?? 0) - (move.promotion != nil ? 100 : 0)
        let attackerVal = attacker.type.centipawnValue
        // Capturing an equal or more valuable piece (or promoting) is immediately non-losing
        if victimVal + promoBonus >= attackerVal {
            return victimVal + promoBonus - attackerVal
        }
        // If destination is NOT defended by opponent, it's a clean free capture
        if !board.isSquareAttacked(move.to, by: attacker.color.opposite) {
            return victimVal + promoBonus
        }
        // Destination IS defended and attacker is strictly more valuable than victim (e.g. QxP, RxP, NxP) -> losing exchange
        return victimVal + promoBonus - attackerVal
    }

    @inline(__always)
    private func movePriority(
        _ move: ChessMove,
        board: ChessBoard,
        ttMove: ChessMove?,
        k0: ChessMove?,
        k1: ChessMove?,
        countermove: ChessMove?,
        colorIdx: Int
    ) -> Int {
        if move == ttMove { return 1_000_000 }
        var score = 0
        let isEp = board[move.from]?.type == .pawn && move.to == board.enPassantSquare
        if board[move.to] != nil || isEp {
            let see = quickSEE(move, on: board)
            if see >= 0 {
                score += 100_000 + captureScore(move, on: board)
            } else {
                // Order losing captures below killers and good quiet moves
                score += -50_000 + see
            }
        }
        if let promo = move.promotion {
            score += 90_000 + promo.centipawnValue
        }
        if score == 0 {
            if move == k0 { score += 50_000 }
            else if move == k1 { score += 45_000 }
            else if move == countermove { score += 40_000 }
            else {
                score += history[colorIdx * 4096 + move.from.rawValue * 64 + move.to.rawValue]
            }
        }
        let cf = abs(move.to.file - 3) + abs(move.to.rank - 3)
        score += (8 - cf)
        return score
    }

    @inline(__always)
    private func captureScore(_ move: ChessMove, on board: ChessBoard) -> Int {
        let victim = board[move.to]?.type.centipawnValue ?? 100
        let attacker = board[move.from]?.type.centipawnValue ?? 100
        let promo = move.promotion?.centipawnValue ?? 0
        return victim * 10 - attacker + promo
    }

    private func storeTT(key: UInt64, depth: Int, score: Int, bound: Bound, bestMove: ChessMove?) {
        let idx = Int(key & UInt64(Self.ttMask))
        let existing = tt[idx]
        if existing.key != key || Int(existing.depth) <= depth {
            let fallbackMove = existing.key == key ? existing.bestMove : nil
            tt[idx] = TTEntry(
                key: key,
                depth: Int8(clamping: depth),
                score: Int32(clamping: score),
                bound: bound,
                bestMove: bestMove ?? fallbackMove
            )
        }
    }

    private func adjustMateScoreForTT(_ score: Int, ply: Int) -> Int {
        if score > Self.mateThreshold { return score + ply }
        if score < -Self.mateThreshold { return score - ply }
        return score
    }

    private func adjustMateScoreFromTT(_ score: Int, ply: Int) -> Int {
        if score > Self.mateThreshold { return score - ply }
        if score < -Self.mateThreshold { return score + ply }
        return score
    }

    private func scoreFromSideToWhite(_ sideScore: Int, turn: PieceColor) -> EngineScore {
        let whiteScore = turn == .white ? sideScore : -sideScore
        if abs(whiteScore) >= Self.mateThreshold {
            let pliesToMate = max(1, Self.mateScore - abs(whiteScore))
            let movesToMate = max(1, (pliesToMate + 1) / 2)
            let signedMate = whiteScore > 0 ? movesToMate : -movesToMate
            return ChessMath.buildEngineScore(cpWhite: whiteScore, mateWhite: signedMate)
        }
        return ChessMath.buildEngineScore(cpWhite: whiteScore)
    }

    // MARK: - PeSTO-Inspired Tapered Evaluation + Pawn Structure, Rooks, King Shield & Mop-Up

    private static let passedPawnMg: [Int] = [0, 5, 10, 20, 38, 68, 105, 0]
    private static let passedPawnEg: [Int] = [0, 12, 22, 40, 72, 118, 175, 0]

    private nonisolated func evaluate(_ board: ChessBoard) -> Int {
        var mgWhite = 0
        var egWhite = 0
        var mgBlack = 0
        var egBlack = 0
        var phase = 0
        var whiteBishops = 0
        var blackBishops = 0

        // Per-file pawn bitmasks & counts (zero heap allocation using fixed 8-bit masks)
        var wPawnCount0 = 0, wPawnCount1 = 0, wPawnCount2 = 0, wPawnCount3 = 0
        var wPawnCount4 = 0, wPawnCount5 = 0, wPawnCount6 = 0, wPawnCount7 = 0
        var bPawnCount0 = 0, bPawnCount1 = 0, bPawnCount2 = 0, bPawnCount3 = 0
        var bPawnCount4 = 0, bPawnCount5 = 0, bPawnCount6 = 0, bPawnCount7 = 0
        var wMinRank: UInt64 = 0x0707_0707_0707_0707 // packed: file f -> byte f stores lowest white pawn rank (0..7)
        var bMaxRank: UInt64 = 0 // packed: file f -> byte f stores highest black pawn rank (0..7)
        var whiteRooks: UInt64 = 0
        var blackRooks: UInt64 = 0
        var whiteKnights: UInt64 = 0
        var blackKnights: UInt64 = 0
        var whiteBishopsBB: UInt64 = 0
        var blackBishopsBB: UInt64 = 0
        var whiteQueens: UInt64 = 0
        var blackQueens: UInt64 = 0
        var whitePawns: UInt64 = 0
        var blackPawns: UInt64 = 0
        var whiteOcc: UInt64 = 0
        var blackOcc: UInt64 = 0
        var whiteBishopLight = false
        var blackBishopLight = false
        var majorCount = 0

        for idx in 0..<64 {
            guard let p = board.squares[idx] else { continue }
            let rank = idx >> 3
            let file = idx & 7
            let bit: UInt64 = 1 &<< idx
            if p.color == .white { whiteOcc |= bit } else { blackOcc |= bit }
            // Table index: 0 = a8 (top-left from White's perspective), 63 = h1
            let pstIdx = p.color == .white ? ((7 - rank) * 8 + file) : (rank * 8 + file)

            let mg: Int
            let eg: Int
            switch p.type {
            case .pawn:
                mg = 82 + Self.mgPawn[pstIdx]
                eg = 94 + Self.egPawn[pstIdx]
                if p.color == .white {
                    whitePawns |= bit
                    switch file {
                    case 0: wPawnCount0 += 1
                    case 1: wPawnCount1 += 1
                    case 2: wPawnCount2 += 1
                    case 3: wPawnCount3 += 1
                    case 4: wPawnCount4 += 1
                    case 5: wPawnCount5 += 1
                    case 6: wPawnCount6 += 1
                    default: wPawnCount7 += 1
                    }
                    let shift = file * 8
                    let cur = Int((wMinRank >> shift) & 0xFF)
                    if rank < cur {
                        wMinRank = (wMinRank & ~(UInt64(0xFF) << shift)) | (UInt64(rank) << shift)
                    }
                } else {
                    blackPawns |= bit
                    switch file {
                    case 0: bPawnCount0 += 1
                    case 1: bPawnCount1 += 1
                    case 2: bPawnCount2 += 1
                    case 3: bPawnCount3 += 1
                    case 4: bPawnCount4 += 1
                    case 5: bPawnCount5 += 1
                    case 6: bPawnCount6 += 1
                    default: bPawnCount7 += 1
                    }
                    let shift = file * 8
                    let cur = Int((bMaxRank >> shift) & 0xFF)
                    if rank > cur {
                        bMaxRank = (bMaxRank & ~(UInt64(0xFF) << shift)) | (UInt64(rank) << shift)
                    }
                }
            case .knight:
                mg = 337 + Self.mgKnight[pstIdx]
                eg = 281 + Self.egKnight[pstIdx]
                phase += 1
                if p.color == .white { whiteKnights |= bit } else { blackKnights |= bit }
            case .bishop:
                mg = 365 + Self.mgBishop[pstIdx]
                eg = 297 + Self.egBishop[pstIdx]
                phase += 1
                let isLight = ((rank + file) & 1) == 1
                if p.color == .white {
                    whiteBishops += 1
                    whiteBishopsBB |= bit
                    whiteBishopLight = isLight
                } else {
                    blackBishops += 1
                    blackBishopsBB |= bit
                    blackBishopLight = isLight
                }
            case .rook:
                mg = 477 + Self.mgRook[pstIdx]
                eg = 512 + Self.egRook[pstIdx]
                phase += 2
                majorCount += 1
                if p.color == .white {
                    whiteRooks |= bit
                    if rank == 6 { mgWhite += 20; egWhite += 28 } // Rook on 7th rank
                } else {
                    blackRooks |= bit
                    if rank == 1 { mgBlack += 20; egBlack += 28 } // Rook on 2nd rank
                }
            case .queen:
                mg = 1025 + Self.mgQueen[pstIdx]
                eg = 936 + Self.egQueen[pstIdx]
                phase += 4
                majorCount += 1
                if p.color == .white { whiteQueens |= bit } else { blackQueens |= bit }
            case .king:
                mg = Self.mgKing[pstIdx]
                eg = Self.egKing[pstIdx]
            }

            if p.color == .white {
                mgWhite += mg
                egWhite += eg
            } else {
                mgBlack += mg
                egBlack += eg
            }
        }

        // Bishop pair bonus
        if whiteBishops >= 2 { mgWhite += 32; egWhite += 50 }
        if blackBishops >= 2 { mgBlack += 32; egBlack += 50 }

        // Helper closures for per-file pawn counts (zero allocation)
        @inline(__always) func wCount(_ f: Int) -> Int {
            switch f {
            case 0: return wPawnCount0
            case 1: return wPawnCount1
            case 2: return wPawnCount2
            case 3: return wPawnCount3
            case 4: return wPawnCount4
            case 5: return wPawnCount5
            case 6: return wPawnCount6
            case 7: return wPawnCount7
            default: return 0
            }
        }
        @inline(__always) func bCount(_ f: Int) -> Int {
            switch f {
            case 0: return bPawnCount0
            case 1: return bPawnCount1
            case 2: return bPawnCount2
            case 3: return bPawnCount3
            case 4: return bPawnCount4
            case 5: return bPawnCount5
            case 6: return bPawnCount6
            case 7: return bPawnCount7
            default: return 0
            }
        }

        // Pawn structure: doubled & isolated pawns
        for f in 0..<8 {
            let wc = wCount(f)
            if wc > 1 { mgWhite -= (wc - 1) * 12; egWhite -= (wc - 1) * 16 }
            if wc > 0 && wCount(f - 1) == 0 && wCount(f + 1) == 0 {
                mgWhite -= 12; egWhite -= 14
            }
            let bc = bCount(f)
            if bc > 1 { mgBlack -= (bc - 1) * 12; egBlack -= (bc - 1) * 16 }
            if bc > 0 && bCount(f - 1) == 0 && bCount(f + 1) == 0 {
                mgBlack -= 12; egBlack -= 14
            }
        }

        // Pawn attack masks (used for protected passers, knight outposts & safe mobility)
        let notAFile: UInt64 = 0xfefe_fefe_fefe_fefe
        let notHFile: UInt64 = 0x7f7f_7f7f_7f7f_7f7f
        let wPawnAttacks: UInt64 = ((whitePawns & notAFile) << 7) | ((whitePawns & notHFile) << 9)
        let bPawnAttacks: UInt64 = ((blackPawns & notHFile) >> 7) | ((blackPawns & notAFile) >> 9)
        let allOcc: UInt64 = whiteOcc | blackOcc

        // Passed pawns (with protected & connected bonuses)
        var wp = whitePawns
        while wp != 0 {
            let sq = wp.trailingZeroBitCount
            wp &= wp - 1
            let r = sq >> 3
            let f = sq & 7
            var blocked = false
            for df in max(0, f - 1)...min(7, f + 1) {
                if bCount(df) > 0 {
                    let maxBR = Int((bMaxRank >> (df * 8)) & 0xFF)
                    if maxBR > r { blocked = true; break }
                }
            }
            if !blocked {
                let bit: UInt64 = 1 &<< sq
                mgWhite += Self.passedPawnMg[r]
                egWhite += Self.passedPawnEg[r]
                if (wPawnAttacks & bit) != 0 { mgWhite += 10; egWhite += 18 } // Protected passer
                let adjSameRank: UInt64 = ((bit & notAFile) >> 1) | ((bit & notHFile) << 1)
                if (whitePawns & adjSameRank) != 0 { mgWhite += 8; egWhite += 14 } // Connected passer
            }
        }

        var bp = blackPawns
        while bp != 0 {
            let sq = bp.trailingZeroBitCount
            bp &= bp - 1
            let r = sq >> 3
            let f = sq & 7
            var blocked = false
            for df in max(0, f - 1)...min(7, f + 1) {
                if wCount(df) > 0 {
                    let minWR = Int((wMinRank >> (df * 8)) & 0xFF)
                    if minWR < r { blocked = true; break }
                }
            }
            if !blocked {
                let bit: UInt64 = 1 &<< sq
                let relRank = 7 - r
                mgBlack += Self.passedPawnMg[relRank]
                egBlack += Self.passedPawnEg[relRank]
                if (bPawnAttacks & bit) != 0 { mgBlack += 10; egBlack += 18 }
                let adjSameRank: UInt64 = ((bit & notAFile) >> 1) | ((bit & notHFile) << 1)
                if (blackPawns & adjSameRank) != 0 { mgBlack += 8; egBlack += 14 }
            }
        }

        // Knight outposts (ranks 4..6 for White, 3..5 for Black, supported by pawn, no enemy pawn on adjacent files ahead)
        var wn = whiteKnights
        while wn != 0 {
            let sq = wn.trailingZeroBitCount
            wn &= wn - 1
            let r = sq >> 3
            let f = sq & 7
            let bit: UInt64 = 1 &<< sq
            if r >= 3 && r <= 5 && (wPawnAttacks & bit) != 0 {
                var canBeChased = false
                if f > 0 && bCount(f - 1) > 0 && Int((bMaxRank >> ((f - 1) * 8)) & 0xFF) > r { canBeChased = true }
                if f < 7 && bCount(f + 1) > 0 && Int((bMaxRank >> ((f + 1) * 8)) & 0xFF) > r { canBeChased = true }
                if !canBeChased { mgWhite += 24; egWhite += 14 }
            }
        }
        var bn = blackKnights
        while bn != 0 {
            let sq = bn.trailingZeroBitCount
            bn &= bn - 1
            let r = sq >> 3
            let f = sq & 7
            let bit: UInt64 = 1 &<< sq
            if r >= 2 && r <= 4 && (bPawnAttacks & bit) != 0 {
                var canBeChased = false
                if f > 0 && wCount(f - 1) > 0 && Int((wMinRank >> ((f - 1) * 8)) & 0xFF) < r { canBeChased = true }
                if f < 7 && wCount(f + 1) > 0 && Int((wMinRank >> ((f + 1) * 8)) & 0xFF) < r { canBeChased = true }
                if !canBeChased { mgBlack += 24; egBlack += 14 }
            }
        }

        // Rook open / semi-open file bonuses
        var wr = whiteRooks
        while wr != 0 {
            let sq = wr.trailingZeroBitCount
            wr &= wr - 1
            let f = sq & 7
            if wCount(f) == 0 {
                if bCount(f) == 0 { mgWhite += 22; egWhite += 12 }
                else { mgWhite += 12; egWhite += 6 }
            }
        }
        var br = blackRooks
        while br != 0 {
            let sq = br.trailingZeroBitCount
            br &= br - 1
            let f = sq & 7
            if bCount(f) == 0 {
                if wCount(f) == 0 { mgBlack += 22; egBlack += 12 }
                else { mgBlack += 12; egBlack += 6 }
            }
        }

        // Piece Mobility + King Zone Attack Safety (zero-alloc bitboard rays)
        let wk = board.whiteKingSquare
        let bk = board.blackKingSquare
        let wKingZone = Self.kingZoneMask(wk)
        let bKingZone = Self.kingZoneMask(bk)
        var wAttackUnits = 0
        var wAttackers = 0
        var bAttackUnits = 0
        var bAttackers = 0

        // Helper for sliding ray mobility + king zone hits
        @inline(__always) func evalSlider(
            _ bb: UInt64,
            friendly: UInt64,
            enemyPawnAtt: UInt64,
            enemyKingZone: UInt64,
            isDiag: Bool,
            mgPerSq: Int,
            egPerSq: Int,
            baseline: Int,
            attackWeight: Int,
            mg: inout Int,
            eg: inout Int,
            atkUnits: inout Int,
            atkCount: inout Int
        ) {
            var pieces = bb
            while pieces != 0 {
                let sq = pieces.trailingZeroBitCount
                pieces &= pieces - 1
                let f = sq & 7
                let r = sq >> 3
                var mob = 0
                var hitZone = false
                let dirs: [(Int, Int)] = isDiag ? [(1, 1), (1, -1), (-1, 1), (-1, -1)] : [(1, 0), (-1, 0), (0, 1), (0, -1)]
                for (df, dr) in dirs {
                    var nf = f + df
                    var nr = r + dr
                    while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                        let bit: UInt64 = 1 &<< (nr * 8 + nf)
                        if (friendly & bit) != 0 { break }
                        if (enemyPawnAtt & bit) == 0 { mob += 1 }
                        if (enemyKingZone & bit) != 0 { hitZone = true }
                        if (allOcc & bit) != 0 { break }
                        nf += df
                        nr += dr
                    }
                }
                mg += (mob - baseline) * mgPerSq
                eg += (mob - baseline) * egPerSq
                if hitZone {
                    atkCount += 1
                    atkUnits += attackWeight
                }
            }
        }

        evalSlider(whiteBishopsBB, friendly: whiteOcc, enemyPawnAtt: bPawnAttacks, enemyKingZone: bKingZone, isDiag: true, mgPerSq: 4, egPerSq: 4, baseline: 6, attackWeight: 2, mg: &mgWhite, eg: &egWhite, atkUnits: &wAttackUnits, atkCount: &wAttackers)
        evalSlider(blackBishopsBB, friendly: blackOcc, enemyPawnAtt: wPawnAttacks, enemyKingZone: wKingZone, isDiag: true, mgPerSq: 4, egPerSq: 4, baseline: 6, attackWeight: 2, mg: &mgBlack, eg: &egBlack, atkUnits: &bAttackUnits, atkCount: &bAttackers)
        evalSlider(whiteRooks, friendly: whiteOcc, enemyPawnAtt: bPawnAttacks, enemyKingZone: bKingZone, isDiag: false, mgPerSq: 2, egPerSq: 4, baseline: 7, attackWeight: 3, mg: &mgWhite, eg: &egWhite, atkUnits: &wAttackUnits, atkCount: &wAttackers)
        evalSlider(blackRooks, friendly: blackOcc, enemyPawnAtt: wPawnAttacks, enemyKingZone: wKingZone, isDiag: false, mgPerSq: 2, egPerSq: 4, baseline: 7, attackWeight: 3, mg: &mgBlack, eg: &egBlack, atkUnits: &bAttackUnits, atkCount: &bAttackers)

        // Queen & Knight king-zone pressure
        var wq = whiteQueens
        while wq != 0 {
            let sq = wq.trailingZeroBitCount
            wq &= wq - 1
            let dist = max(abs((sq & 7) - bk.file), abs((sq >> 3) - bk.rank))
            if dist <= 3 { wAttackers += 1; wAttackUnits += 5 }
        }
        var bq = blackQueens
        while bq != 0 {
            let sq = bq.trailingZeroBitCount
            bq &= bq - 1
            let dist = max(abs((sq & 7) - wk.file), abs((sq >> 3) - wk.rank))
            if dist <= 3 { bAttackers += 1; bAttackUnits += 5 }
        }

        if wAttackers >= 2 { mgWhite += min(180, wAttackUnits * wAttackUnits * 2) }
        if bAttackers >= 2 { mgBlack += min(180, bAttackUnits * bAttackUnits * 2) }

        // King pawn-shield safety in middlegame
        if wk.rank <= 1 {
            for df in max(0, wk.file - 1)...min(7, wk.file + 1) {
                let r1 = (wk.rank + 1) * 8 + df
                let r2 = (wk.rank + 2) * 8 + df
                if (whitePawns & (1 &<< r1)) != 0 { mgWhite += 14 }
                else if (whitePawns & (1 &<< r2)) != 0 { mgWhite += 7 }
                else if wCount(df) == 0 { mgWhite -= 14 }
            }
        }
        if bk.rank >= 6 {
            for df in max(0, bk.file - 1)...min(7, bk.file + 1) {
                let r1 = (bk.rank - 1) * 8 + df
                let r2 = (bk.rank - 2) * 8 + df
                if (blackPawns & (1 &<< r1)) != 0 { mgBlack += 14 }
                else if (blackPawns & (1 &<< r2)) != 0 { mgBlack += 7 }
                else if bCount(df) == 0 { mgBlack -= 14 }
            }
        }

        let mgPhase = min(24, phase)
        let egPhase = 24 - mgPhase
        let whiteDiffMg = mgWhite - mgBlack
        var whiteDiffEg = egWhite - egBlack

        // Opposite-colored bishops endgame drawishness scaling
        if majorCount == 0 && whiteBishops == 1 && blackBishops == 1 && whiteBishopLight != blackBishopLight {
            whiteDiffEg = (whiteDiffEg * 62) / 100
        }

        // Endgame mop-up evaluation (pushes losing king to corner & brings winning king close)
        if mgPhase <= 6 && abs(whiteDiffEg) >= 280 {
            let winningWhite = whiteDiffEg > 0
            let winK = winningWhite ? wk : bk
            let loseK = winningWhite ? bk : wk
            let centerDist = max(3 - loseK.file, loseK.file - 4) + max(3 - loseK.rank, loseK.rank - 4)
            let kingDist = abs(winK.file - loseK.file) + abs(winK.rank - loseK.rank)
            let mopUp = centerDist * 14 + (14 - kingDist) * 7
            whiteDiffEg += winningWhite ? mopUp : -mopUp
        }

        let blended = (whiteDiffMg * mgPhase + whiteDiffEg * egPhase) / 24
        let tempo = 6 + (mgPhase >> 1)
        return (board.turn == .white ? blended : -blended) + tempo
    }

    @inline(__always)
    private static func kingZoneMask(_ kingSq: Square) -> UInt64 {
        let f = kingSq.file
        let r = kingSq.rank
        var mask: UInt64 = 0
        for dr in -1...1 {
            let nr = r + dr
            if nr < 0 || nr > 7 { continue }
            for df in -1...1 {
                let nf = f + df
                if nf < 0 || nf > 7 { continue }
                mask |= (1 &<< (nr * 8 + nf))
            }
        }
        return mask
    }

    // Tapered Piece-Square Tables (White orientation: index 0 = a8, 63 = h1)
    private static let mgPawn: [Int] = [
          0,   0,   0,   0,   0,   0,   0,   0,
         98, 134,  61,  95,  68, 126,  34, -11,
         -6,   7,  26,  31,  65,  56,  25, -20,
        -14,  13,   6,  21,  23,  12,  17, -23,
        -27,  -2,  -5,  12,  17,   6,  10, -25,
        -26,  -4,  -4, -10,   3,   3,  33, -12,
        -35,  -1, -20, -23, -15,  24,  38, -22,
          0,   0,   0,   0,   0,   0,   0,   0,
    ]
    private static let egPawn: [Int] = [
          0,   0,   0,   0,   0,   0,   0,   0,
        178, 173, 158, 134, 147, 132, 165, 187,
         94, 100,  85,  67,  56,  53,  82,  84,
         32,  24,  13,   5,  -2,   4,  17,  17,
         13,   9,  -3,  -7,  -7,  -8,   3,  -1,
          4,   7,  -6,   1,   0,  -5,  -1,  -8,
         13,   8,   8,  10,  13,   0,   2,  -7,
          0,   0,   0,   0,   0,   0,   0,   0,
    ]
    private static let mgKnight: [Int] = [
       -167, -89, -34, -49,  61, -97, -15,-107,
        -73, -41,  72,  36,  23,  62,   7, -17,
        -47,  60,  37,  65,  84, 129,  73,  44,
         -9,  17,  19,  53,  37,  69,  18,  22,
        -13,   4,  16,  13,  28,  19,  21,  -8,
        -23,  -9,  12,  10,  19,  17,  25, -16,
        -29, -53, -12,  -3,  -1,  18, -14, -19,
       -105, -21, -58, -33, -17, -28, -19, -23,
    ]
    private static let egKnight: [Int] = [
        -58, -38, -13, -28, -31, -27, -63, -99,
        -25,  -8, -25,  -2,  -9, -25, -24, -52,
        -24, -20,  10,   9,  -1,  -9, -19, -41,
        -17,   3,  22,  22,  22,  11,   8, -18,
        -18,  -6,  16,  25,  16,  17,   4, -18,
        -23,  -3,  -1,  15,  10,  -3, -20, -22,
        -42, -20, -10,  -5,  -2, -20, -23, -44,
        -29, -51, -23, -15, -22, -18, -50, -64,
    ]
    private static let mgBishop: [Int] = [
        -29,   4, -82, -37, -25, -42,   7,  -8,
        -26,  16, -18, -13,  30,  59,  18, -47,
        -16,  37,  43,  40,  35,  50,  37,  -2,
         -4,   5,  19,  50,  37,  37,   7,  -2,
         -6,  13,  13,  26,  34,  12,  10,   4,
          0,  15,  15,  15,  14,  27,  18,  10,
          4,  15,  16,   0,   7,  21,  33,   1,
        -33,  -3, -14, -21, -13, -12, -39, -21,
    ]
    private static let egBishop: [Int] = [
        -14, -21, -11,  -8,  -7,  -9, -17, -24,
         -8,  -4,   7, -12,  -3, -13,  -4, -14,
          2,  -8,   0,  -1,  -2,   6,   0,   4,
         -3,   9,  12,   9,  14,  10,   3,   2,
         -6,   3,  13,  19,   7,  10,  -3,  -9,
        -12,  -3,   8,  10,  13,   3,  -7, -15,
        -14, -18,  -7,  -1,   4,  -9, -15, -27,
        -23,  -9, -23,  -5,  -9, -16,  -5, -17,
    ]
    private static let mgRook: [Int] = [
         32,  42,  32,  51,  63,   9,  31,  43,
         27,  32,  58,  62,  80,  67,  26,  44,
         -5,  19,  26,  36,  17,  45,  61,  16,
        -24, -11,   7,  26,  24,  35,  -8, -20,
        -36, -26, -12,  -1,   9,  -7,   6, -23,
        -45, -25, -16, -17,   3,   0,  -5, -33,
        -44, -16, -20,  -9,  -1,  11,  -6, -71,
        -19, -13,   1,  17,  16,   7, -37, -26,
    ]
    private static let egRook: [Int] = [
         13,  10,  18,  15,  12,  12,   8,   5,
         11,  13,  13,  11,  -3,   3,   8,   3,
          7,   7,   7,   5,   4,  -3,  -5,  -3,
          4,   3,  13,   1,   2,   1,  -1,   2,
          3,   5,   8,   4,  -5,  -6,  -8, -11,
         -4,   0,  -5,  -1,  -7, -12,  -8, -16,
         -6,  -6,   0,   2,  -9,  -9, -11,  -3,
         -9,   2,   3,  -1,  -5, -13,   4, -20,
    ]
    private static let mgQueen: [Int] = [
        -28,   0,  29,  12,  59,  44,  43,  45,
        -24, -39,  -5,   1, -16,  57,  28,  54,
        -13, -17,   7,   8,  29,  56,  47,  57,
        -27, -27, -16, -16,  -1,  17,  -2,   1,
         -9, -26,  -9, -10,  -2,  -4,   3,  -3,
        -14,   2, -11,  -2,  -5,   2,  14,   5,
        -35,  -8,  11,   2,   8,  15,  -3,   1,
         -1, -18,  -9,  10, -15, -25, -31, -50,
    ]
    private static let egQueen: [Int] = [
         -9,  22,  22,  27,  27,  19,  10,  20,
        -17,  20,  32,  41,  58,  25,  30,   0,
        -20,   6,   9,  49,  47,  35,  19,   9,
          3,  22,  24,  45,  57,  40,  57,  36,
        -18,  28,  19,  47,  31,  34,  39,  23,
        -16, -27,  15,   6,   9,  17,  10,   5,
        -22, -23, -30, -16, -16, -23, -36, -32,
        -33, -28, -22, -43,  -5, -32, -20, -41,
    ]
    private static let mgKing: [Int] = [
        -65,  23,  16, -15, -56, -34,   2,  13,
         29,  -1, -20,  -7,  -8,  -4, -38, -29,
         -9,  24,   2, -16, -20,   6,  22, -22,
        -17, -20, -12, -27, -30, -25, -14, -36,
        -49,  -1, -27, -39, -46, -44, -33, -51,
        -14, -14, -22, -46, -44, -30, -15, -27,
          1,   7,  -8, -64, -43, -16,   9,   8,
        -15,  36,  12, -54,   8, -28,  24,  14,
    ]
    private static let egKing: [Int] = [
        -74, -35, -18, -18, -11,  15,   4, -17,
        -12,  17,  14,  17,  17,  38,  23,  11,
         10,  17,  23,  15,  20,  45,  44,  13,
         -8,  22,  24,  27,  26,  33,  26,   3,
        -18,  -4,  21,  24,  27,  23,   9, -11,
        -19,  -3,  11,  21,  23,  16,   7,  -9,
        -27, -11,   4,  13,  14,   4,  -5, -17,
        -53, -34, -21, -11, -28, -14, -24, -43,
    ]
}
