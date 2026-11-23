import Foundation
import Testing
@testable import BrillyDerCore

@Suite("FSRS-6 Scheduler, Daily Coach & Web <-> iOS Backup")
struct FSRSAndBackupTests {
    @Test("FSRS-6 response-time auto-grading matches BrillyDer thresholds")
    func responseTimeGrading() {
        #expect(FSRS6Scheduler.gradeAttempt(.init(correct: false, responseMs: 1200)) == .again)
        #expect(FSRS6Scheduler.gradeAttempt(.init(correct: true, responseMs: 2500, hintUsed: true)) == .hard)
        #expect(FSRS6Scheduler.gradeAttempt(.init(correct: true, responseMs: 11500)) == .hard)
        #expect(FSRS6Scheduler.gradeAttempt(.init(correct: true, responseMs: 5000)) == .good)
        #expect(FSRS6Scheduler.gradeAttempt(.init(correct: true, responseMs: 1800)) == .easy)
    }

    @Test("FSRS-6 review schedules future interval and increments stability")
    func reviewProgressesCard() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let card = FSRS6Scheduler.createCard(
            courseId: "london-system-core",
            lineId: "london-classical-main",
            side: .white,
            fen: ChessBoard.initialFEN,
            ply: 0,
            moveSequence: [],
            expectedSan: "d4",
            expectedUci: "d2d4",
            unlocked: true,
            now: now
        )
        #expect(FSRS6Scheduler.isCardDue(card, now: now))

        let r1 = FSRS6Scheduler.review(card: card, attempt: .init(correct: true, responseMs: 1900), now: now)
        #expect(r1.rating == .easy)
        #expect(r1.card.attempts == 1)
        #expect(r1.card.firstTryHits == 1)
        #expect(r1.nextDueAt > card.dueAt)
        #expect(r1.recallPct >= 95)
    }

    @Test("DailyCoachPlanner respects 10m / 15m / 25m quotas and builds Gravity Check")
    func dailyCoachPlanning() throws {
        let courses = try CourseRepository.loadStarterCourses()
        let cards = try CourseRepository.hydrateCourseCards(course: courses[0], unlocked: true)
        let plan15 = DailyCoachPlanner.buildPlan(duration: .fifteen, fsrsCards: cards, mistakeDeck: [])
        #expect(plan15.stage1OpeningCards.count == 7)

        let flashes = DailyCoachPlanner.buildGravityCheckFlashes(fsrsCards: cards, mistakeDeck: [])
        #expect(flashes.count == 4) // 3 fallback tactics + 1 due opening flash
    }

    @Test("Web PWA <-> iOS Backup JSON round-trips cleanly with smart merge")
    func backupRoundTrip() throws {
        let courses = try CourseRepository.loadStarterCourses()
        let cards = Array(try CourseRepository.hydrateCourseCards(course: courses[0], unlocked: true).prefix(3))
        let original = VaultSnapshot(
            analyzedGames: [],
            fsrsCards: cards,
            customCourses: [],
            bookmarks: [],
            dailyStreakDays: 4,
            lastDailyCompletedDate: "2026-11-23",
            lichessUsername: "MagnusTest",
            chessComUsername: "HikaruTest"
        )

        let jsonData = try LocalVaultStore.exportBackupJSON(from: original)
        let merged = try LocalVaultStore.mergeBackupJSON(jsonData, into: VaultSnapshot())
        #expect(merged.fsrsCards.count == 3)
        #expect(merged.lichessUsername == "MagnusTest")
        #expect(merged.chessComUsername == "HikaruTest")
    }

    @Test("DailyCoachPlanner validates legal UCI moves, rejects phantom arrows, computes authoritative FEN move numbers, and replays opponent last move")
    func dailyCoachLegalityAndContext() throws {
        // Position after 7. O-O in King's Indian (Black to move on Move 7, b8 is empty so b8c6 is ILLEGAL)
        let moves = ["d4", "Nf6", "c4", "g6", "Nc3", "Bg7", "e4", "d6", "Nf3", "O-O", "Be2", "e5", "O-O"]
        var b = ChessBoard()
        for m in moves { _ = try b.apply(san: m) }
        let fen = b.fen

        // Authoritative move number must be 7 even if fallbackPly is stale (e.g. 4)
        #expect(DailyCoachPlanner.authoritativeMoveNumber(fen: fen, fallbackPly: 4) == 7)

        // Preceding opponent move must be White's castling O-O (e1 -> g1)
        let prev = try #require(DailyCoachPlanner.precedingMove(for: moves))
        #expect(prev.san == "O-O")
        #expect(prev.from.algebraic == "e1")
        #expect(prev.to.algebraic == "g1")

        // Legal check accepts b8c6 when knight is on b8, rejects phantom arrows from empty square (e.g. a1a5)
        #expect(DailyCoachPlanner.legalMove(uci: "b8c6", on: b) != nil)
        #expect(DailyCoachPlanner.legalMove(uci: "a1a5", on: b) == nil)

        // buildPlan must filter out cards whose expectedUci is illegal on their FEN
        let corruptCard = FSRS6Scheduler.createCard(
            courseId: "c1", lineId: "l1", side: .black, fen: fen, ply: 13,
            moveSequence: moves, expectedSan: "Ra5", expectedUci: "a1a5", unlocked: true
        )
        let validCard = FSRS6Scheduler.createCard(
            courseId: "c1", lineId: "l1", side: .black, fen: fen, ply: 13,
            moveSequence: moves, expectedSan: "Nc6", expectedUci: "b8c6", unlocked: true
        )
        let plan = DailyCoachPlanner.buildPlan(duration: .fifteen, fsrsCards: [corruptCard, validCard], mistakeDeck: [])
        #expect(plan.stage1OpeningCards.count == 1)
        #expect(plan.stage1OpeningCards[0].cardId == validCard.cardId)
    }
}
