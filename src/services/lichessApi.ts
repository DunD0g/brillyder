import type { LichessGameRecord, PlayerColor } from '../types/chess';
import { loadPgnSafely } from '../chess/classification';
import { lookupOpeningByMoves } from '../chess/openingBook';

interface LichessRawPlayer {
  user?: { name?: string };
  rating?: number;
  ratingDiff?: number;
  aiLevel?: number;
}

interface LichessRawGame {
  id: string;
  rated?: boolean;
  variant?: string;
  speed?: string;
  perf?: string;
  createdAt?: number;
  status?: string;
  winner?: 'white' | 'black';
  pgn?: string;
  moves?: string;
  opening?: { eco?: string; name?: string; ply?: number };
  clock?: { initial?: number; increment?: number };
  players?: { white?: LichessRawPlayer; black?: LichessRawPlayer };
}

function formatTc(clock?: { initial?: number; increment?: number }, speed?: string): string {
  if (clock && typeof clock.initial === 'number') return `${Math.round(clock.initial / 60)}+${clock.increment ?? 0}`;
  return speed ? speed.charAt(0).toUpperCase() + speed.slice(1) : 'Standard';
}

function mapRawGame(raw: LichessRawGame, username?: string): LichessGameRecord | null {
  const whiteName = raw.players?.white?.user?.name || (raw.players?.white?.aiLevel ? `Stockfish L${raw.players.white.aiLevel}` : 'White');
  const blackName = raw.players?.black?.user?.name || (raw.players?.black?.aiLevel ? `Stockfish L${raw.players.black.aiLevel}` : 'Black');
  let userColor: PlayerColor | undefined;
  if (username) {
    const low = username.trim().toLowerCase();
    if (whiteName.toLowerCase() === low) userColor = 'w';
    else if (blackName.toLowerCase() === low) userColor = 'b';
  }
  const resultString: '1-0' | '0-1' | '1/2-1/2' | '*' =
    raw.winner === 'white' ? '1-0' : raw.winner === 'black' ? '0-1' : raw.status === 'draw' || raw.status === 'stalemate' ? '1/2-1/2' : '*';
  const pgn = raw.pgn || raw.moves || '';
  if (!pgn) return null;
  return {
    id: raw.id,
    source: 'lichess',
    rated: Boolean(raw.rated),
    variant: raw.variant || 'standard',
    speed: raw.speed || 'rapid',
    perf: raw.perf || raw.speed || 'rapid',
    createdAt: raw.createdAt || Date.now(),
    status: raw.status || 'finished',
    winner: raw.winner,
    resultString,
    timeControlLabel: formatTc(raw.clock, raw.speed),
    pgn,
    openingName: raw.opening?.name || 'Unknown Opening',
    openingEco: raw.opening?.eco || '',
    openingPly: raw.opening?.ply,
    white: { name: whiteName, rating: raw.players?.white?.rating, ratingDiff: raw.players?.white?.ratingDiff },
    black: { name: blackName, rating: raw.players?.black?.rating, ratingDiff: raw.players?.black?.ratingDiff },
    userColor,
    url: `https://lichess.org/${raw.id}`,
  };
}

export async function fetchLichessGames(username: string, onGame?: (g: LichessGameRecord) => void): Promise<LichessGameRecord[]> {
  const cleaned = username.trim();
  if (!cleaned) throw new Error('Enter a Lichess username.');
  const res = await fetch(
    `https://lichess.org/api/games/user/${encodeURIComponent(cleaned)}?max=15&pgnInJson=true&opening=true&clocks=true`,
    { headers: { Accept: 'application/x-ndjson' } }
  );
  if (res.status === 404) throw new Error(`Lichess user "${cleaned}" not found.`);
  if (res.status === 429) throw new Error('Lichess rate limit hit — retry in a moment.');
  if (!res.ok) throw new Error(`Lichess API error (${res.status}).`);

  const out: LichessGameRecord[] = [];
  const pushLine = (line: string) => {
    const trimmed = line.trim();
    if (!trimmed) return;
    try {
      const rec = mapRawGame(JSON.parse(trimmed) as LichessRawGame, cleaned);
      if (rec) { out.push(rec); onGame?.(rec); }
    } catch {
      // Skip invalid NDJSON line
    }
  };

  if (res.body) {
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buf = '';
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      buf += decoder.decode(value, { stream: true });
      let idx = buf.indexOf('\n');
      while (idx !== -1) {
        pushLine(buf.slice(0, idx));
        buf = buf.slice(idx + 1);
        idx = buf.indexOf('\n');
      }
    }
    pushLine(buf);
  } else {
    const txt = await res.text();
    for (const l of txt.split(/\r?\n/)) pushLine(l);
  }
  return out;
}

