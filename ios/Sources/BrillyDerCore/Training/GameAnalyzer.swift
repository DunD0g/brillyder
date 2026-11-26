import Foundation

public struct InsightsSnapshot: Sendable {
    public let analyzedCount: Int
    public let avgAccuracy: Double
    public let wins: Int
    public let draws: Int
    public let losses: Int
    public let openingAccuracy: Double
    public let middlegameAccuracy: Double
    public let endgameAccuracy: Double
    public let totalBrilliants: Int
    public let totalBlunders: Int
    public let topOpenings: [(name: String, games: Int, winRate: Double, avgAccuracy: Double)]
    public let currentRatings: [(speed: String, rating: Int)]
    public let avgPerformanceElo: Int?

    public init(
        analyzedCount: Int,
        avgAccuracy: Double,
        wins: Int,
        draws: Int,
        losses: Int,
        openingAccuracy: Double,
        middlegameAccuracy: Double,
        endgameAccuracy: Double,
        totalBrilliants: Int,
        totalBlunders: Int,
        topOpenings: [(name: String, games: Int, winRate: Double, avgAccuracy: Double)],
        currentRatings: [(speed: String, rating: Int)] = [],
        avgPerformanceElo: Int? = nil
    ) {
        self.analyzedCount = analyzedCount
        self.avgAccuracy = avgAccuracy
        self.wins = wins
        self.draws = draws
        self.losses = losses
        self.openingAccuracy = openingAccuracy
        self.middlegameAccuracy = middlegameAccuracy
        self.endgameAccuracy = endgameAccuracy
        self.totalBrilliants = totalBrilliants
        self.totalBlunders = totalBlunders
        self.topOpenings = topOpenings
        self.currentRatings = currentRatings
        self.avgPerformanceElo = avgPerformanceElo
    }
}

