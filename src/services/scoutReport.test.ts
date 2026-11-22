import { describe, expect, it } from 'vitest';
import type { AnalyzedGame, MultiGameInsights } from '../types/chess';
import { buildScoutGameplan } from './scoutReport';

function mockAnalyzedGame(overrides: Partial<AnalyzedGame> & { eco: string; opening: string; white: string; black: string; result: '1-0' | '0-1' | '1/2-1/2'; wAcc?: number; bAcc?: number }): AnalyzedGame {
  return {
    id: overrides.id ?? `g_${Math.random().toString(36).slice(2)}`,
    analyzedAt: Date.now(),
    depth: 14,
    game: {
      id: overrides.id ?? 'g1',
      source: 'lichess',
      rated: true,
      variant: 'standard',
      speed: 'blitz',
      perf: 'blitz',
      createdAt: Date.now(),
      status: 'mate',
      resultString: overrides.result,
      timeControlLabel: '3+2',
      pgn: '1. e4 e5 *',
      openingName: overrides.opening,
      openingEco: overrides.eco,
      white: { name: overrides.white, rating: 1500 },
      black: { name: overrides.black, rating: 1500 },
    },
    initialEval: { cpWhite: 20, mateWhite: null, winPercentWhite: 50, display: '+0.2' },
    plies: [],
    whiteSummary: {
      accuracy: overrides.wAcc ?? 80,
      estimatedElo: 1500,
      counts: { brilliant: 0, great: 0, best: 5, excellent: 2, inaccuracy: 1, mistake: 0, blunder: 0, book: 2 },
      avgWinLoss: 2,
    },
    blackSummary: {
      accuracy: overrides.bAcc ?? 70,
      estimatedElo: 1400,
      counts: { brilliant: 0, great: 0, best: 4, excellent: 2, inaccuracy: 1, mistake: 1, blunder: 1, book: 2 },
      avgWinLoss: 5,
    },
  };
}

describe('buildScoutGameplan', () => {
  it('identifies favorite White/Black openings, weakest targets, and clock/tilt takeaways', () => {
    const games: AnalyzedGame[] = [
      mockAnalyzedGame({ id: 'g1', eco: 'C50', opening: 'Italian Game: Giuoco Piano', white: 'RivalX', black: 'Me', result: '1-0', wAcc: 86 }),
      mockAnalyzedGame({ id: 'g2', eco: 'C50', opening: 'Italian Game: Two Knights', white: 'RivalX', black: 'Other', result: '1-0', wAcc: 82 }),
      mockAnalyzedGame({ id: 'g3', eco: 'B10', opening: 'Caro-Kann Defense', white: 'Me', black: 'RivalX', result: '1-0', bAcc: 58 }),
    ];

    const insights = {
      clockLeaks: { timeTroubleBlunders: 3, impulseBlunders: 2, impulsePerGame: 0.67, avgTimeSpentSec: 12 },
      blownWins: 2,
      tiltGuard: {
        activeWarning: false,
        consecutiveLosses: 0,
        buckets: [
          { label: '0L', priorLosses: 0, games: 5, wins: 3, draws: 1, losses: 1, winRate: 65 },
          { label: '2L+', priorLosses: 2, games: 3, wins: 1, draws: 0, losses: 2, winRate: 30 },
        ],
      },
      skillProfile: { openings: 62, tactics: 48, endgames: 39, conversion: 50, resilience: 50, timeManagement: 45 },
    } as unknown as MultiGameInsights;

    const plan = buildScoutGameplan('RivalX', games, insights);
    expect(plan.favoriteWhite[0].eco).toBe('C50');
    expect(plan.favoriteWhite[0].games).toBe(2);
    expect(plan.favoriteBlack[0].eco).toBe('B10');
    expect(plan.weakestTargets[0].eco).toBe('B10');
    expect(plan.weakestTargets[0].scorePct).toBe(0);
    expect(plan.tacticalTakeaways.some((t) => t.includes('Time-trouble target'))).toBe(true);
    expect(plan.tacticalTakeaways.some((t) => t.includes('Rematch edge'))).toBe(true);
  });
});
