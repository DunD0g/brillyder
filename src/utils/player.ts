import type { GamePlatform, LichessGameRecord, PlayerColor } from '../types/chess';

export type UserHandleMap = Partial<Record<GamePlatform, string>>;
export type UserHandleSpec = string | UserHandleMap;

function candidateHandlesForGame(game: LichessGameRecord, user: UserHandleSpec): string[] {
  if (typeof user === 'string') {
    const trimmed = user.trim().toLowerCase();
    return trimmed ? [trimmed] : [];
  }
  const isChessCom =
    game.source === 'chesscom' ||
    (game.source === 'pgn' && Boolean(game.url?.includes('chess.com')));
  const primary = (isChessCom ? user.chesscom : user.lichess)?.trim().toLowerCase() ?? '';
  const secondary = (isChessCom ? user.lichess : user.chesscom)?.trim().toLowerCase() ?? '';
  const handles: string[] = [];
  if (primary) handles.push(primary);
  if (secondary && secondary !== primary) handles.push(secondary);
  return handles;
}

/**
 * Resolves the user's color in a game. Always matches the platform-appropriate
 * handle (or single username string) against white/black player names first
 * (case-insensitive, trimmed), falling back to baked-in `game.userColor` only
 * when unmatched.
 */
export function resolveUserColor(game: LichessGameRecord, user: UserHandleSpec): PlayerColor {
  const white = game.white.name.trim().toLowerCase();
  const black = game.black.name.trim().toLowerCase();
  for (const handle of candidateHandlesForGame(game, user)) {
    if (white === handle) return 'w';
    if (black === handle) return 'b';
  }
  if (game.userColor) return game.userColor;
  return 'w';
}

export function isUserGame(game: LichessGameRecord, user: UserHandleSpec): boolean {
  const white = game.white.name.trim().toLowerCase();
  const black = game.black.name.trim().toLowerCase();
  for (const handle of candidateHandlesForGame(game, user)) {
    if (white === handle || black === handle) return true;
  }
  return false;
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
