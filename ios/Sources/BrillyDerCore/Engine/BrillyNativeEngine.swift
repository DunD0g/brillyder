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
    private static let ttMask = (1 << 16) - 1 // 65,536 entries (~2 MB RAM)

    private var tt: [TTEntry]
    private var killers: [[ChessMove?]]
    private var pathHashes: [UInt64] = []
    private var nodesVisited: Int = 0
    private var deadline: ContinuousClock.Instant?
    private var enforceDeadline: Bool = false
    private var aborted: Bool = false

    public init() {
        self.tt = Array(repeating: TTEntry(), count: Self.ttMask + 1)
        self.killers = Array(repeating: [nil, nil], count: 64)
    }

    public func clearHash() {
        for i in 0..<tt.count {
            tt[i] = TTEntry()
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
        let clampedDepth = max(1, min(10, depth))
        let requestedPV = max(1, min(multiPV, legal.count))
        let clock = ContinuousClock()
        self.deadline = maxTimeMs.map { clock.now.advanced(by: .milliseconds($0)) }
        self.aborted = false
        self.nodesVisited = 0
        self.killers = Array(repeating: [nil, nil], count: 64)
        self.pathHashes = [board.zobristHash]

        var completedDepth = 0
        var bestLines: [MultiPvLine] = []

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

                let (scoreSide, bestMove, pv, completedAnyMove) = searchRoot(
                    board: board,
                    candidates: candidates,
                    depth: d,
                    storeRootTT: (pvIdx == 1)
                )

                if aborted || !completedAnyMove {
                    depthFullyCompleted = false
                    break
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
        storeRootTT: Bool
    ) -> (score: Int, bestMove: ChessMove?, pv: [ChessMove], completedAnyMove: Bool) {
        let ttSlot = Int(board.zobristHash & UInt64(Self.ttMask))
        let ttMove = (storeRootTT && tt[ttSlot].key == board.zobristHash) ? tt[ttSlot].bestMove : nil
        let ordered = orderMoves(candidates, board: board, ttMove: ttMove, ply: 0)

        var alpha = -Self.mateScore - 100
        let beta = Self.mateScore + 100
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
            if index == 0 {
                score = -negamax(board: next, depth: depth - 1, alpha: -beta, beta: -alpha, ply: 1, pv: &childPV)
            } else {
                var zeroPV: [ChessMove] = []
                let probe = -negamax(board: next, depth: depth - 1, alpha: -alpha - 1, beta: -alpha, ply: 1, pv: &zeroPV)
                if probe > alpha && !aborted {
                    score = -negamax(board: next, depth: depth - 1, alpha: -beta, beta: -alpha, ply: 1, pv: &childPV)
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
            if score > alpha {
                alpha = score
            }
        }

        if storeRootTT, let bm = bestMove, !aborted, completedAny {
            storeTT(key: board.zobristHash, depth: depth, score: bestScore, bound: .exact, bestMove: bm)
        }
        return (bestScore, bestMove, bestPV, completedAny)
    }

    private func negamax(
        board: ChessBoard,
        depth: Int,
        alpha origAlpha: Int,
        beta: Int,
        ply: Int,
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
            var reps = 0
            for i in stride(from: pathHashes.count - 3, through: 0, by: -2) {
                if pathHashes[i] == hash {
                    reps += 1
                    break
                }
            }
            if reps > 0 { return 0 }
        }

        let inCheck = board.isInCheck()
        let effectiveDepth = (inCheck && ply < 16) ? depth + 1 : depth
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

        let legal = board.legalMoves()
        if legal.isEmpty {
            return inCheck ? (-Self.mateScore + ply) : 0
        }

        let ordered = orderMoves(legal, board: board, ttMove: ttMove, ply: ply)
        var bestScore = -Self.mateScore - 100
        var bestMove: ChessMove? = nil

        for (index, move) in ordered.enumerated() {
            var next = board
            next.makeMoveUnchecked(move)
            pathHashes.append(next.zobristHash)

            var childPV: [ChessMove] = []
            let score: Int
            if index == 0 {
                score = -negamax(board: next, depth: effectiveDepth - 1, alpha: -beta, beta: -alpha, ply: ply + 1, pv: &childPV)
            } else {
                var zeroPV: [ChessMove] = []
                let probe = -negamax(board: next, depth: effectiveDepth - 1, alpha: -alpha - 1, beta: -alpha, ply: ply + 1, pv: &zeroPV)
                if probe > alpha && probe < beta && !aborted {
                    score = -negamax(board: next, depth: effectiveDepth - 1, alpha: -beta, beta: -alpha, ply: ply + 1, pv: &childPV)
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
                pv = [move] + childPV
            }
            if alpha >= beta {
                let isEp = board[move.from]?.type == .pawn && move.to == board.enPassantSquare
                if board[move.to] == nil && !isEp && move.promotion == nil && ply < 64 {
                    if killers[ply][0] != move {
                        killers[ply][1] = killers[ply][0]
                        killers[ply][0] = move
                    }
                }
                break
            }
        }

        let bound: Bound
        if bestScore <= origAlpha { bound = .upper }
        else if bestScore >= beta { bound = .lower }
        else { bound = .exact }
        storeTT(
            key: board.zobristHash,
            depth: effectiveDepth,
            score: adjustMateScoreForTT(bestScore, ply: ply),
            bound: bound,
            bestMove: bestMove
        )
        return bestScore
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

        if inCheck {
            // Never stand pat while in check; search all legal evasions & detect checkmate
            let evasions = board.legalMoves()
            if evasions.isEmpty {
                return -Self.mateScore + ply
            }
            if ply >= 24 { return evaluate(board) }
            let ordered = orderMoves(evasions, board: board, ttMove: nil, ply: min(ply, 63))
            for move in ordered {
                var next = board
                next.makeMoveUnchecked(move)
                let score = -quiescence(board: next, alpha: -beta, beta: -alpha, ply: ply + 1)
                if aborted { return 0 }
                if score >= beta { return beta }
                if score > alpha { alpha = score }
            }
            return alpha
        }

        let standPat = evaluate(board)
        if standPat >= beta { return beta }
        if standPat > alpha { alpha = standPat }
        if ply >= 24 { return standPat }

        let captures = board.legalMoves(capturesOnly: true)
        if captures.isEmpty { return standPat }

        let ordered = captures.sorted { lhs, rhs in
            captureScore(lhs, on: board) > captureScore(rhs, on: board)
        }

        for move in ordered {
            if move.promotion == nil, let victim = board[move.to] {
                if standPat + victim.type.centipawnValue + 200 < alpha {
                    continue
                }
            }
            var next = board
            next.makeMoveUnchecked(move)
            let score = -quiescence(board: next, alpha: -beta, beta: -alpha, ply: ply + 1)
            if aborted { return 0 }
            if score >= beta { return beta }
            if score > alpha { alpha = score }
        }
        return alpha
    }

    // MARK: - Move Ordering & TT Helpers

    private func orderMoves(_ moves: [ChessMove], board: ChessBoard, ttMove: ChessMove?, ply: Int) -> [ChessMove] {
        let k0 = ply < 64 ? killers[ply][0] : nil
        let k1 = ply < 64 ? killers[ply][1] : nil
        return moves.sorted { a, b in
            movePriority(a, board: board, ttMove: ttMove, k0: k0, k1: k1) >
            movePriority(b, board: board, ttMove: ttMove, k0: k0, k1: k1)
        }
    }

    @inline(__always)
    private func movePriority(_ move: ChessMove, board: ChessBoard, ttMove: ChessMove?, k0: ChessMove?, k1: ChessMove?) -> Int {
        if move == ttMove { return 1_000_000 }
        var score = 0
        let isEp = board[move.from]?.type == .pawn && move.to == board.enPassantSquare
        if board[move.to] != nil || isEp {
            score += 100_000 + captureScore(move, on: board)
        }
        if let promo = move.promotion {
            score += 90_000 + promo.centipawnValue
        }
        if move == k0 { score += 50_000 }
        else if move == k1 { score += 45_000 }
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

    // MARK: - PeSTO-Inspired Tapered Evaluation

    private func evaluate(_ board: ChessBoard) -> Int {
        var mgWhite = 0
        var egWhite = 0
        var mgBlack = 0
        var egBlack = 0
        var phase = 0
        var whiteBishops = 0
        var blackBishops = 0

        for idx in 0..<64 {
            guard let p = board.squares[idx] else { continue }
            let rank = idx >> 3
            let file = idx & 7
            // Table index: 0 = a8 (top-left from White's perspective), 63 = h1
            let pstIdx = p.color == .white ? ((7 - rank) * 8 + file) : (rank * 8 + file)

            let mg: Int
            let eg: Int
            switch p.type {
            case .pawn:
                mg = 82 + Self.mgPawn[pstIdx]
                eg = 94 + Self.egPawn[pstIdx]
            case .knight:
                mg = 337 + Self.mgKnight[pstIdx]
                eg = 281 + Self.egKnight[pstIdx]
                phase += 1
            case .bishop:
                mg = 365 + Self.mgBishop[pstIdx]
                eg = 297 + Self.egBishop[pstIdx]
                phase += 1
                if p.color == .white { whiteBishops += 1 } else { blackBishops += 1 }
            case .rook:
                mg = 477 + Self.mgRook[pstIdx]
                eg = 512 + Self.egRook[pstIdx]
                phase += 2
            case .queen:
                mg = 1025 + Self.mgQueen[pstIdx]
                eg = 936 + Self.egQueen[pstIdx]
                phase += 4
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
        if whiteBishops >= 2 { mgWhite += 30; egWhite += 45 }
        if blackBishops >= 2 { mgBlack += 30; egBlack += 45 }

        let mgPhase = min(24, phase)
        let egPhase = 24 - mgPhase
        let whiteDiffMg = mgWhite - mgBlack
        let whiteDiffEg = egWhite - egBlack
        let blended = (whiteDiffMg * mgPhase + whiteDiffEg * egPhase) / 24
        let tempo = 12
        return (board.turn == .white ? blended : -blended) + tempo
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
