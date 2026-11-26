import Foundation

public enum FSRSRating: Int, Codable, Hashable, Sendable {
    case again = 1
    case hard = 2
    case good = 3
    case easy = 4

    public var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }
}

public struct OpeningAttemptInput: Sendable {
    public let correct: Bool
    public let responseMs: Int
    public let hintUsed: Bool

    public init(correct: Bool, responseMs: Int, hintUsed: Bool = false) {
        self.correct = correct
        self.responseMs = responseMs
        self.hintUsed = hintUsed
    }
}

public struct OpeningReviewResult: Sendable {
    public let card: FsrsOpeningCard
    public let rating: FSRSRating
    public let nextDueAt: Int64
    public let recallPct: Int
}

/// FSRS-6 spaced repetition scheduler matching BrillyDer's response-time auto-grading & 90% retention target.
public enum FSRS6Scheduler {
    private static let fastThresholdMs = 3_000
    private static let slowThresholdMs = 10_000
    private static let requestRetention = 0.9
    private static let dayMs: Double = 86_400_000.0

    // Standard FSRS default weights (w0..w18)
    private static let w: [Double] = [
        0.40255, 1.18385, 3.173, 15.69105,
        7.1949, 0.5345, 1.4604, 0.0046,
        1.54575, 0.1192, 1.01925, 1.9395,
        0.11, 0.29605, 2.2698, 0.2315,
        2.9898, 0.51655, 0.6621,
    ]

    public static func buildCardId(courseId: String, lineId: String, ply: Int, expectedUci: String) -> String {
        "\(courseId)::\(lineId)::\(ply)::\(expectedUci)"
    }

