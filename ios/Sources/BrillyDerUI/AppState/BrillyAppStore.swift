import Foundation
import SwiftUI
import Observation
import BrillyDerCore
import BrillyDerActivityKit
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif
#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks
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
    public var vaultInitialTab: VaultTab = .brilliant

    public func openVault(tab: VaultTab = .brilliant) {
        vaultInitialTab = tab
        showingVault = true
    }
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

    public var effectiveEmojiPack: BrillyEmojiPack {
        isEmojiPackUnlocked(emojiPack) ? emojiPack : .mindBlown
    }

    public var effectiveDailyDuration: DailyDurationMinutes {
        isDurationUnlocked(dailyDuration) ? dailyDuration : .ten
    }

    public var effectiveAnalysisPreset: AnalysisDepthPreset {
        isAnalysisPresetUnlocked(analysisPreset) ? analysisPreset : .deep
    }

    public func isAnalysisPresetUnlocked(_ preset: AnalysisDepthPreset) -> Bool {
        BrillyEntitlementPolicy.isAnalysisPresetUnlocked(preset, hasProAccess: hasProAccess)
    }

    public var freeAnalysesUsedToday: Int {
        dailyAnalysisQuotaDay == BrillyEntitlementPolicy.localDayKey() ? dailyAnalysisQuotaCount : 0
    }

    public var remainingFreeAnalysesToday: Int {
        BrillyEntitlementPolicy.remainingFreeAnalyses(usedToday: freeAnalysesUsedToday, hasProAccess: hasProAccess)
    }

    public func isCourseUnlocked(_ courseId: String) -> Bool {
        if customCourses.contains(where: { $0.id == courseId }) { return true }
        return BrillyEntitlementPolicy.isCourseUnlocked(courseId, hasProAccess: hasProAccess)
    }

    public func isDurationUnlocked(_ duration: DailyDurationMinutes) -> Bool {
        BrillyEntitlementPolicy.isDurationUnlocked(duration, hasProAccess: hasProAccess)
    }

    public func isPieceSetUnlocked(_ set: PieceSetID) -> Bool {
        BrillyEntitlementPolicy.isPieceSetUnlocked(rawValue: set.rawValue, hasProAccess: hasProAccess)
    }

    public func isEmojiPackUnlocked(_ pack: BrillyEmojiPack) -> Bool {
        BrillyEntitlementPolicy.isEmojiPackUnlocked(rawValue: pack.rawValue, hasProAccess: hasProAccess)
    }

    public func canAnalyzeGame(_ gameId: String) -> Bool {
        let isCached = analyzedGames.contains(where: { $0.id == gameId })
        let isSample = recentGames.first(where: { $0.id == gameId })?.source == .sample
        return BrillyEntitlementPolicy.canStartNewAnalysis(
            isAlreadyCached: isCached || isSample,
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
    public var emojiPack: BrillyEmojiPack {
        didSet { UserDefaults.standard.set(emojiPack.rawValue, forKey: "brilly_emoji_pack") }
    }
    // MARK: - Founder Admin Creator & Exhibition Studio (strictly inactive on App Store target)
    public var creatorNameMaskMode: CreatorNameMaskMode {
        didSet { UserDefaults.standard.set(creatorNameMaskMode.rawValue, forKey: "brilly_creator_name_mask") }
    }
    public var creatorExhibitionTheme: CreatorExhibitionTheme {
        didSet { UserDefaults.standard.set(creatorExhibitionTheme.rawValue, forKey: "brilly_creator_exhibition_theme") }
    }
    public var creatorEventRibbonText: String {
        didSet { UserDefaults.standard.set(creatorEventRibbonText, forKey: "brilly_creator_event_ribbon") }
    }
    public var creatorShowHandleOnCards: Bool {
        didSet { UserDefaults.standard.set(creatorShowHandleOnCards, forKey: "brilly_creator_show_handle") }
    }

    public var effectiveCreatorNameMask: CreatorNameMaskMode {
        edition == .founderAdmin ? creatorNameMaskMode : .off
    }
    public var effectiveExhibitionTheme: CreatorExhibitionTheme {
        edition == .founderAdmin ? creatorExhibitionTheme : .none
    }
    public var effectiveShowCreatorHandle: Bool {
        edition == .founderAdmin && creatorShowHandleOnCards
    }

    public func maskedPlayerName(_ rawName: String, opponent: String? = nil, side: PieceColor) -> (text: String, isBlurred: Bool) {
        CreatorNameMasker.mask(
            rawName: rawName,
            opponentRawName: opponent,
            side: side,
            mode: effectiveCreatorNameMask,
            userHandles: userHandles
        )
    }

    /// Applies Founder Admin Creator Name Masking to the user's own profile handle (Games tab / headers).
    /// Always returns `(rawHandle, false)` on the App Store edition.
    public func maskedProfileUsername(_ rawHandle: String) -> (text: String, isBlurred: Bool) {
        let mode = effectiveCreatorNameMask
        guard mode != .off else { return (rawHandle, false) }
        return CreatorNameMasker.mask(
            rawName: rawHandle,
            opponentRawName: nil,
            side: .white,
            mode: mode,
            userHandles: userHandles
        )
    }

    public func resolvedBroadcastRibbon(forPgn pgn: String? = nil) -> String? {
        let theme = effectiveExhibitionTheme
        guard theme != .none else { return nil }
        let custom = creatorEventRibbonText.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom.isEmpty || custom.uppercased() == "AUTO" {
            return CreatorNameMasker.extractPgnBroadcastLabel(from: pgn) ?? theme.defaultRibbonLabel
        }
        return custom.uppercased()
    }
    public var boardTheme: BoardThemeID {
        didSet { UserDefaults.standard.set(boardTheme.rawValue, forKey: "brilly_board_theme") }
    }
    public var effectiveBoardTheme: BoardThemeID {
        isBoardThemeUnlocked(boardTheme) ? boardTheme : .slate
    }
    public func isBoardThemeUnlocked(_ theme: BoardThemeID) -> Bool {
        BrillyEntitlementPolicy.isBoardThemeUnlocked(rawValue: theme.rawValue, hasProAccess: hasProAccess)
    }
    public var showBoardCoordinates: Bool {
        didSet { UserDefaults.standard.set(showBoardCoordinates, forKey: "brilly_show_board_coordinates") }
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
    public var defaultLaunchTab: BrillyTab {
        didSet {
            UserDefaults.standard.set(defaultLaunchTab.rawValue, forKey: "brilly_default_launch_tab")
        }
    }
    public var autoSyncOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(autoSyncOnLaunch, forKey: "brilly_auto_sync_on_launch")
        }
    }
    public var effectiveAutoSyncOnLaunch: Bool {
        BrillyEntitlementPolicy.isAutoSyncOnLaunchUnlocked(hasProAccess: hasProAccess) && autoSyncOnLaunch
    }
    public var hasPinnedManualGameSelection: Bool = false
    public var isShowingLaunchOverlay: Bool = true
    public var launchOverlayStatusText: String = "Warming up cockpit…"
    @ObservationIgnored private var lastAutoSyncDate: Date? = nil
    @ObservationIgnored private var hasAppliedInitialLaunchTab: Bool = false
    public var showingWelcomeGuide: Bool = false
    public var pendingReviewRequestVersion: String? = nil
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
    public var isLichessHandleLocked: Bool {
        didSet { UserDefaults.standard.set(isLichessHandleLocked, forKey: "brilly_lichess_handle_locked") }
    }
    public var isChessComHandleLocked: Bool {
        didSet { UserDefaults.standard.set(isChessComHandleLocked, forKey: "brilly_chesscom_handle_locked") }
    }

    public var activeHandleForSelectedPlatform: String {
        (syncPlatform == .chesscom ? chessComUsername : lichessUsername)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isActivePlatformHandleLocked: Bool {
        let locked = syncPlatform == .chesscom ? isChessComHandleLocked : isLichessHandleLocked
        return locked && !activeHandleForSelectedPlatform.isEmpty
    }

    public func lockHandle(for platform: GameSource) {
        if platform == .chesscom {
            let clean = chessComUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            chessComUsername = clean
            isChessComHandleLocked = !clean.isEmpty
        } else {
            let clean = lichessUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            lichessUsername = clean
            isLichessHandleLocked = !clean.isEmpty
        }
        persistToDisk()
    }

    public func clearHandle(for platform: GameSource) {
        if platform == .chesscom {
            chessComUsername = ""
            isChessComHandleLocked = false
        } else {
            lichessUsername = ""
            isLichessHandleLocked = false
        }
        persistToDisk()
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
    public var solvedEscapeIds: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(solvedEscapeIds).sorted(), forKey: "brilly_solved_escape_ids")
        }
    }
    public var convertedAdvantageIds: Set<String> = []
    public var boardVisionBestScore: Int = 0
    public var puzzleRushBlitzBest: Int = 0
    public var puzzleRushSurvivalBest: Int = 0

    // MARK: - Engine & Storage
    /// Background analysis engine (single + batch review) powered by MIT-licensed Renegade NNUE (~3300+ Elo offline).
    public let engine = RenegadeEngine()
    /// Dedicated pure-Swift engine for interactive Play Bot, Sandbox, Conversion, and Endgame drills so batch analysis never blocks them.
    public let interactiveEngine = BrillyNativeEngine()
    private let vault = LocalVaultStore()

    @ObservationIgnored private var isHydrated: Bool = false
    @ObservationIgnored private var hydrationTask: Task<Void, Never>? = nil
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
            openProPaywall(feature: "All \(starterCourses.count) Opening Courses (incl. QGD, QGA & Pro Gambits)")
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
        self.emojiPack = BrillyEmojiPack(rawValue: defaults.string(forKey: "brilly_emoji_pack") ?? "") ?? .mindBlown
        self.creatorNameMaskMode = CreatorNameMaskMode(rawValue: defaults.string(forKey: "brilly_creator_name_mask") ?? "") ?? .off
        self.creatorExhibitionTheme = CreatorExhibitionTheme(rawValue: defaults.string(forKey: "brilly_creator_exhibition_theme") ?? "") ?? .none
        self.creatorEventRibbonText = defaults.string(forKey: "brilly_creator_event_ribbon") ?? "WORLD CHAMPIONSHIP 2026"
        self.creatorShowHandleOnCards = defaults.bool(forKey: "brilly_creator_show_handle")
        self.boardTheme = BoardThemeID(rawValue: defaults.string(forKey: "brilly_board_theme") ?? "") ?? .slate
        self.showBoardCoordinates = defaults.object(forKey: "brilly_show_board_coordinates") as? Bool ?? true
        self.pieceSet = PieceSetID(rawValue: defaults.string(forKey: "brilly_piece_set") ?? "") ?? .cburnett
        self.analysisPreset = AnalysisDepthPreset(rawValue: defaults.integer(forKey: "brilly_analysis_preset")) ?? .balanced
        self.hapticsEnabled = defaults.object(forKey: "brilly_haptics_enabled") as? Bool ?? true
        self.soundEnabled = defaults.object(forKey: "brilly_sound_enabled") as? Bool ?? true
        self.celebrationsEnabled = defaults.object(forKey: "brilly_celebrations_enabled") as? Bool ?? true
        self.hasConfiguredDailyOpenings = defaults.bool(forKey: "brilly_daily_opening_configured")
        let completedOnboarding = defaults.bool(forKey: "brilly_has_completed_onboarding")
        self.hasCompletedOnboarding = completedOnboarding
        let savedLaunchTab = BrillyTab(rawValue: defaults.string(forKey: "brilly_default_launch_tab") ?? "") ?? .train
        self.defaultLaunchTab = savedLaunchTab
        self.autoSyncOnLaunch = defaults.object(forKey: "brilly_auto_sync_on_launch") as? Bool ?? true
        self.showingWelcomeGuide = !completedOnboarding
        self.isShowingLaunchOverlay = completedOnboarding
        if completedOnboarding {
            self.selectedTab = savedLaunchTab
            self.hasAppliedInitialLaunchTab = true
        }
        let savedIds = defaults.stringArray(forKey: "brilly_daily_opening_course_ids") ?? []
        self.dailyOpeningCourseIds = Set(savedIds)
        let savedEscapeIds = defaults.stringArray(forKey: "brilly_solved_escape_ids") ?? []
        self.solvedEscapeIds = Set(savedEscapeIds)
        self.isLichessHandleLocked = defaults.bool(forKey: "brilly_lichess_handle_locked")
        self.isChessComHandleLocked = defaults.bool(forKey: "brilly_chesscom_handle_locked")

        self.starterCourses = (try? CourseRepository.loadStarterCourses()) ?? []
        self.recentGames = LichessClient.sampleGames()
        self.launchOverlayStatusText = self.vibeMode == .cosmic ? "Warming up cockpit…" : "Loading BrillyDer…"

        self.hydrationTask = Task {
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

    public func completeOnboarding(applyDefaultTab: Bool = true) {
        hasCompletedOnboarding = true
        showingWelcomeGuide = false
        isShowingLaunchOverlay = false
        if applyDefaultTab && !hasAppliedInitialLaunchTab {
            selectedTab = defaultLaunchTab
            hasAppliedInitialLaunchTab = true
        }
    }

    public func dismissLaunchOverlay() {
        isShowingLaunchOverlay = false
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
            // Keep batch analysis running under its UIBackgroundTask so background completion + local notification actually fire.
            flushToDiskNow()
        } else {
            if soundEnabled {
                BrillySoundEngine.shared.resumeIfNeeded()
            }
            validateDailyStreakLiveness()
            resumePausedBatchIfNeeded()
            Task {
                await storeKit.refreshEntitlements()
                await runQuietAutoSyncIfEligible(isColdLaunch: false)
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
        let event = CelebrationEvent(kind: kind, vibe: vibeMode, calloutStyle: effectiveCalloutStyle, emojiPack: effectiveEmojiPack)
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
        // Auto-lock already-saved handles for upgrading users unless they explicitly cleared them
        if !snap.lichessUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           UserDefaults.standard.object(forKey: "brilly_lichess_handle_locked") == nil {
            self.isLichessHandleLocked = true
        }
        if !snap.chessComUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           UserDefaults.standard.object(forKey: "brilly_chesscom_handle_locked") == nil {
            self.isChessComHandleLocked = true
        }
        self.woodpeckerCycle = snap.woodpeckerCycle
        self.masteredEndgameIds = Set(snap.masteredEndgameIds)
        self.convertedAdvantageIds = Set(snap.convertedAdvantageIds)
        if !snap.solvedEscapeIds.isEmpty {
            self.solvedEscapeIds.formUnion(snap.solvedEscapeIds)
        }
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
        cleanupOrphanedLiveActivitiesIfIdle()

        // Never block the cold-launch overlay on slow/captive networks: dismiss promptly and sync in background.
        let hasSavedHandle = !lichessUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !chessComUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasCompletedOnboarding && selectedTab == .analyze && !hasPinnedManualGameSelection {
            autoLoadLatestGameIfAppropriate(switchToAnalyze: false)
        }
        if isShowingLaunchOverlay {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(280))
                self?.dismissLaunchOverlay()
            }
        }
        if hasCompletedOnboarding && effectiveAutoSyncOnLaunch && hasSavedHandle {
            Task { @MainActor [weak self] in
                await self?.runQuietAutoSyncIfEligible(isColdLaunch: true)
            }
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
                // Coalesce burst writes (e.g. batch analysis games / FSRS cards) to avoid JSON RAM spikes
                try? await Task.sleep(for: .milliseconds(900))
                if Task.isCancelled { break }
                saveDirty = false
                let snap = currentSnapshot()
                try? await vault.save(snap)
            }
            saveLoopTask = nil
        }
    }

    public func flushToDiskAndWait() async {
        guard isHydrated else { return }
        saveLoopTask?.cancel()
        saveLoopTask = nil
        saveDirty = false
        let snap = currentSnapshot()
        try? await vault.save(snap)
    }

    public func flushToDiskNow() {
        guard isHydrated else { return }
        saveLoopTask?.cancel()
        saveLoopTask = nil
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
            solvedEscapeIds: Array(solvedEscapeIds).sorted(),
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
        self.solvedEscapeIds.formUnion(merged.solvedEscapeIds)
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

    /// Ensures imported PGNs & Broadcasts (which often have date-only headers without UTCTime)
    /// always sort cleanly at the top of the Games list instead of getting buried under games played later today.
    private func stampImportedGame(_ record: GameRecord) -> GameRecord {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let stampedAt = max(record.createdAt, nowMs)
        guard stampedAt != record.createdAt else { return record }
        return GameRecord(
            id: record.id,
            source: record.source,
            rated: record.rated,
            variant: record.variant,
            speed: record.speed,
            perf: record.perf,
            createdAt: stampedAt,
            status: record.status,
            winner: record.winner,
            resultString: record.resultString,
            timeControlLabel: record.timeControlLabel,
            pgn: record.pgn,
            openingName: record.openingName,
            openingEco: record.openingEco,
            openingPly: record.openingPly,
            white: record.white,
            black: record.black,
            userColor: record.userColor,
            url: record.url
        )
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
                let rawRecord = try await LichessClient.fetchSingleGame(
                    urlOrId: urlOrId,
                    preferredUsername: active,
                    preferredUsernames: handles
                )
                guard self.syncGeneration == gen, !Task.isCancelled else { return }
                let record = self.stampImportedGame(rawRecord)
                self.recentGames.removeAll { $0.id == record.id }
                self.recentGames.insert(record, at: 0)
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
                    // Preserve pasted PGNs, broadcast/imported games, analyzed games, bookmarked games, and other-platform games
                    let fetchedIds = Set(fetched.map(\.id))
                    let bookmarkedGameIds = Set(self.bookmarks.map(\.gameId))
                    let preserved = self.recentGames.filter { rec in
                        rec.source != .sample && !fetchedIds.contains(rec.id) &&
                        (rec.source == .pgn ||
                         rec.source != platform ||
                         self.analyzedGames.contains(where: { ag in ag.id == rec.id }) ||
                         bookmarkedGameIds.contains(rec.id))
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

    @ObservationIgnored private var isQuietSyncing: Bool = false

    /// Quiet, throttled background sync for Pro users on cold launch and foreground resume.
    /// Never overwrites `syncErrorMessage` or triggers error haptics when offline.
    public func runQuietAutoSyncIfEligible(isColdLaunch: Bool) async {
        guard isHydrated, hasCompletedOnboarding, effectiveAutoSyncOnLaunch, !isSyncing, !isQuietSyncing else { return }
        isQuietSyncing = true
        defer { isQuietSyncing = false }

        let liHandle = lichessUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let ccHandle = chessComUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPlatform: GameSource
        let resolvedHandle: String
        if syncPlatform == .chesscom && !ccHandle.isEmpty {
            resolvedPlatform = .chesscom
            resolvedHandle = ccHandle
        } else if syncPlatform == .lichess && !liHandle.isEmpty {
            resolvedPlatform = .lichess
            resolvedHandle = liHandle
        } else if !ccHandle.isEmpty {
            resolvedPlatform = .chesscom
            resolvedHandle = ccHandle
        } else if !liHandle.isEmpty {
            resolvedPlatform = .lichess
            resolvedHandle = liHandle
        } else {
            return
        }

        if !isColdLaunch, let last = lastAutoSyncDate,
           Date().timeIntervalSince(last) < BrillyEntitlementPolicy.autoSyncThrottleSeconds {
            return
        }
        lastAutoSyncDate = Date()

        do {
            let fetched: [GameRecord]
            if resolvedPlatform == .chesscom {
                fetched = try await ChessComClient.fetchRecentGames(username: resolvedHandle, maxGames: 20)
            } else {
                fetched = try await LichessClient.fetchRecentGames(username: resolvedHandle, maxGames: 20)
            }
            guard !Task.isCancelled else { return }
            if !fetched.isEmpty {
                let fetchedIds = Set(fetched.map(\.id))
                let bookmarkedGameIds = Set(self.bookmarks.map(\.gameId))
                let preserved = self.recentGames.filter { rec in
                    rec.source != .sample && !fetchedIds.contains(rec.id) &&
                    (rec.source == .pgn ||
                     rec.source != resolvedPlatform ||
                     self.analyzedGames.contains(where: { ag in ag.id == rec.id }) ||
                     bookmarkedGameIds.contains(rec.id))
                }
                self.recentGames = (fetched + preserved).sorted { $0.createdAt > $1.createdAt }
                self.persistToDisk()
            }
            if !hasPinnedManualGameSelection && (selectedTab == .analyze || (isColdLaunch && defaultLaunchTab == .analyze)) {
                autoLoadLatestGameIfAppropriate(switchToAnalyze: false)
            }
        } catch {
            // Silent fail when offline or rate-limited; if on Analyze with a cached latest game, still ensure it's loaded.
            if isColdLaunch && selectedTab == .analyze && !hasPinnedManualGameSelection {
                autoLoadLatestGameIfAppropriate(switchToAnalyze: false)
            }
        }
    }

    /// Auto-loads (and starts analyzing if unanalyzed) the most recent real game when the user
    /// has not manually pinned a different game and no active analysis/sandbox is running.
    public func autoLoadLatestGameIfAppropriate(switchToAnalyze: Bool = false) {
        guard isHydrated else { return }
        let latest = recentGames.first(where: { $0.source != .sample }) ?? recentGames.first
        guard let latest else { return }
        guard BrillyEntitlementPolicy.shouldAutoOpenLatestGame(
            isPinnedManualSelection: hasPinnedManualGameSelection,
            isAnalyzing: isAnalyzing,
            isBatchAnalyzing: isBatchAnalyzing,
            hasActiveSandbox: activeSandboxFen != nil,
            latestGameId: latest.id,
            currentAnalyzedGameId: activeAnalyzedGame?.id
        ) else {
            return
        }
        // Only auto-start a brand-new analysis if the user has quota/Pro (avoid popping a paywall unprompted on tab switch).
        if !canAnalyzeGame(latest.id) {
            return
        }
        startAnalysis(for: latest, jumpToPly: nil, isManualSelection: false, switchToAnalyze: switchToAnalyze)
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
            let rawRecord = try LichessClient.parsePastedPGN(
                pgn,
                preferredUsername: activeUsername,
                preferredUsernames: userHandles
            )
            let record = stampImportedGame(rawRecord)
            recentGames.removeAll { $0.id == record.id }
            recentGames.insert(record, at: 0)
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
        hasPinnedManualGameSelection = true
        activeSandboxFen = fen
        selectedTab = .analyze
        triggerHaptic(.move)
    }

    // MARK: - Single & Batch Game Analysis

    public func startAnalysis(
        for game: GameRecord,
        jumpToPly: Int? = nil,
        isManualSelection: Bool = true,
        switchToAnalyze: Bool = true,
        forceReanalyze: Bool = false
    ) {
        if isManualSelection {
            hasPinnedManualGameSelection = true
        }
        activeSandboxFen = nil
        let wasAlreadyCached = analyzedGames.contains(where: { $0.id == game.id })
        let isSampleGame = game.source == .sample
        if !forceReanalyze, let cached = analyzedGames.first(where: { $0.id == game.id }) {
            activeAnalyzedGame = cached
            pendingAnalyzePly = jumpToPly
            if switchToAnalyze {
                selectedTab = .analyze
            }
            return
        }

        if !wasAlreadyCached && !isSampleGame && !canAnalyzeGame(game.id) {
            openProPaywall(feature: "Unlimited Game Analysis (2/day Free limit reached)")
            return
        }

        cancelBatchAnalysis()
        analysisTask?.cancel()
        analysisGeneration &+= 1
        let gen = analysisGeneration

        isAnalyzing = true
        analysisProgress = 0
        let wName = maskedPlayerName(game.white.name, opponent: game.black.name, side: .white).text
        let bName = maskedPlayerName(game.black.name, opponent: game.white.name, side: .black).text
        analyzingMatchupTitle = "\(wName) vs \(bName)"
        analysisStatusText = copy(cosmic: "Scanning trajectory…", classic: "Analyzing game…")
        if switchToAnalyze {
            selectedTab = .analyze
        }

        let preset = effectiveAnalysisPreset
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
                    if !wasAlreadyCached && !isSampleGame {
                        self.recordFreeAnalysisConsumed()
                    }
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

    public func reanalyzeActiveGame(preset: AnalysisDepthPreset, currentPly: Int? = nil) {
        if preset.isSingleGameOnly && !hasProAccess {
            openProPaywall(feature: "Ultra & Stockfish 16 Cloud Review")
            return
        }
        analysisPreset = preset
        guard let ag = activeAnalyzedGame else { return }
        startAnalysis(
            for: ag.game,
            jumpToPly: currentPly,
            isManualSelection: true,
            switchToAnalyze: true,
            forceReanalyze: true
        )
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
        let preset: AnalysisDepthPreset = analysisPreset.isSingleGameOnly ? .deep : analysisPreset
        runBatchAnalysis(targets: targets, preset: preset)
    }

    private func runBatchAnalysis(
        targets: [GameRecord],
        preset: AnalysisDepthPreset,
        priorCompleted: Int = 0,
        originalTotal: Int? = nil
    ) {
        guard !targets.isEmpty else { return }

        cancelAnalysis()
        batchTask?.cancel()
        batchGeneration &+= 1
        let gen = batchGeneration

        let totalGames = max(originalTotal ?? targets.count, priorCompleted + targets.count)
        pendingBatchTargets = targets
        pendingBatchPreset = preset
        isBatchAnalyzing = true
        batchCompletedGames = priorCompleted
        batchTotalGames = totalGames
        batchProgress = max(0.02, Double(priorCompleted) / Double(max(1, totalGames)))
        batchCurrentLabel = "Game \(priorCompleted + 1) of \(totalGames) · Preparing…"
        persistPendingBatchQueue()
        triggerHaptic(.move)

        let engineRef = engine

        #if canImport(UserNotifications) && os(iOS)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        #endif

        #if canImport(UIKit) && os(iOS)
        UIApplication.shared.isIdleTimerDisabled = true
        endBatchBackgroundTask()
        batchBackgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "BrillyDerBatchAnalysis") { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // If iOS 26+ BGContinuedProcessingTask or BGProcessingTask is active, release the 30s token without pausing!
                if self.hasActiveExtendedBackgroundTask {
                    self.endBatchBackgroundTask()
                } else {
                    await self.pauseBatchForBackgroundExpiry()
                }
            }
        }
        #endif

        beginContinuedProcessingTaskIfAvailable(preset: preset, totalGames: totalGames)

        if priorCompleted == 0 {
            startBatchLiveActivity(preset: preset, totalGames: totalGames)
        } else {
            updateBatchLiveActivity(
                completedGames: priorCompleted,
                currentGameIndex: min(totalGames, priorCompleted + 1),
                currentPly: 0,
                totalPlies: 0,
                matchup: "Resuming scan…",
                progress: batchProgress,
                status: "analyzing"
            )
        }

        batchTask = Task.detached(priority: .userInitiated) {
            for (idx, game) in targets.enumerated() {
                if Task.isCancelled { break }
                let globalDoneBefore = priorCompleted + idx
                let globalGameNum = min(totalGames, globalDoneBefore + 1)
                let matchupText: String = await MainActor.run {
                    guard self.batchGeneration == gen else { return "" }
                    let whiteLabel = self.maskedPlayerName(game.white.name, side: .white).text
                    let blackLabel = self.maskedPlayerName(game.black.name, side: .black).text
                    let m = "\(whiteLabel) vs \(blackLabel)"
                    self.batchCurrentLabel = "Game \(globalGameNum)/\(totalGames) · \(preset.title) · \(m)"
                    self.updateBatchLiveActivity(
                        completedGames: self.batchCompletedGames,
                        currentGameIndex: globalGameNum,
                        currentPly: 0,
                        totalPlies: 0,
                        matchup: m,
                        progress: Double(globalDoneBefore) / Double(max(1, totalGames)),
                        status: "analyzing"
                    )
                    return m
                }
                do {
                    let result = try await GameAnalyzer.analyze(
                        game: game,
                        engine: engineRef,
                        preset: preset,
                        isBatch: true
                    ) { donePlies, totalPlies in
                        let sub = Double(donePlies) / Double(max(1, totalPlies))
                        let overall = (Double(globalDoneBefore) + sub) / Double(max(1, totalGames))
                        let shouldPushLive = (donePlies == totalPlies) || (donePlies % 6 == 0)
                        Task { @MainActor in
                            guard self.batchGeneration == gen else { return }
                            self.batchProgress = overall
                            self.batchCurrentLabel = "Game \(globalGameNum)/\(totalGames) (\(preset.title)) · Ply \(donePlies)/\(totalPlies)"
                            if shouldPushLive {
                                self.updateBatchLiveActivity(
                                    completedGames: self.batchCompletedGames,
                                    currentGameIndex: globalGameNum,
                                    currentPly: donePlies,
                                    totalPlies: totalPlies,
                                    matchup: matchupText,
                                    progress: overall,
                                    status: "analyzing"
                                )
                            }
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
                        self.pendingBatchTargets.removeAll { $0.id == result.id }
                        self.batchCompletedGames += 1
                        self.batchProgress = Double(globalDoneBefore + 1) / Double(max(1, totalGames))
                        self.persistPendingBatchQueue()
                        self.updateBatchLiveActivity(
                            completedGames: self.batchCompletedGames,
                            currentGameIndex: min(totalGames, globalGameNum + 1),
                            currentPly: 0,
                            totalPlies: 0,
                            matchup: matchupText,
                            progress: self.batchProgress,
                            status: "analyzing"
                        )
                        self.persistToDisk()
                    }
                } catch is CancellationError {
                    break
                } catch {
                    if Task.isCancelled { break }
                    // Remove permanently failed/corrupt game from pending queue so it doesn't loop on resume
                    await MainActor.run {
                        guard self.batchGeneration == gen else { return }
                        self.pendingBatchTargets.removeAll { $0.id == game.id }
                    }
                }
            }
            let cancelled = Task.isCancelled
            await MainActor.run {
                guard self.batchGeneration == gen else { return }
                let doneCount = self.batchCompletedGames
                self.isBatchAnalyzing = false
                self.batchCurrentLabel = ""
                if !cancelled {
                    self.pendingBatchTargets = []
                    self.pendingBatchPreset = nil
                    self.persistPendingBatchQueue()
                    self.cancelScheduledBackgroundProcessing()
                    self.batchProgress = 1.0
                    self.triggerHaptic(.success)
                }
                #if canImport(UIKit) && os(iOS)
                UIApplication.shared.isIdleTimerDisabled = false
                #endif
                Task { @MainActor in
                    if !cancelled {
                        await self.endBatchLiveActivity(
                            completedGames: doneCount,
                            totalGames: totalGames,
                            status: "complete",
                            dismissAfterSeconds: 8
                        )
                        await self.postBatchNotification(
                            title: "BrillyDer Batch Scan Complete",
                            body: "Analyzed \(doneCount) game\(doneCount == 1 ? "" : "s") at \(preset.title) depth. Tap to review your mistakes & !! moves."
                        )
                    }
                    self.completeActiveExtendedBackgroundTasks(success: !cancelled)
                    self.endBatchBackgroundTask()
                }
            }
        }
    }

    #if canImport(BackgroundTasks) && os(iOS)
    /// Atomic once-guard guaranteeing every `BGTask` calls `setTaskCompleted(success:)` at least once and at most once.
    private final class BGTaskOnceBox: @unchecked Sendable {
        private let lock = NSLock()
        private let task: BGTask
        private var finished: Bool = false

        init(_ task: BGTask) {
            self.task = task
        }

        func complete(success: Bool) {
            lock.lock()
            let shouldComplete = !finished
            finished = true
            lock.unlock()
            if shouldComplete {
                task.setTaskCompleted(success: success)
            }
        }

        @available(iOS 26.0, *)
        var asContinued: BGContinuedProcessingTask? {
            task as? BGContinuedProcessingTask
        }
    }

    /// `nonisolated static` wrapper so Swift 6 NEVER injects `@MainActor` `swift_task_isCurrentExecutor`
    /// assertions into `BGTaskScheduler.register` launchHandler or `task.expirationHandler` (both execute on background queues).
    private nonisolated static func registerNonIsolatedBGTask(
        identifier: String,
        onLaunch: @escaping @Sendable (BGTaskOnceBox) -> Void,
        onExpire: @escaping @Sendable (BGTaskOnceBox) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let box = BGTaskOnceBox(task)
            // Assign expirationHandler SYNCHRONOUSLY inside launchHandler before returning (BGTask.h requirement)
            task.expirationHandler = {
                onExpire(box)
            }
            onLaunch(box)
        }
    }

    private nonisolated static func submitBGTaskRequestOffMain(_ request: BGTaskRequest) {
        nonisolated(unsafe) let req = request
        Task.detached(priority: .utility) {
            try? BGTaskScheduler.shared.submit(req)
        }
    }
    #endif

    @ObservationIgnored private var pendingBatchTargets: [GameRecord] = []
    @ObservationIgnored private var pendingBatchPreset: AnalysisDepthPreset? = nil
    @ObservationIgnored private static var hasRegisteredBGTasksProcessWide: Bool = false
    @ObservationIgnored private var registeredProcessingTaskID: String? = nil
    @ObservationIgnored private var registeredContinuedTaskID: String? = nil
    @ObservationIgnored private var isPausingForExpiry: Bool = false
    #if canImport(BackgroundTasks) && os(iOS)
    @ObservationIgnored private var activeContinuedBox: BGTaskOnceBox? = nil
    @ObservationIgnored private var activeBGProcessingBox: BGTaskOnceBox? = nil
    #endif
    #if canImport(UIKit) && os(iOS)
    @ObservationIgnored private var batchBackgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    #endif

    private var hasActiveExtendedBackgroundTask: Bool {
        #if canImport(BackgroundTasks) && os(iOS)
        return activeContinuedBox != nil || activeBGProcessingBox != nil
        #else
        return false
        #endif
    }

    private var permittedBGTaskIdentifiers: [String] {
        Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
    }

    private static var pendingBatchFileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = dir.appendingPathComponent("BrillyDer", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("pending_batch_targets.json")
    }

    private func persistPendingBatchQueue() {
        let targets = pendingBatchTargets
        let ids = targets.map(\.id)
        if ids.isEmpty {
            UserDefaults.standard.removeObject(forKey: "brilly_pending_batch_ids")
            UserDefaults.standard.removeObject(forKey: "brilly_pending_batch_preset")
            UserDefaults.standard.removeObject(forKey: "brilly_pending_batch_total")
            UserDefaults.standard.removeObject(forKey: "brilly_pending_batch_done")
            if let url = Self.pendingBatchFileURL {
                try? FileManager.default.removeItem(at: url)
            }
        } else {
            UserDefaults.standard.set(ids, forKey: "brilly_pending_batch_ids")
            if let preset = pendingBatchPreset {
                UserDefaults.standard.set(preset.rawValue, forKey: "brilly_pending_batch_preset")
            }
            UserDefaults.standard.set(batchTotalGames, forKey: "brilly_pending_batch_total")
            UserDefaults.standard.set(batchCompletedGames, forKey: "brilly_pending_batch_done")
            if let url = Self.pendingBatchFileURL,
               let data = try? JSONEncoder().encode(targets) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func restorePendingBatchQueueIfNeeded() {
        guard pendingBatchTargets.isEmpty else { return }
        let analyzedIds = Set(analyzedGames.map(\.id))

        // Prefer full persisted GameRecord array (works even on cold BGProcessingTask wakeups!)
        var restored: [GameRecord] = []
        if let url = Self.pendingBatchFileURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([GameRecord].self, from: data) {
            restored = decoded.filter { !analyzedIds.contains($0.id) }
        }
        if restored.isEmpty,
           let savedIds = UserDefaults.standard.stringArray(forKey: "brilly_pending_batch_ids"),
           !savedIds.isEmpty {
            let gamesById = Dictionary(recentGames.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            restored = savedIds.compactMap { id -> GameRecord? in
                guard !analyzedIds.contains(id) else { return nil }
                return gamesById[id]
            }
        }

        guard !restored.isEmpty else {
            persistPendingBatchQueue()
            return
        }
        pendingBatchTargets = restored
        let rawPreset = UserDefaults.standard.integer(forKey: "brilly_pending_batch_preset")
        pendingBatchPreset = AnalysisDepthPreset(rawValue: rawPreset) ?? .balanced
        batchTotalGames = max(UserDefaults.standard.integer(forKey: "brilly_pending_batch_total"), restored.count)
        batchCompletedGames = max(UserDefaults.standard.integer(forKey: "brilly_pending_batch_done"), max(0, batchTotalGames - restored.count))
    }

    /// Registers the iOS 18+ `BGProcessingTask` and iOS 26+ `BGContinuedProcessingTask` handlers
    /// strictly once per process during app launch using `nonisolated` Swift-6-safe callbacks.
    public func registerBackgroundBatchTasks() {
        #if canImport(BackgroundTasks) && os(iOS)
        guard !Self.hasRegisteredBGTasksProcessWide else { return }
        Self.hasRegisteredBGTasksProcessWide = true

        let permitted = permittedBGTaskIdentifiers
        if let processingId = permitted.first(where: { $0.hasSuffix(".batch-processing") }) {
            let ok = Self.registerNonIsolatedBGTask(
                identifier: processingId,
                onLaunch: { [weak self] box in
                    Task { @MainActor [weak self] in
                        guard let self else {
                            box.complete(success: false)
                            return
                        }
                        await self.handleBackgroundProcessingWakeup(box)
                    }
                },
                onExpire: { [weak self] box in
                    Task { @MainActor [weak self] in
                        guard let self else {
                            box.complete(success: false)
                            return
                        }
                        await self.pauseBatchForBackgroundExpiry()
                        box.complete(success: false)
                    }
                }
            )
            if ok {
                registeredProcessingTaskID = processingId
            }
        }

        if #available(iOS 26.0, *),
           let bundleId = Bundle.main.bundleIdentifier,
           let wildcard = permitted.first(where: { $0.hasSuffix(".*") && $0.hasPrefix(bundleId + ".") }) {
            let concreteId = String(wildcard.dropLast(1)) + "batch"
            let ok = Self.registerNonIsolatedBGTask(
                identifier: concreteId,
                onLaunch: { [weak self] box in
                    Task { @MainActor [weak self] in
                        guard let self else {
                            box.complete(success: false)
                            return
                        }
                        // Never overwrite an uncompleted previous task
                        if let prev = self.activeContinuedBox {
                            prev.complete(success: false)
                        }
                        self.activeContinuedBox = box
                        if let continued = box.asContinued {
                            let totalUnits = Int64(max(1, self.batchTotalGames * 100))
                            continued.progress.totalUnitCount = totalUnits
                            continued.progress.completedUnitCount = Int64((self.batchProgress * Double(totalUnits)).rounded())
                        }
                        if !self.isBatchAnalyzing && self.pendingBatchTargets.isEmpty {
                            self.completeActiveExtendedBackgroundTasks(success: true)
                        }
                    }
                },
                onExpire: { [weak self] box in
                    Task { @MainActor [weak self] in
                        guard let self else {
                            box.complete(success: false)
                            return
                        }
                        await self.pauseBatchForBackgroundExpiry()
                        box.complete(success: false)
                    }
                }
            )
            if ok {
                registeredContinuedTaskID = concreteId
            }
        }
        #endif
    }

    #if canImport(BackgroundTasks) && os(iOS)
    private func handleBackgroundProcessingWakeup(_ box: BGTaskOnceBox) async {
        if let prev = activeBGProcessingBox {
            prev.complete(success: false)
        }
        activeBGProcessingBox = box
        // Ensure disk vault is hydrated before inspecting analyzedGames / pending queue
        if let h = hydrationTask {
            await h.value
        }
        restorePendingBatchQueueIfNeeded()
        if pendingBatchTargets.isEmpty {
            completeActiveExtendedBackgroundTasks(success: true)
            return
        }
        resumePausedBatchIfNeeded()
        if let running = batchTask {
            await running.value
        }
        // If expirationHandler is mid-cleanup, let pauseBatchForBackgroundExpiry call setTaskCompleted after flushing disk
        if !isPausingForExpiry {
            await flushToDiskAndWait()
            completeActiveExtendedBackgroundTasks(success: pendingBatchTargets.isEmpty)
        }
    }
    #endif

    /// On iOS 26+, submits a pre-registered `BGContinuedProcessingTaskRequest` off the main thread
    /// so batch analysis keeps running for minutes in the background.
    private func beginContinuedProcessingTaskIfAvailable(preset: AnalysisDepthPreset, totalGames: Int) {
        #if canImport(BackgroundTasks) && os(iOS)
        if #available(iOS 26.0, *) {
            guard activeContinuedBox == nil,
                  activeBGProcessingBox == nil,
                  let taskId = registeredContinuedTaskID else { return }
            let req = BGContinuedProcessingTaskRequest(
                identifier: taskId,
                title: "Analyzing \(totalGames) Game\(totalGames == 1 ? "" : "s")",
                subtitle: "\(preset.title) · \(preset.eloEstimate)"
            )
            req.strategy = .queue
            Self.submitBGTaskRequestOffMain(req)
        }
        #endif
    }

    private func updateContinuedProcessingProgress(
        currentGameIndex: Int,
        totalGames: Int,
        matchup: String,
        progress: Double
    ) {
        #if canImport(BackgroundTasks) && os(iOS)
        if #available(iOS 26.0, *), let task = activeContinuedBox?.asContinued {
            let totalUnits = Int64(max(1, totalGames * 100))
            task.progress.totalUnitCount = totalUnits
            task.progress.completedUnitCount = min(totalUnits, max(0, Int64((progress * Double(totalUnits)).rounded())))
            task.updateTitle(
                "Analyzing \(totalGames) Game\(totalGames == 1 ? "" : "s")",
                subtitle: "Game \(currentGameIndex)/\(totalGames) · \(matchup)"
            )
        }
        #endif
    }

    private func scheduleBackgroundProcessingFallback() {
        #if canImport(BackgroundTasks) && os(iOS)
        guard !pendingBatchTargets.isEmpty, let processingId = registeredProcessingTaskID else { return }
        let req = BGProcessingTaskRequest(identifier: processingId)
        req.requiresNetworkConnectivity = false
        req.requiresExternalPower = false
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        Self.submitBGTaskRequestOffMain(req)
        #endif
    }

    private func cancelScheduledBackgroundProcessing() {
        #if canImport(BackgroundTasks) && os(iOS)
        if let processingId = registeredProcessingTaskID {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingId)
        }
        if activeContinuedBox == nil, let continuedId = registeredContinuedTaskID {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: continuedId)
        }
        #endif
    }

    private func completeActiveExtendedBackgroundTasks(success: Bool) {
        #if canImport(BackgroundTasks) && os(iOS)
        if let continued = activeContinuedBox {
            activeContinuedBox = nil
            continued.complete(success: success)
        }
        if let processing = activeBGProcessingBox {
            activeBGProcessingBox = nil
            processing.complete(success: success)
        }
        #endif
    }

    #if canImport(ActivityKit) && os(iOS)
    @ObservationIgnored private var batchLiveActivityId: String? = nil
    @ObservationIgnored private var liveActivitySeq: UInt64 = 0

    private actor LiveActivitySerialQueue {
        private var lastAppliedSeq: UInt64 = 0

        func update(
            id: String,
            seq: UInt64,
            state: BrillyBatchActivityAttributes.ContentState,
            staleDate: Date?
        ) async {
            guard seq >= lastAppliedSeq else { return }
            lastAppliedSeq = seq
            guard let activity = Activity<BrillyBatchActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            await activity.update(ActivityContent(state: state, staleDate: staleDate))
        }

        func end(
            id: String,
            seq: UInt64,
            state: BrillyBatchActivityAttributes.ContentState?,
            dismissAfterSeconds: TimeInterval?
        ) async {
            guard seq >= lastAppliedSeq else { return }
            lastAppliedSeq = seq
            guard let activity = Activity<BrillyBatchActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            let content = state.map { ActivityContent(state: $0, staleDate: nil) }
            let policy: ActivityUIDismissalPolicy = dismissAfterSeconds.map { .after(Date().addingTimeInterval($0)) } ?? .immediate
            await activity.end(content, dismissalPolicy: policy)
        }

        func endAllOrphans(except keepId: String?) async {
            for activity in Activity<BrillyBatchActivityAttributes>.activities where activity.id != keepId {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static let liveActivityQueue = LiveActivitySerialQueue()
    #endif

    private func cleanupOrphanedLiveActivitiesIfIdle() {
        #if canImport(ActivityKit) && os(iOS)
        guard !isBatchAnalyzing else { return }
        let keepId = batchLiveActivityId
        Task.detached(priority: .utility) {
            await Self.liveActivityQueue.endAllOrphans(except: keepId)
        }
        #endif
    }

    private func startBatchLiveActivity(preset: AnalysisDepthPreset, totalGames: Int) {
        #if canImport(ActivityKit) && os(iOS)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        batchLiveActivityId = nil
        Task.detached {
            await Self.liveActivityQueue.endAllOrphans(except: nil)
        }
        let attrs = BrillyBatchActivityAttributes(
            presetTitle: preset.title,
            presetElo: preset.eloEstimate,
            totalGames: totalGames
        )
        let initialState = BrillyBatchActivityAttributes.ContentState(
            completedGames: 0,
            currentGameIndex: 1,
            currentPly: 0,
            totalPlies: 0,
            matchup: "Starting \(totalGames)-game scan…",
            progress: 0.02,
            status: "analyzing"
        )
        let content = ActivityContent(state: initialState, staleDate: Date().addingTimeInterval(120))
        if let created = try? Activity.request(attributes: attrs, content: content, pushType: nil) {
            batchLiveActivityId = created.id
        }
        #endif
    }

    private func updateBatchLiveActivity(
        completedGames: Int,
        currentGameIndex: Int,
        currentPly: Int,
        totalPlies: Int,
        matchup: String,
        progress: Double,
        status: String
    ) {
        #if canImport(ActivityKit) && os(iOS)
        if let id = batchLiveActivityId {
            liveActivitySeq &+= 1
            let seq = liveActivitySeq
            let state = BrillyBatchActivityAttributes.ContentState(
                completedGames: completedGames,
                currentGameIndex: currentGameIndex,
                currentPly: currentPly,
                totalPlies: totalPlies,
                matchup: matchup,
                progress: min(1.0, max(0.0, progress)),
                status: status
            )
            let stale = Date().addingTimeInterval(120)
            Task.detached {
                await Self.liveActivityQueue.update(id: id, seq: seq, state: state, staleDate: stale)
            }
        }
        #endif
        updateContinuedProcessingProgress(
            currentGameIndex: currentGameIndex,
            totalGames: max(1, batchTotalGames),
            matchup: matchup,
            progress: progress
        )
    }

    private func endBatchLiveActivity(
        completedGames: Int,
        totalGames: Int,
        status: String,
        dismissAfterSeconds: TimeInterval?
    ) async {
        #if canImport(ActivityKit) && os(iOS)
        guard let id = batchLiveActivityId else { return }
        batchLiveActivityId = nil
        liveActivitySeq &+= 1
        let seq = liveActivitySeq
        let finalState = BrillyBatchActivityAttributes.ContentState(
            completedGames: completedGames,
            currentGameIndex: totalGames,
            currentPly: 0,
            totalPlies: 0,
            matchup: status == "complete" ? "All \(completedGames) games ready to review" : "Scan cancelled",
            progress: status == "complete" ? 1.0 : batchProgress,
            status: status
        )
        await Self.liveActivityQueue.end(id: id, seq: seq, state: finalState, dismissAfterSeconds: dismissAfterSeconds)
        #endif
    }

    private func pauseBatchForBackgroundExpiry() async {
        guard !isPausingForExpiry else { return }
        isPausingForExpiry = true
        defer { isPausingForExpiry = false }

        let remaining = pendingBatchTargets.count
        let done = batchCompletedGames
        let total = batchTotalGames
        batchGeneration &+= 1
        batchTask?.cancel()
        batchTask = nil
        isBatchAnalyzing = false
        batchCurrentLabel = ""
        #if canImport(UIKit) && os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
        await flushToDiskAndWait()
        persistPendingBatchQueue()
        if remaining > 0 {
            scheduleBackgroundProcessingFallback()
            #if canImport(ActivityKit) && os(iOS)
            if let id = batchLiveActivityId {
                liveActivitySeq &+= 1
                let seq = liveActivitySeq
                let pausedState = BrillyBatchActivityAttributes.ContentState(
                    completedGames: done,
                    currentGameIndex: min(total, done + 1),
                    currentPly: 0,
                    totalPlies: 0,
                    matchup: "\(remaining) game\(remaining == 1 ? "" : "s") remaining — auto-resuming soon",
                    progress: Double(done) / Double(max(1, total)),
                    status: "paused"
                )
                await Self.liveActivityQueue.update(id: id, seq: seq, state: pausedState, staleDate: nil)
            }
            #endif
            await postBatchNotification(
                title: "BrillyDer Batch Paused (\(done)/\(total) Done)",
                body: "iOS paused background time. BrillyDer will auto-resume when idle, or open the app to continue the remaining \(remaining) game\(remaining == 1 ? "" : "s") now."
            )
        } else {
            cancelScheduledBackgroundProcessing()
            await endBatchLiveActivity(completedGames: done, totalGames: total, status: "complete", dismissAfterSeconds: 6)
        }
        completeActiveExtendedBackgroundTasks(success: remaining == 0)
        endBatchBackgroundTask()
    }

    private func resumePausedBatchIfNeeded() {
        restorePendingBatchQueueIfNeeded()
        guard !isBatchAnalyzing, !pendingBatchTargets.isEmpty else { return }
        let analyzedIds = Set(analyzedGames.map(\.id))
        let remaining = pendingBatchTargets.filter { !analyzedIds.contains($0.id) }
        guard !remaining.isEmpty else {
            pendingBatchTargets = []
            pendingBatchPreset = nil
            let done = batchCompletedGames
            let total = max(batchTotalGames, done)
            Task { @MainActor in
                await self.endBatchLiveActivity(completedGames: done, totalGames: total, status: "complete", dismissAfterSeconds: 5)
            }
            return
        }
        let preset = pendingBatchPreset ?? (analysisPreset.isSingleGameOnly ? .deep : analysisPreset)
        let priorDone = max(batchCompletedGames, max(0, batchTotalGames - remaining.count))
        let origTotal = max(batchTotalGames, priorDone + remaining.count)
        runBatchAnalysis(targets: remaining, preset: preset, priorCompleted: priorDone, originalTotal: origTotal)
    }

    private func endBatchBackgroundTask() {
        #if canImport(UIKit) && os(iOS)
        if batchBackgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(batchBackgroundTaskId)
            batchBackgroundTaskId = .invalid
        }
        #endif
    }

    private func postBatchNotification(title: String, body: String) async {
        #if canImport(UserNotifications) && os(iOS)
        guard UIApplication.shared.applicationState != .active else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: "brillyder.batch.\(UUID().uuidString)", content: content, trigger: nil)
        try? await center.add(req)
        #endif
    }

    public func cancelBatchAnalysis() {
        batchGeneration &+= 1
        batchTask?.cancel()
        batchTask = nil
        pendingBatchTargets = []
        pendingBatchPreset = nil
        persistPendingBatchQueue()
        cancelScheduledBackgroundProcessing()
        isBatchAnalyzing = false
        batchProgress = 0
        batchCurrentLabel = ""
        #if canImport(UIKit) && os(iOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
        let done = batchCompletedGames
        let total = batchTotalGames
        Task { @MainActor in
            await self.endBatchLiveActivity(completedGames: done, totalGames: total, status: "cancelled", dismissAfterSeconds: nil)
        }
        completeActiveExtendedBackgroundTasks(success: false)
        endBatchBackgroundTask()
    }

    public func openGameAtPly(gameId: String, ply: Int) {
        hasPinnedManualGameSelection = true
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

    public func markEscapeSolved(_ id: String) {
        solvedEscapeIds.insert(id)
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
            if dailyStreakDays >= 3 {
                notePositiveMilestoneForReview(.streakMilestone)
            }
        } else if dailyStreakDays < 1 {
            dailyStreakDays = 1
            persistToDisk()
        }
    }

    public enum ReviewMilestone: Sendable {
        case dailySessionCompleted
        case streakMilestone
        case shareCardExported
        case brilliantSaved
    }

    /// Respectful App Store rating prompt gate:
    /// - Never prompts on the personal `BrillyDerAdmin` target
    /// - At most once per app marketing version (`CFBundleShortVersionString`)
    /// - Deferred cleanly via `pendingReviewRequestVersion` until no sheet is interrupting the user
    public func notePositiveMilestoneForReview(_ milestone: ReviewMilestone) {
        guard edition == .appStore else { return }
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.11.3"
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: "brilly_last_review_prompt_version") != currentVersion else { return }

        switch milestone {
        case .dailySessionCompleted:
            let count = defaults.integer(forKey: "brilly_completed_daily_sessions") + 1
            defaults.set(count, forKey: "brilly_completed_daily_sessions")
            guard count >= 2 else { return }
        case .streakMilestone:
            guard dailyStreakDays >= 3 else { return }
        case .shareCardExported, .brilliantSaved:
            break
        }

        pendingReviewRequestVersion = currentVersion
    }

    public func markReviewPrompted(version: String) {
        UserDefaults.standard.set(version, forKey: "brilly_last_review_prompt_version")
        pendingReviewRequestVersion = nil
    }

    public func markDailySessionCompleted() {
        recordTrainingActivity()
        notePositiveMilestoneForReview(.dailySessionCompleted)
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

    public func updateBookmark(id: String, label: String, tags: [String]) {
        guard let idx = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        let cleanedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedLabel.isEmpty {
            bookmarks[idx].label = cleanedLabel
        }
        var seen = Set<String>()
        var cleanedTags: [String] = []
        for raw in tags {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                cleanedTags.append(trimmed)
            }
        }
        bookmarks[idx].tags = cleanedTags
        triggerHaptic(.success)
        persistToDisk()
    }

    public func toggleBookmark(ply: AnalyzedPly, game: GameRecord) {
        let canonical = "\(game.id)::\(ply.ply)"
        let legacy = "\(game.id)::ply::\(ply.ply)"
        if let idx = bookmarks.firstIndex(where: { $0.id == canonical || $0.id == legacy || ($0.gameId == game.id && $0.ply == ply.ply) }) {
            bookmarks.remove(at: idx)
        } else {
            let matchupText = "\(game.white.name) vs \(game.black.name)"
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
                createdAt: Int64(Date().timeIntervalSince1970 * 1000.0),
                tags: [],
                matchup: matchupText
            )
            bookmarks.insert(bm, at: 0)
            if ply.classification == .brilliant {
                notePositiveMilestoneForReview(.brilliantSaved)
            }
            triggerHaptic(.success)
        }
        persistToDisk()
    }
}
