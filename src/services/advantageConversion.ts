import type { AnalyzedGame, EngineScore, PlayerColor } from '../types/chess';
import { resolveUserColor, resultForUserStrict } from '../utils/player';

export const ADVANTAGE_THRESHOLD_CP = 250; // +2.5 pawns (or -2.5 as Black)
export const CONVERSION_WIN_CP = 800; // +8.0 pawns win lock
export const CONVERSION_SLIP_CP = 150; // < +1.5 pawns slip warning
const PLAYABLE_PEAK_MAX_CP = 750; // keep starting conversion positions below CONVERSION_WIN_CP

export interface BlownLeadPosition {
  id: string;
  gameId: string;
  ply: number;
  moveNumber: number;
  userColor: PlayerColor;
  fen: string;
  peakEvalPawns: number;
  peakDisplay: string;
  finalResult: 'W' | 'D' | 'L';
  slippedToDrawOrLoss: boolean;
  opponentName: string;
  opponentRating: number;
  openingName: string;
  playedAt: number;
}

export function userPerspectiveCp(score: EngineScore, userColor: PlayerColor): number {
  const sign = userColor === 'w' ? 1 : -1;
  if (score.isCheckmate) return score.cpWhite * sign;
  if (score.mateWhite !== null && score.mateWhite !== 0) {
    return score.mateWhite * sign > 0 ? 10000 : -10000;
  }
  return score.cpWhite * sign;
}

/**
 * Extracts "Tractor Beam" Advantage Conversion training positions from completed user games where:
 * - User's eval reached >= +2.5 (or <= -2.5 as Black) on their turn
 * - And the game later slipped (drew/lost, or blew the advantage below +1.0 AFTER that peak)
 * Prefers playable peaks in [+2.5, +7.5] (below the +8.0 conversion win lock) so drills don't auto-win on move 1.
 */
export function extractBlownLeadPositions(
  analyzedGames: AnalyzedGame[],
  username: string
): BlownLeadPosition[] {
  const results: BlownLeadPosition[] = [];

  for (const ag of analyzedGames) {
    const uc = resolveUserColor(ag.game, username);
    const finalResult = resultForUserStrict(ag.game, uc);
    if (!finalResult) continue; // exclude unfinished/aborted '*' games

    const slippedToDrawOrLoss = finalResult === 'D' || finalResult === 'L';
    const oppName = uc === 'w' ? ag.game.black.name : ag.game.white.name;
    const oppRating = (uc === 'w' ? ag.game.black.rating : ag.game.white.rating) ?? 1400;

    // Precompute the minimum user eval reached AFTER each ply index
    const minAfterFromIdx = new Array<number>(ag.plies.length).fill(Infinity);
    let runningMin = Infinity;
    for (let i = ag.plies.length - 1; i >= 0; i--) {
      const afterCp = userPerspectiveCp(ag.plies[i].evalAfter, uc);
      runningMin = Math.min(runningMin, afterCp);
      minAfterFromIdx[i] = runningMin;
    }

    let bestPlayableIdx = -1;
    let bestPlayableCp = -Infinity;
    let fallbackIdx = -1;
    let fallbackCp = -Infinity;

    for (let i = 0; i < ag.plies.length; i++) {
      const p = ag.plies[i];
      if (p.color !== uc) continue;
      const cp = userPerspectiveCp(p.evalBefore, uc);
      if (cp < ADVANTAGE_THRESHOLD_CP) continue;

      const actuallySlippedAfter = minAfterFromIdx[i] < 100;
      if (!slippedToDrawOrLoss && !actuallySlippedAfter) continue;

      if (cp <= PLAYABLE_PEAK_MAX_CP) {
        if (cp > bestPlayableCp) {
          bestPlayableCp = cp;
          bestPlayableIdx = i;
        }
      } else if (fallbackIdx === -1 || cp < fallbackCp) {
        // If only huge >= +8.0 / mate leads slipped, pick the smallest winning peak above +7.5
        fallbackCp = cp;
        fallbackIdx = i;
      }
    }

    const peakPlyIndex = bestPlayableIdx !== -1 ? bestPlayableIdx : fallbackIdx;
    const peakCp = bestPlayableIdx !== -1 ? bestPlayableCp : fallbackCp;
    if (peakPlyIndex === -1) continue;

    const targetPly = ag.plies[peakPlyIndex];
    results.push({
      id: `conv_${ag.id}_${targetPly.ply}`,
      gameId: ag.id,
      ply: targetPly.ply,
      moveNumber: targetPly.moveNumber,
      userColor: uc,
      fen: targetPly.beforeFen,
      peakEvalPawns: Number((Math.min(1200, peakCp) / 100).toFixed(1)),
      peakDisplay: targetPly.evalBefore.display,
      finalResult,
      slippedToDrawOrLoss,
      opponentName: oppName,
      opponentRating: oppRating,
      openingName: ag.openingLineDetected || ag.game.openingName || 'Unknown Opening',
      playedAt: ag.game.createdAt,
    });
  }

  return results.sort((a, b) => {
    const outcomeDiff = (b.slippedToDrawOrLoss ? 1 : 0) - (a.slippedToDrawOrLoss ? 1 : 0);
    if (outcomeDiff !== 0) return outcomeDiff;
    return b.peakEvalPawns - a.peakEvalPawns || b.playedAt - a.playedAt;
  });
}

export type ConversionVerdict = 'won' | 'holding' | 'slipping';

export function evaluateConversionStatus(
  score: EngineScore,
  userColor: PlayerColor,
  isCheckmateForUser: boolean
): { verdict: ConversionVerdict; pawns: number } {
  if (isCheckmateForUser) return { verdict: 'won', pawns: 99 };
  const cp = userPerspectiveCp(score, userColor);
  const pawns = Number((Math.max(-1500, Math.min(1500, cp)) / 100).toFixed(1));
  if (cp >= CONVERSION_WIN_CP) return { verdict: 'won', pawns };
  if (cp < CONVERSION_SLIP_CP) return { verdict: 'slipping', pawns };
  return { verdict: 'holding', pawns };
}
