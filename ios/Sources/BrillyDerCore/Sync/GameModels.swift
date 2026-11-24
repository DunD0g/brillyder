import Foundation

public struct PlayerInfo: Codable, Hashable, Sendable {
    public let name: String
    public let rating: Int?
    public let ratingDiff: Int?

    public init(name: String, rating: Int? = nil, ratingDiff: Int? = nil) {
        self.name = name
        self.rating = rating
        self.ratingDiff = ratingDiff
    }
}

public enum GameSource: String, Codable, Hashable, Sendable, CaseIterable {
    case lichess
    case chesscom
    case pgn
    case sample

    public var displayName: String {
        switch self {
        case .lichess: return "Lichess"
        case .chesscom: return "Chess.com"
        case .pgn: return "PGN"
        case .sample: return "Sample"
        }
    }
}

/// 1:1 schema match with web `LichessGameRecord`.
public struct GameRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let source: GameSource
    public let rated: Bool
    public let variant: String
    public let speed: String
    public let perf: String
    public let createdAt: Int64 // epoch ms
    public let status: String
    public let winner: String? // "white" | "black"
    public let resultString: String // "1-0" | "0-1" | "1/2-1/2" | "*"
    public let timeControlLabel: String
    public let pgn: String
    public let openingName: String
    public let openingEco: String
    public let openingPly: Int?
    public let white: PlayerInfo
    public let black: PlayerInfo
    public let userColor: PieceColor?
    public let url: String?

    public init(
        id: String,
        source: GameSource,
        rated: Bool = true,
        variant: String = "standard",
        speed: String = "rapid",
        perf: String = "rapid",
        createdAt: Int64,
        status: String = "normal",
        winner: String? = nil,
        resultString: String,
        timeControlLabel: String,
        pgn: String,
        openingName: String,
        openingEco: String = "",
        openingPly: Int? = nil,
        white: PlayerInfo,
        black: PlayerInfo,
        userColor: PieceColor? = nil,
        url: String? = nil
    ) {
        self.id = id
        self.source = source
        self.rated = rated
        self.variant = variant
        self.speed = speed
        self.perf = perf
        self.createdAt = createdAt
        self.status = status
        self.winner = winner
        self.resultString = resultString
        self.timeControlLabel = timeControlLabel
        self.pgn = pgn
        self.openingName = openingName
        self.openingEco = openingEco
        self.openingPly = openingPly
        self.white = white
        self.black = black
        self.userColor = userColor
        self.url = url
    }

    public var isCustomFenGame: Bool {
        id.hasPrefix("fen_") || perf == "custom"
    }

    public func resolvedUserColor(handles: [String]) -> PieceColor? {
        let normalized = handles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if !normalized.isEmpty {
            let wLow = white.name.lowercased()
            let bLow = black.name.lowercased()
            if normalized.contains(wLow) { return .white }
            if normalized.contains(bLow) { return .black }
        }
        return userColor
    }

    public func userResult(for username: String? = nil) -> String {
        userResult(handles: username.map { [$0] } ?? [])
    }

    public func userResult(handles: [String]) -> String {
        guard let color = resolvedUserColor(handles: handles) else { return resultString }
        if resultString == "1/2-1/2" { return "D" }
        if resultString == "1-0" { return color == .white ? "W" : "L" }
        if resultString == "0-1" { return color == .black ? "W" : "L" }
        return "*"
    }
}

public struct TopEngineLineSummary: Codable, Hashable, Sendable {
    public let san: String
    public let evalDisplay: String
    public let pvSan: [String]

    public init(san: String, evalDisplay: String, pvSan: [String]) {
        self.san = san
        self.evalDisplay = evalDisplay
        self.pvSan = pvSan
    }
}

public struct AnalyzedPly: Codable, Hashable, Sendable, Identifiable {
    public var id: Int { ply }

