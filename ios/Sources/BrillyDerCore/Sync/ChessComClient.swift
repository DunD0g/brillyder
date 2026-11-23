import Foundation

public enum ChessComClient {
    private static let strictUsernameChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

    private struct ArchivesResponse: Decodable {
        let archives: [String]?
    }

    private struct ArchiveGamesResponse: Decodable {
        let games: [RawGame]?
    }

    private struct RawSide: Decodable {
        let username: String?
        let rating: Int?
        let result: String?
    }

    private struct RawGame: Decodable {
        let url: String?
        let pgn: String?
        let time_control: String?
        let end_time: Int64?
        let rated: Bool?
        let time_class: String?
        let rules: String?
        let uuid: String?
        let white: RawSide?
        let black: RawSide?
    }

    public static func fetchRecentGames(username: String, maxGames: Int = 20) async throws -> [GameRecord] {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { throw SyncError.emptyUsername }
        guard trimmed.unicodeScalars.allSatisfy({ strictUsernameChars.contains($0) }),
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: strictUsernameChars),
              let archivesUrl = URL(string: "https://api.chess.com/pub/player/\(encoded)/games/archives") else {
            throw SyncError.networkFailure("Invalid Chess.com username.")
        }

        let targetCount = max(1, min(50, maxGames))
        let archivesPayload: ArchivesResponse = try await fetchJSON(from: archivesUrl, username: trimmed)
        let archives = Array((archivesPayload.archives ?? []).suffix(6).reversed())

        var collected: [GameRecord] = []
        var seenIds = Set<String>()
        for archiveStr in archives {
            try Task.checkCancellation()
            if collected.count >= targetCount { break }
            guard let url = URL(string: archiveStr) else { continue }
            let monthPayload: ArchiveGamesResponse
            do {
                monthPayload = try await fetchJSON(from: url, username: trimmed)
            } catch is CancellationError {
                throw CancellationError()
            } catch let syncErr as SyncError {
                if case .rateLimited = syncErr { throw syncErr }
                continue
            } catch {
                continue
            }
            let sortedMonth = (monthPayload.games ?? []).sorted { ($0.end_time ?? 0) > ($1.end_time ?? 0) }
            for raw in sortedMonth {
                if collected.count >= targetCount { break }
                if let rules = raw.rules, rules != "chess" { continue }
                if let record = normalizeGame(raw, username: trimmed), seenIds.insert(record.id).inserted {
                    collected.append(record)
                }
            }
        }

        collected.sort { $0.createdAt > $1.createdAt }
        return Array(collected.prefix(targetCount))
    }

    private static func fetchJSON<T: Decodable>(from url: URL, username: String) async throws -> T {
        var req = URLRequest(url: url, timeoutInterval: 16)
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
            throw SyncError.networkFailure("Could not reach Chess.com: \(error.localizedDescription)")
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw SyncError.userNotFound("Chess.com user \"\(username)\" not found.") }
            if http.statusCode == 429 { throw SyncError.rateLimited("Chess.com rate limit hit — retry in a minute.") }
            if !(200..<300).contains(http.statusCode) {
                throw SyncError.networkFailure("Chess.com API error (\(http.statusCode)).")
            }
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func normalizeGame(_ raw: RawGame, username: String) -> GameRecord? {
        guard let pgn = raw.pgn,
              let whiteName = raw.white?.username,
              let blackName = raw.black?.username,
              let parsed = try? PGNParser.parse(pgn),
              parsed.moves.count >= 2 else { return nil }

        let userColor: PieceColor?
        if whiteName.lowercased() == username { userColor = .white }
        else if blackName.lowercased() == username { userColor = .black }
        else { userColor = nil }

        let res = resultString(white: raw.white?.result, black: raw.black?.result)
        let winner: String? = res == "1-0" ? "white" : (res == "0-1" ? "black" : nil)
        let sanMoves = parsed.moves.map(\.applied.san)
        let lookup = parsed.startFen == ChessBoard.initialFEN ? MoveClassifier.lookupOpening(byMoves: sanMoves) : nil
        let openingName = parsed.headers["Opening"] ?? parseOpeningFromEcoUrl(parsed.headers["ECOUrl"]) ?? lookup?.name ?? "Unknown Opening"
        let openingEco = parsed.headers["ECO"] ?? lookup?.eco ?? ""
        let id = raw.uuid ?? raw.url?.split(separator: "/").last.map(String.init) ?? UUID().uuidString
        let speed = raw.time_class ?? "rapid"

        return GameRecord(
            id: "cc_\(id)",
            source: .chesscom,
            rated: raw.rated ?? false,
            variant: "standard",
            speed: speed,
            perf: speed,
            createdAt: (raw.end_time ?? Int64(Date().timeIntervalSince1970)) * 1000,
            status: "normal",
            winner: winner,
            resultString: res,
            timeControlLabel: formatTimeControl(raw.time_control, speed: speed),
            pgn: pgn,
            openingName: openingName,
            openingEco: openingEco,
            openingPly: lookup?.matchedPlies,
            white: PlayerInfo(name: whiteName, rating: raw.white?.rating),
            black: PlayerInfo(name: blackName, rating: raw.black?.rating),
            userColor: userColor,
            url: raw.url
        )
    }

    private static func resultString(white: String?, black: String?) -> String {
        if white == "win" { return "1-0" }
        if black == "win" { return "0-1" }
        let drawCodes: Set<String> = ["agreed", "repetition", "stalemate", "insufficient", "50move", "timevsinsufficient"]
        if let w = white, drawCodes.contains(w) { return "1/2-1/2" }
        if let b = black, drawCodes.contains(b) { return "1/2-1/2" }
        return "*"
    }

    private static func parseOpeningFromEcoUrl(_ ecoUrl: String?) -> String? {
        guard let ecoUrl, let range = ecoUrl.range(of: "/openings/") else { return nil }
        let tail = String(ecoUrl[range.upperBound...]).split(separator: "?").first.map(String.init) ?? ""
        let decoded = tail.removingPercentEncoding ?? tail
        let cleaned = decoded.replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func formatTimeControl(_ raw: String?, speed: String) -> String {
        guard let raw, !raw.isEmpty else { return speed.capitalized }
        if raw.hasPrefix("1/") {
            if let secs = Double(raw.dropFirst(2)), secs >= 86400 {
                return "\(Int((secs / 86400.0).rounded()))d"
            }
            return "Daily"
        }
        let parts = raw.split(separator: "+")
        guard let base = Double(parts[0]) else { return raw }
        let inc = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        if base < 60 { return "\(Int(base))s+\(inc)" }
        let mins = base / 60.0
        if mins.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(mins))+\(inc)"
        }
        return String(format: "%.1f+%d", locale: Locale(identifier: "en_US_POSIX"), mins, inc)
    }
}
