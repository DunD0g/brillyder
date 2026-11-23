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

@Observable
@MainActor
public final class BrillyAppStore {
    // MARK: - Navigation & Preferences
    public var selectedTab: BrillyTab = .train
    public var showingSettings: Bool = false

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

    // MARK: - Sync & Game State
    public var syncPlatform: GameSource = .lichess
    public var lichessUsername: String = ""
    public var chessComUsername: String = ""
    public var recentGames: [GameRecord] = []
    public var isSyncing: Bool = false
    public var syncErrorMessage: String? = nil

    // MARK: - Analysis State
    public var analyzedGames: [AnalyzedGame] = []
    public var activeAnalyzedGame: AnalyzedGame? = nil
    public var isAnalyzing: Bool = false
    public var analysisProgress: Double = 0
    public var analysisStatusText: String = ""

    // MARK: - Openings & Training State
    public var starterCourses: [OpeningCourse] = []
    public var customCourses: [OpeningCourse] = []
    public var fsrsCards: [FsrsOpeningCard] = []
    public var bookmarks: [SavedPositionBookmark] = []
    public var dailyDuration: DailyDurationMinutes = .fifteen
    public var dailyStreakDays: Int = 0
    public var lastDailyCompletedDate: String? = nil

    // MARK: - Engine & Storage
    private let engine = BrillyNativeEngine()
    private let vault = LocalVaultStore()
    private var analysisTask: Task<Void, Never>? = nil

    public var allCourses: [OpeningCourse] {
        starterCourses + customCourses
    }

    public var mistakeDeck: [MistakePuzzle] {
        let user = syncPlatform == .chesscom ? chessComUsername : lichessUsername
        return GameAnalyzer.extractMistakePuzzles(from: analyzedGames, username: user.isEmpty ? nil : user)
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
        let user = syncPlatform == .chesscom ? chessComUsername : lichessUsername
        return GameAnalyzer.computeInsights(analyzedGames: analyzedGames, username: user.isEmpty ? nil : user)
    }

    public init() {
        let defaults = UserDefaults.standard
        self.surfaceStyle = SurfaceStyle(rawValue: defaults.string(forKey: "brilly_surface_style") ?? "") ?? .liquidGlass
        self.vibeMode = VibeMode(rawValue: defaults.string(forKey: "brilly_vibe_mode") ?? "") ?? .cosmic
        self.boardTheme = BoardThemeID(rawValue: defaults.string(forKey: "brilly_board_theme") ?? "") ?? .slate
        self.analysisPreset = AnalysisDepthPreset(rawValue: defaults.integer(forKey: "brilly_analysis_preset")) ?? .balanced
        self.hapticsEnabled = defaults.object(forKey: "brilly_haptics_enabled") as? Bool ?? true

        self.starterCourses = (try? CourseRepository.loadStarterCourses()) ?? []
        self.recentGames = LichessClient.sampleGames()

        Task {
            await hydrateFromDisk()
        }
    }

    // MARK: - Copy Helper (Vibe: Cosmic | Classic)

    public func copy(cosmic: String, classic: String) -> String {
        vibeMode == .cosmic ? cosmic : classic
    }

    // MARK: - Haptics

