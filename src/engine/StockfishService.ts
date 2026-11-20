import { Chess } from 'chess.js';
import type { EngineEval, EngineScore, MultiPvLine, PlayerColor } from '../types/chess';
import { buildEngineScore } from '../utils/chessMath';

export class EngineCancelledError extends Error {
  constructor(message = 'Stockfish search cancelled') {
    super(message);
    this.name = 'EngineCancelledError';
  }
}

interface PendingJob {
  cancelled: boolean;
  resolve: (bestMove: string) => void;
  reject: (err: Error) => void;
  onLine: (line: string) => void;
  timeoutId?: number;
  hardTimeoutId?: number;
}

class StockfishEngineService {
  private worker: Worker | null = null;
  private initPromise: Promise<void> | null = null;
  private queue: Promise<unknown> = Promise.resolve();
  private activeJob: PendingJob | null = null;
  private lastMultiPv = 0;
  private lastLimitStrength: boolean | null = null;
  private lastElo = 0;
  private lastSkill = -1;

  async init(): Promise<void> {
    if (this.initPromise) return this.initPromise;
    this.initPromise = new Promise<void>((resolve, reject) => {
      try {
        const worker = new Worker(new URL('stockfish.js', document.baseURI).href);
        this.worker = worker;
        let gotUciOk = false;
        const bootTimeout = window.setTimeout(() => {
          reject(new Error('Stockfish WASM timed out during boot.'));
          this.dispose();
        }, 18000);

        worker.onerror = (ev) => {
          window.clearTimeout(bootTimeout);
          const msg = ev.message || 'Could not load ./stockfish.js or ./stockfish.wasm';
          reject(new Error(msg));
          this.dispose(new Error(msg));
        };

        worker.onmessage = (ev: MessageEvent<string>) => {
          const text = typeof ev.data === 'string' ? ev.data : String(ev.data);
          for (const raw of text.split(/\r?\n/)) {
            const line = raw.trim();
            if (!line) continue;
            if (!gotUciOk && line === 'uciok') {
              gotUciOk = true;
              worker.postMessage('setoption name Hash value 16');
              worker.postMessage('setoption name Threads value 1');
              worker.postMessage('isready');
              continue;
            }
            if (gotUciOk && line === 'readyok' && !this.activeJob) {
              window.clearTimeout(bootTimeout);
              resolve();
              continue;
            }
            if (this.activeJob) {
              if (!this.activeJob.cancelled) this.activeJob.onLine(line);
              if (line.startsWith('bestmove')) {
                const parts = line.split(/\s+/);
                const best = parts[1] && parts[1] !== '(none)' ? parts[1] : '';
                const job = this.activeJob;
                this.activeJob = null;
                if (job.timeoutId !== undefined) window.clearTimeout(job.timeoutId);
                if (job.hardTimeoutId !== undefined) window.clearTimeout(job.hardTimeoutId);
                if (job.cancelled) {
                  job.reject(new EngineCancelledError());
                } else {
                  job.resolve(best);
                }
              }
            }
          }
        };
        worker.postMessage('uci');
      } catch (err) {
        reject(err instanceof Error ? err : new Error('Web Worker unsupported.'));
        this.initPromise = null;
      }
    });
    return this.initPromise;
  }

  private enqueue<T>(task: () => Promise<T>): Promise<T> {
    const next = this.queue.then(task, task);
    this.queue = next.catch(() => undefined);
    return next;
  }

  private runUciSearch(
    buildCommands: () => string[],
    onLine: (l: string) => void,
    timeoutMs: number,
    signal?: AbortSignal
  ): Promise<string> {
    return this.enqueue(async () => {
      if (signal?.aborted) throw new EngineCancelledError();
      await this.init();
      if (signal?.aborted) throw new EngineCancelledError();
      if (!this.worker) throw new Error('Stockfish worker unavailable.');
      const commands = buildCommands();
      return new Promise<string>((resolve, reject) => {
        const job: PendingJob = { cancelled: false, resolve, reject, onLine };

        const onAbort = () => {
          if (this.activeJob === job && !job.cancelled) {
            job.cancelled = true;
            this.worker?.postMessage('stop');
            job.hardTimeoutId = window.setTimeout(() => {
              if (this.activeJob === job) {
                this.dispose(new EngineCancelledError());
              }
            }, 1400);
          }
        };

        if (signal) {
          signal.addEventListener('abort', onAbort, { once: true });
        }

        const cleanupResolve = (best: string) => {
          if (signal) signal.removeEventListener('abort', onAbort);
          resolve(best);
        };
        const cleanupReject = (err: Error) => {
          if (signal) signal.removeEventListener('abort', onAbort);
          reject(err);
        };
        job.resolve = cleanupResolve;
        job.reject = cleanupReject;

        job.timeoutId = window.setTimeout(() => {
          if (this.activeJob === job && this.worker) {
            this.worker.postMessage('stop');
            job.hardTimeoutId = window.setTimeout(() => {
              if (this.activeJob === job) {
                this.dispose(new EngineCancelledError('Stockfish search timed out'));
              }
            }, 1800);
          }
        }, timeoutMs);

        this.activeJob = job;
        for (const cmd of commands) this.worker?.postMessage(cmd);
      });
    });
  }

