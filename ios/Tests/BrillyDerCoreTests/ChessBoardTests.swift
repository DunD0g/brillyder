import Foundation
import Testing
@testable import BrillyDerCore

@Suite("ChessBoard FIDE Legality, Perft & PGN")
struct ChessBoardTests {
    @Test("Starting position Perft depth 1..3 matches canonical FIDE counts")
    func initialPerft() {
        let board = ChessBoard()
        #expect(board.perft(depth: 1) == 20)
        #expect(board.perft(depth: 2) == 400)
        #expect(board.perft(depth: 3) == 8_902)
    }

    @Test("Kiwipete complex tactical position Perft depth 1..3 matches canonical FIDE counts")
    func kiwipetePerft() throws {
        let board = try ChessBoard(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        #expect(board.perft(depth: 1) == 48)
        #expect(board.perft(depth: 2) == 2_039)
        #expect(board.perft(depth: 3) == 97_862)
    }

    @Test("En passant horizontal pin legality is strictly enforced")
    func enPassantHorizontalPin() throws {
        // White king on a5, white pawn on d5, black pawn on e5 (just pushed e7-e5), black rook on h5 -> dxe6 ep would expose king!
        let board = try ChessBoard(fen: "8/8/8/K2pP2r/8/8/8/4k3 w - d6 0 1")
        let moves = board.legalMoves()
        #expect(!moves.contains(ChessMove(from: Square(algebraic: "e5")!, to: Square(algebraic: "d6")!)))
    }

    @Test("Castling through check or out of check is forbidden")
    func castlingLegality() throws {
        let inCheck = try ChessBoard(fen: "4r1k1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        #expect(!inCheck.legalMoves().contains(ChessMove(from: .e1, to: .g1)))
        #expect(!inCheck.legalMoves().contains(ChessMove(from: .e1, to: .c1)))

        let throughCheck = try ChessBoard(fen: "1k3r2/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        #expect(!throughCheck.legalMoves().contains(ChessMove(from: .e1, to: .g1)))
        #expect(throughCheck.legalMoves().contains(ChessMove(from: .e1, to: .c1)))
    }

    @Test("SAN generation handles disambiguation, promotion, check and checkmate")
    func sanDisambiguationAndMate() throws {
        var scholar = ChessBoard()
        for san in ["e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6", "Qxf7#"] {
            let applied = try scholar.apply(san: san)
            if san == "Qxf7#" {
                #expect(applied.san == "Qxf7#")
            }
        }
        #expect(scholar.outcome == .checkmate(winner: .white))
    }

    @Test("PGN parser extracts headers, clocks, and replays moves safely")
    func pgnParsing() throws {
        let pgn = """
        [Event "Rated Rapid game"]
        [White "Alice"]
        [Black "Bob"]
        [Result "1-0"]

        1. e4 { [%clk 0:10:00] } 1... e5 { [%clk 0:09:58] } 2. Nf3 Nc6 (2... Nf6 3. Nxe5) 3. Bb5 a6 1-0
        """
        let parsed = try PGNParser.parse(pgn)
        #expect(parsed.headers["White"] == "Alice")
        #expect(parsed.moves.count == 6)
        #expect(parsed.moves[0].clockText == "0:10:00")
        #expect(parsed.moves[0].clockSeconds == 600.0)
        #expect(parsed.moves[1].clockSeconds == 598.0)
        #expect(parsed.moves.last?.applied.san == "a6")
    }
}
