import type { LichessGameRecord, PlayerColor } from '../types/chess';

/**
 * Resolves the user's color in a game. Always matches the active `username`
 * against white/black player names first (case-insensitive, trimmed), falling
 * back to baked-in `game.userColor` only when `username` is empty or unmatched.
 */
export function resolveUserColor(game: LichessGameRecord, username: string): PlayerColor {
  const low = username.trim().toLowerCase();
  if (low) {
    if (game.white.name.trim().toLowerCase() === low) return 'w';
    if (game.black.name.trim().toLowerCase() === low) return 'b';
  }
  if (game.userColor) return game.userColor;
  return 'w';
}

export function isUserGame(game: LichessGameRecord, username: string): boolean {
  const low = username.trim().toLowerCase();
  if (!low) return false;
  return (
    game.white.name.trim().toLowerCase() === low ||
    game.black.name.trim().toLowerCase() === low
  );
}

/**
 * Strict result for a completed game; returns `null` for unfinished/aborted `*` games
 * so they never inflate draws, reset Tilt Guard, or register as fake blown leads.
 */
export function resultForUserStrict(game: LichessGameRecord, color: PlayerColor): 'W' | 'D' | 'L' | null {
  const res = game.resultString;
  if (res === '1/2-1/2') return 'D';
  if (res === '1-0') return color === 'w' ? 'W' : 'L';
  if (res === '0-1') return color === 'b' ? 'W' : 'L';
  return null;
}

export function resultForUser(game: LichessGameRecord, color: PlayerColor): 'W' | 'D' | 'L' {
  return resultForUserStrict(game, color) ?? 'D';
}