  async cancelCurrent(): Promise<void> {
    const job = this.activeJob;
    if (job && this.worker) {
      job.cancelled = true;
      this.worker.postMessage('stop');
      await new Promise<void>((resolve) => {
        const start = Date.now();
        const poll = () => {
          // Only dispose the worker if this exact job is still active; a new
          // search may have replaced it while we were waiting for "bestmove".
          if (this.activeJob !== job || Date.now() - start > 1400) {
            if (this.activeJob === job) this.dispose(new EngineCancelledError());
            resolve();
            return;
          }
          window.setTimeout(poll, 35);
        };
        poll();
      });
    }
  }

  async analyzePosition(
    fen: string,
    opts: { depth?: number; multiPv?: number; timeoutMs?: number; signal?: AbortSignal } = {}
  ): Promise<EngineEval> {
    const depth = opts.depth ?? 14;
    const multiPv = opts.multiPv ?? 2;
    const timeoutMs = opts.timeoutMs ?? (depth >= 18 ? 24000 : 14000);

    const chess = new Chess(fen);
    if (chess.isGameOver()) {
      if (chess.isCheckmate()) {
        const winner: PlayerColor = chess.turn() === 'w' ? 'b' : 'w';
        return { fen, depth, bestMoveUci: '', pv: [], score: buildEngineScore(0, null, true, winner), lines: [] };
      }
      return { fen, depth, bestMoveUci: '', pv: [], score: buildEngineScore(0, null), lines: [] };
    }

    const sign = chess.turn() === 'w' ? 1 : -1;
    // Track exact lines per depth so aspiration bounds never clobber exact PVs
    // and MultiPV 1/2/3 come from a consistent search depth whenever possible.
    const exactByDepth = new Map<number, Map<number, { score: EngineScore; pv: string[] }>>();
    const deepestExact = new Map<number, { depth: number; score: EngineScore; pv: string[] }>();
    const fallbackBound = new Map<number, { depth: number; score: EngineScore; pv: string[] }>();

    const bestFromEnd = await this.runUciSearch(
      () => {
        const cmds: string[] = [];
        if (this.lastLimitStrength !== false) {
          cmds.push('setoption name UCI_LimitStrength value false');
          this.lastLimitStrength = false;
        }
        if (this.lastSkill !== 20) {
          cmds.push('setoption name Skill Level value 20');
          this.lastSkill = 20;
        }
        if (this.lastMultiPv !== multiPv) {
          cmds.push(`setoption name MultiPV value ${multiPv}`);
          this.lastMultiPv = multiPv;
        }
        cmds.push(`position fen ${fen}`, `go depth ${depth}`);
        return cmds;
      },
      (line) => {
        if (!line.startsWith('info ') || !line.includes(' score ')) return;
        const isBound = line.includes('lowerbound') || line.includes('upperbound');
        const dMatch = line.match(/\bdepth\s+(\d+)/);
        const parsedDepth = dMatch ? parseInt(dMatch[1], 10) : 0;
        const mpvMatch = line.match(/\bmultipv\s+(\d+)/);
        const mpv = mpvMatch ? parseInt(mpvMatch[1], 10) : 1;
        const mateMatch = line.match(/\bscore\s+mate\s+(-?\d+)/);
        const cpMatch = line.match(/\bscore\s+cp\s+(-?\d+)/);
        const pvMatch = line.match(/\bpv\s+(.+)$/);
        const pvMoves = pvMatch ? pvMatch[1].trim().split(/\s+/) : [];

        let score: EngineScore;
        if (mateMatch) score = buildEngineScore(0, parseInt(mateMatch[1], 10) * sign);
        else if (cpMatch) score = buildEngineScore(parseInt(cpMatch[1], 10) * sign, null);
        else return;

        if (!isBound) {
          let depthSlot = exactByDepth.get(parsedDepth);
          if (!depthSlot) {
            depthSlot = new Map();
            exactByDepth.set(parsedDepth, depthSlot);
          }
          depthSlot.set(mpv, { score, pv: pvMoves });

          const prev = deepestExact.get(mpv);
          if (!prev || parsedDepth >= prev.depth) {
            deepestExact.set(mpv, { depth: parsedDepth, score, pv: pvMoves });
          }
        } else {
          const prev = fallbackBound.get(mpv);
          if (!prev || parsedDepth >= prev.depth) {
            fallbackBound.set(mpv, { depth: parsedDepth, score, pv: pvMoves });
          }
        }
      },
      timeoutMs,
      opts.signal
    );

    const legalCount = chess.moves().length;
    const expectedSlots = Math.min(multiPv, Math.max(1, legalCount));

    // Prefer the highest depth that has a complete exact MultiPV set
    let selectedDepth = 0;
    let selectedMap: Map<number, { score: EngineScore; pv: string[] }> | null = null;
    for (const [d, slot] of exactByDepth.entries()) {
      if (slot.size >= expectedSlots && d >= selectedDepth) {
        selectedDepth = d;
        selectedMap = slot;
      }
    }

    const lines: MultiPvLine[] = [];
    if (selectedMap) {
      for (const [multipv, entry] of Array.from(selectedMap.entries()).sort((a, b) => a[0] - b[0])) {
        const moveUci = entry.pv[0] ?? (multipv === 1 ? bestFromEnd : '');
        if (!moveUci) continue;
        lines.push({ multipv, bestMoveUci: moveUci, pv: entry.pv, score: entry.score });
      }
    } else {
      const merged = deepestExact.size > 0 ? deepestExact : fallbackBound;
      const seenMoves = new Set<string>();
      for (const [multipv, entry] of Array.from(merged.entries()).sort((a, b) => a[0] - b[0])) {
        const moveUci = entry.pv[0] ?? (multipv === 1 ? bestFromEnd : '');
        if (!moveUci || seenMoves.has(moveUci)) continue;
        seenMoves.add(moveUci);
        selectedDepth = Math.max(selectedDepth, entry.depth);
        lines.push({ multipv: lines.length + 1, bestMoveUci: moveUci, pv: entry.pv, score: entry.score });
      }
    }

    const primary = lines[0];
    const bestMoveUci = primary?.bestMoveUci || bestFromEnd;
    return {
      fen,
      depth: selectedDepth || depth,
      bestMoveUci,
      pv: primary?.pv ?? (bestMoveUci ? [bestMoveUci] : []),
      score: primary?.score ?? buildEngineScore(0, null),
      lines,
    };
  }

