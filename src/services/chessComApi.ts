import type { LichessGameRecord, PlayerColor } from '../types/chess';
import { loadPgnSafely } from '../chess/classification';
import { lookupOpeningByMoves } from '../chess/openingBook';

interface ChessComArchiveResponse {
  archives?: string[];
}

interface ChessComPlayerSide {
  username?: string;
  rating?: number;
  result?: string;
}

interface ChessComRawGame {
  url?: string;
  pgn?: string;
  time_control?: string;
  end_time?: number;
  rated?: boolean;
  time_class?: string;
  rules?: string;
  uuid?: string;
  white?: ChessComPlayerSide;
  black?: ChessComPlayerSide;
}

const CHESSCOM_API = 'https://api.chess.com/pub';

async function fetchJson<T>(url: string): Promise<T> {
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), 16000);
  try {
    const res = await fetch(url, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    });
    if (res.status === 404) throw new Error('Chess.com user not found.');
    if (res.status === 429) throw new Error('Chess.com rate limit hit — retry in a minute.');
    if (!res.ok) throw new Error(`Chess.com API error (${res.status}).`);
    return (await res.json()) as T;
  } catch (err) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      throw new Error('Chess.com request timed out.');
    }
    throw err;
  } finally {
    window.clearTimeout(timer);
  }
}

function formatTimeControl(raw: string | undefined, speed: string): string {
  if (!raw) return speed ? speed.charAt(0).toUpperCase() + speed.slice(1) : 'Standard';
  const [baseRaw, incRaw] = raw.split('+');
  const base = Number(baseRaw);
  const inc = Number(incRaw ?? 0);
  if (!Number.isFinite(base)) return raw;
  if (base < 60) return `${base}+${inc}`;
  return `${Math.round(base / 60)}+${Number.isFinite(inc) ? inc : 0}`;
}

function resultStringFor(game: ChessComRawGame): '1-0' | '0-1' | '1/2-1/2' | '*' {
  const w = game.white?.result;
  const b = game.black?.result;
  if (w === 'win') return '1-0';
  if (b === 'win') return '0-1';
  const drawCodes = new Set(['agreed', 'repetition', 'stalemate', 'insufficient', '50move', 'timevsinsufficient']);
  if ((w && drawCodes.has(w)) || (b && drawCodes.has(b))) return '1/2-1/2';
  return '*';
}

function normalizeChessComGame(raw: ChessComRawGame, username: string): LichessGameRecord | null {
  if (!raw.pgn || !raw.white?.username || !raw.black?.username) return null;
  let headers: Record<string, string> = {};
  let history: string[] = [];
  try {
    const chess = loadPgnSafely(raw.pgn);
    headers = chess.getHeaders();
    history = chess.history();
  } catch {
    return null;
  }
  if (history.length < 2) return null;

  const low = username.trim().toLowerCase();
  const whiteName = raw.white.username;
  const blackName = raw.black.username;
  let userColor: PlayerColor | undefined;
  if (whiteName.toLowerCase() === low) userColor = 'w';
  else if (blackName.toLowerCase() === low) userColor = 'b';

  const openingHeader = headers.Opening || '';
  const variationHeader = headers.Variation || '';
  const lookup = lookupOpeningByMoves(history);
  const openingName =
    openingHeader && variationHeader
      ? `${openingHeader}: ${variationHeader}`
      : openingHeader || lookup?.name || 'Unknown Opening';

  const resultString = resultStringFor(raw);
  const idFromUrl = raw.url?.split('/').filter(Boolean).pop();
  const id = raw.uuid || idFromUrl || `chesscom_${raw.end_time ?? Date.now()}`;
  const endTime = (raw.end_time ?? Math.floor(Date.now() / 1000)) * 1000;
  const speed = raw.time_class || 'rapid';
  const variant = raw.rules && raw.rules !== 'chess' ? raw.rules : 'standard';

  return {
    id: `cc_${id}`,
    source: 'chesscom',
    rated: Boolean(raw.rated),
    variant,
    speed,
    perf: speed,
    createdAt: endTime,
    status: 'finished',
    winner: resultString === '1-0' ? 'white' : resultString === '0-1' ? 'black' : undefined,
    resultString,
    timeControlLabel: formatTimeControl(raw.time_control, speed),
    pgn: raw.pgn,
    openingName,
    openingEco: headers.ECO || lookup?.eco || '',
    openingPly: lookup?.matchedPlies,
    white: { name: whiteName, rating: raw.white.rating },
    black: { name: blackName, rating: raw.black.rating },
    userColor,
    url: raw.url,
  };
}

/**
 * Fetches recent Chess.com games by walking the monthly archive list backwards
 * until enough games are collected. Uses only Chess.com's public CORS API.
 */
export async function fetchChessComGames(
  username: string,
  onGame?: (game: LichessGameRecord) => void,
  maxGames = 15
): Promise<LichessGameRecord[]> {
  const cleaned = username.trim().toLowerCase();
  if (!cleaned) throw new Error('Enter a Chess.com username.');
  const archiveRes = await fetchJson<ChessComArchiveResponse>(
    `${CHESSCOM_API}/player/${encodeURIComponent(cleaned)}/games/archives`
  );
  const archives = archiveRes.archives ?? [];
  if (archives.length === 0) throw new Error(`No public games found for "${cleaned}".`);

  const collected: ChessComRawGame[] = [];
  for (let i = archives.length - 1; i >= 0 && collected.length < maxGames; i--) {
    const month = await fetchJson<{ games?: ChessComRawGame[] }>(archives[i]);
    const games = (month.games ?? []).slice().reverse();
    collected.push(...games);
  }

  const normalized: LichessGameRecord[] = [];
  const sorted = collected.slice().sort((a, b) => (b.end_time ?? 0) - (a.end_time ?? 0));
  for (const raw of sorted) {
    if (normalized.length >= maxGames) break;
    const game = normalizeChessComGame(raw, cleaned);
    if (game) normalized.push(game);
  }

  if (normalized.length === 0) throw new Error(`No usable standard games found for "${cleaned}".`);
  if (onGame) for (const game of normalized) onGame(game);
  return normalized;
}
