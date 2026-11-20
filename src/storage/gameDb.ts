import type { AnalyzedGame } from '../types/chess';
import {
  getAllAnalyzedGamesIdb,
  getPrefSync,
  hydrateStorageFromIndexedDb,
  saveAnalyzedGameIdb,
  setPrefSync,
} from './brillyDb';

export async function saveAnalyzedGame(game: AnalyzedGame): Promise<void> {
  await saveAnalyzedGameIdb(game);
}

export async function getAllAnalyzedGames(): Promise<AnalyzedGame[]> {
  return getAllAnalyzedGamesIdb();
}

export function getPref<T>(key: string, fallback: T): T {
  return getPrefSync(key, fallback);
}

export function setPref<T>(key: string, value: T): void {
  setPrefSync(key, value);
}

export { hydrateStorageFromIndexedDb };
