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
        case .cloudUltra: return 10
        default: return rawValue
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
        case .balanced:   return "Standard"
        case .deep:       return "Deep"
        case .ultra:      return "Max Local"
        case .cloudUltra: return "SF16 Cloud"
        }
    }

    public var eloEstimate: String {
        switch self {
        case .fast:       return "~1500 Elo"
        case .balanced:   return "~1850 Elo"
        case .deep:       return "~2050 Elo"
        case .ultra:      return "~2250 Elo"
        case .cloudUltra: return "~3500 Elo*"
        }
    }

    public var detailSummary: String {
        switch self {
        case .fast:       return "Instant on-device tactical check"
        case .balanced:   return "Everyday club game review"
        case .deep:       return "Strong tactical & endgame accuracy"
        case .ultra:      return "Max offline on-device depth (single-game)"
        case .cloudUltra: return "Lichess Stockfish 16 Cloud + Ultra offline fallback"
        }
    }

    public var maxTimeMs: Int {
        switch self {
        case .fast:       return 140
        case .balanced:   return 320
        case .deep:       return 750
        case .ultra:      return 1150
        case .cloudUltra: return 1150
        }
    }
}

/// Pluggable, App-Store-compliant engine protocol.
/// Default implementation is `BrillyNativeEngine` (100% pure Swift, zero GPL).
/// Can also wrap permissive MIT C++ NNUE UCI engines (e.g. Caissa / Renegade) in Phase 1.5 without touching UI or analysis code.
public protocol ChessEngine: Sendable {
    var engineName: String { get }
    var engineLicense: String { get }

    func analyze(
        fen: String,
        depth: Int,
        multiPV: Int,
        maxTimeMs: Int?
    ) async throws -> EngineEval
}
