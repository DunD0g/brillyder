import type { PieceSymbol } from 'chess.js';
import type { AnalysisDepthPreset, AnalyzedGame, EngineEval, LichessGameRecord } from '../types/chess';
import { buildAnalyzedGame, isSacrificeMove, loadPgnSafely } from '../chess/classification';
import { EngineCancelledError, stockfishService } from '../engine/StockfishService';
import { saveAnalyzedGame } from '../storage/gameDb';
import { computeGameProgressFraction } from '../utils/analysisProgress';
import { getMoverWinPercent } from '../utils/chessMath';
import { isCustomFenGame } from '../utils/customFen';

const TURNING_POINT_CP_SWING = 100; // >= 1.0 pawn eval swing triggers Pass 2 deepening
const MAX_PASS2_FENS = 28; // paired (before, after) positions capped for smooth mobile runtime

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
 * - Pass 2 (Deep): Deepens paired (before & after) positions for the largest
 *   turning points (>= 1.0 pawn swing), candidate sacrifices, and high-MultiPV-gap
 *   critical moments to D18 (MultiPV=3) so evalBefore/evalAfter stay at matching depth.
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
  const initialFen = moves[0]?.before ?? chess.fen();
  const fens = [initialFen, ...moves.map((m) => m.after)];
  const evals: EngineEval[] = [];

  const fastDepth = twoPass ? (depth >= 18 ? 14 : 12) : depth;
  const deepDepth = depth >= 18 ? 20 : 18;
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

  const runSearch = async (fen: string, opts: { depth: number; multiPv: number; timeoutMs?: number }) => {
    try {
      return await stockfishService.analyzePosition(fen, opts);
    } catch (err) {
      if (err instanceof EngineCancelledError || shouldCancel?.()) {
        throw new AnalysisCancelledError();
      }
      throw err;
    }
  };

  // Pass 1: Fast scan across every position
  const pass1Label = `Pass 1 · Fast scan D${fastDepth}`;
  const pass1Short = `Pass 1 · D${fastDepth}`;
  emitProgress(0, fens.length, 1, pass1Label, pass1Short);
  for (let i = 0; i < fens.length; i++) {
    if (shouldCancel?.()) throw new AnalysisCancelledError();
    if (waitIfPaused) await waitIfPaused();
    if (shouldCancel?.()) throw new AnalysisCancelledError();
    const res = await runSearch(fens[i], { depth: fastDepth, multiPv });
    if (shouldCancel?.()) throw new AnalysisCancelledError();
    evals.push(res);
    emitProgress(i + 1, fens.length, 1, pass1Label, pass1Short);
  }

  // Pass 2: Deepen paired (i, i+1) positions for top turning points, candidate sacrifices & critical only-moves
  const deepenedIndices = new Set<number>();
  if (twoPass && moves.length > 0) {
    const candidates: Array<{ plyIdx: number; priority: number }> = [];
    for (let i = 0; i < moves.length; i++) {
      const before = evals[i];
      const after = evals[i + 1];
      const mv = moves[i];
      const cpBefore = Math.max(-1200, Math.min(1200, before.score.cpWhite));
      const cpAfter = Math.max(-1200, Math.min(1200, after.score.cpWhite));
      const swingCp = Math.abs(cpAfter - cpBefore);
      const isSwing = isTurningPointEvalSwing(before, after);

      // Check MultiPV gap and candidate brilliant sacrifices (which have ~0 swing!)
      const l1 = before.lines.find((l) => l.multipv === 1);
      const l2 = before.lines.find((l) => l.multipv === 2);
      const gapWin = l1 && l2 ? Math.max(0, getMoverWinPercent(l1.score, mv.color) - getMoverWinPercent(l2.score, mv.color)) : 0;
      const winLoss = Math.max(0, getMoverWinPercent(before.score, mv.color) - getMoverWinPercent(after.score, mv.color));
      const isCandidateBrilliant =
        winLoss <= 4 &&
        gapWin >= 5 &&
        isSacrificeMove(
          mv.before,
          mv.after,
          mv.color,
          mv.to,
          mv.piece as PieceSymbol,
          mv.captured as PieceSymbol | undefined,
          mv.promotion as PieceSymbol | undefined
        );
      const isCriticalOnlyMove = winLoss <= 4 && gapWin >= 12;

      if (isCandidateBrilliant) {
        candidates.push({ plyIdx: i, priority: 2000 + gapWin * 10 });
      } else if (isSwing) {
        const mateBonus = (before.score.mateWhite === null) !== (after.score.mateWhite === null) ? 600 : 0;
        candidates.push({ plyIdx: i, priority: swingCp + mateBonus });
      } else if (isCriticalOnlyMove) {
        candidates.push({ plyIdx: i, priority: 300 + gapWin * 8 });
      }
    }

    // Prioritize highest-impact moments first, then collect paired (i, i+1) FENs up to MAX_PASS2_FENS
    candidates.sort((a, b) => b.priority - a.priority);
    const fenSet = new Set<number>();
    const chosenPlies: number[] = [];
    for (const c of candidates) {
      const additions = (fenSet.has(c.plyIdx) ? 0 : 1) + (fenSet.has(c.plyIdx + 1) ? 0 : 1);
      if (fenSet.size + additions > MAX_PASS2_FENS) continue;
      fenSet.add(c.plyIdx);
      fenSet.add(c.plyIdx + 1);
      chosenPlies.push(c.plyIdx);
    }

    const fenOrder = Array.from(fenSet).sort((a, b) => a - b);
    const pass2Label = `Pass 2 · Deepening key moments (D${deepDepth})`;
    const pass2Short = `Pass 2 · Deep D${deepDepth}`;

    if (fenOrder.length === 0) {
      emitProgress(fens.length, fens.length, 2, 'Finalizing review…', 'Finalizing…');
    } else {
      for (let k = 0; k < fenOrder.length; k++) {
        if (shouldCancel?.()) throw new AnalysisCancelledError();
        if (waitIfPaused) await waitIfPaused();
        if (shouldCancel?.()) throw new AnalysisCancelledError();
        const fenIdx = fenOrder[k];
        emitProgress(k, fenOrder.length, 2, pass2Label, pass2Short);
        const deepRes = await runSearch(fens[fenIdx], {
          depth: deepDepth,
          multiPv: 3,
          timeoutMs: deepDepth >= 20 ? 32000 : 24000,
        });
        if (shouldCancel?.()) throw new AnalysisCancelledError();
        evals[fenIdx] = deepRes;
        emitProgress(k + 1, fenOrder.length, 2, pass2Label, pass2Short);
      }
      for (const plyIdx of chosenPlies) deepenedIndices.add(plyIdx);
    }
  }

  const analyzed = buildAnalyzedGame(targetGame, evals, depth, deepenedIndices);
  if (persist && moves.length > 0 && !isCustomFenGame(targetGame)) {
    await saveAnalyzedGame(analyzed);
  }
  return analyzed;
}
