import SwiftUI
import BrillyDerCore

public struct OpeningsTabView: View {
    @Environment(BrillyAppStore.self) private var store
    @State private var sideFilter: RepertoireSide = .white
    @State private var selectedCourse: OpeningCourse? = nil
    @State private var showingImportSheet: Bool = false

    private var courses: [OpeningCourse] {
        store.allCourses.filter { $0.side == sideFilter }
    }

    public var body: some View {
        ZStack {
            CosmicVoidBackdrop(style: store.surfaceStyle)

            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        Picker("Side", selection: $sideFilter) {
                            Text("White").tag(RepertoireSide.white)
                            Text("Black").tag(RepertoireSide.black)
                        }
                        .pickerStyle(.segmented)

                        Button {
                            showingImportSheet = true
                        } label: {
                            Label("Import PGN", systemImage: "square.and.arrow.down")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap.fill")
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        Text("Tap Daily or press & hold any opening to include it in Daily FSRS.")
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 4)

                    LazyVStack(spacing: 12) {
                        ForEach(courses) { course in
                            courseCard(course)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
        }
        .navigationTitle("Openings")
        .sheet(item: $selectedCourse) { course in
            CourseDetailSheet(course: course)
                .environment(store)
        }
        .sheet(isPresented: $showingImportSheet) {
            ImportCourseSheet(defaultSide: sideFilter)
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
        let inDaily = store.isCourseInDaily(course.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.copy(cosmic: course.codename.uppercased(), classic: course.difficulty.uppercased()))
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(BrillyPalette.brillyTeal)
                    Text(course.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                }
                Spacer(minLength: 6)

                // Direct one-tap Daily FSRS inclusion toggle pill
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        store.toggleCourseInDaily(course.id)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: inDaily ? "checkmark.circle.fill" : "plus.circle")
                            .font(.caption2.weight(.bold))
                        Text(inDaily ? "Daily" : "Add Daily")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(inDaily ? BrillyPalette.voidBg : BrillyPalette.inkSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(inDaily ? BrillyPalette.brillyTeal : Color.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(inDaily ? "Included in Daily FSRS. Tap to remove." : "Not in Daily FSRS. Tap to include.")

                if inDaily && dueCount > 0 {
                    Text("\(dueCount) due")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(BrillyPalette.brillyTeal.opacity(0.16)))
                }
            }

            Text(course.tagline)
                .font(.caption)
                .foregroundStyle(BrillyPalette.inkSecondary)
                .lineLimit(2)

            // Inviting empty state when unstarted (0% recall) vs active recall bar
            if reviewed.isEmpty {
                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(BrillyPalette.brillyTeal.opacity(0.14))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [BrillyPalette.brillyTeal.opacity(0.55), BrillyPalette.warpPurple.opacity(0.45)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(18, geo.size.width * 0.14))
                        }
                    }
                    .frame(height: 6)

                    HStack(spacing: 4) {
                        Text("Start Drill")
                            .font(.caption2.weight(.bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(BrillyPalette.brillyTeal)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(BrillyPalette.brillyTeal.opacity(0.14))
                            .overlay(Capsule().strokeBorder(BrillyPalette.brillyTeal.opacity(0.35), lineWidth: 1))
                    )
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView(value: Double(avgRecall), total: 100.0)
                        .tint(BrillyPalette.brillyTeal)
                    Text("\(avgRecall)% recall")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                }
            }
        }
        .padding(16)
        .brillySurface(store.surfaceStyle, cornerRadius: 20, tint: inDaily ? BrillyPalette.brillyTeal : nil, interactive: true)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture {
            selectedCourse = course
        }
        .contextMenu {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    store.toggleCourseInDaily(course.id)
                }
            } label: {
                Label(
                    inDaily ? "Remove from Daily FSRS" : "Include in Daily FSRS",
                    systemImage: inDaily ? "minus.circle" : "checkmark.circle.fill"
                )
            }
            Button {
                selectedCourse = course
            } label: {
                Label("Open Course & Drills", systemImage: "book.fill")
            }
        }
    }
}

// MARK: - Import Custom PGN Course Sheet

