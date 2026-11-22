import { Chess, type PieceSymbol } from 'chess.js';
import { getPref, setPref } from '../storage/gameDb';
import { EngineCancelledError, stockfishService } from './StockfishService';

export const MAIA_ENABLED_PREF_KEY = 'brillyder_maia_enabled';
const MAIA_CACHE_NAME = 'brillyder-maia-models-v1';
const MAIA_RATINGS = [1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900];
const FAILED_MODEL_TTL_MS = 5 * 60 * 1000;

export interface MaiaLocalModelInfo {
  rating: number;
  name: string;
  sizeBytes: number;
}

export interface MaiaAvailability {
  checked: boolean;
  availableRatings: number[];
  localRatings: number[];
  localModels: MaiaLocalModelInfo[];
  activeModelUrl: string | null;
  lastError: string | null;
}

export function parseMaiaRatingFromFilename(filename: string, fallback = 1500): number {
  const match = filename.match(/(1[1-9]00)/);
  if (match) {
    const parsed = parseInt(match[1], 10);
    if (MAIA_RATINGS.includes(parsed)) return parsed;
  }
  return fallback;
}

function localModelCacheUrl(rating: number): string {
  return `https://brillyder.local/maia-models/maia-${rating}.onnx`;
}

const PIECE_ORDER: PieceSymbol[] = ['p', 'n', 'b', 'r', 'q', 'k'];
const FILES = 'abcdefgh';

/**
 * Builds the canonical LC0 / Maia 1858-move policy lookup map:
 * - Indices 0..1791: all queen-ray and knight moves ordered by (fromRank, fromFile) then (toRank, toFile).
 *   Knight promotion shares the base rank-7 -> rank-8 move index per LC0's convention.
 * - Indices 1792..1857: 66 explicit promotions on rank 7 -> 8 (left/straight/right x q, r, b).
 */
export function buildLc0PolicyMap(): Map<string, number> {
  const map = new Map<string, number>();
  let idx = 0;

  for (let fr = 0; fr < 8; fr++) {
    for (let ff = 0; ff < 8; ff++) {
      const from = `${FILES[ff]}${fr + 1}`;
      for (let tr = 0; tr < 8; tr++) {
        for (let tf = 0; tf < 8; tf++) {
          if (fr === tr && ff === tf) continue;
          const dr = Math.abs(tr - fr);
          const df = Math.abs(tf - ff);
          const isQueenMove = dr === 0 || df === 0 || dr === df;
          const isKnightMove = (dr === 2 && df === 1) || (dr === 1 && df === 2);
          if (isQueenMove || isKnightMove) {
            map.set(`${from}${FILES[tf]}${tr + 1}`, idx++);
          }
        }
      }
    }
  }

  for (let ff = 0; ff < 8; ff++) {
    const from = `${FILES[ff]}7`;
    for (const df of [-1, 0, 1]) {
      const tf = ff + df;
      if (tf < 0 || tf > 7) continue;
      const to = `${FILES[tf]}8`;
      for (const promo of ['q', 'r', 'b'] as const) {
        map.set(`${from}${to}${promo}`, idx++);
      }
    }
  }

  return map;
}

const LC0_POLICY_MAP = buildLc0PolicyMap();

/**
 * Maps a legal UCI move into the canonical LC0 / Maia 0..1857 policy index
 * (vertically flipped when Black is to move; knight promotions map to the base move).
 */
