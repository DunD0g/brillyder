import Foundation

/// Deterministic SplitMix64 Zobrist keys for fast hashing & Transposition Table lookups.
internal enum Zobrist {
    // 12 piece indices (0..5 white p,n,b,r,q,k; 6..11 black) x 64 squares
    static let pieceKeys: [UInt64] = {
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        return (0..<(12 * 64)).map { _ in next() }
    }()

    static let sideKey: UInt64 = 0xD1B54A32D192ED03
    static let castlingKeys: [UInt64] = [
        0xA5A5A5A5A5A5A5A5, 0x3C6EF372FE94F82B, 0xBB67AE8584CAA73B, 0x510E527FADE682D1,
        0x9B05688C2B3E6C1F, 0x1F83D9ABFB41BD6B, 0x5BE0CD19137E2179, 0x6A09E667F3BCC908,
        0xCBBB9D5DC1059ED8, 0x629A292A367CD507, 0x9159015A3070DD17, 0x152FECD8F70E5939,
        0x67332667FFC00B31, 0x8EB44A8768581511, 0xDB0C2E0D64F98FA7, 0x47B5481DBEFA4FA4,
    ]
    static let epFileKeys: [UInt64] = [
        0x243F6A8885A308D3, 0x13198A2E03707344, 0xA4093822299F31D0, 0x082EFA98EC4E6C89,
        0x452821E638D01377, 0xBE5466CF34E90C6C, 0xC0AC29B7C97C50DD, 0x3F84D5B5B5470917,
    ]

    @inline(__always)
    static func pieceIndex(_ piece: Piece) -> Int {
        let base: Int
        switch piece.type {
        case .pawn: base = 0
        case .knight: base = 1
        case .bishop: base = 2
        case .rook: base = 3
        case .queen: base = 4
        case .king: base = 5
        }
        return (piece.color == .white ? 0 : 6) + base
    }
}

/// Complete, FIDE-legal, value-type chess position with FEN/SAN/UCI support and Zobrist hashing.
public struct ChessBoard: Hashable, Sendable {
    public static let initialFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

    public private(set) var squares: [Piece?]
    public private(set) var turn: PieceColor
    public private(set) var castling: CastlingRights
    public private(set) var enPassantSquare: Square?
    public private(set) var halfmoveClock: Int
    public private(set) var fullmoveNumber: Int
    public private(set) var whiteKingSquare: Square
    public private(set) var blackKingSquare: Square
    public private(set) var zobristHash: UInt64

    public init() {
        // Safe because initialFEN is compile-time constant valid.
        try! self.init(fen: ChessBoard.initialFEN)
    }

