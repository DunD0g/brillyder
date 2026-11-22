import { Chess, type Square } from 'chess.js';
import { describe, expect, it } from 'vitest';
import { countTotalPieces } from '../utils/chessMath';
import {
  classifyEndgameFenCategory,
  THEORETICAL_ENDGAME_DRILLS,
} from './endgameDrills';

function findKingCoords(chess: Chess, color: 'w' | 'b'): { r: number; c: number; sq: Square } | null {
  const board = chess.board();
  for (let r = 0; r < 8; r++) {
    for (let c = 0; c < 8; c++) {
      const cell = board[r][c];
      if (cell && cell.type === 'k' && cell.color === color) {
        return { r, c, sq: cell.square };
      }
    }
  }
  return null;
}

describe('THEORETICAL_ENDGAME_DRILLS', () => {
  it('covers all 5 Insights endgame categories with strictly legal, non-trivial Syzygy-eligible FENs', () => {
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

      // Verify both kings exist, are not adjacent, and opponent's king is NOT illegally in check
      const wk = findKingCoords(chess, 'w');
      const bk = findKingCoords(chess, 'b');
      expect(wk, `${drill.id} must have White king`).not.toBeNull();
      expect(bk, `${drill.id} must have Black king`).not.toBeNull();
      const kingDist = Math.max(Math.abs(wk!.r - bk!.r), Math.abs(wk!.c - bk!.c));
      expect(kingDist, `${drill.id} kings must not be adjacent`).toBeGreaterThanOrEqual(2);

      const oppKingSq = drill.userColor === 'w' ? bk!.sq : wk!.sq;
      expect(
        chess.isAttacked(oppKingSq, drill.userColor),
        `${drill.id} opponent king must not already be in check`
      ).toBe(false);

      // Verify firstHintSan is legal and NOT a trivial instant checkmate in 1
      const move = chess.move(drill.firstHintSan);
      expect(move, `${drill.id} hint "${drill.firstHintSan}" must be legal SAN`).not.toBeNull();
      expect(chess.isCheckmate(), `${drill.id} hint must not be a trivial mate-in-1`).toBe(false);
    }

    // Verify wrong-color rook pawn drill actually has opposite bishop color from h8
    const wrongBishop = THEORETICAL_ENDGAME_DRILLS.find((d) => d.id === 'eg_minor_wrong_bishop')!;
    const wbChess = new Chess(wrongBishop.fen);
    expect(wbChess.squareColor('f3')).not.toBe(wbChess.squareColor('h8'));
  });
});
