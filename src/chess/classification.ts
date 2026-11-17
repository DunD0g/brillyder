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
  extractClockSeconds,
  getMoverWinPercent,
  uciLineToSan,
} from '../utils/chessMath';
import { generateMoveExplanation } from './moveCoach';
import { isBookPly, lookupOpeningByMoves } from './openingBook';

const SEE_VALUE: Record<PieceSymbol, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 1000 };
const SEE_MAX_DEPTH = 8;
const SACRIFICE_MIN_GAIN = 2;

export const CLASSIFICATION_VERSION = 2;

export function fenPositionKey(fen: string): string {
  return fen.split(' ').slice(0, 4).join(' ');
}

/**
 * Static exchange evaluation for one square. Returns the best net material gain
 * for the side to move if it starts capturing on `target`. Both sides may stop
 * at any point, and only legal captures are considered, so a king cannot take a
 * defended piece and pinned defenders cannot recapture.
 */
function bestCaptureGain(chess: Chess, target: Square, depth: number): number {
  if (depth <= 0) return 0;
  const captures = chess.moves({ verbose: true }).filter((m) => m.to === target && m.captured);
  if (captures.length === 0) return 0;

  let best = 0;
  for (const capture of captures) {
    if (!capture.captured) continue;
    const next = new Chess(chess.fen());
    next.move({ from: capture.from, to: capture.to, promotion: capture.promotion });
    const replyGain = bestCaptureGain(next, target, depth - 1);
    const gain = SEE_VALUE[capture.captured] - replyGain;
    if (gain > best) best = gain;
  }
  return best;
}

/**
 * A move is a sacrifice only when the opponent has a legal capture that wins at
 * least a minor piece's worth of material even after the best recapture, and the
 * mover did not already capture equal value on that square. A merely attacked
 * piece (e.g. a defended rook giving check) is not a sacrifice.
 */
export function isSacrificeMove(
  _beforeFen: string,
  afterFen: string,
  mover: PlayerColor,
  toSquare: string,
  movedPiece: PieceSymbol,
  capturedPiece?: PieceSymbol
): boolean {
  if (movedPiece === 'k') return false;
  const after = new Chess(afterFen);
  if (after.turn() === mover) return false;
  const opponentGain = bestCaptureGain(after, toSquare as Square, SEE_MAX_DEPTH);
  const capturedValue = capturedPiece ? SEE_VALUE[capturedPiece] : 0;
  return opponentGain - capturedValue >= SACRIFICE_MIN_GAIN;
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
  positionRepeated: boolean;
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
    !params.missedMate &&
    !params.positionRepeated &&
    params.moverWinAfter >= 45 &&
    params.moverWinBefore < 94 &&
    params.hasSecondLine &&
    params.secondBestGapWin >= 6 &&
    isSacrificeMove(params.beforeFen, params.afterFen, params.moverColor, params.toSquare, params.movedPiece, params.capturedPiece);

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
  const seenPositions = new Set<string>();
  if (moves.length > 0) seenPositions.add(fenPositionKey(moves[0].before));

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

    const afterPositionKey = fenPositionKey(mv.after);
    const positionRepeated = seenPositions.has(afterPositionKey);
    seenPositions.add(afterPositionKey);

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
      positionRepeated,
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
      clockSeconds: extractClockSeconds(commentsMap.get(mv.after)),
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
  }

  return {
    id: game.id,
    analyzedAt: Date.now(),
    depth,
    classificationVersion: CLASSIFICATION_VERSION,
    game,
    initialEval: evals[0].score,
    plies,
    whiteSummary: computePlayerStats(plies, 'w', game.white.rating, game.black.rating, game.resultString),
    blackSummary: computePlayerStats(plies, 'b', game.black.rating, game.white.rating, game.resultString),
    openingLineDetected: openingLookup?.name,
  };
}

/**
 * Re-checks saved brilliant moves against the current sacrifice/repetition
 * rules. Older reviews were produced by a heuristic that could tag a merely
 * attacked piece as brilliant, so those classifications are downgraded until
 * the game is re-analyzed.
 */
export function refreshBrilliantClassifications(analyzed: AnalyzedGame): AnalyzedGame {
  if ((analyzed.classificationVersion ?? 0) >= CLASSIFICATION_VERSION) return analyzed;

  const seenPositions = new Set<string>();
  if (analyzed.plies.length > 0) seenPositions.add(fenPositionKey(analyzed.plies[0].beforeFen));

  const plies = analyzed.plies.map((ply) => {
    const positionKey = fenPositionKey(ply.afterFen);
    const repeated = seenPositions.has(positionKey);
    seenPositions.add(positionKey);
    if (ply.classification !== 'brilliant') return ply;

    const movedPiece = new Chess(ply.beforeFen).get(ply.from as Square)?.type;
    const sacrifice = movedPiece
      ? isSacrificeMove(ply.beforeFen, ply.afterFen, ply.color, ply.to, movedPiece, ply.captured as PieceSymbol | undefined)
      : false;
    if (sacrifice && !repeated) return ply;

    const moverWinBefore = getMoverWinPercent(ply.evalBefore, ply.color);
    const classification: MoveClassification =
      ply.winLoss <= 2 && ply.secondBestGapWin > 10 && moverWinBefore < 95
        ? 'great'
        : ply.uci === ply.bestMoveUci || ply.winLoss <= 2
          ? 'best'
          : 'excellent';
    const coaching = generateMoveExplanation({
      beforeFen: ply.beforeFen,
      afterFen: ply.afterFen,
      san: ply.san,
      uci: ply.uci,
      color: ply.color,
      bestMoveUci: ply.bestMoveUci,
      bestMoveSan: ply.bestMoveSan,
      threatMoveUci: ply.threatMoveUci,
      evalBefore: ply.evalBefore,
      evalAfter: ply.evalAfter,
      classification,
      openingName: analyzed.openingLineDetected || analyzed.game.openingName,
    });
    return { ...ply, classification, coaching };
  });

  return {
    ...analyzed,
    classificationVersion: CLASSIFICATION_VERSION,
    plies,
    whiteSummary: computePlayerStats(plies, 'w', analyzed.game.white.rating, analyzed.game.black.rating, analyzed.game.resultString),
    blackSummary: computePlayerStats(plies, 'b', analyzed.game.black.rating, analyzed.game.white.rating, analyzed.game.resultString),
  };
}
