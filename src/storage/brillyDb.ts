import { openDB, type DBSchema, type IDBPDatabase } from 'idb';
import type { AnalyzedGame } from '../types/chess';
import type {
  FsrsOpeningCard,
  OpeningCourse,
  TrainingLogRecord,
  WoodpeckerCycleRecord,
} from '../types/openings';

const DB_NAME = 'brillyder_db';
const DB_VERSION = 2;
const BACKUP_SCHEMA_VERSION = 2;
const MIGRATION_FLAG_KEY = 'brillyder_idb_migrated_v2';

export interface PrefRecord {
  key: string;
  value: unknown;
  updatedAt: number;
}

interface BrillyDbSchema extends DBSchema {
  analyzed_games: {
    key: string;
    value: AnalyzedGame;
  };
  prefs: {
    key: string;
    value: PrefRecord;
  };
  repertoires: {
    key: string;
    value: OpeningCourse;
  };
  fsrs_cards: {
    key: string;
    value: FsrsOpeningCard;
    indexes: {
      'by-course': string;
      'by-side': string;
      'by-due': number;
    };
  };
  woodpecker_cycles: {
    key: string;
    value: WoodpeckerCycleRecord;
  };
  training_logs: {
    key: string;
    value: TrainingLogRecord;
  };
}

export interface BrillyBackupPayload {
  app: 'brillyder';
  schemaVersion: number;
  exportedAt: string;
  stores: {
    analyzed_games: AnalyzedGame[];
    prefs: PrefRecord[];
    repertoires: OpeningCourse[];
    fsrs_cards: FsrsOpeningCard[];
    woodpecker_cycles: WoodpeckerCycleRecord[];
    training_logs: TrainingLogRecord[];
  };
}

export interface BackupImportSummary {
  analyzedGames: number;
  prefs: number;
  repertoires: number;
  fsrsCards: number;
  woodpeckerCycles: number;
  trainingLogs: number;
}

export interface StorageStats {
  analyzedGames: number;
  repertoires: number;
  fsrsCards: number;
  woodpeckerCycles: number;
  trainingLogs: number;
}

let dbPromise: Promise<IDBPDatabase<BrillyDbSchema>> | null = null;
const prefCache = new Map<string, unknown>();

function canUseIndexedDb(): boolean {
  return typeof indexedDB !== 'undefined';
}

function canUseLocalStorage(): boolean {
  try {
    return typeof localStorage !== 'undefined';
  } catch {
    return false;
  }
}

export async function getBrillyDb(): Promise<IDBPDatabase<BrillyDbSchema>> {
  if (!canUseIndexedDb()) {
    throw new Error('IndexedDB unavailable in this environment.');
  }
  if (!dbPromise) {
    dbPromise = openDB<BrillyDbSchema>(DB_NAME, DB_VERSION, {
      upgrade(db) {
        if (!db.objectStoreNames.contains('analyzed_games')) {
          db.createObjectStore('analyzed_games', { keyPath: 'id' });
        }
        if (!db.objectStoreNames.contains('prefs')) {
          db.createObjectStore('prefs', { keyPath: 'key' });
        }
        if (!db.objectStoreNames.contains('repertoires')) {
          db.createObjectStore('repertoires', { keyPath: 'id' });
        }
        if (!db.objectStoreNames.contains('fsrs_cards')) {
          const store = db.createObjectStore('fsrs_cards', { keyPath: 'cardId' });
          store.createIndex('by-course', 'courseId');
          store.createIndex('by-side', 'side');
          store.createIndex('by-due', 'dueAt');
        }
        if (!db.objectStoreNames.contains('woodpecker_cycles')) {
          db.createObjectStore('woodpecker_cycles', { keyPath: 'id' });
        }
        if (!db.objectStoreNames.contains('training_logs')) {
          db.createObjectStore('training_logs', { keyPath: 'id' });
        }
      },
      blocking() {
        dbPromise = null;
      },
    }).catch((err) => {
      // Never cache a permanently rejected DB open promise
      dbPromise = null;
      throw err;
    });
  }
  return dbPromise;
}

