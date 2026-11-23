import Foundation

public struct OpeningDeviationReport: Sendable {
    public enum Kind: String, Sendable {
        case userDeviation
        case opponentNovelty
        case inBook
    }

    public let kind: Kind
    public let courseId: String
    public let courseName: String
    public let lineId: String
    public let ply: Int
    public let moveNumber: Int
    public let playedSan: String
    public let expectedSan: String
    public let expectedUci: String
    public let fenBefore: String
    public let matchingCardId: String?
}

/// Compares plies 1–12 of an analyzed game against the user's repertoires (transposition-aware via 4-field FEN).
public enum DeviationDetector {
    public static func detect(
        analyzedGame: AnalyzedGame,
        courses: [OpeningCourse],
        fsrsCards: [FsrsOpeningCard]
    ) -> OpeningDeviationReport? {
        let userColor = analyzedGame.game.userColor ?? .white
        let targetSide: RepertoireSide = userColor == .white ? .white : .black
        let sideCourses = courses.filter { $0.side == targetSide }
        guard !sideCourses.isEmpty else { return nil }

        // Build FEN-key -> expected book moves map from courses
        struct BookExpectation {
            let courseId: String
            let courseName: String
            let lineId: String
            let expectedSan: String
            let expectedUci: String
            let ply: Int
        }

        var mapByFen: [String: [BookExpectation]] = [:]
        for course in sideCourses {
            for line in course.lines {
                var board = ChessBoard()
                for (plyIdx, san) in line.moves.prefix(16).enumerated() {
                    let key = board.positionKey
                    guard let applied = try? board.apply(san: san) else { break }
                    mapByFen[key, default: []].append(BookExpectation(
                        courseId: course.id,
                        courseName: course.name,
                        lineId: line.id,
                        expectedSan: applied.san,
                        expectedUci: applied.move.uci,
                        ply: plyIdx
                    ))
                }
            }
        }

        var matchedAny = false
        var lastMatchedCourse: (id: String, name: String, lineId: String)? = nil

        for ply in analyzedGame.plies.prefix(16) {
            let beforeKey = (try? ChessBoard(fen: ply.beforeFen).positionKey) ?? ""
            guard let expectations = mapByFen[beforeKey], !expectations.isEmpty else {
                break
            }
            if let hit = expectations.first(where: { $0.expectedUci == ply.uci }) {
                matchedAny = true
                lastMatchedCourse = (hit.courseId, hit.courseName, hit.lineId)
                continue
            }

            // Found first deviation after at least 1 matched ply!
            guard matchedAny, let bestExp = expectations.first else { return nil }
            let cardMatch = fsrsCards.first {
                $0.courseId == bestExp.courseId &&
                $0.lineId == bestExp.lineId &&
                $0.expectedUci == bestExp.expectedUci
            }

            return OpeningDeviationReport(
                kind: ply.color == userColor ? .userDeviation : .opponentNovelty,
                courseId: bestExp.courseId,
                courseName: bestExp.courseName,
                lineId: bestExp.lineId,
                ply: ply.ply,
                moveNumber: ply.moveNumber,
                playedSan: ply.san,
                expectedSan: bestExp.expectedSan,
                expectedUci: bestExp.expectedUci,
                fenBefore: ply.beforeFen,
                matchingCardId: cardMatch?.cardId
            )
        }

        if let matched = lastMatchedCourse, let lastPly = analyzedGame.plies.prefix(16).last {
            return OpeningDeviationReport(
                kind: .inBook,
                courseId: matched.id,
                courseName: matched.name,
                lineId: matched.lineId,
                ply: lastPly.ply,
                moveNumber: lastPly.moveNumber,
                playedSan: lastPly.san,
                expectedSan: lastPly.san,
                expectedUci: lastPly.uci,
                fenBefore: lastPly.beforeFen,
                matchingCardId: nil
            )
        }
        return nil
    }
}
