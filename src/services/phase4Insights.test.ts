import { describe, expect, it } from 'vitest';
import type { AnalyzedGame, AnalyzedPly, LichessGameRecord } from '../types/chess';
import {
  buildEngineScore,
  computeMoveTimeSpent,
  countTotalPieces,
  parsePgnTimeControl,
} from '../utils/chessMath';
import { computeMultiGameInsights } from './insightsAggregator';
import { buildBrillyVault } from './vault';
import { isTablebaseEligible } from './tablebaseApi';
import { encodeFenToMaiaPlanes } from '../engine/MaiaService';

function makeAnalyzedGame(
  id: string,
  createdAt: number,
  resultString: '1-0' | '0-1' | '1/2-1/2',
  plies: AnalyzedPly[],
  whiteAcc = 88,
  whiteBlunders = 0
): AnalyzedGame {
  const game: LichessGameRecord = {
    id,
    source: 'lichess',
    rated: true,
    variant: 'standard',
    speed: 'rapid',
    perf: 'rapid',
    createdAt,
    status: 'resign',
    resultString,
    timeControlLabel: '10+0',
    pgn: '[TimeControl "600+0"]\n1. d4 d5 2. Bf4 Nf6',
    openingName: 'London System',
    openingEco: 'D02',
    white: { name: 'Hero', rating: 1500 },
    black: { name: 'Rival', rating: 1500 },
    userColor: 'w',
  };
  return {
    id,
    analyzedAt: createdAt,
    depth: 14,
    game,
    initialEval: buildEngineScore(20, null),
    plies,
    whiteSummary: {
      accuracy: whiteAcc,
      estimatedElo: 1550,
      counts: { brilliant: 0, great: 0, best: 10, excellent: 0, inaccuracy: 0, mistake: 0, blunder: whiteBlunders, book: 0 },
      avgWinLoss: 2,
    },
    blackSummary: {
      accuracy: 72,
      estimatedElo: 1400,
      counts: { brilliant: 0, great: 0, best: 5, excellent: 0, inaccuracy: 0, mistake: 0, blunder: 1, book: 0 },
      avgWinLoss: 12,
    },
  };
}

function makePly(overrides: Partial<AnalyzedPly>): AnalyzedPly {
  return {
    ply: 10,
    moveNumber: 5,
    color: 'w',
    san: 'Nf3',
    uci: 'g1f3',
    from: 'g1',
    to: 'f3',
    beforeFen: 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 1',
    afterFen: 'rnbqkbnr/pppppppp/8/8/3P4/5N2/PPP1PPPP/RNBQKB1R b KQkq - 1 1',
    bestMoveUci: 'g1f3',
    bestMoveSan: 'Nf3',
    bestPvSan: ['Nf3'],
    evalBefore: buildEngineScore(30, null),
    evalAfter: buildEngineScore(30, null),
    secondBestGapWin: 4,
    winLoss: 0,
    accuracy: 98,
    classification: 'best',
    phase: 'middlegame',
    coaching: { headline: 'Best', detail: '', tacticalTag: 'Engine Top' },
    ...overrides,
  };
}

describe('Phase 4 Clock/Tilt Guard, Vault Tabs, Tablebase & Maia Planes', () => {
  it('parses PGN TimeControl increments and computes move time spent', () => {
    expect(parsePgnTimeControl('[TimeControl "600+5"]')).toEqual({ baseSeconds: 600, incrementSeconds: 5 });
    expect(computeMoveTimeSpent(300, 297, 0)).toBe(3); // 3s spent -> Impulse if blunder with >3m left!
    expect(computeMoveTimeSpent(300, 298, 2)).toBe(4);
  });

  it('computes Impulse vs Time-Trouble blunders, Tilt Guard warning, and 20-game checkpoints', () => {
    const impulsePly = makePly({
      ply: 11,
      classification: 'blunder',
      clockSeconds: 420,
      timeSpentSeconds: 2,
      clockTag: 'impulse',
      winLoss: 35,
      coaching: { headline: 'Dropped piece', detail: '', tacticalTag: 'Hanging Piece' },
    });
    const ttPly = makePly({
      ply: 31,
      classification: 'blunder',
      clockSeconds: 25,
      timeSpentSeconds: 4,
      clockTag: 'time-trouble',
      winLoss: 30,
      coaching: { headline: 'Fork', detail: '', tacticalTag: 'Fork' },
    });

    const g1 = makeAnalyzedGame('g1', 1000, '1-0', [makePly({ ply: 1 })], 89, 0);
    const g2 = makeAnalyzedGame('g2', 2000, '0-1', [impulsePly], 65, 1);
    const g3 = makeAnalyzedGame('g3', 3000, '0-1', [ttPly], 60, 1);
    const g4 = makeAnalyzedGame('g4', 4000, '0-1', [impulsePly], 62, 1);

    const insights = computeMultiGameInsights([g1, g2, g3, g4], 'Hero');
    expect(insights.clockLeaks.impulseBlunders).toBe(2);
    expect(insights.clockLeaks.timeTroubleBlunders).toBe(1);
    expect(insights.tiltGuard.activeWarning).toBe(true);
    expect(insights.tiltGuard.consecutiveLosses).toBe(3);
    expect(insights.checkpoints).not.toBeNull();
    expect(insights.checkpoints?.windowSize).toBe(2);
    expect(insights.missedMotifs.some((m) => m.motif === 'Hanging Piece')).toBe(true);
  });

  it('populates expanded Brilly Vault tabs: Clutch Saves, Traps Punished, and Clean Sweeps', () => {
    const oppBlunder = makePly({
      ply: 10,
      color: 'b',
      san: 'Nh5',
      classification: 'blunder',
      winLoss: 40,
    });
    const userPunish = makePly({
      ply: 11,
      color: 'w',
      san: 'Qxh5',
      afterFen: 'rnbqkb1r/pppppppp/8/7Q/3P4/8/PPP1PPPP/RNB1KBNR b KQkq - 0 2',
      classification: 'best',
      winLoss: 0,
      isClutchSave: true,
      secondBestGapPawns: 2.5,
      evalBefore: buildEngineScore(0, null),
    });
    const filler = Array.from({ length: 10 }, (_, i) => makePly({ ply: i + 12 }));
    const g = makeAnalyzedGame('g-clean', 5000, '1-0', [oppBlunder, userPunish, ...filler], 91, 0);

    const vault = buildBrillyVault([g], 'Hero');
    expect(vault.stats.clutchSaves).toBeGreaterThanOrEqual(1);
    expect(vault.stats.trapsPunished).toBeGreaterThanOrEqual(1);
    expect(vault.stats.cleanSweeps).toBe(1);
  });

  it('checks <=7 piece tablebase eligibility and encodes valid 112x8x8 Maia planes', () => {
    expect(countTotalPieces('8/5pk1/8/8/8/8/5PK1/3R4 w - - 0 1')).toBe(5);
    expect(isTablebaseEligible('8/5pk1/8/8/8/8/5PK1/3R4 w - - 0 1')).toBe(true);
    expect(isTablebaseEligible('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1')).toBe(false);

    const planes = encodeFenToMaiaPlanes('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
    expect(planes.length).toBe(112 * 8 * 8);
    expect(planes[111 * 64]).toBe(1);
  });
});
