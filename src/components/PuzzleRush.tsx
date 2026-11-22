import React, { useEffect, useRef, useState } from 'react';
import { Chess, type PieceSymbol, type Square } from 'chess.js';
import {
  ArrowRight,
  CheckCircle2,
  Flame,
  GraduationCap,
  Heart,
  Play,
  RotateCcw,
  Shield,
  Sparkles,
  Target,
  Timer,
  Trophy,
  XCircle,
  Zap,
} from 'lucide-react';
import type { BoardThemeId, MistakePuzzle } from '../types/chess';
import { loadRushBest, saveRushBest, type PuzzleRushMode } from '../services/mistakeDeck';
import { soundManager } from '../utils/sound';
import { ChessgroundBoard } from './ChessgroundBoard';

interface Props {
  puzzles: MistakePuzzle[];
  boardTheme: BoardThemeId;
  storageRevision?: number;
  onExit: () => void;
  onSolved: (puzzle: MistakePuzzle) => void;
  onWrong: (puzzle: MistakePuzzle) => void;
  onFinished: (score: number) => void;
}

type RushPhase = 'ready' | 'running' | 'finished';
type MoveStatus = 'idle' | 'wrong' | 'correct';

const RUSH_SECONDS = 180;
const MAX_STRIKES = 3;

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

