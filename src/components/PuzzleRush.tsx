import React, { useEffect, useRef, useState } from 'react';
import { Chess, type Square } from 'chess.js';
import {
  ArrowRight,
  CheckCircle2,
  Flame,
  GraduationCap,
  Play,
  RotateCcw,
  Sparkles,
  Target,
  Timer,
  Trophy,
  XCircle,
  Zap,
} from 'lucide-react';
import type { BoardThemeId, MistakePuzzle } from '../types/chess';
import { loadRushBest, saveRushBest } from '../services/mistakeDeck';
import { soundManager } from '../utils/sound';
import { ChessgroundBoard } from './ChessgroundBoard';

interface Props {
  puzzles: MistakePuzzle[];
  boardTheme: BoardThemeId;
  onExit: () => void;
  onSolved: (puzzle: MistakePuzzle) => void;
  onWrong: (puzzle: MistakePuzzle) => void;
  onFinished: (score: number) => void;
}

type RushPhase = 'ready' | 'running' | 'finished';
type MoveStatus = 'idle' | 'wrong' | 'correct';

const RUSH_SECONDS = 180;

function shuffle<T>(items: T[]): T[] {
  const copy = items.slice();
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

function formatClock(seconds: number): string {
  const safe = Math.max(0, seconds);
  return `${Math.floor(safe / 60)}:${String(safe % 60).padStart(2, '0')}`;
}

export const PuzzleRush: React.FC<Props> = ({ puzzles, boardTheme, onExit, onSolved, onWrong, onFinished }) => {
  const [phase, setPhase] = useState<RushPhase>('ready');
  const [queue, setQueue] = useState<MistakePuzzle[]>([]);
  const [index, setIndex] = useState(0);
  const [fen, setFen] = useState('');
  const [lastMove, setLastMove] = useState<[string, string] | undefined>();
  const [status, setStatus] = useState<MoveStatus>('idle');
  const [score, setScore] = useState(0);
  const [solved, setSolved] = useState(0);
  const [misses, setMisses] = useState(0);
  const [combo, setCombo] = useState(0);
  const [bestCombo, setBestCombo] = useState(0);
  const [secondsLeft, setSecondsLeft] = useState(RUSH_SECONDS);
  const [best, setBest] = useState(() => loadRushBest());
  const [isNewBest, setIsNewBest] = useState(false);
  const endsAtRef = useRef(0);
  const runBestRef = useRef(0);
  const advanceTimerRef = useRef<number | null>(null);
  const runGenerationRef = useRef(0);
  const finishedHandledRef = useRef(false);

  const current = queue[index] ?? null;
  const interactive = phase === 'running' && status === 'idle' && Boolean(current);

  const clearAdvanceTimer = () => {
    if (advanceTimerRef.current) {
      window.clearTimeout(advanceTimerRef.current);
      advanceTimerRef.current = null;
    }
  };

  useEffect(() => () => clearAdvanceTimer(), []);

  useEffect(() => {
    if (phase !== 'running') return;
    const tick = () => {
      const left = Math.max(0, Math.ceil((endsAtRef.current - Date.now()) / 1000));
      setSecondsLeft(left);
      if (left <= 0) setPhase('finished');
    };
    tick();
    const timer = window.setInterval(tick, 200);
    return () => window.clearInterval(timer);
  }, [phase]);

  useEffect(() => {
    if (phase !== 'finished' || finishedHandledRef.current) return;
    finishedHandledRef.current = true;
    clearAdvanceTimer();
    const isRecord = score > runBestRef.current;
    const nextBest = saveRushBest(score);
    setBest(nextBest);
    setIsNewBest(isRecord);
    setStatus('idle');
    onFinished(score);
  }, [phase, score, onFinished]);

  const start = () => {
    if (puzzles.length === 0) return;
    clearAdvanceTimer();
    runGenerationRef.current += 1;
    finishedHandledRef.current = false;
    runBestRef.current = loadRushBest();
    setIsNewBest(false);
    const nextQueue = shuffle(puzzles);
    setQueue(nextQueue);
    setIndex(0);
    setFen(nextQueue[0].beforeFen);
    setLastMove(undefined);
    setStatus('idle');
    setScore(0);
    setSolved(0);
    setMisses(0);
    setCombo(0);
    setBestCombo(0);
    setSecondsLeft(RUSH_SECONDS);
    endsAtRef.current = Date.now() + RUSH_SECONDS * 1000;
    setPhase('running');
    soundManager.unlock();
  };

  const nextPuzzle = () => {
    clearAdvanceTimer();
    if (queue.length === 0) return;
    const nextIndex = index + 1;
    if (nextIndex >= queue.length) {
      const reshuffled = shuffle(puzzles);
      setQueue(reshuffled);
      setIndex(0);
      setFen(reshuffled[0].beforeFen);
    } else {
      setIndex(nextIndex);
      setFen(queue[nextIndex].beforeFen);
    }
    setLastMove(undefined);
    setStatus('idle');
  };

  const skip = () => {
    if (phase !== 'running' || !current) return;
    runGenerationRef.current += 1;
    setCombo(0);
    nextPuzzle();
  };

  const handleMove = (from: Square, to: Square) => {
    if (!current || phase !== 'running' || status !== 'idle') return;
    const chess = new Chess(fen);
    let move;
    try {
      move = chess.move({ from, to, promotion: 'q' });
    } catch {
      return;
    }
    const uci = `${move.from}${move.to}${move.promotion ?? ''}`;
    const generation = runGenerationRef.current + 1;
    runGenerationRef.current = generation;
    setFen(chess.fen());
    setLastMove([move.from, move.to]);

    if (uci === current.bestMoveUci) {
      soundManager.playSuccess();
      setScore((s) => s + 1);
      setSolved((s) => s + 1);
      setCombo((c) => {
        const next = c + 1;
        setBestCombo((b) => Math.max(b, next));
        return next;
      });
      setStatus('correct');
      onSolved(current);
      advanceTimerRef.current = window.setTimeout(() => {
        if (runGenerationRef.current === generation) nextPuzzle();
      }, 420);
      return;
    }

    soundManager.playError();
    setCombo(0);
    setMisses((m) => m + 1);
    setStatus('wrong');
    onWrong(current);
    advanceTimerRef.current = window.setTimeout(() => {
      if (runGenerationRef.current !== generation) return;
      setFen(current.beforeFen);
      setLastMove(undefined);
      setStatus('idle');
    }, 620);
  };

  const timerPct = Math.max(0, Math.min(100, (secondsLeft / RUSH_SECONDS) * 100));

  const rushHeader = (
    <section className="glass-card glass-card-strong overflow-hidden p-3.5">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-fuchsia-300">
            <Zap className="h-4 w-4" /> Puzzle rush
          </div>
          <h1 className="mt-1 text-lg font-extrabold text-white">Three minutes. Every move counts.</h1>
          <p className="mt-0.5 text-[11px] text-slate-400">Solve your own mistakes at speed. Wrong moves reset the position and break your combo.</p>
        </div>
        <button type="button" onClick={onExit} className="shrink-0 rounded-lg border border-slate-700 bg-slate-800/80 px-2 py-1 text-[10px] font-bold text-slate-300">
          Exit
        </button>
      </div>
      <div className="mt-3 grid grid-cols-4 gap-1.5">
        <RushStat icon={<Timer className="h-3 w-3 text-cyan-300" />} label="Clock" value={formatClock(secondsLeft)} tone="text-cyan-300" />
        <RushStat icon={<Trophy className="h-3 w-3 text-amber-300" />} label="Score" value={String(score)} tone="text-amber-300" />
        <RushStat icon={<Flame className="h-3 w-3 text-orange-300" />} label="Combo" value={`${combo}x`} tone="text-orange-300" />
        <RushStat icon={<Sparkles className="h-3 w-3 text-fuchsia-300" />} label="Best" value={String(best)} tone="text-fuchsia-300" />
      </div>
      <div className="mt-2 h-2 overflow-hidden rounded-full bg-slate-800">
        <div className={`h-full rounded-full transition-all duration-200 ${secondsLeft <= 20 ? 'bg-gradient-to-r from-rose-500 to-orange-400' : 'bg-gradient-to-r from-fuchsia-400 to-cyan-400'}`} style={{ width: `${timerPct}%` }} />
      </div>
    </section>
  );

  if (phase === 'ready') {
    return (
      <div className="space-y-3 pb-24">
        {rushHeader}
        <section className="glass-card p-6 text-center">
          <Target className="mx-auto h-10 w-10 text-fuchsia-300" />
          <h2 className="mt-2 text-base font-extrabold text-slate-100">Ready for the rush?</h2>
          <p className="mx-auto mt-1 max-w-md text-xs leading-relaxed text-slate-400">
            {puzzles.length} puzzles from your own games. Tap a piece, then tap a highlighted square. The clock starts immediately.
          </p>
          <div className="mx-auto mt-3 grid max-w-md grid-cols-3 gap-1.5 text-[10px]">
            <div className="rounded-xl border border-slate-800 bg-slate-950/45 p-2"><div className="font-black text-cyan-300">3:00</div><div className="text-slate-500">on the clock</div></div>
            <div className="rounded-xl border border-slate-800 bg-slate-950/45 p-2"><div className="font-black text-amber-300">+1</div><div className="text-slate-500">per solve</div></div>
            <div className="rounded-xl border border-slate-800 bg-slate-950/45 p-2"><div className="font-black text-orange-300">Combo</div><div className="text-slate-500">build a streak</div></div>
          </div>
          <button
            type="button"
            onClick={start}
            className="mt-4 inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-fuchsia-400 to-cyan-400 px-4 py-2.5 text-xs font-black text-slate-950"
          >
            <Play className="h-4 w-4" /> Start rush
          </button>
        </section>
      </div>
    );
  }

  if (phase === 'finished') {
    const accuracy = solved + misses > 0 ? Math.round((solved / (solved + misses)) * 100) : 0;
    return (
      <div className="space-y-3 pb-24">
        {rushHeader}
        <section className="glass-card glass-card-strong p-6 text-center">
          <Trophy className="mx-auto h-10 w-10 text-amber-300" />
          <h2 className="mt-2 text-lg font-extrabold text-white">Rush complete</h2>
          <p className="mt-0.5 text-xs text-slate-400">
            {isNewBest ? 'New personal best — that is the one to beat.' : `Personal best is still ${best}.`}
          </p>
          <div className="mx-auto mt-3 grid max-w-md grid-cols-2 gap-2 text-left sm:grid-cols-4">
            <RushStat icon={<Trophy className="h-3 w-3 text-amber-300" />} label="Score" value={String(score)} tone="text-amber-300" />
            <RushStat icon={<CheckCircle2 className="h-3 w-3 text-emerald-300" />} label="Solved" value={String(solved)} tone="text-emerald-300" />
            <RushStat icon={<XCircle className="h-3 w-3 text-rose-300" />} label="Missed" value={String(misses)} tone="text-rose-300" />
            <RushStat icon={<Flame className="h-3 w-3 text-orange-300" />} label="Best combo" value={`${bestCombo}x`} tone="text-orange-300" />
          </div>
          <div className="mx-auto mt-2 max-w-md rounded-xl border border-slate-800 bg-slate-950/45 p-2 text-[11px] text-slate-400">
            Accuracy <span className="font-mono font-bold text-cyan-300">{accuracy}%</span> · every miss is a pattern to review in the mistake deck.
          </div>
          <div className="mt-4 flex flex-wrap items-center justify-center gap-2">
            <button type="button" onClick={start} className="inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-fuchsia-400 to-cyan-400 px-4 py-2.5 text-xs font-black text-slate-950">
              <RotateCcw className="h-4 w-4" /> Run it back
            </button>
            <button type="button" onClick={onExit} className="inline-flex items-center gap-1.5 rounded-xl border border-slate-700 bg-slate-800/80 px-4 py-2.5 text-xs font-bold text-slate-200">
              <GraduationCap className="h-4 w-4" /> Back to practice
            </button>
          </div>
        </section>
      </div>
    );
  }

  return (
    <div className="space-y-3 pb-24">
      {rushHeader}

      <div className="grid items-start gap-3 lg:grid-cols-[minmax(0,1fr)_minmax(380px,440px)]">
        <section className="min-w-0">
          <div className="mx-auto w-full lg:max-w-[calc(100dvh-23rem)]">
            {current && (
              <>
                <div className="mb-1.5 flex items-center justify-between gap-2 rounded-xl border border-slate-800 bg-slate-900/75 px-2.5 py-1.5">
                  <div className="flex min-w-0 items-center gap-2">
                    <span className={`h-2.5 w-2.5 shrink-0 rounded-full border ${current.color === 'w' ? 'border-slate-300 bg-white' : 'border-slate-500 bg-slate-950'}`} />
                    <span className="truncate text-[11px] font-bold text-slate-200">{current.playerName}</span>
                    <span className="text-[10px] text-slate-500">to move</span>
                  </div>
                  <span className={`shrink-0 rounded px-1.5 py-0.5 text-[9px] font-black ${current.classification === 'blunder' ? 'bg-rose-500/15 text-rose-300' : 'bg-orange-500/15 text-orange-300'}`}>
                    {current.classification === 'blunder' ? '??' : '?'} {current.moveNumber}{current.color === 'w' ? '.' : '…'} {current.san}
                  </span>
                </div>

                <div className="relative">
                  <ChessgroundBoard
                    fen={fen || current.beforeFen}
                    orientation={current.color}
                    interactive={interactive}
                    turnColor={current.color}
                    lastMove={lastMove}
                    bestMoveUci={status === 'correct' ? current.bestMoveUci : undefined}
                    showBestArrow={status === 'correct'}
                    showPlayedArrow={false}
                    theme={boardTheme}
                    onUserMove={handleMove}
                  />
                  {status === 'wrong' && (
                    <div className="pointer-events-none absolute inset-x-0 bottom-2 z-30 flex justify-center">
                      <span className="rounded-full border border-rose-400/40 bg-rose-950/85 px-3 py-1 text-[10px] font-bold text-rose-200 backdrop-blur">
                        Not the best — resetting…
                      </span>
                    </div>
                  )}
                  {status === 'correct' && (
                    <div className="pointer-events-none absolute inset-x-0 bottom-2 z-30 flex justify-center">
                      <span className="rounded-full border border-emerald-400/40 bg-emerald-950/85 px-3 py-1 text-[10px] font-bold text-emerald-200 backdrop-blur">
                        Solved! Next puzzle →
                      </span>
                    </div>
                  )}
                </div>

                <div className="mt-1.5 flex items-center gap-2">
                  <button
                    type="button"
                    onClick={skip}
                    className="flex-1 rounded-xl border border-slate-700 bg-slate-900/80 px-3 py-2 text-[11px] font-bold text-slate-300"
                  >
                    Skip this one <ArrowRight className="inline h-3 w-3" />
                  </button>
                  <button
                    type="button"
                    onClick={() => setPhase('finished')}
                    className="rounded-xl border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-[11px] font-bold text-rose-200"
                  >
                    End rush
                  </button>
                </div>
              </>
            )}
          </div>
        </section>

        <aside className="min-w-0 space-y-2.5">
          <div className="glass-card p-3.5">
            <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
              <Zap className="h-4 w-4 text-fuchsia-400" /> Rush mode
            </div>
            <p className="mt-1 text-[11px] leading-relaxed text-slate-400">
              Only Stockfish’s top move scores. Find the idea, tap the piece, tap the target square. Wrong moves cost time, not points.
            </p>
            {current && (
              <div className="mt-2 rounded-xl border border-slate-800 bg-slate-950/45 p-2 text-[10px]">
                <div className="truncate text-slate-300">{current.openingEco ? `${current.openingEco} · ` : ''}{current.openingName}</div>
                <div className="mt-0.5 text-slate-500">You played <span className="font-mono font-bold text-orange-300">{current.san}</span> here.</div>
              </div>
            )}
          </div>
          <div className="glass-card p-3.5">
            <div className="text-[10px] font-black uppercase tracking-[0.14em] text-slate-400">Run stats</div>
            <div className="mt-2 grid grid-cols-2 gap-1.5">
              <RushStat icon={<CheckCircle2 className="h-3 w-3 text-emerald-300" />} label="Solved" value={String(solved)} tone="text-emerald-300" />
              <RushStat icon={<XCircle className="h-3 w-3 text-rose-300" />} label="Missed" value={String(misses)} tone="text-rose-300" />
              <RushStat icon={<Flame className="h-3 w-3 text-orange-300" />} label="Best combo" value={`${bestCombo}x`} tone="text-orange-300" />
              <RushStat icon={<Trophy className="h-3 w-3 text-amber-300" />} label="Personal best" value={String(best)} tone="text-amber-300" />
            </div>
          </div>
        </aside>
      </div>
    </div>
  );
};

const RushStat: React.FC<{ icon: React.ReactNode; label: string; value: string; tone: string }> = ({ icon, label, value, tone }) => (
  <div className="rounded-lg border border-slate-800 bg-slate-950/45 px-2 py-1.5">
    <div className="flex items-center gap-1 text-[8px] font-bold uppercase tracking-wide text-slate-500">{icon}{label}</div>
    <div className={`mt-0.5 font-mono text-sm font-black ${tone}`}>{value}</div>
  </div>
);
