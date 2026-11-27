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

    @Test("Brilliant Engine v6 matches Chess.com: rewards 16...Nxd4!! (at -2.5 & -5.51), forced-mate Queen sacs, decisive +5.5 sacs, defensive saves & Fried Liver, while rejecting 8...Nd4 counterthreat, equal-value fork-flee & blowouts")
    func brilliantEngineV6Calibration() throws {
        // 1. Exact real-game position: 16...Nxd4!! (knight captures pawn on d4 where Ne2 can capture it; 17. Nxd4 Bc5! pins & wins a1 rook)
        // Must classify as Brilliant BOTH at Renegade eval (-2.5 vs -1.9) AND Stockfish eval (-5.51 vs -2.2, 88.4% > old 84% cap)!
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

        let sfWinNxd4 = ChessMath.moverWinPercent(ChessMath.buildEngineScore(cpWhite: -551), mover: .black) // 88.4%
        let sfSecondNxd4 = ChessMath.moverWinPercent(ChessMath.buildEngineScore(cpWhite: -220), mover: .black) // 69.4%
        let sfNxd4Class = MoveClassifier.classify(MoveClassificationInput(
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
            moverWinBefore: sfWinNxd4,
            moverWinAfter: sfWinNxd4,
            secondBestGapWin: sfWinNxd4 - sfSecondNxd4,
            hasSecondLine: true
        ))
        #expect(sfNxd4Class == .brilliant)

        // 1b. Classic forced-mate Queen sacrifice (smothered mate Qg8+!! Rxg8 Nf7#): moverWinBefore = 100%, #2 = 85% (+4.7)
        let beforeQg8 = try ChessBoard(fen: "5r1k/6pp/7N/8/8/1Q6/6PP/6K1 w - - 0 1")
        var afterQg8 = beforeQg8
        let appliedQg8 = try afterQg8.apply(uci: "b3g8")
        let qg8Class = MoveClassifier.classify(MoveClassificationInput(
            plyIndex: 40,
            sanPrefix: [],
            playedUci: "b3g8",
            bestMoveUci: "b3g8",
            beforeBoard: beforeQg8,
            afterBoard: afterQg8,
            moverColor: .white,
            fromSquare: appliedQg8.move.from,
            toSquare: appliedQg8.move.to,
            movedPiece: appliedQg8.piece.type,
            capturedPiece: nil,
            promotionPiece: nil,
            positionRepeated: false,
            moverWinBefore: 100.0,
            moverWinAfter: 100.0,
            secondBestGapWin: 15.0,
            hasSecondLine: true,
            deliversForcedMate: true
        ))
        #expect(qg8Class == .brilliant)

        // 1c. Heroic defensive saving sacrifice holding 42% (-0.85 pawns) when #2 loses (25%)
        let defSacClass = MoveClassifier.classify(MoveClassificationInput(
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
            moverWinBefore: 42.0,
            moverWinAfter: 42.0,
            secondBestGapWin: 17.0,
            hasSecondLine: true
        ))
        #expect(defSacClass == .brilliant)

        // 1d. Move-6 Fried Liver 6. Nxf7!! (plyIndex = 10 with openingPlyHint = 12) takes precedence over Book
        let beforeFriedLiver = try ChessBoard(fen: "r1bqkb1r/ppp2ppp/2n5/3np1N1/2B5/8/PPPP1PPP/RNBQK2R w KQkq - 0 6")
        var afterFriedLiver = beforeFriedLiver
        let appliedFriedLiver = try afterFriedLiver.apply(uci: "g5f7")
        let friedLiverClass = MoveClassifier.classify(MoveClassificationInput(
            plyIndex: 10,
            sanPrefix: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Nf6", "Ng5", "d5", "exd5", "Nxd5", "Nxf7"],
            openingPlyHint: 12,
            playedUci: "g5f7",
            bestMoveUci: "g5f7",
            beforeBoard: beforeFriedLiver,
            afterBoard: afterFriedLiver,
            moverColor: .white,
            fromSquare: appliedFriedLiver.move.from,
            toSquare: appliedFriedLiver.move.to,
            movedPiece: appliedFriedLiver.piece.type,
            capturedPiece: appliedFriedLiver.captured?.type,
            promotionPiece: nil,
            positionRepeated: false,
            moverWinBefore: 64.0,
            moverWinAfter: 64.0,
            secondBestGapWin: 14.0,
            hasSecondLine: true
        ))
        #expect(friedLiverClass == .brilliant)

        // 1e. Passive sacrifice still triggers even if a pre-existing opponent piece (Rb5 attacked by Be2) was already hanging elsewhere
        let beforePassiveWithPreexisting = try ChessBoard(fen: "6k1/6b1/8/1r6/8/8/4B2Q/R5K1 w - - 0 1")
        var afterPassiveWithPreexisting = beforePassiveWithPreexisting
        let appliedQh4 = try afterPassiveWithPreexisting.apply(uci: "h2h4")
        #expect(MoveClassifier.detectSacrificeKind(
            beforeBoard: beforePassiveWithPreexisting,
            afterBoard: afterPassiveWithPreexisting,
            mover: .white,
            fromSquare: appliedQh4.move.from,
            toSquare: appliedQh4.move.to,
            movedPiece: appliedQh4.piece.type,
            capturedPiece: nil,
            promotionPiece: nil
        ) == .passive)

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

        // 4. False-positive guards: saving Queen OR equal-value Bishop from a pawn fork while Knight stays hanging is NOT a sacrifice
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

        let eqForkBefore = try ChessBoard(fen: "4k3/8/8/3p4/2B1N3/8/8/4K3 w - - 0 1")
        var eqForkAfter = eqForkBefore
        let savedBishop = try eqForkAfter.apply(uci: "c4d3")
        #expect(!MoveClassifier.isSacrificeMove(
            beforeBoard: eqForkBefore,
            afterBoard: eqForkAfter,
            mover: .white,
            fromSquare: savedBishop.move.from,
            toSquare: savedBishop.move.to,
            movedPiece: savedBishop.piece.type,
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
        let v6Analyzed = GameAnalyzer.reclassifyIfOutdated(v3Analyzed)
        #expect(v6Analyzed.classificationVersion == MoveClassifier.classificationVersion)
        #expect(v6Analyzed.plies.first?.classification == .brilliant)
        #expect(v6Analyzed.blackSummary.count(for: .brilliant) == 1)

        // 7. Instant v5 -> v6 reclassification restores forced-mate Queen sac (previously killed by moverWinBefore < 84%)
        let mateEval = ChessMath.buildEngineScore(cpWhite: 10000, mateWhite: 2)
        let v5MatePly = AnalyzedPly(
            ply: 41,
            moveNumber: 21,
            color: .white,
            san: "Qg8+",
            uci: "b3g8",
            from: "b3",
            to: "g8",
            promotion: nil,
            captured: nil,
            beforeFen: beforeQg8.fen,
            afterFen: afterQg8.fen,
            clockText: nil,
            clockSeconds: nil,
            timeSpentSeconds: nil,
            clockTag: nil,
            bestMoveUci: "b3g8",
            bestMoveSan: "Qg8+",
            bestPvSan: ["Qg8+", "Rxg8", "Nf7#"],
            topLines: [
                TopEngineLineSummary(san: "Qg8+", evalDisplay: "#2", pvSan: ["Qg8+"]),
                TopEngineLineSummary(san: "Qf7", evalDisplay: "+3.0", pvSan: ["Qf7"]),
            ],
            threatMoveUci: nil,
            threatMoveSan: nil,
            evalBefore: mateEval,
            evalAfter: ChessMath.buildEngineScore(cpWhite: 10000, mateWhite: 1),
            secondBestGapWin: 24.0,
            secondBestGapPawns: nil,
            isCriticalMoment: true,
            isClutchSave: false,
            deepened: false,
            winLoss: 0.0,
            accuracy: 100.0,
            classification: .great,
            phase: .middlegame,
            coaching: CoachingExplanation(headline: "Only move", detail: "", tacticalTag: "Precision")
        )
        let v5Analyzed = AnalyzedGame(
            id: "test-qg8-v5",
            analyzedAt: 1_700_000_000_000,
            depth: 14,
            classificationVersion: 5,
            game: dummyGame,
            initialEval: mateEval,
            plies: [v5MatePly],
            whiteSummary: PlayerAnalysisSummary(accuracy: 100, estimatedElo: 2000, counts: ["great": 1], avgWinLoss: 0),
            blackSummary: PlayerAnalysisSummary(accuracy: 90, estimatedElo: 1500, counts: [:], avgWinLoss: 2),
            openingLineDetected: "Test"
        )
        let upgradedV6 = GameAnalyzer.reclassifyIfOutdated(v5Analyzed)
        #expect(upgradedV6.classificationVersion == MoveClassifier.classificationVersion)
        #expect(upgradedV6.plies.first?.classification == .brilliant)
        #expect(upgradedV6.whiteSummary.count(for: .brilliant) == 1)
    }

    @Test("BotArenaEngine supports 11 tiers (400..3500 Hybrid), per-bot opening books, guide mode, and valid PGN export")
    func botArenaEngineAndOpeningBooks() async throws {
        // 1. All 11 bot profiles have strictly ascending Elos and clean Free vs Pro gating
        let allBots = BotProfile.allCases
        #expect(allBots.count == 11)
        for i in 1..<allBots.count {
            #expect(allBots[i].elo > allBots[i - 1].elo)
        }
        #expect(BotProfile.cadet400.isUnlocked(hasProAccess: false))
        #expect(BotProfile.deep.isUnlocked(hasProAccess: false))
        #expect(!BotProfile.ultra.isUnlocked(hasProAccess: false))
        #expect(!BotProfile.hybrid.isUnlocked(hasProAccess: false))
        #expect(BotProfile.ultra.isUnlocked(hasProAccess: true))
        #expect(BotProfile.hybrid.isUnlocked(hasProAccess: true))

        // 2. Per-bot opening book resolution from starterCourses.json
        let courses = try CourseRepository.loadStarterCourses()
        let whiteQG = try #require(courses.first(where: { $0.side == .white && $0.name.localizedCaseInsensitiveContains("Queen's Gambit") }))
        let blackQG = try #require(courses.first(where: { $0.side == .black && $0.name.localizedCaseInsensitiveContains("Queen's Gambit") }))

        var board = ChessBoard()
        var sanHistory: [String] = []
        let nnue = RenegadeEngine()
        let swift = BrillyNativeEngine()

        // Ply 1: White Queen's Gambit book plays 1. d4
        let move1 = try #require(await BotArenaEngine.chooseMove(
            board: board,
            sanHistory: sanHistory,
            profile: .deep,
            openingSelection: .course(courseId: whiteQG.id, lineId: nil),
            opponentOpeningSelection: .course(courseId: blackQG.id, lineId: nil),
            courses: courses,
            nnueEngine: nnue,
            swiftEngine: swift
        ))
        #expect(move1.san == "d4")
        if case .openingBook = move1.source { } else { Issue.record("Expected openingBook source on 1. d4") }
        _ = try board.apply(move1.move)
        sanHistory.append(move1.san)

        // Ply 2: Black Queen's Gambit book replies 1... d5
        let move2 = try #require(await BotArenaEngine.chooseMove(
            board: board,
            sanHistory: sanHistory,
            profile: .ultra,
            openingSelection: .course(courseId: blackQG.id, lineId: nil),
            opponentOpeningSelection: .course(courseId: whiteQG.id, lineId: nil),
            courses: courses,
            nnueEngine: nnue,
            swiftEngine: swift
        ))
        #expect(move2.san == "d5")
        _ = try board.apply(move2.move)
        sanHistory.append(move2.san)

        // Ply 3: Weak bot (Cadet ~400) & Fast NNUE both produce 100% legal out-of-book moves
        let cadetMove = try #require(await BotArenaEngine.chooseMove(
            board: board,
            sanHistory: sanHistory,
            profile: .cadet400,
            openingSelection: .freePlay,
            opponentOpeningSelection: .freePlay,
            guideOpponentOpening: false,
            courses: courses,
            nnueEngine: nnue,
            swiftEngine: swift
        ))
        #expect(board.legalMoves().contains(cadetMove.move))
        _ = try board.apply(cadetMove.move)
        sanHistory.append(cadetMove.san)

        let fastMove = try #require(await BotArenaEngine.chooseMove(
            board: board,
            sanHistory: sanHistory,
            profile: .fast,
            openingSelection: .freePlay,
            opponentOpeningSelection: .freePlay,
            guideOpponentOpening: false,
            courses: courses,
            nnueEngine: nnue,
            swiftEngine: swift
        ))
        #expect(board.legalMoves().contains(fastMove.move))
        _ = try board.apply(fastMove.move)
        sanHistory.append(fastMove.san)

        // 3. Guide mode: Free Play White follows Black's Caro-Kann setup on move 1 (1. e4)
        if let caro = courses.first(where: { $0.side == .black && $0.name.localizedCaseInsensitiveContains("Caro") }) {
            let guided = BotOpeningBookResolver.nextBookMove(
                board: ChessBoard(),
                sanHistory: [],
                selection: .freePlay,
                courses: courses,
                opponentSelection: .course(courseId: caro.id, lineId: nil),
                guideOpponentOpening: true
            )
            #expect(guided?.san == "e4")
        }

        // 4. PGN GameRecord export parses cleanly and keeps userColor nil for Bot vs Bot
        let record = BotArenaEngine.buildGameRecord(
            sanMoves: sanHistory,
            whiteName: BotProfile.deep.displayName,
            whiteElo: BotProfile.deep.elo,
            blackName: BotProfile.ultra.displayName,
            blackElo: BotProfile.ultra.elo,
            resultString: "*",
            userColor: nil,
            openingHintName: "Queen's Gambit"
        )
        #expect(record.userColor == nil)
        #expect(!record.rated)
        let parsed = try PGNParser.parse(record.pgn)
        #expect(parsed.moves.count == sanHistory.count)
    }
}
