import Foundation
import Testing
@testable import BrillyDerCore

@Suite("Native Engine, Accuracy Math & Move Classifier")
struct EngineAndClassificationTests {
    @Test("BrillyNativeEngine spots Mate in 1 instantly")
    func spotsMateInOne() async throws {
        let engine = BrillyNativeEngine()
        let fen = "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1"
        let eval = try await engine.analyze(fen: fen, depth: 3, multiPV: 2, maxTimeMs: 500)
        #expect(eval.bestMoveUci == "d1d8")
        #expect(eval.score.mateWhite == 1)
        #expect(eval.lines.count >= 2)
    }

    @Test("BrillyNativeEngine wins a hanging Queen cleanly")
    func winsHangingQueen() async throws {
        let engine = BrillyNativeEngine()
        let fen = "4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1"
        let eval = try await engine.analyze(fen: fen, depth: 3, multiPV: 2, maxTimeMs: 500)
        #expect(eval.bestMoveUci == "d2d5")
        // After Rxd5, White is cleanly up a full Rook (~+500 cp)
        #expect(eval.score.cpWhite > 400)
    }

    @Test("BrillyNativeEngine finds forced Mate in 2")
    func spotsMateInTwo() async throws {
        let engine = BrillyNativeEngine()
        // White: Kh1, Qf6, Re1; Black: Kh7, pawns g7, h6 -> Re7 leads to Qxg7#
        let fen = "8/6pk/5Q1p/8/8/8/8/4R2K w - - 0 1"
        let eval = try await engine.analyze(fen: fen, depth: 4, multiPV: 1, maxTimeMs: 800)
        #expect(eval.score.mateWhite == 2 || eval.score.cpWhite > 1500)
        #expect(eval.bestMoveUci == "e1e7" || eval.bestMoveUci == "f6g7")
    }

    @Test("Pawn promotion capture bxa8=Q is NOT falsely flagged as a Queen sacrifice")
    func promotionCaptureNotFalseSacrifice() throws {
        var board = try ChessBoard(fen: "r3k3/1P6/8/8/8/8/8/4K3 w - - 0 1")
        let applied = try board.apply(uci: "b7a8q")
        let isSac = MoveClassifier.isSacrificeMove(
            afterBoard: board,
            mover: .white,
            toSquare: applied.move.to,
            movedPiece: applied.piece.type,
            capturedPiece: applied.captured?.type,
            promotionPiece: applied.move.promotion
        )
        #expect(!isSac)
    }

    @Test("SEE prefers Queen promotion before underpromotion on capture square")
    func seePrefersQueenPromotion() throws {
        let board = try ChessBoard(fen: "r3k3/1P6/8/8/8/8/8/4K3 w - - 0 1")
        let gain = ChessMath.legalCaptureGainOnSquare(board: board, square: .a8)
        // Rook (5) + Queen promo surplus (9 - 1 = 8) = 13
        #expect(gain == 13)
    }

    @Test("End-to-end GameAnalyzer produces summaries and mistake puzzles")
    func analyzeSampleGame() async throws {
        let sample = LichessClient.sampleGames()[0]
        let engine = RenegadeEngine()
        let analyzed = try await GameAnalyzer.analyze(game: sample, engine: engine, preset: .fast)
        #expect(analyzed.plies.count == 30)
        #expect(analyzed.whiteSummary.accuracy > 0 && analyzed.whiteSummary.accuracy <= 100)
        #expect(analyzed.openingLineDetected == "London System")
    }

