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
    private static let strictUsernameChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    private static let reservedPathSegments: Set<String> = [
        "training", "analysis", "study", "tv", "inbox", "player", "team",
        "tournament", "swiss", "broadcast", "editor", "paste", "login",
        "signup", "account", "forum", "blog", "coach", "video", "api", "games"
    ]

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
        guard trimmed.unicodeScalars.allSatisfy({ strictUsernameChars.contains($0) }),
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: strictUsernameChars),
              let url = URL(string: "https://lichess.org/api/games/user/\(encoded)?max=\(max(1, min(50, maxGames)))&pgnInJson=true&clocks=true&opening=true&perfType=bullet,blitz,rapid,classical") else {
            throw SyncError.networkFailure("Invalid Lichess username.")
        }

        var req = URLRequest(url: url, timeoutInterval: 18)
        req.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        req.setValue("BrillyDer-iOS/2.6 (local-first chess coach)", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch is CancellationError {
            throw CancellationError()
        } catch let err as URLError where err.code == .cancelled {
            throw CancellationError()
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
        var seenIds = Set<String>()

        for line in text.split(separator: "\n") {
            try Task.checkCancellation()
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, let lineData = trimmedLine.data(using: .utf8) else { continue }
            guard let raw = try? decoder.decode(RawGame.self, from: lineData) else { continue }
            if let mapped = mapRawGame(raw, handles: [trimmed]), seenIds.insert(mapped.id).inserted {
                games.append(mapped)
            }
        }
        return games.sorted { $0.createdAt > $1.createdAt }
    }

    /// Fetches a single public Lichess game from a URL (`https://lichess.org/AbCdEfGh`, `lichess.org/AbCdEfGh/black`) or 8-char game ID.
    public static func fetchSingleGame(
        urlOrId: String,
        preferredUsername: String? = nil,
        preferredUsernames: [String] = []
    ) async throws -> GameRecord {
        let cleaned = urlOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            throw SyncError.invalidPGN("Enter a Lichess game link or 8-character ID.")
        }

        let candidateUrlString: String
        if cleaned.lowercased().hasPrefix("lichess.org/") || cleaned.lowercased().hasPrefix("www.lichess.org/") {
            candidateUrlString = "https://" + cleaned
        } else {
            candidateUrlString = cleaned
        }

        let gameId: String
        if let url = URL(string: candidateUrlString),
           let host = url.host?.lowercased(),
           host == "lichess.org" || host.hasSuffix(".lichess.org") {
            let segments = url.pathComponents.filter { $0 != "/" }
            guard let first = segments.first,
                  !reservedPathSegments.contains(first.lowercased()),
                  first.count == 8 || first.count == 12 else {
                throw SyncError.invalidPGN("Enter a valid Lichess game link (e.g. lichess.org/AbCdEfGh).")
            }
            gameId = String(first.prefix(8))
        } else {
            guard (cleaned.count == 8 || cleaned.count == 12),
                  !reservedPathSegments.contains(cleaned.lowercased()) else {
                throw SyncError.invalidPGN("Enter a valid Lichess game link or 8-character ID.")
            }
            gameId = String(cleaned.prefix(8))
        }

        guard gameId.count == 8, gameId.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw SyncError.invalidPGN("Enter a valid Lichess game link or 8-character ID.")
        }
        guard let apiUrl = URL(string: "https://lichess.org/game/export/\(gameId)?pgnInJson=true&clocks=true&opening=true") else {
            throw SyncError.networkFailure("Invalid Lichess game URL.")
        }
        var req = URLRequest(url: apiUrl, timeoutInterval: 15)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("BrillyDer-iOS/2.6 (local-first chess coach)", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch is CancellationError {
            throw CancellationError()
        } catch let err as URLError where err.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SyncError.networkFailure("Could not reach Lichess: \(error.localizedDescription)")
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 {
                throw SyncError.userNotFound("Lichess game \"\(gameId)\" not found.")
            }
            if http.statusCode == 429 {
                throw SyncError.rateLimited("Lichess rate limit hit — retry in a minute.")
            }
            if !(200..<300).contains(http.statusCode) {
                throw SyncError.networkFailure("Lichess API error (\(http.statusCode)).")
            }
        }
        let raw = try JSONDecoder().decode(RawGame.self, from: data)
        var handles = preferredUsernames
        if let u = preferredUsername, !u.isEmpty { handles.append(u) }
        guard let mapped = mapRawGame(raw, handles: handles) else {
            throw SyncError.invalidPGN("Could not parse Lichess game \(gameId) (only standard chess is supported).")
        }
        return mapped
    }

    public static func parsePastedPGN(
        _ pgn: String,
        preferredUsername: String? = nil,
        preferredUsernames: [String] = []
    ) throws -> GameRecord {
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

        var handles = preferredUsernames
        if let u = preferredUsername, !u.isEmpty { handles.append(u) }
        let handleSet = Set(handles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })

        var userColor: PieceColor? = nil
        if handleSet.contains(whiteName.lowercased()) { userColor = .white }
        else if handleSet.contains(blackName.lowercased()) { userColor = .black }

        let isStandardStart = parsed.startFen == ChessBoard.initialFEN
        let sanMoves = parsed.moves.map(\.applied.san)
        let lookup = isStandardStart ? MoveClassifier.lookupOpening(byMoves: sanMoves) : nil
        let openingName = headers["Opening"] ?? lookup?.name ?? "Custom PGN"
        let openingEco = headers["ECO"] ?? lookup?.eco ?? ""
        let tcLabel = headers["TimeControl"] ?? "PGN"
        let res = parsed.result
        let winner: String? = res == "1-0" ? "white" : (res == "0-1" ? "black" : nil)
        let createdAtMs = parsePGNTimestampMs(headers: headers) ?? Int64(Date().timeIntervalSince1970 * 1000.0)

        return GameRecord(
            id: stableId(for: trimmed),
            source: .pgn,
            rated: false,
            variant: isStandardStart ? "standard" : "fromPosition",
            speed: "rapid",
            perf: "pgn",
            createdAt: createdAtMs,
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

    private static func mapRawGame(_ raw: RawGame, handles: [String]) -> GameRecord? {
        if raw.status == "aborted" || raw.status == "noStart" { return nil }
        if let variant = raw.variant, variant != "standard" { return nil }
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

        let handleSet = Set(handles.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        let userColor: PieceColor?
        if handleSet.contains(whiteName.lowercased()) { userColor = .white }
        else if handleSet.contains(blackName.lowercased()) { userColor = .black }
        else { userColor = nil }

        let resultString: String
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

    private static func parsePGNTimestampMs(headers: [String: String]) -> Int64? {
        let rawDate = (headers["UTCDate"] ?? headers["Date"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawDate, !rawDate.contains("?"), !rawDate.isEmpty else { return nil }
        let rawTime = (headers["UTCTime"] ?? headers["Time"])?.trimmingCharacters(in: .whitespacesAndNewlines)

        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.calendar = Calendar(identifier: .gregorian)

        if let rawTime, !rawTime.contains("?"), !rawTime.isEmpty {
            fmt.dateFormat = "yyyy.MM.dd HH:mm:ss"
            if let date = fmt.date(from: "\(rawDate) \(rawTime)") {
                return Int64(date.timeIntervalSince1970 * 1000.0)
            }
        }
        fmt.dateFormat = "yyyy.MM.dd"
        if let date = fmt.date(from: rawDate) {
            return Int64(date.timeIntervalSince1970 * 1000.0)
        }
        return nil
    }

    private static func formatTimeControl(initial: Int?, inc: Int?, speed: String?) -> String {
        if let initial {
            let i = inc ?? 0
            if initial < 60 { return "\(initial)s+\(i)" }
            if initial % 60 == 0 { return "\(initial / 60)+\(i)" }
            return String(format: "%.1f+%d", locale: Locale(identifier: "en_US_POSIX"), Double(initial) / 60.0, i)
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
