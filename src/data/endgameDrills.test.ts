import { Chess } from 'chess.js';
import { describe, expect, it } from 'vitest';
import { countTotalPieces } from '../utils/chessMath';
import {
  classifyEndgameFenCategory,
  THEORETICAL_ENDGAME_DRILLS,
} from './endgameDrills';

describe('THEORETICAL_ENDGAME_DRILLS', () => {
  it('covers all 5 Insights endgame categories with valid Syzygy-eligible FENs and legal hint moves', () => {
    const categories = new Set(THEORETICAL_ENDGAME_DRILLS.map((d) => d.category));
    expect(categories.has('Pawn')).toBe(true);
    expect(categories.has('Rook')).toBe(true);
    expect(categories.has('Minor Piece')).toBe(true);
    expect(categories.has('Queen')).toBe(true);
    expect(categories.has('Rook+Minor')).toBe(true);

    for (const drill of THEORETICAL_ENDGAME_DRILLS) {
      const chess = new Chess(drill.fen);
      expect(chess.isGameOver(), `${drill.id} must not be game-over`).toBe(false);
      expect(chess.turn(), `${drill.id} turn must match userColor`).toBe(drill.userColor);
      expect(countTotalPieces(drill.fen), `${drill.id} must be <= 7 pieces for Syzygy`).toBeLessThanOrEqual(7);
      expect(countTotalPieces(drill.fen), `${drill.id} must have >= 3 pieces`).toBeGreaterThanOrEqual(3);
      expect(classifyEndgameFenCategory(drill.fen), `${drill.id} category matches FEN pieces`).toBe(drill.category);

      const move = chess.move(drill.firstHintSan);
      expect(move, `${drill.id} hint "${drill.firstHintSan}" must be legal SAN`).not.toBeNull();
    }
  });
});