    @Test("RenegadeEngine loads NNUE via mmap and solves Mate-in-1, Mate-in-2, Hanging Queen, MultiPV & terminal positions")
    func renegadeNNUECoreTactics() async throws {
        let engine = RenegadeEngine()
        let ready = await engine.isNativeNNUEReady()
        #expect(ready, "RenegadeEngine must load bundled renegade-net-36.bin via mmap without falling back")

        // 1. Mate in 1 + MultiPV
        let mate1 = try await engine.analyze(
            fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1",
            depth: 10,
            multiPV: 2,
            maxTimeMs: 300
        )
        #expect(mate1.bestMoveUci == "d1d8")
        #expect(mate1.score.mateWhite == 1)
        #expect(mate1.lines.count == 2)
        #expect(mate1.lines[0].bestMoveUci != mate1.lines[1].bestMoveUci)

        // 2. Hanging Queen
        let queen = try await engine.analyze(
            fen: "4k3/8/8/3q4/8/8/3R4/4K3 w - - 0 1",
            depth: 10,
            multiPV: 2,
            maxTimeMs: 300
        )
        #expect(queen.bestMoveUci == "d2d5")
        #expect(queen.score.cpWhite > 400)

        // 3. Forced Mate in 2
        let mate2 = try await engine.analyze(
            fen: "8/6pk/5Q1p/8/8/8/8/4R2K w - - 0 1",
            depth: 12,
            multiPV: 1,
            maxTimeMs: 400
        )
        #expect(mate2.score.mateWhite == 2 || mate2.score.cpWhite > 1500)
        #expect(mate2.bestMoveUci == "e1e7" || mate2.bestMoveUci == "f6g7")

        // 4. Black to move sign convention (Black has mate in 1: Rd1#)
        let blackMate1 = try await engine.analyze(
            fen: "3r2k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1",
            depth: 8,
            multiPV: 1,
            maxTimeMs: 250
        )
        #expect(blackMate1.bestMoveUci == "d8d1")
        #expect(blackMate1.score.mateWhite == -1)

        // 5. Terminal checkmate position
        let checkmated = try await engine.analyze(
            fen: "3R2k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1",
            depth: 8,
            multiPV: 2,
            maxTimeMs: 150
        )
        #expect(checkmated.score.isCheckmate == true)
        #expect(checkmated.score.cpWhite == 10000)
        #expect(checkmated.bestMoveUci.isEmpty)

        // 6. 4-field FEN + impossible castling flags must be normalized safely without crashing C++ Position
        let shortFen = try await engine.analyze(
            fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w KQkq -",
            depth: 8,
            multiPV: 1,
            maxTimeMs: 250
        )
        #expect(shortFen.bestMoveUci == "d1d8")
        #expect(shortFen.score.mateWhite == 1)

        // 7. Analysis preset Pro gating: Fast/Balanced/Deep are Free, Ultra & Cloud SF require Pro
        #expect(BrillyEntitlementPolicy.isAnalysisPresetUnlocked(.fast, hasProAccess: false))
        #expect(BrillyEntitlementPolicy.isAnalysisPresetUnlocked(.balanced, hasProAccess: false))
        #expect(BrillyEntitlementPolicy.isAnalysisPresetUnlocked(.deep, hasProAccess: false))
        #expect(!BrillyEntitlementPolicy.isAnalysisPresetUnlocked(.ultra, hasProAccess: false))
        #expect(!BrillyEntitlementPolicy.isAnalysisPresetUnlocked(.cloudUltra, hasProAccess: false))
        #expect(BrillyEntitlementPolicy.isAnalysisPresetUnlocked(.ultra, hasProAccess: true))
        #expect(BrillyEntitlementPolicy.isAnalysisPresetUnlocked(.cloudUltra, hasProAccess: true))
    }