export function extractLichessGameId(input: string): string | null {
  const t = input.trim();
  const m = t.match(/(?:https?:\/\/)?(?:www\.)?lichess\.org\/([a-zA-Z0-9]{8})(?:[a-zA-Z0-9]{4})?(?:\/(?:white|black))?(?:[#?].*)?$/i);
  if (m) return m[1];
  return /^[a-zA-Z0-9]{8}$/.test(t) ? t : null;
}

export async function fetchLichessGameByUrlOrId(input: string, usernameHint?: string): Promise<LichessGameRecord> {
  const id = extractLichessGameId(input);
  if (!id) throw new Error('Unrecognized Lichess game URL.');
  const res = await fetch(`https://lichess.org/game/export/${id}?pgnInJson=true&opening=true&clocks=true`, { headers: { Accept: 'application/json' } });
  if (!res.ok) throw new Error(`Could not fetch game (${res.status}).`);
  const rec = mapRawGame((await res.json()) as LichessRawGame, usernameHint);
  if (!rec) throw new Error('Game contains no moves.');
  return rec;
}

export function parseRawPgnToGame(rawPgn: string, usernameHint?: string): LichessGameRecord {
  const trimmed = rawPgn.trim();
  if (!trimmed) throw new Error('Paste a PGN or Lichess URL first.');
  const chess = loadPgnSafely(trimmed);
  const history = chess.history();
  if (history.length === 0) throw new Error('No legal chess moves found in PGN.');

  const h = chess.getHeaders();
  const whiteName = h.White && h.White !== '?' ? h.White : 'White';
  const blackName = h.Black && h.Black !== '?' ? h.Black : 'Black';
  const whiteElo = h.WhiteElo ? parseInt(h.WhiteElo, 10) : undefined;
  const blackElo = h.BlackElo ? parseInt(h.BlackElo, 10) : undefined;
  const resultString: '1-0' | '0-1' | '1/2-1/2' | '*' =
    h.Result === '1-0' || h.Result === '0-1' || h.Result === '1/2-1/2' ? h.Result : '*';
  const book = lookupOpeningByMoves(history);
  let userColor: PlayerColor | undefined;
  if (usernameHint) {
    const low = usernameHint.trim().toLowerCase();
    if (whiteName.toLowerCase() === low) userColor = 'w';
    else if (blackName.toLowerCase() === low) userColor = 'b';
  }
  return {
    id: `pgn_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 6)}`,
    source: 'pgn',
    rated: false,
    variant: 'standard',
    speed: 'rapid',
    perf: 'custom',
    createdAt: Date.now(),
    status: resultString === '*' ? 'imported' : 'finished',
    winner: resultString === '1-0' ? 'white' : resultString === '0-1' ? 'black' : undefined,
    resultString,
    timeControlLabel: h.TimeControl || 'Custom',
    pgn: trimmed,
    openingName: h.Opening || book?.name || 'Custom PGN',
    openingEco: h.ECO || book?.eco || '',
    openingPly: book?.matchedPlies,
    white: { name: whiteName, rating: Number.isFinite(whiteElo) ? whiteElo : undefined },
    black: { name: blackName, rating: Number.isFinite(blackElo) ? blackElo : undefined },
    userColor,
    url: h.Site?.startsWith('https://lichess.org/') ? h.Site : undefined,
  };
}

export const SAMPLE_GAMES: LichessGameRecord[] = [
  {
    id: 'sample_london_1',
    source: 'sample',
    rated: true,
    variant: 'standard',
    speed: 'rapid',
    perf: 'rapid',
    createdAt: Date.now() - 14_400_000,
    status: 'mate',
    winner: 'white',
    resultString: '1-0',
    timeControlLabel: '10+0',
    openingName: 'London System',
    openingEco: 'D02',
    openingPly: 7,
    white: { name: 'Lukedunwell', rating: 1485 },
    black: { name: 'TacticalPanda', rating: 1492 },
    userColor: 'w',
    pgn: `[White "Lukedunwell"]
[Black "TacticalPanda"]
[Result "1-0"]
[WhiteElo "1485"]
[BlackElo "1492"]
[ECO "D02"]
[Opening "London System"]

1. d4 {[%clk 0:10:00]} d5 {[%clk 0:10:00]} 2. Bf4 {[%clk 0:09:57]} Nf6 {[%clk 0:09:56]} 3. e3 {[%clk 0:09:54]} c5 {[%clk 0:09:51]} 4. c3 {[%clk 0:09:50]} Nc6 {[%clk 0:09:46]} 5. Nd2 {[%clk 0:09:44]} Bf5 {[%clk 0:09:38]} 6. Ngf3 {[%clk 0:09:37]} e6 {[%clk 0:09:30]} 7. Qb3 {[%clk 0:09:22]} Qb6 {[%clk 0:09:15]} 8. dxc5 {[%clk 0:09:10]} Bxc5 {[%clk 0:09:07]} 9. Be2 {[%clk 0:08:58]} O-O {[%clk 0:08:55]} 10. O-O {[%clk 0:08:50]} Nh5 {[%clk 0:08:41]} 11. Bg3 {[%clk 0:08:35]} Nxg3 {[%clk 0:08:31]} 12. hxg3 {[%clk 0:08:30]} Qxb3 {[%clk 0:08:15]} 13. axb3 {[%clk 0:08:21]} a6 {[%clk 0:08:02]} 14. b4 {[%clk 0:08:08]} Bd6 {[%clk 0:07:48]} 15. Nb3 {[%clk 0:07:52]} Rfc8 {[%clk 0:07:33]} 16. Nfd4 {[%clk 0:07:36]} Nxd4 {[%clk 0:07:19]} 17. Nxd4 {[%clk 0:07:30]} Bg6 {[%clk 0:07:08]} 18. Rfd1 {[%clk 0:07:10]} Be5 {[%clk 0:06:51]} 19. b5 {[%clk 0:06:54]} axb5 {[%clk 0:06:34]} 20. Nxb5 {[%clk 0:06:45]} Kf8 {[%clk 0:06:15]} 21. Rxa8 {[%clk 0:06:28]} Rxa8 {[%clk 0:06:11]} 22. f4 {[%clk 0:06:12]} Bf6 {[%clk 0:05:54]} 23. Bf3 {[%clk 0:05:55]} Ra2 {[%clk 0:05:32]} 24. Rd2 {[%clk 0:05:40]} Ke7 {[%clk 0:05:18]} 25. Kf2 {[%clk 0:05:25]} Kd7 {[%clk 0:05:01]} 26. c4 {[%clk 0:05:06]} Kc6 {[%clk 0:04:41]} 27. cxd5+ {[%clk 0:04:51]} Kxb5 {[%clk 0:04:30]} 28. dxe6 {[%clk 0:04:38]} fxe6 {[%clk 0:04:15]} 29. Bxb7 {[%clk 0:04:22]} Rxb2 {[%clk 0:03:58]} 30. Rxb2+ {[%clk 0:04:11]} Bxb2 {[%clk 0:03:52]} 1-0`,
  },
  {
    id: 'sample_modern_2',
    source: 'sample',
    rated: true,
    variant: 'standard',
    speed: 'blitz',
    perf: 'blitz',
    createdAt: Date.now() - 86_400_000,
    status: 'resign',
    winner: 'black',
    resultString: '0-1',
    timeControlLabel: '5+3',
    openingName: 'Modern Defense: Standard',
    openingEco: 'B06',
    openingPly: 6,
    white: { name: 'ViennaAttack99', rating: 1478 },
    black: { name: 'Lukedunwell', rating: 1493 },
    userColor: 'b',
    pgn: `[White "ViennaAttack99"]
[Black "Lukedunwell"]
[Result "0-1"]
[WhiteElo "1478"]
[BlackElo "1493"]
[ECO "B06"]
[Opening "Modern Defense"]

1. e4 {[%clk 0:05:00]} g6 {[%clk 0:05:00]} 2. d4 {[%clk 0:04:58]} Bg7 {[%clk 0:04:59]} 3. Nc3 {[%clk 0:04:55]} d6 {[%clk 0:04:56]} 4. Be3 {[%clk 0:04:50]} a6 {[%clk 0:04:52]} 5. Qd2 {[%clk 0:04:46]} b5 {[%clk 0:04:48]} 6. O-O-O {[%clk 0:04:39]} Bb7 {[%clk 0:04:41]} 7. f3 {[%clk 0:04:32]} Nd7 {[%clk 0:04:35]} 8. h4 {[%clk 0:04:24]} h5 {[%clk 0:04:26]} 9. Nh3 {[%clk 0:04:15]} c5 {[%clk 0:04:19]} 10. Ng5 {[%clk 0:04:02]} cxd4 {[%clk 0:04:05]} 11. Bxd4 {[%clk 0:03:58]} Ngf6 {[%clk 0:03:59]} 12. Nd5 {[%clk 0:03:45]} Bxd5 {[%clk 0:03:48]} 13. exd5 {[%clk 0:03:41]} O-O {[%clk 0:03:40]} 14. g4 {[%clk 0:03:28]} Rc8 {[%clk 0:03:27]} 15. gxh5 {[%clk 0:03:17]} Nxh5 {[%clk 0:03:21]} 16. Bxg7 {[%clk 0:03:10]} Nxg7 {[%clk 0:03:16]} 17. Bh3 {[%clk 0:02:55]} Rc4 {[%clk 0:03:04]} 18. Bxd7 {[%clk 0:02:41]} Qxd7 {[%clk 0:02:58]} 19. Ne4 {[%clk 0:02:32]} Qf5 {[%clk 0:02:44]} 20. Qd3 {[%clk 0:02:19]} Rfc8 {[%clk 0:02:36]} 21. Rd2 {[%clk 0:02:04]} Nh5 {[%clk 0:02:23]} 22. b3 {[%clk 0:01:49]} R4c7 {[%clk 0:02:12]} 23. Kb1 {[%clk 0:01:36]} Nf4 {[%clk 0:01:59]} 24. Qe3 {[%clk 0:01:22]} Nxd5 {[%clk 0:01:48]} 25. Rxd5 {[%clk 0:01:12]} Qxd5 {[%clk 0:01:42]} 0-1`,
  },
];
