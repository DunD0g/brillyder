import { Chess, type PieceSymbol, type Square } from 'chess.js';
import type { MistakePuzzle, PlayerColor } from '../types/chess';
import type { WoodpeckerCycleRecord } from '../types/openings';
import { uciToSquares } from '../utils/chessMath';

const PIECE_VAL: Record<PieceSymbol, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 100 };

export const MAX_WOODPECKER_CYCLES = 7;
export const CONSOLIDATION_COOLDOWN_MS = 24 * 60 * 60 * 1000; // 24h recommended minimum (24-48h window)

export interface RadarPingResult {
  targetSquares: Square[];
  primarySquare: Square | null;
  prompt: string;
}

/**
 * Computes the squares/pieces the opponent is immediately threatening in `beforeFen`
 * so the 2-second "Radar Ping" pre-step can verify Checks-Captures-Threats awareness.
 */
export function findRadarPingTargets(
  beforeFen: string,
  moverColor: PlayerColor,
  bestMoveUci?: string,
  threatMoveUci?: string
): RadarPingResult {
  const targets = new Set<Square>();
  const oppColor: PlayerColor = moverColor === 'w' ? 'b' : 'w';

  try {
    const chess = new Chess(beforeFen);

    // 1. Direct hanging or favorably attacked friendly pieces
    for (const row of chess.board()) {
      for (const cell of row) {
        if (!cell || cell.color !== moverColor) continue;
        if (cell.type === 'k' && chess.inCheck()) {
          targets.add(cell.square);
          continue;
        }
        if (cell.type === 'k') continue;
        const attackers = chess.attackers(cell.square, oppColor);
        if (attackers.length === 0) continue;
        const defenders = chess.attackers(cell.square, moverColor);
        let minAtt = 999;
        for (const aSq of attackers) {
          const p = chess.get(aSq);
          if (p && PIECE_VAL[p.type] < minAtt) minAtt = PIECE_VAL[p.type];
        }
        if (defenders.length === 0 || minAtt < PIECE_VAL[cell.type]) {
          targets.add(cell.square);
        }
      }
    }

    // 2. If a known threat UCI exists, add its target square
    if (threatMoveUci) {
      const parsed = uciToSquares(threatMoveUci);
      if (parsed) targets.add(parsed.to);
    }

    // 3. Also accept the key tactical square of the best move if it captures/checks
    if (targets.size === 0 && bestMoveUci) {
      const parsed = uciToSquares(bestMoveUci);
      if (parsed) {
        const pieceAtTo = chess.get(parsed.to);
        if (pieceAtTo && pieceAtTo.color === oppColor) {
          targets.add(parsed.to);
        } else {
          targets.add(parsed.from);
        }
      }
    }
  } catch {
    // ignore invalid FEN
  }

  const list = Array.from(targets);
  const primary = list[0] ?? null;
  const prompt = primary
    ? 'Tap the piece or square under immediate threat (or the key tactical target).'
    : 'Scan checks, captures, and threats, then tap any key square to proceed.';

  return { targetSquares: list, primarySquare: primary, prompt };
}

/**
 * Evaluates centipawn swing magnitude (in pawns) from the mover's perspective.
 */
export function puzzleEvalSwingPawns(puzzle: MistakePuzzle): number {
  const sign = puzzle.color === 'w' ? 1 : -1;
  const beforeCp = Math.max(-1000, Math.min(1000, puzzle.evalBefore.cpWhite * sign));
  const afterCp = Math.max(-1000, Math.min(1000, puzzle.evalAfter.cpWhite * sign));
  const cpSwing = Math.max(0, (beforeCp - afterCp) / 100);
  const mateFlip =
    (puzzle.evalBefore.mateWhite !== null && puzzle.evalAfter.mateWhite === null) ||
    (puzzle.evalBefore.mateWhite === null && puzzle.evalAfter.mateWhite !== null);
  return mateFlip ? Math.max(cpSwing, 4.0) : Number(cpSwing.toFixed(2));
}

/**
 * Filters a user's mistake deck to solvable Woodpecker puzzles:
 * - Eval swing >= 1.5 pawns (or winLoss >= 18%)
 * - Excludes obscure engine-only quiet inaccuracies (classification must be mistake/blunder)
 * - Prioritizes forcing tactics (captures, checks, promotions, clear hanging pieces)
 */
