import Foundation

public enum DailyDurationMinutes: Int, Codable, CaseIterable, Sendable, Identifiable {
    case ten = 10
    case fifteen = 15
    case twentyFive = 25

    public var id: Int { rawValue }
    public var label: String { "\(rawValue)m" }
}

public struct DailyWorkoutQuotas: Sendable {
    public let openingDue: Int
    public let blunderRewind: Int
    public let speedPatterns: Int
    public let weaknessFocus: Int
}

public struct DailyWorkoutPlan: Sendable {
    public let duration: DailyDurationMinutes
    public let quotas: DailyWorkoutQuotas
    public let stage1OpeningCards: [FsrsOpeningCard]
    public let stage2Blunders: [MistakePuzzle]
    public let stage3SpeedDrills: [MistakePuzzle]
    public let stage4FocusLabel: String
    public let stage4Drills: [MistakePuzzle]

    public var totalTasks: Int {
        stage1OpeningCards.count + stage2Blunders.count + stage3SpeedDrills.count + stage4Drills.count
    }
}

public struct GravityFlashItem: Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: String // "tactic" | "opening"
    public let fen: String
    public let orientation: PieceColor
    public let expectedUci: String
    public let expectedSan: String
    public let prompt: String
    public let subtitle: String
    public let timeLimitSec: Int
    public let cardId: String?
}

public enum DailyCoachPlanner {
    public static func quotas(for duration: DailyDurationMinutes) -> DailyWorkoutQuotas {
        switch duration {
        case .ten:        return DailyWorkoutQuotas(openingDue: 5, blunderRewind: 3, speedPatterns: 6, weaknessFocus: 2)
        case .fifteen:    return DailyWorkoutQuotas(openingDue: 7, blunderRewind: 4, speedPatterns: 8, weaknessFocus: 3)
        case .twentyFive: return DailyWorkoutQuotas(openingDue: 10, blunderRewind: 5, speedPatterns: 12, weaknessFocus: 4)
        }
    }

    /// 4 curated, ChessBoard-verified tactical flashes used in the 60-Second Gravity Check when the personal deck has < 3 puzzles.
    public static let fallbackGravityFlashes: [GravityFlashItem] = [
        GravityFlashItem(
            id: "gravity-fb-1",
            kind: "tactic",
            fen: "r1bqkbnr/pppp1ppp/2n5/4p3/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 0 3",
            orientation: .white,
            expectedUci: "d4e5",
            expectedSan: "dxe5",
            prompt: "Hanging central pawn — grab it fast!",
            subtitle: "Center Capture Flash",
            timeLimitSec: 15,
            cardId: nil
        ),
        GravityFlashItem(
            id: "gravity-fb-2",
            kind: "tactic",
            fen: "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4",
            orientation: .white,
            expectedUci: "h5f7",
            expectedSan: "Qxf7#",
            prompt: "Checkmate in 1 — spot the exposed f7 square!",
            subtitle: "Mate-in-1 Flash",
            timeLimitSec: 15,
            cardId: nil
        ),
        GravityFlashItem(
            id: "gravity-fb-3",
            kind: "tactic",
            fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1",
            orientation: .white,
            expectedUci: "d1d8",
            expectedSan: "Rd8#",
            prompt: "Back-rank checkmate — deliver the blow!",
            subtitle: "Back-Rank Flash",
            timeLimitSec: 15,
            cardId: nil
        ),
        GravityFlashItem(
            id: "gravity-fb-4",
            kind: "tactic",
            fen: "r2qk2r/ppp2ppp/2n2n2/3pp3/1b1P4/2NBPN2/PPP2PPP/R1BQK2R w KQkq - 0 6",
            orientation: .white,
            expectedUci: "d4e5",
            expectedSan: "dxe5",
            prompt: "Win the hanging e5 pawn with tempo on f6!",
            subtitle: "Hanging Piece Flash",
            timeLimitSec: 15,
            cardId: nil
        ),
    ]

    public static func buildPlan(
        duration: DailyDurationMinutes = .fifteen,
        fsrsCards: [FsrsOpeningCard],
        mistakeDeck: [MistakePuzzle],
        now: Date = Date()
    ) -> DailyWorkoutPlan {
        let q = quotas(for: duration)
        let dueCards = fsrsCards
            .filter { FSRS6Scheduler.isCardDue($0, now: now) }
            .sorted { $0.dueAt < $1.dueAt }

        let stage1: [FsrsOpeningCard]
        if !dueCards.isEmpty {
            stage1 = Array(dueCards.prefix(q.openingDue))
        } else {
            // Surface first unlocked/learning cards if none are due right now
            stage1 = Array(fsrsCards.prefix(q.openingDue))
        }

        var usedIds = Set<String>()
        func pick(_ pool: [MistakePuzzle], count: Int) -> [MistakePuzzle] {
            var chosen: [MistakePuzzle] = []
            for p in pool where !usedIds.contains(p.id) {
                if chosen.count >= count { break }
                chosen.append(p)
                usedIds.insert(p.id)
            }
            return chosen
        }

        let blunders = mistakeDeck.filter { $0.classification == .blunder }
        let stage2 = pick(blunders + mistakeDeck, count: q.blunderRewind)
        let stage3 = pick(mistakeDeck, count: q.speedPatterns)

        // Stage 4 targets weakest phase (endgame errors first, then middlegame tactics)
        let endgameMistakes = mistakeDeck.filter { $0.phase == .endgame }
        let stage4FocusLabel = endgameMistakes.count >= 2 ? "Endgame Precision" : "Tactical Sharpness"
        let stage4 = pick(endgameMistakes.count >= 2 ? endgameMistakes : mistakeDeck, count: q.weaknessFocus)

        return DailyWorkoutPlan(
            duration: duration,
            quotas: q,
            stage1OpeningCards: stage1,
            stage2Blunders: stage2,
            stage3SpeedDrills: stage3,
            stage4FocusLabel: stage4FocusLabel,
            stage4Drills: stage4
        )
    }

    public static func buildGravityCheckFlashes(
        fsrsCards: [FsrsOpeningCard],
        mistakeDeck: [MistakePuzzle],
        now: Date = Date()
    ) -> [GravityFlashItem] {
        var items: [GravityFlashItem] = []

        // Up to 3 personal mistake flashes, topped up with verified curated flashes
        for p in mistakeDeck.prefix(3) {
            items.append(GravityFlashItem(
                id: "grav_\(p.id)",
                kind: "tactic",
                fen: p.fen,
                orientation: p.playerColor,
                expectedUci: p.bestMoveUci,
                expectedSan: p.bestMoveSan,
                prompt: "You played \(p.playedSan). Find the stronger move!",
                subtitle: "\(p.openingName) · Move \(p.moveNumber)",
                timeLimitSec: 15,
                cardId: nil
            ))
        }
        for fb in fallbackGravityFlashes where items.count < 3 {
            items.append(fb)
        }

        // Add 1 due opening memory flash if available
        if let due = fsrsCards.first(where: { FSRS6Scheduler.isCardDue($0, now: now) }) ?? fsrsCards.first {
            items.append(GravityFlashItem(
                id: "grav_open_\(due.cardId)",
                kind: "opening",
                fen: due.fen,
                orientation: due.side.pieceColor,
                expectedUci: due.expectedUci,
                expectedSan: due.expectedSan,
                prompt: "Opening recall — play your repertoire move!",
                subtitle: "Move \(due.ply / 2 + 1) · \(due.side.rawValue.capitalized)",
                timeLimitSec: 15,
                cardId: due.cardId
            ))
        }

        return items
    }
}
