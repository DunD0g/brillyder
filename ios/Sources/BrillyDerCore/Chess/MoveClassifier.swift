import Foundation

public enum MoveClassification: String, Codable, Hashable, Sendable, CaseIterable {
    case brilliant
    case great
    case best
    case excellent
    case inaccuracy
    case mistake
    case blunder
    case book

    public var label: String {
        switch self {
        case .brilliant: return "Brilliant"
        case .great: return "Great Move"
        case .best: return "Best"
        case .excellent: return "Good"
        case .inaccuracy: return "Inaccuracy"
        case .mistake: return "Mistake"
        case .blunder: return "Blunder"
        case .book: return "Book"
        }
    }

    public var symbol: String {
        switch self {
        case .brilliant: return "!!"
        case .great: return "!"
        case .best: return "★"
        case .excellent: return "✓"
        case .inaccuracy: return "?!"
        case .mistake: return "?"
        case .blunder: return "??"
        case .book: return "📖"
        }
    }
}

public enum GamePhase: String, Codable, Hashable, Sendable {
    case opening
    case middlegame
    case endgame
}

public struct CoachingExplanation: Codable, Hashable, Sendable {
    public let headline: String
    public let detail: String
    public let tacticalTag: String

    public init(headline: String, detail: String, tacticalTag: String) {
        self.headline = headline
        self.detail = detail
        self.tacticalTag = tacticalTag
    }
}

public struct MoveClassificationInput: Sendable {
    public let plyIndex: Int
    public let sanPrefix: [String]
    public let openingPlyHint: Int?
    public let playedUci: String
    public let bestMoveUci: String
    public let afterBoard: ChessBoard
    public let moverColor: PieceColor
    public let toSquare: Square
    public let movedPiece: PieceType
    public let capturedPiece: PieceType?
    public let promotionPiece: PieceType?
    public let positionRepeated: Bool
    public let moverWinBefore: Double
    public let moverWinAfter: Double
    public let secondBestGapWin: Double
    public let hasSecondLine: Bool
    public let missedMate: Bool
    public let missedShortMate: Bool
    public let walkedIntoMate: Bool
    public let forceDrawRepetition: Bool

    public init(
        plyIndex: Int,
        sanPrefix: [String],
        openingPlyHint: Int? = nil,
        playedUci: String,
        bestMoveUci: String,
        afterBoard: ChessBoard,
        moverColor: PieceColor,
        toSquare: Square,
        movedPiece: PieceType,
        capturedPiece: PieceType? = nil,
        promotionPiece: PieceType? = nil,
        positionRepeated: Bool = false,
        moverWinBefore: Double,
        moverWinAfter: Double,
        secondBestGapWin: Double,
        hasSecondLine: Bool,
        missedMate: Bool = false,
        missedShortMate: Bool = false,
        walkedIntoMate: Bool = false,
        forceDrawRepetition: Bool = false
    ) {
        self.plyIndex = plyIndex
        self.sanPrefix = sanPrefix
        self.openingPlyHint = openingPlyHint
        self.playedUci = playedUci
        self.bestMoveUci = bestMoveUci
        self.afterBoard = afterBoard
        self.moverColor = moverColor
        self.toSquare = toSquare
        self.movedPiece = movedPiece
        self.capturedPiece = capturedPiece
        self.promotionPiece = promotionPiece
        self.positionRepeated = positionRepeated
        self.moverWinBefore = moverWinBefore
        self.moverWinAfter = moverWinAfter
        self.secondBestGapWin = secondBestGapWin
        self.hasSecondLine = hasSecondLine
        self.missedMate = missedMate
        self.missedShortMate = missedShortMate
        self.walkedIntoMate = walkedIntoMate
        self.forceDrawRepetition = forceDrawRepetition
    }
}

public enum MoveClassifier {
    public static let classificationVersion = 3
    private static let sacrificeMinGain = 2

    public struct OpeningBookEntry: Sendable {
        public let eco: String
        public let name: String
        public let moves: [String]
    }