    public init(fen: String) throws {
        let parts = fen.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard parts.count >= 4 else {
            throw ChessError.invalidFEN("Expected at least 4 space-separated fields")
        }

        let ranks = parts[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else {
            throw ChessError.invalidFEN("Expected 8 ranks")
        }

        var board = Array<Piece?>(repeating: nil, count: 64)
        var wKing: Square?
        var bKing: Square?
        var wKingCount = 0
        var bKingCount = 0

        for (fenRankIdx, rankStr) in ranks.enumerated() {
            let rank = 7 - fenRankIdx
            var file = 0
            for ch in rankStr {
                if let digit = ch.wholeNumberValue, (1...8).contains(digit) {
                    file += digit
                } else if let piece = Piece(fenChar: ch) {
                    guard file < 8 else {
                        throw ChessError.invalidFEN("Rank \(rank + 1) exceeds 8 files")
                    }
                    if piece.type == .pawn && (rank == 0 || rank == 7) {
                        throw ChessError.invalidFEN("Pawns cannot occupy rank 1 or rank 8")
                    }
                    let sq = Square(unchecked: rank * 8 + file)
                    board[sq.rawValue] = piece
                    if piece.type == .king {
                        if piece.color == .white { wKing = sq; wKingCount += 1 }
                        else { bKing = sq; bKingCount += 1 }
                    }
                    file += 1
                } else {
                    throw ChessError.invalidFEN("Unexpected character '\(ch)' in board field")
                }
            }
            guard file == 8 else {
                throw ChessError.invalidFEN("Rank \(rank + 1) does not sum to 8 files")
            }
        }

        guard wKingCount == 1, bKingCount == 1, let wk = wKing, let bk = bKing else {
            throw ChessError.invalidFEN("Position must contain exactly one white king and one black king")
        }

        guard let side = PieceColor(rawValue: parts[1]) else {
            throw ChessError.invalidFEN("Invalid side to move '\(parts[1])'")
        }
        guard var rights = CastlingRights(fen: parts[2]) else {
            throw ChessError.invalidFEN("Invalid castling rights '\(parts[2])'")
        }
        // Auto-strip impossible castling rights where king/rook aren't on home squares
        if board[Square.e1.rawValue] != Piece(color: .white, type: .king) { rights.remove([.whiteKingside, .whiteQueenside]) }
        if board[Square.h1.rawValue] != Piece(color: .white, type: .rook) { rights.remove(.whiteKingside) }
        if board[Square.a1.rawValue] != Piece(color: .white, type: .rook) { rights.remove(.whiteQueenside) }
        if board[Square.e8.rawValue] != Piece(color: .black, type: .king) { rights.remove([.blackKingside, .blackQueenside]) }
        if board[Square.h8.rawValue] != Piece(color: .black, type: .rook) { rights.remove(.blackKingside) }
        if board[Square.a8.rawValue] != Piece(color: .black, type: .rook) { rights.remove(.blackQueenside) }

        let ep: Square?
        if parts[3] == "-" {
            ep = nil
        } else {
            let expectedRank = side == .white ? 5 : 2
            guard let sq = Square(algebraic: parts[3]), sq.rank == expectedRank else {
                throw ChessError.invalidFEN("Invalid en passant square '\(parts[3])' for side '\(side.rawValue)'")
            }
            let pawnBehindRank = side == .white ? 4 : 3
            let pawnBehindIdx = pawnBehindRank * 8 + sq.file
            guard board[sq.rawValue] == nil,
                  board[pawnBehindIdx] == Piece(color: side.opposite, type: .pawn) else {
                throw ChessError.invalidFEN("En passant square '\(parts[3])' inconsistent with board pieces")
            }
            ep = sq
        }

        let halfmove = parts.count >= 5 ? max(0, min(10_000, Int(parts[4]) ?? 0)) : 0
        let fullmove = parts.count >= 6 ? max(1, min(100_000, Int(parts[5]) ?? 1)) : 1

        self.squares = board
        self.turn = side
        self.castling = rights
        self.enPassantSquare = ep
        self.halfmoveClock = max(0, halfmove)
        self.fullmoveNumber = fullmove
        self.whiteKingSquare = wk
        self.blackKingSquare = bk
        self.zobristHash = 0
        if self.isInCheck(side.opposite) {
            throw ChessError.invalidFEN("Side not to move cannot already be in check")
        }
        self.zobristHash = computeZobristHash()
    }

    public subscript(_ square: Square) -> Piece? {
        squares[square.rawValue]
    }

    public func piece(at algebraic: String) -> Piece? {
        guard let sq = Square(algebraic: algebraic) else { return nil }
        return squares[sq.rawValue]
    }

    public var fen: String {
        var rows: [String] = []
        rows.reserveCapacity(8)
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let p = squares[rank * 8 + file] {
                    if empty > 0 { row.append(String(empty)); empty = 0 }
                    row.append(p.fenChar)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row.append(String(empty)) }
            rows.append(row)
        }
        let epStr = enPassantSquare?.algebraic ?? "-"
        return "\(rows.joined(separator: "/")) \(turn.rawValue) \(castling.fenString) \(epStr) \(halfmoveClock) \(fullmoveNumber)"
    }

    /// Effective en passant square — only non-nil if an opposing pawn actually stands adjacent to capture.
    /// Prevents phantom EP from breaking FIDE transposition & repetition equality (matches chess.js v1).
    private func effectiveEnPassantSquare() -> Square? {
        guard let ep = enPassantSquare else { return nil }
        let attackerRank = turn == .white ? ep.rank - 1 : ep.rank + 1
        guard (0..<8).contains(attackerRank) else { return nil }
        for df in [-1, 1] {
            let f = ep.file + df
            if f >= 0 && f < 8,
               let p = squares[attackerRank * 8 + f],
               p.color == turn && p.type == .pawn {
                return ep
            }
        }
        return nil
    }

