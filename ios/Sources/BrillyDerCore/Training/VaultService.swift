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
    public let title: String
    public let subtitle: String
    public let evalDisplay: String
    public let playedAt: Int64
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
                    title: "\(String(format: "%.1f", summary.accuracy))% Clean Sweep vs \(opp)",
                    subtitle: "\(ag.openingLineDetected ?? ag.game.openingName) · 0 blunders",
                    evalDisplay: lastUserPly?.evalAfter.display ?? "Win",
                    playedAt: ag.game.createdAt
                ))
            }

            var seenBrilliantPositions: Set<String> = []

            for (idx, p) in ag.plies.enumerated() where p.color == userColor {
                let posKey = (try? ChessBoard(fen: p.afterFen).positionKey) ?? p.afterFen
                let moverWinAfter = ChessMath.moverWinPercent(p.evalAfter, mover: p.color)

                if p.classification == .brilliant && !seenBrilliantPositions.contains(posKey) {
                    seenBrilliantPositions.insert(posKey)
                    brilliants.append(VaultHighlight(
                        id: "bril_\(ag.id)_\(p.ply)",
                        kind: .brilliant,
                        gameId: ag.id,
                        ply: p.ply,
                        moveNumber: p.moveNumber,
                        color: p.color,
                        fen: p.afterFen,
                        san: p.san,
                        title: "\(p.moveNumber)\(p.color == .white ? "." : "...") \(p.san) !! vs \(opp)",
                        subtitle: p.coaching.headline,
                        evalDisplay: p.evalAfter.display,
                        playedAt: ag.game.createdAt
                    ))
                }

                if p.isClutchSave == true || (p.classification == .great && p.secondBestGapWin >= 15) {
                    clutches.append(VaultHighlight(
                        id: "clutch_\(ag.id)_\(p.ply)",
                        kind: .clutchSave,
                        gameId: ag.id,
                        ply: p.ply,
                        moveNumber: p.moveNumber,
                        color: p.color,
                        fen: p.afterFen,
                        san: p.san,
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
                            title: "Punished \(prev.san) with \(p.san)",
                            subtitle: "\(ag.openingLineDetected ?? ag.game.openingName) vs \(opp)",
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
