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
    /// - 2-ply stalemate sac: `[userSacUci, opponentForcedCaptureUci]` -> reaches true stalemate.
    /// - 3-ply perpetual save: `[userCheck1Uci, opponentForcedReplyUci, userCheck2Uci]` -> reaches repeating perpetual check.
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
            coachingTip: "Your king on h1 already has zero legal moves because of Black's f2 queen. Give your queen away with check on g7 — once Black takes, it's instant stalemate!"
        ),
        EscapePuzzle(
            id: "escape-queen-g8-dive",
            title: "Sky-Dive Queen on g8",
            theme: .stalemateSac,
            fen: "8/6kp/5pp1/3Q4/8/8/2q5/K7 w - - 0 1",
            userColor: .white,
            solutionUcis: ["d5g8", "g7g8"],
            solutionSans: ["Qg8+", "Kxg8"],
            coachingTip: "Black's c2 queen already seals your king in the a1 corner. Launch Qg8+! so Kxg8 leaves White completely stalemated."
        ),
        EscapePuzzle(
            id: "escape-black-qh2-sac",
            title: "Never Resign on h2",
            theme: .stalemateSac,
            fen: "1q5k/5Q2/8/8/8/8/5PP1/7K b - - 0 1",
            userColor: .black,
            solutionUcis: ["b8h2", "h1h2"],
            solutionSans: ["Qh2+", "Kxh2"],
            coachingTip: "White's f7 queen cages your king on h8. Crash into h2 with check — Kxh2 is forced and saves half a point by stalemate!"
        ),
        EscapePuzzle(
            id: "escape-black-qg1-sac",
            title: "Desperado Queen on g1",
            theme: .stalemateSac,
            fen: "k7/2Q5/1q6/8/8/8/6PP/7K b - - 0 1",
            userColor: .black,
            solutionUcis: ["b6g1", "h1g1"],
            solutionSans: ["Qg1+", "Kxg1"],
            coachingTip: "Your king on a8 is boxed in by White's c7 queen. Throw your queen onto g1 with check to force Kxg1 stalemate."
        ),
        EscapePuzzle(
            id: "escape-rook-f8-sac",
            title: "Back-Rank Rook Desperado",
            theme: .desperadoRook,
            fen: "6k1/6pp/5R2/8/8/8/3r1q2/7K w - - 0 1",
            userColor: .white,
            solutionUcis: ["f6f8", "g8f8"],
            solutionSans: ["Rf8+", "Kxf8"],
            coachingTip: "Down a queen and a rook, your h1 king is already frozen. Sacrifice your last piece with Rf8+! — Kxf8 triggers immediate stalemate."
        ),
        EscapePuzzle(
            id: "escape-black-rook-g2",
            title: "Kamikaze Rook on g2",
            theme: .desperadoRook,
            fen: "7k/5Q2/6r1/8/8/8/5PPP/6K1 b - - 0 1",
            userColor: .black,
            solutionUcis: ["g6g2", "g1g2"],
            solutionSans: ["Rxg2+", "Kxg2"],
            coachingTip: "White threatens mate on g7 and f8, and your king has no squares. Smash Rxg2+! so Kxg2 seals a brilliant stalemate draw."
        ),
        EscapePuzzle(
            id: "escape-rook-h7-gift",
            title: "The Unwanted Rook on h7",
            theme: .desperadoRook,
            fen: "7k/1R6/6pp/8/8/8/2q5/K7 w - - 0 1",
            userColor: .white,
            solutionUcis: ["b7h7", "h8h7"],
            solutionSans: ["Rh7+", "Kxh7"],
            coachingTip: "Down a queen vs rook, your king on a1 cannot move. Offer the mad rook with Rh7+ — taking it is instant stalemate!"
        ),
        EscapePuzzle(
            id: "escape-rook-g7-swindle",
            title: "The Mad Rook on g7",
            theme: .desperadoRook,
            fen: "6k1/4R2p/6p1/8/8/8/2q5/K7 w - - 0 1",
            userColor: .white,
            solutionUcis: ["e7g7", "g8g7"],
            solutionSans: ["Rg7+", "Kxg7"],
            coachingTip: "Whenever your king is boxed into the corner, check if your rook can throw itself at the enemy king. Rg7+ forces Kxg7 stalemate."
        ),
        EscapePuzzle(
            id: "escape-perpetual-e1-g3",
            title: "Perpetual Escape Down a Queen",
            theme: .perpetualSave,
            fen: "7k/1R1Q4/8/4q3/8/5P1P/6P1/7K b - - 0 1",
            userColor: .black,
            solutionUcis: ["e5e1", "h1h2", "e1g3"],
            solutionSans: ["Qe1+", "Kh2", "Qg3+"],
            coachingTip: "Down a queen and a rook! Start with Qe1+ (forcing Kh2), then swing Qg3+ — White's king can never escape the e1-g3 perpetual shuttle."
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
