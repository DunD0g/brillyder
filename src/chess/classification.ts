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
  computeMoveTimeSpent,
  countNonPawnMaterial,
  estimateGameElo,
  extractClockFromComment,
  extractClockSeconds,
  getMoverWinPercent,
  parsePgnTimeControl,
  uciLineToSan,
} from '../utils/chessMath';
import { generateMoveExplanation } from './moveCoach';
import { isBookPly, lookupOpeningByMoves } from './openingBook';
import { detectShortMate, legalCaptureGainOnSquare } from './tacticalMotifs';

const SEE_VALUE: Record<PieceSymbol, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 1000 };
const SEE_MAX_DEPTH = 6;
const SACRIFICE_MIN_GAIN = 2;

export const CLASSIFICATION_VERSION = 3;

export function fenPositionKey(fen: string): string {
  return fen.split(' ').slice(0, 4).join(' ');
}

/**
 * A move is a sacrifice when:
 * 1. Active sacrifice: the opponent has a legal capture on `toSquare` that wins
 *    at least a minor piece's worth of material beyond what the mover captured
 *    (and beyond any pawn promotion value gained on the move — so `bxa8=Q Kxa8`
 *    is NOT falsely treated as a Queen sacrifice!), OR
 * 2. Passive sacrifice: the mover leaves another friendly non-pawn piece en prise
 *    (net legal capture gain >= SACRIFICE_MIN_GAIN beyond any material captured on this move)
 *    to pursue a stronger tactical/mating initiative.
 */