export const PuzzleRush: React.FC<Props> = ({ puzzles, boardTheme, storageRevision = 0, onExit, onSolved, onWrong, onFinished }) => {
  const [rushMode, setRushMode] = useState<PuzzleRushMode>('blitz');
  const [phase, setPhase] = useState<RushPhase>('ready');
  const [queue, setQueue] = useState<MistakePuzzle[]>([]);
  const [index, setIndex] = useState(0);
  const [fen, setFen] = useState('');
  const [lastMove, setLastMove] = useState<[string, string] | undefined>();
  const [pendingPromo, setPendingPromo] = useState<{ from: Square; to: Square } | null>(null);
  const [status, setStatus] = useState<MoveStatus>('idle');
  const [score, setScore] = useState(0);
  const [solved, setSolved] = useState(0);
  const [misses, setMisses] = useState(0);
  const [combo, setCombo] = useState(0);
  const [bestCombo, setBestCombo] = useState(0);
  const [secondsLeft, setSecondsLeft] = useState(RUSH_SECONDS);
  const [best, setBest] = useState(() => loadRushBest('blitz'));
  const [isNewBest, setIsNewBest] = useState(false);
  const endsAtRef = useRef(0);
  const runBestRef = useRef(0);
  const advanceTimerRef = useRef<number | null>(null);
  const runGenerationRef = useRef(0);
  const finishedHandledRef = useRef(false);

  const current = queue[index] ?? null;
  const interactive = phase === 'running' && status === 'idle' && Boolean(current) && !pendingPromo;
  const strikesLeft = Math.max(0, MAX_STRIKES - misses);

  useEffect(() => {
    setBest(loadRushBest(rushMode));
  }, [rushMode, storageRevision]);

  const clearAdvanceTimer = () => {
    if (advanceTimerRef.current) {
      window.clearTimeout(advanceTimerRef.current);
      advanceTimerRef.current = null;
    }
  };

  useEffect(() => () => clearAdvanceTimer(), []);

  useEffect(() => {
    if (phase !== 'running' || rushMode !== 'blitz') return;
    const tick = () => {
      const left = Math.max(0, Math.ceil((endsAtRef.current - Date.now()) / 1000));
      setSecondsLeft(left);
      if (left <= 0) setPhase('finished');
    };
    tick();
    const timer = window.setInterval(tick, 200);
    return () => window.clearInterval(timer);
  }, [phase, rushMode]);

  useEffect(() => {
    if (phase !== 'finished' || finishedHandledRef.current) return;
    finishedHandledRef.current = true;
    clearAdvanceTimer();
    setPendingPromo(null);
    const isRecord = score > runBestRef.current;
    const nextBest = saveRushBest(score, rushMode);
    setBest(nextBest);
    setIsNewBest(isRecord);
    setStatus('idle');
    onFinished(score);
  }, [phase, score, rushMode, onFinished]);

  const start = (modeOverride?: PuzzleRushMode) => {
    if (puzzles.length === 0) return;
    const activeMode = modeOverride ?? rushMode;
    if (modeOverride) setRushMode(modeOverride);
    clearAdvanceTimer();
    runGenerationRef.current += 1;
    finishedHandledRef.current = false;
    runBestRef.current = loadRushBest(activeMode);
    setBest(runBestRef.current);
    setIsNewBest(false);
    const nextQueue = shuffle(puzzles);
    setQueue(nextQueue);
    setIndex(0);
    setFen(nextQueue[0].beforeFen);
    setLastMove(undefined);
    setPendingPromo(null);
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
    setPendingPromo(null);
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
    if (phase !== 'running' || !current || rushMode === 'survival') return;
    runGenerationRef.current += 1;
    setCombo(0);
    nextPuzzle();
  };

  const executeMove = (from: Square, to: Square, promotion?: PieceSymbol) => {
    if (!current || phase !== 'running' || status !== 'idle') return;
    const chess = new Chess(fen);
    let move;
    try {
      move = chess.move({ from, to, promotion });
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
    const nextMisses = misses + 1;
    setMisses(nextMisses);
    setStatus('wrong');
    onWrong(current);

    if (rushMode === 'survival') {
      advanceTimerRef.current = window.setTimeout(() => {
        if (runGenerationRef.current !== generation) return;
        if (nextMisses >= MAX_STRIKES) {
          setPhase('finished');
        } else {
          nextPuzzle();
        }
      }, 950);
      return;
    }

    advanceTimerRef.current = window.setTimeout(() => {
      if (runGenerationRef.current !== generation) return;
      setFen(current.beforeFen);
      setLastMove(undefined);
      setStatus('idle');
    }, 620);
  };

  const handleMove = (from: Square, to: Square) => {
    if (!current || phase !== 'running' || status !== 'idle') return;
    const legal = new Chess(fen).moves({ square: from, verbose: true }).filter((m) => m.to === to);
    if (legal.length === 0) return;
    if (legal.some((m) => Boolean(m.promotion))) {
      setPendingPromo({ from, to });
      return;
    }
    executeMove(from, to);
  };

  const timerPct =
    rushMode === 'blitz'
      ? Math.max(0, Math.min(100, (secondsLeft / RUSH_SECONDS) * 100))
      : Math.max(0, Math.min(100, (strikesLeft / MAX_STRIKES) * 100));

  const rushHeader = (
    <section className="glass-card glass-card-strong overflow-hidden p-3.5">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-fuchsia-300">
            <Zap className="h-4 w-4" /> Puzzle rush · {rushMode === 'blitz' ? '3-Min Blitz' : '3-Strikes Survival'}
          </div>
          <h1 className="mt-1 text-lg font-extrabold text-white">
            {rushMode === 'blitz' ? 'Three minutes. Every move counts.' : 'Three strikes. No clock. Pure accuracy.'}
          </h1>
          <p className="mt-0.5 text-[11px] text-slate-400">
            {rushMode === 'blitz'
              ? 'Solve your own mistakes at speed. Wrong moves reset the position and break your combo.'
              : 'Take your time and calculate carefully. Three wrong moves end the run.'}
          </p>
        </div>
        <button type="button" onClick={onExit} className="shrink-0 rounded-lg border border-slate-700 bg-slate-800/80 px-2.5 py-1.5 text-[10px] font-bold text-slate-300">
          Exit
        </button>
      </div>
      <div className="mt-3 grid grid-cols-4 gap-1.5">
        {rushMode === 'blitz' ? (
          <RushStat icon={<Timer className="h-3 w-3 text-cyan-300" />} label="Clock" value={formatClock(secondsLeft)} tone="text-cyan-300" />
        ) : (
          <RushStat
            icon={<Heart className="h-3 w-3 text-rose-400" />}
            label="Lives"
            value={`${'♥'.repeat(strikesLeft)}${'♡'.repeat(MAX_STRIKES - strikesLeft)}`}
            tone={strikesLeft <= 1 ? 'text-rose-400' : 'text-rose-300'}
          />
        )}
        <RushStat icon={<Trophy className="h-3 w-3 text-amber-300" />} label="Score" value={String(score)} tone="text-amber-300" />
        <RushStat icon={<Flame className="h-3 w-3 text-orange-300" />} label="Combo" value={`${combo}x`} tone="text-orange-300" />
        <RushStat icon={<Sparkles className="h-3 w-3 text-fuchsia-300" />} label="Best" value={String(best)} tone="text-fuchsia-300" />
      </div>
      <div className="mt-2 h-2 overflow-hidden rounded-full bg-slate-800">
        <div
          className={`h-full rounded-full transition-all duration-200 ${
            (rushMode === 'blitz' && secondsLeft <= 20) || (rushMode === 'survival' && strikesLeft <= 1)
              ? 'bg-gradient-to-r from-rose-500 to-orange-400'
              : 'bg-gradient-to-r from-fuchsia-400 to-cyan-400'
          }`}
          style={{ width: `${timerPct}%` }}
        />
      </div>
    </section>
  );

  if (phase === 'ready') {
    const blitzBest = loadRushBest('blitz');
    const survivalBest = loadRushBest('survival');
    return (
      <div className="space-y-3 pb-24">
        {rushHeader}
        <section className="glass-card p-5 text-center sm:p-6">
          <Target className="mx-auto h-10 w-10 text-fuchsia-300" />
          <h2 className="mt-2 text-base font-extrabold text-slate-100">Choose your rush format</h2>
          <p className="mx-auto mt-1 max-w-md text-xs leading-relaxed text-slate-400">
            {puzzles.length} puzzles from your own games. Pick a mode below to begin.
          </p>

          <div className="mx-auto mt-4 grid max-w-md grid-cols-2 gap-2 text-left">
            <button
              type="button"
              onClick={() => setRushMode('blitz')}
              className={`rounded-xl border p-3 transition ${
                rushMode === 'blitz'
                  ? 'border-fuchsia-400/60 bg-fuchsia-500/15'
                  : 'border-slate-800 bg-slate-950/50 hover:border-slate-600'
              }`}
            >
              <div className="flex items-center justify-between gap-1">
                <span className="inline-flex items-center gap-1 text-xs font-extrabold text-white">
                  <Timer className="h-3.5 w-3.5 text-cyan-300" /> 3-Min Blitz
                </span>
                <span className="rounded bg-slate-900 px-1.5 py-0.5 font-mono text-[9px] text-fuchsia-200">
                  best {blitzBest}
                </span>
              </div>
              <p className="mt-1 text-[10px] leading-snug text-slate-400">
                Race the 3:00 clock. Misses reset the position and break combo.
              </p>
            </button>

            <button
              type="button"
              onClick={() => setRushMode('survival')}
              className={`rounded-xl border p-3 transition ${
                rushMode === 'survival'
                  ? 'border-rose-400/60 bg-rose-500/15'
                  : 'border-slate-800 bg-slate-950/50 hover:border-slate-600'
              }`}
            >
              <div className="flex items-center justify-between gap-1">
                <span className="inline-flex items-center gap-1 text-xs font-extrabold text-white">
                  <Shield className="h-3.5 w-3.5 text-rose-300" /> 3-Strikes
                </span>
                <span className="rounded bg-slate-900 px-1.5 py-0.5 font-mono text-[9px] text-rose-200">
                  best {survivalBest}
                </span>
              </div>
              <p className="mt-1 text-[10px] leading-snug text-slate-400">
                Untimed survival. Three wrong moves end the run.
              </p>
            </button>
          </div>

          <button
            type="button"
            onClick={() => start(rushMode)}
            className="mt-4 inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-fuchsia-400 to-cyan-400 px-5 py-2.5 text-xs font-black text-slate-950"
          >
            <Play className="h-4 w-4" /> Start {rushMode === 'blitz' ? '3-Min Blitz' : '3-Strikes Survival'}
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
            <button type="button" onClick={() => start(rushMode)} className="inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-fuchsia-400 to-cyan-400 px-4 py-2.5 text-xs font-black text-slate-950">
              <RotateCcw className="h-4 w-4" /> Run it back
            </button>
            <button
              type="button"
              onClick={() => setPhase('ready')}
              className="inline-flex items-center gap-1.5 rounded-xl border border-fuchsia-400/35 bg-fuchsia-500/10 px-4 py-2.5 text-xs font-bold text-fuchsia-200"
            >
              Switch mode
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

      <div className="grid grid-cols-1 items-start gap-3 lg:grid-cols-[minmax(0,1fr)_minmax(380px,440px)]">
        <section className="min-w-0">
          <div className="mx-auto w-full lg:max-w-[max(320px,calc(100dvh-23rem))]">
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
                    bestMoveUci={status === 'correct' || (rushMode === 'survival' && status === 'wrong') ? current.bestMoveUci : undefined}
                    showBestArrow={status === 'correct' || (rushMode === 'survival' && status === 'wrong')}
                    showPlayedArrow={false}
                    theme={boardTheme}
                    onUserMove={handleMove}
                  />
                  {pendingPromo && (
                    <div
                      className="absolute inset-0 z-40 flex items-center justify-center rounded-xl bg-slate-950/80 backdrop-blur-sm"
                      onClick={(e) => {
                        if (e.target === e.currentTarget) setPendingPromo(null);
                      }}
                    >
                      <div className="rounded-2xl border border-slate-700 bg-slate-900 p-3">
                        <div className="flex gap-2">
                          {([
                            ['q', 'Queen', current.color === 'w' ? '♕' : '♛'],
                            ['r', 'Rook', current.color === 'w' ? '♖' : '♜'],
                            ['b', 'Bishop', current.color === 'w' ? '♗' : '♝'],
                            ['n', 'Knight', current.color === 'w' ? '♘' : '♞'],
                          ] as Array<[PieceSymbol, string, string]>).map(([p, name, glyph]) => (
                            <button
                              key={p}
                              type="button"
                              aria-label={`Promote to ${name}`}
                              onClick={() => {
                                const promo = pendingPromo;
                                setPendingPromo(null);
                                executeMove(promo.from, promo.to, p);
                              }}
                              className="flex h-11 w-11 items-center justify-center rounded-xl border border-slate-700 bg-slate-800 text-2xl text-white hover:border-teal-400"
                            >
                              {glyph}
                            </button>
                          ))}
                        </div>
                        <button
                          type="button"
                          onClick={() => setPendingPromo(null)}
                          className="mt-2 w-full rounded-lg border border-slate-800 bg-void/70 py-1 text-[10px] font-bold text-slate-400 hover:text-slate-200"
                        >
                          Cancel
                        </button>
                      </div>
                    </div>
                  )}
                  {status === 'wrong' && (
                    <div className="pointer-events-none absolute inset-x-0 bottom-2 z-30 flex justify-center">
                      <span className="rounded-full border border-rose-400/40 bg-rose-950/85 px-3 py-1 text-[10px] font-bold text-rose-200 backdrop-blur">
                        {rushMode === 'survival'
                          ? `Strike ${misses}/${MAX_STRIKES} — best was ${current.bestMoveSan}`
                          : 'Not the best — resetting…'}
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
                  {rushMode === 'blitz' && (
                    <button
                      type="button"
                      onClick={skip}
                      className="flex-1 rounded-xl border border-slate-700 bg-slate-900/80 px-3 py-2 text-[11px] font-bold text-slate-300"
                    >
                      Skip this one <ArrowRight className="inline h-3 w-3" />
                    </button>
                  )}
                  <button
                    type="button"
                    onClick={() => setPhase('finished')}
                    className={`${rushMode === 'survival' ? 'flex-1 ' : ''}rounded-xl border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-[11px] font-bold text-rose-200`}
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
              <Zap className="h-4 w-4 text-fuchsia-400" /> {rushMode === 'blitz' ? '3-Min Blitz' : '3-Strikes Survival'}
            </div>
            <p className="mt-1 text-[11px] leading-relaxed text-slate-400">
              {rushMode === 'blitz'
                ? 'Only Stockfish’s top move scores. Find the idea fast — wrong moves cost time, not lives.'
                : 'No clock, 3 lives. Play Stockfish’s best move on the first try — three misses end the run.'}
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
