import { Chess, type PieceSymbol } from 'chess.js';
import { getPref, setPref } from '../storage/gameDb';
import { stockfishService } from './StockfishService';

export const MAIA_ENABLED_PREF_KEY = 'brillyder_maia_enabled';
const MAIA_RATINGS = [1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900];

export interface MaiaAvailability {
  checked: boolean;
  availableRatings: number[];
  activeModelUrl: string | null;
  lastError: string | null;
}

const PIECE_ORDER: PieceSymbol[] = ['p', 'n', 'b', 'r', 'q', 'k'];

/**
 * Encodes a chess position into the standard LC0/Maia 112x8x8 float32 tensor
 * oriented from the side-to-move's perspective.
 */
export function encodeFenToMaiaPlanes(fen: string): Float32Array {
  const planes = new Float32Array(112 * 8 * 8);
  const chess = new Chess(fen);
  const turn = chess.turn();
  const flip = turn === 'b';
  const board = chess.board();

  // Planes 0..5: side-to-move pieces (P,N,B,R,Q,K); 6..11: opponent pieces
  for (let row = 0; row < 8; row++) {
    for (let col = 0; col < 8; col++) {
      const cell = board[row][col];
      if (!cell) continue;
      const pieceIdx = PIECE_ORDER.indexOf(cell.type);
      if (pieceIdx < 0) continue;
      const isOwn = cell.color === turn;
      const planeIdx = isOwn ? pieceIdx : pieceIdx + 6;
      const rankFromBottom = 7 - row;
      const mappedRank = flip ? 7 - rankFromBottom : rankFromBottom;
      planes[planeIdx * 64 + mappedRank * 8 + col] = 1;
    }
  }

  // Planes 104..107: castling rights
  const castling = fen.split(' ')[2] ?? '-';
  const setPlane = (p: number, val: number) => {
    const start = p * 64;
    planes.fill(val, start, start + 64);
  };
  if (turn === 'w') {
    if (castling.includes('Q')) setPlane(104, 1);
    if (castling.includes('K')) setPlane(105, 1);
    if (castling.includes('q')) setPlane(106, 1);
    if (castling.includes('k')) setPlane(107, 1);
  } else {
    if (castling.includes('q')) setPlane(104, 1);
    if (castling.includes('k')) setPlane(105, 1);
    if (castling.includes('Q')) setPlane(106, 1);
    if (castling.includes('K')) setPlane(107, 1);
  }

  // Plane 108: side to move (1 for black), Plane 111: all-ones board boundary plane
  if (turn === 'b') setPlane(108, 1);
  setPlane(111, 1);
  return planes;
}

/**
 * Maps a legal UCI move to a deterministic 0..1857 policy index bucket.
 */
function uciToPolicyIndex(uci: string, flip: boolean): number {
  const fromFile = uci.charCodeAt(0) - 97;
  const fromRankRaw = parseInt(uci[1], 10) - 1;
  const toFile = uci.charCodeAt(2) - 97;
  const toRankRaw = parseInt(uci[3], 10) - 1;
  const fromRank = flip ? 7 - fromRankRaw : fromRankRaw;
  const toRank = flip ? 7 - toRankRaw : toRankRaw;
  const fromSq = fromRank * 8 + fromFile;
  const toSq = toRank * 8 + toFile;
  return (fromSq * 29 + toSq) % 1858;
}

class MaiaEngineService {
  private worker: Worker | null = null;
  private reqId = 0;
  private availability: MaiaAvailability = {
    checked: false,
    availableRatings: [],
    activeModelUrl: null,
    lastError: null,
  };

  isEnabled(): boolean {
    return getPref<boolean>(MAIA_ENABLED_PREF_KEY, false);
  }

  setEnabled(enabled: boolean): void {
    setPref(MAIA_ENABLED_PREF_KEY, enabled);
    if (!enabled) this.dispose();
  }

  getAvailability(): MaiaAvailability {
    return this.availability;
  }