    @Test("Brilliant Engine v5 matches Chess.com: rewards 16...Nxd4!! and rejects 8...Nd4 counterthreat, already-winning positions & fork-flee/king-escape false positives")
    func brilliantEngineV5Calibration() throws {
        // 1. Exact real-game position: 16...Nxd4!! (knight captures pawn on d4 where Ne2 can capture it; 17. Nxd4 Bc5! pins & wins a1 rook)
        // With #1 = -2.5 vs #2 = -1.9 (4.7% sigmoid gap, secondBestWin = 66.8% < 78%), it MUST classify as Brilliant!
        let beforeNxd4 = try ChessBoard(fen: "2kr1b1r/ppp2p1p/2n2p2/3b4/3P4/1P3P2/P3NKPP/RN3B1R b - - 0 16")
        var afterNxd4 = beforeNxd4
        let appliedNxd4 = try afterNxd4.apply(uci: "c6d4")
        let winBeforeNxd4 = ChessMath.moverWinPercent(ChessMath.buildEngineScore(cpWhite: -250), mover: .black)
        let winSecondNxd4 = ChessMath.moverWinPercent(ChessMath.buildEngineScore(cpWhite: -190), mover: .black)
        let gapNxd4 = winBeforeNxd4 - winSecondNxd4 // ~4.7%
        let nxd4Class = MoveClassifier.classify(MoveClassificationInput(
            plyIndex: 31,
            sanPrefix: [],
            playedUci: "c6d4",
            bestMoveUci: "c6d4",
            beforeBoard: beforeNxd4,
            afterBoard: afterNxd4,
            moverColor: .black,
            fromSquare: appliedNxd4.move.from,
            toSquare: appliedNxd4.move.to,
            movedPiece: appliedNxd4.piece.type,
            capturedPiece: appliedNxd4.captured?.type,
            promotionPiece: nil,
            positionRepeated: false,
            moverWinBefore: winBeforeNxd4,
            moverWinAfter: winBeforeNxd4,
            secondBestGapWin: gapNxd4,
            hasSecondLine: true
        ))
        #expect(nxd4Class == .brilliant)

        // 2. Exact real-game false positive from RonaldRaborg: 8...Nd4 counter-attacking White's Qe2
        // while Ne4 is attacked by f3 (and Black is already -5.7 vs #2 -4.5). MUST be Best, NOT Brilliant!
        let beforeNd4 = try ChessBoard(fen: "r1b1kb1r/ppp2ppp/2n5/3pq3/4n3/1B3PP1/PPPPQ2P/RNB1K2R b KQkq - 0 8")
        var afterNd4 = beforeNd4
        let appliedNd4 = try afterNd4.apply(uci: "c6d4")
        #expect(MoveClassifier.detectSacrificeKind(
            beforeBoard: beforeNd4,
            afterBoard: afterNd4,
            mover: .black,
            fromSquare: appliedNd4.move.from,
            toSquare: appliedNd4.move.to,
            movedPiece: appliedNd4.piece.type,
            capturedPiece: nil,
            promotionPiece: nil
        ) == .none)
        let nd4Win = ChessMath.moverWinPercent(ChessMath.buildEngineScore(cpWhite: -570), mover: .black)
        let nd4Second = ChessMath.moverWinPercent(ChessMath.buildEngineScore(cpWhite: -450), mover: .black)
        let nd4Class = MoveClassifier.classify(MoveClassificationInput(
            plyIndex: 15,
            sanPrefix: [],
            playedUci: "c6d4",
            bestMoveUci: "c6d4",
            beforeBoard: beforeNd4,
            afterBoard: afterNd4,
            moverColor: .black,
            fromSquare: appliedNd4.move.from,
            toSquare: appliedNd4.move.to,
            movedPiece: appliedNd4.piece.type,
            capturedPiece: nil,
            promotionPiece: nil,
            positionRepeated: false,
            moverWinBefore: nd4Win,
            moverWinAfter: nd4Win,
            secondBestGapWin: nd4Win - nd4Second,
            hasSecondLine: true
        ))
        #expect(nd4Class == .best)

        // 3. Anti-spam: already crushing (+4.8 / 85% win, #2 already 80%) should NOT award Brilliant
        let crushingClass = MoveClassifier.classify(MoveClassificationInput(
            plyIndex: 31,
            sanPrefix: [],
            playedUci: "c6d4",
            bestMoveUci: "c6d4",
            beforeBoard: beforeNxd4,
            afterBoard: afterNxd4,
            moverColor: .black,
            fromSquare: appliedNxd4.move.from,
            toSquare: appliedNxd4.move.to,
            movedPiece: appliedNxd4.piece.type,
            capturedPiece: appliedNxd4.captured?.type,
            promotionPiece: nil,
            positionRepeated: false,
            moverWinBefore: 85.0,
            moverWinAfter: 85.0,
            secondBestGapWin: 5.0,
            hasSecondLine: true
        ))
        #expect(crushingClass != .brilliant)

        // 4. False-positive guard: saving Queen from a pawn fork while Knight stays hanging is NOT a sacrifice
        let forkBefore = try ChessBoard(fen: "4k3/8/8/3p4/2Q1N3/8/8/4K3 w - - 0 1")
        var forkAfter = forkBefore
        let savedQueen = try forkAfter.apply(uci: "c4d3")
        #expect(!MoveClassifier.isSacrificeMove(
            beforeBoard: forkBefore,
            afterBoard: forkAfter,
            mover: .white,
            fromSquare: savedQueen.move.from,
            toSquare: savedQueen.move.to,
            movedPiece: savedQueen.piece.type,
            capturedPiece: nil,
            promotionPiece: nil
        ))

        // 5. False-positive guard: forced King escape out of check leaving a Rook en prise is NOT a voluntary sacrifice
        let checkBefore = try ChessBoard(fen: "4k3/8/8/8/1b6/8/R7/4K3 w - - 0 1")
        var checkAfter = checkBefore
        let escapedKing = try checkAfter.apply(uci: "e1f1")
        #expect(!MoveClassifier.isSacrificeMove(
            beforeBoard: checkBefore,
            afterBoard: checkAfter,
            mover: .white,
            fromSquare: escapedKing.move.from,
            toSquare: escapedKing.move.to,
            movedPiece: escapedKing.piece.type,
            capturedPiece: nil,
            promotionPiece: nil
        ))

        // 6. Instant v3 -> v4 reclassification promotes stored v3 16...Nxd4 ("best") into "brilliant"
        let dummyGame = GameRecord(
            id: "test-nxd4-v3",
            source: .chesscom,
            createdAt: 1_700_000_000_000,
            resultString: "0-1",
            timeControlLabel: "10+0",
            pgn: "*",
            openingName: "Test",
            white: PlayerInfo(name: "KingElgu", rating: 1310),
            black: PlayerInfo(name: "Lukedunwell", rating: 1249),
            userColor: .black
        )
        let evalScore = ChessMath.buildEngineScore(cpWhite: -250)
        let v3Ply = AnalyzedPly(
            ply: 32,
            moveNumber: 16,
            color: .black,
            san: "Nxd4",
            uci: "c6d4",
            from: "c6",
            to: "d4",
            promotion: nil,
            captured: "p",
            beforeFen: beforeNxd4.fen,
            afterFen: afterNxd4.fen,
            clockText: nil,
            clockSeconds: nil,
            timeSpentSeconds: nil,
            clockTag: nil,
            bestMoveUci: "c6d4",
            bestMoveSan: "Nxd4",
            bestPvSan: ["Nxd4", "Nbc3", "Bc5"],
            topLines: [
                TopEngineLineSummary(san: "Nxd4", evalDisplay: "-2.5", pvSan: ["Nxd4"]),
                TopEngineLineSummary(san: "Bh6", evalDisplay: "-1.9", pvSan: ["Bh6"]),
            ],
            threatMoveUci: nil,
            threatMoveSan: nil,
            evalBefore: evalScore,
            evalAfter: evalScore,
            secondBestGapWin: gapNxd4,
            secondBestGapPawns: nil,
            isCriticalMoment: false,
            isClutchSave: false,
            deepened: false,
            winLoss: 0.0,
            accuracy: 100.0,
            classification: .best,
            phase: .middlegame,
            coaching: CoachingExplanation(headline: "Top engine choice", detail: "", tacticalTag: "Precision")
        )
        let v3Analyzed = AnalyzedGame(
            id: dummyGame.id,
            analyzedAt: 1_700_000_000_000,
            depth: 8,
            classificationVersion: 3,
            game: dummyGame,
            initialEval: evalScore,
            plies: [v3Ply],
            whiteSummary: PlayerAnalysisSummary(accuracy: 90, estimatedElo: 1500, counts: [:], avgWinLoss: 2),
            blackSummary: PlayerAnalysisSummary(accuracy: 96, estimatedElo: 1900, counts: ["best": 1], avgWinLoss: 0),
            openingLineDetected: "Test"
        )
        let v4Analyzed = GameAnalyzer.reclassifyIfOutdated(v3Analyzed)
        #expect(v4Analyzed.classificationVersion == MoveClassifier.classificationVersion)
        #expect(v4Analyzed.plies.first?.classification == .brilliant)
        #expect(v4Analyzed.blackSummary.count(for: .brilliant) == 1)
    }
}
