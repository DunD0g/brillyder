import Foundation

/// Playable & watchable bot tiers spanning beginner (~400 Elo) through Super-GM NNUE (~3300+)
/// and Hybrid Stockfish 16 Cloud + Ultra NNUE (~3500 Elo).
public enum BotProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case cadet400
    case novice700
    case club1000
    case tactician1350
    case challenger1700
    case master2100
    case fast
    case balanced
    case deep
    case ultra
    case hybrid

    public var id: String { rawValue }

    public enum TierGroup: String, CaseIterable, Sendable {
        case casual = "Casual & Club"
        case engine = "BrillyChess NNUE"
    }

    public var tierGroup: TierGroup {
        switch self {
        case .cadet400, .novice700, .club1000, .tactician1350, .challenger1700, .master2100:
            return .casual
        case .fast, .balanced, .deep, .ultra, .hybrid:
            return .engine
        }
    }

    public var displayName: String {
        switch self {
        case .cadet400:       return "Cadet"
        case .novice700:      return "Novice"
        case .club1000:       return "Club"
        case .tactician1350:  return "Tactician"
        case .challenger1700: return "Challenger"
        case .master2100:     return "Master"
        case .fast:           return "Fast NNUE"
        case .balanced:       return "Balanced NNUE"
        case .deep:           return "Deep NNUE"
        case .ultra:          return "Ultra NNUE"
        case .hybrid:         return "Hybrid Cloud SF"
        }
    }

    public var shortName: String {
        switch self {
        case .cadet400:       return "Cadet"
        case .novice700:      return "Novice"
        case .club1000:       return "Club"
        case .tactician1350:  return "Tactician"
        case .challenger1700: return "Challenger"
        case .master2100:     return "Master"
        case .fast:           return "Fast"
        case .balanced:       return "Balanced"
        case .deep:           return "Deep"
        case .ultra:          return "Ultra"
        case .hybrid:         return "Hybrid"
        }
    }

    public var elo: Int {
        switch self {
        case .cadet400:       return 400
        case .novice700:      return 700
        case .club1000:       return 1000
        case .tactician1350:  return 1350
        case .challenger1700: return 1700
        case .master2100:     return 2100
        case .fast:           return 2650
        case .balanced:       return 2900
        case .deep:           return 3100
        case .ultra:          return 3300
        case .hybrid:         return 3500
        }
    }

    public var eloLabel: String {
        switch self {
        case .ultra:  return "~3300+"
        case .hybrid: return "~3500"
        default:      return "~\(elo)"
        }
    }

    public var tagline: String {
        switch self {
        case .cadet400:       return "Beginner sparring partner · frequently misses tactics"
        case .novice700:      return "Spots simple captures · drops 2-move combinations"
        case .club1000:       return "Solid opening basics · occasional tactical slips"
        case .tactician1350:  return "Sharp 2–3 ply tactics · human-like inaccuracies"
        case .challenger1700: return "Strong club pressure & clean tactical eye"
        case .master2100:     return "Candidate Master calculation & endgames"
        case .fast:           return "On-device NNUE · Depth 12 rapid engine"
        case .balanced:       return "GM-strength on-device NNUE · Depth 15"
        case .deep:           return "Super-GM on-device NNUE · Depth 18"
        case .ultra:          return "Max offline NNUE strength · Depth 22"
        case .hybrid:         return "Stockfish 16 Cloud + Ultra NNUE offline fallback"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .cadet400:       return "leaf.fill"
        case .novice700:      return "tortoise.fill"
        case .club1000:       return "figure.walk"
        case .tactician1350:  return "bolt.fill"
        case .challenger1700: return "flame.fill"
        case .master2100:     return "crown.fill"
        case .fast:           return "hare.fill"
        case .balanced:       return "cpu"
        case .deep:           return "cpu.fill"
        case .ultra:          return "sparkles"
        case .hybrid:         return "cloud.bolt.fill"
        }
    }

    /// Ultra (~3300+) and Hybrid Cloud SF (~3500) require Pro (automatically unlocked on Founder Admin).
    public var requiresPro: Bool {
        self == .ultra || self == .hybrid
    }

    public func isUnlocked(hasProAccess: Bool) -> Bool {
        hasProAccess || !requiresPro
    }
}