private struct ImportCourseSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let defaultSide: RepertoireSide
    @State private var name: String = ""
    @State private var side: RepertoireSide = .white
    @State private var pgn: String = ""
    @State private var errorText: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)
                VStack(spacing: 14) {
                    TextField("Course name (e.g. Vienna Gambit)", text: $name)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
                        .foregroundStyle(BrillyPalette.inkPrimary)

                    Picker("Side", selection: $side) {
                        Text("White Repertoire").tag(RepertoireSide.white)
                        Text("Black Repertoire").tag(RepertoireSide.black)
                    }
                    .pickerStyle(.segmented)

                    TextEditor(text: $pgn)
                        .scrollContentBackground(.hidden)
                        .font(.system(.caption, design: .monospaced))
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .padding(12)
                        .brillySurface(store.surfaceStyle, cornerRadius: 16)

                    if let err = errorText {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(BrillyPalette.blunderRose)
                    }

                    Button {
                        do {
                            try store.importCustomCourse(name: name, side: side, pgn: pgn)
                            dismiss()
                        } catch {
                            errorText = error.localizedDescription
                        }
                    } label: {
                        Text("Import & Unlock FSRS Cards")
                            .font(.headline)
                            .foregroundStyle(BrillyPalette.voidBg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoundedRectangle(cornerRadius: 14).fill(BrillyPalette.brillyTeal))
                    }
                    .buttonStyle(.plain)
                    .disabled(pgn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
            }
            .navigationTitle("Import PGN Course")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { side = defaultSide }
        }
    }
}

// MARK: - Course Detail Sheet (Mothership + Walkthrough/Tree + FSRS Drill + PGN Export)