export function selectSolvableWoodpeckerPuzzles(
  deck: MistakePuzzle[],
  batchSize: 30 | 50 | 100
): MistakePuzzle[] {
  const scored: Array<{ puzzle: MistakePuzzle; score: number }> = [];

  for (const p of deck) {
    if (p.classification !== 'blunder' && p.classification !== 'mistake') continue;
    const swing = puzzleEvalSwingPawns(p);
    if (swing < 1.5 && p.winLoss < 18) continue;

    // Exclude obscure deep-only quiet moves when swing is borderline (< 2.2 pawns)
    const isForcingBest = /[x+#=]/.test(p.bestMoveSan);
    const isConcreteTag = /Hanging|Fork|Mate|Back Rank|Capture|Pin|Skewer|King Safety|Only Move/i.test(p.tacticalTag);
    if (swing < 2.2 && !isForcingBest && !isConcreteTag) continue;

    const forcingBonus = isForcingBest ? 2.5 : 0;
    const tagBonus = isConcreteTag ? 1.8 : 0;
    const blunderBonus = p.classification === 'blunder' ? 2.0 : 0;
    scored.push({ puzzle: p, score: swing + forcingBonus + tagBonus + blunderBonus });
  }

  // Fallback: if strict filter yields fewer than 5 puzzles, include all mistakes/blunders sorted by winLoss
  if (scored.length < Math.min(5, deck.length)) {
    return [...deck]
      .sort((a, b) => b.winLoss - a.winLoss || b.playedAt - a.playedAt)
      .slice(0, batchSize);
  }

  return scored
    .sort((a, b) => b.score - a.score || b.puzzle.playedAt - a.puzzle.playedAt)
    .slice(0, batchSize)
    .map((s) => s.puzzle);
}

export function createFrozenWoodpeckerCycle(
  deck: MistakePuzzle[],
  batchSize: 30 | 50 | 100,
  nowMs = Date.now()
): WoodpeckerCycleRecord {
  const chosen = selectSolvableWoodpeckerPuzzles(deck, batchSize);
  return {
    id: `wp-${batchSize}-${nowMs.toString(36)}`,
    createdAt: nowMs,
    batchSize,
    puzzleIds: chosen.map((p) => p.id),
    currentCycle: 1,
    activeIndex: 0,
    activeStartedAt: null,
    activeAttemptedIds: {},
    completedCycles: [],
    cooldownUntil: null,
  };
}

export function recordWoodpeckerPuzzleOutcome(
  cycle: WoodpeckerCycleRecord,
  puzzleId: string,
  outcome: { wrongMoves: number; hintsUsed: number; solved: boolean },
  nowMs = Date.now()
): { updated: WoodpeckerCycleRecord; cycleJustCompleted: boolean } {
  const startedAt = cycle.activeStartedAt ?? nowMs;
  const firstTry = outcome.solved && outcome.wrongMoves === 0 && outcome.hintsUsed === 0;
  const nextAttempted: WoodpeckerCycleRecord['activeAttemptedIds'] = {
    ...cycle.activeAttemptedIds,
    [puzzleId]: {
      firstTry,
      wrongMoves: outcome.wrongMoves,
      hintsUsed: outcome.hintsUsed,
      solved: outcome.solved,
    },
  };

  const totalCount = cycle.puzzleIds.length;
  const completedCount = Object.keys(nextAttempted).length;
  const allDone = totalCount > 0 && completedCount >= totalCount;

  if (!allDone) {
    const nextIdx = cycle.puzzleIds.findIndex((id) => !(id in nextAttempted));
    return {
      updated: {
        ...cycle,
        activeStartedAt: startedAt,
        activeAttemptedIds: nextAttempted,
        activeIndex: nextIdx === -1 ? Math.min(totalCount - 1, cycle.activeIndex + 1) : nextIdx,
      },
      cycleJustCompleted: false,
    };
  }

  // Entire frozen cycle completed!
  const records = Object.values(nextAttempted);
  const solvedCount = records.filter((r) => r.solved).length;
  const firstTryCount = records.filter((r) => r.firstTry).length;
  const elapsedSeconds = Math.max(1, Math.round((nowMs - startedAt) / 1000));
  const accuracyPct = Math.round((solvedCount / totalCount) * 100);
  const firstTryPct = Math.round((firstTryCount / totalCount) * 100);

  const summary = {
    cycleNumber: cycle.currentCycle,
    completedAt: nowMs,
    elapsedSeconds,
    accuracyPct,
    firstTryPct,
    solvedCount,
    totalCount,
  };

  const hasMoreCycles = cycle.currentCycle < MAX_WOODPECKER_CYCLES;
  return {
    updated: {
      ...cycle,
      completedCycles: [...cycle.completedCycles, summary],
      currentCycle: hasMoreCycles ? cycle.currentCycle + 1 : cycle.currentCycle,
      activeIndex: 0,
      activeStartedAt: null,
      activeAttemptedIds: {},
      cooldownUntil: hasMoreCycles ? nowMs + CONSOLIDATION_COOLDOWN_MS : null,
    },
    cycleJustCompleted: true,
  };
}

export function startNextWoodpeckerCycle(
  cycle: WoodpeckerCycleRecord,
  nowMs = Date.now()
): WoodpeckerCycleRecord {
  return {
    ...cycle,
    activeIndex: 0,
    activeStartedAt: nowMs,
    activeAttemptedIds: {},
    cooldownUntil: null,
  };
}

export function getCooldownRemainingMs(cycle: WoodpeckerCycleRecord, nowMs = Date.now()): number {
  if (!cycle.cooldownUntil) return 0;
  return Math.max(0, cycle.cooldownUntil - nowMs);
}

export function formatDurationShort(seconds: number): string {
  const s = Math.max(0, Math.round(seconds));
  const m = Math.floor(s / 60);
  const rem = s % 60;
  if (m === 0) return `${rem}s`;
  return `${m}m ${String(rem).padStart(2, '0')}s`;
}

export function formatCooldownLabel(ms: number): string {
  const totalMins = Math.ceil(ms / 60_000);
  const hrs = Math.floor(totalMins / 60);
  const mins = totalMins % 60;
  if (hrs > 0) return `${hrs}h ${mins}m`;
  return `${mins}m`;
}
