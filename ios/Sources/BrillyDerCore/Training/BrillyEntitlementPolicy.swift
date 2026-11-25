import Foundation

/// App Store Connect In-App Purchase & Subscription product identifiers for BrillyDer Pro.
public enum BrillyProProductID: String, CaseIterable, Sendable, Identifiable, Codable {
    case annual   = "com.brillyder.pro.annual"
    case monthly  = "com.brillyder.pro.monthly"
    case lifetime = "com.brillyder.pro.lifetime"

    public var id: String { rawValue }

    public static let subscriptionGroupID = "brillyder_pro"
    public static var allRawValues: [String] { allCases.map(\.rawValue) }

    public var isSubscription: Bool {
        self == .monthly || self == .annual
    }

    public var planTitle: String {
        switch self {
        case .lifetime: return "Brilly/Der Pro · Lifetime"
        case .annual:   return "Brilly/Der Pro · Annual"
        case .monthly:  return "Brilly/Der Pro · Monthly"
        }
    }

    /// Reference fallback display labels used only before StoreKit returns localized App Store prices.
    public var fallbackTitle: String {
        switch self {
        case .annual:   return "Annual"
        case .monthly:  return "Monthly"
        case .lifetime: return "Lifetime"
        }
    }
}

/// Build-time application edition selected exclusively by the Xcode app target entry point.
/// - `.appStore`: Production App Store target (`com.brillyder.app`) — governed strictly by StoreKit 2 entitlements.
/// - `.founderAdmin`: Personal side-by-side Founder/Admin target (`com.brillyder.admin`) — all Pro features unlocked.
public enum BrillyAppEdition: String, Sendable, Equatable {
    case appStore
    case founderAdmin

    public var isAdminEdition: Bool { self == .founderAdmin }
}

/// Deterministic Free vs. Pro feature boundary rules shared across UI & unit tests.
public enum BrillyEntitlementPolicy {
    /// Free users can run full on-device game analysis on up to 2 new games per local calendar day.
    /// Re-opening previously analyzed games and syncing from Lichess / Chess.com are always unlimited and free.
    public static let freeDailyAnalysisLimit: Int = 2

    /// Two starter courses unlocked for Free FSRS opening drills (1 White + 1 Black).
    public static let freeStarterCourseIDs: Set<String> = [
        "london-system-core",
        "modern-defense-core",
    ]

    /// Classic Retina piece set unlocked on Free; additional 3 sets require Pro.
    public static let freePieceSetRawValue: String = "cburnett"

    /// Default Mind-Blown (`🤯 / 🤦`) emoji pair is Free; extra emoji packs & custom Share Card captions require Pro.
    public static let freeEmojiPackRawValue: String = "mindBlown"

    /// Classic 4 board themes are Free; premium themes (Obsidian, Championship Gold, Cyber Violet) require Pro.
    public static let freeBoardThemeRawValues: Set<String> = [
        "slate", "emerald", "walnut", "neon"
    ]

    /// Minimum interval between automatic background game syncs on foreground resume (90 seconds).
    public static let autoSyncThrottleSeconds: TimeInterval = 90

    public static func isCourseUnlocked(_ courseId: String, hasProAccess: Bool) -> Bool {
        hasProAccess || freeStarterCourseIDs.contains(courseId)
    }

    public static func isDurationUnlocked(_ duration: DailyDurationMinutes, hasProAccess: Bool) -> Bool {
        hasProAccess || duration == .ten
    }

    public static func isPieceSetUnlocked(rawValue: String, hasProAccess: Bool) -> Bool {
        hasProAccess || rawValue == freePieceSetRawValue
    }

    public static func isEmojiPackUnlocked(rawValue: String, hasProAccess: Bool) -> Bool {
        hasProAccess || rawValue == freeEmojiPackRawValue
    }

    public static func isBoardThemeUnlocked(rawValue: String, hasProAccess: Bool) -> Bool {
        hasProAccess || freeBoardThemeRawValues.contains(rawValue)
    }

    /// Automatic sync on app launch / foreground resume is a Pro convenience perk; manual sync is always unlimited & free.
    public static func isAutoSyncOnLaunchUnlocked(hasProAccess: Bool) -> Bool {
        hasProAccess
    }

    /// Determines whether the Analyze tab should automatically load/analyze the latest synced game
    /// without overriding a user's manual selection, running analysis, or custom FEN sandbox.
    public static func shouldAutoOpenLatestGame(
        isPinnedManualSelection: Bool,
        isAnalyzing: Bool,
        isBatchAnalyzing: Bool,
        hasActiveSandbox: Bool,
        latestGameId: String?,
        currentAnalyzedGameId: String?
    ) -> Bool {
        guard !isPinnedManualSelection,
              !isAnalyzing,
              !isBatchAnalyzing,
              !hasActiveSandbox,
              let latestGameId,
              !latestGameId.isEmpty else {
            return false
        }
        return latestGameId != currentAnalyzedGameId
    }

    public static func remainingFreeAnalyses(usedToday: Int, hasProAccess: Bool) -> Int {
        if hasProAccess { return Int.max }
        return max(0, freeDailyAnalysisLimit - max(0, usedToday))
    }

    public static func canStartNewAnalysis(
        isAlreadyCached: Bool,
        usedToday: Int,
        hasProAccess: Bool
    ) -> Bool {
        if hasProAccess || isAlreadyCached { return true }
        return max(0, usedToday) < freeDailyAnalysisLimit
    }

    /// Formats a local calendar day key (`YYYY-MM-DD`) so daily analysis quota resets cleanly at local midnight.
    public static func localDayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 2026
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
