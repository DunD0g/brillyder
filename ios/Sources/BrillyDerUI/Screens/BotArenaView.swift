import SwiftUI
import BrillyDerCore

// MARK: - Bot Arena Presentation Wrapper

public struct BotArenaSheet: View {
    @Environment(BrillyAppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let initialMode: BotArenaView.ArenaMode

    public init(initialMode: BotArenaView.ArenaMode = .botVsBot) {
        self.initialMode = initialMode
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: store.surfaceStyle)
                ScrollView {
                    BotArenaView(
                        initialMode: initialMode,
                        onOpenInAnalyze: { dismiss() }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle(store.copy(cosmic: "Bot Arena", classic: "Bot Arena"))
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
}

// MARK: - Interactive Bot Arena (Play vs Bot + Bot vs Bot)

public struct BotArenaView: View {
    public enum ArenaMode: String, CaseIterable, Identifiable, Sendable {
        case playVsBot = "Play vs Bot"
        case botVsBot = "Bot vs Bot"
        public var id: String { rawValue }
    }

    public enum HumanSideChoice: String, CaseIterable, Identifiable, Sendable {
        case white = "White"
        case random = "Random"
        case black = "Black"
        public var id: String { rawValue }
    }

    public enum ArenaPace: String, CaseIterable, Identifiable, Sendable {
        case slow = "Slow"
        case normal = "Normal"
        case fast = "Fast"
        case blitz = "Blitz"

        public var id: String { rawValue }
        public var delayMs: UInt64 {
            switch self {
            case .slow:   return 1150
            case .normal: return 550
            case .fast:   return 180
            case .blitz:  return 40
            }
        }
    }

    private struct ArenaMoveRecord: Identifiable {
        let id: Int // 1-based ply
        let san: String
        let uci: String
        let from: Square
        let to: Square
        let afterFen: String
        let sourceLabel: String
        let evalScore: EngineScore?
    }

    @Environment(BrillyAppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    private let onOpenInAnalyze: (() -> Void)?

    @State private var mode: ArenaMode
    @State private var setupExpanded: Bool = true
    @State private var suppressNextModeReset: Bool = false

    // Play vs Bot setup
    @State private var humanSideChoice: HumanSideChoice = .white
    @State private var resolvedHumanColor: PieceColor = .white
    @State private var playOpponentBot: BotProfile = .club1000
    @State private var playBotOpening: BotOpeningSelection = .freePlay
    @State private var showEvalInPlay: Bool = true

    // Bot vs Bot setup
    @State private var whiteBot: BotProfile = .deep
    @State private var blackBot: BotProfile = .balanced
    @State private var whiteOpening: BotOpeningSelection = .freePlay
    @State private var blackOpening: BotOpeningSelection = .freePlay
    @State private var guideOpponentOpening: Bool = true
    @State private var pace: ArenaPace = .normal

    // Live board & match state
    @State private var board: ChessBoard = ChessBoard()
    @State private var orientation: PieceColor = .white
    @State private var moveHistory: [ArenaMoveRecord] = []
    @State private var viewPly: Int? = nil // nil = live tip
    @State private var positionCounts: [String: Int] = [:]
    @State private var liveScore: EngineScore = ChessMath.buildEngineScore(cpWhite: 0)
    @State private var isMatchRunning: Bool = false
    @State private var isThinking: Bool = false
    @State private var statusBanner: String = "Configure your bots & openings, then tap Start."
    @State private var resultString: String = "*"
    @State private var hintArrow: BoardArrow? = nil

    // Dedicated lightweight Swift engine for casual/club bots & quick hints
    @State private var localSwiftEngine = BrillyNativeEngine()
    @State private var arenaTask: Task<Void, Never>? = nil
    @State private var hintTask: Task<Void, Never>? = nil
    @State private var matchGeneration: Int = 0

    // Bot picker modal state
    private enum PickerTarget: Identifiable {
        case playOpponent
        case whiteBot
        case blackBot
        var id: String {
            switch self {
            case .playOpponent: return "play"
            case .whiteBot:     return "white"
            case .blackBot:     return "black"
            }
        }
    }
    @State private var activeBotPicker: PickerTarget? = nil

    public init(
        initialMode: ArenaMode = .botVsBot,
        onOpenInAnalyze: (() -> Void)? = nil
    ) {
        _mode = State(initialValue: initialMode)
        self.onOpenInAnalyze = onOpenInAnalyze
    }

    private var whiteCourses: [OpeningCourse] {
        store.allCourses.filter { $0.side == .white }
    }

    private var blackCourses: [OpeningCourse] {
        store.allCourses.filter { $0.side == .black }
    }

    private var isGameOver: Bool {
        resultString != "*"
    }

    private var displayedBoard: ChessBoard {
        guard let ply = viewPly else { return board }
        if ply == 0 { return ChessBoard() }
        if ply >= 1 && ply <= moveHistory.count {
            return (try? ChessBoard(fen: moveHistory[ply - 1].afterFen)) ?? board
        }
        return board
    }

    private var displayedLastMove: (from: Square, to: Square)? {
        let idx = (viewPly ?? moveHistory.count) - 1
        guard idx >= 0 && idx < moveHistory.count else { return nil }
        return (moveHistory[idx].from, moveHistory[idx].to)
    }

    private var displayedScore: EngineScore {
        if let ply = viewPly {
            if ply == 0 { return ChessMath.buildEngineScore(cpWhite: 0) }
            if ply >= 1 && ply <= moveHistory.count {
                for i in stride(from: ply - 1, through: 0, by: -1) {
                    if let s = moveHistory[i].evalScore { return s }
                }
            }
        }
        return liveScore
    }

    private var isHumanTurn: Bool {
        mode == .playVsBot
            && viewPly == nil
            && !isGameOver
            && !isThinking
            && board.turn == resolvedHumanColor
    }

    private var effectiveWhiteName: String {
        if mode == .playVsBot {
            return resolvedHumanColor == .white ? "You" : playOpponentBot.displayName
        }
        return whiteBot.displayName
    }

    private var effectiveBlackName: String {
        if mode == .playVsBot {
            return resolvedHumanColor == .black ? "You" : playOpponentBot.displayName
        }
        return blackBot.displayName
    }

    private var effectiveWhiteElo: Int? {
        if mode == .playVsBot {
            return resolvedHumanColor == .white ? nil : playOpponentBot.elo
        }
        return whiteBot.elo
    }

    private var effectiveBlackElo: Int? {
        if mode == .playVsBot {
            return resolvedHumanColor == .black ? nil : blackBot.elo
        }
        return blackBot.elo
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Mode Switcher: Play vs Bot | Bot vs Bot
            Picker("Arena Mode", selection: $mode) {
                ForEach(ArenaMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in
                if suppressNextModeReset {
                    suppressNextModeReset = false
                    return
                }
                stopMatchLoop()
                resetBoardForCurrentSetup(autoStart: false)
                setupExpanded = true
            }

            // Collapsible Matchup & Openings Setup Card
            setupCard

            // Live Eval Bar (always shown in Bot vs Bot; toggleable in Play vs Bot)
            if mode == .botVsBot || showEvalInPlay {
                EvalBarView(score: displayedScore, orientation: orientation)
            }

            // Top Player Banner
            let topColor: PieceColor = orientation == .white ? .black : .white
            playerBanner(for: topColor)

            // Interactive Chessboard
            InteractiveChessBoardView(
                board: displayedBoard,
                orientation: orientation,
                theme: store.effectiveBoardTheme,
                surfaceStyle: store.surfaceStyle,
                interactive: isHumanTurn,
                lastMove: displayedLastMove,
                arrows: hintArrow.map { [$0] } ?? []
            ) { move in
                handleHumanMove(move)
            }

            // Bottom Player Banner
            playerBanner(for: orientation)

            // Live Status & Move Attribution Ribbon
            statusRibbon

            // Interactive Move Tape
            if !moveHistory.isEmpty {
                moveTape
            }

            // Primary & Secondary Controls
            controlsSection

            // One-tap Full Game Review in Analyze tab
            if moveHistory.count >= 2 {
                Button {
                    analyzeCurrentArenaGame()
                } label: {
                    Label("Analyze Game in Review (!! / ??)", systemImage: "sparkles")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                        .contentShape(Capsule())
                }
                .buttonStyle(BrillyPressScaleStyle())
            }
        }
        .onAppear {
            if positionCounts.isEmpty {
                positionCounts[board.positionKey] = 1
            }
            // Default Ultra vs Deep on Founder Admin / Pro, Balanced vs Deep on Free
            if store.hasProAccess && whiteBot == .deep && blackBot == .balanced && moveHistory.isEmpty {
                blackBot = .ultra
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && isMatchRunning {
                pauseMatchLoop()
            }
        }
        .onDisappear {
            stopMatchLoop()
        }
        .sheet(item: $activeBotPicker) { target in
            BotProfilePickerSheet(
                title: pickerTitle(for: target),
                selected: bindingForPicker(target),
                hasProAccess: store.hasProAccess,
                surfaceStyle: store.surfaceStyle
            ) { lockedBot in
                activeBotPicker = nil
                store.openProPaywall(feature: "\(lockedBot.displayName) (\(lockedBot.eloLabel) Elo)")
            }
        }
    }

    // MARK: - Setup Card

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    setupExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: mode == .botVsBot ? "cpu.fill" : "person.fill.checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                    Text(setupSummaryTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(setupExpanded ? "Hide" : "Edit")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                    Image(systemName: setupExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if setupExpanded {
                Divider().overlay(Color.white.opacity(0.08))
                if mode == .botVsBot {
                    botVsBotSetupBody
                } else {
                    playVsBotSetupBody
                }
            }
        }
        .padding(14)
        .brillySurface(store.surfaceStyle, cornerRadius: 18, tint: mode == .botVsBot ? BrillyPalette.warpPurple : BrillyPalette.brillyTeal)
    }

    private var setupSummaryTitle: String {
        if mode == .botVsBot {
            return "\(whiteBot.shortName) (\(whiteBot.eloLabel)) vs \(blackBot.shortName) (\(blackBot.eloLabel))"
        }
        return "You (\(humanSideChoice.rawValue)) vs \(playOpponentBot.shortName) (\(playOpponentBot.eloLabel))"
    }

    private var botVsBotSetupBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            // White Bot + White Opening
            botSideConfigRow(
                sideLabel: "WHITE BOT",
                sideColor: .white,
                bot: whiteBot,
                opening: $whiteOpening,
                courses: whiteCourses,
                onPickBot: { activeBotPicker = .whiteBot }
            )

            // Quick Swap + VS Divider
            HStack {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                Button {
                    swap(&whiteBot, &blackBot)
                    store.triggerHaptic(.move)
                } label: {
                    Label("Swap Bots", systemImage: "arrow.up.arrow.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BrillyPalette.warpPurpleText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(BrillyPalette.warpPurple.opacity(0.18)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }

            // Black Bot + Black Opening
            botSideConfigRow(
                sideLabel: "BLACK BOT",
                sideColor: .black,
                bot: blackBot,
                opening: $blackOpening,
                courses: blackCourses,
                onPickBot: { activeBotPicker = .blackBot }
            )

            // Guide toggle when one side is Free Play and the other picked an opening
            if (whiteOpening == .freePlay) != (blackOpening == .freePlay) {
                Toggle(isOn: $guideOpponentOpening) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Guide into chosen opening")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Text("Lets the Free-Play bot follow setup moves so the chosen opening occurs.")
                            .font(.caption2)
                            .foregroundStyle(BrillyPalette.inkSecondary)
                    }
                }
                .tint(BrillyPalette.brillyTeal)
            }

            // Move Pace Selector
            HStack(spacing: 8) {
                Text("Pace")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkSecondary)
                Picker("Pace", selection: $pace) {
                    ForEach(ArenaPace.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var playVsBotSetupBody: some View {
        let botColor: PieceColor = humanSideChoice == .black ? .white : .black
        let botCourses = botColor == .white ? whiteCourses : blackCourses

        return VStack(alignment: .leading, spacing: 10) {
            // Opponent Bot Selector
            VStack(alignment: .leading, spacing: 5) {
                Text("OPPONENT BOT")
                    .font(.caption2.weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(BrillyPalette.brillyTeal)
                botSelectorButton(bot: playOpponentBot) {
                    activeBotPicker = .playOpponent
                }
            }

            // Play As White / Random / Black
            HStack(spacing: 8) {
                Text("Play As")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkSecondary)
                Picker("Play As", selection: $humanSideChoice) {
                    ForEach(HumanSideChoice.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: humanSideChoice) { _, newChoice in
                    if newChoice != .random {
                        // Clear incompatible opening if bot switched colors
                        if case .course(let cid, _) = playBotOpening {
                            let newBotSide: RepertoireSide = newChoice == .white ? .black : .white
                            if store.allCourses.first(where: { $0.id == cid })?.side != newBotSide {
                                playBotOpening = .freePlay
                            }
                        }
                    }
                }
            }

            // Optional Opening Book for the Bot
            if humanSideChoice != .random {
                VStack(alignment: .leading, spacing: 5) {
                    Text("BOT OPENING BOOK (\(botColor == .white ? "WHITE" : "BLACK"))")
                        .font(.caption2.weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                    openingMenuRow(selection: $playBotOpening, courses: botCourses)
                }
            }

            Toggle(isOn: $showEvalInPlay) {
                Text("Show Live Eval Bar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrillyPalette.inkPrimary)
            }
            .tint(BrillyPalette.brillyTeal)
        }
    }

    private func botSideConfigRow(
        sideLabel: String,
        sideColor: PieceColor,
        bot: BotProfile,
        opening: Binding<BotOpeningSelection>,
        courses: [OpeningCourse],
        onPickBot: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(sideColor == .white ? Color.white : Color(hex: 0x1E293B))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
                Text(sideLabel)
                    .font(.caption2.weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }

            botSelectorButton(bot: bot, action: onPickBot)
            openingMenuRow(selection: opening, courses: courses)
        }
    }

    private func botSelectorButton(bot: BotProfile, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: bot.sfSymbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(botTint(bot))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(botTint(bot).opacity(0.16)))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(bot.displayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                        Text(bot.eloLabel)
                            .font(.caption2.monospacedDigit().weight(.black))
                            .foregroundStyle(BrillyPalette.voidBg)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(botTint(bot)))
                    }
                    Text(bot.tagline)
                        .font(.caption2)
                        .foregroundStyle(BrillyPalette.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BrillyPalette.inkSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(botTint(bot).opacity(0.28), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func openingMenuRow(
        selection: Binding<BotOpeningSelection>,
        courses: [OpeningCourse]
    ) -> some View {
        let selectedCourse = selection.wrappedValue.courseId.flatMap { cid in
            courses.first(where: { $0.id == cid })
        }

        return HStack(spacing: 8) {
            Menu {
                Button {
                    selection.wrappedValue = .freePlay
                    store.triggerHaptic(.move)
                } label: {
                    Label("Free Play (No Book)", systemImage: selection.wrappedValue == .freePlay ? "checkmark" : "sparkles")
                }
                Divider()
                ForEach(courses) { course in
                    Button {
                        selection.wrappedValue = .course(courseId: course.id, lineId: nil)
                        store.triggerHaptic(.move)
                    } label: {
                        Label(
                            course.name,
                            systemImage: selection.wrappedValue.courseId == course.id ? "checkmark" : "book.closed"
                        )
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                    Text(selectedCourse?.name ?? "Opening: Free Play")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let course = selectedCourse, course.lines.count > 1 {
                let activeLineTitle = selection.wrappedValue.lineId.flatMap { lid in
                    course.lines.first(where: { $0.id == lid })?.title
                }
                Menu {
                    Button {
                        selection.wrappedValue = .course(courseId: course.id, lineId: nil)
                        store.triggerHaptic(.move)
                    } label: {
                        Label("All Lines (Auto)", systemImage: selection.wrappedValue.lineId == nil ? "checkmark" : "shuffle")
                    }
                    Divider()
                    ForEach(course.lines) { line in
                        Button {
                            selection.wrappedValue = .course(courseId: course.id, lineId: line.id)
                            store.triggerHaptic(.move)
                        } label: {
                            Label(
                                line.title,
                                systemImage: selection.wrappedValue.lineId == line.id ? "checkmark" : "arrow.triangle.branch"
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(activeLineTitle ?? "All Lines")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BrillyPalette.goldAmber)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(BrillyPalette.goldAmber.opacity(0.8))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BrillyPalette.goldAmber.opacity(0.14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(BrillyPalette.goldAmber.opacity(0.32), lineWidth: 1)
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    // MARK: - Player Banners & Status

    private func playerBanner(for color: PieceColor) -> some View {
        let isWhite = color == .white
        let isHuman = (mode == .playVsBot && color == resolvedHumanColor)
        let profile: BotProfile? = {
            if isHuman { return nil }
            if mode == .playVsBot { return playOpponentBot }
            return isWhite ? whiteBot : blackBot
        }()
        let name = isWhite ? effectiveWhiteName : effectiveBlackName
        let eloStr = profile?.eloLabel ?? "Human"
        let openingLabel: String? = {
            if isHuman { return nil }
            let sel: BotOpeningSelection
            if mode == .playVsBot {
                sel = playBotOpening
            } else {
                sel = isWhite ? whiteOpening : blackOpening
            }
            guard sel != .freePlay else { return nil }
            return BotOpeningBookResolver.label(for: sel, courses: store.allCourses)
        }()
        let isSideTurn = viewPly == nil && !isGameOver && board.turn == color
        let mat = ChessMath.materialBalance(in: displayedBoard)
        let adv = isWhite ? mat.whiteAdvantage : -mat.whiteAdvantage

        return HStack(spacing: 8) {
            Circle()
                .fill(isWhite ? Color.white : Color(hex: 0x1E293B))
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(isSideTurn ? BrillyPalette.brillyTeal : Color.white.opacity(0.45), lineWidth: isSideTurn ? 2 : 1))

            if let profile {
                Image(systemName: profile.sfSymbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(botTint(profile))
            } else {
                Image(systemName: "person.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BrillyPalette.brillyTeal)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BrillyPalette.inkPrimary)
                        .lineLimit(1)
                    Text(eloStr)
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(BrillyPalette.inkSecondary)
                }
                if let openingLabel {
                    Text("📖 \(openingLabel)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(BrillyPalette.brillyTeal)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if adv > 0 {
                Text("+\(adv)")
                    .font(.caption2.monospacedDigit().weight(.black))
                    .foregroundStyle(BrillyPalette.inkPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
            }

            if isSideTurn && isThinking {
                ProgressView()
                    .controlSize(.mini)
                    .tint(BrillyPalette.brillyTeal)
            } else if isSideTurn {
                Text("TURN")
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundStyle(BrillyPalette.voidBg)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(BrillyPalette.brillyTeal))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .brillySurface(store.surfaceStyle, cornerRadius: 14, tint: isSideTurn ? BrillyPalette.brillyTeal : nil)
    }

    private var statusRibbon: some View {
        HStack(spacing: 8) {
            Text(statusBanner)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isGameOver ? BrillyPalette.goldAmber : BrillyPalette.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if viewPly != nil {
                Button {
                    viewPly = nil
                } label: {
                    Text("Live")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(BrillyPalette.voidBg)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(BrillyPalette.brillyTeal))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .brillySurface(store.surfaceStyle, cornerRadius: 14, tint: isGameOver ? BrillyPalette.goldAmber : nil)
    }

    private var moveTape: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(moveHistory) { item in
                        let isWhiteMove = (item.id % 2 == 1)
                        let moveNum = (item.id + 1) / 2
                        let selected = (viewPly ?? moveHistory.count) == item.id
                        Button {
                            viewPly = (item.id == moveHistory.count) ? nil : item.id
                            store.triggerHaptic(.move)
                        } label: {
                            Text(isWhiteMove ? "\(moveNum). \(item.san)" : item.san)
                                .font(.caption.monospacedDigit().weight(selected ? .black : .semibold))
                                .foregroundStyle(selected ? BrillyPalette.voidBg : BrillyPalette.inkPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule().fill(selected ? BrillyPalette.brillyTeal : Color.white.opacity(0.07))
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: moveHistory.count) { _, newCount in
                if viewPly == nil, newCount > 0 {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(newCount, anchor: .trailing)
                    }
                }
            }
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 8) {
            if mode == .botVsBot {
                HStack(spacing: 8) {
                    Button {
                        if isMatchRunning {
                            pauseMatchLoop()
                        } else {
                            if isGameOver {
                                resetBoardForCurrentSetup(autoStart: true)
                            } else {
                                startBotVsBotLoop()
                            }
                        }
                    } label: {
                        Label(
                            isMatchRunning ? "Pause" : (isGameOver ? "Rematch" : (moveHistory.isEmpty ? "Start Match" : "Resume")),
                            systemImage: isMatchRunning ? "pause.fill" : "play.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(BrillyPalette.voidBg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(isMatchRunning ? BrillyPalette.blunderRose : BrillyPalette.brillyTeal))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(BrillyPressScaleStyle())

                    Button {
                        stepSingleBotMove()
                    } label: {
                        Label("Step", systemImage: "forward.frame.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                    .disabled(isMatchRunning || isThinking || isGameOver)
                    .opacity((isMatchRunning || isThinking || isGameOver) ? 0.45 : 1.0)
                }

                HStack(spacing: 8) {
                    Button {
                        takeOverFromCurrentPosition()
                    } label: {
                        Label("Take Over", systemImage: "hand.point.up.left.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.goldAmber)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                    .disabled(isGameOver)
                    .opacity(isGameOver ? 0.45 : 1.0)

                    Button {
                        orientation = orientation.opposite
                        store.triggerHaptic(.move)
                    } label: {
                        Label("Flip", systemImage: "arrow.up.arrow.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(BrillyPressScaleStyle())

                    Button {
                        resetBoardForCurrentSetup(autoStart: false)
                        store.triggerHaptic(.move)
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                }
            } else {
                // Play vs Bot controls
                HStack(spacing: 8) {
                    Button {
                        startNewPlayVsBotGame()
                    } label: {
                        Label(moveHistory.isEmpty ? "Start Game" : "New Game", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(BrillyPalette.voidBg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(BrillyPalette.brillyTeal))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(BrillyPressScaleStyle())

                    Button {
                        requestHint()
                    } label: {
                        Label("Hint", systemImage: "lightbulb.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(BrillyPalette.goldAmber)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.goldAmber)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                    .disabled(!isHumanTurn)
                    .opacity(isHumanTurn ? 1.0 : 0.45)
                }

                HStack(spacing: 8) {
                    Button {
                        takebackPlayMove()
                    } label: {
                        Label("Takeback", systemImage: "arrow.uturn.backward")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.warpPurple)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                    .disabled(moveHistory.isEmpty || isThinking)
                    .opacity((moveHistory.isEmpty || isThinking) ? 0.45 : 1.0)

                    Button {
                        orientation = orientation.opposite
                        store.triggerHaptic(.move)
                    } label: {
                        Label("Flip", systemImage: "arrow.up.arrow.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.inkPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.brillyTeal)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(BrillyPressScaleStyle())

                    Button {
                        resignPlayGame()
                    } label: {
                        Label("Resign", systemImage: "flag.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrillyPalette.blunderRose)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .brillyGlassPill(store.surfaceStyle, tint: BrillyPalette.blunderRose)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(BrillyPressScaleStyle())
                    .disabled(isGameOver || moveHistory.isEmpty)
                    .opacity((isGameOver || moveHistory.isEmpty) ? 0.45 : 1.0)
                }
            }
        }
    }

    // MARK: - Match Loop & Game Logic

    private func stopMatchLoop() {
        matchGeneration &+= 1
        arenaTask?.cancel()
        arenaTask = nil
        hintTask?.cancel()
        hintTask = nil
        isMatchRunning = false
        isThinking = false
        hintArrow = nil
    }

    private func pauseMatchLoop() {
        stopMatchLoop()
        if !isGameOver {
            statusBanner = "Paused at ply \(moveHistory.count). Tap Resume, Step, or Take Over."
        }
    }

    private func resetBoardForCurrentSetup(autoStart: Bool) {
        stopMatchLoop()
        board = ChessBoard()
        moveHistory = []
        viewPly = nil
        positionCounts = [board.positionKey: 1]
        liveScore = ChessMath.buildEngineScore(cpWhite: 0)
        resultString = "*"
        hintArrow = nil

        if mode == .playVsBot {
            switch humanSideChoice {
            case .white:  resolvedHumanColor = .white
            case .black:  resolvedHumanColor = .black
            case .random: resolvedHumanColor = Bool.random() ? .white : .black
            }
            orientation = resolvedHumanColor
            statusBanner = resolvedHumanColor == .white
                ? "Your move as White vs \(playOpponentBot.displayName) (\(playOpponentBot.eloLabel))."
                : "\(playOpponentBot.displayName) to open as White…"
            if autoStart && resolvedHumanColor == .black {
                triggerSingleBotReplyInPlayMode()
            }
        } else {
            orientation = .white
            statusBanner = "\(whiteBot.shortName) (\(whiteBot.eloLabel)) vs \(blackBot.shortName) (\(blackBot.eloLabel)) — ready!"
            if autoStart {
                startBotVsBotLoop()
            }
        }
    }

    private func startNewPlayVsBotGame() {
        withAnimation(.snappy(duration: 0.2)) {
            setupExpanded = false
        }
        resetBoardForCurrentSetup(autoStart: true)
        store.triggerHaptic(.move)
    }

    private func startBotVsBotLoop() {
        guard !isGameOver else { return }
        stopMatchLoop()
        viewPly = nil
        withAnimation(.snappy(duration: 0.2)) {
            setupExpanded = false
        }
        isMatchRunning = true
        let gen = matchGeneration
        let courses = store.allCourses
        let nnue = store.engine
        let swift = localSwiftEngine

        arenaTask = Task { @MainActor in
            while !Task.isCancelled && self.matchGeneration == gen && self.isMatchRunning && !self.isGameOver {
                let isWhite = self.board.turn == .white
                let activeBot = isWhite ? self.whiteBot : self.blackBot
                let activeOpening = isWhite ? self.whiteOpening : self.blackOpening
                let oppOpening = isWhite ? self.blackOpening : self.whiteOpening
                let curBoard = self.board
                let sanHist = self.moveHistory.map(\.san)
                let seen = self.positionCounts

                self.isThinking = true
                self.statusBanner = "\(activeBot.displayName) (\(isWhite ? "White" : "Black")) thinking…"

                let decision = await BotArenaEngine.chooseMove(
                    board: curBoard,
                    sanHistory: sanHist,
                    profile: activeBot,
                    openingSelection: activeOpening,
                    opponentOpeningSelection: oppOpening,
                    guideOpponentOpening: self.guideOpponentOpening,
                    courses: courses,
                    seenPositionCounts: seen,
                    nnueEngine: nnue,
                    swiftEngine: swift
                )

                guard !Task.isCancelled && self.matchGeneration == gen else { return }
                self.isThinking = false

                guard let decision else {
                    self.evaluateGameOver()
                    self.isMatchRunning = false
                    return
                }

                self.applyArenaMove(decision.move, sourceLabel: decision.source.badgeLabel, evalScore: decision.evalScore)
                if self.isGameOver {
                    self.isMatchRunning = false
                    return
                }

                let delayNs = self.pace.delayMs * 1_000_000
                try? await Task.sleep(nanoseconds: delayNs)
            }
        }
    }

    private func stepSingleBotMove() {
        guard !isGameOver && !isThinking else { return }
        stopMatchLoop()
        viewPly = nil
        withAnimation(.snappy(duration: 0.2)) {
            setupExpanded = false
        }
        let gen = matchGeneration
        let isWhite = board.turn == .white
        let activeBot = isWhite ? whiteBot : blackBot
        let activeOpening = isWhite ? whiteOpening : blackOpening
        let oppOpening = isWhite ? blackOpening : whiteOpening
        let curBoard = board
        let sanHist = moveHistory.map(\.san)
        let seen = positionCounts
        let courses = store.allCourses
        let nnue = store.engine
        let swift = localSwiftEngine

        isThinking = true
        statusBanner = "\(activeBot.displayName) calculating 1 move…"
        arenaTask = Task { @MainActor in
            let decision = await BotArenaEngine.chooseMove(
                board: curBoard,
                sanHistory: sanHist,
                profile: activeBot,
                openingSelection: activeOpening,
                opponentOpeningSelection: oppOpening,
                guideOpponentOpening: self.guideOpponentOpening,
                courses: courses,
                seenPositionCounts: seen,
                nnueEngine: nnue,
                swiftEngine: swift
            )
            guard !Task.isCancelled && self.matchGeneration == gen else { return }
            self.isThinking = false
            if let decision {
                self.applyArenaMove(decision.move, sourceLabel: decision.source.badgeLabel, evalScore: decision.evalScore)
            } else {
                self.evaluateGameOver()
            }
        }
    }

    private func takeOverFromCurrentPosition() {
        guard !isGameOver else { return }
        stopMatchLoop()
        // If user was inspecting an earlier ply, truncate to that ply cleanly
        if let ply = viewPly {
            truncateHistory(toPly: ply)
            viewPly = nil
        }
        let sideToMove = board.turn
        let oppBot = sideToMove == .white ? blackBot : whiteBot
        let oppOpening = sideToMove == .white ? blackOpening : whiteOpening

        suppressNextModeReset = true
        mode = .playVsBot
        resolvedHumanColor = sideToMove
        humanSideChoice = sideToMove == .white ? .white : .black
        playOpponentBot = oppBot
        playBotOpening = oppOpening
        orientation = sideToMove
        setupExpanded = false
        statusBanner = "You took over as \(sideToMove.displayName) vs \(oppBot.displayName) (\(oppBot.eloLabel))!"
        store.triggerHaptic(.success)
    }

    private func handleHumanMove(_ move: ChessMove) {
        guard isHumanTurn else { return }
        hintTask?.cancel()
        hintArrow = nil
        applyArenaMove(move, sourceLabel: "You", evalScore: nil)
        if !isGameOver {
            triggerSingleBotReplyInPlayMode()
        }
    }

    private func triggerSingleBotReplyInPlayMode() {
        guard mode == .playVsBot && !isGameOver && board.turn != resolvedHumanColor else { return }
        stopMatchLoop()
        let gen = matchGeneration
        let curBoard = board
        let sanHist = moveHistory.map(\.san)
        let seen = positionCounts
        let bot = playOpponentBot
        let botBook = playBotOpening
        let courses = store.allCourses
        let nnue = store.engine
        let swift = localSwiftEngine

        isThinking = true
        statusBanner = "\(bot.displayName) (\(bot.eloLabel)) thinking…"
        arenaTask = Task { @MainActor in
            // Tiny natural beat so human move animates smoothly before bot responds
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled && self.matchGeneration == gen else { return }

            let decision = await BotArenaEngine.chooseMove(
                board: curBoard,
                sanHistory: sanHist,
                profile: bot,
                openingSelection: botBook,
                opponentOpeningSelection: .freePlay,
                guideOpponentOpening: false,
                courses: courses,
                seenPositionCounts: seen,
                nnueEngine: nnue,
                swiftEngine: swift
            )
            guard !Task.isCancelled && self.matchGeneration == gen else { return }
            self.isThinking = false
            if let decision {
                self.applyArenaMove(decision.move, sourceLabel: decision.source.badgeLabel, evalScore: decision.evalScore)
            } else {
                self.evaluateGameOver()
            }
        }
    }

    private func applyArenaMove(_ move: ChessMove, sourceLabel: String, evalScore: EngineScore?) {
        guard let applied = try? board.apply(move) else { return }
        let ply = moveHistory.count + 1
        let key = board.positionKey
        positionCounts[key, default: 0] += 1

        if let evalScore {
            liveScore = evalScore
        }

        moveHistory.append(ArenaMoveRecord(
            id: ply,
            san: applied.san,
            uci: move.uci,
            from: move.from,
            to: move.to,
            afterFen: board.fen,
            sourceLabel: sourceLabel,
            evalScore: evalScore
        ))

        let moveNum = (ply + 1) / 2
        let prefix = (ply % 2 == 1) ? "\(moveNum)." : "\(moveNum)..."
        statusBanner = "\(prefix) \(applied.san) · \(sourceLabel)"

        if board.isInCheck() {
            store.triggerHaptic(.success)
        } else {
            store.triggerHaptic(.move)
        }

        evaluateGameOver()
    }

    private func evaluateGameOver() {
        switch board.outcome {
        case .checkmate(let winner):
            resultString = winner == .white ? "1-0" : "0-1"
            let winName = winner == .white ? effectiveWhiteName : effectiveBlackName
            statusBanner = "Checkmate! \(winName) wins (\(resultString))."
            liveScore = ChessMath.buildEngineScore(
                cpWhite: winner == .white ? 10000 : -10000,
                mateWhite: 0,
                isCheckmate: true,
                winnerColor: winner
            )
            store.triggerHaptic(.success)
        case .stalemate:
            resultString = "1/2-1/2"
            statusBanner = "Draw by stalemate (1/2-1/2)."
            liveScore = ChessMath.buildEngineScore(cpWhite: 0)
        case .insufficientMaterial:
            resultString = "1/2-1/2"
            statusBanner = "Draw by insufficient material (1/2-1/2)."
            liveScore = ChessMath.buildEngineScore(cpWhite: 0)
        case .fiftyMoveRule:
            resultString = "1/2-1/2"
            statusBanner = "Draw by 50-move rule (1/2-1/2)."
            liveScore = ChessMath.buildEngineScore(cpWhite: 0)
        case .ongoing:
            if (positionCounts[board.positionKey] ?? 0) >= 3 {
                resultString = "1/2-1/2"
                statusBanner = "Draw by 3-fold repetition (1/2-1/2)."
                liveScore = ChessMath.buildEngineScore(cpWhite: 0)
            } else if moveHistory.count >= 220 {
                resultString = "1/2-1/2"
                statusBanner = "Draw reached (move limit)."
                liveScore = ChessMath.buildEngineScore(cpWhite: 0)
            }
        }
    }

    private func truncateHistory(toPly ply: Int) {
        let clamped = max(0, min(ply, moveHistory.count))
        moveHistory = Array(moveHistory.prefix(clamped))
        board = ChessBoard()
        positionCounts = [board.positionKey: 1]
        for rec in moveHistory {
            if let m = ChessMove(uci: rec.uci), (try? board.apply(m)) != nil {
                positionCounts[board.positionKey, default: 0] += 1
            }
        }
        resultString = "*"
        liveScore = moveHistory.last(where: { $0.evalScore != nil })?.evalScore ?? ChessMath.buildEngineScore(cpWhite: 0)
    }

    private func takebackPlayMove() {
        guard !moveHistory.isEmpty && !isThinking else { return }
        stopMatchLoop()
        viewPly = nil
        // Step back 2 plies if it's currently the human's turn (undo bot + human move), else 1 ply
        let step = (board.turn == resolvedHumanColor && moveHistory.count >= 2) ? 2 : 1
        truncateHistory(toPly: moveHistory.count - step)
        statusBanner = "Took back move — your turn as \(resolvedHumanColor.displayName)."
        store.triggerHaptic(.move)
        if board.turn != resolvedHumanColor && !isGameOver {
            triggerSingleBotReplyInPlayMode()
        }
    }

    private func resignPlayGame() {
        guard mode == .playVsBot && !isGameOver else { return }
        stopMatchLoop()
        resultString = resolvedHumanColor == .white ? "0-1" : "1-0"
        statusBanner = "You resigned (\(resultString)). Tap Analyze Game to review or New Game to rematch!"
        store.triggerHaptic(.error)
    }

    private func requestHint() {
        guard isHumanTurn else { return }
        hintTask?.cancel()
        let fen = board.fen
        let swift = localSwiftEngine
        statusBanner = "Calculating hint…"
        hintTask = Task { @MainActor in
            if let ev = try? await swift.analyze(fen: fen, depth: 5, multiPV: 1, maxTimeMs: 300),
               !Task.isCancelled,
               let m = ChessMove(uci: ev.bestMoveUci) {
                let san = ChessMath.uciLineToSAN(fen: fen, uciMoves: [m.uci], maxMoves: 1).first ?? m.uci
                hintArrow = BoardArrow(from: m.from.algebraic, to: m.to.algebraic, color: .best)
                statusBanner = "Hint: Consider \(san) (\(ev.score.display))"
                store.triggerHaptic(.move)
            }
        }
    }

    private func analyzeCurrentArenaGame() {
        stopMatchLoop()
        let sanMoves = moveHistory.map(\.san)
        guard !sanMoves.isEmpty else { return }

        let openingHint: String? = {
            if mode == .botVsBot {
                let w = whiteOpening != .freePlay ? BotOpeningBookResolver.label(for: whiteOpening, courses: store.allCourses) : nil
                let b = blackOpening != .freePlay ? BotOpeningBookResolver.label(for: blackOpening, courses: store.allCourses) : nil
                if let w, let b { return "\(w) vs \(b)" }
                return w ?? b
            } else {
                return playBotOpening != .freePlay ? BotOpeningBookResolver.label(for: playBotOpening, courses: store.allCourses) : nil
            }
        }()

        let record = BotArenaEngine.buildGameRecord(
            sanMoves: sanMoves,
            whiteName: effectiveWhiteName,
            whiteElo: effectiveWhiteElo,
            blackName: effectiveBlackName,
            blackElo: effectiveBlackElo,
            resultString: resultString,
            userColor: mode == .playVsBot ? resolvedHumanColor : nil,
            openingHintName: openingHint
        )
        store.openBotArenaGameInAnalyze(record)
        onOpenInAnalyze?()
    }

    // MARK: - Picker & Tint Helpers

    private func pickerTitle(for target: PickerTarget) -> String {
        switch target {
        case .playOpponent: return "Choose Opponent Bot"
        case .whiteBot:     return "Choose White Bot"
        case .blackBot:     return "Choose Black Bot"
        }
    }

    private func bindingForPicker(_ target: PickerTarget) -> Binding<BotProfile> {
        switch target {
        case .playOpponent: return $playOpponentBot
        case .whiteBot:     return $whiteBot
        case .blackBot:     return $blackBot
        }
    }

    private func botTint(_ bot: BotProfile) -> Color {
        switch bot {
        case .cadet400, .novice700:       return Color(hex: 0x22C55E)
        case .club1000, .tactician1350:   return BrillyPalette.brillyTeal
        case .challenger1700, .master2100: return BrillyPalette.goldAmber
        case .fast, .balanced, .deep:     return BrillyPalette.warpPurpleText
        case .ultra:                      return Color(hex: 0xF472B6)
        case .hybrid:                     return Color(hex: 0x38BDF8)
        }
    }
}

// MARK: - Bot Profile Picker Sheet

private struct BotProfilePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    @Binding var selected: BotProfile
    let hasProAccess: Bool
    let surfaceStyle: SurfaceStyle
    let onTapLockedPro: (BotProfile) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                CosmicVoidBackdrop(style: surfaceStyle)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(BotProfile.TierGroup.allCases, id: \.self) { group in
                            let bots = BotProfile.allCases.filter { $0.tierGroup == group }
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.rawValue.uppercased())
                                    .font(.caption2.weight(.black))
                                    .tracking(0.9)
                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                    .padding(.horizontal, 4)

                                ForEach(bots) { bot in
                                    let isSelected = selected == bot
                                    let unlocked = bot.isUnlocked(hasProAccess: hasProAccess)
                                    Button {
                                        if !unlocked {
                                            onTapLockedPro(bot)
                                            return
                                        }
                                        selected = bot
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: bot.sfSymbol)
                                                .font(.title3.weight(.bold))
                                                .foregroundStyle(isSelected ? BrillyPalette.voidBg : BrillyPalette.brillyTeal)
                                                .frame(width: 38, height: 38)
                                                .background(
                                                    Circle().fill(isSelected ? BrillyPalette.brillyTeal : BrillyPalette.brillyTeal.opacity(0.14))
                                                )

                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(bot.displayName)
                                                        .font(.subheadline.weight(.bold))
                                                        .foregroundStyle(BrillyPalette.inkPrimary)
                                                    Text("\(bot.eloLabel) Elo")
                                                        .font(.caption2.monospacedDigit().weight(.black))
                                                        .foregroundStyle(BrillyPalette.brillyTeal)
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Capsule().fill(BrillyPalette.brillyTeal.opacity(0.14)))
                                                    if !unlocked {
                                                        Text("PRO")
                                                            .font(.system(size: 9, weight: .black, design: .rounded))
                                                            .foregroundStyle(BrillyPalette.voidBg)
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Capsule().fill(BrillyPalette.warpPurpleText))
                                                    }
                                                }
                                                Text(bot.tagline)
                                                    .font(.caption)
                                                    .foregroundStyle(BrillyPalette.inkSecondary)
                                                    .multilineTextAlignment(.leading)
                                            }
                                            Spacer(minLength: 4)
                                            if !unlocked {
                                                Image(systemName: "lock.fill")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(BrillyPalette.warpPurpleText)
                                            } else if isSelected {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.title3)
                                                    .foregroundStyle(BrillyPalette.brillyTeal)
                                            }
                                        }
                                        .padding(12)
                                        .brillySurface(surfaceStyle, cornerRadius: 16, tint: isSelected ? BrillyPalette.brillyTeal : nil)
                                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(title)
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
}
