import Foundation
import SwiftUI
import Observation
import BrillyDerCore
#if canImport(UIKit)
import UIKit
#endif

public enum BrillyTab: String, CaseIterable, Hashable, Identifiable {
    case train
    case games
    case analyze
    case openings
    case insights

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .train: return "Train"
        case .games: return "Games"
        case .analyze: return "Analyze"
        case .openings: return "Openings"
        case .insights: return "Insights"
        }
    }

    public var systemImage: String {
        switch self {
        case .train: return "bolt.heart.fill"
        case .games: return "list.bullet.rectangle.portrait"
        case .analyze: return "sparkles"
        case .openings: return "book.closed.fill"
        case .insights: return "chart.xyaxis.line"
        }
    }
}

public enum TrainSubMode: String, CaseIterable, Hashable, Identifiable {
    case daily = "15m Coach"
    case woodpecker = "Woodpecker"
    case conversion = "Convert"
    case mistakes = "Mistakes"
    case labs = "Labs"

    public var id: String { rawValue }
}

@Observable
@MainActor
public final class BrillyAppStore {
    // MARK: - Navigation & Preferences
    public var selectedTab: BrillyTab = .train
    public var selectedTrainMode: TrainSubMode = .daily
    public var showingSettings: Bool = false
    public var showingVault: Bool = false
    public var pendingAnalyzePly: Int? = nil
    public var preferredEndgameCategory: EndgameCategory? = nil
    public var preferredMotifFilter: String? = nil