/// Opening book selection for an individual bot (White or Black) in Bot Arena.
public enum BotOpeningSelection: Hashable, Codable, Sendable {
    case freePlay
    case course(courseId: String, lineId: String?)

    public var courseId: String? {
        if case .course(let cid, _) = self { return cid }
        return nil
    }

    public var lineId: String? {
        if case .course(_, let lid) = self { return lid }
        return nil
    }
}

public enum BotMoveSource: Hashable, Sendable {
    case openingBook(courseName: String, lineTitle: String?)
    case cloudStockfish16
    case nnue(BotProfile)
    case swiftEngine(BotProfile)

    public var badgeLabel: String {
        switch self {
        case .openingBook(let course, let line):
            if let line, !line.isEmpty {
                return "Book · \(course) (\(line))"
            }
            return "Book · \(course)"
        case .cloudStockfish16:
            return "Hybrid SF16 Cloud"
        case .nnue(let profile):
            return profile.displayName
        case .swiftEngine(let profile):
            return "\(profile.displayName) (\(profile.eloLabel))"
        }
    }
}

public struct BotMoveDecision: Sendable {
    public let move: ChessMove
    public let san: String
    public let source: BotMoveSource
    public let evalScore: EngineScore?
    public let depth: Int

    public init(
        move: ChessMove,
        san: String,
        source: BotMoveSource,
        evalScore: EngineScore?,
        depth: Int
    ) {
        self.move = move
        self.san = san
        self.source = source
        self.evalScore = evalScore
        self.depth = depth
    }
}

/// Resolves per-bot opening book moves from BrillyDer's starter & custom `OpeningCourse` library.
public enum BotOpeningBookResolver {
    private static func normalizeSan(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
    }

    public static func nextBookMove(
        board: ChessBoard,
        sanHistory: [String],
        selection: BotOpeningSelection,
        courses: [OpeningCourse],
        opponentSelection: BotOpeningSelection = .freePlay,
        guideOpponentOpening: Bool = true
    ) -> (move: ChessMove, san: String, courseName: String, lineTitle: String?)? {
        // 1. Primary: consult the active side's own chosen opening book
        if case .course(let courseId, let lineId) = selection,
           let course = courses.first(where: { $0.id == courseId }) {
            if let match = matchMove(in: course, preferredLineId: lineId, board: board, sanHistory: sanHistory) {
                return match
            }
        }

        // 2. Smart Setup Guide: if the active side is Free Play and the opponent chose a specific opening,
        //    follow the opponent's course setup moves for the opening phase so the chosen opening actually occurs!
        if selection == .freePlay,
           guideOpponentOpening,
           sanHistory.count < 8,
           case .course(let oppCourseId, let oppLineId) = opponentSelection,
           let oppCourse = courses.first(where: { $0.id == oppCourseId }) {
            if let match = matchMove(in: oppCourse, preferredLineId: oppLineId, board: board, sanHistory: sanHistory) {
                return match
            }
        }

        return nil
    }

    private static func matchMove(
        in course: OpeningCourse,
        preferredLineId: String?,
        board: ChessBoard,
        sanHistory: [String]
    ) -> (move: ChessMove, san: String, courseName: String, lineTitle: String?)? {
        let ply = sanHistory.count
        let normalizedHistory = sanHistory.map(normalizeSan)

        let candidateLines: [OpeningLine]
        if let preferredLineId,
           let exactLine = course.lines.first(where: { $0.id == preferredLineId }) {
            candidateLines = [exactLine]
        } else {
            candidateLines = course.lines
        }

        var matchingMoves: [(move: ChessMove, san: String, lineTitle: String)] = []
        for line in candidateLines {
            guard line.moves.count > ply else { continue }
            var prefixMatches = true
            for i in 0..<ply {
                if normalizeSan(line.moves[i]) != normalizedHistory[i] {
                    prefixMatches = false
                    break
                }
            }
            guard prefixMatches else { continue }
            let nextSan = line.moves[ply]
            if let legalMove = try? board.parseSAN(nextSan) {
                var probe = board
                if let applied = try? probe.apply(legalMove) {
                    matchingMoves.append((legalMove, applied.san, line.title))
                }
            }
        }

        guard !matchingMoves.isEmpty else { return nil }
        // Deduplicate by UCI while keeping variety across distinct continuations
        var uniqueByUci: [String: (move: ChessMove, san: String, lineTitle: String)] = [:]
        for item in matchingMoves where uniqueByUci[item.move.uci] == nil {
            uniqueByUci[item.move.uci] = item
        }
        let chosen = Array(uniqueByUci.values).randomElement() ?? matchingMoves[0]
        return (chosen.move, chosen.san, course.name, preferredLineId != nil ? chosen.lineTitle : nil)
    }

