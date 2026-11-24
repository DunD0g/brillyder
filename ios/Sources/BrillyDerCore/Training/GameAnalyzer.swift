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
}

public enum GameAnalyzer {
    public static func analyze(
        game: GameRecord,
        engine: any ChessEngine,
        preset: AnalysisDepthPreset = .balanced,
        onProgress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> AnalyzedGame {
        let parsed = try PGNParser.parse(game.pgn)
        let totalPlies = parsed.moves.count
        let isStandardStart = (parsed.startFen == ChessBoard.initialFEN)
        let tcInc = PGNParser.parseTimeControl(parsed.headers["TimeControl"])?.incrementSeconds ?? 0.0
        onProgress?(0, max(1, totalPlies))

        let initialEvalResult = try await engine.analyze(
            fen: parsed.startFen,
            depth: preset.rawValue,
            multiPV: 2,
            maxTimeMs: preset.maxTimeMs
        )

        var evalByPlyIndex: [EngineEval] = [initialEvalResult]
        evalByPlyIndex.reserveCapacity(totalPlies + 1)

        for (idx, pgnMove) in parsed.moves.enumerated() {
            try Task.checkCancellation()
            let eval = try await engine.analyze(
                fen: pgnMove.applied.afterFen,
                depth: preset.rawValue,
                multiPV: 2,
                maxTimeMs: preset.maxTimeMs
            )
            evalByPlyIndex.append(eval)
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

        for (idx, pgnMove) in parsed.moves.enumerated() {
            let applied = pgnMove.applied
            let evalBefore = evalByPlyIndex[idx]
            var evalAfter = evalByPlyIndex[idx + 1]
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
                afterBoard: afterBoard,
                moverColor: mover,
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
                forceDrawRepetition: isTerminalRepetitionDraw
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
            let coaching = MoveClassifier.generateExplanation(
                classification: classification,
                playedSan: applied.san,
                bestSan: bestSan,
                winLoss: winLoss,
                evalAfterDisplay: evalAfter.score.display,
                isClutchSave: isClutch
            )

            var timeSpent: Double? = nil
            var clockTag: String? = nil
            if let clk = pgnMove.clockSeconds {
                if let prev = prevClockByColor[mover] {
                    timeSpent = max(0, prev + tcInc - clk)
                }
                if clk < 60.0 {
                    clockTag = "time-trouble"
                } else if let spent = timeSpent, spent < 5.0 && clk > 180.0 {
                    clockTag = "impulse"
                }
                prevClockByColor[mover] = clk
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
                deepened: false,
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

    public static func extractMistakePuzzles(
        from analyzedGames: [AnalyzedGame],
        handles: [String] = []
    ) -> [MistakePuzzle] {
        var puzzles: [MistakePuzzle] = []

        for ag in analyzedGames where !ag.game.isCustomFenGame && !ag.plies.isEmpty {
            let userColor = ag.game.resolvedUserColor(handles: handles)
            let opponent = userColor == .black ? ag.game.white.name : ag.game.black.name

            for p in ag.plies {
                if let userColor, p.color != userColor { continue }
                guard p.classification == .blunder || p.classification == .mistake else { continue }
                guard !p.bestMoveUci.isEmpty, p.bestMoveUci != p.uci else { continue }
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
                    opponentName: opponent,
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
        handles: [String] = []
    ) -> InsightsSnapshot {
        let validGames = analyzedGames.filter { !$0.game.isCustomFenGame && !$0.plies.isEmpty }
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

        for ag in validGames {
            let color = ag.game.resolvedUserColor(handles: handles) ?? .white
            let summary = color == .white ? ag.whiteSummary : ag.blackSummary
            accSum += summary.accuracy
            brilliants += summary.count(for: .brilliant)
            blunders += summary.count(for: .blunder)

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
        .sorted { $0.games > $1.games }
        .prefix(5)

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
            topOpenings: Array(topOpenings)
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

        let elo = ChessMath.estimateGameElo(
            playerRating: color == .white ? game.white.rating : game.black.rating,
            opponentRating: color == .white ? game.black.rating : game.white.rating,
            accuracy: acc,
            resultScore: resScore
        )
        return PlayerAnalysisSummary(accuracy: acc, estimatedElo: elo, counts: counts, avgWinLoss: avgLoss)
    }
}