    public func triggerHaptic(_ style: HapticKind) {
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

        if let first = snap.analyzedGames.first {
            self.activeAnalyzedGame = first
        }

        // Hydrate starter opening cards (unlock first line of first White & Black course for immediate daily drills)
        var existingById = Dictionary(uniqueKeysWithValues: snap.fsrsCards.map { ($0.cardId, $0) })
        var hydrated: [FsrsOpeningCard] = []
        for (courseIdx, course) in allCourses.enumerated() {
            for (lineIdx, line) in course.lines.enumerated() {
                let shouldUnlock = (courseIdx == 0 || courseIdx == 1) && lineIdx == 0
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
        let snap = VaultSnapshot(
            analyzedGames: analyzedGames,
            fsrsCards: fsrsCards,
            customCourses: customCourses,
            bookmarks: bookmarks,
            dailyStreakDays: dailyStreakDays,
            lastDailyCompletedDate: lastDailyCompletedDate,
            lichessUsername: lichessUsername,
            chessComUsername: chessComUsername
        )
        Task {
            try? await vault.save(snap)
        }
    }

    public func exportBackupData() throws -> Data {
        let snap = VaultSnapshot(
            analyzedGames: analyzedGames,
            fsrsCards: fsrsCards,
            customCourses: customCourses,
            bookmarks: bookmarks,
            dailyStreakDays: dailyStreakDays,
            lastDailyCompletedDate: lastDailyCompletedDate,
            lichessUsername: lichessUsername,
            chessComUsername: chessComUsername
        )
        return try LocalVaultStore.exportBackupJSON(from: snap)
    }

    public func importBackupData(_ data: Data) throws -> Int {
        let current = VaultSnapshot(
            analyzedGames: analyzedGames,
            fsrsCards: fsrsCards,
            customCourses: customCourses,
            bookmarks: bookmarks,
            dailyStreakDays: dailyStreakDays,
            lastDailyCompletedDate: lastDailyCompletedDate,
            lichessUsername: lichessUsername,
            chessComUsername: chessComUsername
        )
        let merged = try LocalVaultStore.mergeBackupJSON(data, into: current)
        self.analyzedGames = merged.analyzedGames
        self.fsrsCards = merged.fsrsCards
        self.customCourses = merged.customCourses
        self.lichessUsername = merged.lichessUsername
        self.chessComUsername = merged.chessComUsername
        persistToDisk()
        return merged.analyzedGames.count + merged.fsrsCards.count
    }

    // MARK: - Sync Actions

    public func syncRecentGames() async {
        isSyncing = true
        syncErrorMessage = nil
        defer { isSyncing = false }

        do {
            let fetched: [GameRecord]
            if syncPlatform == .chesscom {
                fetched = try await ChessComClient.fetchRecentGames(username: chessComUsername, maxGames: 20)
            } else {
                fetched = try await LichessClient.fetchRecentGames(username: lichessUsername, maxGames: 20)
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

    public func importAndAnalyzePGN(_ pgn: String) {
        let preferred = syncPlatform == .chesscom ? chessComUsername : lichessUsername
        do {
            let record = try LichessClient.parsePastedPGN(pgn, preferredUsername: preferred)
            if !recentGames.contains(where: { $0.id == record.id }) {
                recentGames.insert(record, at: 0)
            }
            startAnalysis(for: record)
        } catch {
            syncErrorMessage = error.localizedDescription
            triggerHaptic(.error)
        }
    }

    // MARK: - Game Analysis

    public func startAnalysis(for game: GameRecord) {
        if let cached = analyzedGames.first(where: { $0.id == game.id }) {
            activeAnalyzedGame = cached
            selectedTab = .analyze
            return
        }

        analysisTask?.cancel()
        isAnalyzing = true
        analysisProgress = 0
        analysisStatusText = copy(cosmic: "Scanning trajectory…", classic: "Analyzing game…")
        selectedTab = .analyze

        let preset = analysisPreset
        let engineRef = engine

        analysisTask = Task {
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
                self.analyzedGames.removeAll { $0.id == result.id }
                self.analyzedGames.insert(result, at: 0)
                self.activeAnalyzedGame = result
                self.isAnalyzing = false
                self.analysisProgress = 1.0
                self.triggerHaptic(.success)
                self.persistToDisk()
            } catch {
                if !Task.isCancelled {
                    self.isAnalyzing = false
                    self.syncErrorMessage = error.localizedDescription
                }
            }
        }
    }

    public func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
    }

    // MARK: - FSRS Card Grading & Daily Streak

    public func recordOpeningAttempt(cardId: String, attempt: OpeningAttemptInput) -> OpeningReviewResult? {
        guard let idx = fsrsCards.firstIndex(where: { $0.cardId == cardId }) else { return nil }
        let result = FSRS6Scheduler.review(card: fsrsCards[idx], attempt: attempt)
        fsrsCards[idx] = result.card
        triggerHaptic(attempt.correct ? .success : .error)
        persistToDisk()
        return result
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