export function uciToLc0PolicyIndex(uci: string, flip: boolean): number {
  if (!uci || uci.length < 4) return -1;
  const fromFile = uci[0];
  const fromRankRaw = parseInt(uci[1], 10);
  const toFile = uci[2];
  const toRankRaw = parseInt(uci[3], 10);
  if (!Number.isFinite(fromRankRaw) || !Number.isFinite(toRankRaw)) return -1;

  const fromRank = flip ? 9 - fromRankRaw : fromRankRaw;
  const toRank = flip ? 9 - toRankRaw : toRankRaw;
  const rawPromo = uci[4]?.toLowerCase();
  const suffix = rawPromo && rawPromo !== 'n' ? rawPromo : '';
  const canonical = `${fromFile}${fromRank}${toFile}${toRank}${suffix}`;
  return LC0_POLICY_MAP.get(canonical) ?? -1;
}

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
  const fenParts = fen.split(' ');
  const castling = fenParts[2] ?? '-';
  const halfmoveClock = Math.max(0, parseInt(fenParts[4] ?? '0', 10) || 0);
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

  // Plane 108: side to move (1 for black), Plane 109: rule50 counter, Plane 111: all-ones boundary plane
  if (turn === 'b') setPlane(108, 1);
  if (halfmoveClock > 0) setPlane(109, Math.min(1, halfmoveClock / 100));
  setPlane(111, 1);
  return planes;
}