    /// Returns a concise human label for an opening selection.
    public static func label(for selection: BotOpeningSelection, courses: [OpeningCourse]) -> String {
        switch selection {
        case .freePlay:
            return "Free Play"
        case .course(let cid, let lid):
            guard let course = courses.first(where: { $0.id == cid }) else { return "Free Play" }
            if let lid, let line = course.lines.first(where: { $0.id == lid }) {
                return "\(course.name) · \(line.title)"
            }
            return course.name
        }
    }
}

/// Unified move generator for Play-vs-Bot and Bot-vs-Bot modes across all 11 bot profiles.
public enum BotArenaEngine {
    /// Computes the next move for `profile` on `board`, consulting its opening book first,
    /// then Hybrid SF16 Cloud (when `.hybrid`), Renegade NNUE, or calibrated BrillyNativeEngine.
    public static func chooseMove(
        board: ChessBoard,
        sanHistory: [String],
        profile: BotProfile,
        openingSelection: BotOpeningSelection = .freePlay,
        opponentOpeningSelection: BotOpeningSelection = .freePlay,
        guideOpponentOpening: Bool = true,
        courses: [OpeningCourse] = [],
        seenPositionCounts: [String: Int] = [:],
        nnueEngine: RenegadeEngine,
        swiftEngine: BrillyNativeEngine
    ) async -> BotMoveDecision? {
        let legalMoves = board.legalMoves()
        guard !legalMoves.isEmpty else { return nil }

        // 1. Opening book lookup
        if let book = BotOpeningBookResolver.nextBookMove(
            board: board,
            sanHistory: sanHistory,
            selection: openingSelection,
            courses: courses,
            opponentSelection: opponentOpeningSelection,
            guideOpponentOpening: guideOpponentOpening
        ) {
            return BotMoveDecision(
                move: book.move,
                san: book.san,
                source: .openingBook(courseName: book.courseName, lineTitle: book.lineTitle),
                evalScore: nil,
                depth: 0
            )
        }

        try? Task.checkCancellation()
        if Task.isCancelled { return nil }

        // 2. Hybrid Cloud Stockfish 16 + Ultra NNUE fallback
        if profile == .hybrid {
            if case .hit(let cloudEval) = await LichessCloudEvalClient.probe(fen: board.fen, multiPV: 1),
               !Task.isCancelled,
               let cloudMove = ChessMove(uci: cloudEval.bestMoveUci),
               legalMoves.contains(cloudMove) {
                var probe = board
                if let applied = try? probe.apply(cloudMove) {
                    return BotMoveDecision(
                        move: cloudMove,
                        san: applied.san,
                        source: .cloudStockfish16,
                        evalScore: cloudEval.score,
                        depth: cloudEval.depth
                    )
                }
            }
            if Task.isCancelled { return nil }
            return await runNNUEBot(
                board: board,
                legalMoves: legalMoves,
                profile: .hybrid,
                depth: 22,
                maxTimeMs: 850,
                multiPV: 2,
                pv2Chance: 0.0,
                pv2MaxGapCp: 0,
                seenPositionCounts: seenPositionCounts,
                nnueEngine: nnueEngine
            )
        }

        // 3. Engine-tier NNUE profiles (Master 2100 -> Ultra 3300+)
        switch profile {
        case .ultra:
            return await runNNUEBot(
                board: board, legalMoves: legalMoves, profile: profile,
                depth: 22, maxTimeMs: 850, multiPV: 2, pv2Chance: 0.0, pv2MaxGapCp: 0,
                seenPositionCounts: seenPositionCounts, nnueEngine: nnueEngine
            )
        case .deep:
            return await runNNUEBot(
                board: board, legalMoves: legalMoves, profile: profile,
                depth: 18, maxTimeMs: 380, multiPV: 2, pv2Chance: 0.0, pv2MaxGapCp: 0,
                seenPositionCounts: seenPositionCounts, nnueEngine: nnueEngine
            )
        case .balanced:
            return await runNNUEBot(
                board: board, legalMoves: legalMoves, profile: profile,
                depth: 15, maxTimeMs: 180, multiPV: 2, pv2Chance: 0.0, pv2MaxGapCp: 0,
                seenPositionCounts: seenPositionCounts, nnueEngine: nnueEngine
            )
        case .fast:
            return await runNNUEBot(
                board: board, legalMoves: legalMoves, profile: profile,
                depth: 12, maxTimeMs: 80, multiPV: 2, pv2Chance: 0.0, pv2MaxGapCp: 0,
                seenPositionCounts: seenPositionCounts, nnueEngine: nnueEngine
            )
        case .master2100:
            return await runNNUEBot(
                board: board, legalMoves: legalMoves, profile: profile,
                depth: 7, maxTimeMs: 50, multiPV: 2, pv2Chance: 0.14, pv2MaxGapCp: 35,
                seenPositionCounts: seenPositionCounts, nnueEngine: nnueEngine
            )

        // 4. Calibrated weaker & club-strength human-like bots (400 -> 1700 Elo)
        case .challenger1700:
            return await runSwiftHumanizedBot(
                board: board, legalMoves: legalMoves, profile: profile,
                depth: 4, maxTimeMs: 240, multiPV: 2,
                pv2Chance: 0.18, pv2MaxGapCp: 55,
                pv3Chance: 0.0, pv3MaxGapCp: 0,
                randomMoveChance: 0.0,
                swiftEngine: swiftEngine
            )
        case .tactician1350:
            return await runSwiftHumanizedBot(
                board: board, legalMoves: legalMoves, profile: profile,
                depth: 3, maxTimeMs: 140, multiPV: 3,
                pv2Chance: 0.24, pv2MaxGapCp: 120,
                pv3Chance: 0.09, pv3MaxGapCp: 170,
                randomMoveChance: 0.03,
                swiftEngine: swiftEngine
            )
        case .club1000:
            return await runSwiftHumanizedBot(
                board: board, legalMoves: legalMoves, profile: profile,
                depth: 2, maxTimeMs: 85, multiPV: 3,
                pv2Chance: 0.30, pv2MaxGapCp: 200,
                pv3Chance: 0.16, pv3MaxGapCp: 280,
                randomMoveChance: 0.12,
                swiftEngine: swiftEngine
            )
        case .novice700:
            return await runSwiftHumanizedBot(
                board: board, legalMoves: legalMoves, profile: profile,
                depth: 1, maxTimeMs: 45, multiPV: 3,
                pv2Chance: 0.34, pv2MaxGapCp: 420,
                pv3Chance: 0.24, pv3MaxGapCp: 560,
                randomMoveChance: 0.38,
                swiftEngine: swiftEngine
            )
        case .cadet400:
            return await runSwiftHumanizedBot(
                board: board, legalMoves: legalMoves, profile: profile,
                depth: 1, maxTimeMs: 30, multiPV: 3,
                pv2Chance: 0.36, pv2MaxGapCp: 800,
                pv3Chance: 0.30, pv3MaxGapCp: 1000,
                randomMoveChance: 0.62,
                swiftEngine: swiftEngine
            )
        case .hybrid:
            return nil
        }
    }

