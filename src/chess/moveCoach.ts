import { Chess, type Square } from 'chess.js';
import type { CoachingExplanation, EngineScore, MoveClassification, PlayerColor } from '../types/chess';
import { getMoverWinPercent, uciToSquares } from '../utils/chessMath';
import {
  detectBackRankThreat,
  detectDeflection,
  detectDiscoveredAttack,
  detectForkOnMove,
  detectPinOrSkewer,
  detectShortMate,
  findHangingPieces,
  legalCaptureGainOnSquare,
  PIECE_NAMES,
  PIECE_VAL,
} from './tacticalMotifs';

export function generateMoveExplanation(params: {
  beforeFen: string;
  afterFen: string;
  san: string;
  uci: string;
  color: PlayerColor;
  bestMoveUci: string;
  bestMoveSan: string;
  bestPvUci?: string[];
  threatMoveUci?: string;
  threatMoveSan?: string;
  evalBefore: EngineScore;
  evalAfter: EngineScore;
  secondBestGapPawns?: number;
  isClutchSave?: boolean;
  classification: MoveClassification;
  openingName?: string;
}): CoachingExplanation {
  const {
    beforeFen,
    afterFen,
    san,
    uci,
    color,
    bestMoveUci,
    bestMoveSan,
    bestPvUci,
    threatMoveUci,
    threatMoveSan,
    evalBefore,
    evalAfter,
    secondBestGapPawns = 0,
    isClutchSave = false,
    classification,
    openingName,
  } = params;
  const oppColor: PlayerColor = color === 'w' ? 'b' : 'w';
  const chessBefore = new Chess(beforeFen);
  const chessAfter = new Chess(afterFen);
  const moverWinBefore = getMoverWinPercent(evalBefore, color);
  const moverWinAfter = getMoverWinPercent(evalAfter, color);
  const matchesBest = uci === bestMoveUci;

  if (classification === 'book') {
    return {
      headline: `Book Move — ${san}`,
      detail: openingName
        ? `Standard theory in the ${openingName}. Builds harmonious development.`
        : 'Follows established opening theory.',
      tacticalTag: 'Theory',
    };
  }

  if (classification === 'brilliant') {
    const deflection = detectDeflection(chessBefore, uci, color, bestPvUci);
    return {
      headline: `Brilliant! ${san}`,
      detail: deflection
        ? `Bold sacrifice deflecting the ${PIECE_NAMES[deflection.targetPiece]} on ${deflection.targetSq} for a winning initiative.`
        : 'Sacrifices material while keeping a sharp, winning initiative — pure BrillyDer precision.',
      tacticalTag: deflection ? 'Deflection' : 'Sacrifice',
    };
  }

  const showClutchOrGreat =
    classification === 'great' ||
    (isClutchSave && (classification === 'best' || classification === 'excellent'));

  if (showClutchOrGreat) {
    const fork = detectForkOnMove(chessBefore, uci, color);
    const pin = detectPinOrSkewer(chessBefore, uci, color);
    const disc = detectDiscoveredAttack(chessBefore, uci, color);
    const tonePrefix = moverWinAfter >= 65 ? 'Only winning move' : 'Critical resource';
    if (fork) {
      return {
        headline: `${isClutchSave ? 'Clutch Save!' : 'Great Move!'} ${san}`,
        detail: `${tonePrefix} — launches a ${PIECE_NAMES[fork.piece]} fork on ${fork.targetSquare} hitting ${fork.victims.slice(0, 2).join(' and ')}.`,
        tacticalTag: 'Fork',
      };
    }
    if (pin) {
      return {
        headline: `${isClutchSave ? 'Clutch Save!' : 'Great Move!'} ${san}`,
        detail: `${pin.kind}s the ${PIECE_NAMES[pin.frontPiece]} on ${pin.frontSq} against the ${PIECE_NAMES[pin.backPiece]} on ${pin.backSq}.`,
        tacticalTag: 'Pin/Skewer',
      };
    }
    if (disc) {
      return {
        headline: `${isClutchSave ? 'Clutch Save!' : 'Great Move!'} ${san}`,
        detail: `Unleashes a discovered attack from the ${PIECE_NAMES[disc.slider]} on ${disc.sliderSq} onto the ${PIECE_NAMES[disc.target]} on ${disc.targetSq}.`,
        tacticalTag: 'Discovered Attack',
      };
    }
    const positionGoal =
      moverWinBefore >= 65
        ? 'to keep a winning advantage'
        : moverWinBefore >= 40
          ? 'to hold the position'
          : 'to stay in the fight';
    return {
      headline: isClutchSave ? `Clutch Save! ${san}` : `Great Move! ${san}`,
      detail: secondBestGapPawns >= 2
        ? `Only move ${positionGoal} (next best alternative drops ${secondBestGapPawns.toFixed(1)} pawns).`
        : `The only move ${positionGoal}; alternatives lose substantial ground.`,
      tacticalTag: 'Only Move Save',
    };
  }

  if (classification === 'best' || classification === 'excellent') {
    if (evalAfter.isCheckmate) {
      return { headline: `Checkmate! ${san}`, detail: 'Delivers forced checkmate cleanly.', tacticalTag: 'Mate in 1–3' };
    }
    const fork = detectForkOnMove(chessBefore, uci, color);
    if (fork) {
      return {
        headline: `${classification === 'best' ? 'Best' : 'Solid'} Move — ${san}`,
        detail: `Creates a ${PIECE_NAMES[fork.piece]} fork on ${fork.targetSquare} targeting ${fork.victims.slice(0, 2).join(' and ')}.`,
        tacticalTag: 'Fork',
      };
    }
    const pin = detectPinOrSkewer(chessBefore, uci, color);
    if (pin) {
      return {
        headline: `${classification === 'best' ? 'Best' : 'Solid'} Move — ${san}`,
        detail: `${pin.kind}s the ${PIECE_NAMES[pin.frontPiece]} on ${pin.frontSq} to the ${PIECE_NAMES[pin.backPiece]} on ${pin.backSq}.`,
        tacticalTag: 'Pin/Skewer',
      };
    }
    const disc = detectDiscoveredAttack(chessBefore, uci, color);
    if (disc) {
      return {
        headline: `${classification === 'best' ? 'Best' : 'Solid'} Move — ${san}`,
        detail: `Opens a discovered attack from ${PIECE_NAMES[disc.slider]} on ${disc.sliderSq} toward ${disc.targetSq}.`,
        tacticalTag: 'Discovered Attack',
      };
    }
    return {
      headline: classification === 'best' ? `Best Move — ${san}` : `Good Move — ${san}`,
      detail: classification === 'best'
        ? matchesBest
          ? `Matches Stockfish's top choice (${evalAfter.display}).`
          : `Virtually equal to Stockfish's top choice ${bestMoveSan} (${evalAfter.display}).`
        : `Solid move; ${bestMoveSan || san} was slightly sharper.`,
      tacticalTag: classification === 'best' ? 'Engine Top' : 'Accurate',
    };
  }

  // Errors: Inaccuracy, Mistake, Blunder
  const prefix = classification === 'blunder' ? 'Blunder' : classification === 'mistake' ? 'Mistake' : 'Inaccuracy';

  // 1. Missed forced mate (Mate in 1-3 vs longer Forced Mate)
  const hadShortMate = detectShortMate(evalBefore, color);
  const stillHasShortMate = evalAfter.isCheckmate || detectShortMate(evalAfter, color) !== null;
  const moverHadMate = evalBefore.mateWhite !== null && evalBefore.mateWhite !== 0 && ((color === 'w' && evalBefore.mateWhite > 0) || (color === 'b' && evalBefore.mateWhite < 0));
  const moverHasMate = evalAfter.isCheckmate || (evalAfter.mateWhite !== null && evalAfter.mateWhite !== 0 && ((color === 'w' && evalAfter.mateWhite > 0) || (color === 'b' && evalAfter.mateWhite < 0)));
  if ((hadShortMate !== null && !stillHasShortMate) || (moverHadMate && !moverHasMate)) {
    const isShort = hadShortMate !== null;
    return {
      headline: `${prefix}: Missed ${isShort ? `Mate in ${hadShortMate}` : 'Forced Mate'}`,
      detail: `${bestMoveSan} forced checkmate, whereas ${san} lets the opponent escape.`,
      tacticalTag: isShort ? 'Mate in 1–3' : 'Forced Mate',
    };
  }

  // 2. Walked into opponent forced mate / Back-Rank
  const oppGotMate = evalAfter.mateWhite !== null && evalAfter.mateWhite !== 0 && ((color === 'w' && evalAfter.mateWhite < 0) || (color === 'b' && evalAfter.mateWhite > 0));
  if (oppGotMate) {
    const oppShortMate = detectShortMate(evalAfter, oppColor);
    const brSq = threatMoveUci ? detectBackRankThreat(chessAfter, threatMoveUci, oppColor) : null;
    if (brSq) {
      return {
        headline: `${prefix}: Allows Back-Rank Mate on ${brSq}`,
        detail: `${san} lets the opponent deliver mate on ${brSq}. ${bestMoveSan} defended the back rank.`,
        tacticalTag: 'Back-Rank Mate',
      };
    }
    return {
      headline: `${prefix}: Walks Into ${oppShortMate ? `Mate in ${oppShortMate}` : 'Forced Mate'}`,
      detail: `${san} exposes your King to a mating net${threatMoveSan ? ` starting with ${threatMoveSan}` : ''}. ${bestMoveSan} stayed safe.`,
      tacticalTag: oppShortMate ? 'Mate in 1–3' : 'Forced Mate',
    };
  }

  // 3. Opponent immediate tactical refutation (Back-Rank, Fork, Pin/Skewer, Discovered Attack)
  if (threatMoveUci) {
    const backRankSq = detectBackRankThreat(chessAfter, threatMoveUci, oppColor);
    if (backRankSq) {
      return {
        headline: `${prefix}: Allows Back-Rank Infiltration on ${backRankSq}`,
        detail: `Allows ${threatMoveSan ?? 'Rook/Queen'} onto ${backRankSq} with check. ${bestMoveSan} covered it.`,
        tacticalTag: 'Back-Rank Mate',
      };
    }
    const oppFork = detectForkOnMove(chessAfter, threatMoveUci, oppColor);
    if (oppFork) {
      return {
        headline: `${prefix}: Allows ${PIECE_NAMES[oppFork.piece]} Fork on ${oppFork.targetSquare}`,
        detail: `${san} walks into ${threatMoveSan ?? 'a fork'} hitting ${oppFork.victims.slice(0, 2).join(' and ')}. Prefer ${bestMoveSan}.`,
        tacticalTag: 'Fork',
      };
    }
    const oppPin = detectPinOrSkewer(chessAfter, threatMoveUci, oppColor);
    if (oppPin) {
      return {
        headline: `${prefix}: Allows ${oppPin.kind} on ${oppPin.frontSq}`,
        detail: `Opponent plays ${threatMoveSan ?? 'a slider move'} to ${oppPin.kind.toLowerCase()} your ${PIECE_NAMES[oppPin.frontPiece]} to your ${PIECE_NAMES[oppPin.backPiece]}. ${bestMoveSan} prevented it.`,
        tacticalTag: 'Pin/Skewer',
      };
    }
    const oppDisc = detectDiscoveredAttack(chessAfter, threatMoveUci, oppColor);
    if (oppDisc) {
      return {
        headline: `${prefix}: Allows Discovered Attack on ${oppDisc.targetSq}`,
        detail: `Allows ${threatMoveSan ?? 'a discovered attack'} uncovering the ${PIECE_NAMES[oppDisc.slider]} on ${oppDisc.sliderSq}. ${bestMoveSan} kept control.`,
        tacticalTag: 'Discovered Attack',
      };
    }
  }

  // 4. Missed offensive tactic (Fork, Pin/Skewer, Discovered Attack, Deflection)
  const missedFork = detectForkOnMove(chessBefore, bestMoveUci, color);
  if (missedFork) {
    return {
      headline: `${prefix}: Missed ${PIECE_NAMES[missedFork.piece]} Fork on ${missedFork.targetSquare}`,
      detail: `Instead of ${san}, ${bestMoveSan} forked ${missedFork.victims.slice(0, 2).join(' and ')}.`,
      tacticalTag: 'Fork',
    };
  }
  const missedPin = detectPinOrSkewer(chessBefore, bestMoveUci, color);
  if (missedPin) {
    return {
      headline: `${prefix}: Missed ${missedPin.kind} on ${missedPin.frontSq}`,
      detail: `${bestMoveSan} would ${missedPin.kind.toLowerCase()} the ${PIECE_NAMES[missedPin.frontPiece]} to the ${PIECE_NAMES[missedPin.backPiece]} on ${missedPin.backSq}.`,
      tacticalTag: 'Pin/Skewer',
    };
  }
  const missedDisc = detectDiscoveredAttack(chessBefore, bestMoveUci, color);
  if (missedDisc) {
    return {
      headline: `${prefix}: Missed Discovered Attack`,
      detail: `${bestMoveSan} unleashed the ${PIECE_NAMES[missedDisc.slider]} on ${missedDisc.sliderSq} against the ${PIECE_NAMES[missedDisc.target]} on ${missedDisc.targetSq}.`,
      tacticalTag: 'Discovered Attack',
    };
  }
  const missedDeflection = detectDeflection(chessBefore, bestMoveUci, color, bestPvUci);
  if (missedDeflection) {
    return {
      headline: `${prefix}: Missed Deflection on ${missedDeflection.targetSq}`,
      detail: `${bestMoveSan} deflected the ${PIECE_NAMES[missedDeflection.targetPiece]} from its defensive duty.`,
      tacticalTag: 'Deflection',
    };
  }

  // 5. Left own piece hanging or dropped material (excluding equal trades on the move's destination square!)
  const parsedPlayed = uciToSquares(uci);
  const capturedOnMove = parsedPlayed ? chessBefore.get(parsedPlayed.to) : null;
  const capturedVal = capturedOnMove && capturedOnMove.color === oppColor ? PIECE_VAL[capturedOnMove.type] : 0;

  const beforeHanging = new Set(findHangingPieces(chessBefore, color).map((h) => h.square));
  const afterHanging = findHangingPieces(chessAfter, color).filter((h) => {
    // If we just captured on this exact square (e.g. Bxf6 trading Bishop for Knight),
    // only flag as hanging if the opponent wins net >= 2 material beyond what we just took!
    if (parsedPlayed && h.square === parsedPlayed.to && capturedVal > 0) {
      return h.netLoss - capturedVal >= 2;
    }
    return true;
  });
  const newlyHanging = afterHanging.find((h) => !beforeHanging.has(h.square)) || afterHanging[0];
  if (newlyHanging) {
    const pName = PIECE_NAMES[newlyHanging.piece];
    const reason = newlyHanging.undefended
      ? `Leaves ${pName} on ${newlyHanging.square} undefended`
      : `Drops ${pName} on ${newlyHanging.square} to a ${newlyHanging.attackerPiece ? PIECE_NAMES[newlyHanging.attackerPiece] : 'lesser'} attack`;
    return {
      headline: `${prefix}: ${reason}`,
      detail: `${bestMoveSan} protected material and kept control.`,
      tacticalTag: 'Hanging Piece',
    };
  }

  // 6. Missed capturing opponent's free hanging piece (verified via legal SEE)
  const parsedBest = uciToSquares(bestMoveUci);
  if (parsedBest) {
    const target = chessBefore.get(parsedBest.to);
    if (target && target.color === oppColor && PIECE_VAL[target.type] >= 3) {
      const legalGain = legalCaptureGainOnSquare(chessBefore, parsedBest.to as Square, 4);
      if (legalGain >= PIECE_VAL[target.type]) {
        return {
          headline: `${prefix}: Missed Free ${PIECE_NAMES[target.type]} on ${parsedBest.to}`,
          detail: `${bestMoveSan} won an undefended ${PIECE_NAMES[target.type]} instead of ${san}.`,
          tacticalTag: 'Hanging Piece',
        };
      }
    }
  }

  // 7. Missed critical Only-Move save (MultiPV gap >= 2.0 pawns)
  if (secondBestGapPawns >= 2.0) {
    return {
      headline: `${prefix}: Missed Only Move (${bestMoveSan})`,
      detail: threatMoveSan
        ? `${bestMoveSan} was the only move to stop ${threatMoveSan} (eval ${evalBefore.display} → ${evalAfter.display}).`
        : `${bestMoveSan} was the only move holding the position (${evalBefore.display} → ${evalAfter.display}).`,
      tacticalTag: 'Only Move Save',
    };
  }

  return {
    headline: `${prefix}: Better was ${bestMoveSan}`,
    detail: `${san} swings evaluation (${evalBefore.display} → ${evalAfter.display}). ${bestMoveSan} kept stronger control.`,
    tacticalTag: classification === 'blunder' ? 'Eval Collapse' : 'Suboptimal',
  };
}