    /// First 4 FEN fields with normalized effective EP — matches web `fenPositionKey` & FIDE transpositions.
    public var positionKey: String {
        let parts = fen.split(separator: " ")
        let epPart = effectiveEnPassantSquare()?.algebraic ?? "-"
        guard parts.count >= 3 else { return fen }
        return "\(parts[0]) \(parts[1]) \(parts[2]) \(epPart)"
    }

    public func computeZobristHash() -> UInt64 {
        var h: UInt64 = 0
        for idx in 0..<64 {
            if let p = squares[idx] {
                h ^= Zobrist.pieceKeys[Zobrist.pieceIndex(p) * 64 + idx]
            }
        }
        if turn == .black { h ^= Zobrist.sideKey }
        h ^= Zobrist.castlingKeys[Int(castling.rawValue)]
        if let ep = effectiveEnPassantSquare() {
            h ^= Zobrist.epFileKeys[ep.file]
        }
        return h
    }

    // MARK: - Attack & Check Detection

    public func kingSquare(for color: PieceColor) -> Square {
        color == .white ? whiteKingSquare : blackKingSquare
    }

    public func isInCheck(_ color: PieceColor? = nil) -> Bool {
        let target = color ?? turn
        return isSquareAttacked(kingSquare(for: target), by: target.opposite)
    }

    public func isSquareAttacked(_ square: Square, by attacker: PieceColor) -> Bool {
        let f = square.file
        let r = square.rank

        // 1. Pawn attacks
        let pawnSourceRank = attacker == .white ? r - 1 : r + 1
        if pawnSourceRank >= 0 && pawnSourceRank < 8 {
            if f > 0, let p = squares[pawnSourceRank * 8 + (f - 1)], p.color == attacker && p.type == .pawn {
                return true
            }
            if f < 7, let p = squares[pawnSourceRank * 8 + (f + 1)], p.color == attacker && p.type == .pawn {
                return true
            }
        }

        // 2. Knight attacks
        for (df, dr) in Self.knightOffsets {
            let nf = f + df
            let nr = r + dr
            if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                if let p = squares[nr * 8 + nf], p.color == attacker && p.type == .knight {
                    return true
                }
            }
        }

