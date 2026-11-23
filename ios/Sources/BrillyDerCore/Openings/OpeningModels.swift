import Foundation

public enum RepertoireSide: String, Codable, Hashable, Sendable, CaseIterable {
    case white
    case black

    public var pieceColor: PieceColor {
        self == .white ? .white : .black
    }
}

public enum ArrowKind: String, Codable, Hashable, Sendable {
    case plan
    case best
    case threat
    case outpost
}

public struct BoardArrow: Codable, Hashable, Sendable {
    public let from: String
    public let to: String
    public let color: ArrowKind

    public init(from: String, to: String, color: ArrowKind) {
        self.from = from
        self.to = to
        self.color = color
    }
}

public struct SquareHighlight: Codable, Hashable, Sendable {
    public let square: String
    public let color: ArrowKind

    public init(square: String, color: ArrowKind) {
        self.square = square
        self.color = color
    }
}

public struct WrongMoveTrap: Codable, Hashable, Sendable {
    public let playedSan: String
    public let punishmentLine: [String]
    public let reason: String
    public let arrows: [BoardArrow]?

    public init(playedSan: String, punishmentLine: [String], reason: String, arrows: [BoardArrow]? = nil) {
        self.playedSan = playedSan
        self.punishmentLine = punishmentLine
        self.reason = reason
        self.arrows = arrows
    }
}

public struct MoveAnnotation: Codable, Hashable, Sendable {
    public let ply: Int
    public let plan: String
    public let cosmicCue: String?
    public let arrows: [BoardArrow]?
    public let highlights: [SquareHighlight]?
    public let wrongMoveTraps: [WrongMoveTrap]?
    public let isCritical: Bool?

    public init(
        ply: Int,
        plan: String,
        cosmicCue: String? = nil,
        arrows: [BoardArrow]? = nil,
        highlights: [SquareHighlight]? = nil,
        wrongMoveTraps: [WrongMoveTrap]? = nil,
        isCritical: Bool? = nil
    ) {
        self.ply = ply
        self.plan = plan
        self.cosmicCue = cosmicCue
        self.arrows = arrows
        self.highlights = highlights
        self.wrongMoveTraps = wrongMoveTraps
        self.isCritical = isCritical
    }
}

public struct OpeningLine: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let eco: String
    public let frequencyNote: String
    public let moves: [String]
    public let annotations: [MoveAnnotation]

    public init(
        id: String,
        title: String,
        subtitle: String,
        eco: String,
        frequencyNote: String,
        moves: [String],
        annotations: [MoveAnnotation]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.eco = eco
        self.frequencyNote = frequencyNote
        self.moves = moves
        self.annotations = annotations
    }
}

public struct MothershipSetup: Codable, Hashable, Sendable {
    public let previewMoves: [String]
    public let arrows: [BoardArrow]
    public let highlights: [SquareHighlight]
    public let corePlans: [String]
    public let goldenRules: [String]
}

public struct OpeningCourse: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let codename: String
    public let side: RepertoireSide
    public let difficulty: String
    public let tagline: String
    public let source: String?
    public let mothershipSetup: MothershipSetup
    public let lines: [OpeningLine]
}

public struct FsrsCardState: Codable, Hashable, Sendable {
    public var due: String
    public var stability: Double
    public var difficulty: Double
    public var scheduled_days: Double
    public var learning_steps: Int
    public var reps: Int
    public var lapses: Int
    public var state: Int // 0 = New, 1 = Learning, 2 = Review, 3 = Relearning
    public var last_review: String?

    public init(
        due: String,
        stability: Double = 0,
        difficulty: Double = 0,
        scheduled_days: Double = 0,
        learning_steps: Int = 0,
        reps: Int = 0,
        lapses: Int = 0,
        state: Int = 0,
        last_review: String? = nil
    ) {
        self.due = due
        self.stability = stability
        self.difficulty = difficulty
        self.scheduled_days = scheduled_days
        self.learning_steps = learning_steps
        self.reps = reps
        self.lapses = lapses
        self.state = state
        self.last_review = last_review
    }
}

public struct FsrsOpeningCard: Codable, Hashable, Sendable, Identifiable {
    public var id: String { cardId }

    public let cardId: String
    public let courseId: String
    public let lineId: String
    public let side: RepertoireSide
    public let fen: String
    public let ply: Int
    public let moveSequence: [String]
    public let expectedSan: String
    public let expectedUci: String
    public var fsrsState: FsrsCardState
    public var dueAt: Int64 // epoch ms (matches web schema!)
    public var attempts: Int
    public var firstTryHits: Int
    public var avgResponseMs: Double
    public var source: String // "course" | "game-deviation"
    public var unlocked: Bool

    public init(
        cardId: String,
        courseId: String,
        lineId: String,
        side: RepertoireSide,
        fen: String,
        ply: Int,
        moveSequence: [String],
        expectedSan: String,
        expectedUci: String,
        fsrsState: FsrsCardState,
        dueAt: Int64,
        attempts: Int = 0,
        firstTryHits: Int = 0,
        avgResponseMs: Double = 0,
        source: String = "course",
        unlocked: Bool = false
    ) {
        self.cardId = cardId
        self.courseId = courseId
        self.lineId = lineId
        self.side = side
        self.fen = fen
        self.ply = ply
        self.moveSequence = moveSequence
        self.expectedSan = expectedSan
        self.expectedUci = expectedUci
        self.fsrsState = fsrsState
        self.dueAt = dueAt
        self.attempts = attempts
        self.firstTryHits = firstTryHits
        self.avgResponseMs = avgResponseMs
        self.source = source
        self.unlocked = unlocked
    }
}