/**
 * Hydrates in-memory pref cache from IndexedDB and performs a one-time
 * idempotent migration of legacy localStorage `brillyder_*` keys into IndexedDB.
 */
export async function hydrateStorageFromIndexedDb(): Promise<void> {
  if (!canUseIndexedDb()) return;
  try {
    const db = await getBrillyDb();
    const existingPrefs = await db.getAll('prefs');
    for (const rec of existingPrefs) {
      prefCache.set(rec.key, rec.value);
    }

    const alreadyMigrated = existingPrefs.some((p) => p.key === MIGRATION_FLAG_KEY);
    if (!alreadyMigrated && canUseLocalStorage()) {
      const tx = db.transaction(['prefs', 'analyzed_games'], 'readwrite');
      const prefStore = tx.objectStore('prefs');
      const gameStore = tx.objectStore('analyzed_games');
      const now = Date.now();
      const migratedGameKeys: string[] = [];

      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (!key || !key.startsWith('brillyder_')) continue;
        const raw = localStorage.getItem(key);
        if (raw === null) continue;
        try {
          const parsed = JSON.parse(raw) as unknown;
          if (key.startsWith('brillyder_game_') && parsed && typeof parsed === 'object' && 'id' in parsed) {
            await gameStore.put(parsed as AnalyzedGame);
            migratedGameKeys.push(key);
          } else {
            const existing = await prefStore.get(key);
            if (!existing) {
              await prefStore.put({ key, value: parsed, updatedAt: now });
              prefCache.set(key, parsed);
            }
          }
        } catch {
          const existing = await prefStore.get(key);
          if (!existing) {
            await prefStore.put({ key, value: raw, updatedAt: now });
            prefCache.set(key, raw);
          }
        }
      }

      await prefStore.put({ key: MIGRATION_FLAG_KEY, value: true, updatedAt: now });
      await tx.done;
      prefCache.set(MIGRATION_FLAG_KEY, true);
      // Free legacy analyzed-game blobs from localStorage quota once safely committed in IDB
      for (const k of migratedGameKeys) {
        try { localStorage.removeItem(k); } catch { /* ignore */ }
      }
    }
  } catch {
    // Graceful fallback to localStorage cache if IndexedDB fails (e.g. private mode restrictions)
  }
}

/* ---------- Analyzed Games ---------- */

export async function saveAnalyzedGameIdb(game: AnalyzedGame): Promise<void> {
  try {
    const db = await getBrillyDb();
    await db.put('analyzed_games', game);
  } catch {
    if (canUseLocalStorage()) {
      try { localStorage.setItem(`brillyder_game_${game.id}`, JSON.stringify(game)); } catch { /* ignore */ }
    }
  }
}

export async function getAllAnalyzedGamesIdb(): Promise<AnalyzedGame[]> {
  try {
    const db = await getBrillyDb();
    const list = await db.getAll('analyzed_games');
    return list.sort((a, b) => b.analyzedAt - a.analyzedAt);
  } catch {
    // Read back localStorage fallback games so private-mode / IDB-error fallback isn't write-only
    if (!canUseLocalStorage()) return [];
    const fallbackGames: AnalyzedGame[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (!key || !key.startsWith('brillyder_game_')) continue;
      try {
        const parsed = JSON.parse(localStorage.getItem(key) ?? '') as AnalyzedGame;
        if (parsed && typeof parsed.id === 'string' && Array.isArray(parsed.plies)) {
          fallbackGames.push(parsed);
        }
      } catch {
        // skip corrupted fallback entry
      }
    }
    return fallbackGames.sort((a, b) => b.analyzedAt - a.analyzedAt);
  }
}

/* ---------- Preferences (Sync cache + IndexedDB write-through) ---------- */

