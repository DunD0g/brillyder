import Foundation

public enum VaultHighlightKind: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case brilliant = "brilliant"
    case clutchSave = "clutch"
    case trap = "trap"
    case cleanSweep = "sweep"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .brilliant: return "!! Brilliant"
        case .clutchSave: return "Clutch Saves"
        case .trap: return "Traps"
        case .cleanSweep: return "Clean Sweeps"
        }
    }
}

public struct VaultHighlight: Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: VaultHighlightKind
    public let gameId: String
    public let ply: Int
    public let moveNumber: Int
    public let color: PieceColor
    public let fen: String
    public let san: String
    public let fromSquare: String?
    public let toSquare: String?
    public let classification: MoveClassification?
    public let evalScore: EngineScore?
    public let whiteName: String
    public let blackName: String
    public let whiteAccuracy: Double?
    public let blackAccuracy: Double?
    public let userAccuracy: Double?
    public let userEstimatedElo: Int?
    public let openingName: String?
    public let title: String
    public let subtitle: String
    public let evalDisplay: String
    public let playedAt: Int64

    public init(
        id: String,
        kind: VaultHighlightKind,
        gameId: String,
        ply: Int,
        moveNumber: Int,
        color: PieceColor,
        fen: String,
        san: String,
        fromSquare: String? = nil,
        toSquare: String? = nil,
        classification: MoveClassification? = nil,
        evalScore: EngineScore? = nil,
        whiteName: String = "White",
        blackName: String = "Black",
        whiteAccuracy: Double? = nil,
        blackAccuracy: Double? = nil,
        userAccuracy: Double? = nil,
        userEstimatedElo: Int? = nil,
        openingName: String? = nil,
        title: String,
        subtitle: String,
        evalDisplay: String,
        playedAt: Int64
    ) {
        self.id = id
        self.kind = kind
        self.gameId = gameId
        self.ply = ply
        self.moveNumber = moveNumber
        self.color = color
        self.fen = fen
        self.san = san
        self.fromSquare = fromSquare
        self.toSquare = toSquare
        self.classification = classification
        self.evalScore = evalScore
        self.whiteName = whiteName
        self.blackName = blackName
        self.whiteAccuracy = whiteAccuracy
        self.blackAccuracy = blackAccuracy
        self.userAccuracy = userAccuracy
        self.userEstimatedElo = userEstimatedElo
        self.openingName = openingName
        self.title = title
        self.subtitle = subtitle
        self.evalDisplay = evalDisplay
        self.playedAt = playedAt
    }
}

public struct VaultCollection: Sendable {
    public let brilliants: [VaultHighlight]
    public let clutchSaves: [VaultHighlight]
    public let traps: [VaultHighlight]
    public let cleanSweeps: [VaultHighlight]

    /// Headline Diamond counter strictly reflects ONLY the user's `!!` Brilliant moves.
    public var headlineBrilliantCount: Int {
        brilliants.count
    }
}

