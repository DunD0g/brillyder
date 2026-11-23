import Foundation

public struct SyzygyMove: Codable, Hashable, Sendable, Identifiable {
    public var id: String { uci }
    public let uci: String
    public let san: String
    /// Mover's perspective AFTER playing this move (`win`, `cursed-win`, `draw`, `blessed-loss`, `loss`).
    public let category: String
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
        case "maybe-win": return "Likely Win"
        case "cursed-win": return "Cursed Win (50-move)"
        case "draw": return "Theoretical Draw"
        case "blessed-loss": return "Blessed Loss (50-move)"
        case "maybe-loss": return "Likely Loss"
        case "loss":
            if let dtm { return "Mated in \(abs(dtm))" }
            if let dtz { return "Losing (DTZ \(abs(dtz)))" }
            return "Tablebase Loss"
        default: return category.capitalized
        }
    }
}

/// Client for Lichess's free 7-piece Syzygy Endgame Tablebase with perspective inversion,
/// 5-field FEN caching (capped at 160 entries), and 3-minute rate-limit backoff.
public actor SyzygyClient {
    public static let shared = SyzygyClient()

    private var cache: [String: SyzygyProbeResult] = [:]
    private var cacheOrder: [String] = []
    private var backoffUntil: Date? = nil
    private let maxCacheEntries = 160

    public static func totalPieceCount(in board: ChessBoard) -> Int {
        board.squares.reduce(0) { $0 + ($1 == nil ? 0 : 1) }
    }

    public static func isEligible(fen: String) -> Bool {
        guard let board = try? ChessBoard(fen: fen) else { return false }
        // Exclude castling positions (Syzygy tablebases don't cover castling) and 2-piece K-vs-K
        guard board.castling.isEmpty else { return false }
        let count = totalPieceCount(in: board)
        return count >= 3 && count <= 7
    }

    /// 5-field cache key (preserves halfmove clock for 50-move cursed-win/blessed-loss accuracy).
    public static func cacheKey(for fen: String) -> String {
        fen.split(separator: " ").prefix(5).joined(separator: " ")
    }

    /// Lichess Tablebase returns each candidate move's category from the OPPONENT'S perspective after the move;
    /// invert it so UI & callers always read the MOVER's outcome (`"loss"` for opponent -> `"win"` for mover).
    public static func invertOpponentCategory(_ raw: String) -> String {
        switch raw {
        case "loss": return "win"
        case "win": return "loss"
        case "maybe-loss": return "maybe-win"
        case "maybe-win": return "maybe-loss"
        case "blessed-loss": return "cursed-win"
        case "cursed-win": return "blessed-loss"
        case "draw": return "draw"
        default: return raw
        }
    }

    public func probe(fen: String) async -> SyzygyProbeResult? {
        guard Self.isEligible(fen: fen) else { return nil }
        let key = Self.cacheKey(for: fen)
        if let hit = cache[key] { return hit }
        if let until = backoffUntil, Date() < until { return nil }

        var comps = URLComponents(string: "https://tablebase.lichess.ovh/standard")
        comps?.queryItems = [URLQueryItem(name: "fen", value: fen)]
        guard let url = comps?.url else { return nil }

        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("BrillyDer-iOS/2.6", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else {
            return nil
        }

        if http.statusCode == 429 || http.statusCode >= 500 {
            backoffUntil = Date().addingTimeInterval(180)
            return nil
        }
        guard (200..<300).contains(http.statusCode),
              let raw = try? JSONDecoder().decode(SyzygyProbeResult.self, from: data),
              raw.category != "unknown" else {
            return nil
        }

        let invertedMoves = raw.moves
            .filter { $0.category != "unknown" }
            .map { m in
                SyzygyMove(
                    uci: m.uci,
                    san: m.san,
                    category: Self.invertOpponentCategory(m.category),
                    dtz: m.dtz,
                    dtm: m.dtm,
                    checkmate: m.checkmate,
                    stalemate: m.stalemate
                )
            }

        let normalized = SyzygyProbeResult(
            category: raw.category,
            dtz: raw.dtz,
            dtm: raw.dtm,
            checkmate: raw.checkmate,
            stalemate: raw.stalemate,
            moves: invertedMoves
        )

        if cache[key] == nil {
            cacheOrder.append(key)
            if cacheOrder.count > maxCacheEntries, let evict = cacheOrder.first {
                cacheOrder.removeFirst()
                cache.removeValue(forKey: evict)
            }
        }
        cache[key] = normalized
        return normalized
    }
}
