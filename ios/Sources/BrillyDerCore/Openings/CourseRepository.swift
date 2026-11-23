import Foundation

public enum CourseRepository {
    public static func loadStarterCourses() throws -> [OpeningCourse] {
        guard let url = Bundle.module.url(forResource: "starterCourses", withExtension: "json") else {
            throw NSError(
                domain: "BrillyDerCore",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Bundled starterCourses.json not found"]
            )
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([OpeningCourse].self, from: data)
    }

    /// Hydrates all user-move FSRS decision points from a single OpeningLine via `ChessBoard`.
    public static func hydrateLineCards(
        courseId: String,
        side: RepertoireSide,
        line: OpeningLine,
        existingById: [String: FsrsOpeningCard] = [:],
        unlocked: Bool = false,
        now: Date = Date()
    ) throws -> [FsrsOpeningCard] {
        var board = ChessBoard()
        let targetColor = side.pieceColor
        var cards: [FsrsOpeningCard] = []
        var prefix: [String] = []

        for (ply, san) in line.moves.enumerated() {
            let fenBefore = board.fen
            let applied = try board.apply(san: san)
            let uci = applied.move.uci

            if applied.piece.color == targetColor {
                let cardId = FSRS6Scheduler.buildCardId(courseId: courseId, lineId: line.id, ply: ply, expectedUci: uci)
                if var existing = existingById[cardId] {
                    if unlocked && !existing.unlocked {
                        existing.unlocked = true
                    }
                    cards.append(existing)
                } else {
                    cards.append(FSRS6Scheduler.createCard(
                        courseId: courseId,
                        lineId: line.id,
                        side: side,
                        fen: fenBefore,
                        ply: ply,
                        moveSequence: prefix,
                        expectedSan: applied.san,
                        expectedUci: uci,
                        source: "course",
                        unlocked: unlocked,
                        now: now
                    ))
                }
            }
            prefix.append(applied.san)
        }
        return cards
    }

    public static func hydrateCourseCards(
        course: OpeningCourse,
        existingById: [String: FsrsOpeningCard] = [:],
        unlocked: Bool = false,
        now: Date = Date()
    ) throws -> [FsrsOpeningCard] {
        var all: [FsrsOpeningCard] = []
        for line in course.lines {
            let lineCards = try hydrateLineCards(
                courseId: course.id,
                side: course.side,
                line: line,
                existingById: existingById,
                unlocked: unlocked,
                now: now
            )
            all.append(contentsOf: lineCards)
        }
        return all
    }
}
