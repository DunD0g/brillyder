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

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .deep: return "Deep"
        }
    }

    public var badge: String {
        switch self {
        case .fast: return "Quick"
        case .balanced: return "Standard"
        case .deep: return "Deep"
        }
    }

    public var maxTimeMs: Int {
        switch self {
        case .fast: return 140
        case .balanced: return 320
        case .deep: return 750
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