public enum VaultService {
    public static func buildVault(
        from analyzedGames: [AnalyzedGame],
        handles: [String]
    ) -> VaultCollection {
        var brilliants: [VaultHighlight] = []
        var clutches: [VaultHighlight] = []
        var traps: [VaultHighlight] = []
        var sweeps: [VaultHighlight] = []

        for ag in analyzedGames where !ag.game.isCustomFenGame && !ag.plies.isEmpty {
            // Strictly attribute highlights ONLY when the user's side is definitively known (never count opponent !! moves!)
            guard let userColor = ag.game.resolvedUserColor(handles: handles) else { continue }
            let opp = userColor == .black ? ag.game.white.name : ag.game.black.name
            let summary = userColor == .white ? ag.whiteSummary : ag.blackSummary

            // Clean Sweep: user won with >= 88% accuracy and 0 blunders
            let res = ag.game.userResult(handles: handles)
            let openingLabel = ag.openingLineDetected ?? ag.game.openingName
            if res == "W" && summary.accuracy >= 88.0 && summary.count(for: .blunder) == 0 && ag.plies.count >= 16 {
                let lastUserPly = ag.plies.last { $0.color == userColor } ?? ag.plies.last
                sweeps.append(VaultHighlight(
                    id: "sweep_\(ag.id)",
                    kind: .cleanSweep,
                    gameId: ag.id,
                    ply: lastUserPly?.ply ?? 1,
                    moveNumber: lastUserPly?.moveNumber ?? 1,
                    color: userColor,
                    fen: lastUserPly?.afterFen ?? ChessBoard.initialFEN,
                    san: lastUserPly?.san ?? "Win",
                    fromSquare: lastUserPly?.from,
                    toSquare: lastUserPly?.to,
                    classification: lastUserPly?.classification,
                    evalScore: lastUserPly?.evalAfter,
                    whiteName: ag.game.white.name,
                    blackName: ag.game.black.name,
                    whiteAccuracy: ag.whiteSummary.accuracy,
                    blackAccuracy: ag.blackSummary.accuracy,
                    userAccuracy: summary.accuracy,
                    userEstimatedElo: summary.estimatedElo,
                    openingName: openingLabel,
                    title: "\(String(format: "%.1f", summary.accuracy))% Clean Sweep vs \(opp)",
                    subtitle: "\(openingLabel) · 0 blunders",
                    evalDisplay: lastUserPly?.evalAfter.display ?? "Win",
                    playedAt: ag.game.createdAt
                ))
            }

            var seenPositions: Set<String> = []

            for (idx, p) in ag.plies.enumerated() where p.color == userColor {
                let moverWinBefore = ChessMath.moverWinPercent(p.evalBefore, mover: p.color)
                let moverWinAfter = ChessMath.moverWinPercent(p.evalAfter, mover: p.color)
                let isClutchCandidate = (p.isClutchSave == true) ||
                    (p.isClutchSave == nil && p.classification == .great && p.secondBestGapWin >= 15 && moverWinBefore <= 62.0 && moverWinAfter >= 30.0)
                let isTrapCandidate: Bool = {
                    guard idx > 0 && p.ply <= 22 && p.winLoss <= 2.0 && moverWinAfter >= 50.0 &&
                          (p.classification == .best || p.classification == .great || p.classification == .brilliant) else { return false }
                    let prev = ag.plies[idx - 1]
                    return prev.classification == .blunder && prev.color != p.color
                }()
                guard p.classification == .brilliant || isClutchCandidate || isTrapCandidate else { continue }

                // Compute ChessBoard positionKey ONLY on highlight candidate plies (avoids O(N*plies) FEN parses on every render!)
                let posKey = (try? ChessBoard(fen: p.afterFen).positionKey) ?? p.afterFen
                guard seenPositions.insert(posKey).inserted else { continue }

                if p.classification == .brilliant {
                    brilliants.append(VaultHighlight(
                        id: "bril_\(ag.id)_\(p.ply)",
                        kind: .brilliant,
                        gameId: ag.id,
                        ply: p.ply,
                        moveNumber: p.moveNumber,
                        color: p.color,
                        fen: p.afterFen,
                        san: p.san,
                        fromSquare: p.from,
                        toSquare: p.to,
                        classification: .brilliant,
                        evalScore: p.evalAfter,
                        whiteName: ag.game.white.name,
                        blackName: ag.game.black.name,
                        whiteAccuracy: ag.whiteSummary.accuracy,
                        blackAccuracy: ag.blackSummary.accuracy,
                        userAccuracy: summary.accuracy,
                        userEstimatedElo: summary.estimatedElo,
                        openingName: openingLabel,
                        title: "\(p.moveNumber)\(p.color == .white ? "." : "...") \(p.san) !! vs \(opp)",
                        subtitle: p.coaching.headline,
                        evalDisplay: p.evalAfter.display,
                        playedAt: ag.game.createdAt
                    ))
                }

                if isClutchCandidate {
                    clutches.append(VaultHighlight(
                        id: "clutch_\(ag.id)_\(p.ply)",
                        kind: .clutchSave,
                        gameId: ag.id,
                        ply: p.ply,
                        moveNumber: p.moveNumber,
                        color: p.color,
                        fen: p.afterFen,
                        san: p.san,
                        fromSquare: p.from,
                        toSquare: p.to,
                        classification: p.classification,
                        evalScore: p.evalAfter,
                        whiteName: ag.game.white.name,
                        blackName: ag.game.black.name,
                        whiteAccuracy: ag.whiteSummary.accuracy,
                        blackAccuracy: ag.blackSummary.accuracy,
                        userAccuracy: summary.accuracy,
                        userEstimatedElo: summary.estimatedElo,
                        openingName: openingLabel,
                        title: "Clutch \(p.san) ! vs \(opp)",
                        subtitle: p.coaching.headline,
                        evalDisplay: p.evalAfter.display,
                        playedAt: ag.game.createdAt
                    ))
                }

                // Trap Punished: opponent blundered in opening (ply <= 22) and user refuted accurately with >= 50% win chance
                if idx > 0 && p.ply <= 22 && p.winLoss <= 2.0 && moverWinAfter >= 50.0 &&
                   (p.classification == .best || p.classification == .great || p.classification == .brilliant) {
                    let prev = ag.plies[idx - 1]
                    if prev.classification == .blunder && prev.color != p.color {
                        traps.append(VaultHighlight(
                            id: "trap_\(ag.id)_\(p.ply)",
                            kind: .trap,
                            gameId: ag.id,
                            ply: p.ply,
                            moveNumber: p.moveNumber,
                            color: p.color,
                            fen: p.afterFen,
                            san: p.san,
                            fromSquare: p.from,
                            toSquare: p.to,
                            classification: p.classification,
                            evalScore: p.evalAfter,
                            whiteName: ag.game.white.name,
                            blackName: ag.game.black.name,
                            whiteAccuracy: ag.whiteSummary.accuracy,
                            blackAccuracy: ag.blackSummary.accuracy,
                            userAccuracy: summary.accuracy,
                            userEstimatedElo: summary.estimatedElo,
                            openingName: openingLabel,
                            title: "Punished \(prev.san) with \(p.san)",
                            subtitle: "\(openingLabel) vs \(opp)",
                            evalDisplay: p.evalAfter.display,
                            playedAt: ag.game.createdAt
                        ))
                    }
                }
            }
        }

        return VaultCollection(
            brilliants: brilliants.sorted { $0.playedAt > $1.playedAt },
            clutchSaves: clutches.sorted { $0.playedAt > $1.playedAt },
            traps: traps.sorted { $0.playedAt > $1.playedAt },
            cleanSweeps: sweeps.sorted { $0.playedAt > $1.playedAt }
        )
    }
}