    public let ply: Int
    public let moveNumber: Int
    public let color: PieceColor
    public let san: String
    public let uci: String
    public let from: String
    public let to: String
    public let promotion: String?
    public let captured: String?
    public let beforeFen: String
    public let afterFen: String
    public let clockText: String?
    public let clockSeconds: Double?
    public let timeSpentSeconds: Double?
    public let clockTag: String?
    public let bestMoveUci: String
    public let bestMoveSan: String
    public let bestPvSan: [String]
    public let topLines: [TopEngineLineSummary]?
    public let threatMoveUci: String?
    public let threatMoveSan: String?
    public let evalBefore: EngineScore
    public let evalAfter: EngineScore
    public let secondBestGapWin: Double
    public let secondBestGapPawns: Double?
    public let isCriticalMoment: Bool?
    public let isClutchSave: Bool?
    public let deepened: Bool?
    public let winLoss: Double
    public let accuracy: Double
    public let classification: MoveClassification
    public let phase: GamePhase
    public let coaching: CoachingExplanation
}

public struct PlayerAnalysisSummary: Codable, Hashable, Sendable {
    public let accuracy: Double
    public let estimatedElo: Int
    public let counts: [String: Int]
    public let avgWinLoss: Double

    public init(accuracy: Double, estimatedElo: Int, counts: [String: Int], avgWinLoss: Double) {
        self.accuracy = accuracy
        self.estimatedElo = estimatedElo
        self.counts = counts
        self.avgWinLoss = avgWinLoss
    }

    public func count(for kind: MoveClassification) -> Int {
        counts[kind.rawValue] ?? 0
    }
}

public struct AnalyzedGame: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let analyzedAt: Int64
    public let depth: Int
    public let classificationVersion: Int?
    public let game: GameRecord
    public let initialEval: EngineScore
    public let plies: [AnalyzedPly]
    public let whiteSummary: PlayerAnalysisSummary
    public let blackSummary: PlayerAnalysisSummary
    public let openingLineDetected: String?
}

public struct MistakePuzzle: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let gameId: String
    public let ply: Int
    public let moveNumber: Int
    public let playerColor: PieceColor
    public let fen: String
    public let playedSan: String
    public let bestMoveUci: String
    public let bestMoveSan: String
    public let pvSan: [String]
    public let classification: MoveClassification
    public let winLoss: Double
    public let phase: GamePhase
    public let tacticalTag: String
    public let headline: String
    public let opponentName: String
    public let openingName: String
    public let playedAt: Int64
}

public struct SavedPositionBookmark: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let gameId: String
    public let ply: Int
    public let fen: String
    public let san: String
    public let moveNumber: Int
    public let color: PieceColor
    public var label: String
    public let note: String?
    public let evalDisplay: String?
    public let classification: MoveClassification?
    public let createdAt: Int64
    public var tags: [String]
    public var matchup: String?

    public init(
        id: String,
        gameId: String,
        ply: Int,
        fen: String,
        san: String,
        moveNumber: Int,
        color: PieceColor,
        label: String,
        note: String? = nil,
        evalDisplay: String? = nil,
        classification: MoveClassification? = nil,
        createdAt: Int64,
        tags: [String] = [],
        matchup: String? = nil
    ) {
        self.id = id
        self.gameId = gameId
        self.ply = ply
        self.fen = fen
        self.san = san
        self.moveNumber = moveNumber
        self.color = color
        self.label = label
        self.note = note
        self.evalDisplay = evalDisplay
        self.classification = classification
        self.createdAt = createdAt
        self.tags = tags
        self.matchup = matchup
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.gameId = try c.decode(String.self, forKey: .gameId)
        self.ply = try c.decode(Int.self, forKey: .ply)
        self.fen = try c.decode(String.self, forKey: .fen)
        self.san = try c.decode(String.self, forKey: .san)
        self.moveNumber = try c.decode(Int.self, forKey: .moveNumber)
        self.color = try c.decode(PieceColor.self, forKey: .color)
        self.label = try c.decode(String.self, forKey: .label)
        self.note = try c.decodeIfPresent(String.self, forKey: .note)
        self.evalDisplay = try c.decodeIfPresent(String.self, forKey: .evalDisplay)
        self.classification = try c.decodeIfPresent(MoveClassification.self, forKey: .classification)
        self.createdAt = try c.decode(Int64.self, forKey: .createdAt)
        self.tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        self.matchup = try? c.decodeIfPresent(String.self, forKey: .matchup)
    }
}
