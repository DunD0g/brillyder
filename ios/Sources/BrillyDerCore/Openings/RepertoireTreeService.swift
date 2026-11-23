import Foundation

public struct RepertoireTreeNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let ply: Int
    public let san: String
    public let fen: String
    public let recallPct: Int?
    public let isUserMove: Bool
    public let lineIds: [String]
    public var children: [RepertoireTreeNode]
}

public enum RepertoireTreeService {
    /// Builds a branching move tree across every line in a course with position-scoped FSRS recall dots (zero branch collision).
    public static func buildTree(
        for course: OpeningCourse,
        fsrsCards: [FsrsOpeningCard],
        now: Date = Date()
    ) -> [RepertoireTreeNode] {
        var recallByPosMove: [String: Int] = [:]
        for card in fsrsCards where card.courseId == course.id {
            let posKey = (try? ChessBoard(fen: card.fen).positionKey) ?? card.fen
            let key = "\(posKey)::\(card.expectedSan)"
            let r = FSRS6Scheduler.recallProbability(for: card, now: now)
            recallByPosMove[key] = max(recallByPosMove[key] ?? 0, r)
        }

        final class Builder {
            let id: String
            let ply: Int
            let san: String
            let beforePosKey: String
            let fen: String
            let isUserMove: Bool
            var lineIds: [String] = []
            var children: [Builder] = []

            init(id: String, ply: Int, san: String, beforePosKey: String, fen: String, isUserMove: Bool) {
                self.id = id
                self.ply = ply
                self.san = san
                self.beforePosKey = beforePosKey
                self.fen = fen
                self.isUserMove = isUserMove
            }

            func freeze(recallByPosMove: [String: Int]) -> RepertoireTreeNode {
                RepertoireTreeNode(
                    id: id,
                    ply: ply,
                    san: san,
                    fen: fen,
                    recallPct: isUserMove ? recallByPosMove["\(beforePosKey)::\(san)"] : nil,
                    isUserMove: isUserMove,
                    lineIds: lineIds,
                    children: children.map { $0.freeze(recallByPosMove: recallByPosMove) }
                )
            }
        }

        let root = Builder(id: "root", ply: -1, san: "", beforePosKey: "", fen: ChessBoard.initialFEN, isUserMove: false)

        for line in course.lines {
            var board = ChessBoard()
            var cursor = root
            for (plyIdx, rawSan) in line.moves.enumerated() {
                let beforeKey = board.positionKey
                guard let applied = try? board.apply(san: rawSan) else { break }
                if let existing = cursor.children.first(where: { $0.san == applied.san }) {
                    if !existing.lineIds.contains(line.id) { existing.lineIds.append(line.id) }
                    cursor = existing
                } else {
                    let isUser = applied.piece.color == course.side.pieceColor
                    let node = Builder(
                        id: "\(cursor.id)/\(plyIdx)_\(applied.san)",
                        ply: plyIdx,
                        san: applied.san,
                        beforePosKey: beforeKey,
                        fen: applied.afterFen,
                        isUserMove: isUser
                    )
                    node.lineIds.append(line.id)
                    cursor.children.append(node)
                    cursor = node
                }
            }
        }

        return root.children.map { $0.freeze(recallByPosMove: recallByPosMove) }
    }

    /// Exports a full course to canonical multi-chapter PGN (100% round-trip valid).
    public static func exportCourseToPGN(_ course: OpeningCourse) -> String {
        var chapters: [String] = []
        for line in course.lines {
            var board = ChessBoard()
            var moveTokens: [String] = []
            for (idx, san) in line.moves.enumerated() {
                guard let applied = try? board.apply(san: san) else { break }
                if idx % 2 == 0 {
                    moveTokens.append("\(idx / 2 + 1). \(applied.san)")
                } else {
                    moveTokens.append(applied.san)
                }
            }
            let safeEvent = "\(course.name): \(line.title)"
                .replacingOccurrences(of: "\"", with: "'")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            let safeEco = line.eco
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "\n", with: "")
            let header = """
            [Event "\(safeEvent)"]
            [Site "BrillyDer"]
            [ECO "\(safeEco)"]
            [White "\(course.side == .white ? "Repertoire" : "Opponent")"]
            [Black "\(course.side == .black ? "Repertoire" : "Opponent")"]
            [Result "*"]
            """
            chapters.append("\(header)\n\n\(moveTokens.joined(separator: " ")) *")
        }
        return chapters.joined(separator: "\n\n")
    }

    /// Imports a single or multi-chapter PGN string into a custom `OpeningCourse`.
    public static func importCourseFromPGN(
        name: String,
        side: RepertoireSide,
        pgn: String
    ) throws -> OpeningCourse {
        let trimmed = pgn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ChessError.invalidPGN("Paste one or more PGN lines to import.")
        }

        let lines = trimmed.components(separatedBy: .newlines)
        var blocks: [String] = []
        var current: [String] = []
        var seenMovetextInCurrent = false

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            let isTag = t.hasPrefix("[") && t.hasSuffix("]") && t.contains("\"")
            if isTag && seenMovetextInCurrent && !current.isEmpty {
                blocks.append(current.joined(separator: "\n"))
                current = [line]
                seenMovetextInCurrent = false
            } else {
                current.append(line)
                if !t.isEmpty && !isTag {
                    seenMovetextInCurrent = true
                }
            }
        }
        if !current.isEmpty { blocks.append(current.joined(separator: "\n")) }
        let rawBlocks = blocks.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        var openingLines: [OpeningLine] = []
        for (idx, block) in rawBlocks.enumerated() {
            let parsed = try PGNParser.parse(block)
            if parsed.startFen != ChessBoard.initialFEN {
                throw ChessError.invalidPGN("Opening courses must start from the standard initial chess position (custom [FEN] not supported in repertoire courses).")
            }
            guard parsed.moves.count >= 2 else { continue }
            let sanMoves = parsed.moves.map(\.applied.san)
            let lookup = MoveClassifier.lookupOpening(byMoves: sanMoves)
            let title = parsed.headers["Event"] ?? "Line \(idx + 1)"
            let eco = parsed.headers["ECO"] ?? lookup?.eco ?? "A00"
            openingLines.append(OpeningLine(
                id: "custom_line_\(idx + 1)_\(UUID().uuidString.prefix(6))",
                title: title,
                subtitle: "Imported custom repertoire line (\(sanMoves.count) plies)",
                eco: eco,
                frequencyNote: "Custom PGN",
                moves: sanMoves,
                annotations: []
            ))
        }

        guard let firstLine = openingLines.first else {
            throw ChessError.invalidPGN("Could not parse any valid opening lines from PGN.")
        }

        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Custom Repertoire" : name.trimmingCharacters(in: .whitespacesAndNewlines)
        return OpeningCourse(
            id: "custom_\(UUID().uuidString.prefix(8))",
            name: cleanName,
            codename: "Custom Deck",
            side: side,
            difficulty: "Club",
            tagline: "Imported \(openingLines.count) line\(openingLines.count == 1 ? "" : "s") from PGN.",
            source: "pgn",
            mothershipSetup: MothershipSetup(
                previewMoves: Array(firstLine.moves.prefix(12)),
                arrows: [],
                highlights: [],
                corePlans: ["Master your custom imported lines with FSRS active recall."],
                goldenRules: ["Drill due positions daily to lock in fast pattern recall."]
            ),
            lines: openingLines
        )
    }
}
