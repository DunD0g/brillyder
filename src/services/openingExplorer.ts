export interface ExplorerMoveStat {
  uci: string;
  san: string;
  white: number;
  draws: number;
  black: number;
  games: number;
}

export interface ExplorerPosition {
  fen: string;
  white: number;
  draws: number;
  black: number;
  games: number;
  moves: ExplorerMoveStat[];
  opening: { eco: string; name: string } | null;
  source: 'lichess';
}

export interface ExplorerQueryOptions {
  ratingBand?: number;
  ratings?: number[];
  speeds?: string[];
  moves?: number;
}

interface RawExplorerMove {
  uci?: string;
  san?: string;
  white?: number;
  draws?: number;
  black?: number;
}

interface RawExplorerResponse {
  white?: number;
  draws?: number;
  black?: number;
  moves?: RawExplorerMove[];
  opening?: { eco?: string; name?: string } | null;
}

interface CacheEntry {
  data: ExplorerPosition | null;
  at: number;
}

const EXPLORER_URL = 'https://explorer.lichess.ovh/lichess';
const LICHESS_BRACKETS = [400, 1000, 1200, 1400, 1600, 1800, 2000, 2200, 2500];
const CACHE_MS = 15 * 60_000;
const FAILURE_TTL_MS = 3 * 60_000;
const REQUEST_TIMEOUT_MS = 6_500;
const MAX_CACHE_ENTRIES = 200;

const cache = new Map<string, CacheEntry>();
let disabledUntil = 0;

export function ratingsForBand(ratingBand?: number): number[] {
  if (!ratingBand || !Number.isFinite(ratingBand)) {
    return [1200, 1400, 1600, 1800, 2000];
  }
  const nearest = LICHESS_BRACKETS.reduce((best, cur) =>
    Math.abs(cur - ratingBand) < Math.abs(best - ratingBand) ? cur : best
  );
  const idx = LICHESS_BRACKETS.indexOf(nearest);
  const brackets = [LICHESS_BRACKETS[Math.max(0, idx - 1)], nearest, LICHESS_BRACKETS[Math.min(LICHESS_BRACKETS.length - 1, idx + 1)]];
  return Array.from(new Set(brackets));
}

function normalise(raw: RawExplorerResponse, fen: string): ExplorerPosition | null {
  const moves: ExplorerMoveStat[] = (raw.moves ?? [])
    .map((move) => {
      const white = Math.max(0, move.white ?? 0);
      const draws = Math.max(0, move.draws ?? 0);
      const black = Math.max(0, move.black ?? 0);
      return {
        uci: move.uci ?? '',
        san: move.san ?? '',
        white,
        draws,
        black,
        games: white + draws + black,
      };
    })
    .filter((move) => move.uci && move.san && move.games > 0)
    .sort((a, b) => b.games - a.games);

  const white = Math.max(0, raw.white ?? 0);
  const draws = Math.max(0, raw.draws ?? 0);
  const black = Math.max(0, raw.black ?? 0);
  const games = white + draws + black;
  if (games <= 0 || moves.length === 0) return null;

  return {
    fen,
    white,
    draws,
    black,
    games,
    moves,
    opening: raw.opening?.name ? { eco: raw.opening.eco ?? '', name: raw.opening.name } : null,
    source: 'lichess',
  };
}

/**
 * Community move statistics from the Lichess opening explorer filtered by
 * rating bracket & time control. Falls back gracefully when offline/rate-limited.
 */
export async function fetchLichessExplorer(
  fen: string,
  options: ExplorerQueryOptions = {}
): Promise<ExplorerPosition | null> {
  const ratings = ((options.ratings && options.ratings.length > 0)
    ? options.ratings
    : ratingsForBand(options.ratingBand)).slice().sort((a, b) => a - b);
  const speeds = ((options.speeds && options.speeds.length > 0)
    ? options.speeds
    : ['blitz', 'rapid', 'classical']).slice().sort();
  const movesLimit = options.moves ?? 10;

  const fenKey = fen.split(' ').slice(0, 4).join(' ');
  const cacheKey = `${fenKey}|r:${ratings.join(',')}|s:${speeds.join(',')}|m:${movesLimit}`;
  const now = Date.now();
  const cached = cache.get(cacheKey);
  if (cached && now - cached.at < CACHE_MS) return cached.data;
  if (now < disabledUntil) return null;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const params = new URLSearchParams({
      variant: 'standard',
      speeds: speeds.join(','),
      ratings: ratings.join(','),
      moves: String(movesLimit),
      topGames: '0',
      recentGames: '0',
      fen,
    });
    const res = await fetch(`${EXPLORER_URL}?${params.toString()}`, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    });
    if (res.status === 401 || res.status === 429 || res.status >= 500) {
      disabledUntil = Date.now() + (res.status === 401 ? 15 * 60_000 : FAILURE_TTL_MS);
      return null;
    }
    if (!res.ok) return null;
    const data = normalise((await res.json()) as RawExplorerResponse, fen);
    if (cache.size >= MAX_CACHE_ENTRIES) {
      const oldest = cache.keys().next().value;
      if (oldest) cache.delete(oldest);
    }
    cache.set(cacheKey, { data, at: now });
    return data;
  } catch {
    // Transient network error — short backoff only, never poison cache for 15 minutes
    disabledUntil = Date.now() + FAILURE_TTL_MS;
    return null;
  } finally {
    clearTimeout(timer);
  }
}

export function resetExplorerBackoff(): void {
  disabledUntil = 0;
}
