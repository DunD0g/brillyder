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
    // MARK: - Edition, StoreKit 2 & Entitlements
    public let edition: BrillyAppEdition
    public let storeKit: BrillyStoreKitManager
    public var showingProPaywall: Bool = false
    public var proPaywallFeature: String? = nil
    /// Only honored on the personal Founder/Admin target (`com.brillyder.admin`) for testing the Free paywall flow.
    public var simulateFreeTierInAdmin: Bool = false
    private var dailyAnalysisQuotaDay: String
    private var dailyAnalysisQuotaCount: Int

    public var hasProAccess: Bool {
        if edition == .founderAdmin {
            return !simulateFreeTierInAdmin
        }
        return storeKit.hasProEntitlement
    }

    public var effectivePieceSet: PieceSetID {
        isPieceSetUnlocked(pieceSet) ? pieceSet : .cburnett
    }

    public var effectiveDailyDuration: DailyDurationMinutes {
        isDurationUnlocked(dailyDuration) ? dailyDuration : .ten
    }

    public var freeAnalysesUsedToday: Int {
        dailyAnalysisQuotaDay == BrillyEntitlementPolicy.localDayKey() ? dailyAnalysisQuotaCount : 0
    }

    public var remainingFreeAnalysesToday: Int {
        BrillyEntitlementPolicy.remainingFreeAnalyses(usedToday: freeAnalysesUsedToday, hasProAccess: hasProAccess)
    }

    public func isCourseUnlocked(_ courseId: String) -> Bool {
        BrillyEntitlementPolicy.isCourseUnlocked(courseId, hasProAccess: hasProAccess)
    }

    public func isDurationUnlocked(_ duration: DailyDurationMinutes) -> Bool {
        BrillyEntitlementPolicy.isDurationUnlocked(duration, hasProAccess: hasProAccess)
    }

    public func isPieceSetUnlocked(_ set: PieceSetID) -> Bool {
        BrillyEntitlementPolicy.isPieceSetUnlocked(rawValue: set.rawValue, hasProAccess: hasProAccess)
    }

    public func canAnalyzeGame(_ gameId: String) -> Bool {
        let isCached = analyzedGames.contains(where: { $0.id == gameId })
        return BrillyEntitlementPolicy.canStartNewAnalysis(
            isAlreadyCached: isCached,
            usedToday: freeAnalysesUsedToday,
            hasProAccess: hasProAccess
        )
    }

    private func recordFreeAnalysisConsumed() {
        guard !hasProAccess else { return }
        let today = BrillyEntitlementPolicy.localDayKey()
        if dailyAnalysisQuotaDay != today {
            dailyAnalysisQuotaDay = today
            dailyAnalysisQuotaCount = 1
        } else {
            dailyAnalysisQuotaCount += 1
        }
        let defaults = UserDefaults.standard
        defaults.set(dailyAnalysisQuotaDay, forKey: "brilly_free_analyses_day")
        defaults.set(dailyAnalysisQuotaCount, forKey: "brilly_free_analyses_count")
    }
    public var pendingAnalyzePly: Int? = nil
    public var preferredEndgameCategory: EndgameCategory? = nil
    public var preferredMotifFilter: String? = nil

    public var surfaceStyle: SurfaceStyle {
        didSet { UserDefaults.standard.set(surfaceStyle.rawValue, forKey: "brilly_surface_style") }
    }
    public var vibeMode: VibeMode {
        didSet { UserDefaults.standard.set(vibeMode.rawValue, forKey: "brilly_vibe_mode") }
    }
    public var calloutStyle: CalloutStyle {
        didSet { UserDefaults.standard.set(calloutStyle.rawValue, forKey: "brilly_callout_style") }
    }
    public var boardTheme: BoardThemeID {
        didSet { UserDefaults.standard.set(boardTheme.rawValue, forKey: "brilly_board_theme") }
    }
    public var pieceSet: PieceSetID {
        didSet { UserDefaults.standard.set(pieceSet.rawValue, forKey: "brilly_piece_set") }
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
    public var dailyOpeningCourseIds: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(dailyOpeningCourseIds).sorted(), forKey: "brilly_daily_opening_course_ids")
        }
    }
    public var hasConfiguredDailyOpenings: Bool {
        didSet {
            UserDefaults.standard.set(hasConfiguredDailyOpenings, forKey: "brilly_daily_opening_configured")
        }
    }
    public var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "brilly_has_completed_onboarding")
        }
    }
    public var showingWelcomeGuide: Bool = false
    public var activeCelebration: CelebrationEvent? = nil

    // MARK: - Sync & Scout State
    public var syncPlatform: GameSource = .lichess
    public var lichessUsername: String = "" {
        didSet {
            if isHydrated, oldValue != lichessUsername {
                derivedCacheKeyVersion &+= 1
            }
        }
    }
    public var chessComUsername: String = "" {
        didSet {
            if isHydrated, oldValue != chessComUsername {
                derivedCacheKeyVersion &+= 1
            }
        }
    }
    public var recentGames: [GameRecord] = []
    public var isSyncing: Bool = false
    public var syncErrorMessage: String? = nil

    public var scoutOpponent: String = ""
    public var scoutGames: [GameRecord] = []
    public var isScouting: Bool = false

    // MARK: - Single & Batch Analysis State
    public var analyzedGames: [AnalyzedGame] = [] {
        didSet { derivedCacheKeyVersion &+= 1 }
    }
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
    /// Background analysis engine (single + batch review).
    public let engine = BrillyNativeEngine()
    /// Dedicated engine for interactive Play Bot, Sandbox, Conversion, and Endgame drills so batch analysis never blocks them.
    public let interactiveEngine = BrillyNativeEngine()
    private let vault = LocalVaultStore()

    @ObservationIgnored private var isHydrated: Bool = false
    @ObservationIgnored private var hasPendingSave: Bool = false
    @ObservationIgnored private var saveDirty: Bool = false
    @ObservationIgnored private var saveLoopTask: Task<Void, Never>? = nil

    @ObservationIgnored private var analysisTask: Task<Void, Never>? = nil
    @ObservationIgnored private var batchTask: Task<Void, Never>? = nil
    @ObservationIgnored private var syncTask: Task<Void, Never>? = nil
    @ObservationIgnored private var scoutTask: Task<Void, Never>? = nil
    @ObservationIgnored private var celebrationDismissTask: Task<Void, Never>? = nil
    @ObservationIgnored private var analysisGeneration: Int = 0
    @ObservationIgnored private var batchGeneration: Int = 0
    @ObservationIgnored private var syncGeneration: Int = 0
    @ObservationIgnored private var scoutGeneration: Int = 0

    // MARK: - Memoization Cache (avoids redundant O(N * plies) recomputations on 120Hz SwiftUI passes)
    @ObservationIgnored private var derivedCacheKeyVersion: Int = 0
    @ObservationIgnored private var cachedMistakeDeck: (key: Int, value: [MistakePuzzle])? = nil
    @ObservationIgnored private var cachedInsights: (key: Int, value: InsightsSnapshot)? = nil
    @ObservationIgnored private var cachedAdvancedInsights: (key: Int, value: AdvancedInsightsReport)? = nil
    @ObservationIgnored private var cachedVault: (key: Int, value: VaultCollection)? = nil
    @ObservationIgnored private var cachedBlownLeads: (key: Int, value: [BlownLeadPosition])? = nil
    @ObservationIgnored private var cachedUserEndgames: (key: Int, value: [EndgameDrill])? = nil

    // MARK: - Computed Properties

    public var activeUsername: String? {
        let raw = syncPlatform == .chesscom ? chessComUsername : lichessUsername
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// All configured user handles across both Lichess and Chess.com for accurate dual-platform ownership resolution.
    public var userHandles: [String] {
        var out: [String] = []
        var seen = Set<String>()
        for raw in [lichessUsername, chessComUsername] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted {
                out.append(trimmed)
            }
        }
        return out
    }

    /// Merges starter courses with custom courses, allowing Web-edited starter overrides without duplicating IDs.
    public var allCourses: [OpeningCourse] {
        let customById = Dictionary(customCourses.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let starterIds = Set(starterCourses.map(\.id))
        let mergedStarters = starterCourses.map { customById[$0.id] ?? $0 }
        let extraCustom = customCourses.filter { !starterIds.contains($0.id) }
        return mergedStarters + extraCustom
    }

    public var unanalyzedRecentGames: [GameRecord] {
        let doneIds = Set(analyzedGames.map(\.id))
        return recentGames.filter { !doneIds.contains($0.id) }
    }

    public var mistakeDeck: [MistakePuzzle] {
        // Touch observable dependencies for SwiftUI invalidation
        _ = analyzedGames.count
        let handles = userHandles
        if let hit = cachedMistakeDeck, hit.key == derivedCacheKeyVersion { return hit.value }
        let value = GameAnalyzer.extractMistakePuzzles(from: analyzedGames, handles: handles)
        cachedMistakeDeck = (derivedCacheKeyVersion, value)
        return value
    }

    /// FSRS cards filtered strictly to openings the user has enabled (and unlocked) for Daily Coach & Gravity Check.
    public var dailyEligibleFsrsCards: [FsrsOpeningCard] {
        fsrsCards.filter { card in
            (dailyOpeningCourseIds.contains(card.courseId) && isCourseUnlocked(card.courseId))
                || card.source == "game-deviation"
        }
    }

    public var dueOpeningCount: Int {
        dailyEligibleFsrsCards.filter { FSRS6Scheduler.isCardDue($0) }.count
    }

    public var dailyWorkoutPlan: DailyWorkoutPlan {
        DailyCoachPlanner.buildPlan(
            duration: effectiveDailyDuration,
            fsrsCards: dailyEligibleFsrsCards,
            mistakeDeck: mistakeDeck
        )
    }

    public func isCourseInDaily(_ courseId: String) -> Bool {
        dailyOpeningCourseIds.contains(courseId) && isCourseUnlocked(courseId)
    }

    public func toggleCourseInDaily(_ courseId: String) {
        guard isCourseUnlocked(courseId) else {
            openProPaywall(feature: "All 8 Opening Courses & Custom Repertoires")
            return
        }
        hasConfiguredDailyOpenings = true
        if dailyOpeningCourseIds.contains(courseId) {
            dailyOpeningCourseIds.remove(courseId)
        } else {
            dailyOpeningCourseIds.insert(courseId)
            ensureFirstLineUnlocked(forCourseId: courseId)
        }
        triggerHaptic(.move)
    }

    public func setDailyOpenings(_ ids: Set<String>) {
        hasConfiguredDailyOpenings = true
        let validIds = Set(allCourses.map(\.id))
        let filtered = ids.intersection(validIds).filter { isCourseUnlocked($0) }
        dailyOpeningCourseIds = filtered
        for cid in filtered {
            ensureFirstLineUnlocked(forCourseId: cid)
        }
        triggerHaptic(.move)
    }

    public func openProPaywall(feature: String? = nil) {
        storeKit.clearNotices()
        proPaywallFeature = feature
        showingProPaywall = true
        if !storeKit.hasLoadedProducts {
            Task { await storeKit.loadProducts() }
        }
    }

    private func ensureFirstLineUnlocked(forCourseId courseId: String) {
        let hasUnlocked = fsrsCards.contains { $0.courseId == courseId && $0.unlocked }
        guard !hasUnlocked,
              let course = allCourses.first(where: { $0.id == courseId }),
              let firstLine = course.lines.first else { return }
        unlockLine(courseId: courseId, lineId: firstLine.id)
    }

    public var insights: InsightsSnapshot {
        _ = analyzedGames.count
        let handles = userHandles
        if let hit = cachedInsights, hit.key == derivedCacheKeyVersion { return hit.value }
        let value = GameAnalyzer.computeInsights(analyzedGames: analyzedGames, handles: handles)
        cachedInsights = (derivedCacheKeyVersion, value)
        return value
    }

    public var advancedInsights: AdvancedInsightsReport {
        _ = analyzedGames.count
        let handles = userHandles
        if let hit = cachedAdvancedInsights, hit.key == derivedCacheKeyVersion { return hit.value }
        let value = AdvancedInsightsService.buildReport(analyzedGames: analyzedGames, handles: handles)
        cachedAdvancedInsights = (derivedCacheKeyVersion, value)
        return value
    }

    public var vaultCollection: VaultCollection {
        _ = analyzedGames.count
        let handles = userHandles
        if let hit = cachedVault, hit.key == derivedCacheKeyVersion { return hit.value }
        let value = VaultService.buildVault(from: analyzedGames, handles: handles)
        cachedVault = (derivedCacheKeyVersion, value)
        return value
    }

    public var blownLeads: [BlownLeadPosition] {
        _ = analyzedGames.count
        let handles = userHandles
        if let hit = cachedBlownLeads, hit.key == derivedCacheKeyVersion { return hit.value }
        let value = WoodpeckerAndConversion.extractBlownLeads(from: analyzedGames, handles: handles)
        cachedBlownLeads = (derivedCacheKeyVersion, value)
        return value
    }

    public var userEndgameDrills: [EndgameDrill] {
        _ = analyzedGames.count
        let handles = userHandles
        if let hit = cachedUserEndgames, hit.key == derivedCacheKeyVersion { return hit.value }
        let value = EndgameLibrary.extractUserEndgameDrills(from: analyzedGames, handles: handles)
        cachedUserEndgames = (derivedCacheKeyVersion, value)
        return value
    }

    public var scoutGameplan: ScoutGameplan? {
        AdvancedInsightsService.buildScoutGameplan(opponent: scoutOpponent, games: scoutGames)
    }

    public init(edition: BrillyAppEdition = .appStore) {
        self.edition = edition
        self.storeKit = BrillyStoreKitManager()
        let defaults = UserDefaults.standard
        self.dailyAnalysisQuotaDay = defaults.string(forKey: "brilly_free_analyses_day") ?? BrillyEntitlementPolicy.localDayKey()
        self.dailyAnalysisQuotaCount = defaults.integer(forKey: "brilly_free_analyses_count")
        self.dailyDuration = edition == .founderAdmin ? .fifteen : .ten
        self.surfaceStyle = SurfaceStyle(rawValue: defaults.string(forKey: "brilly_surface_style") ?? "") ?? .liquidGlass
        self.vibeMode = VibeMode(rawValue: defaults.string(forKey: "brilly_vibe_mode") ?? "") ?? .classic
        self.calloutStyle = CalloutStyle(rawValue: defaults.string(forKey: "brilly_callout_style") ?? "") ?? .brillyDer
        self.boardTheme = BoardThemeID(rawValue: defaults.string(forKey: "brilly_board_theme") ?? "") ?? .slate
        self.pieceSet = PieceSetID(rawValue: defaults.string(forKey: "brilly_piece_set") ?? "") ?? .cburnett
        self.analysisPreset = AnalysisDepthPreset(rawValue: defaults.integer(forKey: "brilly_analysis_preset")) ?? .balanced
        self.hapticsEnabled = defaults.object(forKey: "brilly_haptics_enabled") as? Bool ?? true
        self.soundEnabled = defaults.object(forKey: "brilly_sound_enabled") as? Bool ?? true
        self.celebrationsEnabled = defaults.object(forKey: "brilly_celebrations_enabled") as? Bool ?? true
        self.hasConfiguredDailyOpenings = defaults.bool(forKey: "brilly_daily_opening_configured")
        let completedOnboarding = defaults.bool(forKey: "brilly_has_completed_onboarding")
        self.hasCompletedOnboarding = completedOnboarding
        self.showingWelcomeGuide = !completedOnboarding
        let savedIds = defaults.stringArray(forKey: "brilly_daily_opening_course_ids") ?? []
        self.dailyOpeningCourseIds = Set(savedIds)

        self.starterCourses = (try? CourseRepository.loadStarterCourses()) ?? []
        self.recentGames = LichessClient.sampleGames()

        Task {
            await hydrateFromDisk()
        }
    }

    // MARK: - Copy, Lifecycle & Haptics

    public func copy(cosmic: String, classic: String) -> String {
        vibeMode == .cosmic ? cosmic : classic
    }

    /// Returns the user's selected mascot & move callout style independently of Coach Copy Vibe.
    public var effectiveCalloutStyle: CalloutStyle {
        calloutStyle
    }

    public func completeOnboarding() {
        hasCompletedOnboarding = true
        showingWelcomeGuide = false
    }

    public func classificationLabel(_ classification: MoveClassification) -> String {
        switch effectiveCalloutStyle {
        case .brillyDer:
            switch classification {
            case .brilliant:  return "Brilly!!"
            case .great:      return "Great!"
            case .best:       return "Best"
            case .excellent:  return "Good"
            case .book:       return "Book"
            case .inaccuracy: return "Slip"
            case .mistake:    return "Mini-Der"
            case .blunder:    return "Blun-DER"
            }
        case .cosmicAlien:
            switch classification {
            case .brilliant:  return "Galaxy-Brain"
            case .great:      return "Precision"
            case .best:       return "Best"
            case .excellent:  return "Good"
            case .book:       return "Book"
            case .inaccuracy: return "Orbit Drift"
            case .mistake:    return "Course Slip"
            case .blunder:    return "Hull Breach"
            }
        case .standard:
            return classification.label
        }
    }

    public func handleScenePhaseChange(isBackground: Bool) {
        if isBackground {
            BrillySoundEngine.shared.pause()
            if isAnalyzing { cancelAnalysis() }
            if isBatchAnalyzing { cancelBatchAnalysis() }
            flushToDiskNow()
        } else {
            if soundEnabled {
                BrillySoundEngine.shared.resumeIfNeeded()
            }
            validateDailyStreakLiveness()
            Task {
                await storeKit.refreshEntitlements()
            }
        }
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

    public func triggerCelebration(_ kind: CelebrationEvent.Kind, forceShow: Bool = false) {
        if soundEnabled {
            BrillySoundEngine.shared.play(kind == .brilliant ? .brilliant : .blunder)
        }
        guard forceShow || celebrationsEnabled else { return }
        let event = CelebrationEvent(kind: kind, vibe: vibeMode, calloutStyle: effectiveCalloutStyle)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            activeCelebration = event
        }
        let id = event.id
        celebrationDismissTask?.cancel()
        celebrationDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(kind == .brilliant ? 2900 : 2300))
            guard !Task.isCancelled, let self, self.activeCelebration?.id == id else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.activeCelebration = nil
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

        validateDailyStreakLiveness()

        if let first = snap.analyzedGames.first {
            self.activeAnalyzedGame = first
        }
        // Hydrate Games tab offline from analyzed games if we have them
        if !snap.analyzedGames.isEmpty {
            let cachedRecords = snap.analyzedGames.map(\.game)
            let existingIds = Set(recentGames.map(\.id))
            let newOnes = cachedRecords.filter { !existingIds.contains($0.id) }
            if !newOnes.isEmpty {
                self.recentGames = (newOnes + recentGames).sorted { $0.createdAt > $1.createdAt }
            }
        }

        rehydrateFsrsCards(existing: snap.fsrsCards)
        self.isHydrated = true
        self.derivedCacheKeyVersion &+= 1
        if hasPendingSave {
            hasPendingSave = false
            persistToDisk()
        }
    }

    private func rehydrateFsrsCards(existing: [FsrsOpeningCard]) {
        var existingById = Dictionary(existing.map { ($0.cardId, $0) }, uniquingKeysWith: { a, b in
            let unlocked = a.unlocked || b.unlocked
            let aRev = a.fsrsState.last_review ?? ""
            let bRev = b.fsrsState.last_review ?? ""
            var winner = (bRev != aRev ? (bRev > aRev ? b : a) : (b.attempts >= a.attempts ? b : a))
            winner.unlocked = unlocked
            return winner
        })
        var hydrated: [FsrsOpeningCard] = []
        var emittedIds = Set<String>()

        for (courseIdx, course) in allCourses.enumerated() {
            let isUserImported = course.source == "pgn" || course.source == "lichess-study"
            let isSelectedForDaily = dailyOpeningCourseIds.contains(course.id)
            for (lineIdx, line) in course.lines.enumerated() {
                let shouldUnlock = ((courseIdx == 0 || courseIdx == 1 || isSelectedForDaily) && lineIdx == 0) || isUserImported
                if let cards = try? CourseRepository.hydrateLineCards(
                    courseId: course.id,
                    side: course.side,
                    line: line,
                    existingById: existingById,
                    unlocked: shouldUnlock
                ) {
                    for c in cards where emittedIds.insert(c.cardId).inserted {
                        hydrated.append(c)
                        existingById[c.cardId] = c
                    }
                }
            }
        }

        // Preserve any unmatched cards (e.g., Web `game-deviation` cards) so they are never silently lost.
        for card in existing where emittedIds.insert(card.cardId).inserted {
            hydrated.append(card)
        }

        self.fsrsCards = hydrated

        // Smart default: if user hasn't explicitly configured Daily FSRS openings yet,
        // ONLY include courses they have actually practiced/imported (or first starter course if brand new),
        // never random unpracticed openings!
        let validCourseIds = Set(allCourses.map(\.id))
        if !hasConfiguredDailyOpenings {
            var seeded = Set<String>()
            for card in hydrated where card.attempts > 0 && validCourseIds.contains(card.courseId) {
                seeded.insert(card.courseId)
            }
            for course in allCourses where course.source == "pgn" || course.source == "lichess-study" {
                seeded.insert(course.id)
            }
            if seeded.isEmpty, let first = allCourses.first {
                seeded.insert(first.id)
            }
            self.dailyOpeningCourseIds = seeded
        } else {
            // Prune any orphaned IDs from deleted courses
            let pruned = dailyOpeningCourseIds.intersection(validCourseIds)
            if pruned != dailyOpeningCourseIds {
                self.dailyOpeningCourseIds = pruned
            }
        }
    }

    public func persistToDisk() {
        guard isHydrated else {
            hasPendingSave = true
            return
        }
        saveDirty = true
        guard saveLoopTask == nil else { return }
        saveLoopTask = Task {
            while saveDirty {
                saveDirty = false
                let snap = currentSnapshot()
                try? await vault.save(snap)
            }
            saveLoopTask = nil
        }
    }

    public func flushToDiskNow() {
        guard isHydrated else { return }
        saveDirty = false
        let snap = currentSnapshot()
        let vaultStore = vault
        #if canImport(UIKit) && os(iOS)
        var bgTaskId: UIBackgroundTaskIdentifier = .invalid
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "BrillyDerVaultFlush") {
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
                bgTaskId = .invalid
            }
        }
        Task.detached(priority: .userInitiated) {
            try? await vaultStore.save(snap)
            await MainActor.run {
                if bgTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskId)
                    bgTaskId = .invalid
                }
            }
        }
        #else
        Task.detached(priority: .userInitiated) {
            try? await vaultStore.save(snap)
        }
        #endif
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
        self.woodpeckerCycle = merged.woodpeckerCycle
        self.boardVisionBestScore = merged.boardVisionBestScore
        self.puzzleRushBlitzBest = merged.puzzleRushBlitzBest
        self.puzzleRushSurvivalBest = merged.puzzleRushSurvivalBest
        self.lichessUsername = merged.lichessUsername
        self.chessComUsername = merged.chessComUsername

        validateDailyStreakLiveness()

        // Hydrate Games tab offline with imported analyzed games
        if !merged.analyzedGames.isEmpty {
            let existingIds = Set(recentGames.map(\.id))
            let importedRecords = merged.analyzedGames.map(\.game).filter { !existingIds.contains($0.id) }
            if !importedRecords.isEmpty {
                recentGames = (importedRecords + recentGames).sorted { $0.createdAt > $1.createdAt }
            }
            if activeAnalyzedGame == nil {
                activeAnalyzedGame = merged.analyzedGames.first
            }
        }
        rehydrateFsrsCards(existing: merged.fsrsCards)
        derivedCacheKeyVersion &+= 1
        persistToDisk()
        triggerHaptic(.success)
        return summary
    }

    public func deleteCustomCourse(id: String) {
        customCourses.removeAll { $0.id == id }
        let starterIds = Set(starterCourses.map(\.id))
        if starterIds.contains(id) {
            rehydrateFsrsCards(existing: fsrsCards)
        } else {
            fsrsCards.removeAll { $0.courseId == id }
            dailyOpeningCourseIds.remove(id)
        }
        persistToDisk()
    }

    public func recordPuzzleRushScore(_ score: Int, survival: Bool) {
        if score > 0 { recordTrainingActivity() }
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
        syncTask?.cancel()
        syncGeneration &+= 1
        let gen = syncGeneration
        isSyncing = true
        syncErrorMessage = nil
        let handles = userHandles
        let active = activeUsername

        let task = Task { @MainActor in
            defer {
                if self.syncGeneration == gen { self.isSyncing = false }
            }
            do {
                let record = try await LichessClient.fetchSingleGame(
                    urlOrId: urlOrId,
                    preferredUsername: active,
                    preferredUsernames: handles
                )
                guard self.syncGeneration == gen, !Task.isCancelled else { return }
                if !self.recentGames.contains(where: { $0.id == record.id }) {
                    self.recentGames.insert(record, at: 0)
                }
                self.startAnalysis(for: record)
            } catch is CancellationError {
                return
            } catch {
                guard self.syncGeneration == gen else { return }
                self.syncErrorMessage = error.localizedDescription
                self.triggerHaptic(.error)
            }
        }
        syncTask = task
        await task.value
    }

    // MARK: - Sync & Scout Actions

    public func syncRecentGames() async {
        syncTask?.cancel()
        syncGeneration &+= 1
        let gen = syncGeneration
        isSyncing = true
        syncErrorMessage = nil
        let platform = syncPlatform
        let ccHandle = chessComUsername
        let liHandle = lichessUsername

        let task = Task { @MainActor in
            defer {
                if self.syncGeneration == gen { self.isSyncing = false }
            }
            do {
                let fetched: [GameRecord]
                if platform == .chesscom {
                    fetched = try await ChessComClient.fetchRecentGames(username: ccHandle, maxGames: 30)
                } else {
                    fetched = try await LichessClient.fetchRecentGames(username: liHandle, maxGames: 30)
                }
                guard self.syncGeneration == gen, !Task.isCancelled else { return }
                if !fetched.isEmpty {
                    // Preserve pasted PGNs, analyzed games, and other-platform synced games while deduplicating by id
                    let fetchedIds = Set(fetched.map(\.id))
                    let preserved = self.recentGames.filter { rec in
                        rec.source != .sample && !fetchedIds.contains(rec.id) &&
                        (rec.source != platform || self.analyzedGames.contains(where: { ag in ag.id == rec.id }))
                    }
                    self.recentGames = (fetched + preserved).sorted { $0.createdAt > $1.createdAt }
                    self.triggerHaptic(.success)
                } else {
                    self.syncErrorMessage = "No recent standard games found for that handle."
                }
                self.persistToDisk()
            } catch is CancellationError {
                return
            } catch {
                guard self.syncGeneration == gen else { return }
                self.syncErrorMessage = error.localizedDescription
                self.triggerHaptic(.error)
            }
        }
        syncTask = task
        await task.value
    }

    public func runScout(opponent: String, platform: GameSource) async {
        let clean = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        scoutTask?.cancel()
        scoutGeneration &+= 1
        let gen = scoutGeneration
        isScouting = true
        syncErrorMessage = nil

        let task = Task { @MainActor in
            defer {
                if self.scoutGeneration == gen { self.isScouting = false }
            }
            do {
                let fetched: [GameRecord]
                if platform == .chesscom {
                    fetched = try await ChessComClient.fetchRecentGames(username: clean, maxGames: 25)
                } else {
                    fetched = try await LichessClient.fetchRecentGames(username: clean, maxGames: 25)
                }
                guard self.scoutGeneration == gen, !Task.isCancelled else { return }
                if fetched.isEmpty {
                    self.syncErrorMessage = "No recent standard games found for \"\(clean)\"."
                    self.triggerHaptic(.error)
                    return
                }
                self.scoutOpponent = clean
                self.scoutGames = fetched
                self.selectedTab = .insights
                self.triggerHaptic(.success)
            } catch is CancellationError {
                return
            } catch {
                guard self.scoutGeneration == gen else { return }
                self.syncErrorMessage = "Scout failed: \(error.localizedDescription)"
                self.triggerHaptic(.error)
            }
        }
        scoutTask = task
        await task.value
    }

    public func clearScout() {
        scoutTask?.cancel()
        scoutGeneration &+= 1
        isScouting = false
        scoutOpponent = ""
        scoutGames = []
    }

    @discardableResult
    public func importAndAnalyzePGN(_ pgn: String) -> Bool {
        do {
            let record = try LichessClient.parsePastedPGN(
                pgn,
                preferredUsername: activeUsername,
                preferredUsernames: userHandles
            )
            if !recentGames.contains(where: { $0.id == record.id }) {
                recentGames.insert(record, at: 0)
            }
            syncErrorMessage = nil
            startAnalysis(for: record)
            return true
        } catch {
            syncErrorMessage = error.localizedDescription
            triggerHaptic(.error)
            return false
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

        if !canAnalyzeGame(game.id) {
            openProPaywall(feature: "Unlimited Game Analysis (5/day Free limit reached)")
            return
        }

        cancelBatchAnalysis()
        analysisTask?.cancel()
        analysisGeneration &+= 1
        let gen = analysisGeneration

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
                        guard self.analysisGeneration == gen else { return }
                        self.analysisProgress = Double(completed) / Double(max(1, total))
                        self.analysisStatusText = "Ply \(completed) / \(total)"
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard self.analysisGeneration == gen else { return }
                    self.analyzedGames.removeAll { $0.id == result.id }
                    self.analyzedGames.insert(result, at: 0)
                    self.activeAnalyzedGame = result
                    self.pendingAnalyzePly = jumpToPly
                    self.isAnalyzing = false
                    self.analysisProgress = 1.0
                    self.recordFreeAnalysisConsumed()
                    self.triggerHaptic(.success)
                    self.persistToDisk()
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard self.analysisGeneration == gen else { return }
                    self.isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    guard self.analysisGeneration == gen else { return }
                    self.isAnalyzing = false
                    self.syncErrorMessage = error.localizedDescription
                }
            }
        }
    }

    public func cancelAnalysis() {
        analysisGeneration &+= 1
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
    }

    public func startBatchAnalysis(maxCount: Int) {
        guard hasProAccess else {
            openProPaywall(feature: "Unlimited Batch Analysis")
            return
        }
        let targets = Array(unanalyzedRecentGames.prefix(maxCount))
        guard !targets.isEmpty else { return }

        cancelAnalysis()
        batchTask?.cancel()
        batchGeneration &+= 1
        let gen = batchGeneration

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
                    guard self.batchGeneration == gen else { return }
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
                            guard self.batchGeneration == gen else { return }
                            self.batchProgress = overall
                            self.batchCurrentLabel = "Game \(idx + 1)/\(totalGames) · Ply \(donePlies)/\(totalPlies)"
                        }
                    }
                    if Task.isCancelled { break }
                    await MainActor.run {
                        guard self.batchGeneration == gen else { return }
                        self.analyzedGames.removeAll { $0.id == result.id }
                        self.analyzedGames.insert(result, at: 0)
                        if self.activeAnalyzedGame == nil {
                            self.activeAnalyzedGame = result
                        }
                        self.batchCompletedGames = idx + 1
                        self.batchProgress = Double(idx + 1) / Double(max(1, totalGames))
                        self.persistToDisk()
                    }
                } catch is CancellationError {
                    break
                } catch {
                    if Task.isCancelled { break }
                }
            }
            let cancelled = Task.isCancelled
            await MainActor.run {
                guard self.batchGeneration == gen else { return }
                self.isBatchAnalyzing = false
                self.batchCurrentLabel = ""
                if !cancelled {
                    self.batchProgress = 1.0
                    self.triggerHaptic(.success)
                }
            }
        }
    }

    public func cancelBatchAnalysis() {
        batchGeneration &+= 1
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
        guard let eval = try? await interactiveEngine.analyze(fen: fen, depth: depth, multiPV: 1, maxTimeMs: 350),
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
        if attempt.correct {
            recordTrainingActivity()
        }
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
        dailyOpeningCourseIds.insert(course.id)
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
        if solved {
            cycle.solvedCount += 1
            recordTrainingActivity()
        }
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
            cycle.cooldownUntil = nowMs + 24 * 3_600 * 1_000
            triggerHaptic(.success)
        }
        woodpeckerCycle = cycle
        persistToDisk()
    }

    public func markEndgameMastered(_ id: String) {
        masteredEndgameIds.insert(id)
        recordTrainingActivity()
        triggerHaptic(.success)
        persistToDisk()
    }

    public func markAdvantageConverted(_ id: String) {
        convertedAdvantageIds.insert(id)
        recordTrainingActivity()
        triggerHaptic(.success)
        persistToDisk()
    }

    public func recordBoardVisionScore(_ score: Int) {
        if score > 0 { recordTrainingActivity() }
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

    /// DST-safe daily training streak tracker: called automatically whenever the user completes
    /// any meaningful training activity (opening drill, blunder rewind, Gravity Check, Woodpecker, Endgame, Vision, Rush).
    public func recordTrainingActivity(now: Date = Date()) {
        let today = Self.dayString(for: now)
        let yesterdayDate = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
        let yesterday = Self.dayString(for: yesterdayDate)
        if lastDailyCompletedDate != today {
            if lastDailyCompletedDate == yesterday {
                dailyStreakDays = max(1, dailyStreakDays) + 1
            } else {
                dailyStreakDays = 1
            }
            lastDailyCompletedDate = today
            persistToDisk()
        } else if dailyStreakDays < 1 {
            dailyStreakDays = 1
            persistToDisk()
        }
    }

    public func markDailySessionCompleted() {
        recordTrainingActivity()
        triggerHaptic(.success)
    }

    private func validateDailyStreakLiveness(now: Date = Date()) {
        guard let last = lastDailyCompletedDate, !last.isEmpty else { return }
        let today = Self.dayString(for: now)
        let yesterdayDate = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
        let yesterday = Self.dayString(for: yesterdayDate)
        if last == today && dailyStreakDays < 1 {
            dailyStreakDays = 1
        } else if last != today && last != yesterday {
            dailyStreakDays = 0
        }
    }

    private static func dayString(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    public func isBookmarked(gameId: String, ply: Int) -> Bool {
        let canonical = "\(gameId)::\(ply)"
        let legacy = "\(gameId)::ply::\(ply)"
        return bookmarks.contains { $0.id == canonical || $0.id == legacy || ($0.gameId == gameId && $0.ply == ply) }
    }

    public func removeBookmark(id: String) {
        bookmarks.removeAll { $0.id == id }
        persistToDisk()
    }

    public func toggleBookmark(ply: AnalyzedPly, game: GameRecord) {
        let canonical = "\(game.id)::\(ply.ply)"
        let legacy = "\(game.id)::ply::\(ply.ply)"
        if let idx = bookmarks.firstIndex(where: { $0.id == canonical || $0.id == legacy || ($0.gameId == game.id && $0.ply == ply.ply) }) {
            bookmarks.remove(at: idx)
        } else {
            let bm = SavedPositionBookmark(
                id: canonical,
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
