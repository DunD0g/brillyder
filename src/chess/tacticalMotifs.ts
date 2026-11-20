import { Chess, type Color, type PieceSymbol, type Square } from 'chess.js';
import type { EndgameCategory, EngineScore, PlayerColor } from '../types/chess';
import { uciToSquares } from '../utils/chessMath';

export type TacticalMotifName =
  | 'Hanging Piece'
  | 'Fork'
  | 'Pin/Skewer'
  | 'Back-Rank Mate'
  | 'Discovered Attack'
  | 'Deflection'
  | 'Mate in 1–3'
  | 'Only Move Save';

export const PIECE_NAMES: Record<PieceSymbol, string> = {
  p: 'Pawn',
  n: 'Knight',
  b: 'Bishop',
  r: 'Rook',
  q: 'Queen',
  k: 'King',
};

export const PIECE_VAL: Record<PieceSymbol, number> = {
  p: 1,
  n: 3,
  b: 3,
  r: 5,
  q: 9,
  k: 100,
};

function sqToCoords(sq: Square): [number, number] {
  return [sq.charCodeAt(0) - 97, parseInt(sq[1], 10) - 1];
}

function coordsToSq(file: number, rank: number): Square | null {
  if (file < 0 || file > 7 || rank < 0 || rank > 7) return null;
  return `${String.fromCharCode(97 + file)}${rank + 1}` as Square;
}

const SLIDER_DIRS: Record<'b' | 'r' | 'q', Array<[number, number]>> = {
  b: [[1, 1], [1, -1], [-1, 1], [-1, -1]],
  r: [[1, 0], [-1, 0], [0, 1], [0, -1]],
  q: [[1, 1], [1, -1], [-1, 1], [-1, -1], [1, 0], [-1, 0], [0, 1], [0, -1]],
};

export interface HangingTarget {
  square: Square;
  piece: PieceSymbol;
  attackerPiece: PieceSymbol | null;
  undefended: boolean;
}

export function findHangingPieces(chess: Chess, defenderColor: Color): HangingTarget[] {
  const attackerColor: Color = defenderColor === 'w' ? 'b' : 'w';
  const targets: HangingTarget[] = [];
  for (const row of chess.board()) {
    for (const cell of row) {
      if (!cell || cell.color !== defenderColor || cell.type === 'k') continue;
      const attackers = chess.attackers(cell.square, attackerColor);
      if (attackers.length === 0) continue;
      const defenders = chess.attackers(cell.square, defenderColor);
      let lowestAttacker: PieceSymbol | null = null;
      let lowestVal = 999;
      for (const attSq of attackers) {
        const att = chess.get(attSq);
        if (att && PIECE_VAL[att.type] < lowestVal) {
          lowestVal = PIECE_VAL[att.type];
          lowestAttacker = att.type;
        }
      }
      const undefended = defenders.length === 0;
      if ((undefended && PIECE_VAL[cell.type] >= 3) || lowestVal < PIECE_VAL[cell.type]) {
        targets.push({ square: cell.square, piece: cell.type, attackerPiece: lowestAttacker, undefended });
      }
    }
  }
  return targets.sort((a, b) => PIECE_VAL[b.piece] - PIECE_VAL[a.piece]);
}

export function detectForkOnMove(
  chessBefore: Chess,
  uci: string,
  moverColor: Color
): { piece: PieceSymbol; targetSquare: Square; victims: string[] } | null {
  const parsed = uciToSquares(uci);
  if (!parsed) return null;
  const oppColor: Color = moverColor === 'w' ? 'b' : 'w';
  const clone = new Chess(chessBefore.fen());
  let moved;
  try {
    moved = clone.move({ from: parsed.from, to: parsed.to, promotion: parsed.promotion });
  } catch {
    return null;
  }
  const victims: string[] = [];
  for (const row of clone.board()) {
    for (const cell of row) {
      if (!cell || cell.color !== oppColor || PIECE_VAL[cell.type] < 3) continue;
      if (clone.attackers(cell.square, moverColor).includes(moved.to)) {
        const highVal = cell.type === 'k' || cell.type === 'q' || cell.type === 'r';
        const undefended = clone.attackers(cell.square, oppColor).length === 0;
        if (highVal || undefended || PIECE_VAL[moved.piece] < PIECE_VAL[cell.type]) {
          victims.push(`${PIECE_NAMES[cell.type]} on ${cell.square}`);
        }
      }
    }
  }
  return victims.length >= 2 ? { piece: moved.piece, targetSquare: moved.to, victims } : null;
}

