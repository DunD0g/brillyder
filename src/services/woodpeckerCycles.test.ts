import { describe, expect, it } from 'vitest';
import type { MistakePuzzle } from '../types/chess';
import { buildEngineScore } from '../utils/chessMath';
import {
  CONSOLIDATION_COOLDOWN_MS,
  createFrozenWoodpeckerCycle,
  findRadarPingTargets,
  getCooldownRemainingMs,
  recordWoodpeckerPuzzleOutcome,
  selectSolvableWoodpeckerPuzzles,
  startNextWoodpeckerCycle,
} from './woodpeckerCycles';

function makePuzzle(id: string, overrides: Partial<MistakePuzzle> = {}): MistakePuzzle {
  return {
    id,
    gameId: 'g1',
    ply: 15,
    moveNumber: 8,
    color: 'w',
    beforeFen: 'r1bqkbnr/pppp1ppp/2n5/4p3/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 0 3',
    afterFen: 'r1bqkbnr/pppp1ppp/2n5/4p3/3P4/2N2N2/PPP1PPPP/R1BQKB1R b KQkq - 1 3',
    san: 'Nc3',
    bestMoveSan: 'dxe5',
    bestMoveUci: 'd4e5',
    classification: 'blunder',
    phase: 'middlegame',
    tacticalTag: 'Hanging Piece',
    headline: 'Missed free pawn',
    openingName: 'London System',
    openingEco: 'D02',
    playerName: 'Hero',
    opponentName: 'Villain',
    playedAt: Date.now(),
    evalBefore: buildEngineScore(260, null),
    evalAfter: buildEngineScore(-40, null),
    winLoss: 34,
    ...overrides,
  };
}

describe('woodpeckerCycles', () => {
  it('filters to solvable puzzles (eval swing >= 1.5) and progresses Cycles #1 -> #2 with 24h cooldown', () => {
    const t0 = 1_700_000_000_000;
    const deck = [
      makePuzzle('p1', { playedAt: t0, evalBefore: buildEngineScore(360, null), evalAfter: buildEngineScore(-40, null), winLoss: 34 }),
      makePuzzle('p2', { playedAt: t0 - 1000, evalBefore: buildEngineScore(300, null), evalAfter: buildEngineScore(0, null), winLoss: 30 }),
      makePuzzle('p3', { playedAt: t0 - 2000 }),
      makePuzzle('p4', { playedAt: t0 - 3000 }),
      makePuzzle('p5', { playedAt: t0 - 4000 }),
      makePuzzle('p-tiny', {
        playedAt: t0,
        classification: 'inaccuracy',
        evalBefore: buildEngineScore(60, null),
        evalAfter: buildEngineScore(10, null),
        winLoss: 5,
        bestMoveSan: 'h3',
        tacticalTag: 'Suboptimal',
      }),
    ];

    const selected = selectSolvableWoodpeckerPuzzles(deck, 30);
    expect(selected.map((p) => p.id)).toContain('p1');
    expect(selected.map((p) => p.id)).toContain('p2');
    expect(selected.map((p) => p.id)).not.toContain('p-tiny');

    const cycle = createFrozenWoodpeckerCycle([deck[0], deck[1]], 30, t0);
    expect(cycle.currentCycle).toBe(1);
    expect(cycle.puzzleIds).toEqual(['p1', 'p2']);

    // Puzzle 1: first-try hit (0 wrong, 0 hints)
    const step1 = recordWoodpeckerPuzzleOutcome(cycle, 'p1', { solved: true, wrongMoves: 0, hintsUsed: 0 }, t0 + 10_000);
    expect(step1.cycleJustCompleted).toBe(false);

    // Puzzle 2: solved with 1 wrong move -> counts as solved but NOT first-try!
    const step2 = recordWoodpeckerPuzzleOutcome(step1.updated, 'p2', { solved: true, wrongMoves: 1, hintsUsed: 0 }, t0 + 35_000);
    expect(step2.cycleJustCompleted).toBe(true);
    expect(step2.updated.currentCycle).toBe(2);
    expect(step2.updated.completedCycles).toHaveLength(1);
    expect(step2.updated.completedCycles[0].accuracyPct).toBe(100);
    expect(step2.updated.completedCycles[0].firstTryPct).toBe(50);
    expect(getCooldownRemainingMs(step2.updated, t0 + 35_000)).toBe(CONSOLIDATION_COOLDOWN_MS);

    // Override cooldown to start Cycle #2
    const resumed = startNextWoodpeckerCycle(step2.updated, t0 + 40_000);
    expect(getCooldownRemainingMs(resumed, t0 + 40_000)).toBe(0);
    expect(resumed.activeStartedAt).toBe(t0 + 40_000);
  });

  it('detects threatened friendly squares for Radar Ping pre-step', () => {
    // White knight on c3 attacked by undefended/lower value or hanging queen on d4 attacked by c6 knight
    const fen = 'r1bqkbnr/pppp1ppp/2n5/8/3Q4/8/PPP1PPPP/RNB1KBNR w KQkq - 0 4';
    const ping = findRadarPingTargets(fen, 'w', 'd4a4');
    expect(ping.targetSquares).toContain('d4');
  });
});