    private static func runNNUEBot(
        board: ChessBoard,
        legalMoves: [ChessMove],
        profile: BotProfile,
        depth: Int,
        maxTimeMs: Int,
        multiPV: Int,
        pv2Chance: Double,
        pv2MaxGapCp: Int,
        seenPositionCounts: [String: Int],
        nnueEngine: RenegadeEngine
    ) async -> BotMoveDecision? {
        guard let ev = try? await nnueEngine.analyze(
            fen: board.fen,
            depth: depth,
            multiPV: multiPV,
            maxTimeMs: maxTimeMs
        ), !Task.isCancelled else { return nil }

        let chosenMove = pickBestOrSafeAlternative(
            board: board,
            eval: ev,
            legalMoves: legalMoves,
            pv2Chance: pv2Chance,
            pv2MaxGapCp: pv2MaxGapCp,
            seenPositionCounts: seenPositionCounts
        )
        var probe = board
        guard let applied = try? probe.apply(chosenMove) else { return nil }
        return BotMoveDecision(
            move: chosenMove,
            san: applied.san,
            source: .nnue(profile),
            evalScore: ev.score,
            depth: ev.depth
        )
    }

    private static func runSwiftHumanizedBot(
        board: ChessBoard,
        legalMoves: [ChessMove],
        profile: BotProfile,
        depth: Int,
        maxTimeMs: Int,
        multiPV: Int,
        pv2Chance: Double,
        pv2MaxGapCp: Int,
        pv3Chance: Double,
        pv3MaxGapCp: Int,
        randomMoveChance: Double,
        swiftEngine: BrillyNativeEngine
    ) async -> BotMoveDecision? {
        let ev = try? await swiftEngine.analyze(
            fen: board.fen,
            depth: depth,
            multiPV: multiPV,
            maxTimeMs: maxTimeMs
        )
        if Task.isCancelled { return nil }

        let moverIsWhite = board.turn == .white
        let sign = moverIsWhite ? 1 : -1

        func sideCp(_ score: EngineScore) -> Int {
            if let m = score.mateWhite {
                let moverMates = moverIsWhite ? m > 0 : m < 0
                return moverMates ? 9000 : -9000
            }
            return score.cpWhite * sign
        }

        var chosen: ChessMove? = nil
        if let ev, !ev.lines.isEmpty {
            let line1 = ev.lines[0]
            let s1 = sideCp(line1.score)

            // Even Cadet/Novice spots immediate checkmate-in-1 most of the time
            let isMateIn1 = (ev.score.mateWhite != nil && abs(ev.score.mateWhite!) == 1 && s1 > 0)
            if isMateIn1 && Double.random(in: 0..<1) < (profile == .cadet400 ? 0.65 : 0.90),
               let m1 = ChessMove(uci: line1.bestMoveUci), legalMoves.contains(m1) {
                chosen = m1
            } else if randomMoveChance > 0 && Double.random(in: 0..<1) < randomMoveChance {
                chosen = pickHumanizedRandomMove(board: board, legalMoves: legalMoves, profile: profile)
            } else {
                let roll = Double.random(in: 0..<1)
                if ev.lines.count >= 3,
                   pv3Chance > 0,
                   roll < pv3Chance,
                   s1 - sideCp(ev.lines[2].score) <= pv3MaxGapCp,
                   let m3 = ChessMove(uci: ev.lines[2].bestMoveUci),
                   legalMoves.contains(m3) {
                    chosen = m3
                } else if ev.lines.count >= 2,
                          pv2Chance > 0,
                          roll < pv3Chance + pv2Chance,
                          s1 - sideCp(ev.lines[1].score) <= pv2MaxGapCp,
                          let m2 = ChessMove(uci: ev.lines[1].bestMoveUci),
                          legalMoves.contains(m2) {
                    chosen = m2
                } else if let m1 = ChessMove(uci: line1.bestMoveUci), legalMoves.contains(m1) {
                    chosen = m1
                }
            }
        }

        let finalMove = chosen ?? legalMoves.randomElement() ?? legalMoves[0]
        var probe = board
        guard let applied = try? probe.apply(finalMove) else { return nil }
        return BotMoveDecision(
            move: finalMove,
            san: applied.san,
            source: .swiftEngine(profile),
            evalScore: ev?.score,
            depth: ev?.depth ?? depth
        )
    }

