import SwiftUI
import BrillyDerCore

public struct TrainLabsView: View {
    @Environment(BrillyAppStore.self) private var store

    enum LabKind: String, CaseIterable {
        case endgame = "Endgames"
        case vision = "Vision"
        case rush = "Puzzle Rush"
    }

    @State private var activeLab: LabKind = .endgame
    @State private var selectedCategory: EndgameCategory? = nil
    @State private var activeDrill: EndgameDrill? = nil

    public var body: some View {
        VStack(spacing: 14) {
            Picker("Lab", selection: $activeLab) {
                ForEach(LabKind.allCases, id: \.self) { k in
                    Text(k.rawValue).tag(k)
                }
            }
            .pickerStyle(.segmented)

            switch activeLab {
            case .endgame:
                endgameLabBody
            case .vision:
                BoardVisionPanel()
            case .rush:
                PuzzleRushPanel()
            }
        }
        .onAppear { applyPreferredEndgame() }
        .onChange(of: store.preferredEndgameCategory) { _, _ in
            applyPreferredEndgame()
        }
        .sheet(item: $activeDrill) { drill in
            EndgameDrillPlaySheet(drill: drill).environment(store)
        }
    }

    private func applyPreferredEndgame() {
        if let cat = store.preferredEndgameCategory {
            activeLab = .endgame
            selectedCategory = cat
            store.preferredEndgameCategory = nil
        }
    }

