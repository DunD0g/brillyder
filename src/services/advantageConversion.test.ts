import { describe, expect, it } from 'vitest';
import type { AnalyzedGame, AnalyzedPly, LichessGameRecord } from '../types/chess';
import { buildEngineScore } from '../utils/chessMath';
import {
  evaluateConversionStatus,
  extractBlownLeadPositions,
} from './advantageConversion';

function makeGame(id: string, userColor: 'w' | 'b', resultString: '1-0' | '0-1' | '1/2-1/2', peakCpWhite: number, endCpWhite: number): AnalyzedGame {
  const game: LichessGameRecord = {
    id,
    source: 'lichess',
    rated: true,
    variant: 'standard',
    speed: 'rapid',
    perf: 'rapid',
    createdAt: Date.now(),
    status: 'resign',
    resultString,
    timeControlLabel: '10+0',
    pgn: '1. d4 d5 2. Bf4 Nf6',
    openingName: 'London System',
    openingEco: 'D02',
    white: { name: userColor === 'w' ? 'Hero' : 'Rival', rating: 1450 },
    black: { name: userColor === 'b' ? 'Hero' : 'Rival', rating: 1450 },
    userColor,
  };

  const ply1: AnalyzedPly = {
    ply: 21,
    moveNumber: 11,
    color: userColor,
    san: 'Qh5',
    uci: 'd1h5',
    from: 'd1',
    to: 'h5',
    beforeFen: 'rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 1',
    afterFen: 'rnbqkbnr/pppppppp/8/7Q/3P4/8/PPP1PPPP/RNB1KBNR b KQkq - 1 1',
    bestMoveUci: 'd1h5',
    bestMoveSan: 'Qh5',
    bestPvSan: ['Qh5'],
    evalBefore: buildEngineScore(peakCpWhite, null),
    evalAfter: buildEngineScore(endCpWhite, null),
    secondBestGapWin: 12,
    winLoss: 30,
    accuracy: 40,
    classification: 'blunder',
    phase: 'middlegame',
    coaching: { headline: 'Slipped', detail: '', tacticalTag: 'Eval Collapse' },
  };

  return {
    id,
    analyzedAt: Date.now(),
    depth: 14,
    game,
    initialEval: buildEngineScore(20, null),
    plies: [ply1],
    whiteSummary: { accuracy: 70, estimatedElo: 1450, counts: { brilliant: 0, great: 0, best: 0, excellent: 0, inaccuracy: 0, mistake: 0, blunder: 1, book: 0 }, avgWinLoss: 10 },
    blackSummary: { accuracy: 70, estimatedElo: 1450, counts: { brilliant: 0, great: 0, best: 0, excellent: 0, inaccuracy: 0, mistake: 0, blunder: 0, book: 0 }, avgWinLoss: 5 },
  };
}

describe('advantageConversion (Tractor Beam)', () => {
  it('extracts blown leads >= +2.5 for White and <= -2.5 for Black', () => {
    const whiteBlown = makeGame('g-w', 'w', '0-1', 340, -120);
    const blackBlown = makeGame('g-b', 'b', '1/2-1/2', -290, 0);
    const cleanWin = makeGame('g-clean', 'w', '1-0', 400, 420);

    const extracted = extractBlownLeadPositions([whiteBlown, blackBlown, cleanWin], 'Hero');
    expect(extracted.map((p) => p.gameId)).toContain('g-w');
    expect(extracted.map((p) => p.gameId)).toContain('g-b');
    expect(extracted.map((p) => p.gameId)).not.toContain('g-clean');
  });

  it('evaluates conversion thresholds (+8.0 won, +1.5..+7.9 holding, <+1.5 slipping)', () => {
    expect(evaluateConversionStatus(buildEngineScore(850, null), 'w', false).verdict).toBe('won');
    expect(evaluateConversionStatus(buildEngineScore(-860, null), 'b', false).verdict).toBe('won');
    expect(evaluateConversionStatus(buildEngineScore(320, null), 'w', false).verdict).toBe('holding');
    expect(evaluateConversionStatus(buildEngineScore(90, null), 'w', false).verdict).toBe('slipping');
    expect(evaluateConversionStatus(buildEngineScore(0, null), 'w', true).verdict).toBe('won');
  });
});
