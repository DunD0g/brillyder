import SwiftUI
import BrillyDerCore

public struct TrainTabView: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var showingDailySession = false
    @State private var showingGravityCheck = false
    @State private var showingDailyOpeningsPicker = false

    public var body: some View {
        let plan = store.dailyWorkoutPlan

        ZStack {
            CosmicVoidBackdrop(style: store.surfaceStyle)

            ScrollView {
                VStack(spacing: 16) {
                    // Hero Dual-Tone Brilly / Der Brand Header
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            BrillyWordmarkView(fontSize: 33, uppercase: false, showSlash: true)
                            Text(store.copy(
                                cosmic: "Cosmic chess engine & opening coach",
                                classic: "On-device chess engine & coach"
                            ))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BrillyPalette.inkSecondary)
                        }
                        Spacer(minLength: 8)
                        HStack(spacing: 4) {
                            Text("!!")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                            Text("/")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkSecondary.opacity(0.65))
                            Text("??")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(BrillyPalette.blunderRose)
                        }
                        .accessibilityHidden(true)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.06))
                                .overlay(
                                    Capsule().strokeBorder(
                                        LinearGradient(
                                            colors: [BrillyPalette.brillyTeal.opacity(0.45), BrillyPalette.blunderRose.opacity(0.45)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1
                                    )
                                )
                        )
                    }
                    .padding(.top, 2)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(TrainSubMode.allCases) { mode in
                                let sel = store.selectedTrainMode == mode
                                Button(mode.rawValue) {
                                    if mode == .labs && !store.hasProAccess {
                                        store.openProPaywall(feature: "Endgame & Vision Labs")
                                        return
                                    }
                                    withAnimation(.snappy) {
                                        store.selectedTrainMode = mode
                                    }
                                    store.triggerHaptic(.move)
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(sel ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(sel ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    switch store.selectedTrainMode {
                    case .daily:
                        dailyCoachBody(plan: plan)
                    case .woodpecker:
                        WoodpeckerCyclePanel()
                    case .conversion:
                        AdvantageConversionPanel()
                    case .mistakes:
                        MistakeDeckPanel()
                    case .labs:
                        TrainLabsView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
            .brillySoftScrollEdge()
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showingDailySession) {
            DailySessionSheet(plan: store.dailyWorkoutPlan)
                .environment(store)
        }
        .sheet(isPresented: $showingGravityCheck) {
            GravityCheckSheet()
                .environment(store)
        }
        .sheet(isPresented: $showingDailyOpeningsPicker) {
            DailyOpeningsPickerSheet()
                .environment(store)
        }
    }

    @ViewBuilder
    private func dailyCoachBody(plan: DailyWorkoutPlan) -> some View {
        // MARK: - 1. Daily-First Coach Hero
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.copy(cosmic: "DAILY FLIGHT PLAN", classic: "DAILY IMPROVEMENT PLAN"))
                        .font(.caption.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(BrillyPalette.brillyTeal)

                    Text(store.copy(
                        cosmic: "\(store.dailyDuration.rawValue)-Minute Orbit Coach",
                        classic: "\(store.dailyDuration.rawValue)-Minute Daily Coach"
                    ))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                }
                Spacer()
                Button {
                    showingDailyOpeningsPicker = true
                } label: {
                    Label("\(store.dueOpeningCount) due", systemImage: "brain.head.profile")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                }
                .buttonStyle(.plain)
            }

            // Duration Picker (10m | 15m | 25m)
            HStack(spacing: 8) {
                ForEach(DailyDurationMinutes.allCases) { dur in
                    let selected = store.dailyDuration == dur
                    let lockedPro = (dur == .twentyFive && !store.hasProAccess)
                    Button {
                        if lockedPro {
                            store.openProPaywall(feature: "25-Minute Orbit Coach")
                            return
                        }
                        withAnimation(.snappy) {
                            store.dailyDuration = dur
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(dur.label)
                            if lockedPro {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                            }
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(selected ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // 4-Stage Summary Grid (Tap 1. Openings to choose which openings are active in Daily FSRS!)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button {
                    showingDailyOpeningsPicker = true
                } label: {
                    stageChip(
                        title: "1. Openings · Edit",
                        value: store.dailyOpeningCourseIds.isEmpty
                            ? "Pick Openings"
                            : "\(plan.stage1OpeningCards.count) FSRS (\(store.dailyOpeningCourseIds.count))",
                        icon: "book.fill",
                        tint: BrillyPalette.brillyTeal
                    )
                }
                .buttonStyle(.plain)

                stageChip(
                    title: "2. Blunders",
                    value: "\(plan.stage2Blunders.count) Rewind",
                    icon: "arrow.uturn.backward.circle.fill",
                    tint: BrillyPalette.blunderRose
                )
                stageChip(
                    title: "3. Speed",
                    value: "\(plan.stage3SpeedDrills.count) Patterns",
                    icon: "bolt.fill",
                    tint: BrillyPalette.warpPurple
                )
                stageChip(
                    title: "4. Target",
                    value: plan.stage4Drills.isEmpty ? plan.stage4FocusLabel : "\(plan.stage4Drills.count) \(plan.stage4FocusLabel)",
                    icon: "scope",
                    tint: BrillyPalette.goldAmber
                )
            }

            Button {
                showingDailySession = true
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text(store.copy(cosmic: "Launch \(store.dailyDuration.label) Mission", classic: "Start \(store.dailyDuration.label) Daily Session"))
                        .fontWeight(.bold)
                }
                .font(.headline)
                .foregroundStyle(BrillyPalette.voidBg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [BrillyPalette.brillyTeal, Color(hex: 0x06B6D4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .brillySurface(store.surfaceStyle, cornerRadius: 24, tint: BrillyPalette.brillyTeal)

        // MARK: - 2. 60-Second Gravity Check
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(BrillyPalette.warpPurple.opacity(0.22))
                    .frame(width: 48, height: 48)
                Image(systemName: "timer")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BrillyPalette.warpPurple)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(store.copy(cosmic: "60s Gravity Check", classic: "60-Second Warmup"))
                    .font(.headline)
                    .foregroundStyle(BrillyPalette.inkPrimary)
                Text("4 rapid-fire tactics & opening flashes before you play.")
                    .font(.caption)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }

            Spacer()

            Button("Go") {
                showingGravityCheck = true
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(BrillyPalette.inkPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
            .buttonStyle(.plain)
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: BrillyPalette.warpPurple, interactive: true)

        // MARK: - 3. Quick Status Row (Replaces `0 Bookmarks` with Dynamic Daily Streak!)
        HStack(spacing: 12) {
            statCard(
                label: "Analyzed Games",
                value: "\(store.analyzedGames.count)",
                tint: BrillyPalette.brillyTeal
            )
            statCard(
                label: "Mistake Deck",
                value: "\(store.mistakeDeck.count)",
                tint: BrillyPalette.blunderRose
            )
            if store.bookmarks.isEmpty {
                statCard(
                    label: "Daily Streak",
                    value: store.dailyStreakDays > 0 ? "🔥 \(store.dailyStreakDays)d" : "🔥 Start",
                    tint: BrillyPalette.goldAmber
                )
            } else {
                statCard(
                    label: "Bookmarks",
                    value: "\(store.bookmarks.count)",
                    tint: BrillyPalette.goldAmber
                )
            }
        }
    }

    private func stageChip(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkSecondary)
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func statCard(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(BrillyPalette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .brillySurface(store.surfaceStyle, cornerRadius: 16)
    }
}

// MARK: - Interactive Daily Workout Session Sheet

private struct DailySessionSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let plan: DailyWorkoutPlan

    private struct DrillStep: Identifiable {
        let id: String
        let stageNumber: Int
        let stageLabel: String
        let contextTitle: String
        let moveNumber: Int
        let fen: String
        let orientation: PieceColor
        let expectedUci: String
        let expectedSan: String
        let prompt: String
        let coachingPlan: String?
        let previousBadSan: String?
        let opponentLastMove: (from: Square, to: Square, san: String)?
        let wrongMoveTraps: [WrongMoveTrap]
        let cardId: String?
    }

    @State private var frozenSteps: [DrillStep] = []
    @State private var initialized: Bool = false
    @State private var stepIndex: Int = 0
    @State private var board: ChessBoard = ChessBoard()
    @State private var statusMessage: String = "Find the strongest move."
    @State private var isSolved: Bool = false
    @State private var hadMistakeOnCurrent: Bool = false
    @State private var hintLevel: Int = 0 // 0 = none, 1 = highlight piece, 2 = show legal arrow
    @State private var shownAt: Date = Date()
    @State private var cleanSolveCount: Int = 0
    @State private var lastMove: (from: Square, to: Square)? = nil
    @State private var solvedBadge: MoveBadgeOverlay? = nil

    private func buildInitialSteps() -> [DrillStep] {
        let coursesById = Dictionary(store.allCourses.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let gamesById = Dictionary(store.analyzedGames.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var out: [DrillStep] = []

        func prevGameMove(gameId: String, beforePly ply: Int) -> (from: Square, to: Square, san: String)? {
            guard ply >= 2,
                  let game = gamesById[gameId],
                  let prev = game.plies.first(where: { $0.ply == ply - 1 }),
                  let f = Square(algebraic: prev.from),
                  let t = Square(algebraic: prev.to) else { return nil }
            return (f, t, prev.san)
        }

        for c in plan.stage1OpeningCards {
            guard let fenBoard = try? ChessBoard(fen: c.fen),
                  DailyCoachPlanner.legalMove(uci: c.expectedUci, on: fenBoard) != nil else { continue }
            let sideToMove = fenBoard.turn
            let moveNum = fenBoard.fullmoveNumber
            let course = coursesById[c.courseId]
            let line = course?.lines.first { $0.id == c.lineId }
            let courseName = course?.name ?? "Opening"
            let lineTitle = line?.title
            let contextTitle = lineTitle.map { "\(courseName) · \($0)" } ?? courseName
            let ann = line?.annotations.first { $0.ply == c.ply }

            let seq: [String] = {
                if !c.moveSequence.isEmpty { return c.moveSequence }
                if let lineMoves = line?.moves, c.ply > 0, c.ply <= lineMoves.count {
                    return Array(lineMoves.prefix(c.ply))
                }
                return []
            }()
            let oppPrev = DailyCoachPlanner.precedingMove(for: seq)
            let promptText: String = {
                if let opp = oppPrev {
                    return "After \(opp.san), play your Move \(moveNum) repertoire reply as \(sideToMove.displayName)."
                }
                return "Move \(moveNum) — play your \(courseName) opening move as \(sideToMove.displayName)."
            }()

            out.append(DrillStep(
                id: "s1_\(c.cardId)",
                stageNumber: 1,
                stageLabel: "Openings",
                contextTitle: contextTitle,
                moveNumber: moveNum,
                fen: c.fen,
                orientation: sideToMove,
                expectedUci: c.expectedUci,
                expectedSan: c.expectedSan,
                prompt: promptText,
                coachingPlan: ann?.plan,
                previousBadSan: nil,
                opponentLastMove: oppPrev,
                wrongMoveTraps: ann?.wrongMoveTraps ?? [],
                cardId: c.cardId
            ))
        }

        func appendPuzzleSteps(_ puzzles: [MistakePuzzle], stageNumber: Int, stageLabel: String, prefix: String) {
            for p in puzzles {
                guard let fenBoard = try? ChessBoard(fen: p.fen),
                      DailyCoachPlanner.legalMove(uci: p.bestMoveUci, on: fenBoard) != nil else { continue }
                let sideToMove = fenBoard.turn
                let moveNum = fenBoard.fullmoveNumber
                let oppPrev = prevGameMove(gameId: p.gameId, beforePly: p.ply)
                let pvLine = p.pvSan.isEmpty ? nil : "Best line: \(p.pvSan.prefix(4).joined(separator: " "))"
                let promptText: String = {
                    if stageNumber == 2 {
                        return "You played \(p.playedSan) vs \(p.opponentName). Find the stronger move!"
                    }
                    return p.headline.isEmpty ? "Find the sharpest \(sideToMove.displayName) continuation." : p.headline
                }()
                out.append(DrillStep(
                    id: "\(prefix)_\(p.id)",
                    stageNumber: stageNumber,
                    stageLabel: stageLabel,
                    contextTitle: "\(p.openingName) vs \(p.opponentName)",
                    moveNumber: moveNum,
                    fen: p.fen,
                    orientation: sideToMove,
                    expectedUci: p.bestMoveUci,
                    expectedSan: p.bestMoveSan,
                    prompt: promptText,
                    coachingPlan: pvLine,
                    previousBadSan: p.playedSan,
                    opponentLastMove: oppPrev,
                    wrongMoveTraps: [],
                    cardId: nil
                ))
            }
        }

        appendPuzzleSteps(plan.stage2Blunders, stageNumber: 2, stageLabel: "Rewind", prefix: "s2")
        appendPuzzleSteps(plan.stage3SpeedDrills, stageNumber: 3, stageLabel: "Speed", prefix: "s3")
        appendPuzzleSteps(plan.stage4Drills, stageNumber: 4, stageLabel: plan.stage4FocusLabel, prefix: "s4")

        if out.isEmpty {
            for fb in DailyCoachPlanner.fallbackGravityFlashes {
                guard let fenBoard = try? ChessBoard(fen: fb.fen),
                      DailyCoachPlanner.legalMove(uci: fb.expectedUci, on: fenBoard) != nil else { continue }
                out.append(DrillStep(
                    id: fb.id,
                    stageNumber: 1,
                    stageLabel: "Warmup",
                    contextTitle: fb.subtitle,
                    moveNumber: fenBoard.fullmoveNumber,
                    fen: fb.fen,
                    orientation: fenBoard.turn,
                    expectedUci: fb.expectedUci,
                    expectedSan: fb.expectedSan,
                    prompt: fb.prompt,
                    coachingPlan: nil,
                    previousBadSan: nil,
                    opponentLastMove: nil,
                    wrongMoveTraps: [],
                    cardId: nil
                ))
            }
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                if initialized && stepIndex >= frozenSteps.count {
                    VStack(spacing: 18) {
                        BrillyAlienUFOView(mood: .brilliant, size: 84, showBeam: true)
                        Text(store.copy(cosmic: "Orbit Complete!", classic: "Daily Session Complete!"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Text("Solved \(cleanSolveCount) / \(frozenSteps.count) positions cleanly on first try.")
                            .font(.subheadline)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                            .multilineTextAlignment(.center)
                        Button("Finish & Log Streak") {
                            store.markDailySessionCompleted()
                            dismiss()
                        }
                        .font(.headline)
                        .foregroundStyle(BrillyPalette.voidBg)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(BrillyPalette.brillyTeal))
                        .buttonStyle(.plain)
                    }
                    .padding(28)
                    .brillySurface(store.surfaceStyle, cornerRadius: 24, tint: BrillyPalette.brillyTeal)
                    .padding()
                } else if stepIndex < frozenSteps.count {
                    let current = frozenSteps[stepIndex]
                    let activeHighlights: [SquareHighlight] = (hintLevel >= 1 && !isSolved)
                        ? validatedHintHighlight(for: current.expectedUci, on: board)
                        : []
                    let activeArrows: [BoardArrow] = (hintLevel >= 2 && !isSolved)
                        ? validatedHintArrow(for: current.expectedUci, on: board)
                        : []

                    ScrollView {
                        VStack(spacing: 12) {
                            // Compact Stage Header + Progress Bar
                            HStack(spacing: 8) {
                                Text("Stage \(current.stageNumber) · \(current.stageLabel)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(BrillyPalette.brillyTeal.opacity(0.14)))
                                    .lineLimit(1)

                                Spacer(minLength: 4)

                                Text("\(stepIndex + 1) / \(frozenSteps.count)")
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                            }

                            TractorBeamProgressBar(
                                progress: Double(stepIndex + (isSolved ? 1 : 0)) / Double(max(1, frozenSteps.count)),
                                height: 8
                            )

                            // Authoritative Opening / Game Context Bar (Line + Exact FEN Move Number + Side)
                            HStack(spacing: 8) {
                                Text(current.contextTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(current.orientation == .white ? Color.white : Color(hex: 0x1E293B))
                                        .frame(width: 8, height: 8)
                                        .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.8))
                                    Text("Move \(current.moveNumber)\(current.orientation == .black ? "..." : "")")
                                        .font(.caption2.monospacedDigit().weight(.bold))
                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(Color.white.opacity(0.08)))

                                if let badSan = current.previousBadSan {
                                    Text("Played \(badSan)")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(BrillyPalette.blunderRose)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(BrillyPalette.blunderRose.opacity(0.14)))
                                }
                            }

                            InteractiveChessBoardView(
                                board: board,
                                orientation: current.orientation,
                                theme: store.boardTheme,
                                surfaceStyle: store.surfaceStyle,
                                interactive: !isSolved,
                                lastMove: lastMove,
                                arrows: activeArrows,
                                highlights: activeHighlights,
                                moveBadge: solvedBadge
                            ) { move in
                                handleMove(move, for: current)
                            }

                            // Clean Coach Guidance Card
                            VStack(alignment: .leading, spacing: 6) {
                                Text(current.prompt)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Text(statusMessage)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(isSolved ? BrillyPalette.brillyTeal : (hadMistakeOnCurrent ? BrillyPalette.blunderRose : BrillyPalette.inkSecondary))
                                    .fixedSize(horizontal: false, vertical: true)

                                if isSolved, let planText = current.coachingPlan, !planText.isEmpty {
                                    Text(planText)
                                        .font(.caption)
                                        .foregroundStyle(Color(hex: 0xCBD5E1))
                                        .padding(.top, 2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .brillySurface(store.surfaceStyle, cornerRadius: 16, tint: isSolved ? BrillyPalette.brillyTeal : nil)

                            // Progressive 2-Step Hint + Next/Skip Controls
                            HStack(spacing: 10) {
                                Button {
                                    triggerHint(for: current)
                                } label: {
                                    Label(
                                        hintLevel == 0 ? "Hint" : (hintLevel == 1 ? "Show Arrow" : "Arrow Shown"),
                                        systemImage: hintLevel == 0 ? "lightbulb.fill" : "arrow.up.right"
                                    )
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.goldAmber)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                                }
                                .buttonStyle(.plain)
                                .disabled(isSolved || hintLevel >= 2)
                                .opacity((isSolved || hintLevel >= 2) ? 0.50 : 1.0)

                                Button {
                                    advanceStep()
                                } label: {
                                    Label(isSolved ? "Next" : "Skip", systemImage: "arrow.right")
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(isSolved ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .background(
                                            Capsule().fill(isSolved ? BrillyPalette.brillyTeal : Color.white.opacity(0.10))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Daily Coach")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if !initialized {
                    frozenSteps = buildInitialSteps()
                    initialized = true
                    loadCurrentStep()
                }
            }
        }
    }

    private func loadCurrentStep() {
        guard stepIndex < frozenSteps.count else { return }
        let cur = frozenSteps[stepIndex]
        board = (try? ChessBoard(fen: cur.fen)) ?? ChessBoard()
        if let opp = cur.opponentLastMove {
            lastMove = (opp.from, opp.to)
            statusMessage = "Opponent just played \(opp.san). Play \(cur.orientation.displayName)'s reply."
        } else {
            lastMove = nil
            statusMessage = "Play \(cur.orientation.displayName)'s move on the board."
        }
        isSolved = false
        hadMistakeOnCurrent = false
        hintLevel = 0
        solvedBadge = nil
        shownAt = Date()
    }

    private func triggerHint(for step: DrillStep) {
        guard !isSolved else { return }
        guard let legal = DailyCoachPlanner.legalMove(uci: step.expectedUci, on: board) else { return }
        if hintLevel == 0 {
            hintLevel = 1
            let pieceName = board[legal.from]?.type.displayName ?? "piece"
            statusMessage = "Hint: Look at your \(pieceName) on \(legal.from.algebraic)!"
            store.triggerHaptic(.move)
        } else if hintLevel == 1 {
            hintLevel = 2
            statusMessage = "Arrow revealed: play \(step.expectedSan) (\(legal.from.algebraic) → \(legal.to.algebraic))."
            store.triggerHaptic(.move)
        }
    }

    private func handleMove(_ move: ChessMove, for step: DrillStep) {
        guard !isSolved else { return }
        let elapsedMs = Int(Date().timeIntervalSince(shownAt) * 1000.0)
        let usedAnyHint = hintLevel > 0
        if move.uci == step.expectedUci {
            if let _ = try? board.apply(move) {
                lastMove = (move.from, move.to)
            }
            isSolved = true
            hintLevel = 0
            solvedBadge = MoveBadgeOverlay(square: move.to, classification: .best)
            store.recordTrainingActivity()
            if !hadMistakeOnCurrent {
                cleanSolveCount += 1
                if let cardId = step.cardId {
                    let res = store.recordOpeningAttempt(
                        cardId: cardId,
                        attempt: OpeningAttemptInput(correct: true, responseMs: elapsedMs, hintUsed: usedAnyHint)
                    )
                    statusMessage = "Spot on (\(step.expectedSan)) · FSRS rated \(res?.rating.label ?? "Good")!"
                } else {
                    store.triggerHaptic(.success)
                    statusMessage = "Spot on! \(step.expectedSan) is the top move."
                }
            } else {
                // Already recorded FSRS lapse on first miss — don't double-grade!
                store.triggerHaptic(.success)
                statusMessage = "Got it (\(step.expectedSan))! Scheduled soon for spaced reinforcement."
            }
        } else {
            // Check SAN of attempted move so we can give clear feedback & surface any known wrongMoveTrap!
            var temp = board
            let playedSan = (try? temp.apply(move).san) ?? move.uci
            let trapMatch = step.wrongMoveTraps.first { $0.playedSan == playedSan }

            if !hadMistakeOnCurrent {
                hadMistakeOnCurrent = true
                if let cardId = step.cardId {
                    _ = store.recordOpeningAttempt(
                        cardId: cardId,
                        attempt: OpeningAttemptInput(correct: false, responseMs: elapsedMs, hintUsed: usedAnyHint)
                    )
                } else {
                    store.triggerHaptic(.error)
                }
            } else {
                store.triggerHaptic(.error)
            }
            if let trap = trapMatch {
                statusMessage = "Trap (\(playedSan)): \(trap.reason)"
            } else {
                statusMessage = "Played \(playedSan) — not the target move here. Try again or tap Hint."
            }
        }
    }

    private func advanceStep() {
        withAnimation(.snappy(duration: 0.22)) {
            stepIndex += 1
            loadCurrentStep()
        }
    }

    private func validatedHintHighlight(for uci: String, on currentBoard: ChessBoard) -> [SquareHighlight] {
        guard let legal = DailyCoachPlanner.legalMove(uci: uci, on: currentBoard) else { return [] }
        return [SquareHighlight(square: legal.from.algebraic, color: .plan)]
    }

    private func validatedHintArrow(for uci: String, on currentBoard: ChessBoard) -> [BoardArrow] {
        guard let legal = DailyCoachPlanner.legalMove(uci: uci, on: currentBoard) else { return [] }
        return [BoardArrow(from: legal.from.algebraic, to: legal.to.algebraic, color: .best)]
    }
}

// MARK: - 60-Second Gravity Check Sheet

private struct GravityCheckSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var items: [GravityFlashItem] = []
    @State private var initialized: Bool = false
    @State private var index: Int = 0
    @State private var board: ChessBoard = ChessBoard()
    @State private var lastMove: (from: Square, to: Square)? = nil
    @State private var score: Int = 0
    @State private var feedback: String = ""
    @State private var lastWasHit: Bool? = nil
    @State private var awaitingNext: Bool = false
    @State private var finished: Bool = false
    @State private var remainingSec: Int = 60
    @State private var itemShownAt: Date = Date()
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var advanceTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                if initialized && (finished || items.isEmpty) {
                    VStack(spacing: 16) {
                        Text("\(score) / \(max(1, items.count))")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        Text(score == items.count && !items.isEmpty ? "Locked In — Ready to Queue!" : (remainingSec == 0 ? "Time's Up — Nice Warmup!" : "Warmed Up & Sharp!"))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Button("Done") { dismiss() }
                            .font(.headline)
                            .foregroundStyle(BrillyPalette.voidBg)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(BrillyPalette.brillyTeal))
                            .buttonStyle(.plain)
                    }
                    .padding(28)
                    .brillySurface(store.surfaceStyle, cornerRadius: 24)
                    .padding()
                } else if initialized && index < items.count {
                    let cur = items[index]
                    ScrollView {
                        VStack(spacing: 14) {
                            HStack {
                                Text(cur.subtitle)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.warpPurple)
                                Spacer()
                                Label("\(remainingSec)s", systemImage: "timer")
                                    .font(.caption.monospacedDigit().weight(.black))
                                    .foregroundStyle(remainingSec <= 10 ? BrillyPalette.blunderRose : BrillyPalette.goldAmber)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                                Text("\(index + 1) / \(items.count)")
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                            }

                            InteractiveChessBoardView(
                                board: board,
                                orientation: cur.orientation,
                                theme: store.boardTheme,
                                surfaceStyle: store.surfaceStyle,
                                interactive: !awaitingNext,
                                lastMove: lastMove
                            ) { move in
                                handleFlashMove(move, item: cur)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(cur.prompt)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                if !feedback.isEmpty {
                                    Text(feedback)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(lastWasHit == true ? BrillyPalette.brillyTeal : BrillyPalette.blunderRose)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .brillySurface(store.surfaceStyle, cornerRadius: 16)

                            if awaitingNext {
                                Button("Continue") {
                                    advanceTask?.cancel()
                                    moveToNextItem()
                                }
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(BrillyPalette.voidBg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Capsule().fill(BrillyPalette.brillyTeal))
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle(store.copy(cosmic: "Gravity Check", classic: "60s Warmup"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if !initialized {
                    items = DailyCoachPlanner.buildGravityCheckFlashes(
                        fsrsCards: store.dailyEligibleFsrsCards,
                        mistakeDeck: store.mistakeDeck
                    )
                    initialized = true
                    loadItem(at: 0)
                    startCountdown()
                }
            }
            .onDisappear {
                timerTask?.cancel()
                advanceTask?.cancel()
            }
        }
    }

    private func loadItem(at idx: Int) {
        guard idx < items.count else {
            finishSession()
            return
        }
        let item = items[idx]
        board = (try? ChessBoard(fen: item.fen)) ?? ChessBoard()
        lastMove = nil
        feedback = ""
        lastWasHit = nil
        awaitingNext = false
        itemShownAt = Date()
    }

    private func handleFlashMove(_ move: ChessMove, item: GravityFlashItem) {
        guard !awaitingNext else { return }
        let elapsedMs = max(200, Int(Date().timeIntervalSince(itemShownAt) * 1000.0))
        let hit = move.uci == item.expectedUci
        if let _ = try? board.apply(move) {
            lastMove = (move.from, move.to)
        }
        lastWasHit = hit
        awaitingNext = true

        if hit {
            score += 1
            store.triggerHaptic(.success)
            feedback = "Direct hit: \(item.expectedSan)!"
        } else {
            store.triggerHaptic(.error)
            feedback = "Best was \(item.expectedSan)."
        }

        if let cardId = item.cardId {
            _ = store.recordOpeningAttempt(
                cardId: cardId,
                attempt: OpeningAttemptInput(correct: hit, responseMs: elapsedMs)
            )
        }

        advanceTask?.cancel()
        advanceTask = Task {
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled else { return }
            moveToNextItem()
        }
    }

    private func moveToNextItem() {
        if index + 1 < items.count {
            index += 1
            loadItem(at: index)
        } else {
            finishSession()
        }
    }

    private func startCountdown() {
        timerTask?.cancel()
        remainingSec = 60
        timerTask = Task {
            while !Task.isCancelled && remainingSec > 0 && !finished {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled || finished { break }
                remainingSec -= 1
                if remainingSec <= 0 {
                    finishSession()
                }
            }
        }
    }

    private func finishSession() {
        timerTask?.cancel()
        advanceTask?.cancel()
        if score > 0 {
            store.recordTrainingActivity()
        }
        finished = true
    }
}

// MARK: - Daily FSRS Opening Selector Sheet

public struct DailyOpeningsPickerSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        let whiteCourses = store.allCourses.filter { $0.side == .white }
        let blackCourses = store.allCourses.filter { $0.side == .black }

        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Choose which openings appear in your Daily Orbit Coach & 60s Gravity Check so you only drill lines you actually play.")
                                .font(.caption)
                                .foregroundStyle(BrillyPalette.inkSecondary)

                            HStack(spacing: 8) {
                                quickPresetButton("Practiced Only") {
                                    let practiced = Set(store.fsrsCards.filter { $0.attempts > 0 }.map(\.courseId))
                                    let imported = Set(store.allCourses.filter { $0.source == "pgn" || $0.source == "lichess-study" }.map(\.id))
                                    store.setDailyOpenings(practiced.union(imported))
                                }
                                quickPresetButton("All Openings") {
                                    store.setDailyOpenings(Set(store.allCourses.map(\.id)))
                                }
                                quickPresetButton("Clear") {
                                    store.setDailyOpenings([])
                                }
                            }
                        }
                        .padding(14)
                        .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.brillyTeal)

                        courseSection(title: "WHITE REPERTOIRE", courses: whiteCourses)
                        courseSection(title: "BLACK REPERTOIRE", courses: blackCourses)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Daily FSRS Openings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func courseSection(title: String, courses: [OpeningCourse]) -> some View {
        if !courses.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(BrillyPalette.brillyTeal)
                    .padding(.horizontal, 4)

                ForEach(courses) { course in
                    let isOn = store.isCourseInDaily(course.id)
                    let cards = store.fsrsCards.filter { $0.courseId == course.id }
                    let due = cards.filter { FSRS6Scheduler.isCardDue($0) }.count
                    let practiced = cards.filter { $0.attempts > 0 }.count

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            store.toggleCourseInDaily(course.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isOn ? BrillyPalette.brillyTeal : BrillyPalette.inkSecondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                Text(practiced > 0
                                    ? "\(practiced) practiced · \(due) due"
                                    : "\(course.lines.count) lines · not practiced yet"
                                )
                                .font(.caption2)
                                .foregroundStyle(BrillyPalette.inkSecondary)
                            }
                            Spacer()
                            Text(isOn ? "Active" : "Off")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(isOn ? BrillyPalette.voidBg : BrillyPalette.inkSecondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(isOn ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
                        }
                        .padding(12)
                        .brillySurface(store.surfaceStyle, cornerRadius: 16, tint: isOn ? BrillyPalette.brillyTeal : nil)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func quickPresetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.caption2.weight(.bold))
            .foregroundStyle(BrillyPalette.inkPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .buttonStyle(.plain)
    }
}
