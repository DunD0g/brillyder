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
  | 'Forced Mate'
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

/**
 * Legal static exchange evaluation (SEE) on `target` for the side currently to move.
 * Uses least-valuable legal attacker first (respecting pins, checks, and promotions).
 */
export function legalCaptureGainOnSquare(chess: Chess, target: Square, depth = 6): number {
  if (depth <= 0) return 0;
  const captures = chess.moves({ verbose: true }).filter((m) => m.to === target && m.captured);
  if (captures.length === 0) return 0;

  // Prefer lowest-value capturing piece, tie-breaking by highest promotion value (=Q before =N)
  captures.sort((a, b) => {
    const pieceDiff = PIECE_VAL[a.piece] - PIECE_VAL[b.piece];
    if (pieceDiff !== 0) return pieceDiff;
    const promoA = a.promotion ? PIECE_VAL[a.promotion] : 0;
    const promoB = b.promotion ? PIECE_VAL[b.promotion] : 0;
    return promoB - promoA;
  });
  const minPieceVal = PIECE_VAL[captures[0].piece];
  const candidates = captures.filter((c) => PIECE_VAL[c.piece] === minPieceVal).slice(0, 2);

  let best = 0;
  for (const capture of candidates) {
    if (!capture.captured) continue;
    const next = new Chess(chess.fen());
    next.move({ from: capture.from, to: capture.to, promotion: capture.promotion });
    const promoBonus = capture.promotion ? PIECE_VAL[capture.promotion] - PIECE_VAL.p : 0;
    const replyGain = legalCaptureGainOnSquare(next, target, depth - 1);
    const gain = PIECE_VAL[capture.captured] + promoBonus - replyGain;
    if (gain > best) best = gain;
  }
  return best;
}

export interface HangingTarget {
  square: Square;
  piece: PieceSymbol;
  attackerPiece: PieceSymbol | null;
  undefended: boolean;
  netLoss: number;
}

/**
 * Finds pieces belonging to `defenderColor` that can be won via legal captures.
 * When `chess.turn()` is the attacker, runs exact legal SEE (respecting absolute pins,
 * active checks, and 2-on-1 outnumbered squares). Otherwise uses pseudo-legal fallback.
 */
export function findHangingPieces(chess: Chess, defenderColor: Color): HangingTarget[] {
  const attackerColor: Color = defenderColor === 'w' ? 'b' : 'w';
  const targets: HangingTarget[] = [];

  if (chess.turn() === attackerColor) {
    const legalCaptures = chess.moves({ verbose: true }).filter((m) => Boolean(m.captured));
    const bySquare = new Map<Square, typeof legalCaptures>();
    for (const cap of legalCaptures) {
      const list = bySquare.get(cap.to) ?? [];
      list.push(cap);
      bySquare.set(cap.to, list);
    }

    for (const [sq, caps] of bySquare.entries()) {
      const cell = chess.get(sq);
      if (!cell || cell.color !== defenderColor || cell.type === 'k') continue;
      const gain = legalCaptureGainOnSquare(chess, sq, 6);
      if (gain < 2 && !(gain >= 1 && PIECE_VAL[cell.type] >= 3)) continue;
      // Only flag genuine material losses (>= 2 points, or losing an undefended piece >= 3)
      if (gain < 2) continue;

      caps.sort((a, b) => PIECE_VAL[a.piece] - PIECE_VAL[b.piece]);
      const lowestAttacker = caps[0]?.piece ?? null;
      const defenders = chess.attackers(sq, defenderColor);
      // Check if defender actually has a legal recapture after the lowest capture
      const probe = new Chess(chess.fen());
      probe.move({ from: caps[0].from, to: caps[0].to, promotion: caps[0].promotion });
      const legalRecaptures = probe.moves({ verbose: true }).filter((m) => m.to === sq && m.captured);
      const undefended = defenders.length === 0 || legalRecaptures.length === 0;

      targets.push({
        square: sq,
        piece: cell.type,
        attackerPiece: lowestAttacker,
        undefended,
        netLoss: gain,
      });
    }
    return targets.sort((a, b) => b.netLoss - a.netLoss || PIECE_VAL[b.piece] - PIECE_VAL[a.piece]);
  }

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
      const estLoss = undefended ? PIECE_VAL[cell.type] : Math.max(0, PIECE_VAL[cell.type] - lowestVal);
      if ((undefended && PIECE_VAL[cell.type] >= 3) || estLoss >= 2) {
        targets.push({
          square: cell.square,
          piece: cell.type,
          attackerPiece: lowestAttacker,
          undefended,
          netLoss: estLoss,
        });
      }
    }
  }
  return targets.sort((a, b) => b.netLoss - a.netLoss || PIECE_VAL[b.piece] - PIECE_VAL[a.piece]);
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

  const landedPiece: PieceSymbol = moved.promotion ?? moved.piece;
  // If the forking piece is simply captured for net material loss immediately (and isn't giving a double check / royal rescue), skip false forks
  const immediateLoss = legalCaptureGainOnSquare(clone, moved.to, 4);
  if (immediateLoss >= PIECE_VAL[landedPiece] && !clone.isCheck()) return null;

  const victims: string[] = [];
  for (const row of clone.board()) {
    for (const cell of row) {
      if (!cell || cell.color !== oppColor || PIECE_VAL[cell.type] < 3) continue;
      if (clone.attackers(cell.square, moverColor).includes(moved.to)) {
        const isKing = cell.type === 'k';
        const undefended = clone.attackers(cell.square, oppColor).length === 0;
        const higherThanAttacker = PIECE_VAL[landedPiece] < PIECE_VAL[cell.type];
        if (isKing || undefended || higherThanAttacker) {
          victims.push(`${PIECE_NAMES[cell.type]} on ${cell.square}`);
        }
      }
    }
  }
  return victims.length >= 2 ? { piece: landedPiece, targetSquare: moved.to, victims } : null;
}

