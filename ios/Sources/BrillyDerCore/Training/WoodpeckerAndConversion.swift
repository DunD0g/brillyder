import Foundation

public struct WoodpeckerCompletedCycle: Codable, Hashable, Sendable, Identifiable {
    public var id: Int { cycleNumber }
    public let cycleNumber: Int
    public let completedAt: Int64
    public let elapsedSeconds: Int
    public let accuracyPct: Int
    public let firstTryPct: Int
    public let solvedCount: Int
    public let totalCount: Int

    public init(
        cycleNumber: Int,
        completedAt: Int64,
        elapsedSeconds: Int,
        accuracyPct: Int,
        firstTryPct: Int,
        solvedCount: Int,
        totalCount: Int
    ) {
        self.cycleNumber = cycleNumber
        self.completedAt = completedAt
        self.elapsedSeconds = elapsedSeconds
        self.accuracyPct = accuracyPct
        self.firstTryPct = firstTryPct
        self.solvedCount = solvedCount
        self.totalCount = totalCount
    }
}

public struct WoodpeckerCycleRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let createdAt: Int64
    public let batchSize: Int // 30 | 50 | 100
    public let puzzleIds: [String]
    public var currentCycle: Int
    public var activeIndex: Int
    public var activeStartedAt: Int64?
    public var firstTryCount: Int
    public var solvedCount: Int
    public var completedCycles: [WoodpeckerCompletedCycle]
    public var cooldownUntil: Int64?

    public var isOnCooldown: Bool {
        guard let until = cooldownUntil else { return false }
        return Int64(Date().timeIntervalSince1970 * 1000.0) < until
    }
}

public struct BlownLeadPosition: Hashable, Sendable, Identifiable {
    public let id: String
    public let gameId: String
    public let ply: Int
    public let moveNumber: Int
    public let userColor: PieceColor
    public let fen: String
    public let peakEvalDisplay: String
    public let peakCpForUser: Int
    public let opponentName: String
    public let openingName: String
    public let playedAt: Int64
}

public enum WoodpeckerAndConversion {
    public static func createFrozenCycle(
        from mistakeDeck: [MistakePuzzle],
        batchSize: Int = 30
    ) -> WoodpeckerCycleRecord? {
        // Prefer sharp, solvable tactics (winLoss >= 14%), topped up with remaining mistakes
        let sharp = mistakeDeck.filter { $0.winLoss >= 14.0 }
        let pool = sharp.count >= 6 ? sharp : mistakeDeck
        let selected = Array(pool.prefix(max(1, batchSize)))
        guard !selected.isEmpty else { return nil }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        return WoodpeckerCycleRecord(
            id: "wp_\(nowMs)",
            createdAt: nowMs,
            batchSize: batchSize,
            puzzleIds: selected.map(\.id),
            currentCycle: 1,
            activeIndex: 0,
            activeStartedAt: nowMs,
            firstTryCount: 0,
            solvedCount: 0,
            completedCycles: [],
            cooldownUntil: nil
        )
    }

    /// Extracts positions where the user reached a winning edge (>= +2.5 pawns) and later failed to win.
    public static func extractBlownLeads(
        from analyzedGames: [AnalyzedGame],
        username: String?
    ) -> [BlownLeadPosition] {
        var out: [BlownLeadPosition] = []
        let low = username?.trimmingCharacters(in: .whitespaces).lowercased()

        for ag in analyzedGames {
            let color: PieceColor = ag.game.userColor ?? {
                if let low, !low.isEmpty {
                    if ag.game.white.name.lowercased() == low { return .white }
                    if ag.game.black.name.lowercased() == low { return .black }
                }
                return .white
            }()

            let res = ag.game.userResult(for: username)
            let opp = color == .black ? ag.game.white.name : ag.game.black.name

            // Find peak winning position where it's the user's turn to move (>= +250 cp) that later dropped below +100 cp
            var peakPly: AnalyzedPly? = nil
            var peakCp = 249
            var droppedAfterPeak = false

            for p in ag.plies {
                let cpForUser = color == .white ? p.evalBefore.cpWhite : -p.evalBefore.cpWhite
                if p.color == color && cpForUser >= 250 && cpForUser > peakCp && p.evalBefore.mateWhite == nil {
                    peakCp = cpForUser
                    peakPly = p
                    droppedAfterPeak = false
                } else if peakPly != nil && cpForUser < 100 {
                    droppedAfterPeak = true
                }
            }

            if let peak = peakPly, (res != "W" || droppedAfterPeak) {
                out.append(BlownLeadPosition(
                    id: "conv_\(ag.id)_\(peak.ply)",
                    gameId: ag.id,
                    ply: peak.ply,
                    moveNumber: peak.moveNumber,
                    userColor: color,
                    fen: peak.beforeFen,
                    peakEvalDisplay: peak.evalBefore.display,
                    peakCpForUser: peakCp,
                    opponentName: opp,
                    openingName: ag.openingLineDetected ?? ag.game.openingName,
                    playedAt: ag.game.createdAt
                ))
            }
        }
        return out.sorted { $0.playedAt > $1.playedAt }
    }
}
