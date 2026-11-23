import SwiftUI
import BrillyDerCore

public struct TrainTabView: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var showingDailySession = false
    @State private var showingGravityCheck = false

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
                                cosmic: "Cosmic Stockfish probe & opening coach",
                                classic: "On-device Stockfish chess coach"
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
                .padding(.bottom, 84)
            }
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
                Label("\(store.dueOpeningCount) due", systemImage: "brain.head.profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.brillyTeal)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
            }

            // Duration Picker (10m | 15m | 25m)
            HStack(spacing: 8) {
                ForEach(DailyDurationMinutes.allCases) { dur in
                    let selected = store.dailyDuration == dur
                    Button {
                        withAnimation(.snappy) {
                            store.dailyDuration = dur
                        }
                    } label: {
                        Text(dur.label)
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

            // 4-Stage Summary Grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                stageChip(
                    title: "1. Openings",
                    value: "\(plan.stage1OpeningCards.count) FSRS",
                    icon: "book.fill",
                    tint: BrillyPalette.brillyTeal
                )
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

        // MARK: - 3. Quick Status Row
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
            statCard(
                label: "Bookmarks",
                value: "\(store.bookmarks.count)",
                tint: BrillyPalette.goldAmber
            )
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
        let stageTitle: String
        let fen: String
        let orientation: PieceColor
        let expectedUci: String
        let expectedSan: String
        let prompt: String
        let cardId: String?
    }

    @State private var frozenSteps: [DrillStep] = []
    @State private var initialized: Bool = false
    @State private var stepIndex: Int = 0
    @State private var board: ChessBoard = ChessBoard()
    @State private var statusMessage: String = "Find the strongest repertoire or tactical move."
    @State private var isSolved: Bool = false
    @State private var hadMistakeOnCurrent: Bool = false
    @State private var usedHint: Bool = false
    @State private var shownAt: Date = Date()
    @State private var cleanSolveCount: Int = 0
    @State private var lastMove: (from: Square, to: Square)? = nil

    private func buildInitialSteps() -> [DrillStep] {
        let courseNames = Dictionary(store.allCourses.map { ($0.id, $0.name) }, uniquingKeysWith: { _, latest in latest })
        var out: [DrillStep] = []

        for c in plan.stage1OpeningCards {
            let fenBoard = try? ChessBoard(fen: c.fen)
            let sideToMove = fenBoard?.turn ?? c.side.pieceColor
            let courseName = courseNames[c.courseId] ?? "Opening"
            out.append(DrillStep(
                id: "s1_\(c.cardId)",
                stageTitle: "Stage 1 · \(courseName) (\(sideToMove.displayName))",
                fen: c.fen,
                orientation: sideToMove,
                expectedUci: c.expectedUci,
                expectedSan: c.expectedSan,
                prompt: "\(sideToMove.displayName) to move (Move \(c.ply / 2 + 1)) — recall your \(courseName) move.",
                cardId: c.cardId
            ))
        }
        for p in plan.stage2Blunders {
            let sideToMove = (try? ChessBoard(fen: p.fen))?.turn ?? p.playerColor
            out.append(DrillStep(
                id: "s2_\(p.id)",
                stageTitle: "Stage 2 · Blunder Rewind (\(sideToMove.displayName))",
                fen: p.fen,
                orientation: sideToMove,
                expectedUci: p.bestMoveUci,
                expectedSan: p.bestMoveSan,
                prompt: "You played \(p.playedSan) vs \(p.opponentName). Find the better move!",
                cardId: nil
            ))
        }
        for p in plan.stage3SpeedDrills {
            let sideToMove = (try? ChessBoard(fen: p.fen))?.turn ?? p.playerColor
            out.append(DrillStep(
                id: "s3_\(p.id)",
                stageTitle: "Stage 3 · Pattern Sprint (\(sideToMove.displayName))",
                fen: p.fen,
                orientation: sideToMove,
                expectedUci: p.bestMoveUci,
                expectedSan: p.bestMoveSan,
                prompt: p.headline,
                cardId: nil
            ))
        }
        for p in plan.stage4Drills {
            let sideToMove = (try? ChessBoard(fen: p.fen))?.turn ?? p.playerColor
            out.append(DrillStep(
                id: "s4_\(p.id)",
                stageTitle: "Stage 4 · \(plan.stage4FocusLabel) (\(sideToMove.displayName))",
                fen: p.fen,
                orientation: sideToMove,
                expectedUci: p.bestMoveUci,
                expectedSan: p.bestMoveSan,
                prompt: p.headline,
                cardId: nil
            ))
        }
        if out.isEmpty {
            for fb in DailyCoachPlanner.fallbackGravityFlashes {
                let sideToMove = (try? ChessBoard(fen: fb.fen))?.turn ?? fb.orientation
                out.append(DrillStep(
                    id: fb.id,
                    stageTitle: "Tactical Warmup (\(sideToMove.displayName))",
                    fen: fb.fen,
                    orientation: sideToMove,
                    expectedUci: fb.expectedUci,
                    expectedSan: fb.expectedSan,
                    prompt: fb.prompt,
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
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        Text(store.copy(cosmic: "Orbit Complete!", classic: "Daily Session Complete!"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Text("Solved \(cleanSolveCount) / \(frozenSteps.count) positions on first try.")
                            .foregroundStyle(BrillyPalette.inkSecondary)
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
                    ScrollView {
                        VStack(spacing: 14) {
                            HStack {
                                Text(current.stageTitle)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(stepIndex + 1) / \(frozenSteps.count)")
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                            }

                            TractorBeamProgressBar(
                                progress: Double(stepIndex + (isSolved ? 1 : 0)) / Double(max(1, frozenSteps.count)),
                                height: 9
                            )

                            InteractiveChessBoardView(
                                board: board,
                                orientation: current.orientation,
                                theme: store.boardTheme,
                                surfaceStyle: store.surfaceStyle,
                                interactive: !isSolved,
                                lastMove: lastMove,
                                arrows: (usedHint && !isSolved) ? hintArrows(for: current.expectedUci) : []
                            ) { move in
                                handleMove(move, for: current)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text(current.prompt)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                Text(statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(isSolved ? BrillyPalette.brillyTeal : (hadMistakeOnCurrent ? BrillyPalette.blunderRose : BrillyPalette.inkSecondary))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .brillySurface(store.surfaceStyle, cornerRadius: 16)

                            HStack(spacing: 10) {
                                Button {
                                    usedHint = true
                                    statusMessage = "Hint: Look closely at \(current.expectedSan.prefix(2))…"
                                } label: {
                                    Label("Hint", systemImage: "lightbulb.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BrillyPalette.goldAmber)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 11)
                                        .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                                }
                                .buttonStyle(.plain)
                                .disabled(isSolved)

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
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Daily Coach")
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
        lastMove = nil
        isSolved = false
        hadMistakeOnCurrent = false
        usedHint = false
        shownAt = Date()
        statusMessage = "Play \(cur.orientation.displayName)'s move on the board."
    }

    private func handleMove(_ move: ChessMove, for step: DrillStep) {
        let elapsedMs = Int(Date().timeIntervalSince(shownAt) * 1000.0)
        if move.uci == step.expectedUci {
            if let _ = try? board.apply(move) {
                lastMove = (move.from, move.to)
            }
            isSolved = true
            if !hadMistakeOnCurrent {
                cleanSolveCount += 1
                if let cardId = step.cardId {
                    let res = store.recordOpeningAttempt(
                        cardId: cardId,
                        attempt: OpeningAttemptInput(correct: true, responseMs: elapsedMs, hintUsed: usedHint)
                    )
                    statusMessage = "Spot on (\(step.expectedSan)) · FSRS rated \(res?.rating.label ?? "Good")!"
                } else {
                    store.triggerHaptic(.success)
                    statusMessage = "Spot on! \(step.expectedSan) is the engine's top move."
                }
            } else {
                // Already recorded FSRS lapse on first miss — don't double-grade!
                store.triggerHaptic(.success)
                statusMessage = "Got it (\(step.expectedSan))! Scheduled soon for spaced reinforcement."
            }
        } else {
            if !hadMistakeOnCurrent {
                hadMistakeOnCurrent = true
                if let cardId = step.cardId {
                    _ = store.recordOpeningAttempt(
                        cardId: cardId,
                        attempt: OpeningAttemptInput(correct: false, responseMs: elapsedMs, hintUsed: usedHint)
                    )
                } else {
                    store.triggerHaptic(.error)
                }
            } else {
                store.triggerHaptic(.error)
            }
            statusMessage = "Not quite — try again, or tap Hint for a nudge."
        }
    }

    private func advanceStep() {
        stepIndex += 1
        loadCurrentStep()
    }

    private func hintArrows(for uci: String) -> [BoardArrow] {
        guard let m = ChessMove(uci: uci) else { return [] }
        return [BoardArrow(from: m.from.algebraic, to: m.to.algebraic, color: .best)]
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                if !initialized {
                    items = DailyCoachPlanner.buildGravityCheckFlashes(
                        fsrsCards: store.fsrsCards,
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
        finished = true
    }
}
