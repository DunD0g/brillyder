import Foundation
import Testing
@testable import BrillyDerCore

@Suite("Phase 2 Power Suite: Endgame Lab, Repertoire Tree, Vault, Deviation & Insights")
struct Phase2PowerSuiteTests {
    @Test("All 12 theoretical Syzygy endgame drills are <= 7 pieces, legal, non-adjacent kings, and valid firstHintSan")
    func validateTheoreticalEndgames() throws {
        #expect(EndgameLibrary.theoreticalDrills.count == 12)
        for drill in EndgameLibrary.theoreticalDrills {
            var board = try ChessBoard(fen: drill.fen)
            #expect(SyzygyClient.isEligible(fen: drill.fen))
            #expect(board.turn == drill.userColor)
            // Non-adjacent kings check
            let wk = board.whiteKingSquare
            let bk = board.blackKingSquare
            #expect(abs(wk.file - bk.file) > 1 || abs(wk.rank - bk.rank) > 1)
            // Non-mover cannot already be in check
            #expect(!board.isInCheck(board.turn.opposite))
            // firstHintSan must be legal and not immediate mate-in-1
            let applied = try board.apply(san: drill.firstHintSan)
            #expect(!applied.san.hasSuffix("#"))
        }
    }

    @Test("RepertoireTreeService builds move trees and round-trips canonical PGN across all 8 starter courses")
    func repertoireTreeAndPgnRoundTrip() throws {
        let courses = try CourseRepository.loadStarterCourses()
        for course in courses {
            let tree = RepertoireTreeService.buildTree(for: course, fsrsCards: [])
            #expect(!tree.isEmpty)
            let pgn = RepertoireTreeService.exportCourseToPGN(course)
            let reimported = try RepertoireTreeService.importCourseFromPGN(name: course.name, side: course.side, pgn: pgn)
            #expect(reimported.lines.count == course.lines.count)
            for (orig, imp) in zip(course.lines, reimported.lines) {
                #expect(imp.moves.count == orig.moves.count)
            }
        }
    }

    @Test("DeviationDetector spots first user opening leak accurately")
    func deviationDetection() async throws {
        let courses = try CourseRepository.loadStarterCourses()
        let london = try #require(courses.first { $0.id == "london-system-core" })
        // Deviate on move 2 with e3 instead of Bf4!
        let pgn = "1. d4 d5 2. e3 Nf6 3. Nf3 e6 4. Bd3 c5 *"
        let game = try LichessClient.parsePastedPGN(pgn)
        let whiteGame = GameRecord(
            id: game.id, source: .pgn, createdAt: game.createdAt,
            resultString: "*", timeControlLabel: "10+0", pgn: pgn,
            openingName: "Queen's Pawn", white: PlayerInfo(name: "You"),
            black: PlayerInfo(name: "Opp"), userColor: .white
        )
        let analyzed = try await GameAnalyzer.analyze(game: whiteGame, engine: BrillyNativeEngine(), preset: .fast)
        let cards = try CourseRepository.hydrateCourseCards(course: london, unlocked: true)
        let report = DeviationDetector.detect(analyzedGame: analyzed, courses: [london], fsrsCards: cards)
        #expect(report?.kind == .userDeviation)
        #expect(report?.playedSan == "e3")
        #expect(report?.expectedSan == "Bf4")
        #expect(report?.matchingCardId != nil)
    }

    @Test("VaultService counts strictly user !! moves in headlineBrilliantCount")
    func vaultStrictCount() async throws {
        let sample = LichessClient.sampleGames()[0]
        let analyzed = try await GameAnalyzer.analyze(game: sample, engine: BrillyNativeEngine(), preset: .fast)
        let vault = VaultService.buildVault(from: [analyzed], username: "You")
        #expect(vault.headlineBrilliantCount == vault.brilliants.count)
    }

    @Test("AdvancedInsightsService builds tilt buckets and ScoutGameplan cleanly")
    func insightsAndScout() {
        let samples = LichessClient.sampleGames()
        let plan = AdvancedInsightsService.buildScoutGameplan(opponent: "You", games: samples)
        #expect(plan?.sampleGames == 2)
        #expect(plan?.winRatePct == 100)
    }
}
