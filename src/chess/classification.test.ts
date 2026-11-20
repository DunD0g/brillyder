import { describe, expect, it } from 'vitest';
import { Chess } from 'chess.js';
import {
  classifyMove,
  computePlayerStats,
  isSacrificeMove,
  loadPgnSafely,
} from './classification';
import { isBookPly } from './openingBook';
import {
  detectBackRankThreat,
  detectDeflection,
  detectForkOnMove,
  detectPinOrSkewer,
} from './tacticalMotifs';
import { generateMoveExplanation } from './moveCoach';
import {
  buildEngineScore,
  computeMoveTimeSpent,
  extractClockFromComment,
  extractClockSeconds,
  parsePgnTimeControl,
} from '../utils/chessMath';
import { buildLc0PolicyMap, uciToLc0PolicyIndex } from '../engine/MaiaService';

describe('Pass 1 — Brilliant engine, classification, motifs, clocks & Maia policy map', () => {
  it('does NOT flag pawn promotion bxa8=Q Kxa8 as a brilliant sacrifice', () => {
    // White pawn on b7 captures Black Rook on a8 and promotes to Queen; Black King on b8 can recapture
    const beforeFen = 'rk6/1P6/8/8/8/8/8/4K3 w - - 0 1';
    const c = new Chess(beforeFen);
    const mv = c.move({ from: 'b7', to: 'a8', promotion: 'q' });
    expect(
      isSacrificeMove(beforeFen, c.fen(), 'w', mv.to, mv.piece, mv.captured, mv.promotion)
    ).toBe(false);
  });

  it('detects active rook sacrifice and passive sacrifice (leaving Rook en prise)', () => {
    // Active sacrifice: White Rook on e1 takes defended pawn on e6 (pawn on f7 recaptures)
    const activeBefore = '4k3/5p2/4p3/8/8/8/8/4R1K1 w - - 0 1';
    const c1 = new Chess(activeBefore);
    const mv1 = c1.move({ from: 'e1', to: 'e6' });
    expect(isSacrificeMove(activeBefore, c1.fen(), 'w', mv1.to, mv1.piece, mv1.captured)).toBe(true);

    // Passive sacrifice: White Rook on a1 is attacked by Black Bishop on g7, White plays quiet Qh6 instead of saving Ra1
    const passiveBefore = '6k1/6b1/8/8/8/8/7Q/R5K1 w - - 0 1';
    const c2 = new Chess(passiveBefore);
    const mv2 = c2.move({ from: 'h2', to: 'h6' });
    expect(isSacrificeMove(passiveBefore, c2.fen(), 'w', mv2.to, mv2.piece, mv2.captured)).toBe(true);
  });

  it('never classifies Stockfish #1 best move as blunder even when walkedIntoMate is true', () => {
    const cls = classifyMove({
      plyIndex: 20,
      sanPrefix: [],
      playedUci: 'g1h1',
      bestMoveUci: 'g1h1',
      beforeFen: '6k1/8/8/8/8/8/6PP/6K1 w - - 0 1',
      afterFen: '6k1/8/8/8/8/8/6PP/7K b - - 1 1',
      moverColor: 'w',
      toSquare: 'h1',
      movedPiece: 'k',
      positionRepeated: false,
      moverWinBefore: 25,
      moverWinAfter: 0,
      secondBestGapWin: 12,
      hasSecondLine: true,
      missedMate: false,
      walkedIntoMate: true,
    });
    expect(cls).not.toBe('blunder');
    expect(cls).toBe('great');
  });

  it('penalizes missing Mate in 1 instead of grading it Best Move', () => {
    const cls = classifyMove({
      plyIndex: 30,
      sanPrefix: [],
      playedUci: 'a1a2',
      bestMoveUci: 'd1d8',
      beforeFen: '6k1/5ppp/8/8/8/8/5PPP/R2R2K1 w - - 0 1',
      afterFen: '6k1/5ppp/8/8/8/8/R4PPP/3R2K1 b - - 1 1',
      moverColor: 'w',
      toSquare: 'a2',
      movedPiece: 'r',
      positionRepeated: false,
      moverWinBefore: 100,
      moverWinAfter: 98.2,
      secondBestGapWin: 1.8,
      hasSecondLine: true,
      missedMate: true,
      missedShortMate: true,
      walkedIntoMate: false,
    });
    expect(cls).toBe('inaccuracy');
  });

  it('marks standard Move 1 (1. e4 / 1... e5) as Book even without lichessOpeningPly', () => {
    expect(isBookPly(0, ['e4'], undefined, 0)).toBe(true);
    expect(isBookPly(1, ['e4', 'e5'], undefined, 0)).toBe(true);
  });

  it('handles 0-ply player stats safely and treats "*" result neutrally', () => {
    const empty = computePlayerStats([], 'w', 1500, 1500, '*');
    expect(empty.accuracy).toBe(0);
    expect(empty.estimatedElo).toBe(1500);
  });

  it('strips PGN variations without breaking parentheses inside headers or comments', () => {
    const pgn = '[Event "Blitz (3+0)"]\n[Site "Lichess"]\n\n1. e4 {solid :)} (1. d4 d5) 1... e5 2. Nf3 *';
    const chess = loadPgnSafely(pgn);
    expect(chess.history()).toEqual(['e4', 'e5', 'Nf3']);
  });

  it('parses 2-part decimal clocks, sub-minute consistency, multi-stage TC, and move 1 increment', () => {
    expect(extractClockFromComment('[%clk 04:58.3 ]')).toBe('4:58');
    expect(extractClockSeconds('[%clk 04:58.3 ]')).toBe(298.3);
    expect(extractClockFromComment('[%clk 0:00:59.9]')).toBe('0:59');
    expect(extractClockSeconds('[%clk 0:00:59.9]')).toBeLessThan(60);
    expect(parsePgnTimeControl('[TimeControl "40/5400+30:1800+30"]')).toEqual({
      baseSeconds: 5400,
      incrementSeconds: 30,
    });
    expect(parsePgnTimeControl('[Event "Sample"]', '5+3')).toEqual({
      baseSeconds: 300,
      incrementSeconds: 3,
    });
    // Move 1 instant move in 5+3 should be 0s spent, not 3s
    expect(computeMoveTimeSpent(300, 300, 3, true)).toBe(0);
    expect(computeMoveTimeSpent(300, 298, 3, false)).toBe(5);
  });

  it('avoids false positives in Fork, Pin/Skewer, Back-Rank, Deflection, and Equal-Trade Hanging Piece', () => {
    // Promotion fork c8=Q+ (attacking King on e8 + undefended Rook on h3) should report Queen ('q'), never Pawn ('p')
    const promoForkFen = '4k3/2P5/8/8/8/7r/8/4K3 w - - 0 1';
    const promoFork = detectForkOnMove(new Chess(promoForkFen), 'c7c8q', 'w');
    expect(promoFork).not.toBeNull();
    expect(promoFork?.piece).toBe('q');

    // Back-rank check with opponent King NOT on back rank (King on e5) is NOT a Back-Rank Mate
    const midKingFen = '8/8/8/4k3/8/8/8/4R1K1 w - - 0 1';
    expect(detectBackRankThreat(new Chess(midKingFen), 'e1e8', 'w')).toBeNull();

    // Queen lining up with defended Rook + defended Bishop is NOT a Skewer
    const qLineFen = '4k3/3p4/4r3/5b2/8/8/8/1Q2K3 w - - 0 1';
    expect(detectPinOrSkewer(new Chess(qLineFen), 'b1b3', 'w')).toBeNull();

    // Ordinary double exchange Nxd5 Nxd5 Bxd5 is NOT a Deflection
    const tradeFen = 'r1bqkb1r/ppp2ppp/2n5/3np3/8/2N2N2/PPPPBPPP/R1BQK2R w KQkq - 0 6';
    expect(detectDeflection(new Chess(tradeFen), 'c3d5', 'w', ['c3d5', 'd8d5', 'e2c4'])).toBeNull();

    // Equal trade Bxf6 (g7xf6 recaptures) should NOT be tagged "Leaves Bishop on f6 undefended"
    const equalTradeBefore = 'r1bqkb1r/pppp1ppp/5n2/6B1/4P3/8/PPP2PPP/RN1QKBNR w KQkq - 0 4';
    const ct = new Chess(equalTradeBefore);
    const mv = ct.move('Bxf6');
    const coaching = generateMoveExplanation({
      beforeFen: equalTradeBefore,
      afterFen: ct.fen(),
      san: mv.san,
      uci: 'g5f6',
      color: 'w',
      bestMoveUci: 'b1c3',
      bestMoveSan: 'Nc3',
      evalBefore: buildEngineScore(30, null),
      evalAfter: buildEngineScore(-30, null),
      classification: 'inaccuracy',
    });
    expect(coaching.tacticalTag).not.toBe('Hanging Piece');
  });

  it('builds exact 1858-entry LC0 policy map with valid underpromotion & black-flip indices', () => {
    const map = buildLc0PolicyMap();
    expect(map.size).toBe(1858);
    expect(uciToLc0PolicyIndex('e2e4', false)).toBeGreaterThanOrEqual(0);
    expect(uciToLc0PolicyIndex('e7e5', true)).toBe(uciToLc0PolicyIndex('e2e4', false));
    // Knight promotion maps to base move, Queen/Rook/Bishop map to 1792..1857
    expect(uciToLc0PolicyIndex('a7a8n', false)).toBe(uciToLc0PolicyIndex('a7a8', false));
    expect(uciToLc0PolicyIndex('a7a8q', false)).toBeGreaterThanOrEqual(1792);
    expect(uciToLc0PolicyIndex('a7a8r', false)).toBeGreaterThanOrEqual(1792);
    expect(uciToLc0PolicyIndex('a7a8b', false)).toBeGreaterThanOrEqual(1792);
    expect(uciToLc0PolicyIndex('a7a8q', false)).not.toBe(uciToLc0PolicyIndex('a7a8r', false));
  });
});
