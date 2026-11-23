import SwiftUI
import BrillyDerCore

public struct OpeningsTabView: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var sideFilter: RepertoireSide = .white
    @State private var selectedCourse: OpeningCourse? = nil

    private var courses: [OpeningCourse] {
        store.allCourses.filter { $0.side == sideFilter }
    }

    public var body: some View {
        ZStack {
            CosmicVoidBackdrop(style: store.surfaceStyle)

            ScrollView {
                VStack(spacing: 14) {
                    Picker("Side", selection: $sideFilter) {
                        Text("White Repertoire").tag(RepertoireSide.white)
                        Text("Black Repertoire").tag(RepertoireSide.black)
                    }
                    .pickerStyle(.segmented)

                    LazyVStack(spacing: 12) {
                        ForEach(courses) { course in
                            courseCard(course)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Openings")
        .sheet(item: $selectedCourse) { course in
            CourseDetailSheet(course: course)
                .environment(store)
        }
    }

    private func courseCard(_ course: OpeningCourse) -> some View {
        let courseCards = store.fsrsCards.filter { $0.courseId == course.id }
        let dueCount = courseCards.filter { FSRS6Scheduler.isCardDue($0) }.count
        let reviewed = courseCards.filter { $0.attempts > 0 }
        let avgRecall = reviewed.isEmpty
            ? 0
            : reviewed.map { FSRS6Scheduler.recallProbability(for: $0) }.reduce(0, +) / reviewed.count

        return Button {
            selectedCourse = course
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.copy(cosmic: course.codename.uppercased(), classic: course.difficulty.uppercased()))
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        Text(course.name)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                    }
                    Spacer()
                    if dueCount > 0 {
                        Text("\(dueCount) due")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BrillyPalette.voidBg)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(BrillyPalette.brillyTeal))
                    } else {
                        Text("\(course.lines.count) lines")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BrillyPalette.inkSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                }

                Text(course.tagline)
                    .font(.caption)
                    .foregroundStyle(BrillyPalette.inkSecondary)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    ProgressView(value: Double(avgRecall), total: 100.0)
                        .tint(BrillyPalette.brillyTeal)
                    Text("\(avgRecall)% recall")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }
            }
            .padding(16)
            .brillySurface(store.surfaceStyle, cornerRadius: 20, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Course Detail Sheet (Mothership + Walkthrough + FSRS Drill)

private struct CourseDetailSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let course: OpeningCourse

    enum CourseTab: String, CaseIterable {
        case setup = "Setup"
        case walkthrough = "Walkthrough"
        case drill = "FSRS Drill"
    }

    @State private var activeTab: CourseTab = .setup
    @State private var selectedLineIndex: Int = 0

    // Walkthrough state
    @State private var walkStep: Int = 0
    @State private var isAutoPlaying: Bool = false

    // Drill state
    @State private var drillCards: [FsrsOpeningCard] = []
    @State private var drillIdx: Int = 0
    @State private var drillBoard: ChessBoard = ChessBoard()
    @State private var drillShownAt: Date = Date()
    @State private var drillUsedHint: Bool = false
    @State private var drillFeedback: String = "Play your repertoire move on the board."
    @State private var drillSolved: Bool = false

    private var currentLine: OpeningLine {
        course.lines[min(selectedLineIndex, max(0, course.lines.count - 1))]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollView {
                    VStack(spacing: 14) {
                        Picker("Mode", selection: $activeTab) {
                            ForEach(CourseTab.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch activeTab {
                        case .setup:
                            mothershipView
                        case .walkthrough:
                            walkthroughView
                        case .drill:
                            drillView
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(course.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isAutoPlaying = false
                        dismiss()
                    }
                }
            }
            .onChange(of: activeTab) { _, newTab in
                isAutoPlaying = false
                if newTab == .drill {
                    prepareDrill()
                }
            }
            .task(id: isAutoPlaying) {
                guard isAutoPlaying else { return }
                while !Task.isCancelled && isAutoPlaying {
                    try? await Task.sleep(for: .milliseconds(1200))
                    guard !Task.isCancelled, isAutoPlaying else { break }
                    if walkStep < currentLine.moves.count {
                        walkStep += 1
                    } else {
                        isAutoPlaying = false
                    }
                }
            }
        }
    }

    // MARK: - 1. Mothership Setup

    private var mothershipView: some View {
        let board = boardAfter(moves: course.mothershipSetup.previewMoves)
        return VStack(alignment: .leading, spacing: 14) {
            InteractiveChessBoardView(
                board: board,
                orientation: course.side.pieceColor,
                theme: store.boardTheme,
                surfaceStyle: store.surfaceStyle,
                interactive: false,
                arrows: course.mothershipSetup.arrows,
                highlights: course.mothershipSetup.highlights
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(store.copy(cosmic: "Mothership Core Plans", classic: "Core Strategic Plans"))
                    .font(.headline)
                    .foregroundStyle(BrillyPalette.brillyTeal)
                ForEach(course.mothershipSetup.corePlans, id: \.self) { plan in
                    Label(plan, systemImage: "sparkle")
                        .font(.subheadline)
                        .foregroundStyle(BrillyPalette.inkPrimary)
                }
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)

            VStack(alignment: .leading, spacing: 8) {
                Text("Golden Rules")
                    .font(.headline)
                    .foregroundStyle(BrillyPalette.goldAmber)
                ForEach(course.mothershipSetup.goldenRules, id: \.self) { rule in
                    Label(rule, systemImage: "shield.checkered")
                        .font(.subheadline)
                        .foregroundStyle(BrillyPalette.inkPrimary)
                }
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)
        }
    }

    // MARK: - 2. Guided Walkthrough (with Play/Pause Auto-Step)

    private var walkthroughView: some View {
        let clampedStep = max(0, min(walkStep, currentLine.moves.count))
        let prefix = Array(currentLine.moves.prefix(clampedStep))
        let board = boardAfter(moves: prefix)
        let activeAnnotation = currentLine.annotations.first { $0.ply == clampedStep - 1 }

        return VStack(spacing: 12) {
            // Line Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(course.lines.enumerated()), id: \.element.id) { idx, line in
                        let sel = idx == selectedLineIndex
                        Button {
                            selectedLineIndex = idx
                            walkStep = 0
                            isAutoPlaying = false
                        } label: {
                            Text("\(line.eco) · \(line.title)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(sel ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(sel ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            InteractiveChessBoardView(
                board: board,
                orientation: course.side.pieceColor,
                theme: store.boardTheme,
                surfaceStyle: store.surfaceStyle,
                interactive: false,
                arrows: activeAnnotation?.arrows ?? [],
                highlights: activeAnnotation?.highlights ?? []
            )

            // Play/Pause + Step Transport
            BrillyGlassCluster(style: store.surfaceStyle, spacing: 10) {
                HStack(spacing: 10) {
                    walkBtn("backward.end.fill") { isAutoPlaying = false; walkStep = 0 }
                    walkBtn("chevron.left") { isAutoPlaying = false; walkStep = max(0, clampedStep - 1) }
                    walkBtn(isAutoPlaying ? "pause.fill" : "play.fill") {
                        if clampedStep >= currentLine.moves.count { walkStep = 0 }
                        isAutoPlaying.toggle()
                    }
                    walkBtn("chevron.right") { isAutoPlaying = false; walkStep = min(currentLine.moves.count, clampedStep + 1) }
                    walkBtn("forward.end.fill") { isAutoPlaying = false; walkStep = currentLine.moves.count }
                }
            }

            // Live Coaching Callout
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(clampedStep == 0 ? currentLine.title : "Move \((clampedStep + 1) / 2): \(currentLine.moves[clampedStep - 1])")
                        .font(.headline)
                        .foregroundStyle(BrillyPalette.inkPrimary)
                    Spacer()
                    Text("\(clampedStep) / \(currentLine.moves.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }
                Text(activeAnnotation?.plan ?? currentLine.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(BrillyPalette.inkSecondary)
                if store.vibeMode == .cosmic, let cue = activeAnnotation?.cosmicCue {
                    Text(cue)
                        .font(.caption.italic())
                        .foregroundStyle(BrillyPalette.brillyTeal)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)

            Button {
                store.unlockLine(courseId: course.id, lineId: currentLine.id)
                activeTab = .drill
            } label: {
                Label("Unlock & Drill This Line", systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(BrillyPalette.voidBg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(BrillyPalette.brillyTeal))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 3. FSRS Signal Strength Drill

    private var drillView: some View {
        VStack(spacing: 12) {
            if drillCards.isEmpty {
                Text("No drill cards available for this line.")
                    .foregroundStyle(BrillyPalette.inkSecondary)
            } else {
                let card = drillCards[min(drillIdx, drillCards.count - 1)]
                HStack {
                    Text("Card \(drillIdx + 1) / \(drillCards.count)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                    Spacer()
                    Text("Recall \(FSRS6Scheduler.recallProbability(for: card))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }

                InteractiveChessBoardView(
                    board: drillBoard,
                    orientation: course.side.pieceColor,
                    theme: store.boardTheme,
                    surfaceStyle: store.surfaceStyle,
                    interactive: !drillSolved,
                    arrows: drillUsedHint ? arrowFor(uci: card.expectedUci) : []
                ) { move in
                    let elapsedMs = Int(Date().timeIntervalSince(drillShownAt) * 1000.0)
                    let hit = move.uci == card.expectedUci
                    let result = store.recordOpeningAttempt(
                        cardId: card.cardId,
                        attempt: OpeningAttemptInput(correct: hit, responseMs: elapsedMs, hintUsed: drillUsedHint)
                    )
                    if hit {
                        _ = try? drillBoard.apply(move)
                        drillSolved = true
                        drillFeedback = "Locked in \(card.expectedSan)! FSRS graded \(result?.rating.label ?? "Good")."
                    } else {
                        drillFeedback = "Expected a different course move (FSRS graded Again). Try again or tap Hint."
                    }
                }

                Text(drillFeedback)
                    .font(.subheadline)
                    .foregroundStyle(drillSolved ? BrillyPalette.brillyTeal : BrillyPalette.inkPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .brillySurface(store.surfaceStyle, cornerRadius: 16)

                HStack(spacing: 10) {
                    Button {
                        drillUsedHint = true
                    } label: {
                        Label("Hint", systemImage: "lightbulb.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrillyPalette.goldAmber)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                    }
                    .buttonStyle(.plain)

                    Button {
                        drillIdx = (drillIdx + 1) % drillCards.count
                        loadDrillCard()
                    } label: {
                        Text(drillSolved ? "Next Card" : "Skip")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(drillSolved ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(drillSolved ? BrillyPalette.brillyTeal : Color.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func prepareDrill() {
        store.unlockLine(courseId: course.id, lineId: currentLine.id)
        drillCards = store.fsrsCards
            .filter { $0.courseId == course.id && $0.lineId == currentLine.id }
            .sorted { $0.ply < $1.ply }
        drillIdx = 0
        loadDrillCard()
    }

    private func loadDrillCard() {
        guard drillIdx < drillCards.count else { return }
        let card = drillCards[drillIdx]
        drillBoard = (try? ChessBoard(fen: card.fen)) ?? ChessBoard()
        drillShownAt = Date()
        drillUsedHint = false
        drillSolved = false
        drillFeedback = "Move \(card.ply / 2 + 1) — play the repertoire move!"
    }

    private func boardAfter(moves: [String]) -> ChessBoard {
        var b = ChessBoard()
        for m in moves {
            guard (try? b.apply(san: m)) != nil else { break }
        }
        return b
    }

    private func arrowFor(uci: String) -> [BoardArrow] {
        guard let m = ChessMove(uci: uci) else { return [] }
        return [BoardArrow(from: m.from.algebraic, to: m.to.algebraic, color: .best)]
    }

    private func walkBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button {
            store.triggerHaptic(.move)
            action()
        } label: {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrillyPalette.inkPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .brillySurface(store.surfaceStyle, cornerRadius: 14, interactive: true)
        }
        .buttonStyle(.plain)
    }
}
