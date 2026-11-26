import Foundation

public struct MultiPvLine: Codable, Hashable, Sendable {
    public let multipv: Int
    public let bestMoveUci: String
    public let pv: [String]
    public let score: EngineScore

    public init(multipv: Int, bestMoveUci: String, pv: [String], score: EngineScore) {
        self.multipv = multipv
        self.bestMoveUci = bestMoveUci
        self.pv = pv
        self.score = score
    }
}

public struct EngineEval: Codable, Hashable, Sendable {
    public let fen: String
    public let depth: Int
    public let bestMoveUci: String
    public let pv: [String]
    public let score: EngineScore
    public let lines: [MultiPvLine]

    public init(
        fen: String,
        depth: Int,
        bestMoveUci: String,
        pv: [String],
        score: EngineScore,
        lines: [MultiPvLine]
    ) {
        self.fen = fen
        self.depth = depth
        self.bestMoveUci = bestMoveUci
        self.pv = pv
        self.score = score
        self.lines = lines
    }
}

public enum AnalysisDepthPreset: Int, Codable, CaseIterable, Sendable, Identifiable {
    case fast = 4
    case balanced = 6
    case deep = 8
    case ultra = 10
    case cloudUltra = 11

    public var id: Int { rawValue }

    /// Presets eligible for multi-game Batch Analysis (keeps batch fast and 100% offline).
    public static var batchPresets: [AnalysisDepthPreset] {
        [.fast, .balanced, .deep]
    }

    public var isSingleGameOnly: Bool {
        self == .ultra || self == .cloudUltra
    }

    public var usesCloudEval: Bool {
        self == .cloudUltra
    }

    public var searchDepth: Int {
        switch self {
        case .fast:       return 12
        case .balanced:   return 15
        case .deep:       return 18
        case .ultra:      return 22
        case .cloudUltra: return 22
        }
    }

    public var sfSymbol: String {
        switch self {
        case .cloudUltra: return "cloud.bolt.fill"
        case .ultra:      return "sparkles"
        default:          return "cpu"
        }
    }

    public var title: String {
        switch self {
        case .fast:       return "Fast"
        case .balanced:   return "Balanced"
        case .deep:       return "Deep"
        case .ultra:      return "Ultra"
        case .cloudUltra: return "Cloud SF"
        }
    }

    public var badge: String {
        switch self {
        case .fast:       return "Quick"
        case .balanced:   return "GM Local"
        case .deep:       return "Super-GM"
        case .ultra:      return "Max Local"
        case .cloudUltra: return "SF16 Cloud"
        }
    }

    public var eloEstimate: String {
        switch self {
        case .fast:       return "~2650 Elo"
        case .balanced:   return "~2900 Elo"
        case .deep:       return "~3100 Elo"
        case .ultra:      return "~3300+ Elo"
        case .cloudUltra: return "~3500 Elo"
        }
    }

    public var detailSummary: String {
        switch self {
        case .fast:       return "Blazing on-device NNUE tactical check (batch-ready)"
        case .balanced:   return "Grandmaster-grade on-device NNUE review"
        case .deep:       return "Super-GM on-device NNUE positional & tactical review"
        case .ultra:      return "Max 100% offline NNUE strength (single-game)"
        case .cloudUltra: return "Hybrid Stockfish 16 Cloud + BrillyChess NNUE Ultra fallback"
        }
    }

    public var maxTimeMs: Int {
        switch self {
        case .fast:       return 65
        case .balanced:   return 150
        case .deep:       return 350
        case .ultra:      return 900
        case .cloudUltra: return 900
        }
    }
}

/// Pluggable, App-Store-compliant engine protocol.
/// Primary game-analysis engine is `RenegadeEngine` (MIT-licensed C++20 ARM64 NEON NNUE, ~3300+ Elo offline, zero GPL),
/// with `BrillyNativeEngine` (100% pure Swift) serving as automatic fallback and dedicated interactive bot/sandbox engine.
public protocol ChessEngine: Sendable {
    var engineName: String { get }
    var engineLicense: String { get }

    func analyze(
        fen: String,
        depth: Int,
        multiPV: Int,
        maxTimeMs: Int?
    ) async throws -> EngineEval

    /// Optional hook to reset transposition tables & search histories between unrelated games.
    func clearHash() async
}

public extension ChessEngine {
    func clearHash() async {}
}
