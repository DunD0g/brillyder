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
const CACHE_MS = 15 * 60_000;
const FAILURE_TTL_MS = 10 * 60_000;
const REQUEST_TIMEOUT_MS = 6_000;

const cache = new Map<string, CacheEntry>();
let disabledUntil = 0;

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
 * Community move statistics from the Lichess opening explorer. The endpoint is
 * optional: when it is unavailable (offline, rate limited or blocked) the UI
 * falls back to BrillyDer's bundled theory book. Failures are remembered for a
 * while so moving around a review does not hammer the API.
 */
export async function fetchLichessExplorer(fen: string): Promise<ExplorerPosition | null> {
  const now = Date.now();
  const cached = cache.get(fen);
  if (cached && now - cached.at < CACHE_MS) return cached.data;
  if (now < disabledUntil) return null;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const params = new URLSearchParams({
      variant: 'standard',
      speeds: 'blitz,rapid,classical',
      ratings: '1200,1400,1600,1800,2000,2200',
      moves: '10',
      topGames: '0',
      recentGames: '0',
      fen,
    });
    const res = await fetch(`${EXPLORER_URL}?${params.toString()}`, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    });
    if (!res.ok) throw new Error(`Lichess explorer returned ${res.status}`);
    const data = normalise((await res.json()) as RawExplorerResponse, fen);
    cache.set(fen, { data, at: now });
    return data;
  } catch {
    disabledUntil = Date.now() + FAILURE_TTL_MS;
    cache.set(fen, { data: null, at: now });
    return null;
  } finally {
    clearTimeout(timer);
  }
}
