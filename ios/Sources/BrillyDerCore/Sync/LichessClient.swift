import Foundation

public enum SyncError: Error, LocalizedError, Sendable {
    case emptyUsername
    case userNotFound(String)
    case rateLimited(String)
    case networkFailure(String)
    case invalidPGN(String)

    public var errorDescription: String? {
        switch self {
        case .emptyUsername: return "Enter a username to sync recent games."
        case .userNotFound(let msg): return msg
        case .rateLimited(let msg): return msg
        case .networkFailure(let msg): return msg
        case .invalidPGN(let msg): return msg
        }
    }
}

public enum LichessClient {
    private struct RawPlayer: Decodable {
        struct User: Decodable { let name: String? }
        let user: User?
        let rating: Int?
        let ratingDiff: Int?
        let aiLevel: Int?
    }

    private struct RawGame: Decodable {
        struct Opening: Decodable { let eco: String?; let name: String?; let ply: Int? }
        struct Clock: Decodable { let initial: Int?; let increment: Int? }
        struct Players: Decodable { let white: RawPlayer?; let black: RawPlayer? }

        let id: String
        let rated: Bool?
        let variant: String?
        let speed: String?
        let perf: String?
        let createdAt: Int64?
        let status: String?
        let winner: String?
        let pgn: String?
        let moves: String?
        let opening: Opening?
        let clock: Clock?
        let players: Players?
    }

