import { countTotalPieces } from '../utils/chessMath';

export interface TablebaseMove {
  uci: string;
  san: string;
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

const cache = new Map<string, { data: TablebaseResult | null; at: number }>();
let disabledUntil = 0;

export function isTablebaseEligible(fen: string): boolean {
  const pieces = countTotalPieces(fen);
  return pieces >= 2 && pieces <= 7;
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
  const now = Date.now();
  const cached = cache.get(fen);
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
    if (!res.ok) throw new Error(`Tablebase HTTP ${res.status}`);
    const raw = (await res.json()) as RawTbResponse;
    if (!raw.category) return null;
    const result: TablebaseResult = {
      fen,
      category: raw.category,
      dtz: raw.dtz ?? null,
      dtm: raw.dtm ?? null,
      checkmate: Boolean(raw.checkmate),
      stalemate: Boolean(raw.stalemate),
      moves: (raw.moves ?? [])
        .filter((m): m is Required<Pick<RawTbMove, 'uci' | 'san' | 'category'>> & RawTbMove =>
          Boolean(m.uci && m.san && m.category)
        )
        .slice(0, 6)
        .map((m) => ({
          uci: m.uci,
          san: m.san,
          category: m.category,
          dtz: m.dtz ?? null,
          dtm: m.dtm ?? null,
          zeroing: Boolean(m.zeroing),
        })),
    };
    cache.set(fen, { data: result, at: now });
    return result;
  } catch {
    disabledUntil = Date.now() + FAILURE_TTL_MS;
    cache.set(fen, { data: null, at: now });
    return null;
  } finally {
    clearTimeout(timer);
  }
}