    private static func pickHumanizedRandomMove(
        board: ChessBoard,
        legalMoves: [ChessMove],
        profile: BotProfile
    ) -> ChessMove {
        // Beginners gravitate slightly toward captures, checks, and pawn/minor moves rather than pure uniform chaos
        var weighted: [ChessMove] = []
        weighted.reserveCapacity(legalMoves.count * 2)
        for m in legalMoves {
            weighted.append(m)
            let isCapture = board[m.to] != nil
            if isCapture && profile != .cadet400 {
                weighted.append(m)
            } else if isCapture && Double.random(in: 0..<1) < 0.45 {
                weighted.append(m)
            }
        }
        return weighted.randomElement() ?? legalMoves[0]
    }

    private static func pickBestOrSafeAlternative(
        board: ChessBoard,
        eval: EngineEval,
        legalMoves: [ChessMove],
        pv2Chance: Double,
        pv2MaxGapCp: Int,
        seenPositionCounts: [String: Int]
    ) -> ChessMove {
        let sign = board.turn == .white ? 1 : -1
        let m1 = ChessMove(uci: eval.bestMoveUci).flatMap { legalMoves.contains($0) ? $0 : nil } ?? legalMoves[0]

        guard eval.lines.count >= 2,
              let m2 = ChessMove(uci: eval.lines[1].bestMoveUci),
              legalMoves.contains(m2) else {
            return m1
        }

        let cp1 = eval.lines[0].score.cpWhite * sign
        let cp2 = eval.lines[1].score.cpWhite * sign

        // Avoid accidental 3-fold repetition when clearly winning (+1.5 or better) if PV2 keeps a winning edge
        if cp1 >= 150 && cp2 >= 90 {
            var after1 = board
            if (try? after1.apply(m1)) != nil, (seenPositionCounts[after1.positionKey] ?? 0) >= 2 {
                return m2
            }
        }

        if pv2Chance > 0 && (cp1 - cp2) <= pv2MaxGapCp && Double.random(in: 0..<1) < pv2Chance {
            return m2
        }
        return m1
    }