        // 3. King attacks
        for (df, dr) in Self.kingOffsets {
            let nf = f + df
            let nr = r + dr
            if nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                if let p = squares[nr * 8 + nf], p.color == attacker && p.type == .king {
                    return true
                }
            }
        }

        // 4. Orthogonal sliders (rook / queen)
        for (df, dr) in Self.rookDirs {
            var nf = f + df
            var nr = r + dr
            while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                if let p = squares[nr * 8 + nf] {
                    if p.color == attacker && (p.type == .rook || p.type == .queen) {
                        return true
                    }
                    break
                }
                nf += df
                nr += dr
            }
        }

        // 5. Diagonal sliders (bishop / queen)
        for (df, dr) in Self.bishopDirs {
            var nf = f + df
            var nr = r + dr
            while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                if let p = squares[nr * 8 + nf] {
                    if p.color == attacker && (p.type == .bishop || p.type == .queen) {
                        return true
                    }
                    break
                }
                nf += df
                nr += dr
            }
        }

        return false
    }

    // MARK: - Move Generation

    public func pseudoLegalMoves(capturesOnly: Bool = false) -> [ChessMove] {
        var moves: [ChessMove] = []
        moves.reserveCapacity(capturesOnly ? 16 : 44)
        let side = turn
        let enemy = side.opposite

        for idx in 0..<64 {
            guard let piece = squares[idx], piece.color == side else { continue }
            let from = Square(unchecked: idx)
            let f = from.file
            let r = from.rank

            switch piece.type {
            case .pawn:
                let dir = side == .white ? 1 : -1
                let startRank = side == .white ? 1 : 6
                let promoRank = side == .white ? 7 : 0
                let nextRank = r + dir

                // Single & double pushes
                if !capturesOnly && nextRank >= 0 && nextRank < 8 {
                    let oneIdx = nextRank * 8 + f
                    if squares[oneIdx] == nil {
                        let to = Square(unchecked: oneIdx)
                        if nextRank == promoRank {
                            for promo in PieceType.promotionChoices {
                                moves.append(ChessMove(from: from, to: to, promotion: promo))
                            }
                        } else {
                            moves.append(ChessMove(from: from, to: to))
                            if r == startRank {
                                let twoIdx = (r + dir * 2) * 8 + f
                                if squares[twoIdx] == nil {
                                    moves.append(ChessMove(from: from, to: Square(unchecked: twoIdx)))
                                }
                            }
                        }
                    }
                } else if capturesOnly && nextRank == promoRank {
                    // Include quiet queen promotions in quiescence search
                    let oneIdx = nextRank * 8 + f
                    if squares[oneIdx] == nil {
                        moves.append(ChessMove(from: from, to: Square(unchecked: oneIdx), promotion: .queen))
                    }
                }

                // Captures + En Passant
                if nextRank >= 0 && nextRank < 8 {
                    for df in [-1, 1] {
                        let nf = f + df
                        guard nf >= 0 && nf < 8 else { continue }
                        let targetIdx = nextRank * 8 + nf
                        let targetSq = Square(unchecked: targetIdx)
                        let isCapture = squares[targetIdx]?.color == enemy
                        let isEP = enPassantSquare == targetSq
                        if isCapture || isEP {
                            if nextRank == promoRank {
                                for promo in PieceType.promotionChoices {
                                    moves.append(ChessMove(from: from, to: targetSq, promotion: promo))
                                }
                            } else {
                                moves.append(ChessMove(from: from, to: targetSq))
                            }
                        }
                    }
                }

            case .knight:
                for (df, dr) in Self.knightOffsets {
                    let nf = f + df
                    let nr = r + dr
                    guard nf >= 0 && nf < 8 && nr >= 0 && nr < 8 else { continue }
                    let targetIdx = nr * 8 + nf
                    if let occ = squares[targetIdx] {
                        if occ.color == enemy {
                            moves.append(ChessMove(from: from, to: Square(unchecked: targetIdx)))
                        }
                    } else if !capturesOnly {
                        moves.append(ChessMove(from: from, to: Square(unchecked: targetIdx)))
                    }
                }

            case .bishop, .rook, .queen:
                let dirs: [(Int, Int)]
                switch piece.type {
                case .bishop: dirs = Self.bishopDirs
                case .rook: dirs = Self.rookDirs
                default: dirs = Self.kingOffsets
                }
                for (df, dr) in dirs {
                    var nf = f + df
                    var nr = r + dr
                    while nf >= 0 && nf < 8 && nr >= 0 && nr < 8 {
                        let targetIdx = nr * 8 + nf
                        if let occ = squares[targetIdx] {
                            if occ.color == enemy {
                                moves.append(ChessMove(from: from, to: Square(unchecked: targetIdx)))
                            }
                            break
                        } else if !capturesOnly {
                            moves.append(ChessMove(from: from, to: Square(unchecked: targetIdx)))
                        }
                        nf += df
                        nr += dr
                    }
                }

            case .king:
                for (df, dr) in Self.kingOffsets {
                    let nf = f + df
                    let nr = r + dr
                    guard nf >= 0 && nf < 8 && nr >= 0 && nr < 8 else { continue }
                    let targetIdx = nr * 8 + nf
                    if let occ = squares[targetIdx] {
                        if occ.color == enemy {
                            moves.append(ChessMove(from: from, to: Square(unchecked: targetIdx)))
                        }
                    } else if !capturesOnly {
                        moves.append(ChessMove(from: from, to: Square(unchecked: targetIdx)))
                    }
                }

                if !capturesOnly {
                    if side == .white && from == .e1 && !isSquareAttacked(.e1, by: .black) {
                        if castling.contains(.whiteKingside),
                           squares[Square.f1.rawValue] == nil,
                           squares[Square.g1.rawValue] == nil,
                           squares[Square.h1.rawValue] == Piece(color: .white, type: .rook),
                           !isSquareAttacked(.f1, by: .black),
                           !isSquareAttacked(.g1, by: .black) {
                            moves.append(ChessMove(from: .e1, to: .g1))
                        }
                        if castling.contains(.whiteQueenside),
                           squares[Square.d1.rawValue] == nil,
                           squares[Square.c1.rawValue] == nil,
                           squares[Square.b1.rawValue] == nil,
                           squares[Square.a1.rawValue] == Piece(color: .white, type: .rook),
                           !isSquareAttacked(.d1, by: .black),
                           !isSquareAttacked(.c1, by: .black) {
                            moves.append(ChessMove(from: .e1, to: .c1))
                        }
                    } else if side == .black && from == .e8 && !isSquareAttacked(.e8, by: .white) {
                        if castling.contains(.blackKingside),
                           squares[Square.f8.rawValue] == nil,
                           squares[Square.g8.rawValue] == nil,
                           squares[Square.h8.rawValue] == Piece(color: .black, type: .rook),
                           !isSquareAttacked(.f8, by: .white),
                           !isSquareAttacked(.g8, by: .white) {
                            moves.append(ChessMove(from: .e8, to: .g8))
                        }
                        if castling.contains(.blackQueenside),
                           squares[Square.d8.rawValue] == nil,
                           squares[Square.c8.rawValue] == nil,
                           squares[Square.b8.rawValue] == nil,
                           squares[Square.a8.rawValue] == Piece(color: .black, type: .rook),
                           !isSquareAttacked(.d8, by: .white),
                           !isSquareAttacked(.c8, by: .white) {
                            moves.append(ChessMove(from: .e8, to: .c8))
                        }
                    }
                }
            }
        }

        return moves
    }

    public func legalMoves(capturesOnly: Bool = false) -> [ChessMove] {
        let pseudo = pseudoLegalMoves(capturesOnly: capturesOnly)
        var legal: [ChessMove] = []
        legal.reserveCapacity(pseudo.count)
        let mover = turn
        for move in pseudo {
            var next = self
            next.makeMoveUnchecked(move)
            if !next.isInCheck(mover) {
                legal.append(move)
            }
        }
        return legal
    }

    public func legalMoves(from square: Square) -> [ChessMove] {
        legalMoves().filter { $0.from == square }
    }

    /// Fast unchecked move execution (assumes move is pseudo-legal).
    public mutating func makeMoveUnchecked(_ move: ChessMove) {
        guard let moving = squares[move.from.rawValue] else { return }
        let mover = moving.color

        // Remove old castling & effective EP hash
        zobristHash ^= Zobrist.castlingKeys[Int(castling.rawValue)]
        if let oldEp = effectiveEnPassantSquare() {
            zobristHash ^= Zobrist.epFileKeys[oldEp.file]
        }

        let targetPiece = squares[move.to.rawValue]
        let isEnPassant = moving.type == .pawn && move.to == enPassantSquare && targetPiece == nil

        // Remove moving piece from `from`
        zobristHash ^= Zobrist.pieceKeys[Zobrist.pieceIndex(moving) * 64 + move.from.rawValue]
        squares[move.from.rawValue] = nil

        // Remove captured piece
        if let cap = targetPiece {
            zobristHash ^= Zobrist.pieceKeys[Zobrist.pieceIndex(cap) * 64 + move.to.rawValue]
        } else if isEnPassant {
            let capRank = mover == .white ? move.to.rank - 1 : move.to.rank + 1
            let capIdx = capRank * 8 + move.to.file
            if let epPawn = squares[capIdx] {
                zobristHash ^= Zobrist.pieceKeys[Zobrist.pieceIndex(epPawn) * 64 + capIdx]
                squares[capIdx] = nil
            }
        }

        // Place piece (possibly promoted) on `to`
        let placed = Piece(color: mover, type: move.promotion ?? moving.type)
        squares[move.to.rawValue] = placed
        zobristHash ^= Zobrist.pieceKeys[Zobrist.pieceIndex(placed) * 64 + move.to.rawValue]

        // Handle castling rook shift & king square tracking
        if moving.type == .king {
            if mover == .white {
                whiteKingSquare = move.to
                castling.remove([.whiteKingside, .whiteQueenside])
                if move.from == .e1 && move.to == .g1 {
                    moveRook(.h1, to: .f1, color: .white)
                } else if move.from == .e1 && move.to == .c1 {
                    moveRook(.a1, to: .d1, color: .white)
                }
            } else {
                blackKingSquare = move.to
                castling.remove([.blackKingside, .blackQueenside])
                if move.from == .e8 && move.to == .g8 {
                    moveRook(.h8, to: .f8, color: .black)
                } else if move.from == .e8 && move.to == .c8 {
                    moveRook(.a8, to: .d8, color: .black)
                }
            }
        }

        // Revoke castling rights when rooks move or are captured
        if move.from == .a1 || move.to == .a1 { castling.remove(.whiteQueenside) }
        if move.from == .h1 || move.to == .h1 { castling.remove(.whiteKingside) }
        if move.from == .a8 || move.to == .a8 { castling.remove(.blackQueenside) }
        if move.from == .h8 || move.to == .h8 { castling.remove(.blackKingside) }

        // En passant square
        if moving.type == .pawn && abs(move.to.rank - move.from.rank) == 2 {
            let epRank = (move.from.rank + move.to.rank) / 2
            enPassantSquare = Square(unchecked: epRank * 8 + move.from.file)
        } else {
            enPassantSquare = nil
        }

        // Halfmove & fullmove clocks
        if moving.type == .pawn || targetPiece != nil || isEnPassant {
            halfmoveClock = 0
        } else {
            halfmoveClock += 1
        }
        if mover == .black {
            fullmoveNumber += 1
        }

        turn = mover.opposite

        // Re-apply hash for new side, castling, effective EP
        zobristHash ^= Zobrist.sideKey
        zobristHash ^= Zobrist.castlingKeys[Int(castling.rawValue)]
        if let newEp = effectiveEnPassantSquare() {
            zobristHash ^= Zobrist.epFileKeys[newEp.file]
        }
    }

    /// Performs a zero-allocation null move (passes the turn) for Null-Move Pruning.
    @inline(__always)
    public mutating func makeNullMove() {
        if let oldEp = effectiveEnPassantSquare() {
            zobristHash ^= Zobrist.epFileKeys[oldEp.file]
        }
        enPassantSquare = nil
        halfmoveClock += 1
        turn = turn.opposite
        zobristHash ^= Zobrist.sideKey
    }

    /// Returns true if `color` has at least one non-pawn, non-king piece (guards against zugzwang in NMP).
    @inline(__always)
    public func hasNonPawnMaterial(for color: PieceColor) -> Bool {
        for idx in 0..<64 {
            if let p = squares[idx], p.color == color, p.type != .pawn && p.type != .king {
                return true
            }
        }
        return false
    }

    @inline(__always)
    private mutating func moveRook(_ from: Square, to: Square, color: PieceColor) {
        let rook = Piece(color: color, type: .rook)
        zobristHash ^= Zobrist.pieceKeys[Zobrist.pieceIndex(rook) * 64 + from.rawValue]
        squares[from.rawValue] = nil
        squares[to.rawValue] = rook
        zobristHash ^= Zobrist.pieceKeys[Zobrist.pieceIndex(rook) * 64 + to.rawValue]
    }

    // MARK: - SAN Generation & Parsing

    public func san(for move: ChessMove, legalCache: [ChessMove]? = nil) -> String? {
        let legal = legalCache ?? legalMoves()
        guard legal.contains(move), let piece = squares[move.from.rawValue] else { return nil }

        let isCastleKS = piece.type == .king && move.from.file == 4 && move.to.file == 6
        let isCastleQS = piece.type == .king && move.from.file == 4 && move.to.file == 2
        let isEP = piece.type == .pawn && move.to == enPassantSquare && squares[move.to.rawValue] == nil
        let isCapture = squares[move.to.rawValue] != nil || isEP

        var text = ""
        if isCastleKS {
            text = "O-O"
        } else if isCastleQS {
            text = "O-O-O"
        } else if piece.type == .pawn {
            if isCapture {
                text.append(move.from.fileChar)
                text.append("x")
            }
            text.append(move.to.algebraic)
            if let promo = move.promotion {
                text.append("=")
                text.append(promo.sanLetter)
            }
        } else {
            text.append(piece.type.sanLetter)
            let ambiguous = legal.filter {
                $0.from != move.from &&
                $0.to == move.to &&
                squares[$0.from.rawValue]?.type == piece.type
            }
            if !ambiguous.isEmpty {
                let sameFile = ambiguous.contains { $0.from.file == move.from.file }
                let sameRank = ambiguous.contains { $0.from.rank == move.from.rank }
                if !sameFile {
                    text.append(move.from.fileChar)
                } else if !sameRank {
                    text.append(move.from.rankChar)
                } else {
                    text.append(move.from.fileChar)
                    text.append(move.from.rankChar)
                }
            }
            if isCapture { text.append("x") }
            text.append(move.to.algebraic)
        }

        var next = self
        next.makeMoveUnchecked(move)
        if next.isInCheck() {
            text.append(next.legalMoves().isEmpty ? "#" : "+")
        }
        return text
    }

    public mutating func apply(_ move: ChessMove) throws -> AppliedMove {
        let legal = legalMoves()
        guard legal.contains(move), let piece = squares[move.from.rawValue] else {
            throw ChessError.illegalMove(move.uci)
        }
        let beforeFen = fen
        let sanStr = san(for: move, legalCache: legal) ?? move.uci
        let isCastleKS = piece.type == .king && move.from.file == 4 && move.to.file == 6
        let isCastleQS = piece.type == .king && move.from.file == 4 && move.to.file == 2
        let isEP = piece.type == .pawn && move.to == enPassantSquare && squares[move.to.rawValue] == nil
        let captured: Piece?
        if isEP {
            captured = Piece(color: piece.color.opposite, type: .pawn)
        } else {
            captured = squares[move.to.rawValue]
        }

        makeMoveUnchecked(move)
        return AppliedMove(
            move: move,
            piece: piece,
            captured: captured,
            isEnPassant: isEP,
            isCastleKingside: isCastleKS,
            isCastleQueenside: isCastleQS,
            san: sanStr,
            beforeFen: beforeFen,
            afterFen: fen
        )
    }

    public mutating func apply(uci: String) throws -> AppliedMove {
        guard let move = ChessMove(uci: uci) else {
            throw ChessError.illegalMove(uci)
        }
        return try apply(move)
    }

    public mutating func apply(san rawSan: String) throws -> AppliedMove {
        let move = try parseSAN(rawSan)
        return try apply(move)
    }

    public func parseSAN(_ rawSan: String) throws -> ChessMove {
        let cleaned = rawSan
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0", with: "O")
            .trimmingCharacters(in: CharacterSet(charactersIn: "+#!?"))
        guard !cleaned.isEmpty else {
            throw ChessError.invalidSAN(rawSan)
        }

        let legal = legalMoves()
        if cleaned == "O-O" {
            let from: Square = turn == .white ? .e1 : .e8
            let to: Square = turn == .white ? .g1 : .g8
            if let m = legal.first(where: { $0.from == from && $0.to == to }) { return m }
            throw ChessError.illegalMove(rawSan)
        }
        if cleaned == "O-O-O" {
            let from: Square = turn == .white ? .e1 : .e8
            let to: Square = turn == .white ? .c1 : .c8
            if let m = legal.first(where: { $0.from == from && $0.to == to }) { return m }
            throw ChessError.illegalMove(rawSan)
        }

        // Exact SAN match fast path (ignoring trailing check/mate marks)
        for m in legal {
            if let candidate = san(for: m, legalCache: legal) {
                let stripped = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "+#"))
                if stripped == cleaned { return m }
            }
        }

        // Permissive algebraic parser (handles e.g. e8Q without '=', unnecessary disambiguators)
        var s = cleaned
        var promo: PieceType? = nil
        if let eqIdx = s.lastIndex(of: "=") {
            let promoStr = String(s[s.index(after: eqIdx)...]).lowercased()
            promo = PieceType(rawValue: promoStr)
            s = String(s[..<eqIdx])
        } else if let last = s.last, ["Q", "R", "B", "N", "q", "r", "b", "n"].contains(String(last)), s.count >= 3 {
            let withoutLast = String(s.dropLast())
            if withoutLast.last?.isNumber == true {
                promo = PieceType(rawValue: last.lowercased())
                s = withoutLast
            }
        }

        let pieceType: PieceType
        if let first = s.first, ["N", "B", "R", "Q", "K"].contains(String(first)) {
            guard let pt = PieceType(rawValue: first.lowercased()) else {
                throw ChessError.invalidSAN(rawSan)
            }
            pieceType = pt
            s.removeFirst()
        } else {
            pieceType = .pawn
        }

        s = s.replacingOccurrences(of: "x", with: "")
        guard s.count >= 2 else { throw ChessError.invalidSAN(rawSan) }
        let destStr = String(s.suffix(2))
        guard let dest = Square(algebraic: destStr) else {
            throw ChessError.invalidSAN(rawSan)
        }
        let disambig = String(s.dropLast(2))
        var reqFile: Int?
        var reqRank: Int?
        for ch in disambig {
            guard let ascii = ch.asciiValue else {
                throw ChessError.invalidSAN(rawSan)
            }
            if ascii >= UInt8(ascii: "a") && ascii <= UInt8(ascii: "h") {
                reqFile = Int(ascii - UInt8(ascii: "a"))
            } else if ascii >= UInt8(ascii: "1") && ascii <= UInt8(ascii: "8") {
                reqRank = Int(ascii - UInt8(ascii: "1"))
            } else {
                throw ChessError.invalidSAN(rawSan)
            }
        }

        let matches = legal.filter { m in
            guard m.to == dest,
                  squares[m.from.rawValue]?.type == pieceType,
                  m.promotion == promo else { return false }
            if let rf = reqFile, m.from.file != rf { return false }
            if let rr = reqRank, m.from.rank != rr { return false }
            return true
        }
        if matches.count == 1 {
            return matches[0]
        }
        throw ChessError.illegalMove(rawSan)
    }

    // MARK: - Game State & Outcome

    public var isInsufficientMaterial: Bool {
        var minorPieces: [(PieceColor, PieceType, Square)] = []
        for idx in 0..<64 {
            guard let p = squares[idx], p.type != .king else { continue }
            if p.type == .pawn || p.type == .rook || p.type == .queen { return false }
            minorPieces.append((p.color, p.type, Square(unchecked: idx)))
        }
        if minorPieces.count <= 1 { return true }
        if minorPieces.count == 2 &&
           minorPieces[0].1 == .bishop &&
           minorPieces[1].1 == .bishop &&
           minorPieces[0].2.isLightSquare == minorPieces[1].2.isLightSquare {
            return true
        }
        return false
    }

    public var outcome: GameOutcome {
        let moves = legalMoves()
        if moves.isEmpty {
            return isInCheck() ? .checkmate(winner: turn.opposite) : .stalemate
        }
        if halfmoveClock >= 100 { return .fiftyMoveRule }
        if isInsufficientMaterial { return .insufficientMaterial }
        return .ongoing
    }

    /// Fast short-circuiting check used by the search engine to detect horizon stalemates without allocating a full move list.
    public func hasAnyLegalMove() -> Bool {
        !legalMoves().isEmpty
    }

    /// Standard Perft node count for exact FIDE legal move verification.
    public func perft(depth: Int) -> UInt64 {
        if depth <= 0 { return 1 }
        let moves = legalMoves()
        if depth == 1 { return UInt64(moves.count) }
        var total: UInt64 = 0
        for m in moves {
            var next = self
            next.makeMoveUnchecked(m)
            total += next.perft(depth: depth - 1)
        }
        return total
    }

    // MARK: - Direction Tables

    private static let knightOffsets: [(Int, Int)] = [
        (-2, -1), (-2, 1), (-1, -2), (-1, 2),
        (1, -2), (1, 2), (2, -1), (2, 1),
    ]
    private static let rookDirs: [(Int, Int)] = [
        (1, 0), (-1, 0), (0, 1), (0, -1),
    ]
    private static let bishopDirs: [(Int, Int)] = [
        (1, 1), (1, -1), (-1, 1), (-1, -1),
    ]
    private static let kingOffsets: [(Int, Int)] = [
        (1, 0), (-1, 0), (0, 1), (0, -1),
        (1, 1), (1, -1), (-1, 1), (-1, -1),
    ]

    public var materialBalance: MaterialBalance {
        ChessMath.materialBalance(in: self)
    }
}
