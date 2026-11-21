import { describe, expect, it } from 'vitest';
import {
  buildPuzzleSolutionLine,
  formatSolutionLineSan,
  userMoveCountForLine,
} from './puzzleSequence';

describe('puzzleSequence — multi-move tactical puzzles', () => {
  it('extracts a forced Mate-in-2 (3 plies) sequence cleanly', () => {
    // Classic back-rank Mate-in-2: 1. Re8+ Rxe8 2. Rxe8#
    const fen = 'r5k1/5ppp/8/8/8/8/4RPPP/4R1K1 w - - 0 1';
    const line = buildPuzzleSolutionLine({
      beforeFen: fen,
      bestMoveUci: 'e2e8',
      bestPvSan: ['Re8+', 'Rxe8', 'Rxe8#'],
      tacticalTag: 'Back-Rank Mate',
    });
    expect(line).toHaveLength(3);
    expect(userMoveCountForLine(line)).toBe(2);
    expect(line.map((s) => s.san)).toEqual(['Re8+', 'Rxe8', 'Rxe8#']);
    expect(line[2].isCheckmate).toBe(true);
    expect(formatSolutionLineSan(line)).toBe('Re8+ → Rxe8 → Rxe8#');
  });

  it('extracts a 2-move forcing tactic (check + capture) when PV continues tactically', () => {
    // Queen check winning an undefended rook on a8: 1. Qd5+ Kh8 2. Qxa8
    const fen = 'r5k1/5ppp/8/8/3Q4/8/5PPP/6K1 w - - 0 1';
    const line = buildPuzzleSolutionLine({
      beforeFen: fen,
      bestMoveUci: 'd4d5',
      bestPvSan: ['Qd5+', 'Kh8', 'Qxa8', 'h6'],
      tacticalTag: 'Fork',
    });
    expect(line).toHaveLength(3);
    expect(userMoveCountForLine(line)).toBe(2);
    expect(line.map((s) => s.uci)).toEqual(['d4d5', 'g8h8', 'd5a8']);
  });

  it('keeps quiet positional continuations as 1-move puzzles instead of arbitrary multi-move guesses', () => {
    const fen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2';
    const line = buildPuzzleSolutionLine({
      beforeFen: fen,
      bestMoveUci: 'g1f3',
      bestPvSan: ['Nf3', 'Nc6', 'Bc4', 'Nf6'],
      tacticalTag: 'Development',
    });
    expect(line).toHaveLength(1);
    expect(userMoveCountForLine(line)).toBe(1);
  });

  it('stops at Move 1 when Move 1 is already checkmate', () => {
    const fen = '6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1';
    const line = buildPuzzleSolutionLine({
      beforeFen: fen,
      bestMoveUci: 'e1e8',
      bestPvSan: ['Re8#'],
      tacticalTag: 'Back-Rank Mate',
    });
    expect(line).toHaveLength(1);
    expect(line[0].isCheckmate).toBe(true);
  });

  it('gracefully falls back to Move 1 if bestPvSan contains malformed moves or mismatches', () => {
    const fen = '4r1k1/5ppp/8/8/8/8/5PPP/3RR1K1 w - - 0 1';
    const line = buildPuzzleSolutionLine({
      beforeFen: fen,
      bestMoveUci: 'e1e8',
      bestPvSan: ['Re8+', 'ILLEGAL_SAN', 'Rxe8#'],
      tacticalTag: 'Back-Rank Mate',
    });
    expect(line).toHaveLength(1);
    expect(line[0].uci).toBe('e1e8');
  });
});
