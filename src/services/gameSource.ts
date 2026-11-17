import type { AnalyzedGame, GamePlatform, LichessGameRecord } from '../types/chess';
import { fetchChessComGames } from './chessComApi';
import { fetchLichessGames } from './lichessApi';

export const PLATFORM_META: Record<GamePlatform, { id: GamePlatform; label: string; short: string; color: string }> = {
  lichess: { id: 'lichess', label: 'Lichess', short: 'Li', color: '#22d3ee' },
  chesscom: { id: 'chesscom', label: 'Chess.com', short: 'Cc', color: '#34d399' },
};

export function platformLabel(platform: GamePlatform): string {
  return platform === 'chesscom' ? 'Chess.com' : 'Lichess';
}

export function fetchGamesForPlatform(
  platform: GamePlatform,
  username: string,
  onGame?: (game: LichessGameRecord) => void,
  maxGames = 15
): Promise<LichessGameRecord[]> {
  return platform === 'chesscom'
    ? fetchChessComGames(username, onGame, maxGames)
    : fetchLichessGames(username, onGame, maxGames);
}

export function scopeGamesForPlatform(games: LichessGameRecord[], platform: GamePlatform): LichessGameRecord[] {
  return games.filter((game) => {
    if (game.source === 'chesscom') return platform === 'chesscom';
    if (game.source === 'pgn') {
      const isChessComUrl = Boolean(game.url?.includes('chess.com'));
      return platform === 'chesscom' ? isChessComUrl : !isChessComUrl;
    }
    return platform === 'lichess';
  });
}

export function scopeAnalyzedGamesForPlatform(games: AnalyzedGame[], platform: GamePlatform): AnalyzedGame[] {
  const allowed = new Set(scopeGamesForPlatform(games.map((g) => g.game), platform).map((g) => g.id));
  return games.filter((g) => allowed.has(g.game.id));
}
