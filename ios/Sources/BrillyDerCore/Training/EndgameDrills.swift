import Foundation

public enum EndgameCategory: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case pawn = "Pawn"
    case rook = "Rook"
    case minorPiece = "Minor Piece"
    case queen = "Queen"
    case rookMinor = "Rook+Minor"

    public var id: String { rawValue }
}

public enum EndgameGoal: String, Codable, Hashable, Sendable {
    case win
    case draw
}

public struct EndgameDrill: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let category: EndgameCategory
    public let goal: EndgameGoal
    public let difficulty: String
    public let fen: String
    public let userColor: PieceColor
    public let keyIdea: String
    public let firstHintSan: String
    public let source: String // "theory" | "user-game"
    public let sourceGameId: String?
    public let opponentName: String?

    public init(
        id: String,
        title: String,
        category: EndgameCategory,
        goal: EndgameGoal,
        difficulty: String,
        fen: String,
        userColor: PieceColor,
        keyIdea: String,
        firstHintSan: String,
        source: String = "theory",
        sourceGameId: String? = nil,
        opponentName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.goal = goal
        self.difficulty = difficulty
        self.fen = fen
        self.userColor = userColor
        self.keyIdea = keyIdea
        self.firstHintSan = firstHintSan
        self.source = source
        self.sourceGameId = sourceGameId
        self.opponentName = opponentName
    }
}

public enum EndgameLibrary {
    /// 12 verified <=7-piece theoretical endgames identical to the Web PWA's audited suite.
    public static let theoreticalDrills: [EndgameDrill] = [
        EndgameDrill(
            id: "eg_pawn_opposition",
            title: "King & Pawn — Outflank from the 5th Rank",
            category: .pawn, goal: .win, difficulty: "Essential",
            fen: "4k3/8/8/4K3/4P3/8/8/8 w - - 0 1",
            userColor: .white,
            keyIdea: "Your king is ahead of the pawn! Step onto a key 6th-rank square (Kd6 or Kf6) to seize outflanking squares and escort the pawn home.",
            firstHintSan: "Kd6"
        ),
        EndgameDrill(
            id: "eg_pawn_key_squares",
            title: "Key Squares — Outflank the Defender",
            category: .pawn, goal: .win, difficulty: "Essential",
            fen: "3k4/8/3K4/8/3P4/8/8/8 w - - 0 1",
            userColor: .white,
            keyIdea: "Your king is already on the 6th rank in front of the pawn — step sideways or push d5 to win regardless of opposition.",
            firstHintSan: "Ke6"
        ),
        EndgameDrill(
            id: "eg_pawn_opposition_draw",
            title: "Defending K+P vs K — Hold Opposition",
            category: .pawn, goal: .draw, difficulty: "Essential",
            fen: "4k3/8/4P3/4K3/8/8/8/8 b - - 0 1",
            userColor: .black,
            keyIdea: "Retreat straight back to e7/e8 and always step directly in front of White's king when it advances.",
            firstHintSan: "Ke7"
        ),
        EndgameDrill(
            id: "eg_pawn_outside_passer",
            title: "Outside Passed Pawn Decoy",
            category: .pawn, goal: .win, difficulty: "Club",
            fen: "8/8/3k4/p7/P1K4P/8/8/8 w - - 0 1",
            userColor: .white,
            keyIdea: "Push the outside h-pawn (h5!) to drag Black's king away from the queenside, then infiltrate to b5 and capture on a5.",
            firstHintSan: "h5"
        ),
        EndgameDrill(
            id: "eg_rook_lucena",
            title: "The Lucena Position (Build a Bridge)",
            category: .rook, goal: .win, difficulty: "Essential",
            fen: "1K1k4/1P6/8/8/8/8/r7/2R5 w - - 0 1",
            userColor: .white,
            keyIdea: "Cut off Black's king with Rc4 (the 4th-rank bridge), then step out with your king and shield checks on the 4th rank.",
            firstHintSan: "Rc4"
        ),
        EndgameDrill(
            id: "eg_rook_philidor",
            title: "Philidor Defense (Back-Rank Checks)",
            category: .rook, goal: .draw, difficulty: "Essential",
            fen: "4k3/8/3P4/4K3/8/r7/5R2/8 b - - 0 1",
            userColor: .black,
            keyIdea: "Once the pawn reaches the 6th rank, swing your rook to the 1st rank (Ra1!) for endless checks from behind.",
            firstHintSan: "Ra1"
        ),
        EndgameDrill(
            id: "eg_rook_cutoff",
            title: "Rook Cutoff — Keep the King Out",
            category: .rook, goal: .win, difficulty: "Club",
            fen: "8/8/2k5/4P3/4K3/8/1r6/3R4 w - - 0 1",
            userColor: .white,
            keyIdea: "Cut Black's king off along the d-file (Rd6+) and march the e-pawn with king support.",
            firstHintSan: "Rd6+"
        ),
        EndgameDrill(
            id: "eg_rook_vancura",
            title: "Vancura Defense — Side Attack on a7",
            category: .rook, goal: .draw, difficulty: "Master",
            fen: "R7/P4k2/5r2/8/8/8/6K1/8 b - - 0 1",
            userColor: .black,
            keyIdea: "Attack the a7 pawn laterally with Ra6! Keep White's rook tied to a8 while your king stays tucked safely on g7/f7.",
            firstHintSan: "Ra6"
        ),
        EndgameDrill(
            id: "eg_minor_wrong_bishop",
            title: "Wrong-Color Rook Pawn — Fortress Draw",
            category: .minorPiece, goal: .draw, difficulty: "Essential",
            fen: "8/6k1/8/7P/6K1/5B2/8/8 b - - 0 1",
            userColor: .black,
            keyIdea: "The h8 corner is dark while White's bishop is light-squared! Tuck your king into h8/g8 and hold the fortress draw.",
            firstHintSan: "Kh8"
        ),
        EndgameDrill(
            id: "eg_minor_knight_blockade",
            title: "Knight + Pawn vs Lone King Technique",
            category: .minorPiece, goal: .win, difficulty: "Club",
            fen: "8/8/4k3/8/3PK3/4N3/8/8 w - - 0 1",
            userColor: .white,
            keyIdea: "Push d5+ and use the knight to deny defensive squares while your king takes space in front of the pawn.",
            firstHintSan: "d5+"
        ),
        EndgameDrill(
            id: "eg_queen_vs_7th",
            title: "Queen vs 7th-Rank Center Pawn",
            category: .queen, goal: .win, difficulty: "Club",
            fen: "8/8/8/1Q6/8/6K1/3p4/2k5 w - - 0 1",
            userColor: .white,
            keyIdea: "Deliver stair-step checks (Qc4+!) to force Black's king onto d1 in front of its own pawn, winning a tempo to walk your king closer.",
            firstHintSan: "Qc4+"
        ),
        EndgameDrill(
            id: "eg_rook_minor_convert",
            title: "Rook + Bishop vs Rook — 6th-Rank Squeeze",
            category: .rookMinor, goal: .win, difficulty: "Master",
            fen: "4k3/8/3K4/3B4/8/8/5r2/R7 w - - 0 1",
            userColor: .white,
            keyIdea: "Drive Black's king into the corner with Re1+ / Ra8+, coordinating king, rook, and bishop to force mate or win the rook.",
            firstHintSan: "Re1+"
        ),
    ]