class MaiaEngineService {
  private worker: Worker | null = null;
  private reqId = 0;
  private loadedModelKey: string | null = null;
  private pendingRejectors = new Map<number, (err: Error) => void>();
  private failedModels = new Map<string, number>();
  private memoryModels = new Map<number, { buffer: ArrayBuffer; name: string }>();
  private availability: MaiaAvailability = {
    checked: false,
    availableRatings: [],
    localRatings: [],
    localModels: [],
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

  private async listCachedLocalModels(): Promise<MaiaLocalModelInfo[]> {
    const found = new Map<number, MaiaLocalModelInfo>();
    for (const [rating, entry] of this.memoryModels.entries()) {
      found.set(rating, { rating, name: entry.name, sizeBytes: entry.buffer.byteLength });
    }
    if (typeof caches !== 'undefined') {
      try {
        const cache = await caches.open(MAIA_CACHE_NAME);
        for (const rating of MAIA_RATINGS) {
          const res = await cache.match(localModelCacheUrl(rating));
          if (!res) continue;
          const sizeHeader = parseInt(res.headers.get('x-maia-size') ?? '0', 10);
          const nameHeader = res.headers.get('x-maia-name') || `maia-${rating}.onnx`;
          found.set(rating, {
            rating,
            name: nameHeader,
            sizeBytes: Number.isFinite(sizeHeader) && sizeHeader > 0 ? sizeHeader : 0,
          });
        }
      } catch {
        // Cache Storage may be unavailable in restricted contexts
      }
    }
    return Array.from(found.values()).sort((a, b) => a.rating - b.rating);
  }

  private async readLocalModelBuffer(rating: number): Promise<ArrayBuffer | null> {
    const inMem = this.memoryModels.get(rating);
    if (inMem) return inMem.buffer.slice(0);
    if (typeof caches !== 'undefined') {
      try {
        const cache = await caches.open(MAIA_CACHE_NAME);
        const res = await cache.match(localModelCacheUrl(rating));
        if (res) return await res.arrayBuffer();
      } catch {
        // ignore cache read failures
      }
    }
    return null;
  }

  async importLocalModel(file: File, ratingOverride?: number): Promise<MaiaLocalModelInfo> {
    if (!file.name.toLowerCase().endsWith('.onnx')) {
      throw new Error('Please choose a Maia .onnx model file (e.g. maia-1500.onnx).');
    }
    const rating = ratingOverride ?? parseMaiaRatingFromFilename(file.name, 1500);
    const buffer = await file.arrayBuffer();
    if (buffer.byteLength < 1024) {
      throw new Error('File looks too small to be a valid ONNX model.');
    }

    this.memoryModels.set(rating, { buffer: buffer.slice(0), name: file.name });
    if (typeof caches !== 'undefined') {
      try {
        const cache = await caches.open(MAIA_CACHE_NAME);
        const response = new Response(buffer, {
          headers: {
            'Content-Type': 'application/octet-stream',
            'x-maia-name': file.name,
            'x-maia-size': String(buffer.byteLength),
          },
        });
        await cache.put(localModelCacheUrl(rating), response);
      } catch {
        // Fall back cleanly to in-memory buffer for this session
      }
    }
    this.failedModels.delete(`local:${rating}`);
    // Reset active worker session so replacing an already-loaded rating uses the newly uploaded model
    if (this.loadedModelKey === `local:${rating}`) {
      this.dispose();
    }
    await this.probeAvailableModels();
    return { rating, name: file.name, sizeBytes: buffer.byteLength };
  }

  async removeLocalModel(rating: number): Promise<MaiaAvailability> {
    this.memoryModels.delete(rating);
    if (typeof caches !== 'undefined') {
      try {
        const cache = await caches.open(MAIA_CACHE_NAME);
        await cache.delete(localModelCacheUrl(rating));
      } catch {
        // ignore
      }
    }
    this.dispose();
    return this.probeAvailableModels();
  }

  /**
   * Probes both locally uploaded Cache Storage models and `public/models/maia-*.onnx` cleanly in parallel.
   */
  async probeAvailableModels(): Promise<MaiaAvailability> {
    const localModels = await this.listCachedLocalModels();
    const localRatings = localModels.map((m) => m.rating);

    if (typeof window === 'undefined' || typeof fetch === 'undefined') {
      this.availability = {
        checked: true,
        availableRatings: localRatings,
        localRatings,
        localModels,
        activeModelUrl: localRatings.length > 0 ? `local:${localRatings[0]}` : null,
        lastError: null,
      };
      return this.availability;
    }

    const checks = await Promise.all(
      MAIA_RATINGS.map(async (elo) => {
        const url = new URL(`models/maia-${elo}.onnx`, document.baseURI).href;
        try {
          const res = await fetch(url, { method: 'HEAD' });
          const ct = (res.headers.get('content-type') ?? '').toLowerCase();
          return res.ok && !ct.includes('text/html') ? elo : null;
        } catch {
          return null;
        }
      })
    );

    const hosted = checks.filter((r): r is number => r !== null);
    const merged = Array.from(new Set([...localRatings, ...hosted])).sort((a, b) => a - b);

    this.availability = {
      checked: true,
      availableRatings: merged,
      localRatings,
      localModels,
      activeModelUrl:
        merged.length > 0
          ? localRatings.includes(merged[0])
            ? `local:${merged[0]}`
            : new URL(`models/maia-${merged[0]}.onnx`, document.baseURI).href
          : null,
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

  private callWorker<T>(
    payload: Record<string, unknown>,
    timeoutMs = 6000,
    transfer?: Transferable[],
    signal?: AbortSignal
  ): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      if (signal?.aborted) {
        reject(new EngineCancelledError('Maia search cancelled'));
        return;
      }
      let worker: Worker;
      try {
        worker = this.ensureWorker();
      } catch (err) {
        reject(err instanceof Error ? err : new Error('Maia worker unavailable'));
        return;
      }

      const id = ++this.reqId;
      const cleanup = () => {
        window.clearTimeout(timer);
        this.pendingRejectors.delete(id);
        worker.removeEventListener('message', onMsg);
        worker.removeEventListener('error', onErr);
        signal?.removeEventListener('abort', onAbort);
      };

      const onAbort = () => {
        cleanup();
        reject(new EngineCancelledError('Maia search cancelled'));
      };

      const timer = window.setTimeout(() => {
        cleanup();
        this.dispose();
        reject(new Error('Maia ONNX worker timed out'));
      }, timeoutMs);

      const onMsg = (ev: MessageEvent) => {
        if (ev.data?.id !== id) return;
        cleanup();
        if (ev.data.type === 'error') reject(new Error(ev.data.error));
        else resolve(ev.data as T);
      };

      const onErr = (ev: ErrorEvent) => {
        cleanup();
        this.dispose();
        reject(new Error(ev.message || 'Maia worker crashed'));
      };

      this.pendingRejectors.set(id, (err) => {
        cleanup();
        reject(err);
      });
      signal?.addEventListener('abort', onAbort, { once: true });
      worker.addEventListener('message', onMsg);
      worker.addEventListener('error', onErr);
      if (transfer && transfer.length > 0) {
        worker.postMessage({ ...payload, id }, transfer);
      } else {
        worker.postMessage({ ...payload, id });
      }
    });
  }