    public static func fetchRecentGames(username: String, maxGames: Int = 20) async throws -> [GameRecord] {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SyncError.emptyUsername }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://lichess.org/api/games/user/\(encoded)?max=\(max(1, min(50, maxGames)))&pgnInJson=true&clocks=true&opening=true&perfType=bullet,blitz,rapid,classical") else {
            throw SyncError.networkFailure("Invalid Lichess username.")
        }

        var req = URLRequest(url: url, timeoutInterval: 18)
        req.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        req.setValue("BrillyDer-iOS/2.3 (local-first chess coach)", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw SyncError.networkFailure("Could not reach Lichess: \(error.localizedDescription)")
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw SyncError.userNotFound("Lichess user \"\(trimmed)\" not found.") }
            if http.statusCode == 429 { throw SyncError.rateLimited("Lichess rate limit hit — retry in a minute.") }
            if !(200..<300).contains(http.statusCode) {
                throw SyncError.networkFailure("Lichess API error (\(http.statusCode)).")
            }
        }

        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        var games: [GameRecord] = []

        for line in text.split(separator: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, let lineData = trimmedLine.data(using: .utf8) else { continue }
            guard let raw = try? decoder.decode(RawGame.self, from: lineData) else { continue }
            if let mapped = mapRawGame(raw, username: trimmed) {
                games.append(mapped)
            }
        }
        return games
    }

    public static func parsePastedPGN(_ pgn: String, preferredUsername: String? = nil) throws -> GameRecord {
        let trimmed = pgn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SyncError.invalidPGN("Paste a PGN to analyze.") }

        let parsed: ParsedPGNGame
        do {
            parsed = try PGNParser.parse(trimmed)
        } catch {
            throw SyncError.invalidPGN(error.localizedDescription)
        }
        guard parsed.moves.count >= 2 else {
            throw SyncError.invalidPGN("PGN must contain at least 2 legal plies.")
        }

        let headers = parsed.headers
        let whiteName = headers["White"] ?? "White"
        let blackName = headers["Black"] ?? "Black"
        let whiteElo = headers["WhiteElo"].flatMap(Int.init)
        let blackElo = headers["BlackElo"].flatMap(Int.init)

        var userColor: PieceColor? = nil
        if let u = preferredUsername?.trimmingCharacters(in: .whitespaces).lowercased(), !u.isEmpty {
            if whiteName.lowercased() == u { userColor = .white }
            else if blackName.lowercased() == u { userColor = .black }
        }

        let sanMoves = parsed.moves.map(\.applied.san)
        let lookup = MoveClassifier.lookupOpening(byMoves: sanMoves)
        let openingName = headers["Opening"] ?? lookup?.name ?? "Custom PGN"
        let openingEco = headers["ECO"] ?? lookup?.eco ?? ""
        let tcLabel = headers["TimeControl"] ?? "PGN"
        let res = parsed.result
        let winner: String? = res == "1-0" ? "white" : (res == "0-1" ? "black" : nil)

        return GameRecord(
            id: stableId(for: trimmed),
            source: .pgn,
            rated: false,
            variant: "standard",
            speed: "rapid",
            perf: "pgn",
            createdAt: Int64(Date().timeIntervalSince1970 * 1000.0),
            status: "normal",
            winner: winner,
            resultString: res,
            timeControlLabel: tcLabel,
            pgn: trimmed,
            openingName: openingName,
            openingEco: openingEco,
            openingPly: lookup?.matchedPlies,
            white: PlayerInfo(name: whiteName, rating: whiteElo),
            black: PlayerInfo(name: blackName, rating: blackElo),
            userColor: userColor,
            url: nil
        )
    }

    public static func sampleGames() -> [GameRecord] {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        return [
            GameRecord(
                id: "sample_london_attack",
                source: .sample,
                rated: true,
                speed: "rapid",
                perf: "rapid",
                createdAt: nowMs - 3_600_000,
                winner: "white",
                resultString: "1-0",
                timeControlLabel: "10+0",
                pgn: """
                [Event "BrillyDer Showcase: London Attack"]
                [White "You"]
                [Black "ClubOpponent"]
                [WhiteElo "1420"]
                [BlackElo "1445"]
                [Result "1-0"]

                1. d4 d5 2. Bf4 Nf6 3. e3 e6 4. Nf3 c5 5. c3 Nc6 6. Nbd2 Bd6 7. Bg3 O-O 8. Bd3 b6 9. Ne5 Bb7 10. f4 Ne7 11. Qf3 Rc8 12. Bh4 Ng6 13. Bxf6 Qxf6 14. Nd7 Qe7 15. Nxf8 Rxf8 1-0
                """,
                openingName: "London System",
                openingEco: "D02",
                openingPly: 6,
                white: PlayerInfo(name: "You", rating: 1420),
                black: PlayerInfo(name: "ClubOpponent", rating: 1445),
                userColor: .white
            ),
            GameRecord(
                id: "sample_italian_tactics",
                source: .sample,
                rated: true,
                speed: "blitz",
                perf: "blitz",
                createdAt: nowMs - 86_400_000,
                winner: "white",
                resultString: "1-0",
                timeControlLabel: "5+3",
                pgn: """
                [Event "BrillyDer Showcase: Italian Fork"]
                [White "You"]
                [Black "BlitzRival"]
                [WhiteElo "1415"]
                [BlackElo "1460"]
                [Result "1-0"]

                1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 Nf6 5. d4 exd4 6. cxd4 Bb4+ 7. Bd2 Bxd2+ 8. Nbxd2 d5 9. exd5 Nxd5 10. Qb3 Nce7 11. O-O O-O 12. Rfe1 c6 13. Ne4 Rb8 14. Nc5 1-0
                """,
                openingName: "Italian Game",
                openingEco: "C54",
                openingPly: 8,
                white: PlayerInfo(name: "You", rating: 1415),
                black: PlayerInfo(name: "BlitzRival", rating: 1460),
                userColor: .white
            ),
        ]
    }

    // MARK: - Helpers

    private static func mapRawGame(_ raw: RawGame, username: String) -> GameRecord? {
        if raw.status == "aborted" || raw.status == "noStart" { return nil }
        let pgn = raw.pgn ?? raw.moves ?? ""
        guard !pgn.isEmpty, let parsed = try? PGNParser.parse(pgn), parsed.moves.count >= 2 else {
            return nil
        }

        let whiteName = raw.players?.white?.user?.name
            ?? raw.players?.white?.aiLevel.map { "Stockfish L\($0)" }
            ?? "White"
        let blackName = raw.players?.black?.user?.name
            ?? raw.players?.black?.aiLevel.map { "Stockfish L\($0)" }
            ?? "Black"

        let low = username.lowercased()
        let userColor: PieceColor?
        if whiteName.lowercased() == low { userColor = .white }
        else if blackName.lowercased() == low { userColor = .black }
        else { userColor = nil }

        var resultString: String
        if raw.winner == "white" { resultString = "1-0" }
        else if raw.winner == "black" { resultString = "0-1" }
        else if raw.status == "draw" || raw.status == "stalemate" { resultString = "1/2-1/2" }
        else { resultString = parsed.result }

        let sanMoves = parsed.moves.map(\.applied.san)
        let lookup = MoveClassifier.lookupOpening(byMoves: sanMoves)
        let openingName = raw.opening?.name ?? lookup?.name ?? "Unknown Opening"
        let openingEco = raw.opening?.eco ?? lookup?.eco ?? ""
        let tc = formatTimeControl(initial: raw.clock?.initial, inc: raw.clock?.increment, speed: raw.speed)

        return GameRecord(
            id: raw.id,
            source: .lichess,
            rated: raw.rated ?? false,
            variant: raw.variant ?? "standard",
            speed: raw.speed ?? "rapid",
            perf: raw.perf ?? raw.speed ?? "rapid",
            createdAt: raw.createdAt ?? Int64(Date().timeIntervalSince1970 * 1000.0),
            status: raw.status ?? "normal",
            winner: raw.winner,
            resultString: resultString,
            timeControlLabel: tc,
            pgn: pgn,
            openingName: openingName,
            openingEco: openingEco,
            openingPly: raw.opening?.ply ?? lookup?.matchedPlies,
            white: PlayerInfo(
                name: whiteName,
                rating: raw.players?.white?.rating,
                ratingDiff: raw.players?.white?.ratingDiff
            ),
            black: PlayerInfo(
                name: blackName,
                rating: raw.players?.black?.rating,
                ratingDiff: raw.players?.black?.ratingDiff
            ),
            userColor: userColor,
            url: "https://lichess.org/\(raw.id)"
        )
    }

    private static func formatTimeControl(initial: Int?, inc: Int?, speed: String?) -> String {
        if let initial {
            let i = inc ?? 0
            if initial < 60 { return "\(initial)s+\(i)" }
            if initial % 60 == 0 { return "\(initial / 60)+\(i)" }
            return String(format: "%.1f+%d", Double(initial) / 60.0, i)
        }
        return (speed ?? "Standard").capitalized
    }

    private static func stableId(for text: String) -> String {
        var h: UInt64 = 14695981039346656037
        for b in text.utf8 {
            h ^= UInt64(b)
            h = h &* 1099511628211
        }
        return "pgn_\(String(h, radix: 36))"
    }
}
