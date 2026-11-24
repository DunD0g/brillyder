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

/// Compares plies 1–24 of an analyzed game against active repertoires (transposition-aware via normalized 4-field FEN).
public enum DeviationDetector {
    public static func detect(
        analyzedGame: AnalyzedGame,
        courses: [OpeningCourse],
        fsrsCards: [FsrsOpeningCard],
        handles: [String] = []
    ) -> OpeningDeviationReport? {
        guard let userColor = analyzedGame.game.resolvedUserColor(handles: handles) ?? analyzedGame.game.userColor else {
            return nil
        }
        // Skip custom-FEN games
        if analyzedGame.game.isCustomFenGame { return nil }
        let targetSide: RepertoireSide = userColor == .white ? .white : .black
        let sideCourses = courses.filter { $0.side == targetSide }
        guard !sideCourses.isEmpty else { return nil }

        struct BookExpectation {
            let courseId: String
            let courseName: String
            let lineId: String
            let expectedSan: String
            let expectedUci: String
            let ply: Int
        }

        var mapByFen: [String: [BookExpectation]] = [:]
        var maxBookPly = 16
        for course in sideCourses {
            for line in course.lines {
                maxBookPly = max(maxBookPly, min(24, line.moves.count))
                var board = ChessBoard()
                for (plyIdx, san) in line.moves.prefix(24).enumerated() {
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

        var activeLines: Set<String> = []
        var lastMatched: (courseId: String, courseName: String, lineId: String, ply: AnalyzedPly)? = nil
        var matchedUserMove = false

        for ply in analyzedGame.plies.prefix(maxBookPly) {
            let beforeKey = (try? ChessBoard(fen: ply.beforeFen).positionKey) ?? ""
            guard let expectations = mapByFen[beforeKey], !expectations.isEmpty else {
                break
            }
            let matchingHits = expectations.filter { $0.expectedUci == ply.uci }
            if !matchingHits.isEmpty {
                let preferred = matchingHits.first { activeLines.contains("\($0.courseId)::\($0.lineId)") } ?? matchingHits[0]
                let hitKeys = Set(matchingHits.map { "\($0.courseId)::\($0.lineId)" })
                activeLines = activeLines.isEmpty ? hitKeys : (activeLines.intersection(hitKeys).isEmpty ? hitKeys : activeLines.intersection(hitKeys))
                lastMatched = (preferred.courseId, preferred.courseName, preferred.lineId, ply)
                if ply.color == userColor { matchedUserMove = true }
                continue
            }

            // Do not falsely flag Black playing a different defense on move 1 (e.g. 1. e4 e5 vs Caro-Kann course)
            if ply.ply <= 2 && !matchedUserMove { return nil }
            guard lastMatched != nil else { return nil }
            let bestExp = expectations.first { activeLines.contains("\($0.courseId)::\($0.lineId)") } ?? expectations[0]
            let cardMatch = fsrsCards.first { card in
                card.courseId == bestExp.courseId &&
                card.lineId == bestExp.lineId &&
                card.expectedUci == bestExp.expectedUci &&
                (card.ply == bestExp.ply || ((try? ChessBoard(fen: card.fen).positionKey) == beforeKey))
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

        if let matched = lastMatched {
            return OpeningDeviationReport(
                kind: .inBook,
                courseId: matched.courseId,
                courseName: matched.courseName,
                lineId: matched.lineId,
                ply: matched.ply.ply,
                moveNumber: matched.ply.moveNumber,
                playedSan: matched.ply.san,
                expectedSan: matched.ply.san,
                expectedUci: matched.ply.uci,
                fenBefore: matched.ply.beforeFen,
                matchingCardId: nil
            )
        }
        return nil
    }
}
