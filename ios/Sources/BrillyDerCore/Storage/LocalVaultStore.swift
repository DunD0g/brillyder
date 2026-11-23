import Foundation

public struct BackupImportSummary: Sendable {
    public let analyzedGames: Int
    public let fsrsCards: Int
    public let repertoires: Int
    public let bookmarks: Int
    public let masteredEndgames: Int
    public let skippedItems: Int

    public var totalImported: Int {
        analyzedGames + fsrsCards + repertoires + bookmarks + masteredEndgames
    }

    public var humanSummary: String {
        var parts: [String] = []
        if analyzedGames > 0 { parts.append("\(analyzedGames) games") }
        if fsrsCards > 0 { parts.append("\(fsrsCards) opening cards") }
        if repertoires > 0 { parts.append("\(repertoires) courses") }
        if bookmarks > 0 { parts.append("\(bookmarks) bookmarks") }
        if masteredEndgames > 0 { parts.append("\(masteredEndgames) endgames") }
        return parts.isEmpty ? "Backup synced cleanly." : "Imported " + parts.joined(separator: ", ") + "."
    }
}

/// Exact Web PWA <-> iOS Backup schema (`app: "brillyder"`, `schemaVersion: 2`).
public struct BrillyBackupPayload: Codable, Sendable {
    public struct PrefRecord: Codable, Sendable {
        public let key: String
        public let value: JSONValue
        public let updatedAt: Int64

        public init(key: String, value: JSONValue, updatedAt: Int64) {
            self.key = key
            self.value = value
            self.updatedAt = updatedAt
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.key = try c.decode(String.self, forKey: .key)
            self.value = (try? c.decode(JSONValue.self, forKey: .value)) ?? .null
            if let i = try? c.decode(Int64.self, forKey: .updatedAt) {
                self.updatedAt = i
            } else if let d = try? c.decode(Double.self, forKey: .updatedAt) {
                self.updatedAt = Int64(d)
            } else {
                self.updatedAt = 0
            }
        }
    }

    public struct Stores: Codable, Sendable {
        public var analyzed_games: [AnalyzedGame]
        public var prefs: [PrefRecord]
        public var repertoires: [OpeningCourse]
        public var fsrs_cards: [FsrsOpeningCard]
        public var woodpecker_cycles: [WoodpeckerCycleRecord]
        public var training_logs: [JSONValue]

        public init(
            analyzed_games: [AnalyzedGame] = [],
            prefs: [PrefRecord] = [],
            repertoires: [OpeningCourse] = [],
            fsrs_cards: [FsrsOpeningCard] = [],
            woodpecker_cycles: [WoodpeckerCycleRecord] = [],
            training_logs: [JSONValue] = []
        ) {
            self.analyzed_games = analyzed_games
            self.prefs = prefs
            self.repertoires = repertoires
            self.fsrs_cards = fsrs_cards
            self.woodpecker_cycles = woodpecker_cycles
            self.training_logs = training_logs
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.analyzed_games = (try? c.decode([AnalyzedGame].self, forKey: .analyzed_games)) ?? []
            self.prefs = (try? c.decode([PrefRecord].self, forKey: .prefs)) ?? []
            self.repertoires = (try? c.decode([OpeningCourse].self, forKey: .repertoires)) ?? []
            self.fsrs_cards = (try? c.decode([FsrsOpeningCard].self, forKey: .fsrs_cards)) ?? []
            self.woodpecker_cycles = (try? c.decode([WoodpeckerCycleRecord].self, forKey: .woodpecker_cycles)) ?? []
            self.training_logs = (try? c.decode([JSONValue].self, forKey: .training_logs)) ?? []
        }
    }

    public let app: String
    public let schemaVersion: Int
    public let exportedAt: String
    public var stores: Stores

    public init(
        app: String = "brillyder",
        schemaVersion: Int = 2,
        exportedAt: String = FSRS6Scheduler.isoString(from: Date()),
        stores: Stores
    ) {
        self.app = app
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.stores = stores
    }
}

/// Lightweight Sendable JSON value for lossless Web <-> iOS `prefs` round-trips.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let b = try? container.decode(Bool.self) { self = .bool(b) }
        else if let n = try? container.decode(Double.self) { self = .number(n) }
        else if let s = try? container.decode(String.self) { self = .string(s) }
        else if let a = try? container.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? container.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }
}

/// Lossy per-element array decoder so one malformed record never wipes an entire persisted array.
private struct LossyDecodableArray<Element: Decodable>: Decodable {
    let elements: [Element]

    private struct Dummy: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decoded: [Element] = []
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                decoded.append(value)
            } else {
                _ = try? container.decode(Dummy.self)
            }
        }
        self.elements = decoded
    }
}

