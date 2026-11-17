import { Chess } from 'chess.js';
import type { EngineEval, EngineScore, MultiPvLine, PlayerColor } from '../types/chess';
import { buildEngineScore } from '../utils/chessMath';

interface PendingJob {
  cancelled: boolean;
  resolve: (bestMove: string) => void;
  reject: (err: Error) => void;
  onLine: (line: string) => void;
  timeoutId?: number;
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
          if (this.activeJob) {
            this.activeJob.reject(new Error(msg));
            this.activeJob = null;
          }
          reject(new Error(msg));
          this.dispose();
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
                if (job.timeoutId) window.clearTimeout(job.timeoutId);
                job.resolve(job.cancelled ? '' : best);
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

  private runUciSearch(commands: string[], onLine: (l: string) => void, timeoutMs: number): Promise<string> {
    return this.enqueue(async () => {
      await this.init();
      if (!this.worker) throw new Error('Stockfish worker unavailable.');
      return new Promise<string>((resolve, reject) => {
        const job: PendingJob = { cancelled: false, resolve, reject, onLine };
        job.timeoutId = window.setTimeout(() => {
          if (this.activeJob === job && this.worker) this.worker.postMessage('stop');
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
            if (this.activeJob === job) this.dispose();
            resolve();
            return;
          }
          window.setTimeout(poll, 35);
        };
        poll();
      });
    }
  }

  async analyzePosition(fen: string, opts: { depth?: number; multiPv?: number; timeoutMs?: number } = {}): Promise<EngineEval> {
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
    const lineMap = new Map<number, { depth: number; score: EngineScore; pv: string[]; exact: boolean }>();
    const cmds: string[] = [];

    if (this.lastLimitStrength !== false) { cmds.push('setoption name UCI_LimitStrength value false'); this.lastLimitStrength = false; }
    if (this.lastSkill !== 20) { cmds.push('setoption name Skill Level value 20'); this.lastSkill = 20; }
    if (this.lastMultiPv !== multiPv) { cmds.push(`setoption name MultiPV value ${multiPv}`); this.lastMultiPv = multiPv; }
    cmds.push(`position fen ${fen}`, `go depth ${depth}`);

    const bestFromEnd = await this.runUciSearch(cmds, (line) => {
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

      const prev = lineMap.get(mpv);
      if (!prev || parsedDepth > prev.depth || (parsedDepth === prev.depth && (!isBound || !prev.exact))) {
        lineMap.set(mpv, { depth: parsedDepth, score, pv: pvMoves, exact: !isBound });
      }
    }, timeoutMs);

    const lines: MultiPvLine[] = Array.from(lineMap.entries())
      .sort((a, b) => a[0] - b[0])
      .map(([multipv, d]) => ({ multipv, bestMoveUci: d.pv[0] ?? bestFromEnd, pv: d.pv, score: d.score }));

    const primary = lines[0];
    const bestMoveUci = primary?.bestMoveUci || bestFromEnd;
    return {
      fen,
      depth,
      bestMoveUci,
      pv: primary?.pv ?? (bestMoveUci ? [bestMoveUci] : []),
      score: primary?.score ?? buildEngineScore(0, null),
      lines,
    };
  }

  async getBotMove(fen: string, targetElo: number): Promise<string> {
    const cmds: string[] = [];
    if (this.lastMultiPv !== 1) { cmds.push('setoption name MultiPV value 1'); this.lastMultiPv = 1; }
    if (targetElo < 1320) {
      if (this.lastLimitStrength !== false) { cmds.push('setoption name UCI_LimitStrength value false'); this.lastLimitStrength = false; }
      if (this.lastSkill !== 2) { cmds.push('setoption name Skill Level value 2'); this.lastSkill = 2; }
      cmds.push(`position fen ${fen}`, 'go depth 5 movetime 250');
    } else {
      const elo = Math.min(3190, Math.max(1320, Math.round(targetElo)));
      if (this.lastLimitStrength !== true) { cmds.push('setoption name UCI_LimitStrength value true'); this.lastLimitStrength = true; }
      if (this.lastElo !== elo) { cmds.push(`setoption name UCI_Elo value ${elo}`); this.lastElo = elo; }
      cmds.push(`position fen ${fen}`, 'go movetime 550');
    }
    return this.runUciSearch(cmds, () => undefined, 5000);
  }

  dispose(): void {
    if (this.worker) { this.worker.terminate(); this.worker = null; }
    this.initPromise = null;
    this.activeJob = null;
    this.lastMultiPv = 0;
    this.lastLimitStrength = null;
    this.lastElo = 0;
    this.lastSkill = -1;
  }
}

export const stockfishService = new StockfishEngineService();
