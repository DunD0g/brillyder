import Foundation
import Testing
@testable import BrillyDerCore

@Suite("Starter Courses 100% Legal SAN Validation")
struct StarterCoursesValidationTests {
    @Test("Every previewMoves, line moves, and wrongMoveTraps punishmentLine in starterCourses.json is 100% legal")
    func validateAllStarterCourses() throws {
        let courses = try CourseRepository.loadStarterCourses()
        #expect(courses.count >= 16)
        let ids = Set(courses.map(\.id))
        #expect(ids.contains("alien-gambit-core"))
        #expect(ids.contains("vienna-gambit-core"))
        #expect(ids.contains("stafford-gambit-core"))
        #expect(ids.contains("englund-gambit-core"))
        #expect(ids.contains("ruy-lopez-core"))
        #expect(ids.contains("caro-kann-core"))
        #expect(ids.contains("queens-gambit-core"))
        #expect(ids.contains("queens-gambit-declined-core"))
        #expect(ids.contains("queens-gambit-accepted-core"))
        if let qgWhite = courses.first(where: { $0.id == "queens-gambit-core" }) {
            let lineIds = Set(qgWhite.lines.map(\.id))
            #expect(lineIds.contains("qga-c6-qf3-refutation"))
            #expect(lineIds.contains("qga-center-seizure"))
            #expect(lineIds.contains("qga-classical-e3-nf3"))
            #expect(lineIds.contains("qgd-exchange-minority"))
            #expect(lineIds.contains("qgd-classical-bg5"))
            #expect(lineIds.contains("qgd-slav-a4-stop"))
        }

        var totalPliesValidated = 0
        var totalTrapsValidated = 0
        var totalCounterLinesValidated = 0

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

            // 4. Validate every counterGuide line is 100% legal SAN
            let counters = course.counterGuide ?? []
            #expect(!counters.isEmpty, "Course \(course.id) should include counterGuide lines")
            for counter in counters {
                var cBoard = ChessBoard()
                #expect(!counter.moves.isEmpty, "Empty counter line in \(course.id)/\(counter.id)")
                for san in counter.moves {
                    _ = try cBoard.apply(san: san)
                    totalPliesValidated += 1
                }
                totalCounterLinesValidated += 1
            }
        }

        #expect(totalPliesValidated > 700)
        #expect(totalTrapsValidated > 0)
        #expect(totalCounterLinesValidated >= 32)
    }

    @Test("Fallback 60-Second Gravity Check flashes all have 100% legal expected moves")
    func validateFallbackGravityFlashes() throws {
        for flash in DailyCoachPlanner.fallbackGravityFlashes {
            var board = try ChessBoard(fen: flash.fen)
            let applied = try board.apply(uci: flash.expectedUci)
            #expect(applied.san == flash.expectedSan)
        }
    }

    @Test("All 10 Never Give Up escape puzzles have legal FENs and genuinely force stalemate or perpetual check")
    func validateNeverGiveUpEscapePuzzles() throws {
        let puzzles = EscapeLibrary.allPuzzles
        #expect(puzzles.count == 10)
        #expect(Set(puzzles.map(\.id)).count == puzzles.count)

        for puzzle in puzzles {
            var board = try ChessBoard(fen: puzzle.fen)
            #expect(board.turn == puzzle.userColor)
            #expect(!board.isInCheck(board.turn.opposite))
            #expect(puzzle.solutionUcis.count == puzzle.solutionSans.count)
            #expect(!puzzle.solutionUcis.isEmpty)

            for (idx, uci) in puzzle.solutionUcis.enumerated() {
                let applied = try board.apply(uci: uci)
                #expect(applied.san == puzzle.solutionSans[idx], "SAN mismatch in \(puzzle.id) step \(idx)")

                // After user's first move (idx == 0), verify EVERY legal opponent reply is strictly forced!
                if idx == 0 {
                    let oppReplies = board.legalMoves()
                    #expect(!oppReplies.isEmpty, "Expected opponent replies in \(puzzle.id)")
                    switch puzzle.theme {
                    case .stalemateSac, .desperadoRook:
                        for reply in oppReplies {
                            var testBoard = board
                            _ = try testBoard.apply(reply)
                            #expect(
                                testBoard.outcome == .stalemate,
                                "Opponent reply \(reply.uci) escapes stalemate in \(puzzle.id)!"
                            )
                        }
                    case .perpetualSave:
                        #expect(oppReplies.count == 1, "Expected 100% forced reply to check 1 in \(puzzle.id)")
                    }
                }
            }

            switch puzzle.theme {
            case .stalemateSac, .desperadoRook:
                #expect(board.legalMoves().isEmpty, "Expected zero legal moves (stalemate) in \(puzzle.id)")
                #expect(!board.isInCheck(board.turn), "Expected NOT in check (stalemate, not mate) in \(puzzle.id)")
                #expect(board.outcome == .stalemate, "Expected .stalemate outcome in \(puzzle.id)")
            case .perpetualSave:
                #expect(board.isInCheck(board.turn), "Expected final perpetual move to deliver check in \(puzzle.id)")
                let replies2 = board.legalMoves()
                #expect(replies2.count == 1, "Expected 100% forced reply to check 2 in \(puzzle.id)")
                // Verify the perpetual shuttle repeats cleanly
                if let forcedReply = replies2.first {
                    var repeatBoard = board
                    _ = try repeatBoard.apply(forcedReply)
                    let repeatFrom = String(puzzle.solutionUcis[2].suffix(2))
                    let repeatTo = String(puzzle.solutionUcis[0].suffix(2))
                    _ = try repeatBoard.apply(uci: repeatFrom + repeatTo)
                    #expect(repeatBoard.isInCheck(repeatBoard.turn), "Expected perpetual check to repeat in \(puzzle.id)")
                }
            }
        }
    }
}