    public static func isoString(from date: Date) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date)
    }

    public static func date(fromIso iso: String) -> Date? {
        if let d = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(iso) {
            return d
        }
        if let d = try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(iso) {
            return d
        }
        // Fallback for legacy iOS timestamps saved without a trailing 'Z'
        let legacyFrac = Date.ISO8601FormatStyle.iso8601.year().month().day().time(includingFractionalSeconds: true)
        if let d = try? legacyFrac.parse(iso) {
            return d
        }
        let legacyWhole = Date.ISO8601FormatStyle.iso8601.year().month().day().time(includingFractionalSeconds: false)
        return try? legacyWhole.parse(iso)
    }

    public static func gradeAttempt(_ attempt: OpeningAttemptInput) -> FSRSRating {
        if !attempt.correct { return .again }
        if attempt.hintUsed || attempt.responseMs > slowThresholdMs { return .hard }
        if attempt.responseMs < fastThresholdMs { return .easy }
        return .good
    }

    public static func createCard(
        courseId: String,
        lineId: String,
        side: RepertoireSide,
        fen: String,
        ply: Int,
        moveSequence: [String],
        expectedSan: String,
        expectedUci: String,
        source: String = "course",
        unlocked: Bool = false,
        now: Date = Date()
    ) -> FsrsOpeningCard {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000.0)
        return FsrsOpeningCard(
            cardId: buildCardId(courseId: courseId, lineId: lineId, ply: ply, expectedUci: expectedUci),
            courseId: courseId,
            lineId: lineId,
            side: side,
            fen: fen,
            ply: ply,
            moveSequence: moveSequence,
            expectedSan: expectedSan,
            expectedUci: expectedUci,
            fsrsState: FsrsCardState(due: isoString(from: now)),
            dueAt: nowMs,
            attempts: 0,
            firstTryHits: 0,
            avgResponseMs: 0,
            source: source,
            unlocked: unlocked
        )
    }

    public static func isCardDue(_ card: FsrsOpeningCard, now: Date = Date()) -> Bool {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000.0)
        return card.unlocked && card.dueAt <= nowMs
    }

    /// Recall probability (0...100 integer) using the FSRS power-law forgetting curve.
    public static func recallProbability(for card: FsrsOpeningCard, now: Date = Date()) -> Int {
        let state = card.fsrsState
        guard state.reps > 0, state.stability > 0 else { return 0 }
        let lastReview = state.last_review.flatMap(date(fromIso:)) ?? now
        let elapsedDays = max(0.0, now.timeIntervalSince(lastReview) / 86_400.0)
        let r = pow(1.0 + elapsedDays / (9.0 * state.stability), -1.0)
        return Int((ChessMath.clamp(r * 100.0, min: 0, max: 100)).rounded())
    }

    public static func review(
        card: FsrsOpeningCard,
        attempt: OpeningAttemptInput,
        now: Date = Date()
    ) -> OpeningReviewResult {
        let rating = gradeAttempt(attempt)
        var updated = card
        var s = card.fsrsState

        let elapsedDays: Double
        if let lastIso = s.last_review, let lastDate = date(fromIso: lastIso) {
            elapsedDays = max(0.0, now.timeIntervalSince(lastDate) / 86_400.0)
        } else {
            elapsedDays = 0.0
        }

        var newStability: Double
        let newDifficulty: Double
        var nextIntervalDays: Double
        var nextState: Int
        var nextSteps = s.learning_steps
        var nextLapses = s.lapses

        if s.reps == 0 {
            newStability = initialStability(for: rating)
            newDifficulty = initialDifficulty(for: rating)
            switch rating {
            case .again:
                nextState = 1
                nextSteps = 0
                nextIntervalDays = 1.0 / 1440.0 // 1 min
            case .hard:
                nextState = 1
                nextSteps = 0
                nextIntervalDays = 6.0 / 1440.0 // 6 min
            case .good:
                nextState = 1
                nextSteps = 1
                nextIntervalDays = 10.0 / 1440.0 // 10 min
            case .easy:
                nextState = 2
                nextSteps = 0
                nextIntervalDays = max(1.0, intervalDays(stability: newStability))
            }
        } else {
            let retrievability = s.stability > 0
                ? pow(1.0 + elapsedDays / (9.0 * s.stability), -1.0)
                : 0.9
            newDifficulty = nextDifficulty(current: s.difficulty, rating: rating)

            if rating == .again {
                nextLapses += 1
                nextState = 3 // Relearning
                nextSteps = 0
                let prevS = max(0.1, s.stability)
                newStability = max(0.1, min(prevS, forgetStability(d: newDifficulty, s: prevS, r: retrievability)))
                nextIntervalDays = 5.0 / 1440.0 // 5 min relearn
            } else {
                newStability = max(0.1, recallStability(d: newDifficulty, s: max(0.1, s.stability), r: retrievability, rating: rating))
                nextState = 2 // Review
                nextSteps = 0
                let rawDays = intervalDays(stability: newStability)
                nextIntervalDays = max(1.0, rawDays.rounded())
            }
        }

        let maxIntervalDays = 36_500.0
        if !newStability.isFinite { newStability = 1.0 }
        newStability = ChessMath.clamp(newStability, min: 0.1, max: maxIntervalDays)
        if !nextIntervalDays.isFinite { nextIntervalDays = 1.0 }
        nextIntervalDays = ChessMath.clamp(nextIntervalDays, min: 1.0 / 1440.0, max: maxIntervalDays)

        let nextDueDate = now.addingTimeInterval(nextIntervalDays * 86_400.0)
        let rawMs = nextDueDate.timeIntervalSince1970 * 1000.0
        let nextDueMs: Int64 = rawMs.isFinite
            ? Int64(ChessMath.clamp(rawMs, min: -9_000_000_000_000_000.0, max: 9_000_000_000_000_000.0))
            : Int64(now.timeIntervalSince1970 * 1000.0)

        let hadPriorReview = (s.last_review != nil && s.stability > 0)
        let preReviewRecall = hadPriorReview ? recallProbability(for: updated, now: now) : nil
        s.stability = (newStability * 1000.0).rounded() / 1000.0
        s.difficulty = (newDifficulty * 1000.0).rounded() / 1000.0
        s.scheduled_days = nextIntervalDays
        s.learning_steps = nextSteps
        s.reps = max(0, s.reps) + 1
        s.lapses = max(0, nextLapses)
        s.state = nextState
        s.last_review = isoString(from: now)
        s.due = isoString(from: nextDueDate)

        let prevAttempts = max(0, updated.attempts)
        let nextAttempts = prevAttempts + 1
        let clampedMs = Double(max(200, min(60_000, attempt.responseMs)))
        updated.fsrsState = s
        updated.dueAt = nextDueMs
        updated.attempts = nextAttempts
        updated.firstTryHits = max(0, updated.firstTryHits) + ((attempt.correct && !attempt.hintUsed) ? 1 : 0)
        let safePrevAvg = updated.avgResponseMs.isFinite ? updated.avgResponseMs : clampedMs
        updated.avgResponseMs = nextAttempts == 1
            ? clampedMs
            : ((safePrevAvg * Double(prevAttempts) + clampedMs) / Double(nextAttempts))
        updated.unlocked = true

        let reportedRecall = preReviewRecall ?? recallProbability(for: updated, now: now)
        return OpeningReviewResult(
            card: updated,
            rating: rating,
            nextDueAt: nextDueMs,
            recallPct: reportedRecall
        )
    }

    // MARK: - FSRS Math Helpers

    private static func initialStability(for rating: FSRSRating) -> Double {
        max(0.1, w[rating.rawValue - 1])
    }

    private static func initialDifficulty(for rating: FSRSRating) -> Double {
        let g = Double(rating.rawValue)
        return ChessMath.clamp(w[4] - exp(w[5] * (g - 1.0)) + 1.0, min: 1.0, max: 10.0)
    }

    private static func nextDifficulty(current d: Double, rating: FSRSRating) -> Double {
        let g = Double(rating.rawValue)
        let d0 = initialDifficulty(for: .easy)
        let delta = -w[6] * (g - 3.0)
        let next = d + delta * (10.0 - d) / 9.0
        let meanReverted = w[7] * d0 + (1.0 - w[7]) * next
        return ChessMath.clamp(meanReverted, min: 1.0, max: 10.0)
    }

    private static func recallStability(d: Double, s: Double, r: Double, rating: FSRSRating) -> Double {
        let hardPenalty = rating == .hard ? w[15] : 1.0
        let easyBonus = rating == .easy ? w[16] : 1.0
        let inc = exp(w[8])
            * (11.0 - d)
            * pow(s, -w[9])
            * (exp((1.0 - r) * w[10]) - 1.0)
            * hardPenalty
            * easyBonus
        return s * (1.0 + inc)
    }

    private static func forgetStability(d: Double, s: Double, r: Double) -> Double {
        w[11] * pow(d, -w[12]) * (pow(s + 1.0, w[13]) - 1.0) * exp((1.0 - r) * w[14])
    }

    private static func intervalDays(stability s: Double) -> Double {
        let factor = 9.0 * (1.0 / requestRetention - 1.0)
        return max(1.0, s * factor)
    }
}