    /// Builds a valid PGN + `GameRecord` from an Arena game so the user can launch full Game Review
    /// (with Brilliant `!!` detection, eval graph & coaching) in 1 tap.
    public static func buildGameRecord(
        sanMoves: [String],
        whiteName: String,
        whiteElo: Int?,
        blackName: String,
        blackElo: Int?,
        resultString: String,
        userColor: PieceColor?,
        openingHintName: String? = nil
    ) -> GameRecord {
        var movetextParts: [String] = []
        for (idx, san) in sanMoves.enumerated() {
            if idx % 2 == 0 {
                movetextParts.append("\((idx / 2) + 1). \(san)")
            } else {
                movetextParts.append(san)
            }
        }
        movetextParts.append(resultString)

        let detectedOpening = MoveClassifier.lookupOpening(byMoves: sanMoves)
        let openingName = openingHintName ?? detectedOpening?.name ?? "Bot Arena Match"
        let openingEco = detectedOpening?.eco ?? ""
        let openingPly = detectedOpening?.matchedPlies

        let cleanWhite = whiteName.replacingOccurrences(of: "\"", with: "")
        let cleanBlack = blackName.replacingOccurrences(of: "\"", with: "")
        let cleanOpening = openingName.replacingOccurrences(of: "\"", with: "")

        let headers = [
            "[Event \"BrillyDer Bot Arena\"]",
            "[Site \"On-Device\"]",
            "[White \"\(cleanWhite)\"]",
            "[Black \"\(cleanBlack)\"]",
            whiteElo.map { "[WhiteElo \"\($0)\"]" },
            blackElo.map { "[BlackElo \"\($0)\"]" },
            "[Result \"\(resultString)\"]",
            openingEco.isEmpty ? nil : "[ECO \"\(openingEco)\"]",
            "[Opening \"\(cleanOpening)\"]",
        ].compactMap { $0 }

        let pgn = headers.joined(separator: "\n") + "\n\n" + movetextParts.joined(separator: " ")
        let winner: String? = resultString == "1-0" ? "white" : (resultString == "0-1" ? "black" : nil)

        return GameRecord(
            id: "arena-\(UUID().uuidString.prefix(10).lowercased())",
            source: .pgn,
            rated: false,
            variant: "standard",
            speed: "rapid",
            perf: "rapid",
            createdAt: Int64(Date().timeIntervalSince1970 * 1000.0),
            status: resultString == "*" ? "started" : "normal",
            winner: winner,
            resultString: resultString,
            timeControlLabel: "Bot Arena",
            pgn: pgn,
            openingName: openingName,
            openingEco: openingEco,
            openingPly: openingPly,
            white: PlayerInfo(name: whiteName, rating: whiteElo),
            black: PlayerInfo(name: blackName, rating: blackElo),
            userColor: userColor,
            url: nil
        )
    }
}
