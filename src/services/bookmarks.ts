import type { SavedPositionBookmark } from '../types/chess';
import { getPref, setPref } from '../storage/gameDb';

export const SAVED_POSITIONS_PREF_KEY = 'brillyder_saved_positions_v1';

export function loadSavedPositions(): SavedPositionBookmark[] {
  const raw = getPref<SavedPositionBookmark[]>(SAVED_POSITIONS_PREF_KEY, []);
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((b) => b && typeof b.id === 'string' && typeof b.fen === 'string')
    .sort((a, b) => b.createdAt - a.createdAt);
}

export function saveSavedPositions(list: SavedPositionBookmark[]): void {
  setPref(SAVED_POSITIONS_PREF_KEY, list.slice(0, 120));
}

export function buildBookmarkId(gameId: string, ply: number): string {
  return `${gameId}::${ply}`;
}

export function toggleBookmarkInList(
  list: SavedPositionBookmark[],
  item: Omit<SavedPositionBookmark, 'id' | 'createdAt'>
): { next: SavedPositionBookmark[]; added: boolean } {
  const id = buildBookmarkId(item.gameId, item.ply);
  const exists = list.some((b) => b.id === id);
  if (exists) {
    return { next: list.filter((b) => b.id !== id), added: false };
  }
  const entry: SavedPositionBookmark = {
    ...item,
    id,
    createdAt: Date.now(),
  };
  return { next: [entry, ...list].slice(0, 120), added: true };
}
