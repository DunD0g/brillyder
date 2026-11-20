import type { AnalysisDepthPreset, AnalyzedGame, EngineEval, LichessGameRecord } from '../types/chess';
import { buildAnalyzedGame, loadPgnSafely } from '../chess/classification';
import { stockfishService } from '../engine/StockfishService';
import { saveAnalyzedGame } from '../storage/gameDb';

const START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const TURNING_POINT_CP_SWING = 100; // >= 1.0 pawn eval swing triggers Pass 2 deepening

export class AnalysisCancelledError extends Error {
  constructor() {
    super('Analysis cancelled');
    this.name = 'AnalysisCancelledError';
  }
}

export interface AnalysisRunnerOptions {
  onProgress?: (done: number, total: number, stageLabel?: string) => void;
  shouldCancel?: () => boolean;
  persist?: boolean;
  multiPv?: number;
  twoPass?: boolean;
}

export function isTurningPointEvalSwing(before: EngineEval, after: EngineEval): boolean {
  const mateChanged = (before.score.mateWhite === null) !== (after.score.mateWhite === null);
  if (mateChanged) return true;
  const cpBefore = Math.max(-1200, Math.min(1200, before.score.cpWhite));
  const cpAfter = Math.max(-1200, Math.min(1200, after.score.cpWhite));
  return Math.abs(cpAfter - cpBefore) >= TURNING_POINT_CP_SWING;
}

/**
 * Two-Pass Stockfish Analyzer:
 * - Pass 1 (Fast): D12–D14 (MultiPV=2) across all positions
 * - Pass 2 (Deep): Automatically deepens ONLY turning points (eval swing >= 1.0 pawn)
 *   to D18 (MultiPV=3) for richer plain-English explanations & Clutch Save detection.
 */
export async function analyzeGameToReview(
  targetGame: LichessGameRecord,
  depth: AnalysisDepthPreset | number,
  options: AnalysisRunnerOptions = {}
): Promise<AnalyzedGame> {
  const {
    onProgress,
    shouldCancel,
    persist = true,
    multiPv = 2,
    twoPass = depth >= 14,
  } = options;
  const chess = loadPgnSafely(targetGame.pgn);
  const moves = chess.history({ verbose: true });
  const fens = [START_FEN, ...moves.map((m) => m.after)];
  const evals: EngineEval[] = [];

  const fastDepth = twoPass ? (depth >= 18 ? 14 : 12) : depth;

  // Pass 1: Fast scan across every position
  onProgress?.(0, fens.length, `Pass 1 · Fast scan D${fastDepth}`);
  for (let i = 0; i < fens.length; i++) {
    if (shouldCancel?.()) throw new AnalysisCancelledError();
    const res = await stockfishService.analyzePosition(fens[i], { depth: fastDepth, multiPv });
    if (shouldCancel?.()) throw new AnalysisCancelledError();
    evals.push(res);
    onProgress?.(i + 1, fens.length, `Pass 1 · Fast scan D${fastDepth}`);
  }

  // Pass 2: Deepen turning points (eval swing >= 1.0 pawn) to D18 MultiPV=3
  const deepenedIndices = new Set<number>();
  if (twoPass) {
    const turningIndices: number[] = [];
    for (let i = 0; i < moves.length; i++) {
      if (isTurningPointEvalSwing(evals[i], evals[i + 1])) {
        turningIndices.push(i);
      }
    }
    const maxDeepen = Math.min(turningIndices.length, 24);
    for (let k = 0; k < maxDeepen; k++) {
      if (shouldCancel?.()) throw new AnalysisCancelledError();
      const plyIdx = turningIndices[k];
      onProgress?.(
        k,
        maxDeepen,
        `Pass 2 · Deepening turning point ${k + 1}/${maxDeepen} (D18 · MultiPV 3)`
      );
      const deepRes = await stockfishService.analyzePosition(fens[plyIdx], {
        depth: 18,
        multiPv: 3,
        timeoutMs: 24000,
      });
      if (shouldCancel?.()) throw new AnalysisCancelledError();
      evals[plyIdx] = deepRes;
      deepenedIndices.add(plyIdx);
      onProgress?.(
        k + 1,
        maxDeepen,
        `Pass 2 · Deepening turning point ${k + 1}/${maxDeepen} (D18 · MultiPV 3)`
      );
    }
  }

  const analyzed = buildAnalyzedGame(targetGame, evals, depth, deepenedIndices);
  if (persist) await saveAnalyzedGame(analyzed);
  return analyzed;
}