private struct CourseDetailSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let course: OpeningCourse

    enum CourseTab: String, CaseIterable {
        case setup = "Setup"
        case walkthrough = "Walkthrough"
        case drill = "FSRS Drill"
    }

    enum WalkLayout: String, CaseIterable {
        case line = "Line"
        case tree = "Move Tree"
    }

    @State private var activeTab: CourseTab = .setup
    @State private var walkLayout: WalkLayout = .line
    @State private var selectedLineIndex: Int = 0
    @State private var selectedTreeFen: String? = nil
    @State private var cachedTreeRoots: [RepertoireTreeNode] = []
    @State private var confirmingDelete: Bool = false

    // Walkthrough state
    @State private var walkStep: Int = 0
    @State private var isAutoPlaying: Bool = false

    // Drill state
    @State private var drillCardIds: [String] = []
    @State private var drillIdx: Int = 0
    @State private var drillBoard: ChessBoard = ChessBoard()
    @State private var drillLastMove: (from: Square, to: Square)? = nil
    @State private var drillShownAt: Date = Date()
    @State private var drillHintLevel: Int = 0
    @State private var drillHadMistake: Bool = false
    @State private var drillFeedback: String = "Play your repertoire move on the board."
    @State private var drillSolved: Bool = false
    @State private var drillSolvedBadge: MoveBadgeOverlay? = nil

    private var currentLine: OpeningLine? {
        guard !course.lines.isEmpty else { return nil }
        return course.lines[min(selectedLineIndex, course.lines.count - 1)]
    }

    private var isDeletableCustom: Bool {
        course.source == "pgn" || course.source == "lichess-study"
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
                if isDeletableCustom {
                    ToolbarItem(placement: .automatic) {
                        Button(role: .destructive) {
                            confirmingDelete = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(BrillyPalette.blunderRose)
                        }
                        .accessibilityLabel("Delete Custom Course")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    ShareLink(item: RepertoireTreeService.exportCourseToPGN(course)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export Course PGN")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isAutoPlaying = false
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Delete \"\(course.name)\"?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Course & Cards", role: .destructive) {
                    store.deleteCustomCourse(id: course.id)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the custom repertoire and its FSRS cards from this device.")
            }
            .onAppear {
                refreshTreeCache()
            }
            .onChange(of: activeTab) { _, newTab in
                isAutoPlaying = false
                if newTab == .drill {
                    prepareDrill()
                } else if newTab == .walkthrough && walkLayout == .tree {
                    refreshTreeCache()
                }
            }
            .onChange(of: walkLayout) { _, newLayout in
                if newLayout == .tree { refreshTreeCache() }
            }
            .task(id: isAutoPlaying) {
                guard isAutoPlaying, let line = currentLine else { return }
                while !Task.isCancelled && isAutoPlaying {
                    try? await Task.sleep(for: .milliseconds(1200))
                    guard !Task.isCancelled, isAutoPlaying else { break }
                    if walkStep < line.moves.count {
                        walkStep += 1
                    } else {
                        isAutoPlaying = false
                    }
                }
            }
        }
    }

    private func refreshTreeCache() {
        cachedTreeRoots = RepertoireTreeService.buildTree(for: course, fsrsCards: store.fsrsCards)
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

    // MARK: - 2. Guided Walkthrough + Visual Repertoire Move Tree

    private var walkthroughView: some View {
        VStack(spacing: 12) {
            Picker("Layout", selection: $walkLayout) {
                ForEach(WalkLayout.allCases, id: \.self) { l in
                    Text(l.rawValue).tag(l)
                }
            }
            .pickerStyle(.segmented)

            if walkLayout == .tree {
                treeView
            } else {
                lineWalkthroughBody
            }
        }
    }

    private var treeView: some View {
        let previewBoard = (selectedTreeFen.flatMap { try? ChessBoard(fen: $0) }) ?? boardAfter(moves: course.mothershipSetup.previewMoves)

        return VStack(spacing: 12) {
            InteractiveChessBoardView(
                board: previewBoard,
                orientation: course.side.pieceColor,
                theme: store.boardTheme,
                surfaceStyle: store.surfaceStyle,
                interactive: false
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(store.copy(cosmic: "Repertoire Star Chart (Tap any move)", classic: "Repertoire Move Tree (Tap any move)"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrillyPalette.brillyTeal)

                if cachedTreeRoots.isEmpty {
                    Text("No repertoire branches found in this course.")
                        .font(.caption)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                } else {
                    ForEach(cachedTreeRoots) { node in
                        TreeNodeRow(node: node, depth: 0, selectedFen: $selectedTreeFen)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)
        }
    }

    @ViewBuilder
    private var lineWalkthroughBody: some View {
        if let line = currentLine {
            let clampedStep = max(0, min(walkStep, line.moves.count))
            let prefix = Array(line.moves.prefix(clampedStep))
            let board = boardAfter(moves: prefix)
            let activeAnnotation = line.annotations.first { $0.ply == clampedStep - 1 }

            VStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(course.lines.enumerated()), id: \.element.id) { idx, ln in
                            let sel = idx == selectedLineIndex
                            Button {
                                selectedLineIndex = idx
                                walkStep = 0
                                isAutoPlaying = false
                            } label: {
                                Text("\(ln.eco) · \(ln.title)")
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

                BrillyGlassCluster(style: store.surfaceStyle, spacing: 10) {
                    HStack(spacing: 10) {
                        walkBtn("backward.end.fill", label: "Start of line") { isAutoPlaying = false; walkStep = 0 }
                        walkBtn("chevron.left", label: "Previous move") { isAutoPlaying = false; walkStep = max(0, clampedStep - 1) }
                        walkBtn(isAutoPlaying ? "pause.fill" : "play.fill", label: isAutoPlaying ? "Pause" : "Auto play") {
                            if clampedStep >= line.moves.count { walkStep = 0 }
                            isAutoPlaying.toggle()
                        }
                        walkBtn("chevron.right", label: "Next move") { isAutoPlaying = false; walkStep = min(line.moves.count, clampedStep + 1) }
                        walkBtn("forward.end.fill", label: "End of line") { isAutoPlaying = false; walkStep = line.moves.count }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(clampedStep == 0 ? line.title : "Move \((clampedStep + 1) / 2): \(line.moves[clampedStep - 1])")
                            .font(.headline)
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Spacer()
                        Text("\(clampedStep) / \(line.moves.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(BrillyPalette.inkSecondary)
                    }
                    Text(activeAnnotation?.plan ?? line.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                    if store.vibeMode == .cosmic, let cue = activeAnnotation?.cosmicCue {
                        Text(cue)
                            .font(.caption.italic())
                            .foregroundStyle(BrillyPalette.brillyTeal)
                    }

                    if let traps = activeAnnotation?.wrongMoveTraps, !traps.isEmpty {
                        Divider().overlay(Color.white.opacity(0.1))
                        ForEach(traps, id: \.playedSan) { trap in
                            VStack(alignment: .leading, spacing: 3) {
                                Label("Avoid Trap: \(trap.playedSan)", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.blunderRose)
                                Text("Punishment: \(trap.punishmentLine.joined(separator: " ")) — \(trap.reason)")
                                    .font(.caption2)
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .brillySurface(store.surfaceStyle, cornerRadius: 18)

                Button {
                    store.unlockLine(courseId: course.id, lineId: line.id)
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
        } else {
            Text("This course has no playable lines yet.")
                .font(.subheadline)
                .foregroundStyle(BrillyPalette.inkSecondary)
                .padding(24)
        }
    }

    // MARK: - 3. FSRS Signal Strength Drill (Live card lookup + no double FSRS grading!)

    private var drillView: some View {
        VStack(spacing: 12) {
            if drillCardIds.isEmpty {
                Text("No drill cards available for this line.")
                    .foregroundStyle(BrillyPalette.inkSecondary)
            } else {
                let safeIdx = min(drillIdx, drillCardIds.count - 1)
                let cardId = drillCardIds[safeIdx]
                if let card = store.fsrsCards.first(where: { $0.cardId == cardId }) {
                    let fenBoard = try? ChessBoard(fen: card.fen)
                    let orient = fenBoard?.turn ?? course.side.pieceColor
                    let moveNum = fenBoard?.fullmoveNumber ?? (card.ply / 2 + 1)
                    let ann = currentLine?.annotations.first { $0.ply == card.ply }
                    let hintHighlights: [SquareHighlight] = {
                        guard drillHintLevel >= 1 && !drillSolved,
                              let legal = DailyCoachPlanner.legalMove(uci: card.expectedUci, on: drillBoard) else { return [] }
                        return [SquareHighlight(square: legal.from.algebraic, color: .plan)]
                    }()
                    let hintArrows: [BoardArrow] = {
                        guard drillHintLevel >= 2 && !drillSolved,
                              let legal = DailyCoachPlanner.legalMove(uci: card.expectedUci, on: drillBoard) else { return [] }
                        return [BoardArrow(from: legal.from.algebraic, to: legal.to.algebraic, color: .best)]
                    }()

                    HStack {
                        Text("Card \(safeIdx + 1) / \(drillCardIds.count) · Move \(moveNum)\(orient == .black ? "..." : "")")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(BrillyPalette.brillyTeal)
                        Spacer()
                        Text("Recall \(FSRS6Scheduler.recallProbability(for: card))%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(BrillyPalette.inkSecondary)
                    }

                    InteractiveChessBoardView(
                        board: drillBoard,
                        orientation: orient,
                        theme: store.boardTheme,
                        surfaceStyle: store.surfaceStyle,
                        interactive: !drillSolved,
                        lastMove: drillLastMove,
                        arrows: hintArrows,
                        highlights: hintHighlights,
                        moveBadge: drillSolvedBadge
                    ) { move in
                        guard !drillSolved else { return }
                        let elapsedMs = Int(Date().timeIntervalSince(drillShownAt) * 1000.0)
                        let usedHint = drillHintLevel > 0
                        let hit = move.uci == card.expectedUci
                        if hit {
                            if (try? drillBoard.apply(move)) != nil {
                                drillLastMove = (move.from, move.to)
                            }
                            drillSolved = true
                            drillHintLevel = 0
                            drillSolvedBadge = MoveBadgeOverlay(square: move.to, classification: .best)
                            if !drillHadMistake {
                                let result = store.recordOpeningAttempt(
                                    cardId: card.cardId,
                                    attempt: OpeningAttemptInput(correct: true, responseMs: elapsedMs, hintUsed: usedHint)
                                )
                                drillFeedback = "Locked in \(card.expectedSan)! FSRS graded \(result?.rating.label ?? "Good")."
                            } else {
                                store.triggerHaptic(.success)
                                drillFeedback = "Got it (\(card.expectedSan))! Scheduled soon after your earlier miss."
                            }
                        } else {
                            var temp = drillBoard
                            let playedSan = (try? temp.apply(move).san) ?? move.uci
                            let trap = ann?.wrongMoveTraps?.first { $0.playedSan == playedSan }
                            if !drillHadMistake {
                                drillHadMistake = true
                                _ = store.recordOpeningAttempt(
                                    cardId: card.cardId,
                                    attempt: OpeningAttemptInput(correct: false, responseMs: elapsedMs, hintUsed: usedHint)
                                )
                            } else {
                                store.triggerHaptic(.error)
                            }
                            if let trap {
                                drillFeedback = "Trap (\(playedSan)): \(trap.reason)"
                            } else {
                                drillFeedback = "Played \(playedSan) — try a different repertoire move, or tap Hint."
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(drillFeedback)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(drillSolved ? BrillyPalette.brillyTeal : (drillHadMistake ? BrillyPalette.blunderRose : BrillyPalette.inkPrimary))
                        if drillSolved, let plan = ann?.plan, !plan.isEmpty {
                            Text(plan)
                                .font(.caption)
                                .foregroundStyle(Color(hex: 0xCBD5E1))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .brillySurface(store.surfaceStyle, cornerRadius: 16, tint: drillSolved ? BrillyPalette.brillyTeal : nil)

                    HStack(spacing: 10) {
                        Button {
                            guard !drillSolved,
                                  let legal = DailyCoachPlanner.legalMove(uci: card.expectedUci, on: drillBoard) else { return }
                            if drillHintLevel == 0 {
                                drillHintLevel = 1
                                let pName = drillBoard[legal.from]?.type.displayName ?? "piece"
                                drillFeedback = "Hint: Look at your \(pName) on \(legal.from.algebraic)!"
                            } else if drillHintLevel == 1 {
                                drillHintLevel = 2
                                drillFeedback = "Arrow revealed: play \(card.expectedSan) (\(legal.from.algebraic) → \(legal.to.algebraic))."
                            }
                            store.triggerHaptic(.move)
                        } label: {
                            Label(
                                drillHintLevel == 0 ? "Hint" : (drillHintLevel == 1 ? "Show Arrow" : "Arrow Shown"),
                                systemImage: drillHintLevel == 0 ? "lightbulb.fill" : "arrow.up.right"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BrillyPalette.goldAmber)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                        }
                        .buttonStyle(.plain)
                        .disabled(drillSolved || drillHintLevel >= 2)
                        .opacity((drillSolved || drillHintLevel >= 2) ? 0.50 : 1.0)

                        Button {
                            drillIdx = (safeIdx + 1) % drillCardIds.count
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
    }

    private func prepareDrill() {
        guard let line = currentLine else {
            drillCardIds = []
            return
        }
        store.unlockLine(courseId: course.id, lineId: line.id)
        drillCardIds = store.fsrsCards
            .filter { $0.courseId == course.id && $0.lineId == line.id }
            .sorted { $0.ply < $1.ply }
            .map(\.cardId)
        drillIdx = 0
        loadDrillCard()
    }

    private func loadDrillCard() {
        guard drillIdx < drillCardIds.count,
              let card = store.fsrsCards.first(where: { $0.cardId == drillCardIds[drillIdx] }) else { return }
        let board = (try? ChessBoard(fen: card.fen)) ?? ChessBoard()
        let moveNum = board.fullmoveNumber
        let seq: [String] = {
            if !card.moveSequence.isEmpty { return card.moveSequence }
            if let moves = currentLine?.moves, card.ply > 0, card.ply <= moves.count {
                return Array(moves.prefix(card.ply))
            }
            return []
        }()
        let oppPrev = DailyCoachPlanner.precedingMove(for: seq)
        drillBoard = board
        drillLastMove = oppPrev.map { ($0.from, $0.to) }
        drillShownAt = Date()
        drillHintLevel = 0
        drillHadMistake = false
        drillSolved = false
        drillSolvedBadge = nil
        if let oppPrev {
            drillFeedback = "After \(oppPrev.san) (Move \(moveNum)) — play your \(board.turn.displayName) repertoire reply!"
        } else {
            drillFeedback = "Move \(moveNum) — play your \(board.turn.displayName) repertoire move!"
        }
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

    private func walkBtn(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
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
        .accessibilityLabel(label)
    }
}

private struct TreeNodeRow: View {
    let node: RepertoireTreeNode
    let depth: Int
    @Binding var selectedFen: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                selectedFen = node.fen
            } label: {
                HStack(spacing: 6) {
                    Text("\(node.ply / 2 + 1)\(node.ply % 2 == 0 ? "." : "...") \(node.san)")
                        .font(.caption.monospaced().weight(node.isUserMove ? .bold : .regular))
                        .foregroundStyle(selectedFen == node.fen ? BrillyPalette.brillyTeal : BrillyPalette.inkPrimary)
                    if let r = node.recallPct {
                        Circle()
                            .fill(r >= 80 ? Color(hex: 0x22C55E) : (r > 0 ? BrillyPalette.goldAmber : Color.white.opacity(0.25)))
                            .frame(width: 7, height: 7)
                    }
                    Spacer()
                }
                .padding(.leading, CGFloat(min(depth, 5)) * 12)
                .padding(.vertical, 3)
            }
            .buttonStyle(.plain)

            ForEach(node.children) { child in
                TreeNodeRow(node: child, depth: depth + 1, selectedFen: $selectedFen)
            }
        }
    }
}
