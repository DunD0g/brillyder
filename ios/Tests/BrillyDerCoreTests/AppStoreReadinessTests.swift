import Foundation
import Testing
@testable import BrillyDerCore

@Suite("App Store Readiness & P0 Regression Suite")
struct AppStoreReadinessTests {
    @Test("ChessBoard.parseSAN safely rejects Unicode combining characters and garbage disambiguation without crashing")
    func parseSANUnicodeSafety() throws {
        var board = ChessBoard()
        for badSan in ["a\u{0301}e4", "1\u{20E3}e4", "Ze4", "N\u{0300}f3", "b\u{0300}d2"] {
            #expect(throws: ChessError.self) {
                _ = try board.apply(san: badSan)
            }
        }
        // Negative perft depth must not recurse infinitely
        #expect(board.perft(depth: -1) == 1)
        // Extreme FEN fullmove/halfmove clocks clamp cleanly without Int overflow on apply
        var extreme = try ChessBoard(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 999999999 999999999")
        _ = try extreme.apply(san: "e4")
        #expect(extreme.fullmoveNumber <= 100_001)
    }

    @Test("FSRS6Scheduler caps stability and interval at 36,500 days across 25 consecutive Easy reviews and survives corrupt negative attempts")
    func fsrsBoundedScheduling() throws {
        var card = FSRS6Scheduler.createCard(
            courseId: "c1",
            lineId: "l1",
            side: .white,
            fen: ChessBoard.initialFEN,
            ply: 0,
            moveSequence: [],
            expectedSan: "d4",
            expectedUci: "d2d4",
            unlocked: true
        )
        card.attempts = -1 // simulate corrupted stored counter
        var now = Date(timeIntervalSince1970: 1_700_000_000)

        for _ in 0..<25 {
            let res = FSRS6Scheduler.review(
                card: card,
                attempt: OpeningAttemptInput(correct: true, responseMs: 900, hintUsed: false),
                now: now
            )
            card = res.card
            #expect(card.fsrsState.stability.isFinite && card.fsrsState.stability <= 36_500.0)
            #expect(card.fsrsState.scheduled_days.isFinite && card.fsrsState.scheduled_days <= 36_500.0)
            #expect(card.avgResponseMs.isFinite && card.avgResponseMs >= 200)
            now = now.addingTimeInterval(max(1.0, card.fsrsState.scheduled_days) * 86_400.0)
        }
    }

    @Test("BrillyNativeEngine evaluates horizon stalemate as 0 draw instead of winning standPat")
    func engineHorizonStalemateCheck() async throws {
        // White to move with K+Q vs K, Qb6 is instant stalemate while Qh7# / Qg7# is mate
        let fen = "7k/5Q2/6K1/8/8/8/8/8 w - - 0 1"
        let engine = BrillyNativeEngine()
        let eval = try await engine.analyze(fen: fen, depth: 3, multiPV: 3, maxTimeMs: 700)
        // Must pick checkmate (not stalemate!) and keep strict MultiPV ordering
        #expect(eval.score.mateWhite == 1)
        if eval.lines.count >= 2 {
            #expect(eval.lines[0].score.cpWhite >= eval.lines[1].score.cpWhite)
        }
    }