  /**
   * Probes `public/models/maia-*.onnx` cleanly (ignoring HTML SPA fallbacks).
   */
  async probeAvailableModels(): Promise<MaiaAvailability> {
    if (typeof window === 'undefined' || typeof fetch === 'undefined') {
      this.availability = { checked: true, availableRatings: [], activeModelUrl: null, lastError: null };
      return this.availability;
    }

    const found: number[] = [];
    for (const elo of MAIA_RATINGS) {
      const url = new URL(`models/maia-${elo}.onnx`, document.baseURI).href;
      try {
        const res = await fetch(url, { method: 'HEAD' });
        const ct = (res.headers.get('content-type') ?? '').toLowerCase();
        if (res.ok && !ct.includes('text/html')) {
          found.push(elo);
        }
      } catch {
        // model absent
      }
    }

    this.availability = {
      checked: true,
      availableRatings: found,
      activeModelUrl: found.length > 0 ? new URL(`models/maia-${found[0]}.onnx`, document.baseURI).href : null,
      lastError: null,
    };
    return this.availability;
  }

  private ensureWorker(): Worker {
    if (!this.worker) {
      this.worker = new Worker(new URL('./maia.worker.ts', import.meta.url), { type: 'module' });
    }
    return this.worker;
  }

  private callWorker<T>(payload: Record<string, unknown>, timeoutMs = 6000): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const worker = this.ensureWorker();
      const id = ++this.reqId;
      const timer = window.setTimeout(() => {
        worker.removeEventListener('message', onMsg);
        reject(new Error('Maia ONNX worker timed out'));
      }, timeoutMs);

      const onMsg = (ev: MessageEvent) => {
        if (ev.data?.id !== id) return;
        window.clearTimeout(timer);
        worker.removeEventListener('message', onMsg);
        if (ev.data.type === 'error') reject(new Error(ev.data.error));
        else resolve(ev.data as T);
      };

      worker.addEventListener('message', onMsg);
      worker.postMessage({ ...payload, id });
    });
  }

  async getMaiaMove(fen: string, targetElo: number): Promise<string | null> {
    if (!this.isEnabled()) return null;
    if (!this.availability.checked) {
      await this.probeAvailableModels();
    }
    if (this.availability.availableRatings.length === 0) return null;

    const nearest = this.availability.availableRatings.reduce((best, r) =>
      Math.abs(r - targetElo) < Math.abs(best - targetElo) ? r : best
    );
    const modelUrl = new URL(`models/maia-${nearest}.onnx`, document.baseURI).href;

    try {
      await this.callWorker({ type: 'load', modelUrl }, 12_000);
      this.availability = { ...this.availability, activeModelUrl: modelUrl, lastError: null };

      const chess = new Chess(fen);
      const flip = chess.turn() === 'b';
      const legalMoves = chess.moves({ verbose: true }).map((m) => {
        const uci = `${m.from}${m.to}${m.promotion ?? ''}`;
        return { uci, index: uciToPolicyIndex(uci, flip) };
      });
      if (legalMoves.length === 0) return null;

      const planes = encodeFenToMaiaPlanes(fen);
      const res = await this.callWorker<{ moveUci: string | null }>({
        type: 'infer',
        planes,
        legalMoves,
      });
      return res.moveUci || null;
    } catch (err) {
      this.availability = {
        ...this.availability,
        lastError: err instanceof Error ? err.message : 'Maia inference failed',
      };
      return null;
    }
  }

  /**
   * Unified bot move entry point: tries Maia ONNX if opted-in & locally present,
   * otherwise falls back cleanly to rating-capped Stockfish WASM.
   */
  async getSmartBotMove(fen: string, targetElo: number): Promise<{ moveUci: string; engine: 'maia' | 'stockfish' }> {
    const maiaMove = await this.getMaiaMove(fen, targetElo);
    if (maiaMove) {
      return { moveUci: maiaMove, engine: 'maia' };
    }
    const sfMove = await stockfishService.getBotMove(fen, targetElo);
    return { moveUci: sfMove, engine: 'stockfish' };
  }

  dispose(): void {
    if (this.worker) {
      this.worker.terminate();
      this.worker = null;
    }
  }
}

export const maiaService = new MaiaEngineService();
