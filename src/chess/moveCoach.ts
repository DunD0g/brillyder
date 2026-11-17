import { Chess, type Color, type PieceSymbol, type Square } from 'chess.js';
import type { CoachingExplanation, EngineScore, MoveClassification, PlayerColor } from '../types/chess';
import { uciToSquares } from '../utils/chessMath';

const PIECE_NAMES: Record<PieceSymbol, string> = { p: 'Pawn', n: 'Knight', b: 'Bishop', r: 'Rook', q: 'Queen', k: 'King' };
const PIECE_VAL: Record<PieceSymbol, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 100 };

interface HangingTarget {
  square: Square;
  piece: PieceSymbol;
  attackerPiece: PieceSymbol | null;
  undefended: boolean;
}

function findHangingPieces(chess: Chess, defenderColor: Color): HangingTarget[] {
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

function detectForkOnMove(chessBefore: Chess, uci: string, moverColor: Color): { piece: PieceSymbol; targetSquare: Square; victims: string[] } | null {
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

function detectBackRank(chessBefore: Chess, threatUci: string, attackerColor: Color): Square | null {
  const parsed = uciToSquares(threatUci);
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

export function generateMoveExplanation(params: {
  beforeFen: string;
  afterFen: string;
  san: string;
  uci: string;
  color: PlayerColor;
  bestMoveUci: string;
  bestMoveSan: string;
  threatMoveUci?: string;
  evalBefore: EngineScore;
  evalAfter: EngineScore;
  classification: MoveClassification;
  openingName?: string;
}): CoachingExplanation {
  const { beforeFen, afterFen, san, uci, color, bestMoveUci, bestMoveSan, threatMoveUci, evalBefore, evalAfter, classification, openingName } = params;
  const oppColor: PlayerColor = color === 'w' ? 'b' : 'w';
  const chessBefore = new Chess(beforeFen);
  const chessAfter = new Chess(afterFen);

  if (classification === 'book') {
    return {
      headline: `Book Move — ${san}`,
      detail: openingName ? `Standard theory in the ${openingName}. Builds development and central tension.` : 'Follows established opening theory.',
      tacticalTag: 'Theory',
    };
  }
  if (classification === 'brilliant') {
    return {
      headline: `Brilliant! ${san}`,
      detail: 'Sacrifices material while keeping a sharp, winning initiative — pure BrillyDer magic!',
      tacticalTag: 'Sacrifice',
    };
  }
  if (classification === 'great') {
    const fork = detectForkOnMove(chessBefore, uci, color);
    return {
      headline: `Great Move! ${san}`,
      detail: fork
        ? `Only winning move — launches a ${PIECE_NAMES[fork.piece]} fork on ${fork.targetSquare} hitting ${fork.victims.slice(0, 2).join(' and ')}.`
        : 'The only move that preserves your advantage; alternatives lose substantial ground.',
      tacticalTag: 'Only Move',
    };
  }
  if (classification === 'best' || classification === 'excellent') {
    if (evalAfter.isCheckmate) return { headline: `Checkmate! ${san}`, detail: 'Delivers forced checkmate cleanly.', tacticalTag: 'Checkmate' };
    const fork = detectForkOnMove(chessBefore, uci, color);
    if (fork) {
      return {
        headline: `${classification === 'best' ? 'Best' : 'Solid'} Move — ${san}`,
        detail: `Creates a double attack on ${fork.targetSquare} targeting ${fork.victims.slice(0, 2).join(' and ')}.`,
        tacticalTag: 'Tactic',
      };
    }
    return {
      headline: classification === 'best' ? `Best Move — ${san}` : `Good Move — ${san}`,
      detail: classification === 'best' ? `Matches Stockfish's top choice (${evalAfter.display}).` : `Keeps things solid; ${bestMoveSan || san} was slightly sharper.`,
      tacticalTag: classification === 'best' ? 'Engine Top' : 'Accurate',
    };
  }

  const prefix = classification === 'blunder' ? 'Blunder' : classification === 'mistake' ? 'Mistake' : 'Inaccuracy';
  const moverHadMate = evalBefore.mateWhite !== null && ((color === 'w' && evalBefore.mateWhite > 0) || (color === 'b' && evalBefore.mateWhite < 0));
  const moverHasMate = evalAfter.isCheckmate || (evalAfter.mateWhite !== null && ((color === 'w' && evalAfter.mateWhite > 0) || (color === 'b' && evalAfter.mateWhite < 0)));
  if (moverHadMate && !moverHasMate) {
    return { headline: `${prefix}: Missed Forced Mate`, detail: `${bestMoveSan} forced checkmate, whereas ${san} lets the opponent escape.`, tacticalTag: 'Missed Mate' };
  }

  const oppGotMate = evalAfter.mateWhite !== null && ((color === 'w' && evalAfter.mateWhite < 0) || (color === 'b' && evalAfter.mateWhite > 0));
  if (oppGotMate) {
    return { headline: `${prefix}: Walks Into Forced Mate`, detail: `${san} exposes your King to a mating net. ${bestMoveSan} stayed safe.`, tacticalTag: 'King Safety' };
  }

  if (threatMoveUci) {
    const backRankSq = detectBackRank(chessAfter, threatMoveUci, oppColor);
    if (backRankSq) {
      return { headline: `${prefix}: Allows Back-Rank Infiltration`, detail: `Allows opponent's Rook/Queen onto ${backRankSq} with check. ${bestMoveSan} covered it.`, tacticalTag: 'Back Rank' };
    }
    const oppFork = detectForkOnMove(chessAfter, threatMoveUci, oppColor);
    if (oppFork) {
      return { headline: `${prefix}: Allows Fork on ${oppFork.targetSquare}`, detail: `${san} walks into a ${PIECE_NAMES[oppFork.piece]} fork hitting ${oppFork.victims.slice(0, 2).join(' and ')}. Prefer ${bestMoveSan}.`, tacticalTag: 'Allowed Fork' };
    }
  }

  const missedFork = detectForkOnMove(chessBefore, bestMoveUci, color);
  if (missedFork) {
    return { headline: `${prefix}: Missed ${PIECE_NAMES[missedFork.piece]} Fork on ${missedFork.targetSquare}`, detail: `Instead of ${san}, ${bestMoveSan} forked ${missedFork.victims.slice(0, 2).join(' and ')}.`, tacticalTag: 'Missed Fork' };
  }

  const beforeHanging = findHangingPieces(chessBefore, color).map((h) => h.square);
  const afterHanging = findHangingPieces(chessAfter, color);
  const newlyHanging = afterHanging.find((h) => !beforeHanging.includes(h.square)) || afterHanging[0];
  if (newlyHanging) {
    const pName = PIECE_NAMES[newlyHanging.piece];
    const reason = newlyHanging.undefended
      ? `Leaves your ${pName} on ${newlyHanging.square} undefended`
      : `Drops your ${pName} on ${newlyHanging.square} to a ${newlyHanging.attackerPiece ? PIECE_NAMES[newlyHanging.attackerPiece] : 'lesser'} attack`;
    return { headline: `${prefix}: ${reason}`, detail: `${bestMoveSan} protected material and kept control.`, tacticalTag: 'Hanging Piece' };
  }

  const parsedBest = uciToSquares(bestMoveUci);
  if (parsedBest) {
    const target = chessBefore.get(parsedBest.to);
    if (target && target.color === oppColor && PIECE_VAL[target.type] >= 3 && chessBefore.attackers(parsedBest.to, oppColor).length === 0) {
      return { headline: `${prefix}: Missed Free ${PIECE_NAMES[target.type]} on ${parsedBest.to}`, detail: `${bestMoveSan} captured an undefended ${PIECE_NAMES[target.type]} instead of ${san}.`, tacticalTag: 'Missed Capture' };
    }
  }

  return {
    headline: `${prefix}: Better was ${bestMoveSan}`,
    detail: `${san} swings evaluation (${evalBefore.display} → ${evalAfter.display}). ${bestMoveSan} kept stronger control.`,
    tacticalTag: classification === 'blunder' ? 'Eval Collapse' : 'Suboptimal',
  };
}
