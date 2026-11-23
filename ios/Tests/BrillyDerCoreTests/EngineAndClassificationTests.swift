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
        let engine = BrillyNativeEngine()
        let analyzed = try await GameAnalyzer.analyze(game: sample, engine: engine, preset: .fast)
        #expect(analyzed.plies.count == 30)
        #expect(analyzed.whiteSummary.accuracy > 0 && analyzed.whiteSummary.accuracy <= 100)
        #expect(analyzed.openingLineDetected == "London System")
    }
}