    public static let commonOpenings: [OpeningBookEntry] = [
        .init(eco: "D02", name: "London System", moves: ["d4", "d5", "Bf4"]),
        .init(eco: "A45", name: "London System", moves: ["d4", "Nf6", "Bf4"]),
        .init(eco: "C50", name: "Italian Game", moves: ["e4", "e5", "Nf3", "Nc6", "Bc4"]),
        .init(eco: "C60", name: "Ruy Lopez", moves: ["e4", "e5", "Nf3", "Nc6", "Bb5"]),
        .init(eco: "C42", name: "Petrov's Defense", moves: ["e4", "e5", "Nf3", "Nf6"]),
        .init(eco: "C45", name: "Scotch Game", moves: ["e4", "e5", "Nf3", "Nc6", "d4"]),
        .init(eco: "C25", name: "Vienna Game", moves: ["e4", "e5", "Nc3"]),
        .init(eco: "B10", name: "Caro-Kann Defense", moves: ["e4", "c6"]),
        .init(eco: "B12", name: "Caro-Kann: Advance", moves: ["e4", "c6", "d4", "d5", "e5"]),
        .init(eco: "B01", name: "Scandinavian Defense", moves: ["e4", "d5"]),
        .init(eco: "B20", name: "Sicilian Defense", moves: ["e4", "c5"]),
        .init(eco: "B50", name: "Sicilian: Open", moves: ["e4", "c5", "Nf3", "d6", "d4"]),
        .init(eco: "B23", name: "Sicilian: Closed", moves: ["e4", "c5", "Nc3"]),
        .init(eco: "C00", name: "French Defense", moves: ["e4", "e6"]),
        .init(eco: "D06", name: "Queen's Gambit", moves: ["d4", "d5", "c4"]),
        .init(eco: "D30", name: "Queen's Gambit Declined", moves: ["d4", "d5", "c4", "e6"]),
        .init(eco: "D10", name: "Slav Defense", moves: ["d4", "d5", "c4", "c6"]),
        .init(eco: "E60", name: "King's Indian Defense", moves: ["d4", "Nf6", "c4", "g6"]),
        .init(eco: "A10", name: "English Opening", moves: ["c4"]),
        .init(eco: "A04", name: "Réti Opening", moves: ["Nf3"]),
    ]

    public static func lookupOpening(byMoves sanMoves: [String]) -> (eco: String, name: String, matchedPlies: Int)? {
        var best: (String, String, Int)?
        for entry in commonOpenings {
            guard sanMoves.count >= entry.moves.count else { continue }
            var matched = true
            for i in 0..<entry.moves.count {
                if sanMoves[i] != entry.moves[i] {
                    matched = false
                    break
                }
            }
            if matched {
                if best == nil || entry.moves.count > best!.2 {
                    best = (entry.eco, entry.name, entry.moves.count)
                }
            }
        }
        return best
    }

    public static func isBookPly(
        plyIndex: Int,
        sanPrefix: [String],
        openingPlyHint: Int?,
        winLoss: Double
    ) -> Bool {
        guard winLoss <= 8.0, plyIndex < 16 else { return false }
        if let hint = openingPlyHint, plyIndex < hint {
            return true
        }
        if !sanPrefix.isEmpty && commonOpenings.contains(where: { $0.moves.starts(with: sanPrefix) }) {
            return true
        }
        if let match = lookupOpening(byMoves: sanPrefix), plyIndex < match.matchedPlies {
            return true
        }
        return false
    }

    public static func isSacrificeMove(
        afterBoard: ChessBoard,
        mover: PieceColor,
        toSquare: Square,
        movedPiece: PieceType,
        capturedPiece: PieceType?,
        promotionPiece: PieceType?
    ) -> Bool {
        guard afterBoard.turn != mover else { return false }

        let capturedValue = capturedPiece?.seeValue ?? 0
        let promoSurplus: Int
        if movedPiece == .pawn, let promo = promotionPiece {
            promoSurplus = max(0, promo.seeValue - PieceType.pawn.seeValue)
        } else {
            promoSurplus = 0
        }

        // 1. Active sacrifice on destination square
        if movedPiece != .king {
            let oppGain = ChessMath.legalCaptureGainOnSquare(board: afterBoard, square: toSquare, maxDepth: 6)
            if oppGain - promoSurplus - capturedValue >= sacrificeMinGain {
                return true
            }
        }

        // 2. Passive sacrifice: leaving another friendly non-pawn piece en prise (accounting for promoSurplus)
        for idx in 0..<64 {
            let sq = Square(unchecked: idx)
            guard sq != toSquare,
                  let p = afterBoard[sq],
                  p.color == mover,
                  p.type != .king,
                  p.type != .pawn else { continue }
            let oppGain = ChessMath.legalCaptureGainOnSquare(board: afterBoard, square: sq, maxDepth: 6)
            if oppGain - promoSurplus - capturedValue >= sacrificeMinGain {
                return true
            }
        }
        return false
    }

