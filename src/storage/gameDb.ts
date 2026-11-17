import type { AnalyzedGame } from '../types/chess';

const DB_NAME = 'brillyder_db';
const STORE_ANALYZED = 'analyzed_games';

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    if (typeof indexedDB === 'undefined') { reject(new Error('No IndexedDB')); return; }
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains(STORE_ANALYZED)) {
        req.result.createObjectStore(STORE_ANALYZED, { keyPath: 'id' });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

export async function saveAnalyzedGame(game: AnalyzedGame): Promise<void> {
  try {
    const db = await openDb();
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction(STORE_ANALYZED, 'readwrite');
      tx.objectStore(STORE_ANALYZED).put(game);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  } catch {
    try { localStorage.setItem(`brillyder_game_${game.id}`, JSON.stringify(game)); } catch { /* ignore */ }
  }
}

export async function getAllAnalyzedGames(): Promise<AnalyzedGame[]> {
  try {
    const db = await openDb();
    const list = await new Promise<AnalyzedGame[]>((resolve, reject) => {
      const tx = db.transaction(STORE_ANALYZED, 'readonly');
      const req = tx.objectStore(STORE_ANALYZED).getAll();
      req.onsuccess = () => resolve((req.result as AnalyzedGame[]) ?? []);
      req.onerror = () => reject(req.error);
    });
    return list.sort((a, b) => b.analyzedAt - a.analyzedAt);
  } catch {
    return [];
  }
}

export function getPref<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key);
    return raw === null ? fallback : (JSON.parse(raw) as T);
  } catch { return fallback; }
}

export function setPref<T>(key: string, value: T): void {
  try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* ignore */ }
}
