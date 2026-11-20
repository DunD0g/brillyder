import { Chess, type Color, type PieceSymbol, type Square } from 'chess.js';
import type { EngineScore, PlayerColor } from '../types/chess';

const PIECE_VALUES: Record<PieceSymbol, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };

export function clamp(val: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, val));
}

export function cpToWinPercent(cp: number): number {
  const clampedCp = clamp(cp, -2500, 2500);
  return 50 + 50 * (2 / (1 + Math.exp(-0.00368208 * clampedCp)) - 1);
}

export function buildEngineScore(
  cpWhite: number,
  mateWhite: number | null,
  isCheckmate = false,
  winnerColor?: PlayerColor
): EngineScore {
  if (isCheckmate && winnerColor) {
    const isWhiteWin = winnerColor === 'w';
    return {
      cpWhite: isWhiteWin ? 10000 : -10000,
      mateWhite: 0,
      isCheckmate: true,
      winPercentWhite: isWhiteWin ? 100 : 0,
      display: '#',
    };
  }
  if (mateWhite !== null) {
    const isWhiteWin = mateWhite > 0;
    const absMate = Math.abs(mateWhite);
    return {
      cpWhite: isWhiteWin ? 10000 - absMate * 50 : -10000 + absMate * 50,
      mateWhite,
      winPercentWhite: isWhiteWin ? 100 : 0,
      display: `${isWhiteWin ? '' : '-'}M${absMate}`,
    };
  }
  const winPercentWhite = cpToWinPercent(cpWhite);
  const pawns = cpWhite / 100;
  const absPawns = Math.abs(pawns);
  const formatted = absPawns >= 10 ? `${pawns >= 0 ? '+' : '-'}${Math.round(absPawns)}` : `${pawns >= 0 ? '+' : ''}${pawns.toFixed(1)}`;
  return {
    cpWhite,
    mateWhite: null,
    winPercentWhite,
    display: Math.abs(cpWhite) < 8 ? '0.0' : formatted,
  };
}

export function getMoverWinPercent(score: EngineScore, mover: PlayerColor): number {
  return mover === 'w' ? score.winPercentWhite : 100 - score.winPercentWhite;
}

export function calculateMoveAccuracy(winLoss: number): number {
  if (winLoss <= 0.1) return 100;
  const raw = 103.1668 * Math.exp(-0.04354 * winLoss) - 3.1669;
  return clamp(Number(raw.toFixed(1)), 0, 100);
}

export function calculateGameAccuracy(moveAccuracies: number[], winPercents: number[]): number {
  if (moveAccuracies.length === 0) return 100;
  let weightedSum = 0;
  let weightTotal = 0;
  let harmonicDenom = 0;
  for (let i = 0; i < moveAccuracies.length; i++) {
    const acc = moveAccuracies[i];
    const wp = winPercents[i] ?? 50;
    const weight = 0.5 + 0.5 * (1 - Math.abs(wp - 50) / 50);
    weightedSum += acc * weight;
    weightTotal += weight;
    harmonicDenom += 1 / Math.max(12, acc);
  }
  const wMean = weightTotal > 0 ? weightedSum / weightTotal : 100;
  const hMean = moveAccuracies.length / harmonicDenom;
  return Number(clamp(0.58 * wMean + 0.42 * hMean, 0, 100).toFixed(1));
}

export function estimateGameElo(
  playerRating: number | undefined,
  opponentRating: number | undefined,
  accuracy: number,
  resultScore: 1 | 0.5 | 0
): number {
  const anchor =
    playerRating && opponentRating
      ? (playerRating + opponentRating) / 2
      : playerRating || opponentRating || 1500;
  const baseline = clamp(56 + (anchor - 1000) * 0.018, 52, 90);
  const bonus = resultScore === 1 ? 85 : resultScore === 0.5 ? 0 : -85;
  return Math.round(clamp(anchor + (accuracy - baseline) * 19 + bonus, 400, 3100) / 10) * 10;
}

export function uciToSquares(uci: string): { from: Square; to: Square; promotion?: PieceSymbol } | null {
  if (!uci || uci.length < 4) return null;
  return {
    from: uci.slice(0, 2) as Square,
    to: uci.slice(2, 4) as Square,
    promotion: uci.length >= 5 ? (uci[4] as PieceSymbol) : undefined,
  };
}

export function uciLineToSan(fen: string, uciMoves: string[], maxMoves = 5): string[] {
  const chess = new Chess(fen);
  const out: string[] = [];
  for (const uci of uciMoves.slice(0, maxMoves)) {
    const parsed = uciToSquares(uci);
    if (!parsed) break;
    try {
      const mv = chess.move({ from: parsed.from, to: parsed.to, promotion: parsed.promotion });
      out.push(mv.san);
    } catch {
      break;
    }
  }
  return out;
}