    public static func classify(_ input: MoveClassificationInput) -> MoveClassification {
        let isTopMove = input.playedUci == input.bestMoveUci && !input.forceDrawRepetition
        let rawLoss = max(0.0, input.moverWinBefore - input.moverWinAfter)
        let winLoss = isTopMove ? 0.0 : rawLoss

        if isBookPly(
            plyIndex: input.plyIndex,
            sanPrefix: input.sanPrefix,
            openingPlyHint: input.openingPlyHint,
            winLoss: winLoss
        ) {
            return .book
        }

        let walkedIntoMateError = input.walkedIntoMate && !isTopMove
        if walkedIntoMateError || (input.missedMate && winLoss > 12.0) || winLoss > 30.0 {
            return .blunder
        }

        if input.missedShortMate && !isTopMove {
            return winLoss > 4.0 ? .mistake : .inaccuracy
        }

        if winLoss > 18.0 { return .mistake }
        if winLoss > 10.0 { return .inaccuracy }

        let isBrilliant = isTopMove
            && winLoss <= 2.0
            && !input.missedMate
            && !input.positionRepeated
            && input.moverWinAfter >= 45.0
            && input.moverWinBefore < 94.0
            && input.hasSecondLine
            && input.secondBestGapWin >= 6.0
            && isSacrificeMove(
                afterBoard: input.afterBoard,
                mover: input.moverColor,
                toSquare: input.toSquare,
                movedPiece: input.movedPiece,
                capturedPiece: input.capturedPiece,
                promotionPiece: input.promotionPiece
            )
        if isBrilliant { return .brilliant }

        let isGreat = isTopMove
            && winLoss <= 2.0
            && !input.missedMate
            && input.hasSecondLine
            && input.secondBestGapWin > 10.0
            && input.moverWinBefore < 95.0
        if isGreat { return .great }

        if isTopMove || winLoss <= 2.0 { return .best }
        return .excellent
    }

    public static func detectPhase(plyIndex: Int, board: ChessBoard, isStandardStart: Bool = true) -> GamePhase {
        if ChessMath.nonPawnMaterial(in: board) <= 24 { return .endgame }
        if isStandardStart && plyIndex < 16 { return .opening }
        return .middlegame
    }

    /// Inspects the position before/after a mistake or blunder along with the missed best move
    /// to identify a concrete chess tactical motif (Mate Threat, Hanging Piece, Fork / Double Attack,
    /// Back-Rank, Promotion, Missed Capture, etc.) so Insights → Missed Motifs shows real patterns.
    public static func detectTacticalMotif(
        beforeBoard: ChessBoard,
        afterBoard: ChessBoard,
        moverColor: PieceColor,
        playedToSquare: Square,
        bestMoveUci: String,
        missedMate: Bool,
        walkedIntoMate: Bool
    ) -> String? {
        if walkedIntoMate { return "Mate Threat" }
        if missedMate { return "Missed Mate" }

        let opp = moverColor.opposite

        // 1. Check if the played move hung the moved piece (or left a major/minor piece en prise)
        if let movedPiece = afterBoard.squares[playedToSquare.rawValue],
           movedPiece.color == moverColor,
           movedPiece.type != .pawn,
           movedPiece.type != .king,
           afterBoard.isSquareAttacked(playedToSquare, by: opp) {
            let defended = afterBoard.isSquareAttacked(playedToSquare, by: moverColor)
            if !defended {
                return "Hanging Piece"
            }
            if movedPiece.type == .queen || movedPiece.type == .rook {
                return "Hanging Piece"
            }
        }

        // 2. Inspect the missed best move on a copy of beforeBoard
        if bestMoveUci.count >= 4 {
            var bestAfter = beforeBoard
            if let appliedBest = try? bestAfter.apply(uci: bestMoveUci) {
                // Missed promotion
                if appliedBest.move.promotion != nil {
                    return "Promotion"
                }

                // Back-rank check or mate threat on rank 1 or 8
                let backRank = opp == .white ? 0 : 7
                if bestAfter.isInCheck(opp),
                   bestAfter.kingSquare(for: opp).rank == backRank,
                   (appliedBest.piece.type == .rook || appliedBest.piece.type == .queen) {
                    return "Back-Rank"
                }

                // Missed fork / double attack: best move attacks 2+ valuable opponent pieces
                let dest = appliedBest.move.to
                let attackedValuableTargets = countValuableTargetsAttacked(from: dest, mover: moverColor, on: bestAfter)
                if attackedValuableTargets >= 2 {
                    return "Fork / Double Attack"
                }

                // Missed winning capture of a minor/major piece
                if let cap = appliedBest.captured, cap.type != .pawn {
                    let capVal = cap.type.materialValue
                    let moverVal = appliedBest.piece.type.materialValue
                    if capVal > moverVal || !bestAfter.isSquareAttacked(dest, by: opp) {
                        return "Missed Capture"
                    }
                }

                // Missed forcing check
                if bestAfter.isInCheck(opp) {
                    return "Forcing Check"
                }
            }
        }

        // 3. Check if any other mover piece (non-pawn) was left completely undefended & attacked
        for idx in 0..<64 {
            let sq = Square(unchecked: idx)
            if let p = afterBoard.squares[idx],
               p.color == moverColor,
               p.type != .pawn, p.type != .king,
               afterBoard.isSquareAttacked(sq, by: opp),
               !afterBoard.isSquareAttacked(sq, by: moverColor) {
                return "Hanging Piece"
            }
        }

        return nil
    }

