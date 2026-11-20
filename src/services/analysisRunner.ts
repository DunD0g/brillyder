import type { AnalysisDepthPreset, AnalyzedGame, EngineEval, LichessGameRecord } from '../types/chess';
import { buildAnalyzedGame, loadPgnSafely } from '../chess/classification';
import { stockfishService } from '../engine/StockfishService';
import { saveAnalyzedGame } from '../storage/gameDb';
import { computeGameProgressFraction } from '../utils/analysisProgress';

const START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const TURNING_POINT_CP_SWING = 100; // >= 1.0 pawn eval swing triggers Pass 2 deepening

export class AnalysisCancelledError extends Error {
  constructor() {
    super('Analysis cancelled');
    this.name = 'AnalysisCancelledError';
  }
}

export interface AnalysisProgressMeta {
  pass: 1 | 2;
  twoPass: boolean;
  fastDepth: number;
  gameFraction: number;
  shortStage: string;
}

export interface AnalysisRunnerOptions {
  onProgress?: (done: number, total: number, stageLabel?: string, meta?: AnalysisProgressMeta) => void;
  shouldCancel?: () => boolean;
  waitIfPaused?: () => Promise<void>;
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
    waitIfPaused,
    persist = true,
    multiPv = 2,
    twoPass = depth >= 14,
  } = options;
  const chess = loadPgnSafely(targetGame.pgn);
  const moves = chess.history({ verbose: true });
  const fens = [START_FEN, ...moves.map((m) => m.after)];
  const evals: EngineEval[] = [];

  const fastDepth = twoPass ? (depth >= 18 ? 14 : 12) : depth;
  let maxGameFraction = 0;

  const emitProgress = (
    done: number,
    total: number,
    pass: 1 | 2,
    stageLabel: string,
    shortStage: string
  ) => {
    maxGameFraction = computeGameProgressFraction(done, total, pass, twoPass, maxGameFraction);
    onProgress?.(done, total, stageLabel, {
      pass,
      twoPass,
      fastDepth,
      gameFraction: maxGameFraction,
      shortStage,
    });
  };

  // Pass 1: Fast scan across every position
  const pass1Label = `Pass 1 · Fast scan D${fastDepth}`;
  const pass1Short = `Pass 1 · D${fastDepth}`;
  emitProgress(0, fens.length, 1, pass1Label, pass1Short);
  for (let i = 0; i < fens.length; i++) {
    if (shouldCancel?.()) throw new AnalysisCancelledError();
    if (waitIfPaused) await waitIfPaused();
    if (shouldCancel?.()) throw new AnalysisCancelledError();
    const res = await stockfishService.analyzePosition(fens[i], { depth: fastDepth, multiPv });
    if (shouldCancel?.()) throw new AnalysisCancelledError();
    evals.push(res);
    emitProgress(i + 1, fens.length, 1, pass1Label, pass1Short);
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
    const pass2Label = 'Pass 2 · Deepening turning points (D18)';
    const pass2Short = 'Pass 2 · Deep D18';

    if (maxDeepen === 0) {
      emitProgress(fens.length, fens.length, 2, 'Finalizing review…', 'Finalizing…');
    } else {
      for (let k = 0; k < maxDeepen; k++) {
        if (shouldCancel?.()) throw new AnalysisCancelledError();
        if (waitIfPaused) await waitIfPaused();
        if (shouldCancel?.()) throw new AnalysisCancelledError();
        const plyIdx = turningIndices[k];
        emitProgress(k, maxDeepen, 2, pass2Label, pass2Short);
        const deepRes = await stockfishService.analyzePosition(fens[plyIdx], {
          depth: 18,
          multiPv: 3,
          timeoutMs: 24000,
        });
        if (shouldCancel?.()) throw new AnalysisCancelledError();
        evals[plyIdx] = deepRes;
        deepenedIndices.add(plyIdx);
        emitProgress(k + 1, maxDeepen, 2, pass2Label, pass2Short);
      }
    }
  }

  const analyzed = buildAnalyzedGame(targetGame, evals, depth, deepenedIndices);
  if (persist) await saveAnalyzedGame(analyzed);
  return analyzed;
}
