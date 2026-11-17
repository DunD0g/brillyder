import type { AnalysisDepthPreset, AnalyzedGame, EngineEval, LichessGameRecord } from '../types/chess';
import { buildAnalyzedGame, loadPgnSafely } from '../chess/classification';
import { stockfishService } from '../engine/StockfishService';
import { saveAnalyzedGame } from '../storage/gameDb';

const START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

export class AnalysisCancelledError extends Error {
  constructor() {
    super('Analysis cancelled');
    this.name = 'AnalysisCancelledError';
  }
}

export interface AnalysisRunnerOptions {
  onProgress?: (done: number, total: number) => void;
  shouldCancel?: () => boolean;
  persist?: boolean;
  multiPv?: number;
}

/**
 * Runs Stockfish across every position of a game and optionally persists the
 * finished review to IndexedDB. Shared by single-game, batch and scout runs.
 */
export async function analyzeGameToReview(
  targetGame: LichessGameRecord,
  depth: AnalysisDepthPreset | number,
  options: AnalysisRunnerOptions = {}
): Promise<AnalyzedGame> {
  const { onProgress, shouldCancel, persist = true, multiPv = 2 } = options;
  const chess = loadPgnSafely(targetGame.pgn);
  const moves = chess.history({ verbose: true });
  const fens = [START_FEN, ...moves.map((m) => m.after)];
  const evals: EngineEval[] = [];

  onProgress?.(0, fens.length);
  for (let i = 0; i < fens.length; i++) {
    if (shouldCancel?.()) throw new AnalysisCancelledError();
    const res = await stockfishService.analyzePosition(fens[i], { depth, multiPv });
    if (shouldCancel?.()) throw new AnalysisCancelledError();
    evals.push(res);
    onProgress?.(i + 1, fens.length);
  }

  const analyzed = buildAnalyzedGame(targetGame, evals, depth);
  if (persist) await saveAnalyzedGame(analyzed);
  return analyzed;
}
