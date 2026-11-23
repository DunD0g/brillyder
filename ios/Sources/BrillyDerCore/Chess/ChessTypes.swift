import Foundation

public enum PieceColor: String, Codable, Hashable, Sendable, CaseIterable {
    case white = "w"
    case black = "b"

    public var opposite: PieceColor {
        self == .white ? .black : .white
    }

    public var sideName: String {
        self == .white ? "white" : "black"
    }

    public var displayName: String {
        self == .white ? "White" : "Black"
    }
}

public enum PieceType: String, Codable, Hashable, Sendable, CaseIterable {
    case pawn = "p"
    case knight = "n"
    case bishop = "b"
    case rook = "r"
    case queen = "q"
    case king = "k"

    public var sanLetter: String {
        switch self {
        case .pawn: return ""
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }

    public var displayName: String {
        switch self {
        case .pawn: return "pawn"
        case .knight: return "knight"
        case .bishop: return "bishop"
        case .rook: return "rook"
        case .queen: return "queen"
        case .king: return "king"
        }
    }

    public var materialValue: Int {
        switch self {
        case .pawn: return 1
        case .knight, .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 0
        }
    }

    public var seeValue: Int {
        self == .king ? 1000 : materialValue
    }

    public var centipawnValue: Int {
        switch self {
        case .pawn: return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook: return 500
        case .queen: return 900
        case .king: return 20000
        }
    }

    public static let promotionChoices: [PieceType] = [.queen, .rook, .bishop, .knight]
}

public struct Piece: Hashable, Sendable, Codable {
    public let color: PieceColor
    public let type: PieceType

    public init(color: PieceColor, type: PieceType) {
        self.color = color
        self.type = type
    }

    public var fenChar: Character {
        let base: Character
        switch type {
        case .pawn: base = "p"
        case .knight: base = "n"
        case .bishop: base = "b"
        case .rook: base = "r"
        case .queen: base = "q"
        case .king: base = "k"
        }
        return color == .white ? Character(base.uppercased()) : base
    }

    public init?(fenChar: Character) {
        let color: PieceColor = fenChar.isUppercase ? .white : .black
        guard let type = PieceType(rawValue: fenChar.lowercased()) else { return nil }
        self.color = color
        self.type = type
    }
}

/// 0 = a1, 7 = h1, 56 = a8, 63 = h8
public struct Square: RawRepresentable, Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let rawValue: Int

