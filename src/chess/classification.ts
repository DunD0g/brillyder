import { Chess, type PieceSymbol, type Square } from 'chess.js';
import type {
  AnalyzedGame,
  AnalyzedPly,
  EngineEval,
  LichessGameRecord,
  MoveClassification,
  PlayerAnalysisSummary,
  PlayerColor,
} from '../types/chess';
import {
  calculateGameAccuracy,
  calculateMoveAccuracy,
  countNonPawnMaterial,
  estimateGameElo,
  extractClockFromComment,
  getMoverWinPercent,
  uciLineToSan,
} from '../utils/chessMath';
import { generateMoveExplanation } from './moveCoach';
import { isBookPly, lookupOpeningByMoves } from './openingBook';

const PIECE_VAL: Record<PieceSymbol, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };

function sideMaterial(fen: string, color: PlayerColor): number {
  const c = new Chess(fen);
  let total = 0;
  for (const row of c.board()) {
    for (const cell of row) {
      if (cell && cell.color === color) total += PIECE_VAL[cell.type];
    }
  }
  return total;
}

function isSacrificeMove(
  beforeFen: string,
  afterFen: string,
  mover: PlayerColor,
  toSquare: string,
  movedPiece: PieceSymbol,
  capturedPiece: PieceSymbol | undefined,
  prevToSquare: string | undefined
): boolean {
  if (prevToSquare && toSquare === prevToSquare && capturedPiece) return false;
  const opp: PlayerColor = mover === 'w' ? 'b' : 'w';
  const netBefore = sideMaterial(beforeFen, mover) - sideMaterial(beforeFen, opp);
  const netAfter = sideMaterial(afterFen, mover) - sideMaterial(afterFen, opp);
  if (netAfter - netBefore <= -2) return true;

  const after = new Chess(afterFen);
  const attackers = after.attackers(toSquare as Square, opp);
  const defenders = after.attackers(toSquare as Square, mover);
  if (PIECE_VAL[movedPiece] >= 3 && attackers.length > 0 && PIECE_VAL[movedPiece] > (capturedPiece ? PIECE_VAL[capturedPiece] : 0)) {
    if (defenders.length === 0) return true;
    for (const sq of attackers) {
      const p = after.get(sq);
      if (p && PIECE_VAL[p.type] < PIECE_VAL[movedPiece]) return true;
    }
  }
  return false;
}

export function classifyMove(params: {
  plyIndex: number;
  sanPrefix: string[];
  lichessOpeningPly?: number;
  playedUci: string;
  bestMoveUci: string;
  beforeFen: string;
  afterFen: string;
  moverColor: PlayerColor;
  toSquare: string;
  movedPiece: PieceSymbol;
  capturedPiece?: PieceSymbol;
  prevMoveToSquare?: string;
  moverWinBefore: number;
  moverWinAfter: number;
  secondBestGapWin: number;
  hasSecondLine: boolean;
  missedMate: boolean;
  walkedIntoMate: boolean;
}): MoveClassification {
  const rawLoss = Math.max(0, params.moverWinBefore - params.moverWinAfter);
  const winLoss = params.playedUci === params.bestMoveUci ? 0 : rawLoss;

  if (isBookPly(params.plyIndex, params.sanPrefix, params.lichessOpeningPly, winLoss)) return 'book';
  if (params.walkedIntoMate || (params.missedMate && winLoss > 12) || winLoss > 30) return 'blunder';
  if (winLoss > 18) return 'mistake';
  if (winLoss > 10) return 'inaccuracy';

  const brilliant =
    winLoss <= 2 &&
    params.moverWinAfter >= 45 &&
    params.moverWinBefore < 94 &&
    params.hasSecondLine &&
    params.secondBestGapWin >= 6 &&
    isSacrificeMove(params.beforeFen, params.afterFen, params.moverColor, params.toSquare, params.movedPiece, params.capturedPiece, params.prevMoveToSquare);

  if (brilliant) return 'brilliant';
  if (winLoss <= 2 && params.hasSecondLine && params.secondBestGapWin > 10 && params.moverWinBefore < 95) return 'great';
  if (params.playedUci === params.bestMoveUci || winLoss <= 2) return 'best';
  return 'excellent';
}

export function computePlayerStats(
  plies: AnalyzedPly[],
  color: PlayerColor,
  playerRating: number | undefined,
  opponentRating: number | undefined,
  resultString: string
): PlayerAnalysisSummary {
  const counts: Record<MoveClassification, number> = {
    brilliant: 0, great: 0, best: 0, excellent: 0, inaccuracy: 0, mistake: 0, blunder: 0, book: 0,
  };
  const sidePlies = plies.filter((p) => p.color === color);
  const accs: number[] = [];
  const winPcts: number[] = [];
  let lossSum = 0;
  for (const p of sidePlies) {
    counts[p.classification]++;
    accs.push(p.accuracy);
    winPcts.push(p.evalBefore.winPercentWhite);
    lossSum += p.winLoss;
  }
  const accuracy = calculateGameAccuracy(accs, winPcts);
  const resultScore: 1 | 0.5 | 0 =
    resultString === '1/2-1/2' ? 0.5 : (color === 'w' && resultString === '1-0') || (color === 'b' && resultString === '0-1') ? 1 : 0;
  return {
    accuracy,
    estimatedElo: estimateGameElo(playerRating, opponentRating, accuracy, resultScore),
    counts,
    avgWinLoss: sidePlies.length > 0 ? Number((lossSum / sidePlies.length).toFixed(1)) : 0,
  };
}