export function getPrefSync<T>(key: string, fallback: T): T {
  if (prefCache.has(key)) {
    return prefCache.get(key) as T;
  }
  if (canUseLocalStorage()) {
    try {
      const raw = localStorage.getItem(key);
      if (raw !== null) {
        const parsed = JSON.parse(raw) as T;
        prefCache.set(key, parsed);
        return parsed;
      }
    } catch {
      return fallback;
    }
  }
  return fallback;
}

export function setPrefSync<T>(key: string, value: T): void {
  prefCache.set(key, value);
  if (canUseLocalStorage()) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* ignore */ }
  }
  if (canUseIndexedDb()) {
    void getBrillyDb()
      .then((db) => db.put('prefs', { key, value, updatedAt: Date.now() }))
      .catch(() => undefined);
  }
}

export async function getPrefAsync<T>(key: string, fallback: T): Promise<T> {
  if (prefCache.has(key)) return prefCache.get(key) as T;
  try {
    const db = await getBrillyDb();
    const rec = await db.get('prefs', key);
    if (rec) {
      prefCache.set(key, rec.value);
      return rec.value as T;
    }
  } catch {
    // ignore
  }
  return getPrefSync(key, fallback);
}

/* ---------- Opening Repertoires ---------- */

export async function getAllRepertoires(): Promise<OpeningCourse[]> {
  try {
    const db = await getBrillyDb();
    return await db.getAll('repertoires');
  } catch {
    return [];
  }
}

export async function saveRepertoire(course: OpeningCourse): Promise<void> {
  const db = await getBrillyDb();
  await db.put('repertoires', course);
}

export async function deleteRepertoire(courseId: string): Promise<void> {
  const db = await getBrillyDb();
  const tx = db.transaction(['repertoires', 'fsrs_cards'], 'readwrite');
  await tx.objectStore('repertoires').delete(courseId);
  const fsrsStore = tx.objectStore('fsrs_cards');
  const cardKeys = await fsrsStore.index('by-course').getAllKeys(courseId);
  for (const key of cardKeys) {
    await fsrsStore.delete(key);
  }
  await tx.done;
}

/* ---------- FSRS Opening Cards ---------- */

export async function getAllFsrsCards(): Promise<FsrsOpeningCard[]> {
  try {
    const db = await getBrillyDb();
    return await db.getAll('fsrs_cards');
  } catch {
    return [];
  }
}

export async function getFsrsCardsByCourse(courseId: string): Promise<FsrsOpeningCard[]> {
  try {
    const db = await getBrillyDb();
    return await db.getAllFromIndex('fsrs_cards', 'by-course', courseId);
  } catch {
    return [];
  }
}

export async function saveFsrsCard(card: FsrsOpeningCard): Promise<void> {
  const db = await getBrillyDb();
  await db.put('fsrs_cards', card);
}

export async function saveFsrsCardsBulk(cards: FsrsOpeningCard[]): Promise<void> {
  if (cards.length === 0) return;
  const db = await getBrillyDb();
  const tx = db.transaction('fsrs_cards', 'readwrite');
  for (const card of cards) {
    await tx.store.put(card);
  }
  await tx.done;
}

/* ---------- Woodpecker Cycles ---------- */

export async function getAllWoodpeckerCycles(): Promise<WoodpeckerCycleRecord[]> {
  try {
    const db = await getBrillyDb();
    const all = await db.getAll('woodpecker_cycles');
    return all.sort((a, b) => b.createdAt - a.createdAt);
  } catch {
    return [];
  }
}

export async function saveWoodpeckerCycle(cycle: WoodpeckerCycleRecord): Promise<void> {
  const db = await getBrillyDb();
  await db.put('woodpecker_cycles', cycle);
}

/* ---------- Training Logs ---------- */

export async function getTrainingLog(id: string): Promise<TrainingLogRecord | undefined> {
  try {
    const db = await getBrillyDb();
    return await db.get('training_logs', id);
  } catch {
    return undefined;
  }
}