export function detectBackRankThreat(
  chessBefore: Chess,
  moveUci: string,
  attackerColor: Color
): Square | null {
  const parsed = uciToSquares(moveUci);
  if (!parsed) return null;
  const oppColor: Color = attackerColor === 'w' ? 'b' : 'w';
  const backRank = attackerColor === 'w' ? '8' : '1';
  if (parsed.to[1] !== backRank) return null;

  const piece = chessBefore.get(parsed.from);
  const landedPiece = parsed.promotion ?? piece?.type;
  if (!landedPiece || (landedPiece !== 'r' && landedPiece !== 'q')) return null;

  // Verify the opponent's King is actually on the back rank!
  let oppKingOnBackRank = false;
  for (const row of chessBefore.board()) {
    for (const cell of row) {
      if (cell && cell.color === oppColor && cell.type === 'k' && cell.square[1] === backRank) {
        oppKingOnBackRank = true;
      }
    }
  }
  if (!oppKingOnBackRank) return null;

  const clone = new Chess(chessBefore.fen());
  try {
    const mv = clone.move({ from: parsed.from, to: parsed.to, promotion: parsed.promotion });
    if (clone.isCheckmate()) return parsed.to;
    if (clone.isCheck()) {
      // Avoid flagging routine equal recaptures (e.g. Qxd8+ Rxd8) as a back-rank infiltration unless profitable or mating
      const capturedVal = mv.captured ? PIECE_VAL[mv.captured] : 0;
      const replyLoss = legalCaptureGainOnSquare(clone, parsed.to, 4);
      if (replyLoss <= capturedVal || replyLoss < PIECE_VAL[landedPiece]) {
        return parsed.to;
      }
    }
  } catch {
    return null;
  }
  return null;
}

/**
 * Detects if playing `uci` creates a genuine Pin or Skewer along a ray from the moved slider (B/R/Q).
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
  const landedPiece: PieceSymbol = moved.promotion ?? moved.piece;
  if (landedPiece !== 'b' && landedPiece !== 'r' && landedPiece !== 'q') return null;

  const attackerVal = PIECE_VAL[landedPiece];
  const [f0, r0] = sqToCoords(moved.to);
  for (const [df, dr] of SLIDER_DIRS[landedPiece]) {
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
        const frontUndefended = clone.attackers(first.sq, oppColor).length === 0;
        const backUndefended = clone.attackers(sq, oppColor).length === 0;

        // Pin: back piece is strictly more valuable than front piece, and attacker actually threatens the back piece
        if (
          backVal > frontVal &&
          backVal >= 5 &&
          frontVal >= 3 &&
          (cell.type === 'k' || backUndefended || attackerVal < backVal)
        ) {
          return {
            kind: 'Pin',
            attacker: landedPiece,
            frontPiece: first.piece,
            frontSq: first.sq,
            backPiece: cell.type,
            backSq: sq,
          };
        }
        // Skewer: front piece is forced to move (King, undefended, or more valuable than attacker) exposing valuable/undefended back piece
        if (
          frontVal > backVal &&
          frontVal >= 5 &&
          backVal >= 3 &&
          (first.piece === 'k' || frontUndefended || attackerVal < frontVal) &&
          (backUndefended || attackerVal < backVal)
        ) {
          return {
            kind: 'Skewer',
            attacker: landedPiece,
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
        const higherThanSlider = PIECE_VAL[slider.type] < PIECE_VAL[cell.type];
        if (cell.type === 'k' || undefended || higherThanSlider) {
          return { slider: slider.type, sliderSq: attSq, target: cell.type, targetSq: cell.square };
        }
      }
    }
  }
  return null;
}

/**
 * Detects Deflection: `uci` (matching `pvUci[0]`) forces an enemy defender away from its
 * defensive post so that `pvUci[2]` wins a valuable piece on a DIFFERENT square (or mates)
 * that the defender was previously guarding.
 */
export function detectDeflection(
  chessBefore: Chess,
  uci: string,
  moverColor: Color,
  pvUci?: string[]
): { targetPiece: PieceSymbol; targetSq: Square } | null {
  if (!pvUci || pvUci.length < 3) return null;
  if (pvUci[0] !== uci) return null;
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

    // Check which squares the defender guarded before moving away
    const guardedBefore = new Set(c.attackers(follow.to, oppColor));
    const wasGuardingFollowSq = guardedBefore.has(reply.from);

    const m2 = c.move({ from: reply.from, to: reply.to, promotion: reply.promotion });
    const m3 = c.move({ from: follow.from, to: follow.to, promotion: follow.promotion });

    // Exclude routine recaptures on the exact same square (e.g. Nxd5 Nxd5 Bxd5)
    if (m3.to === m1.to && !c.isCheckmate()) return null;

    if (
      m2.to === m1.to &&
      wasGuardingFollowSq &&
      ((m3.captured && PIECE_VAL[m3.captured] >= 3) || c.isCheckmate())
    ) {
      return { targetPiece: defenderBefore.type, targetSq: reply.from };
    }
  } catch {
    return null;
  }
  return null;
}

export function detectShortMate(score: EngineScore, color: PlayerColor): number | null {
  if (score.mateWhite === null || score.mateWhite === 0) return null;
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
