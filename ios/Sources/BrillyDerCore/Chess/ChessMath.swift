import Foundation

public struct EngineScore: Codable, Hashable, Sendable {
    public let cpWhite: Int
    public let mateWhite: Int?
    public let isCheckmate: Bool?
    public let winPercentWhite: Double
    public let display: String

    public init(
        cpWhite: Int,
        mateWhite: Int? = nil,
        isCheckmate: Bool? = nil,
        winPercentWhite: Double,
        display: String
    ) {
        self.cpWhite = cpWhite
        self.mateWhite = mateWhite
        self.isCheckmate = isCheckmate
        self.winPercentWhite = winPercentWhite
        self.display = display
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .cpWhite) {
            self.cpWhite = i
        } else if let d = try? c.decode(Double.self, forKey: .cpWhite), d.isFinite {
            self.cpWhite = Int(min(100_000.0, max(-100_000.0, d.rounded())))
        } else {
            self.cpWhite = 0
        }
        if let m = try? c.decodeIfPresent(Int.self, forKey: .mateWhite) {
            self.mateWhite = m
        } else if let md = try? c.decodeIfPresent(Double.self, forKey: .mateWhite), md.isFinite {
            self.mateWhite = Int(min(1000.0, max(-1000.0, md.rounded())))
        } else {
            self.mateWhite = nil
        }
        self.isCheckmate = try? c.decodeIfPresent(Bool.self, forKey: .isCheckmate)
        self.winPercentWhite = (try? c.decode(Double.self, forKey: .winPercentWhite)) ?? 50.0
        self.display = (try? c.decode(String.self, forKey: .display)) ?? "0.0"
    }
}

public struct MaterialBalance: Hashable, Sendable {
    /// Signed material score from White's perspective (`whitePoints - blackPoints`).
    public let whiteAdvantage: Int
    public let capturedByWhite: [PieceType]
    public let capturedByBlack: [PieceType]
    public let whiteExtraPieces: [PieceType]
    public let blackExtraPieces: [PieceType]

    public init(
        whiteAdvantage: Int,
        capturedByWhite: [PieceType],
        capturedByBlack: [PieceType],
        whiteExtraPieces: [PieceType] = [],
        blackExtraPieces: [PieceType] = []
    ) {
        self.whiteAdvantage = whiteAdvantage
        self.capturedByWhite = capturedByWhite
        self.capturedByBlack = capturedByBlack
        self.whiteExtraPieces = whiteExtraPieces
        self.blackExtraPieces = blackExtraPieces
    }

    /// Non-negative material lead for `color` (0 if equal or behind).
    public func advantage(for color: PieceColor) -> Int {
        color == .white ? max(0, whiteAdvantage) : max(0, -whiteAdvantage)
    }

    /// Net extra piece types held by `color` compared to opponent (ordered Q, R, B, N, P).
    public func extraPieces(for color: PieceColor) -> [PieceType] {
        color == .white ? whiteExtraPieces : blackExtraPieces
    }

    /// Compact monochrome chess glyphs + point lead (e.g. `"♝ +3"`), using U+FE0E so iOS never renders pawn as an emoji.
    public func compactBadgeText(for color: PieceColor, maxIcons: Int = 2) -> String? {
        let adv = advantage(for: color)
        guard adv > 0 else { return nil }
        let pieces = extraPieces(for: color)
        let glyphs = pieces.prefix(maxIcons).map { Self.textGlyph(for: $0) }.joined()
        return glyphs.isEmpty ? "+\(adv)" : "\(glyphs) +\(adv)"
    }

    private static func textGlyph(for type: PieceType) -> String {
        switch type {
        case .queen:  return "♛\u{FE0E}"
        case .rook:   return "♜\u{FE0E}"
        case .bishop: return "♝\u{FE0E}"
        case .knight: return "♞\u{FE0E}"
        case .pawn:   return "♟\u{FE0E}"
        case .king:   return ""
        }
    }
}

public enum ChessMath {
    public static func clamp(_ value: Double, min lo: Double, max hi: Double) -> Double {
        guard value.isFinite else { return lo }
        return Swift.max(lo, Swift.min(hi, value))
    }

