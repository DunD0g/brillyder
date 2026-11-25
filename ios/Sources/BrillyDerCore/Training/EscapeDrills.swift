import Foundation

public enum EscapeTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case stalemateSac = "Stalemate Sac"
    case desperadoRook = "Desperado Rook"
    case perpetualSave = "Perpetual Save"

    public var id: String { rawValue }

    public var badgeSymbol: String {
        switch self {
        case .stalemateSac: return "crown.fill"
        case .desperadoRook: return "shield.lefthalf.filled"
        case .perpetualSave: return "arrow.triangle.2.circlepath"
        }
    }
}

public struct EscapePuzzle: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let theme: EscapeTheme
    public let fen: String
    public let userColor: PieceColor
    /// Alternating sequence starting with user's move:
    /// - 2-ply stalemate sac: `[userSacUci, opponentForcedCaptureUci]` -> every legal opponent reply reaches true stalemate.
    /// - 3-ply perpetual save: `[userCheck1Uci, opponentForcedReplyUci, userCheck2Uci]` -> every legal reply is 100% forced into a repeating perpetual check.
    public let solutionUcis: [String]
    public let solutionSans: [String]
    public let coachingTip: String

    public init(
        id: String,
        title: String,
        theme: EscapeTheme,
        fen: String,
        userColor: PieceColor,
        solutionUcis: [String],
        solutionSans: [String],
        coachingTip: String
    ) {
        self.id = id
        self.title = title
        self.theme = theme
        self.fen = fen
        self.userColor = userColor
        self.solutionUcis = solutionUcis
        self.solutionSans = solutionSans
        self.coachingTip = coachingTip
    }
}

public enum EscapeLibrary {
    public static let allPuzzles: [EscapePuzzle] = [
        EscapePuzzle(
            id: "escape-queen-g7-corner",
            title: "The Corner Queen Gift",
            theme: .stalemateSac,
            fen: "6k1/7p/7Q/8/8/8/5q2/7K w - - 0 1",
            userColor: .white,
            solutionUcis: ["h6g7", "g8g7"],
            solutionSans: ["Qg7+", "Kxg7"],
            coachingTip: "Your king on h1 already has zero legal moves because of Black's f2 queen. Give your queen away with check on g7 — Kxg7 is the only legal move and triggers instant stalemate!"
        ),
        EscapePuzzle(
            id: "escape-queen-g8-dive",
            title: "Sky-Dive Queen on g8",
            theme: .stalemateSac,
            fen: "8/6k1/5ppp/3Q4/8/8/2q5/K7 w - - 0 1",
            userColor: .white,
            solutionUcis: ["d5g8", "g7g8"],
            solutionSans: ["Qg8+", "Kxg8"],
            coachingTip: "Black's c2 queen seals your king on a1, and Black's own pawns box in their king. Launch Qg8+! — Kxg8 is 100% forced and stalemates White."
        ),
        EscapePuzzle(
            id: "escape-black-qh2-sac",
            title: "Never Resign on h2",
            theme: .stalemateSac,
            fen: "1q5k/5Q2/8/8/8/8/5PP1/7K b - - 0 1",
            userColor: .black,
            solutionUcis: ["b8h2", "h1h2"],
            solutionSans: ["Qh2+", "Kxh2"],
            coachingTip: "White's f7 queen cages your king on h8. Crash into h2 with check — Kxh2 is the only legal reply and saves half a point by stalemate!"
        ),
        EscapePuzzle(
            id: "escape-black-qg1-sac",
            title: "Desperado Queen on g1",
            theme: .stalemateSac,
            fen: "k7/2Q5/1q6/8/8/8/6PP/7K b - - 0 1",
            userColor: .black,
            solutionUcis: ["b6g1", "h1g1"],
            solutionSans: ["Qg1+", "Kxg1"],
            coachingTip: "Your king on a8 is boxed in by White's c7 queen. Throw your queen onto g1 with check — Kxg1 is forced and seals instant stalemate."
        ),
        EscapePuzzle(
            id: "escape-rook-f8-sac",
            title: "Back-Rank Rook Desperado",
            theme: .desperadoRook,
            fen: "6k1/6pp/5R2/8/8/6q1/3r4/7K w - - 0 1",
            userColor: .white,
            solutionUcis: ["f6f8", "g8f8"],
            solutionSans: ["Rf8+", "Kxf8"],
            coachingTip: "Black's g3 queen freezes your h1 king and can't reach f8. Sacrifice your last piece with Rf8+! — Kxf8 is Black's only legal move and triggers instant stalemate."
        ),
        EscapePuzzle(
            id: "escape-black-rook-g1",
            title: "Kamikaze Rook on g1",
            theme: .desperadoRook,
            fen: "7k/5Q2/6r1/8/8/8/5P1P/7K b - - 0 1",
            userColor: .black,
            solutionUcis: ["g6g1", "h1g1"],
            solutionSans: ["Rg1+", "Kxg1"],
            coachingTip: "White threatens mate on g7 and f8, and your h8 king has zero squares. Drop Rg1+! — Kxg1 is White's only legal move and forces stalemate."
        ),
        EscapePuzzle(
            id: "escape-rook-a7-gift",
            title: "The Unwanted Rook on a7",
            theme: .desperadoRook,
            fen: "kr6/pp6/R7/8/8/6q1/8/7K w - - 0 1",
            userColor: .white,
            solutionUcis: ["a6a7", "a8a7"],
            solutionSans: ["Rxa7+", "Kxa7"],
            coachingTip: "Black's g3 queen locks your h1 king in the corner. Smash Rxa7+! — Black's b8 rook and b7 pawn trap their own king, so Kxa7 is forced stalemate."
        ),
        EscapePuzzle(
            id: "escape-rook-g7-swindle",
            title: "The Mad Rook on g7",
            theme: .desperadoRook,
            fen: "5nkr/5ppp/8/8/8/6R1/2q5/K7 w - - 0 1",
            userColor: .white,
            solutionUcis: ["g3g7", "g8g7"],
            solutionSans: ["Rxg7+", "Kxg7"],
            coachingTip: "Your king on a1 is already stalemated by Qc2. Crash Rxg7+! — Black's own pieces box in their king, forcing Kxg7 stalemate."
        ),
        EscapePuzzle(
            id: "escape-perpetual-e1-h4",
            title: "Perpetual Escape Down a Queen",
            theme: .perpetualSave,
            fen: "6k1/1QR2ppp/8/8/8/4qP2/6P1/7K b - - 0 1",
            userColor: .black,
            solutionUcis: ["e3e1", "h1h2", "e1h4"],
            solutionSans: ["Qe1+", "Kh2", "Qh4+"],
            coachingTip: "Down a queen and a rook! Start with Qe1+ (forcing Kh2), then swing Qh4+ (forcing Kg1) — White's king can never escape the e1-h4 perpetual shuttle."
        ),
        EscapePuzzle(
            id: "escape-perpetual-e8-h5",
            title: "The e8-h5 Perpetual Shuttle",
            theme: .perpetualSave,
            fen: "7k/6p1/4Qp2/8/8/8/1qr2PPP/6K1 w - - 0 1",
            userColor: .white,
            solutionUcis: ["e6e8", "h8h7", "e8h5"],
            solutionSans: ["Qe8+", "Kh7", "Qh5+"],
            coachingTip: "Black is up a full queen and rook and threatens back-rank mate. Play Qe8+ (forcing Kh7), then Qh5+ (forcing Kg8) for an unstoppable perpetual draw!"
        )
    ]
}