    private var endgameLabBody: some View {
        let combined = store.userEndgameDrills + EndgameLibrary.theoreticalDrills
        let filtered = combined.filter { selectedCategory == nil || $0.category == selectedCategory }

        return VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    catChip("All", cat: nil)
                    ForEach(EndgameCategory.allCases) { cat in
                        catChip(cat.rawValue, cat: cat)
                    }
                }
            }

            LazyVStack(spacing: 10) {
                ForEach(filtered) { drill in
                    let mastered = store.masteredEndgameIds.contains(drill.id)
                    Button {
                        activeDrill = drill
                    } label: {
                        HStack(spacing: 12) {
                            InteractiveChessBoardView(
                                board: (try? ChessBoard(fen: drill.fen)) ?? ChessBoard(),
                                orientation: drill.userColor,
                                theme: store.boardTheme,
                                surfaceStyle: store.surfaceStyle,
                                interactive: false
                            )
                            .frame(width: 66, height: 66)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(drill.category.rawValue)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(BrillyPalette.brillyTeal)
                                    Text("· \(drill.goal == .win ? "Play to Win" : "Hold Draw")")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(drill.goal == .win ? Color(hex: 0x22C55E) : BrillyPalette.goldAmber)
                                    Spacer()
                                    if mastered {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(BrillyPalette.brillyTeal)
                                    }
                                }
                                Text(drill.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(BrillyPalette.inkPrimary)
                                    .lineLimit(1)
                                Text(drill.keyIdea)
                                    .font(.caption2)
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(12)
                        .brillySurface(store.surfaceStyle, cornerRadius: 16, interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func catChip(_ label: String, cat: EndgameCategory?) -> some View {
        let sel = selectedCategory == cat
        return Button(label) {
            selectedCategory = cat
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(sel ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(sel ? BrillyPalette.brillyTeal : Color.white.opacity(0.08)))
        .buttonStyle(.plain)
    }
}

// MARK: - Interactive Syzygy Endgame Drill Sheet

private struct EndgameDrillPlaySheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let drill: EndgameDrill

    @State private var board: ChessBoard = ChessBoard()
    @State private var status: String = ""
    @State private var syzygy: SyzygyProbeResult? = nil
    @State private var botThinking = false
    @State private var showHint = false
    @State private var movesPlayed = 0
    @State private var botTask: Task<Void, Never>? = nil
    @State private var probeTask: Task<Void, Never>? = nil
    @State private var generation: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)

                ScrollView {
                    VStack(spacing: 14) {
                        HStack {
                            Label(drill.goal == .win ? "Goal: Win" : "Goal: Hold Draw", systemImage: "flag.checkered")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(BrillyPalette.brillyTeal)
                            Spacer()
                            if let syz = syzygy {
                                Text(syz.humanLabel)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.goldAmber)
                            }
                        }

                        InteractiveChessBoardView(
                            board: board,
                            orientation: drill.userColor,
                            theme: store.boardTheme,
                            surfaceStyle: store.surfaceStyle,
                            interactive: !botThinking && board.turn == drill.userColor && board.outcome == .ongoing
                        ) { move in
                            handleUserMove(move)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(status.isEmpty ? drill.keyIdea : status)
                                .font(.subheadline)
                                .foregroundStyle(BrillyPalette.inkPrimary)
                            if showHint {
                                Text("Key first idea: \(drill.firstHintSan)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(BrillyPalette.goldAmber)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .brillySurface(store.surfaceStyle, cornerRadius: 16)

                        HStack(spacing: 10) {
                            Button("Hint") { showHint = true }
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(BrillyPalette.goldAmber)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                                .buttonStyle(.plain)

                            Button("Reset") { resetDrill() }
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(BrillyPalette.inkPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(drill.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { resetDrill() }
            .onDisappear { cancelTasks() }
        }
    }

    private func cancelTasks() {
        generation &+= 1
        botTask?.cancel()
        botTask = nil
        probeTask?.cancel()
        probeTask = nil
        botThinking = false
    }

    private func resetDrill() {
        cancelTasks()
        board = (try? ChessBoard(fen: drill.fen)) ?? ChessBoard()
        status = drill.keyIdea
        showHint = false
        movesPlayed = 0
        probeCurrent()
    }

    private func probeCurrent() {
        probeTask?.cancel()
        let gen = generation
        let fen = board.fen
        probeTask = Task {
            let res = await SyzygyClient.shared.probe(fen: fen)
            if !Task.isCancelled && self.generation == gen {
                syzygy = res
            }
        }
    }

    @discardableResult
    private func checkTerminalOutcome() -> Bool {
        switch board.outcome {
        case .checkmate(let winner):
            if winner == drill.userColor {
                status = "Checkmate! Endgame mastered!"
                store.markEndgameMastered(drill.id)
            } else {
                status = "Checkmated — tap Reset to try again."
                store.triggerHaptic(.error)
            }
            return true
        case .stalemate, .insufficientMaterial, .fiftyMoveRule:
            if drill.goal == .draw {
                status = "Draw secured! Fortress mastered!"
                store.markEndgameMastered(drill.id)
            } else {
                status = "Drawn — you had a win here! Tap Reset to retry."
                store.triggerHaptic(.error)
            }
            return true
        case .ongoing:
            return false
        }
    }

    private func handleUserMove(_ move: ChessMove) {
        guard (try? board.apply(move)) != nil else { return }
        movesPlayed += 1
        store.triggerHaptic(.move)

        if checkTerminalOutcome() { return }

        botTask?.cancel()
        generation &+= 1
        let gen = generation
        botThinking = true
        let fenAfterUser = board.fen

        botTask = Task {
            let probe = await SyzygyClient.shared.probe(fen: fenAfterUser)
            guard !Task.isCancelled && self.generation == gen else { return }
            self.syzygy = probe

            // After user's move, opponent is to move: `draw` or `cursed-win` (opponent's 50-move draw) means user holds the draw!
            if drill.goal == .draw && movesPlayed >= 6 && (probe?.category == "draw" || probe?.category == "cursed-win") {
                status = "Holding solid theoretical draw! Endgame fortress mastered."
                store.markEndgameMastered(drill.id)
            }

            if let bestSyz = probe?.moves.first, let m = ChessMove(uci: bestSyz.uci) {
                _ = try? board.apply(m)
                store.triggerHaptic(.move)
            } else if let reply = await store.computeBotReply(fen: fenAfterUser, depth: 4) {
                guard !Task.isCancelled && self.generation == gen else { return }
                _ = try? board.apply(reply)
                store.triggerHaptic(.move)
            }

            guard !Task.isCancelled && self.generation == gen else { return }
            botThinking = false
            if !checkTerminalOutcome() {
                probeCurrent()
            }
        }
    }
}

// MARK: - 60-Second Board Vision Coordinate Sniper

private struct BoardVisionPanel: View {
    @Environment(BrillyAppStore.self) private var store

    @State private var isRunning = false
    @State private var orientation: PieceColor = .white
    @State private var hideCoords = true
    @State private var timeRemaining = 60
    @State private var score = 0
    @State private var mistakes = 0
    @State private var targetSquare: Square = Square(unchecked: 28) // e4
    @State private var flashColor: Color? = nil
    @State private var flashTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("60s Board Vision")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                    Text("Personal Best: \(store.boardVisionBestScore)")
                        .font(.caption)
                        .foregroundStyle(BrillyPalette.brillyTeal)
                }
                Spacer()
                if isRunning {
                    Text("\(timeRemaining)s")
                        .font(.title2.monospacedDigit().weight(.black))
                        .foregroundStyle(timeRemaining <= 10 ? BrillyPalette.blunderRose : BrillyPalette.brillyTeal)
                }
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)

            // Target Prompt Banner
            HStack {
                Text(isRunning ? "TAP SQUARE" : "READY")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrillyPalette.inkSecondary)
                Spacer()
                Text(isRunning ? targetSquare.algebraic.uppercased() : "--")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(flashColor ?? BrillyPalette.brillyTeal)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Score \(score)")
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                    if mistakes > 0 {
                        Text("\(mistakes) miss")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(BrillyPalette.blunderRose)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: BrillyPalette.warpPurple)

            // Tappable 8x8 Coordinate Board
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let cell = side / 8.0
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { col in
                                let rank = orientation == .white ? (7 - row) : row
                                let file = orientation == .white ? col : (7 - col)
                                let sq = Square(unchecked: rank * 8 + file)
                                ZStack {
                                    sq.isLightSquare ? store.boardTheme.lightSquare : store.boardTheme.darkSquare
                                    if !hideCoords {
                                        Text(sq.algebraic)
                                            .font(.system(size: 9, weight: .bold, design: .rounded))
                                            .foregroundStyle(store.boardTheme.coordColor(isLightSquare: sq.isLightSquare))
                                    }
                                }
                                .frame(width: cell, height: cell)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    handleTap(sq)
                                }
                            }
                        }
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .frame(maxWidth: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)

            // Controls
            HStack(spacing: 10) {
                Button(isRunning ? "Stop" : "Start 60s") {
                    if isRunning {
                        stopGame()
                    } else {
                        startGame()
                    }
                }
                .font(.headline)
                .foregroundStyle(isRunning ? BrillyPalette.inkPrimary : BrillyPalette.voidBg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(isRunning ? BrillyPalette.blunderRose : BrillyPalette.brillyTeal))
                .buttonStyle(.plain)

                Button(orientation == .white ? "White" : "Black") {
                    orientation = orientation.opposite
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(BrillyPalette.inkPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                .buttonStyle(.plain)

                Button(hideCoords ? "Labels Off" : "Labels On") {
                    hideCoords.toggle()
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(BrillyPalette.inkPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                .buttonStyle(.plain)
            }
        }
        .task(id: isRunning) {
            guard isRunning else { return }
            while isRunning && timeRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard isRunning && !Task.isCancelled else { break }
                timeRemaining -= 1
                if timeRemaining == 0 {
                    stopGame()
                }
            }
        }
        .onDisappear {
            flashTask?.cancel()
        }
    }

    private func startGame() {
        score = 0
        mistakes = 0
        timeRemaining = 60
        isRunning = true
        pickNextSquare()
    }

    private func stopGame() {
        isRunning = false
        store.recordBoardVisionScore(score)
        store.triggerHaptic(.success)
    }

    private func pickNextSquare() {
        var next = Square(unchecked: Int.random(in: 0..<64))
        if next == targetSquare {
            next = Square(unchecked: (next.rawValue + 17) % 64)
        }
        targetSquare = next
    }

    private func handleTap(_ sq: Square) {
        guard isRunning else { return }
        if sq == targetSquare {
            score += 1
            flashColor = Color(hex: 0x22C55E)
            store.triggerHaptic(.move)
            pickNextSquare()
        } else {
            mistakes += 1
            flashColor = BrillyPalette.blunderRose
            store.triggerHaptic(.error)
        }
        flashTask?.cancel()
        flashTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            if !Task.isCancelled {
                flashColor = nil
            }
        }
    }
}

// MARK: - Puzzle Rush (3-Min Blitz & Survival 3-Strikes)

private struct PuzzleRushPanel: View {
    @Environment(BrillyAppStore.self) private var store

    enum RushMode: String, CaseIterable {
        case blitz = "3-Min Blitz"
        case survival = "Survival"
    }

    private struct RushItem: Identifiable {
        let id: String
        let fen: String
        let orientation: PieceColor
        let expectedUci: String
        let expectedSan: String
        let subtitle: String
    }

    @State private var mode: RushMode = .blitz
    @State private var running = false
    @State private var timeLeft = 180
    @State private var strikes = 0
    @State private var score = 0
    @State private var deck: [RushItem] = []
    @State private var idx = 0
    @State private var board = ChessBoard()
    @State private var feedback = "Solve as many tactics as you can before 3 strikes!"

    var body: some View {
        VStack(spacing: 14) {
            Picker("Mode", selection: $mode) {
                ForEach(RushMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .disabled(running)
            .onChange(of: mode) { _, _ in
                if !running {
                    score = 0
                    strikes = 0
                    timeLeft = 180
                    feedback = mode == .blitz
                        ? "3 minutes on the clock — 3 strikes and you're out!"
                        : "No clock — survive as long as you can with 3 strikes!"
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode == .blitz ? "Best Blitz: \(store.puzzleRushBlitzBest)" : "Best Survival: \(store.puzzleRushSurvivalBest)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: i < (3 - strikes) ? "heart.fill" : "heart.slash")
                                .font(.caption)
                                .foregroundStyle(i < (3 - strikes) ? BrillyPalette.blunderRose : BrillyPalette.inkSecondary)
                        }
                    }
                }
                Spacer()
                Text("Score \(score)")
                    .font(.headline.monospacedDigit().weight(.black))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                if mode == .blitz && running {
                    Text("\(timeLeft / 60):\(String(format: "%02d", timeLeft % 60))")
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(timeLeft <= 20 ? BrillyPalette.blunderRose : BrillyPalette.brillyTeal)
                        .padding(.leading, 8)
                }
            }
            .padding(14)
            .brillySurface(store.surfaceStyle, cornerRadius: 18)

            if running && idx < deck.count {
                let item = deck[idx]
                InteractiveChessBoardView(
                    board: board,
                    orientation: item.orientation,
                    theme: store.boardTheme,
                    surfaceStyle: store.surfaceStyle
                ) { move in
                    if move.uci == item.expectedUci {
                        score += 1
                        feedback = "Hit! \(item.expectedSan)"
                        store.triggerHaptic(.success)
                    } else {
                        strikes += 1
                        feedback = "Strike \(strikes)/3 — best was \(item.expectedSan)"
                        store.triggerHaptic(.error)
                        if strikes >= 3 {
                            finishRun()
                            return
                        }
                    }
                    idx = (idx + 1) % max(1, deck.count)
                    board = (try? ChessBoard(fen: deck[idx].fen)) ?? ChessBoard()
                }
            }

            if !feedback.isEmpty {
                Text(feedback)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(running ? BrillyPalette.inkPrimary : BrillyPalette.brillyTeal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .brillySurface(store.surfaceStyle, cornerRadius: 14)
            }

            Button(running ? "End Run" : "Start \(mode.rawValue)") {
                if running { finishRun() } else { startRun() }
            }
            .font(.headline)
            .foregroundStyle(running ? BrillyPalette.inkPrimary : BrillyPalette.voidBg)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(running ? BrillyPalette.blunderRose : BrillyPalette.brillyTeal))
            .buttonStyle(.plain)
        }
        .task(id: running) {
            guard running && mode == .blitz else { return }
            while running && timeLeft > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard running && !Task.isCancelled else { break }
                timeLeft -= 1
                if timeLeft == 0 { finishRun() }
            }
        }
    }

    private func startRun() {
        var items: [RushItem] = store.mistakeDeck.shuffled().map {
            let orient = (try? ChessBoard(fen: $0.fen))?.turn ?? $0.playerColor
            return RushItem(id: $0.id, fen: $0.fen, orientation: orient, expectedUci: $0.bestMoveUci, expectedSan: $0.bestMoveSan, subtitle: $0.openingName)
        }
        for fb in DailyCoachPlanner.fallbackGravityFlashes {
            items.append(RushItem(id: fb.id, fen: fb.fen, orientation: fb.orientation, expectedUci: fb.expectedUci, expectedSan: fb.expectedSan, subtitle: fb.subtitle))
        }
        deck = items
        idx = 0
        score = 0
        strikes = 0
        timeLeft = 180
        running = true
        feedback = "Find the winning move fast!"
        if let first = deck.first {
            board = (try? ChessBoard(fen: first.fen)) ?? ChessBoard()
        }
    }

    private func finishRun() {
        running = false
        store.recordPuzzleRushScore(score, survival: mode == .survival)
        feedback = "Run finished! Final score: \(score)."
    }
}