export async function getAllTrainingLogs(): Promise<TrainingLogRecord[]> {
  try {
    const db = await getBrillyDb();
    return await db.getAll('training_logs');
  } catch {
    return [];
  }
}

export async function saveTrainingLog(record: TrainingLogRecord): Promise<void> {
  const db = await getBrillyDb();
  await db.put('training_logs', record);
}

/* ---------- Full Backup Export / Import ---------- */

export async function getStorageStats(): Promise<StorageStats> {
  try {
    const db = await getBrillyDb();
    const [analyzedGames, repertoires, fsrsCards, woodpeckerCycles, trainingLogs] = await Promise.all([
      db.count('analyzed_games'),
      db.count('repertoires'),
      db.count('fsrs_cards'),
      db.count('woodpecker_cycles'),
      db.count('training_logs'),
    ]);
    return { analyzedGames, repertoires, fsrsCards, woodpeckerCycles, trainingLogs };
  } catch {
    return { analyzedGames: 0, repertoires: 0, fsrsCards: 0, woodpeckerCycles: 0, trainingLogs: 0 };
  }
}

export function validateBackupPayload(input: unknown): BrillyBackupPayload {
  if (!input || typeof input !== 'object') {
    throw new Error('Backup file must be a JSON object.');
  }
  const obj = input as Partial<BrillyBackupPayload>;
  if (obj.app !== 'brillyder') {
    throw new Error('Unrecognized backup file (expected BrillyDer export).');
  }
  if (typeof obj.schemaVersion !== 'number' || obj.schemaVersion < 1 || obj.schemaVersion > BACKUP_SCHEMA_VERSION) {
    throw new Error(`Unsupported backup schema version: ${String(obj.schemaVersion)}`);
  }
  if (!obj.stores || typeof obj.stores !== 'object') {
    throw new Error('Backup file is missing the stores payload.');
  }
  const stores = obj.stores as Partial<BrillyBackupPayload['stores']>;
  const asArray = <T>(val: unknown, name: string): T[] => {
    if (val === undefined) return [];
    if (!Array.isArray(val)) throw new Error(`Backup store "${name}" must be an array.`);
    return val as T[];
  };

  return {
    app: 'brillyder',
    schemaVersion: obj.schemaVersion,
    exportedAt: typeof obj.exportedAt === 'string' ? obj.exportedAt : new Date().toISOString(),
    stores: {
      analyzed_games: asArray<AnalyzedGame>(stores.analyzed_games, 'analyzed_games'),
      prefs: asArray<PrefRecord>(stores.prefs, 'prefs'),
      repertoires: asArray<OpeningCourse>(stores.repertoires, 'repertoires'),
      fsrs_cards: asArray<FsrsOpeningCard>(stores.fsrs_cards, 'fsrs_cards'),
      woodpecker_cycles: asArray<WoodpeckerCycleRecord>(stores.woodpecker_cycles, 'woodpecker_cycles'),
      training_logs: asArray<TrainingLogRecord>(stores.training_logs, 'training_logs'),
    },
  };
}

export async function exportFullBackup(): Promise<BrillyBackupPayload> {
  const db = await getBrillyDb();
  const tx = db.transaction(
    ['analyzed_games', 'prefs', 'repertoires', 'fsrs_cards', 'woodpecker_cycles', 'training_logs'],
    'readonly'
  );
  const [analyzed_games, prefs, repertoires, fsrs_cards, woodpecker_cycles, training_logs] = await Promise.all([
    tx.objectStore('analyzed_games').getAll(),
    tx.objectStore('prefs').getAll(),
    tx.objectStore('repertoires').getAll(),
    tx.objectStore('fsrs_cards').getAll(),
    tx.objectStore('woodpecker_cycles').getAll(),
    tx.objectStore('training_logs').getAll(),
  ]);
  await tx.done;
  return {
    app: 'brillyder',
    schemaVersion: BACKUP_SCHEMA_VERSION,
    exportedAt: new Date().toISOString(),
    stores: {
      analyzed_games,
      prefs,
      repertoires,
      fsrs_cards,
      woodpecker_cycles,
      training_logs,
    },
  };
}

