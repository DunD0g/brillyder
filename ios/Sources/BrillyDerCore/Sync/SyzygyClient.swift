import Foundation

public struct SyzygyMove: Codable, Hashable, Sendable, Identifiable {
    public var id: String { uci }
    public let uci: String
    public let san: String
    public let category: String // "win" | "maybe-win" | "cursed-win" | "draw" | "blessed-loss" | "maybe-loss" | "loss"
    public let dtz: Int?
    public let dtm: Int?
    public let checkmate: Bool?
    public let stalemate: Bool?
}

public struct SyzygyProbeResult: Codable, Hashable, Sendable {
    public let category: String
    public let dtz: Int?
    public let dtm: Int?
    public let checkmate: Bool?
    public let stalemate: Bool?
    public let moves: [SyzygyMove]

    public var humanLabel: String {
        switch category {
        case "win":
            if let dtm { return "Forced Mate in \(abs(dtm))" }
            if let dtz { return "Winning (DTZ \(abs(dtz)))" }
            return "Tablebase Win"
        case "cursed-win": return "Cursed Win (50-move)"
        case "draw": return "Theoretical Draw"
        case "blessed-loss": return "Blessed Loss (50-move)"
        case "loss":
            if let dtm { return "Mated in \(abs(dtm))" }
            if let dtz { return "Losing (DTZ \(abs(dtz)))" }
            return "Tablebase Loss"
        default: return category.capitalized
        }
    }
}

/// Client for Lichess's free 7-piece Syzygy Endgame Tablebase with 5-field FEN caching.
public actor SyzygyClient {
    public static let shared = SyzygyClient()
    private var cache: [String: SyzygyProbeResult] = [:]

    public static func totalPieceCount(in board: ChessBoard) -> Int {
        board.squares.reduce(0) { $0 + ($1 == nil ? 0 : 1) }
    }

    public static func isEligible(fen: String) -> Bool {
        guard let board = try? ChessBoard(fen: fen) else { return false }
        let count = totalPieceCount(in: board)
        return count >= 2 && count <= 7
    }

    /// 5-field cache key (preserves halfmove clock for 50-move cursed-win/blessed-loss accuracy).
    public static func cacheKey(for fen: String) -> String {
        fen.split(separator: " ").prefix(5).joined(separator: " ")
    }

    public func probe(fen: String) async -> SyzygyProbeResult? {
        guard Self.isEligible(fen: fen) else { return nil }
        let key = Self.cacheKey(for: fen)
        if let hit = cache[key] { return hit }

        let underscored = fen.replacingOccurrences(of: " ", with: "_")
        guard let encoded = underscored.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://tablebase.lichess.ovh/standard?fen=\(encoded)") else {
            return nil
        }

        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("BrillyDer-iOS/2.3", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(SyzygyProbeResult.self, from: data) else {
            return nil
        }

        cache[key] = decoded
        return decoded
    }
}