public enum GameAnalyzer {
    public static func analyze(
        game: GameRecord,
        engine: any ChessEngine,
        preset: AnalysisDepthPreset = .balanced,
        isBatch: Bool = false,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> AnalyzedGame {
        let parsed = try PGNParser.parse(game.pgn)
        let totalPlies = parsed.moves.count
        let isStandardStart = (parsed.startFen == ChessBoard.initialFEN)
        let parsedTC = PGNParser.parseTimeControl(parsed.headers["TimeControl"])
        let tcInc = parsedTC?.incrementSeconds ?? 0.0
        let lowClockLimit: Double = {
            if let initSec = parsedTC?.initialSeconds, initSec > 0 {
                return min(60.0, max(10.0, initSec * 0.25))
            }
            return game.speed == "bullet" ? 15.0 : 60.0
        }()
        onProgress?(0, max(1, totalPlies))
        await engine.clearHash()

        var cloudEnabled = preset.usesCloudEval
        var consecutiveCloudMisses = 0

        let baseTimeMs: Int = {
            guard isBatch else { return preset.maxTimeMs }
            switch preset {
            case .fast:     return 40
            case .balanced: return 110
            case .deep:     return 260
            default:        return preset.maxTimeMs
            }
        }()

        func evaluatePosition(_ fen: String, plyIndex: Int) async throws -> (eval: EngineEval, fromCloud: Bool) {
            // Early standard opening moves (plies 0..3, moves 1-2) don't need MultiPV=2 or deep time budgets
            let isEarlyOpeningBook = isStandardStart && plyIndex < 4
            let pvCount = isEarlyOpeningBook ? 1 : 2
            let timeBudget = isEarlyOpeningBook ? min(baseTimeMs, 30) : baseTimeMs

            if cloudEnabled {
                switch await LichessCloudEvalClient.probe(fen: fen, multiPV: pvCount) {
                case .hit(let cloudEval):
                    consecutiveCloudMisses = 0
                    if pvCount >= 2 && cloudEval.lines.count < 2 {
                        let legalCount = (try? ChessBoard(fen: fen))?.legalMoves().count ?? 0
                        if legalCount >= 2 {
                            // Fall through to local Renegade so MultiPV=2 gap is available for Brilliant/Great detection
                            break
                        }
                    }
                    return (cloudEval, true)
                case .rateLimited:
                    cloudEnabled = false
                case .miss:
                    consecutiveCloudMisses += 1
                    if consecutiveCloudMisses >= 4 {
                        cloudEnabled = false
                    }
                }
            }
            try Task.checkCancellation()
            let localEval = try await engine.analyze(
                fen: fen,
                depth: preset.searchDepth,
                multiPV: pvCount,
                maxTimeMs: timeBudget
            )
            return (localEval, false)
        }

        let initialEvalTuple = try await evaluatePosition(parsed.startFen, plyIndex: 0)
        let initialEvalResult = initialEvalTuple.eval

        var evalByPlyIndex: [EngineEval] = [initialEvalResult]
        var evalWasCloud: [Bool] = [initialEvalTuple.fromCloud]
        evalByPlyIndex.reserveCapacity(totalPlies + 1)
        evalWasCloud.reserveCapacity(totalPlies + 1)

        for (idx, pgnMove) in parsed.moves.enumerated() {
            try Task.checkCancellation()
            let (eval, fromCloud) = try await evaluatePosition(pgnMove.applied.afterFen, plyIndex: idx + 1)
            evalByPlyIndex.append(eval)
            evalWasCloud.append(fromCloud)
            onProgress?(idx + 1, max(1, totalPlies))
        }
        if totalPlies == 0 {
            onProgress?(1, 1)
        }

        var plies: [AnalyzedPly] = []
        plies.reserveCapacity(totalPlies)

        var seenKeys: [String: Int] = [:]
        if let startBoard = try? ChessBoard(fen: parsed.startFen) {
            seenKeys[startBoard.positionKey] = 1
        }
        var sanPrefix: [String] = []
        var prevClockByColor: [PieceColor: Double] = [:]
        var deepenedSacrificeCount = 0

        for (idx, pgnMove) in parsed.moves.enumerated() {
            try Task.checkCancellation()
            let applied = pgnMove.applied
            var evalBefore = evalByPlyIndex[idx]
            var evalAfter = evalByPlyIndex[idx + 1]
            var beforeIsCloud = evalWasCloud[idx]
            var afterIsCloud = evalWasCloud[idx + 1]
            // Eliminate cross-engine eval cliffs on BOTH cloud→local and local→cloud transition plies
            if beforeIsCloud && !afterIsCloud {
                evalBefore = try await engine.analyze(
                    fen: applied.beforeFen,
                    depth: preset.searchDepth,
                    multiPV: 2,
                    maxTimeMs: preset.maxTimeMs
                )
                beforeIsCloud = false
            } else if !beforeIsCloud && afterIsCloud {
                evalAfter = try await engine.analyze(
                    fen: applied.afterFen,
                    depth: preset.searchDepth,
                    multiPV: 2,
                    maxTimeMs: preset.maxTimeMs
                )
                afterIsCloud = false
            }
            let beforeBoard = (try? ChessBoard(fen: applied.beforeFen)) ?? ChessBoard()
            let afterBoard = (try? ChessBoard(fen: applied.afterFen)) ?? ChessBoard()

            let posKey = afterBoard.positionKey
            let repeatCount = (seenKeys[posKey] ?? 0) + 1
            seenKeys[posKey] = repeatCount
            sanPrefix.append(applied.san)

            // Score terminal 3-fold repetition draws at 0.0 so throwing a winning game into a draw is flagged as a blunder
            let isTerminalRepetitionDraw = repeatCount >= 3 && idx == totalPlies - 1 && game.resultString == "1/2-1/2"
            if isTerminalRepetitionDraw {
                let drawScore = ChessMath.buildEngineScore(cpWhite: 0)
                evalAfter = EngineEval(
                    fen: evalAfter.fen,
                    depth: evalAfter.depth,
                    bestMoveUci: evalAfter.bestMoveUci,
                    pv: evalAfter.pv,
                    score: drawScore,
                    lines: evalAfter.lines
                )
            }

            let mover = applied.piece.color
            var wasDeepened = false
            // Tactical Sacrifice Deepening Pass (both single-game & lightweight batch):
            // Give candidate piece sacrifices extra depth/time so deep refutations (e.g. pins/skewers 6-10 plies out)
            // evaluate accurately instead of falling victim to shallow horizon cutoffs.
            let maxDeepenedSacs = isBatch ? 2 : 8
            if !isTerminalRepetitionDraw && deepenedSacrificeCount < maxDeepenedSacs && !beforeIsCloud && !afterIsCloud {
                let prelimWinBefore = ChessMath.moverWinPercent(evalBefore.score, mover: mover)
                let prelimWinAfter = ChessMath.moverWinPercent(evalAfter.score, mover: mover)
                let prelimIsTop = applied.move.uci == evalBefore.bestMoveUci
                let prelimLoss = prelimIsTop ? 0.0 : max(0.0, prelimWinBefore - prelimWinAfter)
                if prelimWinBefore < 94.0 && prelimLoss <= 16.0 && MoveClassifier.isSacrificeMove(
                    beforeBoard: beforeBoard,
                    afterBoard: afterBoard,
                    mover: mover,
                    fromSquare: applied.move.from,
                    toSquare: applied.move.to,
                    movedPiece: applied.piece.type,
                    capturedPiece: applied.captured?.type,
                    promotionPiece: applied.move.promotion
                ) {
                    let deepDepth = isBatch ? max(preset.searchDepth, 16) : max(preset.searchDepth, 20)
                    let deepMs = isBatch ? max(baseTimeMs * 2, 260) : max(baseTimeMs * 2, 550)
                    try Task.checkCancellation()
                    evalBefore = try await engine.analyze(
                        fen: applied.beforeFen,
                        depth: deepDepth,
                        multiPV: 2,
                        maxTimeMs: deepMs
                    )
                    try Task.checkCancellation()
                    evalAfter = try await engine.analyze(
                        fen: applied.afterFen,
                        depth: deepDepth,
                        multiPV: 2,
                        maxTimeMs: deepMs
                    )
                    evalByPlyIndex[idx] = evalBefore
                    evalByPlyIndex[idx + 1] = evalAfter
                    wasDeepened = true
                    deepenedSacrificeCount += 1
                }
            }

            let winBefore = ChessMath.moverWinPercent(evalBefore.score, mover: mover)
            let winAfter = ChessMath.moverWinPercent(evalAfter.score, mover: mover)
            let isTopMove = applied.move.uci == evalBefore.bestMoveUci && !isTerminalRepetitionDraw
            let winLoss = isTopMove ? 0.0 : max(0.0, winBefore - winAfter)

            let hasSecond = evalBefore.lines.count >= 2
            let secondBestGap: Double
            if hasSecond {
                let firstWin = ChessMath.moverWinPercent(evalBefore.lines[0].score, mover: mover)
                let secondWin = ChessMath.moverWinPercent(evalBefore.lines[1].score, mover: mover)
                secondBestGap = max(0.0, firstWin - secondWin)
            } else {
                secondBestGap = 0.0
            }

            let hadMateForMover: Bool = {
                guard let m = evalBefore.score.mateWhite else { return false }
                return mover == .white ? m > 0 : m < 0
            }()
            let stillHasMate: Bool = {
                if evalAfter.score.isCheckmate == true { return true }
                guard let m = evalAfter.score.mateWhite else { return false }
                return mover == .white ? m > 0 : m < 0
            }()
            let walkedIntoMate: Bool = {
                guard let m = evalAfter.score.mateWhite, winBefore > 15.0 else { return false }
                let oppMate = mover == .white ? m < 0 : m > 0
                let alreadyMated = evalBefore.score.mateWhite.map { mover == .white ? $0 < 0 : $0 > 0 } ?? false
                return oppMate && !alreadyMated
            }()
            let missedMate = hadMateForMover && !stillHasMate
            let missedShortMate = missedMate && abs(evalBefore.score.mateWhite ?? 99) <= 3

            let classification = MoveClassifier.classify(MoveClassificationInput(
                plyIndex: idx,
                sanPrefix: isStandardStart ? sanPrefix : [],
                openingPlyHint: isStandardStart ? game.openingPly : 0,
                playedUci: applied.move.uci,
                bestMoveUci: evalBefore.bestMoveUci,
                beforeBoard: beforeBoard,
                afterBoard: afterBoard,
                moverColor: mover,
                fromSquare: applied.move.from,
                toSquare: applied.move.to,
                movedPiece: applied.piece.type,
                capturedPiece: applied.captured?.type,
                promotionPiece: applied.move.promotion,
                positionRepeated: repeatCount >= 2,
                moverWinBefore: winBefore,
                moverWinAfter: winAfter,
                secondBestGapWin: secondBestGap,
                hasSecondLine: hasSecond,
                missedMate: missedMate,
                missedShortMate: missedShortMate,
                walkedIntoMate: walkedIntoMate,
                forceDrawRepetition: isTerminalRepetitionDraw,
                deliversForcedMate: stillHasMate || (isTopMove && hadMateForMover)
            ))
            let moveAcc = classification == .book ? 100.0 : ChessMath.calculateMoveAccuracy(winLoss: winLoss)

            let bestPvSan = ChessMath.uciLineToSAN(fen: applied.beforeFen, uciMoves: evalBefore.pv, maxMoves: 5)
            let fallbackBestSan = ChessMath.uciLineToSAN(fen: applied.beforeFen, uciMoves: [evalBefore.bestMoveUci], maxMoves: 1).first
            let bestSan = bestPvSan.first ?? fallbackBestSan ?? applied.san
            let topLines: [TopEngineLineSummary] = evalBefore.lines.prefix(3).map { line in
                let pvSan = ChessMath.uciLineToSAN(fen: applied.beforeFen, uciMoves: line.pv, maxMoves: 4)
                return TopEngineLineSummary(
                    san: pvSan.first ?? line.bestMoveUci,
                    evalDisplay: line.score.display,
                    pvSan: pvSan
                )
            }

            let isClutch = classification == .great && winBefore < 52 && secondBestGap >= 15
            let detectedMotif: String? = (classification == .mistake || classification == .blunder)
                ? MoveClassifier.detectTacticalMotif(
                    beforeBoard: beforeBoard,
                    afterBoard: afterBoard,
                    moverColor: mover,
                    playedToSquare: applied.move.to,
                    bestMoveUci: evalBefore.bestMoveUci,
                    missedMate: missedMate,
                    walkedIntoMate: walkedIntoMate
                )
                : nil
            let coaching = MoveClassifier.generateExplanation(
                classification: classification,
                playedSan: applied.san,
                bestSan: bestSan,
                winLoss: winLoss,
                evalAfterDisplay: evalAfter.score.display,
                isClutchSave: isClutch,
                detectedMotif: detectedMotif
            )

            var timeSpent: Double? = nil
            var clockTag: String? = nil
            if let clk = pgnMove.clockSeconds {
                if let prev = prevClockByColor[mover] {
                    let rawDelta = prev + tcInc - clk
                    // Ignore negative deltas from opponent adding +15s on Lichess
                    if rawDelta >= -1.0 {
                        timeSpent = max(0, rawDelta)
                    }
                }
                if clk < lowClockLimit {
                    clockTag = "time-trouble"
                } else if let spent = timeSpent, spent < 5.0 && clk > 180.0 {
                    clockTag = "impulse"
                }
                prevClockByColor[mover] = clk
            } else {
                prevClockByColor[mover] = nil
            }

            let phase = MoveClassifier.detectPhase(plyIndex: idx, board: afterBoard, isStandardStart: isStandardStart)

            plies.append(AnalyzedPly(
                ply: idx + 1,
                moveNumber: beforeBoard.fullmoveNumber,
                color: mover,
                san: applied.san,
                uci: applied.move.uci,
                from: applied.move.from.algebraic,
                to: applied.move.to.algebraic,
                promotion: applied.move.promotion?.rawValue,
                captured: applied.captured?.type.rawValue,
                beforeFen: applied.beforeFen,
                afterFen: applied.afterFen,
                clockText: pgnMove.clockText,
                clockSeconds: pgnMove.clockSeconds,
                timeSpentSeconds: timeSpent,
                clockTag: clockTag,
                bestMoveUci: evalBefore.bestMoveUci,
                bestMoveSan: bestSan,
                bestPvSan: bestPvSan,
                topLines: topLines,
                threatMoveUci: nil,
                threatMoveSan: nil,
                evalBefore: evalBefore.score,
                evalAfter: evalAfter.score,
                secondBestGapWin: secondBestGap,
                secondBestGapPawns: nil,
                isCriticalMoment: winLoss > 12 || classification == .brilliant || classification == .great,
                isClutchSave: isClutch,
                deepened: wasDeepened,
                winLoss: (winLoss * 10.0).rounded() / 10.0,
                accuracy: moveAcc,
                classification: classification,
                phase: phase,
                coaching: coaching
            ))
        }

        let whiteSummary = summarize(plies: plies, color: .white, game: game)
        let blackSummary = summarize(plies: plies, color: .black, game: game)
        let detected = isStandardStart
            ? (MoveClassifier.lookupOpening(byMoves: sanPrefix)?.name ?? game.openingName)
            : game.openingName

        return AnalyzedGame(
            id: game.id,
            analyzedAt: Int64(Date().timeIntervalSince1970 * 1000.0),
            depth: preset.rawValue,
            classificationVersion: MoveClassifier.classificationVersion,
            game: game,
            initialEval: initialEvalResult.score,
            plies: plies,
            whiteSummary: whiteSummary,
            blackSummary: blackSummary,
            openingLineDetected: detected
        )
    }

    /// Instantly upgrades previously analyzed games to the latest `MoveClassifier.classificationVersion`
    /// without re-running the engine — promoting newly qualifying Brilliant sacrifices and clearing false positives.
    public static func reclassifyIfOutdated(_ analyzed: AnalyzedGame) -> AnalyzedGame {
        guard (analyzed.classificationVersion ?? 0) < MoveClassifier.classificationVersion,
              !analyzed.plies.isEmpty else {
            return analyzed
        }

        var seenKeys: [String: Int] = [:]
        if let firstBefore = try? ChessBoard(fen: analyzed.plies[0].beforeFen) {
            seenKeys[firstBefore.positionKey] = 1
        }
        let isStandardStart = analyzed.plies[0].beforeFen == ChessBoard.initialFEN
        var sanPrefix: [String] = []
        var updatedPlies: [AnalyzedPly] = []
        updatedPlies.reserveCapacity(analyzed.plies.count)
        var anyChanged = false

        for (idx, ply) in analyzed.plies.enumerated() {
            sanPrefix.append(ply.san)
            let beforeBoard = try? ChessBoard(fen: ply.beforeFen)
            let afterBoard = try? ChessBoard(fen: ply.afterFen)
            let posKey = afterBoard?.positionKey ?? ""
            let repeatCount: Int
            if !posKey.isEmpty {
                repeatCount = (seenKeys[posKey] ?? 0) + 1
                seenKeys[posKey] = repeatCount
            } else {
                repeatCount = 1
            }

            let eligibleForRefresh = ply.classification == .brilliant
                || ply.classification == .great
                || ply.classification == .best
                || ply.classification == .excellent
                || (ply.classification == .book && idx >= 8)

            guard eligibleForRefresh,
                  let beforeBoard,
                  let afterBoard,
                  let fromSq = Square(algebraic: ply.from),
                  let toSq = Square(algebraic: ply.to),
                  let movedPiece = beforeBoard[fromSq]?.type else {
                updatedPlies.append(ply)
                continue
            }

            let isTerminalRepetitionDraw = repeatCount >= 3 && idx == analyzed.plies.count - 1 && analyzed.game.resultString == "1/2-1/2"
            let isTopMove = ply.uci == ply.bestMoveUci && !isTerminalRepetitionDraw
            let winBefore = ChessMath.moverWinPercent(ply.evalBefore, mover: ply.color)
            let winAfter = ChessMath.moverWinPercent(ply.evalAfter, mover: ply.color)
            let hadMateForMover: Bool = {
                guard let m = ply.evalBefore.mateWhite else { return false }
                return ply.color == .white ? m > 0 : m < 0
            }()
            let stillHasMate: Bool = {
                if ply.evalAfter.isCheckmate == true { return true }
                guard let m = ply.evalAfter.mateWhite else { return false }
                return ply.color == .white ? m > 0 : m < 0
            }()
            let missedMate = hadMateForMover && !stillHasMate
            let missedShortMate = missedMate && abs(ply.evalBefore.mateWhite ?? 99) <= 3
            let hasSecond = ((ply.topLines?.count ?? 2) >= 2) || ply.secondBestGapWin > 0
            let capturedType: PieceType? = ply.captured.flatMap { PieceType(rawValue: $0.lowercased()) }
                ?? (beforeBoard[toSq]?.color == ply.color.opposite
                    ? beforeBoard[toSq]?.type
                    : (movedPiece == .pawn && fromSq.file != toSq.file ? .pawn : nil))
            let promoType: PieceType? = ply.promotion.flatMap { PieceType(rawValue: $0.lowercased()) }
                ?? (ply.uci.count >= 5 ? PieceType(rawValue: String(ply.uci.suffix(1)).lowercased()) : nil)

            let newClass = MoveClassifier.classify(MoveClassificationInput(
                plyIndex: idx,
                sanPrefix: isStandardStart ? sanPrefix : [],
                openingPlyHint: isStandardStart ? analyzed.game.openingPly : 0,
                playedUci: ply.uci,
                bestMoveUci: ply.bestMoveUci,
                beforeBoard: beforeBoard,
                afterBoard: afterBoard,
                moverColor: ply.color,
                fromSquare: fromSq,
                toSquare: toSq,
                movedPiece: movedPiece,
                capturedPiece: capturedType,
                promotionPiece: promoType,
                positionRepeated: repeatCount >= 2,
                moverWinBefore: winBefore,
                moverWinAfter: winAfter,
                secondBestGapWin: ply.secondBestGapWin,
                hasSecondLine: hasSecond,
                missedMate: missedMate,
                missedShortMate: missedShortMate,
                walkedIntoMate: false,
                forceDrawRepetition: isTerminalRepetitionDraw,
                deliversForcedMate: stillHasMate || (isTopMove && hadMateForMover)
            ))

            if newClass == ply.classification {
                updatedPlies.append(ply)
                continue
            }

            anyChanged = true
            let isClutch = newClass == .great && winBefore < 52 && ply.secondBestGapWin >= 15
            let newCoaching = MoveClassifier.generateExplanation(
                classification: newClass,
                playedSan: ply.san,
                bestSan: ply.bestMoveSan,
                winLoss: ply.winLoss,
                evalAfterDisplay: ply.evalAfter.display,
                isClutchSave: isClutch
            )
            updatedPlies.append(AnalyzedPly(
                ply: ply.ply,
                moveNumber: ply.moveNumber,
                color: ply.color,
                san: ply.san,
                uci: ply.uci,
                from: ply.from,
                to: ply.to,
                promotion: ply.promotion,
                captured: ply.captured,
                beforeFen: ply.beforeFen,
                afterFen: ply.afterFen,
                clockText: ply.clockText,
                clockSeconds: ply.clockSeconds,
                timeSpentSeconds: ply.timeSpentSeconds,
                clockTag: ply.clockTag,
                bestMoveUci: ply.bestMoveUci,
                bestMoveSan: ply.bestMoveSan,
                bestPvSan: ply.bestPvSan,
                topLines: ply.topLines,
                threatMoveUci: ply.threatMoveUci,
                threatMoveSan: ply.threatMoveSan,
                evalBefore: ply.evalBefore,
                evalAfter: ply.evalAfter,
                secondBestGapWin: ply.secondBestGapWin,
                secondBestGapPawns: ply.secondBestGapPawns,
                isCriticalMoment: ply.winLoss > 12 || newClass == .brilliant || newClass == .great,
                isClutchSave: isClutch,
                deepened: ply.deepened,
                winLoss: ply.winLoss,
                accuracy: newClass == .book ? 100.0 : ply.accuracy,
                classification: newClass,
                phase: ply.phase,
                coaching: newCoaching
            ))
        }

        let whiteSummary = anyChanged ? summarize(plies: updatedPlies, color: .white, game: analyzed.game) : analyzed.whiteSummary
        let blackSummary = anyChanged ? summarize(plies: updatedPlies, color: .black, game: analyzed.game) : analyzed.blackSummary
        return AnalyzedGame(
            id: analyzed.id,
            analyzedAt: analyzed.analyzedAt,
            depth: analyzed.depth,
            classificationVersion: MoveClassifier.classificationVersion,
            game: analyzed.game,
            initialEval: analyzed.initialEval,
            plies: updatedPlies,
            whiteSummary: whiteSummary,
            blackSummary: blackSummary,
            openingLineDetected: analyzed.openingLineDetected
        )
    }

    public static func extractMistakePuzzles(
        from analyzedGames: [AnalyzedGame],
        handles: [String] = []
    ) -> [MistakePuzzle] {
        var puzzles: [MistakePuzzle] = []

        for ag in analyzedGames where !ag.game.isCustomFenGame && !ag.plies.isEmpty {
            guard let userColor = ag.game.resolvedUserColor(handles: handles) else { continue }

            for p in ag.plies where p.color == userColor {
                guard p.classification == .blunder || p.classification == .mistake else { continue }
                guard !p.bestMoveUci.isEmpty, p.bestMoveUci != p.uci else { continue }
                let oppForPly = p.color == .black ? ag.game.white.name : ag.game.black.name
                puzzles.append(MistakePuzzle(
                    id: "\(ag.id)::ply::\(p.ply)",
                    gameId: ag.id,
                    ply: p.ply,
                    moveNumber: p.moveNumber,
                    playerColor: p.color,
                    fen: p.beforeFen,
                    playedSan: p.san,
                    bestMoveUci: p.bestMoveUci,
                    bestMoveSan: p.bestMoveSan,
                    pvSan: p.bestPvSan,
                    classification: p.classification,
                    winLoss: p.winLoss,
                    phase: p.phase,
                    tacticalTag: p.coaching.tacticalTag,
                    headline: p.coaching.headline,
                    opponentName: oppForPly,
                    openingName: ag.openingLineDetected ?? ag.game.openingName,
                    playedAt: ag.game.createdAt
                ))
            }
        }
        return puzzles.sorted { lhs, rhs in
            if lhs.playedAt != rhs.playedAt { return lhs.playedAt > rhs.playedAt }
            return lhs.winLoss > rhs.winLoss
        }
    }

    public static func computeInsights(
        analyzedGames: [AnalyzedGame],
        recentGames: [GameRecord] = [],
        handles: [String] = []
    ) -> InsightsSnapshot {
        // Strictly match VaultService & AdvancedInsightsService: only count games where the user's side is known
        // so GM broadcasts / imported third-party PGNs never skew personal !! counts, W/D/L, or Avg Accuracy.
        let validGames: [(ag: AnalyzedGame, color: PieceColor)] = analyzedGames.compactMap { ag in
            guard !ag.game.isCustomFenGame && !ag.plies.isEmpty else { return nil }
            guard let color = ag.game.resolvedUserColor(handles: handles) else { return nil }
            return (ag, color)
        }
        guard !validGames.isEmpty else {
            return InsightsSnapshot(
                analyzedCount: 0,
                avgAccuracy: 0,
                wins: 0,
                draws: 0,
                losses: 0,
                openingAccuracy: 0,
                middlegameAccuracy: 0,
                endgameAccuracy: 0,
                totalBrilliants: 0,
                totalBlunders: 0,
                topOpenings: []
            )
        }

        var accSum = 0.0
        var wins = 0
        var draws = 0
        var losses = 0
        var openingAccs: [Double] = []
        var middleAccs: [Double] = []
        var endgameAccs: [Double] = []
        var brilliants = 0
        var blunders = 0
        var openingMap: [String: (games: Int, wins: Int, accSum: Double)] = [:]
        var latestLiveBySpeed: [String: (createdAt: Int64, rating: Int)] = [:]
        var latestFallbackBySpeed: [String: (createdAt: Int64, rating: Int)] = [:]
        var perfElos: [Int] = []

        func recordRating(from g: GameRecord, color: PieceColor) {
            guard let rating = (color == .white ? g.white.rating : g.black.rating), rating > 0 else { return }
            let speedKey = g.speed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let label = speedKey.isEmpty ? "Rated" : speedKey.capitalized
            let isLive = (g.source == .lichess || g.source == .chesscom)
            if isLive {
                if let existing = latestLiveBySpeed[label] {
                    if g.createdAt > existing.createdAt { latestLiveBySpeed[label] = (g.createdAt, rating) }
                } else {
                    latestLiveBySpeed[label] = (g.createdAt, rating)
                }
            } else {
                if let existing = latestFallbackBySpeed[label] {
                    if g.createdAt > existing.createdAt { latestFallbackBySpeed[label] = (g.createdAt, rating) }
                } else {
                    latestFallbackBySpeed[label] = (g.createdAt, rating)
                }
            }
        }

        // Also ingest synced unanalyzed games so Current Elo stays live right after Sync!
        for g in recentGames where !g.isCustomFenGame {
            if let color = g.resolvedUserColor(handles: handles) {
                recordRating(from: g, color: color)
            }
        }

        for (ag, color) in validGames {
            let summary = color == .white ? ag.whiteSummary : ag.blackSummary
            accSum += summary.accuracy
            brilliants += summary.count(for: .brilliant)
            blunders += summary.count(for: .blunder)
            if summary.estimatedElo > 0 {
                perfElos.append(summary.estimatedElo)
            }
            recordRating(from: ag.game, color: color)

            let res = ag.game.userResult(handles: handles)
            if res == "W" { wins += 1 }
            else if res == "D" { draws += 1 }
            else if res == "L" { losses += 1 }

            let opName = ag.openingLineDetected ?? ag.game.openingName
            var entry = openingMap[opName] ?? (0, 0, 0)
            entry.games += 1
            if res == "W" { entry.wins += 1 }
            entry.accSum += summary.accuracy
            openingMap[opName] = entry

            for p in ag.plies where p.color == color {
                switch p.phase {
                case .opening: openingAccs.append(p.accuracy)
                case .middlegame: middleAccs.append(p.accuracy)
                case .endgame: endgameAccs.append(p.accuracy)
                }
            }
        }

        func mean(_ vals: [Double]) -> Double {
            guard !vals.isEmpty else { return 0 }
            return ((vals.reduce(0, +) / Double(vals.count)) * 10.0).rounded() / 10.0
        }

        let topOpenings = openingMap.map { name, data in
            (
                name: name,
                games: data.games,
                winRate: Double(data.wins) / Double(max(1, data.games)) * 100.0,
                avgAccuracy: (data.accSum / Double(max(1, data.games)) * 10.0).rounded() / 10.0
            )
        }
        .sorted { lhs, rhs in
            if lhs.games != rhs.games { return lhs.games > rhs.games }
            if lhs.avgAccuracy != rhs.avgAccuracy { return lhs.avgAccuracy > rhs.avgAccuracy }
            return lhs.name < rhs.name
        }
        .prefix(5)

        let chosenRatingMap = latestLiveBySpeed.isEmpty ? latestFallbackBySpeed : latestLiveBySpeed
        let currentRatings = chosenRatingMap
            .sorted { lhs, rhs in
                if lhs.value.createdAt != rhs.value.createdAt { return lhs.value.createdAt > rhs.value.createdAt }
                return lhs.key < rhs.key
            }
            .prefix(4)
            .map { (speed: $0.key, rating: $0.value.rating) }

        let avgPerfElo: Int? = perfElos.isEmpty
            ? nil
            : Int((Double(perfElos.reduce(0, +)) / Double(perfElos.count)).rounded())

        return InsightsSnapshot(
            analyzedCount: validGames.count,
            avgAccuracy: ((accSum / Double(validGames.count)) * 10.0).rounded() / 10.0,
            wins: wins,
            draws: draws,
            losses: losses,
            openingAccuracy: mean(openingAccs),
            middlegameAccuracy: mean(middleAccs),
            endgameAccuracy: mean(endgameAccs),
            totalBrilliants: brilliants,
            totalBlunders: blunders,
            topOpenings: Array(topOpenings),
            currentRatings: Array(currentRatings),
            avgPerformanceElo: avgPerfElo
        )
    }

    private static func summarize(
        plies: [AnalyzedPly],
        color: PieceColor,
        game: GameRecord
    ) -> PlayerAnalysisSummary {
        let sidePlies = plies.filter { $0.color == color }
        var counts: [String: Int] = [:]
        for c in MoveClassification.allCases { counts[c.rawValue] = 0 }
        for p in sidePlies {
            counts[p.classification.rawValue, default: 0] += 1
        }
        let acc = ChessMath.calculateGameAccuracy(
            moveAccuracies: sidePlies.map(\.accuracy),
            winPercents: sidePlies.map { ChessMath.moverWinPercent($0.evalBefore, mover: color) }
        )
        let avgLoss = sidePlies.isEmpty
            ? 0.0
            : (sidePlies.map(\.winLoss).reduce(0, +) / Double(sidePlies.count) * 10.0).rounded() / 10.0

        let resScore: Double
        if game.resultString == "1/2-1/2" { resScore = 0.5 }
        else if game.resultString == "1-0" { resScore = color == .white ? 1.0 : 0.0 }
        else if game.resultString == "0-1" { resScore = color == .black ? 1.0 : 0.0 }
        else { resScore = 0.5 }

        let elo: Int
        if sidePlies.isEmpty {
            elo = (color == .white ? game.white.rating : game.black.rating) ?? 1500
        } else {
            elo = ChessMath.estimateGameElo(
                playerRating: color == .white ? game.white.rating : game.black.rating,
                opponentRating: color == .white ? game.black.rating : game.white.rating,
                accuracy: acc,
                resultScore: resScore
            )
        }
        return PlayerAnalysisSummary(accuracy: acc, estimatedElo: elo, counts: counts, avgWinLoss: avgLoss)
    }
}