export async function importFullBackup(
  rawJson: string,
  options: { mode?: 'merge' | 'replace' } = {}
): Promise<BackupImportSummary> {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawJson);
  } catch {
    throw new Error('Selected file is not valid JSON.');
  }
  const payload = validateBackupPayload(parsed);
  const mode = options.mode ?? 'merge';
  const db = await getBrillyDb();

  const tx = db.transaction(
    ['analyzed_games', 'prefs', 'repertoires', 'fsrs_cards', 'woodpecker_cycles', 'training_logs'],
    'readwrite'
  );

  if (mode === 'replace') {
    await Promise.all([
      tx.objectStore('analyzed_games').clear(),
      tx.objectStore('prefs').clear(),
      tx.objectStore('repertoires').clear(),
      tx.objectStore('fsrs_cards').clear(),
      tx.objectStore('woodpecker_cycles').clear(),
      tx.objectStore('training_logs').clear(),
    ]);
    // Keep migration flag inside the replace transaction so hydration never resurrects old localStorage keys
    await tx.objectStore('prefs').put({ key: MIGRATION_FLAG_KEY, value: true, updatedAt: Date.now() });
  }

  let gamesWritten = 0;
  let prefsWritten = 0;
  let repertoiresWritten = 0;
  let fsrsWritten = 0;
  let cyclesWritten = 0;
  let logsWritten = 0;
  const writtenPrefs: PrefRecord[] = [];

  for (const g of payload.stores.analyzed_games) {
    if (g && typeof g.id === 'string' && Array.isArray(g.plies) && g.game) {
      await tx.objectStore('analyzed_games').put(g);
      gamesWritten++;
    }
  }
  for (const p of payload.stores.prefs) {
    if (p && typeof p.key === 'string') {
      await tx.objectStore('prefs').put(p);
      writtenPrefs.push(p);
      prefsWritten++;
    }
  }
  for (const r of payload.stores.repertoires) {
    if (r && typeof r.id === 'string' && Array.isArray(r.lines)) {
      await tx.objectStore('repertoires').put(r);
      repertoiresWritten++;
    }
  }
  for (const c of payload.stores.fsrs_cards) {
    if (c && typeof c.cardId === 'string' && typeof c.courseId === 'string') {
      await tx.objectStore('fsrs_cards').put(c);
      fsrsWritten++;
    }
  }
  for (const w of payload.stores.woodpecker_cycles) {
    if (w && typeof w.id === 'string' && Array.isArray(w.puzzleIds)) {
      await tx.objectStore('woodpecker_cycles').put(w);
      cyclesWritten++;
    }
  }
  for (const t of payload.stores.training_logs) {
    if (t && typeof t.id === 'string') {
      await tx.objectStore('training_logs').put(t);
      logsWritten++;
    }
  }

  // Only mutate in-memory cache and localStorage AFTER the IDB transaction commits atomically!
  await tx.done;

  if (mode === 'replace') {
    prefCache.clear();
    prefCache.set(MIGRATION_FLAG_KEY, true);
    if (canUseLocalStorage()) {
      const toRemove: string[] = [];
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i);
        if (key && key.startsWith('brillyder_')) toRemove.push(key);
      }
      for (const k of toRemove) {
        try { localStorage.removeItem(k); } catch { /* ignore */ }
      }
    }
  }

  for (const p of writtenPrefs) {
    prefCache.set(p.key, p.value);
    if (canUseLocalStorage() && p.key !== MIGRATION_FLAG_KEY) {
      try { localStorage.setItem(p.key, JSON.stringify(p.value)); } catch { /* ignore */ }
    }
  }

  return {
    analyzedGames: gamesWritten,
    prefs: prefsWritten,
    repertoires: repertoiresWritten,
    fsrsCards: fsrsWritten,
    woodpeckerCycles: cyclesWritten,
    trainingLogs: logsWritten,
  };
}