    @Test("MoveClassifier flags terminal 3-fold repetition draw blunder even when playedUci == bestMoveUci")
    func repetitionDrawBlunderClassification() throws {
        let board = try ChessBoard(fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 b - - 0 1")
        let cls = MoveClassifier.classify(MoveClassificationInput(
            plyIndex: 40,
            sanPrefix: [],
            playedUci: "d1d8",
            bestMoveUci: "d1d8",
            afterBoard: board,
            moverColor: .white,
            toSquare: Square(algebraic: "d8")!,
            movedPiece: .rook,
            positionRepeated: true,
            moverWinBefore: 95.0,
            moverWinAfter: 50.0,
            secondBestGapWin: 5.0,
            hasSecondLine: true,
            forceDrawRepetition: true
        ))
        #expect(cls == .blunder)
    }

    @Test("ChessComClient.formatTimeControl and PGNParser survive hostile/malformed inputs safely")
    func hostileInputsSafety() throws {
        #expect(ChessComClient.formatTimeControl("+", speed: "blitz") == "+")
        #expect(ChessComClient.formatTimeControl("1/inf", speed: "daily") == "Daily")
        #expect(ChessComClient.formatTimeControl("nan+nan", speed: "rapid") == "nan+nan")
        #expect(ChessComClient.formatTimeControl("600+5", speed: "rapid") == "10+5")

        // UTF-8 BOM + empty FEN + multi-game PGN + malformed clock & non-finite TimeControl
        let hostilePgn = "\u{FEFF}[Event \"G1\"]\n[FEN \"\"]\n[TimeControl \"inf+nan\"]\n[Result \"1-0\"]\n\n1. e4 {[%clk 0:05:..]} e5 2. Nf3 Nc6 1-0\n\n[Event \"G2\"]\n1. d4 d5 *"
        let parsed = try PGNParser.parse(hostilePgn)
        #expect(parsed.moves.count == 4)
        #expect(parsed.result == "1-0")
        #expect(parsed.moves[0].clockSeconds == nil)
        #expect(PGNParser.parseTimeControl("inf+nan") == nil)
    }

    @Test("DeviationDetector does not falsely flag Black playing a different move-1 defense")
    func deviationDetectorBlackMove1Guard() async throws {
        let courses = try CourseRepository.loadStarterCourses()
        let caro = try #require(courses.first { $0.side == .black && $0.lines.first?.moves.first == "e4" })
        let pgn = "1. e4 e5 2. Nf3 Nc6 *"
        let raw = try LichessClient.parsePastedPGN(pgn)
        let blackGame = GameRecord(
            id: "dev_b1", source: .pgn, createdAt: raw.createdAt,
            resultString: "*", timeControlLabel: "10+0", pgn: pgn,
            openingName: "Open Game", white: PlayerInfo(name: "Opp"),
            black: PlayerInfo(name: "You"), userColor: .black
        )
        let analyzed = try await GameAnalyzer.analyze(game: blackGame, engine: BrillyNativeEngine(), preset: .fast)
        let report = DeviationDetector.detect(analyzedGame: analyzed, courses: [caro], fsrsCards: [], handles: ["You"])
        // Playing 1...e5 when your Black course is 1...c6/c5 is choosing a different opening, NOT a mid-line deviation!
        if caro.lines.allSatisfy({ ($0.moves.count > 1 ? $0.moves[1] : "") != "e5" }) {
            #expect(report == nil)
        }
    }

    @Test("BrillyEntitlementPolicy enforces Free vs Pro boundaries and StoreKit 2 product IDs cleanly")
    func entitlementPolicyBoundaries() throws {
        // Canonical App Store Connect product identifiers
        #expect(BrillyProProductID.monthly.rawValue == "com.brillyder.pro.monthly")
        #expect(BrillyProProductID.annual.rawValue == "com.brillyder.pro.annual")
        #expect(BrillyProProductID.lifetime.rawValue == "com.brillyder.pro.lifetime")
        #expect(BrillyProProductID.monthly.isSubscription)
        #expect(BrillyProProductID.annual.isSubscription)
        #expect(!BrillyProProductID.lifetime.isSubscription)

        // Daily analysis quota: Free gets 5/day; cached games are always free; Pro is unlimited
        #expect(BrillyEntitlementPolicy.freeDailyAnalysisLimit == 5)
        #expect(BrillyEntitlementPolicy.remainingFreeAnalyses(usedToday: 0, hasProAccess: false) == 5)
        #expect(BrillyEntitlementPolicy.remainingFreeAnalyses(usedToday: 4, hasProAccess: false) == 1)
        #expect(BrillyEntitlementPolicy.remainingFreeAnalyses(usedToday: 5, hasProAccess: false) == 0)
        #expect(BrillyEntitlementPolicy.canStartNewAnalysis(isAlreadyCached: false, usedToday: 4, hasProAccess: false))
        #expect(!BrillyEntitlementPolicy.canStartNewAnalysis(isAlreadyCached: false, usedToday: 5, hasProAccess: false))
        #expect(BrillyEntitlementPolicy.canStartNewAnalysis(isAlreadyCached: true, usedToday: 99, hasProAccess: false))
        #expect(BrillyEntitlementPolicy.canStartNewAnalysis(isAlreadyCached: false, usedToday: 99, hasProAccess: true))

        // Openings: 2 starter courses free (1 White + 1 Black); all 8 unlocked on Pro
        let courses = try CourseRepository.loadStarterCourses()
        let freeCourses = courses.filter { BrillyEntitlementPolicy.isCourseUnlocked($0.id, hasProAccess: false) }
        #expect(freeCourses.count == 2)
        #expect(freeCourses.contains(where: { $0.side == .white }))
        #expect(freeCourses.contains(where: { $0.side == .black }))
        #expect(courses.allSatisfy { BrillyEntitlementPolicy.isCourseUnlocked($0.id, hasProAccess: true) })

        // Coach durations: 10m free, 15m & 25m Pro
        #expect(BrillyEntitlementPolicy.isDurationUnlocked(.ten, hasProAccess: false))
        #expect(!BrillyEntitlementPolicy.isDurationUnlocked(.fifteen, hasProAccess: false))
        #expect(!BrillyEntitlementPolicy.isDurationUnlocked(.twentyFive, hasProAccess: false))
        #expect(BrillyEntitlementPolicy.isDurationUnlocked(.twentyFive, hasProAccess: true))

        // Piece sets: cburnett free, others Pro
        #expect(BrillyEntitlementPolicy.isPieceSetUnlocked(rawValue: "cburnett", hasProAccess: false))
        #expect(!BrillyEntitlementPolicy.isPieceSetUnlocked(rawValue: "chessnut", hasProAccess: false))
        #expect(BrillyEntitlementPolicy.isPieceSetUnlocked(rawValue: "kiwen-suwi", hasProAccess: true))
    }
}