  async getBotMove(fen: string, targetElo: number, signal?: AbortSignal): Promise<string> {
    return this.runUciSearch(
      () => {
        const cmds: string[] = [];
        if (this.lastMultiPv !== 1) {
          cmds.push('setoption name MultiPV value 1');
          this.lastMultiPv = 1;
        }
        if (targetElo < 1320) {
          if (this.lastLimitStrength !== false) {
            cmds.push('setoption name UCI_LimitStrength value false');
            this.lastLimitStrength = false;
          }
          if (this.lastSkill !== 2) {
            cmds.push('setoption name Skill Level value 2');
            this.lastSkill = 2;
          }
          cmds.push(`position fen ${fen}`, 'go depth 5 movetime 250');
        } else {
          const elo = Math.min(3190, Math.max(1320, Math.round(targetElo)));
          if (this.lastSkill !== 20) {
            cmds.push('setoption name Skill Level value 20');
            this.lastSkill = 20;
          }
          if (this.lastLimitStrength !== true) {
            cmds.push('setoption name UCI_LimitStrength value true');
            this.lastLimitStrength = true;
          }
          if (this.lastElo !== elo) {
            cmds.push(`setoption name UCI_Elo value ${elo}`);
            this.lastElo = elo;
          }
          cmds.push(`position fen ${fen}`, 'go movetime 550');
        }
        return cmds;
      },
      () => undefined,
      5000,
      signal
    );
  }

  dispose(reason?: Error): void {
    const pending = this.activeJob;
    this.activeJob = null;
    if (pending) {
      if (pending.timeoutId !== undefined) window.clearTimeout(pending.timeoutId);
      if (pending.hardTimeoutId !== undefined) window.clearTimeout(pending.hardTimeoutId);
      pending.reject(reason ?? new EngineCancelledError('Stockfish worker disposed'));
    }
    if (this.worker) {
      this.worker.terminate();
      this.worker = null;
    }
    this.initPromise = null;
    this.lastMultiPv = 0;
    this.lastLimitStrength = null;
    this.lastElo = 0;
    this.lastSkill = -1;
  }
}

export const stockfishService = new StockfishEngineService();
