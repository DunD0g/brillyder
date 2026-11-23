import Foundation

public struct TiltBucket: Hashable, Sendable, Identifiable {
    public var id: String { label }
    public let label: String // "0L" | "1L" | "2L" | "3L+"
    public let games: Int
    public let winRatePct: Double
}

public struct MotifLeak: Hashable, Sendable, Identifiable {
    public var id: String { tag }
    public let tag: String
    public let count: Int
    public let avgWinLoss: Double
}

public struct EndgameWeaknessItem: Hashable, Sendable, Identifiable {
    public var id: String { category.rawValue }
    public let category: EndgameCategory
    public let moves: Int
    public let errors: Int
    public let accuracy: Double
}

public struct AdvancedInsightsReport: Sendable {
    public let impulseBlunders: Int
    public let timeTroubleBlunders: Int
    public let tiltBuckets: [TiltBucket]
    public let currentLossStreak: Int
    public let missedMotifs: [MotifLeak]
    public let endgameWeaknesses: [EndgameWeaknessItem]
}

public struct ScoutGameplan: Sendable {
    public let opponentName: String
    public let sampleGames: Int
    public let winRatePct: Double
    public let favoriteWhiteOpenings: [(name: String, games: Int, winRate: Double)]
    public let favoriteBlackOpenings: [(name: String, games: Int, winRate: Double)]
    public let softestTarget: String
    public let tacticalSummary: String
}

public enum AdvancedInsightsService {
    public static func buildReport(
        analyzedGames: [AnalyzedGame],
        handles: [String]
    ) -> AdvancedInsightsReport {
        var impulse = 0
        var timeTrouble = 0
        var motifMap: [String: (count: Int, lossSum: Double)] = [:]
        var egMap: [EndgameCategory: (moves: Int, errors: Int, accSum: Double)] = [:]

        let valid = analyzedGames
            .filter { !$0.game.isCustomFenGame && !$0.plies.isEmpty }
            .sorted { $0.game.createdAt < $1.game.createdAt }

        var priorLosses = 0
        var tiltData: [Int: (games: Int, wins: Int)] = [0: (0, 0), 1: (0, 0), 2: (0, 0), 3: (0, 0)]

        for ag in valid {
            guard let color = ag.game.resolvedUserColor(handles: handles) ?? ag.game.userColor else { continue }
            let res = ag.game.userResult(handles: handles)
            if res == "W" || res == "D" || res == "L" {
                let bucketKey = min(3, priorLosses)
                var b = tiltData[bucketKey] ?? (0, 0)
                b.games += 1
                if res == "W" { b.wins += 1 }
                tiltData[bucketKey] = b

                if res == "L" { priorLosses += 1 }
                else { priorLosses = 0 } // Reset streak on wins AND draws
            }

            for p in ag.plies where p.color == color {
                let isSevere = p.classification == .blunder || p.classification == .mistake
                if isSevere {
                    if let rem = p.clockSeconds, rem < 60.0 {
                        timeTrouble += 1
                    } else if let spent = p.timeSpentSeconds, let rem = p.clockSeconds, spent < 5.0 && rem > 180.0 {
                        impulse += 1
                    }
                    let tag = p.coaching.tacticalTag
                    var m = motifMap[tag] ?? (0, 0)
                    m.count += 1
                    m.lossSum += p.winLoss
                    motifMap[tag] = m
                }

                if p.phase == .endgame {
                    let cat = EndgameLibrary.classifyCategory(fen: p.beforeFen)
                    var e = egMap[cat] ?? (0, 0, 0)
                    e.moves += 1
                    if isSevere { e.errors += 1 }
                    e.accSum += p.accuracy
                    egMap[cat] = e
                }
            }
        }

        let labels = ["0L", "1L", "2L", "3L+"]
        let buckets: [TiltBucket] = (0...3).map { k in
            let row = tiltData[k] ?? (0, 0)
            let pct = row.games > 0 ? (Double(row.wins) / Double(row.games) * 100.0).rounded() : 0
            return TiltBucket(label: labels[k], games: row.games, winRatePct: pct)
        }

        let motifs = motifMap.map { tag, d in
            MotifLeak(tag: tag, count: d.count, avgWinLoss: (d.lossSum / Double(max(1, d.count))).rounded())
        }
        .sorted { $0.count > $1.count }
        .prefix(5)

        let egWeaknesses = egMap.map { cat, d in
            EndgameWeaknessItem(
                category: cat,
                moves: d.moves,
                errors: d.errors,
                accuracy: ((d.accSum / Double(max(1, d.moves))) * 10.0).rounded() / 10.0
            )
        }
        .sorted { $0.accuracy < $1.accuracy }

        return AdvancedInsightsReport(
            impulseBlunders: impulse,
            timeTroubleBlunders: timeTrouble,
            tiltBuckets: buckets,
            currentLossStreak: priorLosses,
            missedMotifs: Array(motifs),
            endgameWeaknesses: egWeaknesses
        )
    }

    public static func buildScoutGameplan(
        opponent: String,
        games: [GameRecord]
    ) -> ScoutGameplan? {
        let target = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !games.isEmpty else { return nil }
        let low = target.lowercased()

        var whiteOps: [String: (games: Int, score: Double)] = [:]
        var blackOps: [String: (games: Int, score: Double)] = [:]
        var total = 0
        var totalScore = 0.0

        for g in games where g.resultString != "*" {
            let isWhite = g.white.name.lowercased() == low
            let isBlack = g.black.name.lowercased() == low
            guard isWhite || isBlack else { continue }
            total += 1
            let pts: Double
            if g.resultString == "1/2-1/2" { pts = 0.5 }
            else if (isWhite && g.resultString == "1-0") || (isBlack && g.resultString == "0-1") { pts = 1.0 }
            else { pts = 0.0 }
            totalScore += pts

            let op = g.openingName
            if isWhite {
                var e = whiteOps[op] ?? (0, 0)
                e.games += 1
                e.score += pts
                whiteOps[op] = e
            } else {
                var e = blackOps[op] ?? (0, 0)
                e.games += 1
                e.score += pts
                blackOps[op] = e
            }
        }
        guard total > 0 else { return nil }

        func rank(_ map: [String: (games: Int, score: Double)]) -> [(name: String, games: Int, winRate: Double)] {
            map.map { name, d in
                (name, d.games, (d.score / Double(max(1, d.games)) * 100.0).rounded())
            }
            .sorted { $0.games > $1.games }
        }

        let allWhite = rank(whiteOps)
        let allBlack = rank(blackOps)
        let candidates: [(label: String, games: Int, scorePct: Double)] =
            allWhite.filter { $0.games >= 2 }.map { ("\($0.name) (as White)", $0.games, $0.winRate) } +
            allBlack.filter { $0.games >= 2 }.map { ("\($0.name) (as Black)", $0.games, $0.winRate) }

        let softest = candidates.sorted { $0.scorePct < $1.scorePct }.first
            .map { "\($0.label) — \(Int($0.scorePct))% score" }
            ?? "Mixed repertoire — stick to your main lines"

        let overallScore = (totalScore / Double(total) * 100.0).rounded()
        let summary = "Scouted \(total) scored games (\(Int(overallScore))% score). Target \(softest)."

        return ScoutGameplan(
            opponentName: target,
            sampleGames: total,
            winRatePct: overallScore,
            favoriteWhiteOpenings: Array(allWhite.prefix(3)),
            favoriteBlackOpenings: Array(allBlack.prefix(3)),
            softestTarget: softest,
            tacticalSummary: summary
        )
    }
}
