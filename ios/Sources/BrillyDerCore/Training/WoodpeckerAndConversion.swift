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
    public let batchSize: Int
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

    public init(
        id: String,
        createdAt: Int64,
        batchSize: Int,
        puzzleIds: [String],
        currentCycle: Int,
        activeIndex: Int,
        activeStartedAt: Int64?,
        firstTryCount: Int,
        solvedCount: Int,
        completedCycles: [WoodpeckerCompletedCycle],
        cooldownUntil: Int64?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.batchSize = batchSize
        self.puzzleIds = puzzleIds
        self.currentCycle = currentCycle
        self.activeIndex = activeIndex
        self.activeStartedAt = activeStartedAt
        self.firstTryCount = firstTryCount
        self.solvedCount = solvedCount
        self.completedCycles = completedCycles
        self.cooldownUntil = cooldownUntil
    }

    /// Resilient decoder supporting both native iOS records and Web PWA `woodpecker_cycles` (which uses `activeAttemptedIds` and `gameId_ply` IDs).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        self.id = (try? c.decode(String.self, forKey: .init("id"))) ?? "wp_\(Int64(Date().timeIntervalSince1970 * 1000))"
        self.createdAt = (try? c.decode(Int64.self, forKey: .init("createdAt"))) ?? Int64(Date().timeIntervalSince1970 * 1000)
        let rawIds = (try? c.decode([String].self, forKey: .init("puzzleIds"))) ?? []
        self.puzzleIds = rawIds.map(Self.normalizePuzzleId)
        self.batchSize = (try? c.decode(Int.self, forKey: .init("batchSize"))) ?? max(1, rawIds.count)
        self.currentCycle = max(1, (try? c.decode(Int.self, forKey: .init("currentCycle"))) ?? 1)
        self.activeIndex = max(0, (try? c.decode(Int.self, forKey: .init("activeIndex"))) ?? 0)
        self.activeStartedAt = try? c.decodeIfPresent(Int64.self, forKey: .init("activeStartedAt"))
        self.completedCycles = (try? c.decode([WoodpeckerCompletedCycle].self, forKey: .init("completedCycles"))) ?? []
        self.cooldownUntil = try? c.decodeIfPresent(Int64.self, forKey: .init("cooldownUntil"))

        if let ft = try? c.decode(Int.self, forKey: .init("firstTryCount")),
           let sc = try? c.decode(Int.self, forKey: .init("solvedCount")) {
            self.firstTryCount = ft
            self.solvedCount = sc
        } else if let webAttempts = try? c.decode([String: WebAttempt].self, forKey: .init("activeAttemptedIds")) {
            self.firstTryCount = webAttempts.values.filter(\.firstTry).count
            self.solvedCount = webAttempts.values.filter(\.solved).count
        } else {
            self.firstTryCount = 0
            self.solvedCount = 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(batchSize, forKey: .batchSize)
        try c.encode(puzzleIds, forKey: .puzzleIds)
        try c.encode(currentCycle, forKey: .currentCycle)
        try c.encode(activeIndex, forKey: .activeIndex)
        try c.encodeIfPresent(activeStartedAt, forKey: .activeStartedAt)
        try c.encode(firstTryCount, forKey: .firstTryCount)
        try c.encode(solvedCount, forKey: .solvedCount)
        try c.encode(completedCycles, forKey: .completedCycles)
        try c.encodeIfPresent(cooldownUntil, forKey: .cooldownUntil)
    }

    private struct WebAttempt: Decodable {
        let firstTry: Bool
        let solved: Bool
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { self.stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, batchSize, puzzleIds, currentCycle, activeIndex, activeStartedAt, firstTryCount, solvedCount, completedCycles, cooldownUntil
    }

    /// Normalizes Web `"<gameId>_<ply>"` IDs to native `"<gameId>::ply::<ply>"` so imported cycles match native MistakeDeck.
    public static func normalizePuzzleId(_ raw: String) -> String {
        if raw.contains("::ply::") { return raw }
        if let under = raw.lastIndex(of: "_") {
            let suffix = raw[raw.index(after: under)...]
            if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) {
                return "\(raw[..<under])::ply::\(suffix)"
            }
        }
        return raw
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
        let sharp = mistakeDeck.filter { $0.winLoss >= 14.0 }
        let rest = mistakeDeck.filter { $0.winLoss < 14.0 }
        let pool = sharp + rest
        let selected = Array(pool.prefix(max(1, batchSize)))
        guard !selected.isEmpty else { return nil }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        return WoodpeckerCycleRecord(
            id: "wp_\(nowMs)",
            createdAt: nowMs,
            batchSize: selected.count,
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

    /// Extracts positions where the user reached a winning edge (+2.5..+7.5 pawns or non-trivial mate) and later slipped or failed to win.
    public static func extractBlownLeads(
        from analyzedGames: [AnalyzedGame],
        handles: [String]
    ) -> [BlownLeadPosition] {
        var out: [BlownLeadPosition] = []

        for ag in analyzedGames where !ag.game.isCustomFenGame && !ag.plies.isEmpty {
            guard ag.game.resultString != "*",
                  let color = ag.game.resolvedUserColor(handles: handles) ?? ag.game.userColor else { continue }
            let userWon = (color == .white && ag.game.resultString == "1-0")
                || (color == .black && ag.game.resultString == "0-1")
            let opp = color == .black ? ag.game.white.name : ag.game.black.name

            var peakPly: AnalyzedPly? = nil
            var peakCp = 249
            var droppedAfterPeak = false

            for p in ag.plies {
                let cpBefore = color == .white ? p.evalBefore.cpWhite : -p.evalBefore.cpWhite
                let cpAfter = color == .white ? p.evalAfter.cpWhite : -p.evalAfter.cpWhite
                let trivialMate = p.evalBefore.mateWhite.map { abs($0) <= 1 } ?? false
                // Prefer practical winning positions (+2.5..+7.5) so drills don't auto-win on move 1
                if p.color == color && !trivialMate && cpBefore >= 250 && cpBefore <= 750 && cpBefore > peakCp {
                    peakCp = cpBefore
                    peakPly = p
                    droppedAfterPeak = false
                } else if peakPly != nil && (cpBefore < 100 || cpAfter < 100) {
                    droppedAfterPeak = true
                }
            }

            if let peak = peakPly, (!userWon || droppedAfterPeak) {
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
