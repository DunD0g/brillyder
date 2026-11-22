import { countTotalPieces } from '../utils/chessMath';

export interface TablebaseMove {
  uci: string;
  san: string;
  /** Outcome category from the MOVER's perspective (inverted from Lichess's opponent-to-move raw field). */
  category: string;
  dtz: number | null;
  dtm: number | null;
  zeroing: boolean;
}

export interface TablebaseResult {
  fen: string;
  category: string;
  dtz: number | null;
  dtm: number | null;
  checkmate: boolean;
  stalemate: boolean;
  moves: TablebaseMove[];
}

interface RawTbMove {
  uci?: string;
  san?: string;
  category?: string;
  dtz?: number | null;
  dtm?: number | null;
  zeroing?: boolean;
}

interface RawTbResponse {
  category?: string;
  dtz?: number | null;
  dtm?: number | null;
  checkmate?: boolean;
  stalemate?: boolean;
  moves?: RawTbMove[];
}

const TABLEBASE_URL = 'https://tablebase.lichess.ovh/standard';
const CACHE_MS = 30 * 60_000;
const FAILURE_TTL_MS = 3 * 60_000;
const TIMEOUT_MS = 5_500;
const MAX_CACHE_ENTRIES = 160;

const cache = new Map<string, { data: TablebaseResult; at: number }>();
let disabledUntil = 0;

export function isTablebaseEligible(fen: string): boolean {
  const pieces = countTotalPieces(fen);
  return pieces >= 2 && pieces <= 7;
}

/**
 * Lichess's Syzygy API returns each candidate `moves[]` item's `category` from the
 * OPPONENT's perspective after that move is played (`loss` = opponent loses = winning move
 * for the side to move!). Invert so UI badges accurately show `(win)` for winning moves
 * and `(loss)` for losing blunders.
 */
export function invertTablebaseMoveCategory(rawOpponentCategory: string): string {
  switch (rawOpponentCategory) {
    case 'win':
      return 'loss';
    case 'loss':
      return 'win';
    case 'maybe-win':
      return 'maybe-loss';
    case 'maybe-loss':
      return 'maybe-win';
    case 'cursed-win':
      return 'blessed-loss';
    case 'blessed-loss':
      return 'cursed-win';
    default:
      return rawOpponentCategory;
  }
}

export function formatTablebaseWdl(category: string, sideToMove: 'w' | 'b'): {
  label: string;
  tone: 'win' | 'draw' | 'loss';
} {
  const sideLabel = sideToMove === 'w' ? 'White' : 'Black';
  const oppLabel = sideToMove === 'w' ? 'Black' : 'White';
  switch (category) {
    case 'win':
    case 'maybe-win':
      return { label: `${sideLabel} Wins (Syzygy)`, tone: 'win' };
    case 'cursed-win':
      return { label: `${sideLabel} Cursed Win (50-move draw)`, tone: 'draw' };
    case 'draw':
      return { label: 'Exact Draw (Syzygy)', tone: 'draw' };
    case 'blessed-loss':
      return { label: `Blessed Loss (${sideLabel} holds 50-move)`, tone: 'draw' };
    case 'loss':
    case 'maybe-loss':
      return { label: `${oppLabel} Wins (Syzygy)`, tone: 'loss' };
    default:
      return { label: category, tone: 'draw' };
  }
}

export async function fetchLichessTablebase(fen: string): Promise<TablebaseResult | null> {
  if (!isTablebaseEligible(fen)) return null;
  // Preserve 5th field (halfmove clock) since 50-move distance changes cursed-win/blessed-loss WDL
  const key = fen.split(' ').slice(0, 5).join(' ');
  const now = Date.now();
  const cached = cache.get(key);
  if (cached && now - cached.at < CACHE_MS) return cached.data;
  if (now < disabledUntil) return null;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const url = `${TABLEBASE_URL}?fen=${encodeURIComponent(fen)}`;
    const res = await fetch(url, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    });
    if (res.status === 429 || res.status >= 500) {
      disabledUntil = Date.now() + FAILURE_TTL_MS;
      return null;
    }
    if (!res.ok) return null;
    const raw = (await res.json()) as RawTbResponse;
    if (!raw.category || raw.category === 'unknown') return null;
    const result: TablebaseResult = {
      fen,
      category: raw.category,
      dtz: raw.dtz ?? null,
      dtm: raw.dtm ?? null,
      checkmate: Boolean(raw.checkmate),
      stalemate: Boolean(raw.stalemate),
      moves: (raw.moves ?? [])
        .filter((m): m is Required<Pick<RawTbMove, 'uci' | 'san' | 'category'>> & RawTbMove =>
          Boolean(m.uci && m.san && m.category && m.category !== 'unknown')
        )
        .slice(0, 6)
        .map((m) => ({
          uci: m.uci,
          san: m.san,
          category: invertTablebaseMoveCategory(m.category),
          dtz: m.dtz ?? null,
          dtm: m.dtm ?? null,
          zeroing: Boolean(m.zeroing),
        })),
    };
    if (cache.size >= MAX_CACHE_ENTRIES) {
      const oldest = cache.keys().next().value;
      if (oldest) cache.delete(oldest);
    }
    cache.set(key, { data: result, at: now });
    return result;
  } catch {
    // Transient network error — use short backoff without poisoning cache for 30 min
    disabledUntil = Date.now() + FAILURE_TTL_MS;
    return null;
  } finally {
    clearTimeout(timer);
  }
}