    public static func cpToWinPercent(_ cp: Double) -> Double {
        guard cp.isFinite else { return 50.0 }
        let clamped = clamp(cp, min: -2500.0, max: 2500.0)
        return 50.0 + 50.0 * (2.0 / (1.0 + exp(-0.00368208 * clamped)) - 1.0)
    }

    public static func buildEngineScore(
        cpWhite: Int,
        mateWhite: Int? = nil,
        isCheckmate: Bool = false,
        winnerColor: PieceColor? = nil
    ) -> EngineScore {
        if isCheckmate, let winner = winnerColor {
            let isWhiteWin = winner == .white
            return EngineScore(
                cpWhite: isWhiteWin ? 10000 : -10000,
                mateWhite: 0,
                isCheckmate: true,
                winPercentWhite: isWhiteWin ? 100.0 : 0.0,
                display: "#"
            )
        }
        if let mate = mateWhite, mate != 0 {
            let isWhiteWin = mate > 0
            let absMate = min(150, abs(mate))
            return EngineScore(
                cpWhite: isWhiteWin ? (10000 - absMate * 50) : (-10000 + absMate * 50),
                mateWhite: mate,
                isCheckmate: nil,
                winPercentWhite: isWhiteWin ? 100.0 : 0.0,
                display: "\(isWhiteWin ? "" : "-")M\(absMate)"
            )
        }
        let winPct = cpToWinPercent(Double(cpWhite))
        let pawns = Double(cpWhite) / 100.0
        let absPawns = abs(pawns)
        let display: String
        if abs(cpWhite) < 8 {
            display = "0.0"
        } else if absPawns >= 10.0 {
            display = "\(pawns >= 0 ? "+" : "-")\(Int(absPawns.rounded()))"
        } else {
            display = String(format: "%@%.1f", locale: Locale(identifier: "en_US_POSIX"), pawns >= 0 ? "+" : "", pawns)
        }
        return EngineScore(
            cpWhite: cpWhite,
            mateWhite: nil,
            isCheckmate: nil,
            winPercentWhite: winPct,
            display: display
        )
    }

    public static func moverWinPercent(_ score: EngineScore, mover: PieceColor) -> Double {
        mover == .white ? score.winPercentWhite : (100.0 - score.winPercentWhite)
    }

    public static func calculateMoveAccuracy(winLoss: Double) -> Double {
        guard winLoss.isFinite, winLoss > 0.1 else { return 100.0 }
        let raw = 103.1668 * exp(-0.04354 * winLoss) - 3.1669
        let rounded = (raw * 10.0).rounded() / 10.0
        return clamp(rounded, min: 0.0, max: 100.0)
    }

    public static func calculateGameAccuracy(moveAccuracies: [Double], winPercents: [Double]) -> Double {
        guard !moveAccuracies.isEmpty else { return 0.0 }
        var weightedSum = 0.0
        var weightTotal = 0.0
        var harmonicDenom = 0.0

        for i in 0..<moveAccuracies.count {
            let acc = clamp(moveAccuracies[i], min: 0.0, max: 100.0)
            let wp = i < winPercents.count ? clamp(winPercents[i], min: 0.0, max: 100.0) : 50.0
            let weight = 0.5 + 0.5 * (1.0 - abs(wp - 50.0) / 50.0)
            weightedSum += acc * weight
            weightTotal += weight
            harmonicDenom += 1.0 / max(5.0, acc)
        }

        let wMean = weightTotal > 0 ? weightedSum / weightTotal : 0.0
        let hMean = harmonicDenom > 0 ? Double(moveAccuracies.count) / harmonicDenom : 0.0
        let combined = clamp(0.58 * wMean + 0.42 * hMean, min: 0.0, max: 100.0)
        return (combined * 10.0).rounded() / 10.0
    }

    public static func estimateGameElo(
        playerRating: Int?,
        opponentRating: Int?,
        accuracy: Double,
        resultScore: Double
    ) -> Int {
        let anchor: Double
        if let p = playerRating, let o = opponentRating {
            anchor = Double(p + o) / 2.0
        } else if let p = playerRating {
            anchor = Double(p)
        } else if let o = opponentRating {
            anchor = Double(o)
        } else {
            anchor = 1500.0
        }
        let baseline = clamp(56.0 + (anchor - 1000.0) * 0.018, min: 52.0, max: 90.0)
        let bonus: Double = resultScore >= 0.99 ? 85.0 : (resultScore <= 0.01 ? -85.0 : 0.0)
        let raw = clamp(anchor + (accuracy - baseline) * 19.0 + bonus, min: 400.0, max: 3100.0)
        return Int((raw / 10.0).rounded()) * 10
    }