export function loadPgnSafely(pgn: string): Chess {
  const chess = new Chess();
  try {
    chess.loadPgn(pgn);
    return chess;
  } catch {
    let stripped = '';
    let depth = 0;
    for (const ch of pgn) {
      if (ch === '(') depth++;
      else if (ch === ')') depth = Math.max(0, depth - 1);
      else if (depth === 0) stripped += ch;
    }
    chess.loadPgn(stripped);
    return chess;
  }
}

export function buildAnalyzedGame(game: LichessGameRecord, evals: EngineEval[], depth: number): AnalyzedGame {
  const chess = loadPgnSafely(game.pgn);
  const commentsMap = new Map<string, string>();
  for (const entry of chess.getComments()) commentsMap.set(entry.fen, entry.comment);

  const moves = chess.history({ verbose: true });
  const sanList = moves.map((m) => m.san);
  const openingLookup = lookupOpeningByMoves(sanList);
  const plies: AnalyzedPly[] = [];
  let prevTo: string | undefined;

  for (let i = 0; i < moves.length; i++) {
    const mv = moves[i];
    const evalBefore = evals[i];
    const evalAfter = evals[i + 1];
    const color: PlayerColor = mv.color;
    const playedUci = `${mv.from}${mv.to}${mv.promotion ?? ''}`;
    const bestMoveUci = evalBefore.bestMoveUci || playedUci;
    const bestMoveSan = uciLineToSan(mv.before, [bestMoveUci], 1)[0] || mv.san;
    const bestPvSan = uciLineToSan(mv.before, evalBefore.pv, 5);
    const threatMoveUci = evalAfter?.bestMoveUci;
    const threatMoveSan = threatMoveUci ? uciLineToSan(mv.after, [threatMoveUci], 1)[0] : undefined;

    const moverWinBefore = getMoverWinPercent(evalBefore.score, color);
    const moverWinAfter = getMoverWinPercent(evalAfter.score, color);
    const winLoss = playedUci === bestMoveUci ? 0 : Math.max(0, Number((moverWinBefore - moverWinAfter).toFixed(2)));

    const line1 = evalBefore.lines.find((l) => l.multipv === 1);
    const line2 = evalBefore.lines.find((l) => l.multipv === 2);
    const hasSecondLine = Boolean(line1 && line2);
    const secondBestGapWin = line1 && line2 ? Math.max(0, getMoverWinPercent(line1.score, color) - getMoverWinPercent(line2.score, color)) : 0;

    const moverHadMate = evalBefore.score.mateWhite !== null && ((color === 'w' && evalBefore.score.mateWhite > 0) || (color === 'b' && evalBefore.score.mateWhite < 0));
    const moverHasMate = evalAfter.score.isCheckmate || (evalAfter.score.mateWhite !== null && ((color === 'w' && evalAfter.score.mateWhite > 0) || (color === 'b' && evalAfter.score.mateWhite < 0)));
    const oppHasMate = evalAfter.score.mateWhite !== null && ((color === 'w' && evalAfter.score.mateWhite < 0) || (color === 'b' && evalAfter.score.mateWhite > 0));

    const classification = classifyMove({
      plyIndex: i,
      sanPrefix: sanList.slice(0, i + 1),
      lichessOpeningPly: game.openingPly,
      playedUci,
      bestMoveUci,
      beforeFen: mv.before,
      afterFen: mv.after,
      moverColor: color,
      toSquare: mv.to,
      movedPiece: mv.piece,
      capturedPiece: mv.captured,
      prevMoveToSquare: prevTo,
      moverWinBefore,
      moverWinAfter,
      secondBestGapWin,
      hasSecondLine,
      missedMate: moverHadMate && !moverHasMate,
      walkedIntoMate: oppHasMate && moverWinBefore > 15,
    });

    const accuracy = classification === 'book' ? 100 : calculateMoveAccuracy(winLoss);
    const nonPawnMat = countNonPawnMaterial(mv.before);
    const phase: 'opening' | 'middlegame' | 'endgame' =
      i < 16 || classification === 'book' ? 'opening' : nonPawnMat <= 24 ? 'endgame' : 'middlegame';

    const coaching = generateMoveExplanation({
      beforeFen: mv.before,
      afterFen: mv.after,
      san: mv.san,
      uci: playedUci,
      color,
      bestMoveUci,
      bestMoveSan,
      threatMoveUci,
      evalBefore: evalBefore.score,
      evalAfter: evalAfter.score,
      classification,
      openingName: game.openingName !== 'Unknown Opening' ? game.openingName : openingLookup?.name,
    });

    plies.push({
      ply: i + 1,
      moveNumber: Math.floor(i / 2) + 1,
      color,
      san: mv.san,
      uci: playedUci,
      from: mv.from,
      to: mv.to,
      promotion: mv.promotion,
      captured: mv.captured,
      beforeFen: mv.before,
      afterFen: mv.after,
      clockText: extractClockFromComment(commentsMap.get(mv.after)),
      bestMoveUci,
      bestMoveSan,
      bestPvSan,
      threatMoveUci,
      threatMoveSan,
      evalBefore: evalBefore.score,
      evalAfter: evalAfter.score,
      secondBestGapWin: Number(secondBestGapWin.toFixed(1)),
      winLoss,
      accuracy,
      classification,
      phase,
      coaching,
    });
    prevTo = mv.to;
  }

  return {
    id: game.id,
    analyzedAt: Date.now(),
    depth,
    game,
    initialEval: evals[0].score,
    plies,
    whiteSummary: computePlayerStats(plies, 'w', game.white.rating, game.black.rating, game.resultString),
    blackSummary: computePlayerStats(plies, 'b', game.black.rating, game.white.rating, game.resultString),
    openingLineDetected: openingLookup?.name,
  };
}
