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
}
