import Foundation
import Testing
@testable import BrillyDerCore

@Suite("Starter Courses 100% Legal SAN Validation")
struct StarterCoursesValidationTests {
    @Test("Every previewMoves, line moves, and wrongMoveTraps punishmentLine in starterCourses.json is 100% legal")
    func validateAllStarterCourses() throws {
        let courses = try CourseRepository.loadStarterCourses()
        #expect(courses.count >= 8)

        var totalPliesValidated = 0
        var totalTrapsValidated = 0

        for course in courses {
            // 1. Validate mothershipSetup.previewMoves
            var previewBoard = ChessBoard()
            for san in course.mothershipSetup.previewMoves {
                _ = try previewBoard.apply(san: san)
                totalPliesValidated += 1
            }

            // 2. Validate every line & annotation traps
            for line in course.lines {
                var board = ChessBoard()
                var fensBeforePly: [String] = []
                for san in line.moves {
                    fensBeforePly.append(board.fen)
                    _ = try board.apply(san: san)
                    totalPliesValidated += 1
                }

                for ann in line.annotations {
                    guard let traps = ann.wrongMoveTraps else { continue }
                    guard ann.ply >= 0 && ann.ply < fensBeforePly.count else {
                        Issue.record("Annotation ply \(ann.ply) out of bounds in \(course.id)/\(line.id)")
                        continue
                    }
                    for trap in traps {
                        var trapBoard = try ChessBoard(fen: fensBeforePly[ann.ply])
                        _ = try trapBoard.apply(san: trap.playedSan)
                        for pSan in trap.punishmentLine {
                            _ = try trapBoard.apply(san: pSan)
                            totalPliesValidated += 1
                        }
                        totalTrapsValidated += 1
                    }
                }

                // 3. Hydrate FSRS cards cleanly
                let cards = try CourseRepository.hydrateLineCards(
                    courseId: course.id,
                    side: course.side,
                    line: line
                )
                #expect(!cards.isEmpty)
            }
        }

        #expect(totalPliesValidated > 400)
        #expect(totalTrapsValidated > 0)
    }

    @Test("Fallback 60-Second Gravity Check flashes all have 100% legal expected moves")
    func validateFallbackGravityFlashes() throws {
        for flash in DailyCoachPlanner.fallbackGravityFlashes {
            var board = try ChessBoard(fen: flash.fen)
            let applied = try board.apply(uci: flash.expectedUci)
            #expect(applied.san == flash.expectedSan)
        }
    }
}