    public static func uciLineToSAN(fen: String, uciMoves: [String], maxMoves: Int = 5) -> [String] {
        guard var board = try? ChessBoard(fen: fen) else { return [] }
        var out: [String] = []
        for uci in uciMoves.prefix(maxMoves) {
            guard let applied = try? board.apply(uci: uci) else { break }
            out.append(applied.san)
        }
        return out
    }

    public static func nonPawnMaterial(in board: ChessBoard) -> Int {
        var total = 0
        for p in board.squares {
            guard let p, p.type != .pawn && p.type != .king else { continue }
            total += p.type.materialValue
        }
        return total
    }

    public static func materialBalance(in board: ChessBoard) -> MaterialBalance {
        let startCounts: [PieceType: Int] = [.queen: 1, .rook: 2, .bishop: 2, .knight: 2, .pawn: 8]
        var curW: [PieceType: Int] = [:]
        var curB: [PieceType: Int] = [:]
        var wPts = 0
        var bPts = 0

        for p in board.squares {
            guard let p, p.type != .king else { continue }
            if p.color == .white {
                curW[p.type, default: 0] += 1
                wPts += p.type.materialValue
            } else {
                curB[p.type, default: 0] += 1
                bPts += p.type.materialValue
            }
        }

        let order: [PieceType] = [.queen, .rook, .bishop, .knight, .pawn]
        var capByWhite: [PieceType] = []
        var capByBlack: [PieceType] = []
        var wExtra: [PieceType] = []
        var bExtra: [PieceType] = []

        for t in order {
            let wCnt = curW[t] ?? 0
            let bCnt = curB[t] ?? 0
            let missingBlack = max(0, (startCounts[t] ?? 0) - bCnt)
            let missingWhite = max(0, (startCounts[t] ?? 0) - wCnt)
            if missingBlack > 0 { capByWhite.append(contentsOf: repeatElement(t, count: missingBlack)) }
            if missingWhite > 0 { capByBlack.append(contentsOf: repeatElement(t, count: missingWhite)) }
            let net = wCnt - bCnt
            if net > 0 { wExtra.append(contentsOf: repeatElement(t, count: net)) }
            else if net < 0 { bExtra.append(contentsOf: repeatElement(t, count: -net)) }
        }

        return MaterialBalance(
            whiteAdvantage: wPts - bPts,
            capturedByWhite: capByWhite,
            capturedByBlack: capByBlack,
            whiteExtraPieces: wExtra,
            blackExtraPieces: bExtra
        )
    }

    /// Static Exchange Evaluation (SEE) on `square` for side-to-move.
    /// Matches web Swarm Audit Pass 1: picks least-valuable attacker first, and highest promotion (`=Q`) first on ties.
    public static func legalCaptureGainOnSquare(
        board: ChessBoard,
        square: Square,
        maxDepth: Int = 6
    ) -> Int {
        guard maxDepth > 0, let victim = board[square], victim.color != board.turn else {
            return 0
        }
        let captures = board.legalMoves(capturesOnly: true).filter { $0.to == square }
        guard !captures.isEmpty else { return 0 }

        let sorted = captures.sorted { lhs, rhs in
            let lv = board[lhs.from]?.type.seeValue ?? 1000
            let rv = board[rhs.from]?.type.seeValue ?? 1000
            if lv != rv { return lv < rv }
            let lp = lhs.promotion?.seeValue ?? 0
            let rp = rhs.promotion?.seeValue ?? 0
            return lp > rp
        }

        guard let bestCapture = sorted.first else { return 0 }
        let promoBonus = bestCapture.promotion.map { max(0, $0.seeValue - PieceType.pawn.seeValue) } ?? 0
        let gainNow = victim.type.seeValue + promoBonus

        var next = board
        next.makeMoveUnchecked(bestCapture)
        let reply = legalCaptureGainOnSquare(board: next, square: square, maxDepth: maxDepth - 1)
        return max(0, gainNow - reply)
    }
}
