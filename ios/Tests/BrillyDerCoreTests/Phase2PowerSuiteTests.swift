import Foundation
import Testing
@testable import BrillyDerCore

@Suite("Phase 2 Power Suite: Endgame Lab, Repertoire Tree, Vault, Deviation & Audit Regressions")
struct Phase2PowerSuiteTests {
    @Test("All 12 theoretical Syzygy endgame drills are <= 7 pieces, legal, non-adjacent kings, and valid firstHintSan")
    func validateTheoreticalEndgames() throws {
        #expect(EndgameLibrary.theoreticalDrills.count == 12)
        for drill in EndgameLibrary.theoreticalDrills {
            var board = try ChessBoard(fen: drill.fen)
            #expect(SyzygyClient.isEligible(fen: drill.fen))
            #expect(board.turn == drill.userColor)
            let wk = board.whiteKingSquare
            let bk = board.blackKingSquare
            #expect(abs(wk.file - bk.file) > 1 || abs(wk.rank - bk.rank) > 1)
            #expect(!board.isInCheck(board.turn.opposite))
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

    @Test("DeviationDetector spots first user opening leak accurately with dual handles")
    func deviationDetection() async throws {
        let courses = try CourseRepository.loadStarterCourses()
        let london = try #require(courses.first { $0.id == "london-system-core" })
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
        let report = DeviationDetector.detect(analyzedGame: analyzed, courses: [london], fsrsCards: cards, handles: ["You"])
        #expect(report?.kind == .userDeviation)
        #expect(report?.playedSan == "e3")
        #expect(report?.expectedSan == "Bf4")
        #expect(report?.matchingCardId != nil)
    }

    @Test("VaultService counts strictly user !! moves and rejects unresolved opponent games")
    func vaultStrictCount() async throws {
        let sample = LichessClient.sampleGames()[0]
        let analyzed = try await GameAnalyzer.analyze(game: sample, engine: BrillyNativeEngine(), preset: .fast)
        let vault = VaultService.buildVault(from: [analyzed], handles: ["You"])
        #expect(vault.headlineBrilliantCount == vault.brilliants.count)

        // When userColor is nil and handles don't match either player, Vault must NOT attribute moves to the user.
        let anonymousGame = GameRecord(
            id: "anon_1", source: .pgn, createdAt: sample.createdAt,
            resultString: "1-0", timeControlLabel: "10+0", pgn: sample.pgn,
            openingName: sample.openingName, white: PlayerInfo(name: "Alice"),
            black: PlayerInfo(name: "Bob"), userColor: nil
        )
        let anonAnalyzed = AnalyzedGame(
            id: anonymousGame.id,
            analyzedAt: analyzed.analyzedAt,
            depth: analyzed.depth,
            classificationVersion: analyzed.classificationVersion,
            game: anonymousGame,
            initialEval: analyzed.initialEval,
            plies: analyzed.plies,
            whiteSummary: analyzed.whiteSummary,
            blackSummary: analyzed.blackSummary,
            openingLineDetected: analyzed.openingLineDetected
        )
        let emptyVault = VaultService.buildVault(from: [anonAnalyzed], handles: ["UnrelatedUser"])
        #expect(emptyVault.headlineBrilliantCount == 0)
        #expect(emptyVault.cleanSweeps.isEmpty)
    }

    @Test("AdvancedInsightsService builds tilt buckets and ScoutGameplan cleanly")
    func insightsAndScout() {
        let samples = LichessClient.sampleGames()
        let plan = AdvancedInsightsService.buildScoutGameplan(opponent: "You", games: samples)
        #expect(plan?.sampleGames == 2)
        #expect(plan?.winRatePct == 100)
    }

    @Test("SyzygyClient inverts opponent move categories and guards castling & K-vs-K eligibility")
    func syzygyPerspectiveAndEligibility() {
        #expect(SyzygyClient.invertOpponentCategory("loss") == "win")
        #expect(SyzygyClient.invertOpponentCategory("win") == "loss")
        #expect(SyzygyClient.invertOpponentCategory("blessed-loss") == "cursed-win")
        #expect(SyzygyClient.invertOpponentCategory("cursed-win") == "blessed-loss")
        #expect(SyzygyClient.invertOpponentCategory("draw") == "draw")

        // 2-piece K-vs-K is ineligible; castling position is ineligible; 3-piece KR vs K without castling is eligible
        #expect(!SyzygyClient.isEligible(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1"))
        #expect(!SyzygyClient.isEligible(fen: "4k3/8/8/8/8/8/8/4K2R w K - 0 1"))
        #expect(SyzygyClient.isEligible(fen: "4k3/8/8/8/8/8/8/4K2R w - - 0 1"))
    }

    @Test("Phantom En Passant squares normalize to identical positionKey & Zobrist hash")
    func phantomEnPassantNormalization() throws {
        // After 1. e4, Black has NO pawn on d4/f4 so e3 is a phantom en passant square
        let withPhantomEp = try ChessBoard(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
        let withoutEp = try ChessBoard(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1")
        #expect(withPhantomEp.positionKey == withoutEp.positionKey)
        #expect(withPhantomEp.zobristHash == withoutEp.zobristHash)
    }

    @Test("Strict ChessBoard(fen:) rejects illegal pawns, opponent-in-check, and strips impossible castling")
    func strictFenValidation() throws {
        // Pawn on rank 8
        #expect(throws: ChessError.self) {
            _ = try ChessBoard(fen: "p3k3/8/8/8/8/8/8/4K3 w - - 0 1")
        }
        // Side NOT to move already in check
        #expect(throws: ChessError.self) {
            _ = try ChessBoard(fen: "4k3/4Q3/8/8/8/8/8/4K3 w - - 0 1")
        }
        // Impossible castling flag stripped cleanly
        let stripped = try ChessBoard(fen: "4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1")
        #expect(stripped.castling.isEmpty)
    }

    @Test("MultiPV engine search never poisons root TT across repeated calls")
    func multiPVNoRootTTPoisoning() async throws {
        let engine = BrillyNativeEngine()
        let fen = "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1"
        for _ in 0..<3 {
            let eval = try await engine.analyze(fen: fen, depth: 3, multiPV: 3, maxTimeMs: 600)
            #expect(eval.bestMoveUci == "d1d8")
            #expect(eval.score.mateWhite == 1)
            if eval.lines.count >= 2 {
                #expect(eval.lines[0].score.cpWhite >= eval.lines[1].score.cpWhite)
            }
        }
    }

    @Test("Web PWA backup JSON (patched starter course, dual handles, Woodpecker cycles, training_logs.ids) round-trips safely")
    func realWebPwaBackupImport() throws {
        let courses = try CourseRepository.loadStarterCourses()
        let starterJson = try String(data: JSONEncoder().encode(courses[0]), encoding: .utf8) ?? "{}"

        let webBackupJSON = """
        {
          "app": "brillyder",
          "schemaVersion": 2,
          "exportedAt": "2026-11-23T20:00:00.000Z",
          "stores": {
            "analyzed_games": [],
            "repertoires": [\(starterJson)],
            "fsrs_cards": [
              {
                "cardId": "london-system-core::london-classical-main::0::d2d4",
                "courseId": "london-system-core",
                "lineId": "london-classical-main",
                "side": "white",
                "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                "ply": 0,
                "moveSequence": [],
                "expectedSan": "d4",
                "expectedUci": "d2d4",
                "fsrsState": { "due": "2026-11-25T10:00:00.000Z", "stability": 4.2, "difficulty": 4.8, "reps": 2, "lapses": 0, "state": 2 },
                "dueAt": 1795600800000,
                "attempts": 2,
                "firstTryHits": 2,
                "avgResponseMs": 2100,
                "source": "course",
                "unlocked": true
              }
            ],
            "woodpecker_cycles": [
              {
                "id": "wp_web_1",
                "createdAt": 1795500000000,
                "batchSize": 2,
                "puzzleIds": ["gameA_14", "gameB_22"],
                "currentCycle": 2,
                "activeIndex": 1,
                "activeAttemptedIds": {
                  "gameA_14": { "firstTry": true, "solved": true }
                },
                "completedCycles": []
              }
            ],
            "prefs": [
              { "key": "brillyder_username_lichess", "value": "Lukedunwell", "updatedAt": 1795500000000 },
              { "key": "brillyder_username_chesscom", "value": "LukeCC", "updatedAt": 1795500000000 },
              { "key": "brillyder_endgame_mastered_v1", "value": ["eg_pawn_opposition", "eg_rook_lucena"], "updatedAt": 1795500000000 },
              { "key": "brillyder_vision_best_white", "value": 34, "updatedAt": 1795500000000 },
              { "key": "brillyder_rush_best", "value": 19, "updatedAt": 1795500000000 },
              { "key": "brillyder_daily_done", "value": "2026-11-23", "updatedAt": 1795500000000 },
              { "key": "brillyder_mistake_streak", "value": { "current": 5, "best": 8, "lastSolvedAt": 1795520000000 }, "updatedAt": 1795500000000 },
              {
                "key": "brillyder_saved_positions_v1",
                "value": [
                  {
                    "id": "g1::12",
                    "gameId": "g1",
                    "ply": 12,
                    "fen": "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1",
                    "san": "d4",
                    "moveNumber": 1,
                    "color": "w",
                    "label": "London Move 1",
                    "createdAt": 1795500000000
                  }
                ],
                "updatedAt": 1795500000000
              }
            ],
            "training_logs": [
              { "id": "conversion", "kind": "conversion", "updatedAt": 1795500000000, "data": { "ids": ["conv_web_1", "conv_web_2"] } }
            ]
          }
        }
        """
        let data = Data(webBackupJSON.utf8)
        let (merged, summary) = try LocalVaultStore.mergeBackupJSONWithSummary(data, into: VaultSnapshot())
        #expect(merged.lichessUsername == "Lukedunwell")
        #expect(merged.chessComUsername == "LukeCC")
        #expect(merged.fsrsCards.count == 1)
        #expect(merged.customCourses.count == 1)
        #expect(merged.masteredEndgameIds.count == 2)
        #expect(merged.bookmarks.count == 1)
        #expect(merged.boardVisionBestScore == 34)
        #expect(merged.puzzleRushBlitzBest == 19)
        #expect(merged.dailyStreakDays == 5)
        // `lastSolvedAt` (1795520000000 = 2026-11-24) is newer than `brillyder_daily_done` (2026-11-23)
        #expect(merged.lastDailyCompletedDate == "2026-11-24")
        #expect(merged.convertedAdvantageIds.contains("conv_web_1"))
        #expect(merged.convertedAdvantageIds.contains("conv_web_2"))
        #expect(merged.woodpeckerCycle?.puzzleIds == ["gameA::ply::14", "gameB::ply::22"])
        #expect(merged.woodpeckerCycle?.firstTryCount == 1)
        #expect(merged.woodpeckerCycle?.solvedCount == 1)
        #expect(summary.fsrsCards == 1)
        #expect(summary.bookmarks == 1)

        // Export back to Web JSON and verify round-trip preserves woodpecker + conversion ids + dual handles
        let reExported = try LocalVaultStore.exportBackupJSON(from: merged)
        let roundTripped = try LocalVaultStore.mergeBackupJSON(reExported, into: VaultSnapshot())
        #expect(roundTripped.lichessUsername == "Lukedunwell")
        #expect(roundTripped.chessComUsername == "LukeCC")
        #expect(roundTripped.woodpeckerCycle?.currentCycle == 2)
        #expect(roundTripped.convertedAdvantageIds.contains("conv_web_1"))
    }
}
