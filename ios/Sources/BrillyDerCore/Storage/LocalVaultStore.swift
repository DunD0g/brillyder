import Foundation

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
    }

    public struct Stores: Codable, Sendable {
        public var analyzed_games: [AnalyzedGame]
        public var prefs: [PrefRecord]
        public var repertoires: [OpeningCourse]
        public var fsrs_cards: [FsrsOpeningCard]

        public init(
            analyzed_games: [AnalyzedGame] = [],
            prefs: [PrefRecord] = [],
            repertoires: [OpeningCourse] = [],
            fsrs_cards: [FsrsOpeningCard] = []
        ) {
            self.analyzed_games = analyzed_games
            self.prefs = prefs
            self.repertoires = repertoires
            self.fsrs_cards = fsrs_cards
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
        boardVisionBestScore: Int = 0
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
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.analyzedGames = (try? c.decode([AnalyzedGame].self, forKey: .analyzedGames)) ?? []
        self.fsrsCards = (try? c.decode([FsrsOpeningCard].self, forKey: .fsrsCards)) ?? []
        self.customCourses = (try? c.decode([OpeningCourse].self, forKey: .customCourses)) ?? []
        self.bookmarks = (try? c.decode([SavedPositionBookmark].self, forKey: .bookmarks)) ?? []
        self.dailyStreakDays = (try? c.decode(Int.self, forKey: .dailyStreakDays)) ?? 0
        self.lastDailyCompletedDate = try? c.decode(String.self, forKey: .lastDailyCompletedDate)
        self.lichessUsername = (try? c.decode(String.self, forKey: .lichessUsername)) ?? ""
        self.chessComUsername = (try? c.decode(String.self, forKey: .chessComUsername)) ?? ""
        self.woodpeckerCycle = try? c.decode(WoodpeckerCycleRecord.self, forKey: .woodpeckerCycle)
        self.masteredEndgameIds = (try? c.decode([String].self, forKey: .masteredEndgameIds)) ?? []
        self.convertedAdvantageIds = (try? c.decode([String].self, forKey: .convertedAdvantageIds)) ?? []
        self.boardVisionBestScore = (try? c.decode(Int.self, forKey: .boardVisionBestScore)) ?? 0
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
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? JSONDecoder().decode(VaultSnapshot.self, from: data) else {
            return VaultSnapshot()
        }
        return snap
    }

    public func save(_ snapshot: VaultSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    public static func exportBackupJSON(from snapshot: VaultSnapshot) throws -> Data {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        var prefs: [BrillyBackupPayload.PrefRecord] = []
        if !snapshot.lichessUsername.isEmpty {
            prefs.append(.init(key: "brillyder_username", value: .string(snapshot.lichessUsername), updatedAt: nowMs))
        }
        if !snapshot.chessComUsername.isEmpty {
            prefs.append(.init(key: "brillyder_chesscom_username", value: .string(snapshot.chessComUsername), updatedAt: nowMs))
        }
        let payload = BrillyBackupPayload(
            stores: .init(
                analyzed_games: snapshot.analyzedGames,
                prefs: prefs,
                repertoires: snapshot.customCourses,
                fsrs_cards: snapshot.fsrsCards
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    /// Smart-merge import compatible with backups exported by the BrillyDer Web PWA or iOS app.
    public static func mergeBackupJSON(_ data: Data, into existing: VaultSnapshot) throws -> VaultSnapshot {
        let payload = try JSONDecoder().decode(BrillyBackupPayload.self, from: data)
        guard payload.app == "brillyder" else {
            throw NSError(
                domain: "BrillyDerCore",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "Invalid backup file (expected BrillyDer schema)."]
            )
        }

        var merged = existing

        // Merge analyzed games (keep newest analyzedAt per id)
        var gamesById = Dictionary(uniqueKeysWithValues: merged.analyzedGames.map { ($0.id, $0) })
        for incoming in payload.stores.analyzed_games {
            if let cur = gamesById[incoming.id], cur.analyzedAt >= incoming.analyzedAt {
                continue
            }
            gamesById[incoming.id] = incoming
        }
        merged.analyzedGames = Array(gamesById.values).sorted { $0.game.createdAt > $1.game.createdAt }

        // Merge FSRS cards (keep higher attempts / newer review)
        var cardsById = Dictionary(uniqueKeysWithValues: merged.fsrsCards.map { ($0.cardId, $0) })
        for incoming in payload.stores.fsrs_cards {
            if let cur = cardsById[incoming.cardId], cur.attempts > incoming.attempts {
                continue
            }
            cardsById[incoming.cardId] = incoming
        }
        merged.fsrsCards = Array(cardsById.values)

        // Merge custom courses
        var coursesById = Dictionary(uniqueKeysWithValues: merged.customCourses.map { ($0.id, $0) })
        for incoming in payload.stores.repertoires {
            coursesById[incoming.id] = incoming
        }
        merged.customCourses = Array(coursesById.values)

        // Restore usernames if blank locally
        for pref in payload.stores.prefs {
            if pref.key == "brillyder_username", case .string(let s) = pref.value, merged.lichessUsername.isEmpty {
                merged.lichessUsername = s
            }
            if pref.key == "brillyder_chesscom_username", case .string(let s) = pref.value, merged.chessComUsername.isEmpty {
                merged.chessComUsername = s
            }
        }

        return merged
    }
}