    public static func classifyCategory(fen: String) -> EndgameCategory {
        let boardPart = fen.split(separator: " ").first.map(String.init) ?? ""
        let hasQ = boardPart.contains("Q") || boardPart.contains("q")
        let hasR = boardPart.contains("R") || boardPart.contains("r")
        let hasMinor = boardPart.contains("B") || boardPart.contains("b") || boardPart.contains("N") || boardPart.contains("n")
        if hasQ { return .queen }
        if hasR && hasMinor { return .rookMinor }
        if hasR { return .rook }
        if hasMinor { return .minorPiece }
        return .pawn
    }

    public static func extractUserEndgameDrills(
        from analyzedGames: [AnalyzedGame],
        handles: [String]
    ) -> [EndgameDrill] {
        var drills: [(playedAt: Int64, drill: EndgameDrill)] = []

        for ag in analyzedGames where !ag.game.isCustomFenGame && !ag.plies.isEmpty {
            guard let color = ag.game.resolvedUserColor(handles: handles) ?? ag.game.userColor else { continue }
            let opp = color == .black ? ag.game.white.name : ag.game.black.name

            // Pick at most the 1 worst <=7-piece endgame slip per game
            var worstPly: AnalyzedPly? = nil
            for p in ag.plies where p.color == color {
                guard p.classification == .blunder || p.classification == .mistake else { continue }
                guard !p.bestMoveUci.isEmpty && p.bestMoveUci != p.uci else { continue }
                guard SyzygyClient.isEligible(fen: p.beforeFen) else { continue }
                let moverCp = p.color == .white ? p.evalBefore.cpWhite : -p.evalBefore.cpWhite
                guard moverCp >= -100 else { continue }
                if worstPly == nil || p.winLoss > worstPly!.winLoss {
                    worstPly = p
                }
            }

            if let p = worstPly {
                let moverCp = p.color == .white ? p.evalBefore.cpWhite : -p.evalBefore.cpWhite
                let goal: EndgameGoal = moverCp >= 120 ? .win : .draw
                let cat = classifyCategory(fen: p.beforeFen)
                drills.append((
                    playedAt: ag.game.createdAt,
                    drill: EndgameDrill(
                        id: "eg_user_\(ag.id)_\(p.ply)",
                        title: "vs \(opp) · Move \(p.moveNumber) (\(cat.rawValue))",
                        category: cat,
                        goal: goal,
                        difficulty: "Your Game",
                        fen: p.beforeFen,
                        userColor: p.color,
                        keyIdea: "In your game you played \(p.san) (-\(Int(p.winLoss.rounded()))% win). Find \(p.bestMoveSan) and convert cleanly!",
                        firstHintSan: p.bestMoveSan,
                        source: "user-game",
                        sourceGameId: ag.id,
                        opponentName: opp
                    )
                ))
            }
        }
        return drills.sorted { $0.playedAt > $1.playedAt }.map(\.drill)
    }
}
