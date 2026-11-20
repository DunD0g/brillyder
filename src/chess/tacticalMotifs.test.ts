import { describe, expect, it } from 'vitest';
import { Chess } from 'chess.js';
import {
  classifyEndgameCategory,
  detectBackRankThreat,
  detectDiscoveredAttack,
  detectForkOnMove,
  detectPinOrSkewer,
} from './tacticalMotifs';
import { generateMoveExplanation } from './moveCoach';
import { buildEngineScore } from '../utils/chessMath';
import { isTurningPointEvalSwing } from '../services/analysisRunner';

describe('tacticalMotifs, moveCoach & two-pass swing detection', () => {
  it('detects Knight Fork, Bishop Pin, Rook Skewer, Back-Rank threat, and Discovered Attack', () => {
    // Knight fork on c7 hitting King on e8 and Rook on a8
    const forkBoard = new Chess('r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1');
    const fork = detectForkOnMove(forkBoard, 'b5c7', 'w');
    expect(fork).not.toBeNull();
    expect(fork?.targetSquare).toBe('c7');

    // Bishop pin: Bb5 pins Knight on c6 to King on e8
    const pinBoard = new Chess('4k3/8/2n5/8/8/8/8/4KB2 w - - 0 1');
    const pin = detectPinOrSkewer(pinBoard, 'f1b5', 'w');
    expect(pin?.kind).toBe('Pin');
    expect(pin?.frontPiece).toBe('n');
    expect(pin?.backPiece).toBe('k');

    // Rook skewer: Ra8 skewers King on d8 to Queen on h8
    const skewerBoard = new Chess('3k3q/8/8/8/8/8/8/R3K3 w - - 0 1');
    const skewer = detectPinOrSkewer(skewerBoard, 'a1a8', 'w');
    expect(skewer?.kind).toBe('Skewer');

    // Back-rank check on d8
    const brBoard = new Chess('6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1');
    expect(detectBackRankThreat(brBoard, 'd1d8', 'w')).toBe('d8');

    // Discovered attack: Knight on e4 moves to g5, uncovering Rook on e1 against Queen on e7
    const discBoard = new Chess('4k3/4q3/8/8/4N3/8/8/4R1K1 w - - 0 1');
    const disc = detectDiscoveredAttack(discBoard, 'e4g5', 'w');
    expect(disc).not.toBeNull();
    expect(disc?.slider).toBe('r');
    expect(disc?.target).toBe('q');
  });

  it('classifies all 5 canonical endgame categories accurately', () => {
    expect(classifyEndgameCategory('8/5pk1/8/8/8/8/5PK1/8 w - - 0 1')).toBe('Pawn');
    expect(classifyEndgameCategory('8/5pk1/8/8/8/8/5PK1/3R4 w - - 0 1')).toBe('Rook');
    expect(classifyEndgameCategory('8/5pk1/8/8/8/8/5PK1/3B4 w - - 0 1')).toBe('Minor Piece');
    expect(classifyEndgameCategory('8/5pk1/8/8/8/8/5PK1/3Q4 w - - 0 1')).toBe('Queen');
    expect(classifyEndgameCategory('8/5pk1/8/8/8/8/3N1PK1/3R4 w - - 0 1')).toBe('Rook+Minor');
  });

  it('produces Only Move Save explanation when MultiPV gap >= 2.0 pawns', () => {
    const exp = generateMoveExplanation({
      beforeFen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
      afterFen: 'rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2',
      san: 'e5',
      uci: 'e7e5',
      color: 'b',
      bestMoveUci: 'e7e5',
      bestMoveSan: 'e5',
      evalBefore: buildEngineScore(20, null),
      evalAfter: buildEngineScore(20, null),
      secondBestGapPawns: 2.8,
      isClutchSave: true,
      classification: 'great',
    });
    expect(exp.tacticalTag).toBe('Only Move Save');
    expect(exp.headline).toContain('Clutch Save');
  });

  it('detects two-pass turning points when eval swings >= 1.0 pawn or mate changes', () => {
    const base = { fen: '', depth: 12, bestMoveUci: '', pv: [], lines: [] };
    expect(
      isTurningPointEvalSwing(
        { ...base, score: buildEngineScore(40, null) },
        { ...base, score: buildEngineScore(80, null) }
      )
    ).toBe(false);
    expect(
      isTurningPointEvalSwing(
        { ...base, score: buildEngineScore(40, null) },
        { ...base, score: buildEngineScore(-90, null) }
      )
    ).toBe(true);
    expect(
      isTurningPointEvalSwing(
        { ...base, score: buildEngineScore(300, null) },
        { ...base, score: buildEngineScore(0, 3) }
      )
    ).toBe(true);
  });
});