  async getMaiaMove(fen: string, targetElo: number, signal?: AbortSignal): Promise<string | null> {
    if (!this.isEnabled() || signal?.aborted) return null;
    if (!this.availability.checked) {
      await this.probeAvailableModels();
    }
    if (signal?.aborted || this.availability.availableRatings.length === 0) return null;

    const nearest = this.availability.availableRatings.reduce((best, r) =>
      Math.abs(r - targetElo) < Math.abs(best - targetElo) ? r : best
    );
    const isLocal = this.availability.localRatings.includes(nearest);
    const modelKey = isLocal ? `local:${nearest}` : new URL(`models/maia-${nearest}.onnx`, document.baseURI).href;
    const failedAt = this.failedModels.get(modelKey);
    if (failedAt && Date.now() - failedAt < FAILED_MODEL_TTL_MS) {
      return null;
    }

    try {
      if (this.loadedModelKey !== modelKey || !this.worker) {
        if (isLocal) {
          const buffer = await this.readLocalModelBuffer(nearest);
          if (!buffer || signal?.aborted) return null;
          await this.callWorker(
            { type: 'load', modelUrl: modelKey, modelKey, modelBuffer: buffer },
            15_000,
            [buffer],
            signal
          );
        } else {
          await this.callWorker({ type: 'load', modelUrl: modelKey, modelKey }, 12_000, undefined, signal);
        }
        this.loadedModelKey = modelKey;
      }
      if (signal?.aborted) return null;
      this.availability = { ...this.availability, activeModelUrl: modelKey, lastError: null };

      const chess = new Chess(fen);
      const flip = chess.turn() === 'b';
      const legalMoves = chess.moves({ verbose: true }).map((m) => {
        const uci = `${m.from}${m.to}${m.promotion ?? ''}`;
        return { uci, index: uciToLc0PolicyIndex(uci, flip) };
      });
      if (legalMoves.length === 0) return null;

      const planes = encodeFenToMaiaPlanes(fen);
      const res = await this.callWorker<{ moveUci: string | null }>(
        {
          type: 'infer',
          planes,
          legalMoves,
        },
        6000,
        undefined,
        signal
      );
      if (signal?.aborted) return null;
      return res.moveUci || null;
    } catch (err) {
      if (err instanceof EngineCancelledError || signal?.aborted) return null;
      this.failedModels.set(modelKey, Date.now());
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
  async getSmartBotMove(
    fen: string,
    targetElo: number,
    signal?: AbortSignal
  ): Promise<{ moveUci: string; engine: 'maia' | 'stockfish' }> {
    if (signal?.aborted) throw new EngineCancelledError();
    const maiaMove = await this.getMaiaMove(fen, targetElo, signal);
    if (signal?.aborted) throw new EngineCancelledError();
    if (maiaMove) {
      return { moveUci: maiaMove, engine: 'maia' };
    }
    const sfMove = await stockfishService.getBotMove(fen, targetElo, signal);
    return { moveUci: sfMove, engine: 'stockfish' };
  }

  dispose(): void {
    this.loadedModelKey = null;
    const pending = Array.from(this.pendingRejectors.values());
    this.pendingRejectors.clear();
    for (const reject of pending) {
      reject(new EngineCancelledError('Maia worker disposed'));
    }
    if (this.worker) {
      this.worker.terminate();
      this.worker = null;
    }
  }
}

export const maiaService = new MaiaEngineService();
