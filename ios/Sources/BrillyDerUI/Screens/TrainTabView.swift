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
                    // Clean Daily-First Mode Strip (15m Coach default; Woodpecker / Convert / Mistakes / Labs one tap away)
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
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(store.copy(cosmic: "BrillyDer", classic: "Train"))
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
        // MARK: - 1. Daily-First 15m Coach Hero
        VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.copy(cosmic: "DAILY FLIGHT PLAN", classic: "DAILY IMPROVEMENT PLAN"))
                                    .font(.caption.weight(.bold))
                                    .tracking(1.1)
                                    .foregroundStyle(BrillyPalette.brillyTeal)

                                Text(store.copy(cosmic: "15-Minute Orbit Coach", classic: "Daily Guided Coach"))
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
                                value: plan.stage4FocusLabel,
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

                    // MARK: - 3. Quick Status Row (Tucked Cleanly Below Hero)
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

    @State private var stepIndex: Int = 0
    @State private var board: ChessBoard = ChessBoard()
    @State private var statusMessage: String = "Find the strongest repertoire or tactical move."
    @State private var isSolved: Bool = false
    @State private var usedHint: Bool = false
    @State private var shownAt: Date = Date()
    @State private var correctCount: Int = 0
    @State private var lastMove: (from: Square, to: Square)? = nil

    private var steps: [DrillStep] {
        var out: [DrillStep] = []
        for c in plan.stage1OpeningCards {
            out.append(DrillStep(
                id: "s1_\(c.cardId)",
                stageTitle: "Stage 1 · Opening Recall",
                fen: c.fen,
                orientation: c.side.pieceColor,
                expectedUci: c.expectedUci,
                expectedSan: c.expectedSan,
                prompt: "Move \(c.ply / 2 + 1) — recall your course move.",
                cardId: c.cardId
            ))
        }
        for p in plan.stage2Blunders {
            out.append(DrillStep(
                id: "s2_\(p.id)",
                stageTitle: "Stage 2 · Blunder Rewind",
                fen: p.fen,
                orientation: p.playerColor,
                expectedUci: p.bestMoveUci,
                expectedSan: p.bestMoveSan,
                prompt: "You played \(p.playedSan) vs \(p.opponentName). Find the better move!",
                cardId: nil
            ))
        }
        for p in plan.stage3SpeedDrills {
            out.append(DrillStep(
                id: "s3_\(p.id)",
                stageTitle: "Stage 3 · Pattern Sprint",
                fen: p.fen,
                orientation: p.playerColor,
                expectedUci: p.bestMoveUci,
                expectedSan: p.bestMoveSan,
                prompt: p.headline,
                cardId: nil
            ))
        }
        if out.isEmpty {
            for fb in DailyCoachPlanner.fallbackGravityFlashes {
                out.append(DrillStep(
                    id: fb.id,
                    stageTitle: "Tactical Warmup",
                    fen: fb.fen,
                    orientation: fb.orientation,
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

                if stepIndex >= steps.count {
                    VStack(spacing: 18) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        Text(store.copy(cosmic: "Orbit Complete!", classic: "Daily Session Complete!"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Text("Solved \(correctCount) / \(steps.count) positions cleanly.")
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
                } else {
                    let current = steps[stepIndex]
                    VStack(spacing: 14) {
                        HStack {
                            Text(current.stageTitle)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                            Spacer()
                            Text("\(stepIndex + 1) / \(steps.count)")
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(BrillyPalette.inkSecondary)
                        }

                        ProgressView(value: Double(stepIndex), total: Double(max(1, steps.count)))
                            .tint(BrillyPalette.brillyTeal)

                        InteractiveChessBoardView(
                            board: board,
                            orientation: current.orientation,
                            theme: store.boardTheme,
                            surfaceStyle: store.surfaceStyle,
                            interactive: !isSolved,
                            lastMove: lastMove,
                            arrows: usedHint ? hintArrows(for: current.expectedUci) : []
                        ) { move in
                            handleMove(move, for: current)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(current.prompt)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(isSolved ? BrillyPalette.brillyTeal : BrillyPalette.inkSecondary)
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
                    .onAppear { loadCurrentStep() }
                }
            }
            .navigationTitle("Daily Coach")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func loadCurrentStep() {
        guard stepIndex < steps.count else { return }
        let cur = steps[stepIndex]
        board = (try? ChessBoard(fen: cur.fen)) ?? ChessBoard()
        lastMove = nil
        isSolved = false
        usedHint = false
        shownAt = Date()
        statusMessage = "Play your move on the board."
    }

    private func handleMove(_ move: ChessMove, for step: DrillStep) {
        let elapsedMs = Int(Date().timeIntervalSince(shownAt) * 1000.0)
        if move.uci == step.expectedUci {
            if let _ = try? board.apply(move) {
                lastMove = (move.from, move.to)
            }
            isSolved = true
            correctCount += 1
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
            if let cardId = step.cardId {
                _ = store.recordOpeningAttempt(
                    cardId: cardId,
                    attempt: OpeningAttemptInput(correct: false, responseMs: elapsedMs, hintUsed: usedHint)
                )
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
    @State private var index: Int = 0
    @State private var board: ChessBoard = ChessBoard()
    @State private var score: Int = 0
    @State private var feedback: String = ""
    @State private var finished: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                if finished || items.isEmpty {
                    VStack(spacing: 16) {
                        Text("\(score) / \(max(1, items.count))")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        Text(score == items.count ? "Locked In — Ready to Queue!" : "Warmed Up & Sharp!")
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
                } else {
                    let cur = items[index]
                    VStack(spacing: 14) {
                        HStack {
                            Text(cur.subtitle)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.warpPurple)
                            Spacer()
                            Text("Flash \(index + 1) / \(items.count)")
                                .font(.caption.monospacedDigit().weight(.bold))
                                .foregroundStyle(BrillyPalette.inkSecondary)
                        }

                        InteractiveChessBoardView(
                            board: board,
                            orientation: cur.orientation,
                            theme: store.boardTheme,
                            surfaceStyle: store.surfaceStyle
                        ) { move in
                            let hit = move.uci == cur.expectedUci
                            if hit {
                                score += 1
                                store.triggerHaptic(.success)
                                feedback = "Direct hit: \(cur.expectedSan)!"
                            } else {
                                store.triggerHaptic(.error)
                                feedback = "Best was \(cur.expectedSan)."
                            }
                            if let cardId = cur.cardId {
                                _ = store.recordOpeningAttempt(
                                    cardId: cardId,
                                    attempt: OpeningAttemptInput(correct: hit, responseMs: 3200)
                                )
                            }
                            if index + 1 < items.count {
                                index += 1
                                board = (try? ChessBoard(fen: items[index].fen)) ?? ChessBoard()
                            } else {
                                finished = true
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(cur.prompt)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            if !feedback.isEmpty {
                                Text(feedback)
                                    .font(.caption)
                                    .foregroundStyle(BrillyPalette.brillyTeal)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .brillySurface(store.surfaceStyle, cornerRadius: 16)
                    }
                    .padding(16)
                }
            }
            .navigationTitle(store.copy(cosmic: "Gravity Check", classic: "60s Warmup"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                items = DailyCoachPlanner.buildGravityCheckFlashes(
                    fsrsCards: store.fsrsCards,
                    mistakeDeck: store.mistakeDeck
                )
                if let first = items.first {
                    board = (try? ChessBoard(fen: first.fen)) ?? ChessBoard()
                }
            }
        }
    }
}
