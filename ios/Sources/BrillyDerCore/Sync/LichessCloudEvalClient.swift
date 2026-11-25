import Foundation

/// Lightweight, zero-auth client for Lichess's free public Stockfish 16 Cloud Eval cache
/// (`https://lichess.org/api/cloud-eval`). Used exclusively by the Pro `Cloud SF` single-game
/// review mode, with seamless fallback to on-device `Ultra` search on cache misses or offline use.
public enum LichessCloudEvalClient {
    public enum ProbeOutcome: Sendable {
        case hit(EngineEval)
        case miss
        case rateLimited
    }

    private struct RawCloudPV: Decodable {
        let moves: String
        let cp: Int?
        let mate: Int?
    }

    private struct RawCloudResponse: Decodable {
        let fen: String?
        let knodes: Int?
        let depth: Int?
        let pvs: [RawCloudPV]?
    }

    private actor Cache {
        private var store: [String: EngineEval] = [:]
        private var order: [String] = []
        private let maxEntries = 512

        func get(_ key: String) -> EngineEval? {
            store[key]
        }

        func set(_ key: String, value: EngineEval) {
            if store[key] == nil {
                order.append(key)
                if order.count > maxEntries, let oldest = order.first {
                    order.removeFirst()
                    store.removeValue(forKey: oldest)
                }
            }
            store[key] = value
        }
    }

    private static let cache = Cache()

    private static func normalizedKey(for fen: String) -> String {
        fen.split(separator: " ").prefix(4).joined(separator: " ")
    }

    public static func probe(fen: String, multiPV: Int = 2) async -> ProbeOutcome {
        let key = normalizedKey(for: fen)
        if let cached = await cache.get(key) {
            return .hit(cached)
        }
        var components = URLComponents(string: "https://lichess.org/api/cloud-eval")
        components?.queryItems = [
            URLQueryItem(name: "fen", value: fen),
            URLQueryItem(name: "multiPv", value: String(max(1, min(3, multiPV))))
        ]
        guard let url = components?.url else { return .miss }

        var req = URLRequest(url: url, timeoutInterval: 2.2)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let ver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.13"
        req.setValue("BrillyDer-iOS/\(ver) (local-first chess coach)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 429 { return .rateLimited }
                guard (200..<300).contains(http.statusCode) else { return .miss }
            }
            if let decoded = decodeCloudEval(data: data, fen: fen) {
                await cache.set(key, value: decoded)
                return .hit(decoded)
            }
            return .miss
        } catch {
            return .miss
        }
    }

    /// Pure deterministic decoder for Lichess Cloud Eval JSON (unit-testable offline).
    public static func decodeCloudEval(data: Data, fen: String) -> EngineEval? {
        guard let raw = try? JSONDecoder().decode(RawCloudResponse.self, from: data),
              let pvs = raw.pvs, !pvs.isEmpty else {
            return nil
        }
        let depth = raw.depth ?? 30
        var lines: [MultiPvLine] = []

        for (idx, pv) in pvs.enumerated() {
            let moveTokens = pv.moves
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 4 }
            guard let firstUci = moveTokens.first else { continue }
            let score = ChessMath.buildEngineScore(
                cpWhite: pv.cp ?? 0,
                mateWhite: pv.mate
            )
            lines.append(MultiPvLine(
                multipv: idx + 1,
                bestMoveUci: firstUci,
                pv: moveTokens,
                score: score
            ))
        }

        guard let top = lines.first else { return nil }
        return EngineEval(
            fen: raw.fen ?? fen,
            depth: depth,
            bestMoveUci: top.bestMoveUci,
            pv: top.pv,
            score: top.score,
            lines: lines
        )
    }
}
