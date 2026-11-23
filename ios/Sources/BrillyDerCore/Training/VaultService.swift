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
        username: String?
    ) -> VaultCollection {
        var brilliants: [VaultHighlight] = []
        var clutches: [VaultHighlight] = []
        var traps: [VaultHighlight] = []
        var sweeps: [VaultHighlight] = []

        let low = username?.trimmingCharacters(in: .whitespaces).lowercased()

        for ag in analyzedGames {
            let userColor: PieceColor? = ag.game.userColor ?? {
                guard let low, !low.isEmpty else { return nil }
                if ag.game.white.name.lowercased() == low { return .white }
                if ag.game.black.name.lowercased() == low { return .black }
                return nil
            }()
            let opp = userColor == .black ? ag.game.white.name : ag.game.black.name
            let effectiveColor = userColor ?? .white
            let summary = effectiveColor == .white ? ag.whiteSummary : ag.blackSummary

            // Clean Sweep: user won with >= 88% accuracy and 0 blunders
            let res = ag.game.userResult(for: username)
            if res == "W" && summary.accuracy >= 88.0 && summary.count(for: .blunder) == 0 && ag.plies.count >= 16 {
                let lastPly = ag.plies.last
                sweeps.append(VaultHighlight(
                    id: "sweep_\(ag.id)",
                    kind: .cleanSweep,
                    gameId: ag.id,
                    ply: lastPly?.ply ?? 1,
                    moveNumber: lastPly?.moveNumber ?? 1,
                    color: effectiveColor,
                    fen: lastPly?.afterFen ?? ChessBoard.initialFEN,
                    san: lastPly?.san ?? "Win",
                    title: "\(String(format: "%.1f", summary.accuracy))% Clean Sweep vs \(opp)",
                    subtitle: "\(ag.openingLineDetected ?? ag.game.openingName) · 0 blunders",
                    evalDisplay: lastPly?.evalAfter.display ?? "Win",
                    playedAt: ag.game.createdAt
                ))
            }

            for (idx, p) in ag.plies.enumerated() {
                if let userColor, p.color != userColor { continue }

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
                        title: "\(p.moveNumber)\(p.color == .white ? "." : "...") \(p.san) !! vs \(opp)",
                        subtitle: p.coaching.headline,
                        evalDisplay: p.evalAfter.display,
                        playedAt: ag.game.createdAt
                    ))
                } else if p.isClutchSave == true || (p.classification == .great && p.secondBestGapWin >= 15) {
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

                // Trap Punished: opponent blundered in opening (ply <= 20) and user immediately played Best/Great/Brilliant
                if idx > 0 && p.ply <= 22 && (p.classification == .best || p.classification == .great || p.classification == .brilliant) {
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
