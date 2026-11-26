import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// Shared ActivityKit attributes for BrillyDer Batch Analysis Dynamic Island & Lock Screen Live Activity.
public struct BrillyBatchActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public var completedGames: Int
        public var currentGameIndex: Int
        public var currentPly: Int
        public var totalPlies: Int
        public var matchup: String
        public var progress: Double
        /// `"analyzing"`, `"paused"`, or `"complete"`
        public var status: String

        public init(
            completedGames: Int,
            currentGameIndex: Int,
            currentPly: Int,
            totalPlies: Int,
            matchup: String,
            progress: Double,
            status: String
        ) {
            self.completedGames = completedGames
            self.currentGameIndex = currentGameIndex
            self.currentPly = currentPly
            self.totalPlies = totalPlies
            self.matchup = matchup
            self.progress = progress
            self.status = status
        }
    }

    public var presetTitle: String
    public var presetElo: String
    public var totalGames: Int

    public init(presetTitle: String, presetElo: String, totalGames: Int) {
        self.presetTitle = presetTitle
        self.presetElo = presetElo
        self.totalGames = totalGames
    }
}
#endif