export function detectBackRankThreat(
  chessBefore: Chess,
  moveUci: string,
  attackerColor: Color
): Square | null {
  const parsed = uciToSquares(moveUci);
  if (!parsed) return null;
  const piece = chessBefore.get(parsed.from);
  if (!piece || (piece.type !== 'r' && piece.type !== 'q')) return null;
  if (parsed.to[1] !== (attackerColor === 'w' ? '8' : '1')) return null;
  const clone = new Chess(chessBefore.fen());
  try {
    clone.move({ from: parsed.from, to: parsed.to, promotion: parsed.promotion });
    if (clone.isCheck() || clone.isCheckmate()) return parsed.to;
  } catch {
    return null;
  }
  return null;
}

/**
 * Detects if playing `uci` creates a Pin or Skewer along a ray from the moved slider (B/R/Q).
 */
export function detectPinOrSkewer(
  chessBefore: Chess,
  uci: string,
  moverColor: Color
): { kind: 'Pin' | 'Skewer'; attacker: PieceSymbol; frontPiece: PieceSymbol; frontSq: Square; backPiece: PieceSymbol; backSq: Square } | null {
  const parsed = uciToSquares(uci);
  if (!parsed) return null;
  const oppColor: Color = moverColor === 'w' ? 'b' : 'w';
  const clone = new Chess(chessBefore.fen());
  let moved;
  try {
    moved = clone.move({ from: parsed.from, to: parsed.to, promotion: parsed.promotion });
  } catch {
    return null;
  }
  if (moved.piece !== 'b' && moved.piece !== 'r' && moved.piece !== 'q') return null;

  const [f0, r0] = sqToCoords(moved.to);
  for (const [df, dr] of SLIDER_DIRS[moved.piece]) {
    let first: { sq: Square; piece: PieceSymbol } | null = null;
    for (let step = 1; step < 8; step++) {
      const sq = coordsToSq(f0 + df * step, r0 + dr * step);
      if (!sq) break;
      const cell = clone.get(sq);
      if (!cell) continue;
      if (cell.color !== oppColor) break;
      if (!first) {
        first = { sq, piece: cell.type };
      } else {
        const frontVal = PIECE_VAL[first.piece];
        const backVal = PIECE_VAL[cell.type];
        if (backVal > frontVal && backVal >= 5 && frontVal >= 3) {
          return {
            kind: 'Pin',
            attacker: moved.piece,
            frontPiece: first.piece,
            frontSq: first.sq,
            backPiece: cell.type,
            backSq: sq,
          };
        }
        if (frontVal > backVal && frontVal >= 5 && backVal >= 3) {
          return {
            kind: 'Skewer',
            attacker: moved.piece,
            frontPiece: first.piece,
            frontSq: first.sq,
            backPiece: cell.type,
            backSq: sq,
          };
        }
        break;
      }
    }
  }
  return null;
}

/**
 * Detects a Discovered Attack: moving a piece from `from` uncovers a friendly slider (B/R/Q)
 * that now attacks a valuable opponent piece (K, Q, R, or undefended minor piece).
 */