    private static func countValuableTargetsAttacked(from sq: Square, mover: PieceColor, on board: ChessBoard) -> Int {
        guard let attacker = board.squares[sq.rawValue], attacker.color == mover else { return 0 }
        let opp = mover.opposite
        let f = sq.file
        let r = sq.rank
        var targets: [Square] = []

        switch attacker.type {
        case .pawn:
            let nr = mover == .white ? r + 1 : r - 1
            if nr >= 0 && nr < 8 {
                if f > 0 { targets.append(Square(unchecked: nr * 8 + (f - 1))) }
                if f < 7 { targets.append(Square(unchecked: nr * 8 + (f + 1))) }
            }
        case .knight:
            let offsets = [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
            for (df, dr) in offsets {
                let nf = f + df, nr = r + dr
                if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                    targets.append(Square(unchecked: nr * 8 + nf))
                }
            }
        case .king:
            break
        case .bishop, .rook, .queen:
            var dirs: [(Int, Int)] = []
            if attacker.type == .rook || attacker.type == .queen {
                dirs += [(1, 0), (-1, 0), (0, 1), (0, -1)]
            }
            if attacker.type == .bishop || attacker.type == .queen {
                dirs += [(1, 1), (1, -1), (-1, 1), (-1, -1)]
            }
            for (df, dr) in dirs {
                var nf = f + df, nr = r + dr
                while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                    let s = Square(unchecked: nr * 8 + nf)
                    if board.squares[s.rawValue] != nil {
                        targets.append(s)
                        break
                    }
                    nf += df
                    nr += dr
                }
            }
        }

        var count = 0
        for s in targets {
            if let target = board.squares[s.rawValue], target.color == opp {
                if target.type == .king || target.type == .queen || target.type == .rook
                    || ((target.type == .bishop || target.type == .knight) && !board.isSquareAttacked(s, by: opp)) {
                    count += 1
                }
            }
        }
        return count
    }

    public static func generateExplanation(
        classification: MoveClassification,
        playedSan: String,
        bestSan: String,
        winLoss: Double,
        evalAfterDisplay: String,
        isClutchSave: Bool = false,
        detectedMotif: String? = nil
    ) -> CoachingExplanation {
        switch classification {
        case .book:
            return CoachingExplanation(
                headline: "Established opening theory",
                detail: "\(playedSan) follows known opening book lines cleanly.",
                tacticalTag: "Opening Theory"
            )
        case .brilliant:
            return CoachingExplanation(
                headline: "Brilliant tactical sacrifice!",
                detail: "\(playedSan) puts material on the line and finds the only winning sequence (\(evalAfterDisplay)).",
                tacticalTag: "Sacrifice"
            )
        case .great:
            return CoachingExplanation(
                headline: isClutchSave ? "Clutch only-move save!" : "Only-move precision!",
                detail: "\(playedSan) was the sole sharp move holding the edge—alternatives drop off sharply.",
                tacticalTag: isClutchSave ? "Clutch Defense" : "Only Move"
            )
        case .best:
            return CoachingExplanation(
                headline: "Top engine choice",
                detail: "\(playedSan) maintains optimal piece activity and evaluation (\(evalAfterDisplay)).",
                tacticalTag: "Precision"
            )
        case .excellent:
            return CoachingExplanation(
                headline: "Solid practical move",
                detail: "\(playedSan) keeps the position healthy; \(bestSan) was slightly sharper.",
                tacticalTag: "Solid"
            )
        case .inaccuracy:
            return CoachingExplanation(
                headline: "Slight slip — \(bestSan) was stronger",
                detail: "\(playedSan) gives back \(Int(winLoss.rounded()))% win probability. Prefer \(bestSan) to stay active.",
                tacticalTag: "Inaccuracy"
            )
        case .mistake:
            let tag = detectedMotif ?? "Missed Tactic"
            return CoachingExplanation(
                headline: detectedMotif.map { "\($0) — missed \(bestSan)" } ?? "Tactical mistake — missed \(bestSan)",
                detail: "\(playedSan) drops \(Int(winLoss.rounded()))% win chance (\(evalAfterDisplay)). \(bestSan) kept control.",
                tacticalTag: tag
            )
        case .blunder:
            let tag = detectedMotif ?? "Blunder"
            return CoachingExplanation(
                headline: detectedMotif.map { "Blunder (\($0)) — \(bestSan) was needed" } ?? "Decisive blunder — \(bestSan) was needed",
                detail: "\(playedSan) swings the evaluation to \(evalAfterDisplay) (-\(Int(winLoss.rounded()))% win chance). Rewind and find \(bestSan)!",
                tacticalTag: tag
            )
        }
    }
}
