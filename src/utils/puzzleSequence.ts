import { Chess } from 'chess.js';
import { uciToSquares } from './chessMath';

export interface PuzzleStep {
  uci: string;
  san: string;
  from: string;
  to: string;
  promotion?: string;
  beforeFen: string;
  afterFen: string;
  isCheck: boolean;
  isCapture: boolean;
  isPromotion: boolean;
  isCheckmate: boolean;
}

const TACTICAL_MOTIF_RE =
  /fork|pin|skewer|deflection|discovered|back-rank|mate|hanging|only move|tactic|sacrifice/i;

/**
 * Builds a validated, 100%-legal multi-move puzzle sequence from a puzzle's
 * starting FEN, best move UCI, and Stockfish's best PV (SAN).
 *
 * Returns an odd-length array of plies:
 * - length 1: single-move puzzle (User 1)
 * - length 3: 2-move tactical sequence (User 1 -> Opp 1 -> User 2)
 * - length 5: forced Mate-in-3 sequence (User 1 -> Opp 1 -> User 2 -> Opp 2 -> User 3#)
 *
 * Only extends past Move 1 when the sequence is genuinely forcing (a checkmate
 * sequence or a tactical finish ending in capture/check/promotion), preventing
 * quiet positional moves from demanding arbitrary follow-up guesses.
 */
export function buildPuzzleSolutionLine(params: {
  beforeFen: string;
  bestMoveUci: string;
  bestPvSan?: string[];
  tacticalTag?: string;
}): PuzzleStep[] {
  const { beforeFen, bestMoveUci, bestPvSan = [], tacticalTag = '' } = params;
  const firstSq = uciToSquares(bestMoveUci);
  if (!firstSq) return [];

  let chess: Chess;
  try {
    chess = new Chess(beforeFen);
  } catch {
    return [];
  }

  let firstMove;
  try {
    firstMove = chess.move({
      from: firstSq.from,
      to: firstSq.to,
      promotion: firstSq.promotion,
    });
  } catch {
    return [];
  }

  const steps: PuzzleStep[] = [
    {
      uci: `${firstMove.from}${firstMove.to}${firstMove.promotion ?? ''}`,
      san: firstMove.san,
      from: firstMove.from,
      to: firstMove.to,
      promotion: firstMove.promotion,
      beforeFen,
      afterFen: chess.fen(),
      isCheck: chess.inCheck(),
      isCapture: Boolean(firstMove.captured),
      isPromotion: Boolean(firstMove.promotion),
      isCheckmate: chess.isCheckmate(),
    },
  ];

  // Move 1 already ends the game -> 1-move puzzle
  if (chess.isGameOver() || bestPvSan.length < 3) {
    return steps;
  }

  // Verify bestPvSan[0] matches Move 1 (allowing trailing +/# differences)
  const cleanSan = (s: string) => s.replace(/[+#?!]+$/g, '');
  const pvMatchesFirst = cleanSan(bestPvSan[0] ?? '') === cleanSan(firstMove.san);
  if (!pvMatchesFirst) {
    return steps;
  }

  // Replay up to 4 more plies (total 5 plies = 3 user moves)
  const candidateSteps: PuzzleStep[] = [...steps];
  for (let i = 1; i < Math.min(5, bestPvSan.length); i++) {
    if (chess.isGameOver()) break;
    const prevFen = chess.fen();
    try {
      const mv = chess.move(bestPvSan[i]);
      candidateSteps.push({
        uci: `${mv.from}${mv.to}${mv.promotion ?? ''}`,
        san: mv.san,
        from: mv.from,
        to: mv.to,
        promotion: mv.promotion,
        beforeFen: prevFen,
        afterFen: chess.fen(),
        isCheck: chess.inCheck(),
        isCapture: Boolean(mv.captured),
        isPromotion: Boolean(mv.promotion),
        isCheckmate: chess.isCheckmate(),
      });
    } catch {
      break;
    }
  }

  // Forced Mate-in-3 (5 plies ending in user checkmate)
  if (candidateSteps.length >= 5 && candidateSteps[4].isCheckmate) {
    return candidateSteps.slice(0, 5);
  }

  // Forced Mate-in-2 (3 plies ending in user checkmate)
  if (candidateSteps.length >= 3 && candidateSteps[2].isCheckmate) {
    return candidateSteps.slice(0, 3);
  }

  // 2-move forcing tactic (3 plies: User1 -> Opp1 -> User2)
  if (candidateSteps.length >= 3) {
    const u1 = candidateSteps[0];
    const u2 = candidateSteps[2];
    const openingForcing =
      u1.isCheck || u1.isCapture || u1.isPromotion || TACTICAL_MOTIF_RE.test(tacticalTag);
    const finishForcing = u2.isCheck || u2.isCapture || u2.isPromotion || u2.isCheckmate;
    if (openingForcing && finishForcing) {
      return candidateSteps.slice(0, 3);
    }
  }

  return steps;
}

/**
 * Total number of moves the user must play in a puzzle solution line (1, 2, or 3).
 */
export function userMoveCountForLine(line: PuzzleStep[]): number {
  return Math.max(1, Math.ceil(line.length / 2));
}

/**
 * Formats the solution line concisely for Reveal Solution feedback (e.g., "Qxf7+ · Kxf7 · Bc4#").
 */
export function formatSolutionLineSan(line: PuzzleStep[]): string {
  return line.map((s) => s.san).join(' → ');
}