export function detectDiscoveredAttack(
  chessBefore: Chess,
  uci: string,
  moverColor: Color
): { slider: PieceSymbol; sliderSq: Square; target: PieceSymbol; targetSq: Square } | null {
  const parsed = uciToSquares(uci);
  if (!parsed) return null;
  const oppColor: Color = moverColor === 'w' ? 'b' : 'w';
  const clone = new Chess(chessBefore.fen());
  try {
    clone.move({ from: parsed.from, to: parsed.to, promotion: parsed.promotion });
  } catch {
    return null;
  }

  for (const row of clone.board()) {
    for (const cell of row) {
      if (!cell || cell.color !== oppColor || PIECE_VAL[cell.type] < 3) continue;
      const beforeAtt = new Set(chessBefore.attackers(cell.square, moverColor));
      const afterAtt = clone.attackers(cell.square, moverColor);
      for (const attSq of afterAtt) {
        if (attSq === parsed.to || beforeAtt.has(attSq)) continue;
        const slider = clone.get(attSq);
        if (!slider || (slider.type !== 'b' && slider.type !== 'r' && slider.type !== 'q')) continue;
        const undefended = clone.attackers(cell.square, oppColor).length === 0;
        if (cell.type === 'k' || cell.type === 'q' || cell.type === 'r' || undefended) {
          return { slider: slider.type, sliderSq: attSq, target: cell.type, targetSq: cell.square };
        }
      }
    }
  }
  return null;
}

/**
 * Detects Deflection: `uci` attacks or sacrifices onto an enemy defender whose capture/relocation
 * drops protection on another high-value square.
 */
export function detectDeflection(
  chessBefore: Chess,
  uci: string,
  moverColor: Color,
  pvUci?: string[]
): { targetPiece: PieceSymbol; targetSq: Square } | null {
  if (!pvUci || pvUci.length < 3) return null;
  const first = uciToSquares(uci);
  const reply = uciToSquares(pvUci[1]);
  const follow = uciToSquares(pvUci[2]);
  if (!first || !reply || !follow) return null;

  const oppColor: Color = moverColor === 'w' ? 'b' : 'w';
  const c = new Chess(chessBefore.fen());
  try {
    const m1 = c.move({ from: first.from, to: first.to, promotion: first.promotion });
    const defenderBefore = c.get(reply.from);
    if (!defenderBefore || defenderBefore.color !== oppColor) return null;
    const m2 = c.move({ from: reply.from, to: reply.to, promotion: reply.promotion });
    const m3 = c.move({ from: follow.from, to: follow.to, promotion: follow.promotion });
    // If reply recaptured our piece (or moved away) and our follow-up captured a valuable piece or gave checkmate
    if (m2.to === m1.to && (m3.captured && PIECE_VAL[m3.captured] >= 3 || c.isCheckmate())) {
      return { targetPiece: defenderBefore.type, targetSq: reply.from };
    }
  } catch {
    return null;
  }
  return null;
}

export function detectShortMate(score: EngineScore, color: PlayerColor): number | null {
  if (score.mateWhite === null) return null;
  const signed = color === 'w' ? score.mateWhite : -score.mateWhite;
  if (signed > 0 && signed <= 3) return signed;
  return null;
}

/**
 * Classifies an endgame position into one of 5 canonical endgame families:
 * Rook, Pawn, Minor Piece, Queen, or Rook+Minor.
 */
export function classifyEndgameCategory(fen: string): EndgameCategory {
  const chess = new Chess(fen);
  let queens = 0;
  let rooks = 0;
  let minors = 0;

  for (const row of chess.board()) {
    for (const cell of row) {
      if (!cell || cell.type === 'k' || cell.type === 'p') continue;
      if (cell.type === 'q') queens++;
      else if (cell.type === 'r') rooks++;
      else if (cell.type === 'b' || cell.type === 'n') minors++;
    }
  }

  if (queens > 0) return 'Queen';
  if (rooks > 0 && minors > 0) return 'Rook+Minor';
  if (rooks > 0) return 'Rook';
  if (minors > 0) return 'Minor Piece';
  return 'Pawn';
}
