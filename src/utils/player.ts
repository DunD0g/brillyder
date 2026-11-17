import type { LichessGameRecord, PlayerColor } from '../types/chess';

export function resolveUserColor(game: LichessGameRecord, username: string): PlayerColor {
  if (game.userColor) return game.userColor;
  const low = username.trim().toLowerCase();
  if (low && game.black.name.toLowerCase() === low) return 'b';
  return 'w';
}

export function isUserGame(game: LichessGameRecord, username: string): boolean {
  const low = username.trim().toLowerCase();
  if (!low) return false;
  return game.white.name.toLowerCase() === low || game.black.name.toLowerCase() === low;
}

export function resultForUser(game: LichessGameRecord, color: PlayerColor): 'W' | 'D' | 'L' {
  const res = game.resultString;
  if (res === '1/2-1/2' || res === '*') return 'D';
  const won = (color === 'w' && res === '1-0') || (color === 'b' && res === '0-1');
  return won ? 'W' : 'L';
}