export function isSacrificeMove(
  _beforeFen: string,
  afterFen: string,
  mover: PlayerColor,
  toSquare: string,
  movedPiece: PieceSymbol,
  capturedPiece?: PieceSymbol,
  promotionPiece?: PieceSymbol
): boolean {
  const after = new Chess(afterFen);
  if (after.turn() === mover) return false;

  const capturedValue = capturedPiece ? SEE_VALUE[capturedPiece] : 0;
  // On a pawn promotion (e.g. bxa8=Q), the mover only risked a pawn (1), not a queen (9)
  const promoSurplus =
    movedPiece === 'p' && promotionPiece ? Math.max(0, SEE_VALUE[promotionPiece] - SEE_VALUE.p) : 0;

  // 1. Active sacrifice on destination square (kings cannot sacrifice themselves)
  if (movedPiece !== 'k') {
    const opponentGainOnDest = legalCaptureGainOnSquare(after, toSquare as Square, SEE_MAX_DEPTH);
    const netRiskedOnDest = opponentGainOnDest - promoSurplus - capturedValue;
    if (netRiskedOnDest >= SACRIFICE_MIN_GAIN) return true;
  }

  // 2. Passive sacrifice: leaving another friendly non-pawn piece legally capturable for >= 2 net material
  for (const row of after.board()) {
    for (const cell of row) {
      if (!cell || cell.color !== mover || cell.type === 'k' || cell.type === 'p') continue;
      if (cell.square === toSquare) continue;
      const oppGain = legalCaptureGainOnSquare(after, cell.square, SEE_MAX_DEPTH);
      if (oppGain - capturedValue >= SACRIFICE_MIN_GAIN) {
        return true;
      }
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
  promotionPiece?: PieceSymbol;
  positionRepeated: boolean;
  moverWinBefore: number;
  moverWinAfter: number;
  secondBestGapWin: number;
  hasSecondLine: boolean;
  missedMate: boolean;
  missedShortMate?: boolean;
  walkedIntoMate: boolean;
}): MoveClassification {
  const isTopMove = params.playedUci === params.bestMoveUci;
  const rawLoss = Math.max(0, params.moverWinBefore - params.moverWinAfter);
  const winLoss = isTopMove ? 0 : rawLoss;

  if (isBookPly(params.plyIndex, params.sanPrefix, params.lichessOpeningPly, winLoss)) return 'book';

  // Never blame Stockfish's #1 best move for walking into forced mate (horizon/depth effect)
  const walkedIntoMateError = params.walkedIntoMate && !isTopMove;
  if (walkedIntoMateError || (params.missedMate && winLoss > 12) || winLoss > 30) return 'blunder';

  // Missing a forced Mate in 1–3 should never be praised as Best/Great/Brilliant
  if (params.missedShortMate && !isTopMove) {
    if (winLoss > 4) return 'mistake';
    return 'inaccuracy';
  }

  if (winLoss > 18) return 'mistake';
  if (winLoss > 10) return 'inaccuracy';

  const brilliant =
    isTopMove &&
    winLoss <= 2 &&
    !params.missedMate &&
    !params.positionRepeated &&
    params.moverWinAfter >= 45 &&
    params.moverWinBefore < 94 &&
    params.hasSecondLine &&
    params.secondBestGapWin >= 6 &&
    isSacrificeMove(
      params.beforeFen,
      params.afterFen,
      params.moverColor,
      params.toSquare,
      params.movedPiece,
      params.capturedPiece,
      params.promotionPiece
    );

  if (brilliant) return 'brilliant';
  if (
    isTopMove &&
    winLoss <= 2 &&
    !params.missedMate &&
    params.hasSecondLine &&
    params.secondBestGapWin > 10 &&
    params.moverWinBefore < 95
  ) {
    return 'great';
  }
  if (isTopMove || winLoss <= 2) return 'best';
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
  if (sidePlies.length === 0) {
    return {
      accuracy: 0,
      estimatedElo: playerRating ?? opponentRating ?? 1500,
      counts,
      avgWinLoss: 0,
    };
  }

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
    resultString === '1/2-1/2' || resultString === '*'
      ? 0.5
      : (color === 'w' && resultString === '1-0') || (color === 'b' && resultString === '0-1')
        ? 1
        : 0;
  return {
    accuracy,
    estimatedElo: estimateGameElo(playerRating, opponentRating, accuracy, resultScore),
    counts,
    avgWinLoss: Number((lossSum / sidePlies.length).toFixed(1)),
  };
}

/**
 * Strips parenthesized RAV variations ONLY outside PGN header tags `[...]`
 * and brace comments `{...}` so headers like `[Event "Blitz (3+0)"]` stay intact.
 */
function stripPgnVariationsSafely(pgn: string): string {
  let out = '';
  let inHeader = false;
  let inHeaderQuote = false;
  let inBrace = false;
  let parenDepth = 0;

  for (let i = 0; i < pgn.length; i++) {
    const ch = pgn[i];
    if (inBrace) {
      if (parenDepth === 0) out += ch;
      if (ch === '}') inBrace = false;
      continue;
    }
    if (inHeader) {
      out += ch;
      if (ch === '"' && pgn[i - 1] !== '\\') inHeaderQuote = !inHeaderQuote;
      else if (ch === ']' && !inHeaderQuote) inHeader = false;
      continue;
    }
    if (ch === '[' && parenDepth === 0) {
      inHeader = true;
      out += ch;
      continue;
    }
    if (ch === '{') {
      inBrace = true;
      if (parenDepth === 0) out += ch;
      continue;
    }
    if (ch === '(') {
      parenDepth++;
      continue;
    }
    if (ch === ')') {
      parenDepth = Math.max(0, parenDepth - 1);
      continue;
    }
    if (parenDepth === 0) out += ch;
  }
  return out;
}

export function loadPgnSafely(pgn: string): Chess {
  const chess = new Chess();
  try {
    chess.loadPgn(pgn);
    return chess;
  } catch {
    chess.loadPgn(stripPgnVariationsSafely(pgn));
    return chess;
  }
}

export function buildAnalyzedGame(
  game: LichessGameRecord,
  evals: EngineEval[],
  depth: number,
  deepenedIndices?: Set<number>
): AnalyzedGame {
  const chess = loadPgnSafely(game.pgn);
  const commentsMap = new Map<string, string>();
  for (const entry of chess.getComments()) commentsMap.set(entry.fen, entry.comment);
  const timeControl = parsePgnTimeControl(game.pgn, game.timeControlLabel);

  const moves = chess.history({ verbose: true });
  const sanList = moves.map((m) => m.san);
  const openingLookup = lookupOpeningByMoves(sanList);
  const plies: AnalyzedPly[] = [];
  const seenPositions = new Set<string>();
  const lastClockByColor: Record<PlayerColor, number | undefined> = {
    w: timeControl.baseSeconds ?? undefined,
    b: timeControl.baseSeconds ?? undefined,
  };
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

    const topLines = evalBefore.lines.slice(0, 3).map((l) => {
      const pvSan = uciLineToSan(mv.before, l.pv, 4);
      return {
        san: pvSan[0] || l.bestMoveUci,
        evalDisplay: l.score.display,
        pvSan,
      };
    });

    const moverWinBefore = getMoverWinPercent(evalBefore.score, color);
    const moverWinAfter = getMoverWinPercent(evalAfter.score, color);
    const winLoss = playedUci === bestMoveUci ? 0 : Math.max(0, Number((moverWinBefore - moverWinAfter).toFixed(2)));

    const line1 = evalBefore.lines.find((l) => l.multipv === 1);
    const line2 = evalBefore.lines.find((l) => l.multipv === 2);
    const hasSecondLine = Boolean(line1 && line2);
    const secondBestGapWin = line1 && line2 ? Math.max(0, getMoverWinPercent(line1.score, color) - getMoverWinPercent(line2.score, color)) : 0;
    const sign = color === 'w' ? 1 : -1;
    const cp1 = line1 ? Math.max(-1200, Math.min(1200, line1.score.cpWhite * sign)) : 0;
    const cp2 = line2 ? Math.max(-1200, Math.min(1200, line2.score.cpWhite * sign)) : 0;
    const secondBestGapPawns = line1 && line2 ? Number((Math.max(0, cp1 - cp2) / 100).toFixed(2)) : 0;

    const moverHadMate =
      evalBefore.score.mateWhite !== null &&
      evalBefore.score.mateWhite !== 0 &&
      ((color === 'w' && evalBefore.score.mateWhite > 0) || (color === 'b' && evalBefore.score.mateWhite < 0));
    const moverHasMate =
      evalAfter.score.isCheckmate ||
      (evalAfter.score.mateWhite !== null &&
        evalAfter.score.mateWhite !== 0 &&
        ((color === 'w' && evalAfter.score.mateWhite > 0) || (color === 'b' && evalAfter.score.mateWhite < 0)));
    const oppHadMate =
      evalBefore.score.mateWhite !== null &&
      evalBefore.score.mateWhite !== 0 &&
      ((color === 'w' && evalBefore.score.mateWhite < 0) || (color === 'b' && evalBefore.score.mateWhite > 0));
    const oppHasMate =
      evalAfter.score.mateWhite !== null &&
      evalAfter.score.mateWhite !== 0 &&
      ((color === 'w' && evalAfter.score.mateWhite < 0) || (color === 'b' && evalAfter.score.mateWhite > 0));
    const hadShortMate = detectShortMate(evalBefore.score, color) !== null;
    const stillShortMate = evalAfter.score.isCheckmate || detectShortMate(evalAfter.score, color) !== null;

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
      promotionPiece: mv.promotion,
      positionRepeated,
      moverWinBefore,
      moverWinAfter,
      secondBestGapWin,
      hasSecondLine,
      missedMate: moverHadMate && !moverHasMate,
      missedShortMate: hadShortMate && !stillShortMate,
      walkedIntoMate: oppHasMate && !oppHadMate && moverWinBefore > 15,
    });

    const moveNumber = Math.floor(i / 2) + 1;
    const clockText = extractClockFromComment(commentsMap.get(mv.after));
    const clockSeconds = extractClockSeconds(commentsMap.get(mv.after));
    const prevClock = lastClockByColor[color];
    const timeSpentSeconds = computeMoveTimeSpent(
      prevClock,
      clockSeconds,
      timeControl.incrementSeconds,
      moveNumber === 1
    );
    if (clockSeconds !== undefined) lastClockByColor[color] = clockSeconds;

    let clockTag: 'impulse' | 'time-trouble' | undefined;
    if (classification === 'blunder' || classification === 'mistake') {
      if (clockSeconds !== undefined && clockSeconds < 60) {
        clockTag = 'time-trouble';
      } else if (
        timeSpentSeconds !== undefined &&
        timeSpentSeconds < 5 &&
        (prevClock ?? clockSeconds ?? 0) > 180
      ) {
        clockTag = 'impulse';
      }
    }

    const isCriticalMoment = hasSecondLine && secondBestGapPawns >= 2.0;
    const isClutchSave =
      isCriticalMoment &&
      playedUci === bestMoveUci &&
      !positionRepeated &&
      winLoss <= 2 &&
      moverWinAfter >= 30 &&
      moverWinBefore < 88 &&
      (classification === 'best' || classification === 'great' || classification === 'brilliant') &&
      (moverWinBefore <= 62 || (clockSeconds !== undefined && clockSeconds <= 90));

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
      bestPvUci: evalBefore.pv,
      threatMoveUci,
      threatMoveSan,
      evalBefore: evalBefore.score,
      evalAfter: evalAfter.score,
      secondBestGapPawns,
      isClutchSave,
      classification,
      openingName: game.openingName !== 'Unknown Opening' ? game.openingName : openingLookup?.name,
    });

    plies.push({
      ply: i + 1,
      moveNumber,
      color,
      san: mv.san,
      uci: playedUci,
      from: mv.from,
      to: mv.to,
      promotion: mv.promotion,
      captured: mv.captured,
      beforeFen: mv.before,
      afterFen: mv.after,
      clockText,
      clockSeconds,
      timeSpentSeconds,
      clockTag,
      bestMoveUci,
      bestMoveSan,
      bestPvSan,
      topLines,
      threatMoveUci,
      threatMoveSan,
      evalBefore: evalBefore.score,
      evalAfter: evalAfter.score,
      secondBestGapWin: Number(secondBestGapWin.toFixed(1)),
      secondBestGapPawns,
      isCriticalMoment,
      isClutchSave,
      deepened: deepenedIndices?.has(i) ?? false,
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
 * Re-checks saved brilliant & clutch classifications against the current sacrifice,
 * promotion, repetition, and viability rules so older cached reviews upgrade cleanly.
 */
export function refreshBrilliantClassifications(analyzed: AnalyzedGame): AnalyzedGame {
  if ((analyzed.classificationVersion ?? 0) >= CLASSIFICATION_VERSION) return analyzed;

  const seenPositions = new Set<string>();
  if (analyzed.plies.length > 0) seenPositions.add(fenPositionKey(analyzed.plies[0].beforeFen));

  const plies = analyzed.plies.map((ply) => {
    const positionKey = fenPositionKey(ply.afterFen);
    const repeated = seenPositions.has(positionKey);
    seenPositions.add(positionKey);

    const moverWinBefore = getMoverWinPercent(ply.evalBefore, ply.color);
    const moverWinAfter = getMoverWinPercent(ply.evalAfter, ply.color);
    let classification = ply.classification;
    let isClutchSave = ply.isClutchSave;
    let changed = false;

    if (classification === 'brilliant') {
      const movedPiece = new Chess(ply.beforeFen).get(ply.from as Square)?.type;
      const sacrifice = movedPiece
        ? isSacrificeMove(
            ply.beforeFen,
            ply.afterFen,
            ply.color,
            ply.to,
            movedPiece,
            ply.captured as PieceSymbol | undefined,
            ply.promotion as PieceSymbol | undefined
          )
        : false;
      const validBrilliant =
        sacrifice &&
        !repeated &&
        ply.uci === ply.bestMoveUci &&
        ply.winLoss <= 2 &&
        moverWinAfter >= 45 &&
        moverWinBefore < 94 &&
        ply.secondBestGapWin >= 6;

      if (!validBrilliant) {
        classification =
          ply.uci === ply.bestMoveUci && ply.winLoss <= 2 && ply.secondBestGapWin > 10 && moverWinBefore < 95
            ? 'great'
            : ply.uci === ply.bestMoveUci || ply.winLoss <= 2
              ? 'best'
              : 'excellent';
        changed = true;
      }
    }

    if (isClutchSave) {
      const validClutch =
        !repeated &&
        ply.uci === ply.bestMoveUci &&
        moverWinAfter >= 30 &&
        moverWinBefore < 88 &&
        (classification === 'best' || classification === 'great' || classification === 'brilliant');
      if (!validClutch) {
        isClutchSave = false;
        changed = true;
      }
    }

    if (!changed) return ply;

    const coaching = generateMoveExplanation({
      beforeFen: ply.beforeFen,
      afterFen: ply.afterFen,
      san: ply.san,
      uci: ply.uci,
      color: ply.color,
      bestMoveUci: ply.bestMoveUci,
      bestMoveSan: ply.bestMoveSan,
      threatMoveUci: ply.threatMoveUci,
      threatMoveSan: ply.threatMoveSan,
      evalBefore: ply.evalBefore,
      evalAfter: ply.evalAfter,
      secondBestGapPawns: ply.secondBestGapPawns,
      isClutchSave,
      classification,
      openingName: analyzed.openingLineDetected || analyzed.game.openingName,
    });
    return { ...ply, classification, isClutchSave, coaching };
  });

  return {
    ...analyzed,
    classificationVersion: CLASSIFICATION_VERSION,
    plies,
    whiteSummary: computePlayerStats(plies, 'w', analyzed.game.white.rating, analyzed.game.black.rating, analyzed.game.resultString),
    blackSummary: computePlayerStats(plies, 'b', analyzed.game.black.rating, analyzed.game.white.rating, analyzed.game.resultString),
  };
}