    public var surfaceStyle: SurfaceStyle {
        didSet { UserDefaults.standard.set(surfaceStyle.rawValue, forKey: "brilly_surface_style") }
    }
    public var vibeMode: VibeMode {
        didSet { UserDefaults.standard.set(vibeMode.rawValue, forKey: "brilly_vibe_mode") }
    }
    public var boardTheme: BoardThemeID {
        didSet { UserDefaults.standard.set(boardTheme.rawValue, forKey: "brilly_board_theme") }
    }
    public var analysisPreset: AnalysisDepthPreset {
        didSet { UserDefaults.standard.set(analysisPreset.rawValue, forKey: "brilly_analysis_preset") }
    }
    public var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "brilly_haptics_enabled") }
    }
    public var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "brilly_sound_enabled") }
    }
    public var celebrationsEnabled: Bool {
        didSet { UserDefaults.standard.set(celebrationsEnabled, forKey: "brilly_celebrations_enabled") }
    }
    public var activeCelebration: CelebrationEvent? = nil

    // MARK: - Sync & Scout State
    public var syncPlatform: GameSource = .lichess
    public var lichessUsername: String = ""
    public var chessComUsername: String = ""
    public var recentGames: [GameRecord] = []
    public var isSyncing: Bool = false
    public var syncErrorMessage: String? = nil

    public var scoutOpponent: String = ""
    public var scoutGames: [GameRecord] = []
    public var isScouting: Bool = false

    // MARK: - Single & Batch Analysis State
    public var analyzedGames: [AnalyzedGame] = []
    public var activeAnalyzedGame: AnalyzedGame? = nil
    public var activeSandboxFen: String? = nil
    public var isAnalyzing: Bool = false
    public var analysisProgress: Double = 0
    public var analysisStatusText: String = ""
    public var analyzingMatchupTitle: String = ""

    public var isBatchAnalyzing: Bool = false
    public var batchCompletedGames: Int = 0
    public var batchTotalGames: Int = 0
    public var batchProgress: Double = 0
    public var batchCurrentLabel: String = ""

    // MARK: - Openings, Vault & Training State
    public var starterCourses: [OpeningCourse] = []
    public var customCourses: [OpeningCourse] = []
    public var fsrsCards: [FsrsOpeningCard] = []
    public var bookmarks: [SavedPositionBookmark] = []
    public var dailyDuration: DailyDurationMinutes = .fifteen
    public var dailyStreakDays: Int = 0
    public var lastDailyCompletedDate: String? = nil
    public var woodpeckerCycle: WoodpeckerCycleRecord? = nil
    public var masteredEndgameIds: Set<String> = []
    public var convertedAdvantageIds: Set<String> = []
    public var boardVisionBestScore: Int = 0
    public var puzzleRushBlitzBest: Int = 0
    public var puzzleRushSurvivalBest: Int = 0

    // MARK: - Engine & Storage
    public let engine = BrillyNativeEngine()
    private let vault = LocalVaultStore()
    private var analysisTask: Task<Void, Never>? = nil
    private var batchTask: Task<Void, Never>? = nil

    // MARK: - Computed Properties

    public var activeUsername: String? {
        let raw = syncPlatform == .chesscom ? chessComUsername : lichessUsername
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var allCourses: [OpeningCourse] {
        starterCourses + customCourses
    }

    public var unanalyzedRecentGames: [GameRecord] {
        let doneIds = Set(analyzedGames.map(\.id))
        return recentGames.filter { !doneIds.contains($0.id) }
    }

    public var mistakeDeck: [MistakePuzzle] {
        GameAnalyzer.extractMistakePuzzles(from: analyzedGames, username: activeUsername)
    }

    public var dueOpeningCount: Int {
        fsrsCards.filter { FSRS6Scheduler.isCardDue($0) }.count
    }

    public var dailyWorkoutPlan: DailyWorkoutPlan {
        DailyCoachPlanner.buildPlan(
            duration: dailyDuration,
            fsrsCards: fsrsCards,
            mistakeDeck: mistakeDeck
        )
    }

    public var insights: InsightsSnapshot {
        GameAnalyzer.computeInsights(analyzedGames: analyzedGames, username: activeUsername)
    }

    public var advancedInsights: AdvancedInsightsReport {
        AdvancedInsightsService.buildReport(analyzedGames: analyzedGames, username: activeUsername)
    }

    public var vaultCollection: VaultCollection {
        VaultService.buildVault(from: analyzedGames, username: activeUsername)
    }

    public var blownLeads: [BlownLeadPosition] {
        WoodpeckerAndConversion.extractBlownLeads(from: analyzedGames, username: activeUsername)
    }

    public var userEndgameDrills: [EndgameDrill] {
        EndgameLibrary.extractUserEndgameDrills(from: analyzedGames, username: activeUsername)
    }

    public var scoutGameplan: ScoutGameplan? {
        AdvancedInsightsService.buildScoutGameplan(opponent: scoutOpponent, games: scoutGames)
    }

    public init() {
        let defaults = UserDefaults.standard
        self.surfaceStyle = SurfaceStyle(rawValue: defaults.string(forKey: "brilly_surface_style") ?? "") ?? .liquidGlass
        self.vibeMode = VibeMode(rawValue: defaults.string(forKey: "brilly_vibe_mode") ?? "") ?? .cosmic
        self.boardTheme = BoardThemeID(rawValue: defaults.string(forKey: "brilly_board_theme") ?? "") ?? .slate
        self.analysisPreset = AnalysisDepthPreset(rawValue: defaults.integer(forKey: "brilly_analysis_preset")) ?? .balanced
        self.hapticsEnabled = defaults.object(forKey: "brilly_haptics_enabled") as? Bool ?? true
        self.soundEnabled = defaults.object(forKey: "brilly_sound_enabled") as? Bool ?? true
        self.celebrationsEnabled = defaults.object(forKey: "brilly_celebrations_enabled") as? Bool ?? true

        self.starterCourses = (try? CourseRepository.loadStarterCourses()) ?? []
        self.recentGames = LichessClient.sampleGames()

        Task {
            await hydrateFromDisk()
        }
    }

    // MARK: - Copy & Haptics

    public func copy(cosmic: String, classic: String) -> String {
        vibeMode == .cosmic ? cosmic : classic
    }

    public func triggerHaptic(_ style: HapticKind) {
        if soundEnabled {
            switch style {
            case .move: BrillySoundEngine.shared.play(.move)
            case .capture: BrillySoundEngine.shared.play(.capture)
            case .success: BrillySoundEngine.shared.play(.sonar)
            case .error: BrillySoundEngine.shared.play(.blunder)
            }
        }
        guard hapticsEnabled else { return }
        #if canImport(UIKit) && os(iOS)
        switch style {
        case .move:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .capture:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #endif
    }

    public func triggerCelebration(_ kind: CelebrationEvent.Kind) {
        if soundEnabled {
            BrillySoundEngine.shared.play(kind == .brilliant ? .brilliant : .blunder)
        }
        guard celebrationsEnabled else { return }
        let event = CelebrationEvent(kind: kind, vibe: vibeMode)
        withAnimation(.spring(duration: 0.35)) {
            activeCelebration = event
        }
        let id = event.id
        Task {
            try? await Task.sleep(for: .milliseconds(kind == .brilliant ? 2600 : 1900))
            if activeCelebration?.id == id {
                withAnimation(.easeOut(duration: 0.25)) {
                    activeCelebration = nil
                }
            }
        }
    }

    public enum HapticKind {
        case move, capture, success, error
    }

    // MARK: - Persistence & Backup

    private func hydrateFromDisk() async {
        let snap = await vault.load()
        self.analyzedGames = snap.analyzedGames
        self.customCourses = snap.customCourses
        self.bookmarks = snap.bookmarks
        self.dailyStreakDays = snap.dailyStreakDays
        self.lastDailyCompletedDate = snap.lastDailyCompletedDate
        self.lichessUsername = snap.lichessUsername
        self.chessComUsername = snap.chessComUsername
        self.woodpeckerCycle = snap.woodpeckerCycle
        self.masteredEndgameIds = Set(snap.masteredEndgameIds)
        self.convertedAdvantageIds = Set(snap.convertedAdvantageIds)
        self.boardVisionBestScore = snap.boardVisionBestScore
        self.puzzleRushBlitzBest = snap.puzzleRushBlitzBest
        self.puzzleRushSurvivalBest = snap.puzzleRushSurvivalBest

        if let first = snap.analyzedGames.first {
            self.activeAnalyzedGame = first
        }
        // Hydrate Games tab offline from analyzed games if we have them
        if !snap.analyzedGames.isEmpty {
            let cachedRecords = snap.analyzedGames.map(\.game)
            let sampleIds = Set(recentGames.map(\.id))
            let newOnes = cachedRecords.filter { !sampleIds.contains($0.id) }
            if !newOnes.isEmpty {
                self.recentGames = newOnes + recentGames
            }
        }

        rehydrateFsrsCards(existing: snap.fsrsCards)
    }

    private func rehydrateFsrsCards(existing: [FsrsOpeningCard]) {
        var existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.cardId, $0) })
        var hydrated: [FsrsOpeningCard] = []
        for (courseIdx, course) in allCourses.enumerated() {
            for (lineIdx, line) in course.lines.enumerated() {
                let shouldUnlock = ((courseIdx == 0 || courseIdx == 1) && lineIdx == 0) || course.source == "pgn"
                if let cards = try? CourseRepository.hydrateLineCards(
                    courseId: course.id,
                    side: course.side,
                    line: line,
                    existingById: existingById,
                    unlocked: shouldUnlock
                ) {
                    hydrated.append(contentsOf: cards)
                    for c in cards { existingById[c.cardId] = c }
                }
            }
        }
        self.fsrsCards = hydrated
    }

    public func persistToDisk() {
        let snap = currentSnapshot()
        Task {
            try? await vault.save(snap)
        }
    }

    private func currentSnapshot() -> VaultSnapshot {
        VaultSnapshot(
            analyzedGames: analyzedGames,
            fsrsCards: fsrsCards,
            customCourses: customCourses,
            bookmarks: bookmarks,
            dailyStreakDays: dailyStreakDays,
            lastDailyCompletedDate: lastDailyCompletedDate,
            lichessUsername: lichessUsername,
            chessComUsername: chessComUsername,
            woodpeckerCycle: woodpeckerCycle,
            masteredEndgameIds: Array(masteredEndgameIds),
            convertedAdvantageIds: Array(convertedAdvantageIds),
            boardVisionBestScore: boardVisionBestScore,
            puzzleRushBlitzBest: puzzleRushBlitzBest,
            puzzleRushSurvivalBest: puzzleRushSurvivalBest
        )
    }

    public func exportBackupData() throws -> Data {
        try LocalVaultStore.exportBackupJSON(from: currentSnapshot())
    }

    public func importBackupData(_ data: Data) throws -> BackupImportSummary {
        let (merged, summary) = try LocalVaultStore.mergeBackupJSONWithSummary(data, into: currentSnapshot())
        self.analyzedGames = merged.analyzedGames
        self.customCourses = merged.customCourses
        self.bookmarks = merged.bookmarks
        self.masteredEndgameIds = Set(merged.masteredEndgameIds)
        self.convertedAdvantageIds = Set(merged.convertedAdvantageIds)
        self.dailyStreakDays = merged.dailyStreakDays
        self.lastDailyCompletedDate = merged.lastDailyCompletedDate
        self.boardVisionBestScore = merged.boardVisionBestScore
        self.puzzleRushBlitzBest = merged.puzzleRushBlitzBest
        self.puzzleRushSurvivalBest = merged.puzzleRushSurvivalBest
        self.lichessUsername = merged.lichessUsername
        self.chessComUsername = merged.chessComUsername
        // Hydrate Games tab offline with imported analyzed games
        if !merged.analyzedGames.isEmpty {
            let existingIds = Set(recentGames.map(\.id))
            let importedRecords = merged.analyzedGames.map(\.game).filter { !existingIds.contains($0.id) }
            if !importedRecords.isEmpty {
                recentGames = importedRecords + recentGames
            }
            if activeAnalyzedGame == nil {
                activeAnalyzedGame = merged.analyzedGames.first
            }
        }
        rehydrateFsrsCards(existing: merged.fsrsCards)
        persistToDisk()
        triggerHaptic(.success)
        return summary
    }

    public func deleteCustomCourse(id: String) {
        customCourses.removeAll { $0.id == id }
        fsrsCards.removeAll { $0.courseId == id }
        persistToDisk()
    }

    public func recordPuzzleRushScore(_ score: Int, survival: Bool) {
        if survival {
            if score > puzzleRushSurvivalBest {
                puzzleRushSurvivalBest = score
                persistToDisk()
            }
        } else {
            if score > puzzleRushBlitzBest {
                puzzleRushBlitzBest = score
                persistToDisk()
            }
        }
    }

    public func importLichessGameURL(_ urlOrId: String) async {
        isSyncing = true
        syncErrorMessage = nil
        defer { isSyncing = false }
        do {
            let record = try await LichessClient.fetchSingleGame(urlOrId: urlOrId, preferredUsername: activeUsername)
            if !recentGames.contains(where: { $0.id == record.id }) {
                recentGames.insert(record, at: 0)
            }
            startAnalysis(for: record)
        } catch {
            syncErrorMessage = error.localizedDescription
            triggerHaptic(.error)
        }
    }

    // MARK: - Sync & Scout Actions

    public func syncRecentGames() async {
        isSyncing = true
        syncErrorMessage = nil
        defer { isSyncing = false }

        do {
            let fetched: [GameRecord]
            if syncPlatform == .chesscom {
                fetched = try await ChessComClient.fetchRecentGames(username: chessComUsername, maxGames: 30)
            } else {
                fetched = try await LichessClient.fetchRecentGames(username: lichessUsername, maxGames: 30)
            }
            if !fetched.isEmpty {
                recentGames = fetched
                triggerHaptic(.success)
            } else {
                syncErrorMessage = "No recent standard games found for that handle."
            }
            persistToDisk()
        } catch {
            syncErrorMessage = error.localizedDescription
            triggerHaptic(.error)
        }
    }

    public func runScout(opponent: String, platform: GameSource) async {
        let clean = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        isScouting = true
        syncErrorMessage = nil
        defer { isScouting = false }

        do {
            let fetched: [GameRecord]
            if platform == .chesscom {
                fetched = try await ChessComClient.fetchRecentGames(username: clean, maxGames: 25)
            } else {
                fetched = try await LichessClient.fetchRecentGames(username: clean, maxGames: 25)
            }
            scoutOpponent = clean
            scoutGames = fetched
            selectedTab = .insights
            triggerHaptic(.success)
        } catch {
            syncErrorMessage = "Scout failed: \(error.localizedDescription)"
            triggerHaptic(.error)
        }
    }

    public func clearScout() {
        scoutOpponent = ""
        scoutGames = []
    }

    public func importAndAnalyzePGN(_ pgn: String) {
        do {
            let record = try LichessClient.parsePastedPGN(pgn, preferredUsername: activeUsername)
            if !recentGames.contains(where: { $0.id == record.id }) {
                recentGames.insert(record, at: 0)
            }
            startAnalysis(for: record)
        } catch {
            syncErrorMessage = error.localizedDescription
            triggerHaptic(.error)
        }
    }

    public func openCustomFEN(_ fen: String) {
        activeSandboxFen = fen
        selectedTab = .analyze
        triggerHaptic(.move)
    }

    // MARK: - Single & Batch Game Analysis

    public func startAnalysis(for game: GameRecord, jumpToPly: Int? = nil) {
        activeSandboxFen = nil
        if let cached = analyzedGames.first(where: { $0.id == game.id }) {
            activeAnalyzedGame = cached
            pendingAnalyzePly = jumpToPly
            selectedTab = .analyze
            return
        }

        batchTask?.cancel()
        isBatchAnalyzing = false
        analysisTask?.cancel()
        isAnalyzing = true
        analysisProgress = 0
        analyzingMatchupTitle = "\(game.white.name) vs \(game.black.name)"
        analysisStatusText = copy(cosmic: "Scanning trajectory…", classic: "Analyzing game…")
        selectedTab = .analyze

        let preset = analysisPreset
        let engineRef = engine

        analysisTask = Task.detached(priority: .userInitiated) {
            do {
                let result = try await GameAnalyzer.analyze(
                    game: game,
                    engine: engineRef,
                    preset: preset
                ) { completed, total in
                    Task { @MainActor in
                        self.analysisProgress = Double(completed) / Double(max(1, total))
                        self.analysisStatusText = "Ply \(completed) / \(total)"
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.analyzedGames.removeAll { $0.id == result.id }
                    self.analyzedGames.insert(result, at: 0)
                    self.activeAnalyzedGame = result
                    self.pendingAnalyzePly = jumpToPly
                    self.isAnalyzing = false
                    self.analysisProgress = 1.0
                    self.triggerHaptic(.success)
                    self.persistToDisk()
                }
            } catch {
                if !Task.isCancelled {
                    await MainActor.run {
                        self.isAnalyzing = false
                        self.syncErrorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    public func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
    }

    public func startBatchAnalysis(maxCount: Int) {
        let targets = Array(unanalyzedRecentGames.prefix(maxCount))
        guard !targets.isEmpty else { return }

        analysisTask?.cancel()
        isAnalyzing = false
        batchTask?.cancel()

        isBatchAnalyzing = true
        batchCompletedGames = 0
        batchTotalGames = targets.count
        batchProgress = 0.02
        batchCurrentLabel = "Game 1 of \(targets.count) · Preparing…"
        triggerHaptic(.move)

        let preset: AnalysisDepthPreset = .fast
        let engineRef = engine
        let totalGames = targets.count

        batchTask = Task.detached(priority: .userInitiated) {
            for (idx, game) in targets.enumerated() {
                if Task.isCancelled { break }
                let matchup = "\(game.white.name) vs \(game.black.name)"
                await MainActor.run {
                    self.batchCurrentLabel = "Game \(idx + 1)/\(totalGames) · \(matchup)"
                }
                do {
                    let result = try await GameAnalyzer.analyze(
                        game: game,
                        engine: engineRef,
                        preset: preset
                    ) { donePlies, totalPlies in
                        let sub = Double(donePlies) / Double(max(1, totalPlies))
                        let overall = (Double(idx) + sub) / Double(max(1, totalGames))
                        Task { @MainActor in
                            self.batchProgress = overall
                            self.batchCurrentLabel = "Game \(idx + 1)/\(totalGames) · Ply \(donePlies)/\(totalPlies)"
                        }
                    }
                    if Task.isCancelled { break }
                    await MainActor.run {
                        self.analyzedGames.removeAll { $0.id == result.id }
                        self.analyzedGames.insert(result, at: 0)
                        if self.activeAnalyzedGame == nil {
                            self.activeAnalyzedGame = result
                        }
                        self.batchCompletedGames = idx + 1
                        self.batchProgress = Double(idx + 1) / Double(max(1, totalGames))
                        self.persistToDisk()
                    }
                } catch {
                    if Task.isCancelled { break }
                }
            }
            await MainActor.run {
                self.isBatchAnalyzing = false
                self.batchCurrentLabel = ""
                if !Task.isCancelled {
                    self.batchProgress = 1.0
                    self.triggerHaptic(.success)
                }
            }
        }
    }

    public func cancelBatchAnalysis() {
        batchTask?.cancel()
        batchTask = nil
        isBatchAnalyzing = false
        batchProgress = 0
        batchCurrentLabel = ""
    }

    public func openGameAtPly(gameId: String, ply: Int) {
        showingVault = false
        activeSandboxFen = nil
        if let ag = analyzedGames.first(where: { $0.id == gameId }) {
            activeAnalyzedGame = ag
            pendingAnalyzePly = ply
            selectedTab = .analyze
        }
    }

    // MARK: - Bot Engine Helper

    public func computeBotReply(fen: String, depth: Int = 4) async -> ChessMove? {
        guard let eval = try? await engine.analyze(fen: fen, depth: depth, multiPV: 1, maxTimeMs: 350),
              let move = ChessMove(uci: eval.bestMoveUci) else {
            return nil
        }
        return move
    }

    // MARK: - FSRS, Courses, Woodpecker, Endgame & Bookmarks

    public func recordOpeningAttempt(cardId: String, attempt: OpeningAttemptInput) -> OpeningReviewResult? {
        guard let idx = fsrsCards.firstIndex(where: { $0.cardId == cardId }) else { return nil }
        let result = FSRS6Scheduler.review(card: fsrsCards[idx], attempt: attempt)
        fsrsCards[idx] = result.card
        triggerHaptic(attempt.correct ? .success : .error)
        persistToDisk()
        return result
    }

    public func boostCardDueNow(cardId: String) {
        guard let idx = fsrsCards.firstIndex(where: { $0.cardId == cardId }) else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        fsrsCards[idx].unlocked = true
        fsrsCards[idx].dueAt = nowMs - 1_000
        triggerHaptic(.success)
        persistToDisk()
    }

    public func unlockLine(courseId: String, lineId: String) {
        var changed = false
        for i in fsrsCards.indices where fsrsCards[i].courseId == courseId && fsrsCards[i].lineId == lineId {
            if !fsrsCards[i].unlocked {
                fsrsCards[i].unlocked = true
                changed = true
            }
        }
        if changed { persistToDisk() }
    }

    public func importCustomCourse(name: String, side: RepertoireSide, pgn: String) throws {
        let course = try RepertoireTreeService.importCourseFromPGN(name: name, side: side, pgn: pgn)
        customCourses.insert(course, at: 0)
        rehydrateFsrsCards(existing: fsrsCards)
        triggerHaptic(.success)
        persistToDisk()
    }

    public func startWoodpeckerCycle(batchSize: Int) {
        if let cycle = WoodpeckerAndConversion.createFrozenCycle(from: mistakeDeck, batchSize: batchSize) {
            woodpeckerCycle = cycle
            triggerHaptic(.success)
            persistToDisk()
        }
    }

    public func recordWoodpeckerStep(firstTry: Bool, solved: Bool) {
        guard var cycle = woodpeckerCycle else { return }
        if firstTry { cycle.firstTryCount += 1 }
        if solved { cycle.solvedCount += 1 }
        cycle.activeIndex += 1

        if cycle.activeIndex >= cycle.puzzleIds.count {
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
            let started = cycle.activeStartedAt ?? nowMs
            let elapsedSec = max(1, Int((nowMs - started) / 1000))
            let total = max(1, cycle.puzzleIds.count)
            let summary = WoodpeckerCompletedCycle(
                cycleNumber: cycle.currentCycle,
                completedAt: nowMs,
                elapsedSeconds: elapsedSec,
                accuracyPct: Int((Double(cycle.solvedCount) / Double(total) * 100.0).rounded()),
                firstTryPct: Int((Double(cycle.firstTryCount) / Double(total) * 100.0).rounded()),
                solvedCount: cycle.solvedCount,
                totalCount: total
            )
            cycle.completedCycles.append(summary)
            cycle.currentCycle += 1
            cycle.activeIndex = 0
            cycle.firstTryCount = 0
            cycle.solvedCount = 0
            cycle.activeStartedAt = nowMs
            cycle.cooldownUntil = nowMs + 24 * 3_600 * 1_000 // 24h consolidation window (overridable)
            triggerHaptic(.success)
        }
        woodpeckerCycle = cycle
        persistToDisk()
    }

    public func markEndgameMastered(_ id: String) {
        masteredEndgameIds.insert(id)
        triggerHaptic(.success)
        persistToDisk()
    }

    public func markAdvantageConverted(_ id: String) {
        convertedAdvantageIds.insert(id)
        triggerHaptic(.success)
        persistToDisk()
    }

    public func recordBoardVisionScore(_ score: Int) {
        if score > boardVisionBestScore {
            boardVisionBestScore = score
            persistToDisk()
        }
    }

    public func openEndgameLab(category: EndgameCategory? = nil) {
        preferredEndgameCategory = category
        selectedTrainMode = .labs
        selectedTab = .train
    }

    public func openMotifTrainer(tag: String) {
        preferredMotifFilter = tag
        selectedTrainMode = .mistakes
        selectedTab = .train
    }

    public func markDailySessionCompleted() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = fmt.string(from: Date())
        if lastDailyCompletedDate != today {
            dailyStreakDays += 1
            lastDailyCompletedDate = today
            persistToDisk()
        }
        triggerHaptic(.success)
    }

    public func toggleBookmark(ply: AnalyzedPly, game: GameRecord) {
        let id = "\(game.id)::ply::\(ply.ply)"
        if let idx = bookmarks.firstIndex(where: { $0.id == id }) {
            bookmarks.remove(at: idx)
        } else {
            let bm = SavedPositionBookmark(
                id: id,
                gameId: game.id,
                ply: ply.ply,
                fen: ply.afterFen,
                san: ply.san,
                moveNumber: ply.moveNumber,
                color: ply.color,
                label: "\(game.openingName) · Move \(ply.moveNumber) (\(ply.san))",
                evalDisplay: ply.evalAfter.display,
                classification: ply.classification,
                createdAt: Int64(Date().timeIntervalSince1970 * 1000.0)
            )
            bookmarks.insert(bm, at: 0)
            triggerHaptic(.success)
        }
        persistToDisk()
    }
}