    public init?(rawValue: Int) {
        guard (0..<64).contains(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    @inline(__always)
    public init(unchecked index: Int) {
        self.rawValue = index
    }

    public init?(file: Int, rank: Int) {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        self.rawValue = rank * 8 + file
    }

    public init?(algebraic: String) {
        let bytes = Array(algebraic.lowercased().utf8)
        guard bytes.count == 2 else { return nil }
        let file = Int(bytes[0]) - Int(UInt8(ascii: "a"))
        let rank = Int(bytes[1]) - Int(UInt8(ascii: "1"))
        self.init(file: file, rank: rank)
    }

    @inline(__always)
    public var file: Int { rawValue & 7 }

    @inline(__always)
    public var rank: Int { rawValue >> 3 }

    public var isLightSquare: Bool {
        (file + rank) % 2 == 1
    }

    public var fileChar: Character {
        Character(UnicodeScalar(UInt8(ascii: "a") + UInt8(file)))
    }

    public var rankChar: Character {
        Character(UnicodeScalar(UInt8(ascii: "1") + UInt8(rank)))
    }

    public var algebraic: String {
        "\(fileChar)\(rankChar)"
    }

    public var description: String { algebraic }

    public static func < (lhs: Square, rhs: Square) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static let allSquares: [Square] = (0..<64).map { Square(unchecked: $0) }

    public static let a1 = Square(unchecked: 0)
    public static let b1 = Square(unchecked: 1)
    public static let c1 = Square(unchecked: 2)
    public static let d1 = Square(unchecked: 3)
    public static let e1 = Square(unchecked: 4)
    public static let f1 = Square(unchecked: 5)
    public static let g1 = Square(unchecked: 6)
    public static let h1 = Square(unchecked: 7)
    public static let a8 = Square(unchecked: 56)
    public static let b8 = Square(unchecked: 57)
    public static let c8 = Square(unchecked: 58)
    public static let d8 = Square(unchecked: 59)
    public static let e8 = Square(unchecked: 60)
    public static let f8 = Square(unchecked: 61)
    public static let g8 = Square(unchecked: 62)
    public static let h8 = Square(unchecked: 63)
}

public struct CastlingRights: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let whiteKingside  = CastlingRights(rawValue: 1 << 0)
    public static let whiteQueenside = CastlingRights(rawValue: 1 << 1)
    public static let blackKingside  = CastlingRights(rawValue: 1 << 2)
    public static let blackQueenside = CastlingRights(rawValue: 1 << 3)
    public static let all: CastlingRights = [.whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside]

    public var fenString: String {
        if isEmpty { return "-" }
        var s = ""
        if contains(.whiteKingside) { s.append("K") }
        if contains(.whiteQueenside) { s.append("Q") }
        if contains(.blackKingside) { s.append("k") }
        if contains(.blackQueenside) { s.append("q") }
        return s
    }

    public init?(fen: String) {
        if fen == "-" {
            self = []
            return
        }
        var rights: CastlingRights = []
        for ch in fen {
            switch ch {
            case "K": rights.insert(.whiteKingside)
            case "Q": rights.insert(.whiteQueenside)
            case "k": rights.insert(.blackKingside)
            case "q": rights.insert(.blackQueenside)
            default: return nil
            }
        }
        self = rights
    }
}

public struct ChessMove: Hashable, Sendable, Codable, CustomStringConvertible {
    public let from: Square
    public let to: Square
    public let promotion: PieceType?

    public init(from: Square, to: Square, promotion: PieceType? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    public init?(uci: String) {
        let trimmed = uci.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == 4 || trimmed.count == 5 else { return nil }
        let idx2 = trimmed.index(trimmed.startIndex, offsetBy: 2)
        let idx4 = trimmed.index(trimmed.startIndex, offsetBy: 4)
        guard
            let from = Square(algebraic: String(trimmed[..<idx2])),
            let to = Square(algebraic: String(trimmed[idx2..<idx4]))
        else { return nil }
        var promo: PieceType? = nil
        if trimmed.count == 5 {
            guard let p = PieceType(rawValue: String(trimmed[idx4])),
                  p != .pawn && p != .king else { return nil }
            promo = p
        }
        self.from = from
        self.to = to
        self.promotion = promo
    }

    public var uci: String {
        "\(from.algebraic)\(to.algebraic)\(promotion?.rawValue ?? "")"
    }

    public var description: String { uci }
}

public struct AppliedMove: Hashable, Sendable {
    public let move: ChessMove
    public let piece: Piece
    public let captured: Piece?
    public let isEnPassant: Bool
    public let isCastleKingside: Bool
    public let isCastleQueenside: Bool
    public let san: String
    public let beforeFen: String
    public let afterFen: String
}

public enum GameOutcome: Hashable, Sendable {
    case ongoing
    case checkmate(winner: PieceColor)
    case stalemate
    case insufficientMaterial
    case fiftyMoveRule
}

public enum ChessError: Error, LocalizedError, Sendable, Equatable {
    case invalidFEN(String)
    case illegalMove(String)
    case invalidSAN(String)
    case invalidPGN(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFEN(let msg): return "Invalid FEN: \(msg)"
        case .illegalMove(let msg): return "Illegal move: \(msg)"
        case .invalidSAN(let msg): return "Invalid SAN: \(msg)"
        case .invalidPGN(let msg): return "Invalid PGN: \(msg)"
        }
    }
}