public struct VaultSnapshot: Codable, Sendable {
    public var analyzedGames: [AnalyzedGame]
    public var fsrsCards: [FsrsOpeningCard]
    public var customCourses: [OpeningCourse]
    public var bookmarks: [SavedPositionBookmark]
    public var dailyStreakDays: Int
    public var lastDailyCompletedDate: String?
    public var lichessUsername: String
    public var chessComUsername: String
    public var woodpeckerCycle: WoodpeckerCycleRecord?
    public var masteredEndgameIds: [String]
    public var convertedAdvantageIds: [String]
    public var boardVisionBestScore: Int
    public var puzzleRushBlitzBest: Int
    public var puzzleRushSurvivalBest: Int

    public init(
        analyzedGames: [AnalyzedGame] = [],
        fsrsCards: [FsrsOpeningCard] = [],
        customCourses: [OpeningCourse] = [],
        bookmarks: [SavedPositionBookmark] = [],
        dailyStreakDays: Int = 0,
        lastDailyCompletedDate: String? = nil,
        lichessUsername: String = "",
        chessComUsername: String = "",
        woodpeckerCycle: WoodpeckerCycleRecord? = nil,
        masteredEndgameIds: [String] = [],
        convertedAdvantageIds: [String] = [],
        boardVisionBestScore: Int = 0,
        puzzleRushBlitzBest: Int = 0,
        puzzleRushSurvivalBest: Int = 0
    ) {
        self.analyzedGames = analyzedGames
        self.fsrsCards = fsrsCards
        self.customCourses = customCourses
        self.bookmarks = bookmarks
        self.dailyStreakDays = dailyStreakDays
        self.lastDailyCompletedDate = lastDailyCompletedDate
        self.lichessUsername = lichessUsername
        self.chessComUsername = chessComUsername
        self.woodpeckerCycle = woodpeckerCycle
        self.masteredEndgameIds = masteredEndgameIds
        self.convertedAdvantageIds = convertedAdvantageIds
        self.boardVisionBestScore = boardVisionBestScore
        self.puzzleRushBlitzBest = puzzleRushBlitzBest
        self.puzzleRushSurvivalBest = puzzleRushSurvivalBest
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.analyzedGames = (try? c.decode(LossyDecodableArray<AnalyzedGame>.self, forKey: .analyzedGames))?.elements ?? []
        self.fsrsCards = (try? c.decode(LossyDecodableArray<FsrsOpeningCard>.self, forKey: .fsrsCards))?.elements ?? []
        self.customCourses = (try? c.decode(LossyDecodableArray<OpeningCourse>.self, forKey: .customCourses))?.elements ?? []
        self.bookmarks = (try? c.decode(LossyDecodableArray<SavedPositionBookmark>.self, forKey: .bookmarks))?.elements ?? []
        self.dailyStreakDays = (try? c.decode(Int.self, forKey: .dailyStreakDays)) ?? 0
        self.lastDailyCompletedDate = try? c.decode(String.self, forKey: .lastDailyCompletedDate)
        self.lichessUsername = (try? c.decode(String.self, forKey: .lichessUsername)) ?? ""
        self.chessComUsername = (try? c.decode(String.self, forKey: .chessComUsername)) ?? ""
        self.woodpeckerCycle = try? c.decode(WoodpeckerCycleRecord.self, forKey: .woodpeckerCycle)
        self.masteredEndgameIds = (try? c.decode([String].self, forKey: .masteredEndgameIds)) ?? []
        self.convertedAdvantageIds = (try? c.decode([String].self, forKey: .convertedAdvantageIds)) ?? []
        self.boardVisionBestScore = (try? c.decode(Int.self, forKey: .boardVisionBestScore)) ?? 0
        self.puzzleRushBlitzBest = (try? c.decode(Int.self, forKey: .puzzleRushBlitzBest)) ?? 0
        self.puzzleRushSurvivalBest = (try? c.decode(Int.self, forKey: .puzzleRushSurvivalBest)) ?? 0
    }
}