export function countNonPawnMaterial(fen: string): number {
  const chess = new Chess(fen);
  let total = 0;
  for (const row of chess.board()) {
    for (const cell of row) {
      if (!cell || cell.type === 'p' || cell.type === 'k') continue;
      total += PIECE_VALUES[cell.type];
    }
  }
  return total;
}

export function getMaterialBalance(fen: string): {
  whiteAdvantage: number;
  capturedByWhite: PieceSymbol[];
  capturedByBlack: PieceSymbol[];
} {
  const start: Record<Exclude<PieceSymbol, 'k'>, number> = { q: 1, r: 2, b: 2, n: 2, p: 8 };
  const cur: Record<Color, Record<Exclude<PieceSymbol, 'k'>, number>> = {
    w: { q: 0, r: 0, b: 0, n: 0, p: 0 },
    b: { q: 0, r: 0, b: 0, n: 0, p: 0 },
  };
  let wPts = 0;
  let bPts = 0;
  const chess = new Chess(fen);
  for (const row of chess.board()) {
    for (const cell of row) {
      if (!cell || cell.type === 'k') continue;
      cur[cell.color][cell.type]++;
      if (cell.color === 'w') wPts += PIECE_VALUES[cell.type];
      else bPts += PIECE_VALUES[cell.type];
    }
  }
  const order: Exclude<PieceSymbol, 'k'>[] = ['q', 'r', 'b', 'n', 'p'];
  const capturedByWhite: PieceSymbol[] = [];
  const capturedByBlack: PieceSymbol[] = [];
  for (const p of order) {
    for (let i = 0; i < Math.max(0, start[p] - cur.b[p]); i++) capturedByWhite.push(p);
    for (let i = 0; i < Math.max(0, start[p] - cur.w[p]); i++) capturedByBlack.push(p);
  }
  return { whiteAdvantage: wPts - bPts, capturedByWhite, capturedByBlack };
}

export function extractClockFromComment(comment: string | undefined): string | undefined {
  if (!comment) return undefined;
  const match = comment.match(/\[%clk\s+(\d+:\d+(?::\d+(?:\.\d+)?)?)\]/);
  if (!match) return undefined;
  const parts = match[1].split(':');
  if (parts.length === 3) {
    const h = parseInt(parts[0], 10);
    const m = parseInt(parts[1], 10);
    const s = Math.floor(parseFloat(parts[2]));
    return h > 0
      ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
      : `${m}:${String(s).padStart(2, '0')}`;
  }
  return match[1];
}

export function extractClockSeconds(comment: string | undefined): number | undefined {
  if (!comment) return undefined;
  const match = comment.match(/\[%clk\s+(\d+:\d+(?::\d+(?:\.\d+)?)?)\]/);
  if (!match) return undefined;
  const parts = match[1].split(':').map((p) => parseFloat(p));
  if (parts.some((n) => !Number.isFinite(n))) return undefined;
  if (parts.length === 3) return Math.round(parts[0] * 3600 + parts[1] * 60 + parts[2]);
  if (parts.length === 2) return Math.round(parts[0] * 60 + parts[1]);
  return undefined;
}

export function parsePgnTimeControl(pgn: string): { baseSeconds: number | null; incrementSeconds: number } {
  const match = pgn.match(/\[TimeControl\s+"(\d+)(?:\+(\d+))?"\]/);
  if (!match) return { baseSeconds: null, incrementSeconds: 0 };
  const base = parseInt(match[1], 10);
  const inc = match[2] ? parseInt(match[2], 10) : 0;
  return {
    baseSeconds: Number.isFinite(base) ? base : null,
    incrementSeconds: Number.isFinite(inc) ? inc : 0,
  };
}

export function computeMoveTimeSpent(
  prevClockSeconds: number | undefined,
  currentClockSeconds: number | undefined,
  incrementSeconds = 0
): number | undefined {
  if (prevClockSeconds === undefined || currentClockSeconds === undefined) return undefined;
  const spent = prevClockSeconds - currentClockSeconds + incrementSeconds;
  return Math.max(0, Math.round(spent));
}

export function countTotalPieces(fen: string): number {
  const placement = fen.split(' ')[0] ?? '';
  let count = 0;
  for (const ch of placement) {
    if (/[pnbrqkPNBRQK]/.test(ch)) count++;
  }
  return count;
}

export function formatClockSeconds(totalSeconds: number): string {
  const s = Math.max(0, Math.round(totalSeconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`;
  return `${m}:${String(sec).padStart(2, '0')}`;
}

export function formatTimeAgo(timestampMs: number): string {
  const mins = Math.floor((Date.now() - timestampMs) / 60000);
  if (mins < 2) return 'Just now';
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  if (days < 30) return `${days}d ago`;
  return new Date(timestampMs).toLocaleDateString();
}