/// Local-first file vault stored inside Application Support with zero cloud dependencies.
public actor LocalVaultStore {
    private let fileURL: URL

    public init(customDirectory: URL? = nil) {
        let base = customDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("BrillyDer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("brillyder_vault_v2.json")
    }

    public func load() -> VaultSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return VaultSnapshot()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(VaultSnapshot.self, from: data)
        } catch {
            // Preserve unreadable file for diagnostics/recovery instead of silently destroying it.
            let backupURL = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            return VaultSnapshot()
        }
    }

    public func save(_ snapshot: VaultSnapshot) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    public static func exportBackupJSON(from snapshot: VaultSnapshot) throws -> Data {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let encoder = JSONEncoder()
        var prefs: [BrillyBackupPayload.PrefRecord] = []

        if !snapshot.lichessUsername.isEmpty {
            prefs.append(.init(key: "brillyder_username_lichess", value: .string(snapshot.lichessUsername), updatedAt: nowMs))
            prefs.append(.init(key: "brillyder_username", value: .string(snapshot.lichessUsername), updatedAt: nowMs))
        }
        if !snapshot.chessComUsername.isEmpty {
            prefs.append(.init(key: "brillyder_username_chesscom", value: .string(snapshot.chessComUsername), updatedAt: nowMs))
            prefs.append(.init(key: "brillyder_chesscom_username", value: .string(snapshot.chessComUsername), updatedAt: nowMs))
        }
        if !snapshot.masteredEndgameIds.isEmpty {
            prefs.append(.init(
                key: "brillyder_endgame_mastered_v1",
                value: .array(snapshot.masteredEndgameIds.map { .string($0) }),
                updatedAt: nowMs
            ))
        }
        if snapshot.boardVisionBestScore > 0 {
            prefs.append(.init(key: "brillyder_vision_best_white", value: .number(Double(snapshot.boardVisionBestScore)), updatedAt: nowMs))
        }
        if snapshot.puzzleRushBlitzBest > 0 {
            prefs.append(.init(key: "brillyder_rush_best", value: .number(Double(snapshot.puzzleRushBlitzBest)), updatedAt: nowMs))
        }
        if snapshot.puzzleRushSurvivalBest > 0 {
            prefs.append(.init(key: "brillyder_rush_survival_best", value: .number(Double(snapshot.puzzleRushSurvivalBest)), updatedAt: nowMs))
        }
        if snapshot.dailyStreakDays > 0 || snapshot.lastDailyCompletedDate != nil {
            var streakObj: [String: JSONValue] = [
                "current": .number(Double(snapshot.dailyStreakDays)),
                "best": .number(Double(snapshot.dailyStreakDays)),
                "lastDate": .string(snapshot.lastDailyCompletedDate ?? ""),
            ]
            if let dateStr = snapshot.lastDailyCompletedDate, let ms = parseDayStringToEpochMs(dateStr) {
                streakObj["lastSolvedAt"] = .number(Double(ms))
                prefs.append(.init(key: "brillyder_daily_done", value: .string(dateStr), updatedAt: nowMs))
            }
            prefs.append(.init(key: "brillyder_mistake_streak", value: .object(streakObj), updatedAt: nowMs))
        }
        if !snapshot.bookmarks.isEmpty,
           let bmData = try? encoder.encode(snapshot.bookmarks),
           let bmVal = try? JSONDecoder().decode(JSONValue.self, from: bmData) {
            prefs.append(.init(key: "brillyder_saved_positions_v1", value: bmVal, updatedAt: nowMs))
        }

        var trainingLogs: [JSONValue] = []
        if !snapshot.convertedAdvantageIds.isEmpty {
            let idVals = snapshot.convertedAdvantageIds.sorted().map { JSONValue.string($0) }
            trainingLogs.append(.object([
                "id": .string("conversion_mastered"),
                "kind": .string("conversion"),
                "createdAt": .number(Double(nowMs)),
                "data": .object([
                    "ids": .array(idVals),
                    "convertedIds": .array(idVals),
                ]),
            ]))
        }

        let payload = BrillyBackupPayload(
            stores: .init(
                analyzed_games: snapshot.analyzedGames,
                prefs: prefs,
                repertoires: snapshot.customCourses,
                fsrs_cards: snapshot.fsrsCards,
                woodpecker_cycles: snapshot.woodpeckerCycle.map { [$0] } ?? [],
                training_logs: trainingLogs
            )
        )
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    /// Resilient, smart-merge import compatible with real Web PWA (`brillyder-backup-*.json`) AND iOS exports.
    public static func mergeBackupJSON(_ data: Data, into existing: VaultSnapshot) throws -> VaultSnapshot {
        let (merged, _) = try mergeBackupJSONWithSummary(data, into: existing)
        return merged
    }

    public static func mergeBackupJSONWithSummary(
        _ data: Data,
        into existing: VaultSnapshot
    ) throws -> (snapshot: VaultSnapshot, summary: BackupImportSummary) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["app"] as? String) == "brillyder",
              let stores = root["stores"] as? [String: Any] else {
            throw NSError(
                domain: "BrillyDerCore",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "Unrecognized backup file (expected a BrillyDer JSON backup)."]
            )
        }

        let decoder = JSONDecoder()
        var merged = existing
        var skipped = 0

        func decodeArray<T: Decodable>(_ raw: Any?, as type: T.Type) -> [T] {
            guard let arr = raw as? [Any] else { return [] }
            var out: [T] = []
            for item in arr {
                guard JSONSerialization.isValidJSONObject(item),
                      let itemData = try? JSONSerialization.data(withJSONObject: item) else {
                    skipped += 1
                    continue
                }
                if let decoded = try? decoder.decode(T.self, from: itemData) {
                    out.append(decoded)
                } else {
                    skipped += 1
                }
            }
            return out
        }

        // 1. Analyzed games (keep newest analyzedAt per id, exclude 0-ply sandbox placeholders)
        let incomingGames = decodeArray(stores["analyzed_games"], as: AnalyzedGame.self).filter { !$0.plies.isEmpty }
        var gamesById = Dictionary(merged.analyzedGames.map { ($0.id, $0) }, uniquingKeysWith: { a, b in
            a.analyzedAt >= b.analyzedAt ? a : b
        })
        for incoming in incomingGames {
            if let cur = gamesById[incoming.id], cur.analyzedAt >= incoming.analyzedAt { continue }
            gamesById[incoming.id] = incoming
        }
        merged.analyzedGames = Array(gamesById.values).sorted { $0.game.createdAt > $1.game.createdAt }

        // 2. FSRS Opening Cards (preserve unlocked state, prefer newer review then higher attempts)
        let incomingCards = decodeArray(stores["fsrs_cards"], as: FsrsOpeningCard.self)
        var cardsById = Dictionary(merged.fsrsCards.map { ($0.cardId, $0) }, uniquingKeysWith: { a, b in
            mergeCard(existing: a, incoming: b)
        })
        for incoming in incomingCards {
            if let cur = cardsById[incoming.cardId] {
                cardsById[incoming.cardId] = mergeCard(existing: cur, incoming: incoming)
            } else {
                cardsById[incoming.cardId] = incoming
            }
        }
        merged.fsrsCards = Array(cardsById.values)

        // 3. Repertoires (dedup safely by ID — never crash on duplicate starter IDs!)
        let incomingCourses = decodeArray(stores["repertoires"], as: OpeningCourse.self)
        var coursesById = Dictionary(merged.customCourses.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for incoming in incomingCourses {
            coursesById[incoming.id] = incoming
        }
        merged.customCourses = Array(coursesById.values)

        // 4. Prefs (usernames, bookmarks, mastered endgames, streaks, personal bests!)
        var importedBookmarksCount = 0
        var importedEndgamesCount = 0
        let incomingPrefs = decodeArray(stores["prefs"], as: BrillyBackupPayload.PrefRecord.self)

        // Check explicit platform keys with priority over legacy `brillyder_username`
        var explicitLichess: String? = nil
        var legacyUsername: String? = nil
        var explicitChessCom: String? = nil

        for pref in incomingPrefs {
            switch pref.key {
            case "brillyder_username_lichess":
                if case .string(let s) = pref.value, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    explicitLichess = s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            case "brillyder_username":
                if case .string(let s) = pref.value, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    legacyUsername = s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            case "brillyder_username_chesscom", "brillyder_chesscom_username":
                if case .string(let s) = pref.value, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    explicitChessCom = s.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            case "brillyder_endgame_mastered_v1":
                if case .array(let arr) = pref.value {
                    let ids = arr.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
                    importedEndgamesCount += ids.count
                    merged.masteredEndgameIds = Array(Set(merged.masteredEndgameIds + ids))
                }
            case "brillyder_saved_positions_v1":
                if case .array(let bmArr) = pref.value {
                    var decodedBms: [SavedPositionBookmark] = []
                    for item in bmArr {
                        if let rawItemData = try? JSONEncoder().encode(item),
                           let bm = try? decoder.decode(SavedPositionBookmark.self, from: rawItemData) {
                            decodedBms.append(bm)
                        } else {
                            skipped += 1
                        }
                    }
                    importedBookmarksCount += decodedBms.count
                    var bmByPosKey = Dictionary(merged.bookmarks.map { ("\($0.gameId)::\($0.ply)", $0) }, uniquingKeysWith: { a, b in
                        a.createdAt >= b.createdAt ? a : b
                    })
                    for bm in decodedBms {
                        let key = "\(bm.gameId)::\(bm.ply)"
                        if let cur = bmByPosKey[key], cur.createdAt >= bm.createdAt { continue }
                        bmByPosKey[key] = bm
                    }
                    merged.bookmarks = Array(bmByPosKey.values).sorted { $0.createdAt > $1.createdAt }
                }
            case "brillyder_rush_best":
                if case .number(let n) = pref.value {
                    merged.puzzleRushBlitzBest = max(merged.puzzleRushBlitzBest, Int(n.rounded()))
                }
            case "brillyder_rush_survival_best":
                if case .number(let n) = pref.value {
                    merged.puzzleRushSurvivalBest = max(merged.puzzleRushSurvivalBest, Int(n.rounded()))
                }
            case "brillyder_daily_done":
                if case .string(let d) = pref.value, !d.isEmpty {
                    if (merged.lastDailyCompletedDate ?? "") < d {
                        merged.lastDailyCompletedDate = d
                    }
                }
            case "brillyder_mistake_streak":
                if case .object(let obj) = pref.value {
                    if case .number(let cur) = obj["current"] {
                        merged.dailyStreakDays = max(merged.dailyStreakDays, Int(cur.rounded()))
                    }
                    if case .string(let d) = obj["lastDate"], !d.isEmpty {
                        if (merged.lastDailyCompletedDate ?? "") < d {
                            merged.lastDailyCompletedDate = d
                        }
                    } else if case .number(let ms) = obj["lastSolvedAt"], ms > 0 {
                        let dayStr = formatDayString(fromEpochMs: Int64(ms))
                        if (merged.lastDailyCompletedDate ?? "") < dayStr {
                            merged.lastDailyCompletedDate = dayStr
                        }
                    }
                }
            default:
                if pref.key.hasPrefix("brillyder_vision_best_"), case .number(let n) = pref.value {
                    merged.boardVisionBestScore = max(merged.boardVisionBestScore, Int(n.rounded()))
                }
            }
        }

        if let lichess = explicitLichess ?? legacyUsername {
            merged.lichessUsername = lichess
        }
        if let cc = explicitChessCom {
            merged.chessComUsername = cc
        }

        // 5. Training Logs (Advantage Conversion IDs — Web writes `data.ids`, older iOS wrote `data.convertedIds`)
        if let rawLogs = stores["training_logs"] as? [[String: Any]] {
            for log in rawLogs where (log["kind"] as? String) == "conversion" {
                if let logData = log["data"] as? [String: Any] {
                    let ids = (logData["ids"] as? [String]) ?? (logData["convertedIds"] as? [String]) ?? []
                    if !ids.isEmpty {
                        merged.convertedAdvantageIds = Array(Set(merged.convertedAdvantageIds + ids))
                    }
                }
            }
        }

        // 6. Woodpecker Cycles (Web & iOS bidirectional import)
        let incomingCycles = decodeArray(stores["woodpecker_cycles"], as: WoodpeckerCycleRecord.self)
        if !incomingCycles.isEmpty {
            let candidates = (merged.woodpeckerCycle.map { [$0] } ?? []) + incomingCycles
            merged.woodpeckerCycle = candidates.max { lhs, rhs in
                if lhs.completedCycles.count != rhs.completedCycles.count {
                    return lhs.completedCycles.count < rhs.completedCycles.count
                }
                if lhs.currentCycle != rhs.currentCycle {
                    return lhs.currentCycle < rhs.currentCycle
                }
                if lhs.activeIndex != rhs.activeIndex {
                    return lhs.activeIndex < rhs.activeIndex
                }
                return lhs.createdAt < rhs.createdAt
            }
        }

        let summary = BackupImportSummary(
            analyzedGames: incomingGames.count,
            fsrsCards: incomingCards.count,
            repertoires: incomingCourses.count,
            bookmarks: importedBookmarksCount,
            masteredEndgames: importedEndgamesCount,
            skippedItems: skipped
        )
        return (merged, summary)
    }

    // MARK: - Helpers

    private static func mergeCard(existing cur: FsrsOpeningCard, incoming: FsrsOpeningCard) -> FsrsOpeningCard {
        let unlocked = cur.unlocked || incoming.unlocked
        let curRev = cur.fsrsState.last_review ?? ""
        let incRev = incoming.fsrsState.last_review ?? ""
        var winner: FsrsOpeningCard
        if incRev != curRev {
            winner = incRev > curRev ? incoming : cur
        } else {
            winner = incoming.attempts >= cur.attempts ? incoming : cur
        }
        winner.unlocked = unlocked
        return winner
    }

    private static func formatDayString(fromEpochMs ms: Int64) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date(timeIntervalSince1970: Double(ms) / 1000.0))
    }

    private static func parseDayStringToEpochMs(_ day: String) -> Int64? {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: day) else { return nil }
        return Int64(date.timeIntervalSince1970 * 1000.0)
    }
}
