import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Chess, type Square } from 'chess.js';
import {
  CheckCircle2,
  Clock,
  Rocket,
  RotateCcw,
  Sparkles,
  Timer,
  X,
  XCircle,
} from 'lucide-react';
import type { BoardThemeId, MistakePuzzle } from '../../types/chess';
import type { BoardArrow, FsrsOpeningCard, OpeningCourse } from '../../types/openings';
import { buildGravityCheckItems, type GravityFlashItem } from '../../services/dailyCoach';
import { reviewFsrsOpeningCard } from '../../lib/fsrsOpening';
import { uciToSquares } from '../../utils/chessMath';
import { soundManager } from '../../utils/sound';
import { useVibe } from '../../utils/vibeCopy';
import { ChessgroundBoard } from '../ChessgroundBoard';

interface Props {
  open: boolean;
  onClose: () => void;
  deck: MistakePuzzle[];
  fsrsCards: FsrsOpeningCard[];
  courses: OpeningCourse[];
  boardTheme: BoardThemeId;
  onCardReviewed: (updated: FsrsOpeningCard) => Promise<void>;
  onCompleted?: (summary: { hits: number; total: number; avgMs: number }) => void;
}

interface ItemResult {
  id: string;
  kind: 'tactic' | 'opening';
  hit: boolean;
  ms: number;
  expectedSan: string;
}

export const GravityCheckModal: React.FC<Props> = ({
  open,
  onClose,
  deck,
  fsrsCards,
  courses,
  boardTheme,
  onCardReviewed,
  onCompleted,
}) => {
  const { copy } = useVibe();
  const [runKey, setRunKey] = useState(0);
  const [idx, setIdx] = useState(0);
  const [secondsLeft, setSecondsLeft] = useState(8);
  const [phaseState, setPhaseState] = useState<'active' | 'feedback' | 'summary'>('active');
  const [lastOutcome, setLastOutcome] = useState<'hit' | 'miss' | 'timeout' | null>(null);
  const [results, setResults] = useState<ItemResult[]>([]);
  const [boardFen, setBoardFen] = useState('');
  const [arrows, setArrows] = useState<BoardArrow[] | undefined>(undefined);

  const startedAtRef = useRef<number>(performance.now());
  const nextTimerRef = useRef<number | null>(null);
  const resolvedStepRef = useRef<string>('');
  const resultsRef = useRef<ItemResult[]>([]);
  const onCloseRef = useRef(onClose);
  const onCompletedRef = useRef(onCompleted);
  const onCardReviewedRef = useRef(onCardReviewed);
  onCloseRef.current = onClose;
  onCompletedRef.current = onCompleted;
  onCardReviewedRef.current = onCardReviewed;

  const items = useMemo<GravityFlashItem[]>(
    () =>
      open
        ? buildGravityCheckItems({
            deck,
            fsrsCards,
            courses,
            sessionSeed: Math.floor(Date.now() / 60_000) + runKey,
          })
        : [],
    // Snapshot items only when opening or restarting a run so mid-run FSRS updates never reshuffle!
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [open, runKey]
  );

  const activeItem = items[idx] ?? null;

  const resetSession = () => {
    if (nextTimerRef.current) window.clearTimeout(nextTimerRef.current);
    resolvedStepRef.current = '';
    resultsRef.current = [];
    setRunKey((k) => k + 1);
    setIdx(0);
    setResults([]);
    setPhaseState('active');
    setLastOutcome(null);
    setArrows(undefined);
  };

  // Only reset session when `open` flips true -> NEVER on `onClose` identity changes or background ticks!
  useEffect(() => {
    if (!open) return;
    resolvedStepRef.current = '';
    resultsRef.current = [];
    setIdx(0);
    setResults([]);
    setPhaseState('active');
    setLastOutcome(null);
    setArrows(undefined);

    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';

    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onCloseRef.current();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => {
      document.body.style.overflow = prevOverflow;
      window.removeEventListener('keydown', onKey);
      if (nextTimerRef.current) window.clearTimeout(nextTimerRef.current);
    };
  }, [open]);

  const finishItem = useCallback(
    (item: GravityFlashItem, itemIdx: number, hit: boolean, outcome: 'hit' | 'miss' | 'timeout', elapsedMs: number) => {
      const stepKey = `${runKey}:${itemIdx}:${item.id}`;
      if (resolvedStepRef.current === stepKey) return;
      resolvedStepRef.current = stepKey;

      setPhaseState('feedback');
      setLastOutcome(outcome);
      const sq = uciToSquares(item.expectedUci);
      if (sq) {
        setArrows([{ from: sq.from, to: sq.to, color: hit ? 'best' : 'threat' }]);
      }

      if (hit) soundManager.playSonarPing();
      else soundManager.playHullThud();

      // Only grade genuine due FSRS cards (buildGravityCheckItems omits `card` on fallback previews)
      if (item.card && item.card.unlocked) {
        const reviewed = reviewFsrsOpeningCard(item.card, { correct: hit, responseMs: elapsedMs });
        void onCardReviewedRef.current(reviewed.card);
      }

      const nextResults: ItemResult[] = [
        ...resultsRef.current,
        {
          id: item.id,
          kind: item.kind,
          hit,
          ms: elapsedMs,
          expectedSan: item.expectedSan,
        },
      ];
      resultsRef.current = nextResults;
      setResults(nextResults);

      if (nextTimerRef.current) window.clearTimeout(nextTimerRef.current);
      nextTimerRef.current = window.setTimeout(() => {
        if (itemIdx + 1 >= items.length) {
          setPhaseState('summary');
          const hits = nextResults.filter((r) => r.hit).length;
          const avgMs = Math.round(
            nextResults.reduce((s, r) => s + r.ms, 0) / Math.max(1, nextResults.length)
          );
          onCompletedRef.current?.({ hits, total: nextResults.length, avgMs });
        } else {
          setIdx(itemIdx + 1);
          setPhaseState('active');
          setLastOutcome(null);
        }
      }, hit ? 750 : 1200);
    },
    [items.length, runKey]
  );

  // Per-item countdown timer (no side effects inside state updaters!)
  useEffect(() => {
    if (!open || !activeItem || phaseState !== 'active') return;
    setBoardFen(activeItem.fen);
    setArrows(undefined);
    setSecondsLeft(activeItem.timeLimitSec);
    startedAtRef.current = performance.now();

    const interval = window.setInterval(() => {
      const elapsedSec = Math.floor((performance.now() - startedAtRef.current) / 1000);
      const remaining = Math.max(0, activeItem.timeLimitSec - elapsedSec);
      setSecondsLeft(remaining);
      if (remaining <= 0) {
        window.clearInterval(interval);
        finishItem(activeItem, idx, false, 'timeout', activeItem.timeLimitSec * 1000);
      }
    }, 250);

    return () => window.clearInterval(interval);
  }, [open, idx, activeItem, phaseState, finishItem]);

  const handleMove = (from: Square, to: Square) => {
    if (!activeItem || phaseState !== 'active') return;
    soundManager.unlock();
    const chess = new Chess(activeItem.fen);
    let mv;
    try {
      mv = chess.move({ from, to, promotion: 'q' });
    } catch {
      return;
    }
    const uci = `${mv.from}${mv.to}${mv.promotion ?? ''}`;
    const elapsedMs = Math.max(150, Math.round(performance.now() - startedAtRef.current));
    const isHit = uci === activeItem.expectedUci || mv.san === activeItem.expectedSan || chess.isCheckmate();
    setBoardFen(chess.fen());
    finishItem(activeItem, idx, isHit, isHit ? 'hit' : 'miss', elapsedMs);
  };

  if (!open) return null;

  const hits = results.filter((r) => r.hit).length;
  const avgSec = results.length > 0
    ? (results.reduce((s, r) => s + r.ms, 0) / results.length / 1000).toFixed(1)
    : '0.0';
  const progressPct = items.length > 0
    ? Math.round(((phaseState === 'summary' ? items.length : idx) / items.length) * 100)
    : 0;
  const tacticTotal = items.filter((it) => it.kind === 'tactic').length;
  const openingTotal = items.filter((it) => it.kind === 'opening').length;

  return (
    <div
      className="fixed inset-0 z-[90] flex items-center justify-center bg-[#04070e]/85 px-3 pt-[max(0.75rem,env(safe-area-inset-top))] pb-[max(0.75rem,env(safe-area-inset-bottom))] backdrop-blur-md sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-label={copy.gravityCheckTitle}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="glass-card glass-card-strong anim-pop flex max-h-full w-full max-w-md flex-col overflow-hidden rounded-2xl">
        <div className="flex shrink-0 items-center justify-between gap-2 border-b border-slate-800/80 bg-void/80 px-3.5 py-2.5">
          <div className="flex min-w-0 items-center gap-2">
            <span className="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-xl border border-teal-400/35 bg-teal-400/10 text-brilly">
              <Rocket className="h-4 w-4" />
            </span>
            <div className="min-w-0">
              <div className="truncate text-xs font-black uppercase tracking-[0.14em] text-brilly">
                {copy.gravityCheckTitle}
              </div>
              <div className="truncate text-[10px] text-slate-400">
                3× 8s tactic flashes + 2 opening checks
              </div>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-xl border border-slate-700 bg-hull text-slate-300 hover:text-white"
            aria-label="Close warmup"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Tractor Beam Progress */}
        <div className="shrink-0 px-3.5 pt-2.5">
          <div className="tractor-beam-track h-2 w-full">
            <div className="tractor-beam-fill" style={{ width: `${Math.max(4, progressPct)}%` }} />
          </div>
        </div>

        <div className="flex-1 overflow-y-auto px-3.5 py-3 nice-scroll">
          {phaseState === 'summary' ? (
            <div className="space-y-3.5 py-1 text-center">
              <div className="mx-auto inline-flex h-12 w-12 items-center justify-center rounded-2xl border border-teal-400/45 bg-gradient-to-br from-teal-400/20 to-purple-500/20 text-brilly accent-glow">
                <Sparkles className="h-6 w-6" />
              </div>
              <div>
                <div className="text-[10px] font-black uppercase tracking-[0.18em] text-clean">
                  Pre-Game Calibration Complete
                </div>
                <h2 className="mt-1 text-base font-extrabold text-white">{copy.gravityCheckCleared}</h2>
                <p className="mt-1 text-xs text-slate-400">
                  Your tactical radar and opening memory are warmed up and ready to queue.
                </p>
              </div>

              <div className="grid grid-cols-3 gap-2">
                <div className="rounded-xl border border-slate-800 bg-void/60 p-2">
                  <div className="font-mono text-base font-black text-brilly">
                    {hits}/{results.length}
                  </div>
                  <div className="text-[9px] uppercase tracking-wider text-slate-500">Accuracy</div>
                </div>
                <div className="rounded-xl border border-slate-800 bg-void/60 p-2">
                  <div className="font-mono text-base font-black text-purple-300">{avgSec}s</div>
                  <div className="text-[9px] uppercase tracking-wider text-slate-500">Avg Speed</div>
                </div>
                <div className="rounded-xl border border-slate-800 bg-void/60 p-2">
                  <div className="font-mono text-base font-black text-clean">
                    {hits >= 4 ? 'A+' : hits >= 3 ? 'READY' : 'WARM'}
                  </div>
                  <div className="text-[9px] uppercase tracking-wider text-slate-500">Status</div>
                </div>
              </div>

              <div className="space-y-1 text-left">
                {results.map((r, i) => (
                  <div
                    key={r.id + i}
                    className="flex items-center justify-between rounded-lg border border-slate-800/80 bg-void/45 px-2.5 py-1.5 text-[11px]"
                  >
                    <span className="inline-flex items-center gap-1.5 text-slate-200">
                      {r.hit ? (
                        <CheckCircle2 className="h-3.5 w-3.5 text-clean" />
                      ) : (
                        <XCircle className="h-3.5 w-3.5 text-blunder" />
                      )}
                      <span className="capitalize text-slate-400">{r.kind}</span>
                      <span className="font-mono font-bold text-white">{r.expectedSan}</span>
                    </span>
                    <span className="font-mono text-[10px] text-slate-400">{(r.ms / 1000).toFixed(1)}s</span>
                  </div>
                ))}
              </div>

              <div className="flex justify-center gap-2 pt-1">
                <button
                  type="button"
                  onClick={resetSession}
                  className="inline-flex items-center gap-1.5 rounded-xl border border-slate-700 bg-hull px-3.5 py-2 text-xs font-bold text-slate-200"
                >
                  <RotateCcw className="h-3.5 w-3.5" /> Run Again
                </button>
                <button
                  type="button"
                  onClick={onClose}
                  className="inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-4 py-2 text-xs font-extrabold text-slate-950"
                >
                  <Rocket className="h-3.5 w-3.5" /> Ready to Queue
                </button>
              </div>
            </div>
          ) : activeItem ? (
            <div className="space-y-2.5">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <span
                    className={`inline-block rounded-full border px-2 py-0.5 text-[9px] font-black uppercase tracking-wider ${
                      activeItem.kind === 'tactic'
                        ? 'border-amber-400/40 bg-amber-500/15 text-amber-200'
                        : 'border-purple-400/40 bg-purple-500/15 text-purple-200'
                    }`}
                  >
                    {activeItem.kind === 'tactic'
                      ? `Tactic Flash ${idx + 1}/${Math.max(1, tacticTotal)}`
                      : `Opening Recall ${Math.max(1, idx - tacticTotal + 1)}/${Math.max(1, openingTotal)}`}
                  </span>
                  <div className="mt-1 text-xs font-extrabold leading-snug text-white">{activeItem.prompt}</div>
                  <div className="truncate text-[10px] text-slate-400">{activeItem.subtitle}</div>
                </div>

                <div
                  className={`inline-flex shrink-0 items-center gap-1 rounded-xl border px-2.5 py-1.5 font-mono text-sm font-black tabular-nums ${
                    secondsLeft <= 3
                      ? 'border-rose-400/50 bg-rose-500/20 text-rose-200'
                      : 'border-teal-400/35 bg-teal-400/10 text-brilly'
                  }`}
                >
                  {secondsLeft <= 3 ? <Clock className="h-3.5 w-3.5 animate-pulse" /> : <Timer className="h-3.5 w-3.5" />}
                  {secondsLeft}s
                </div>
              </div>

              {/* Height-capped responsive square board so full 8x8 + feedback always fit cleanly on iPhone */}
              <div className="mx-auto w-full max-w-[min(340px,calc(100dvh-17.5rem))]">
                <ChessgroundBoard
                  fen={boardFen || activeItem.fen}
                  orientation={activeItem.orientation}
                  interactive={phaseState === 'active'}
                  turnColor={activeItem.orientation}
                  showBestArrow={false}
                  showPlayedArrow={false}
                  customArrows={arrows}
                  theme={boardTheme}
                  onUserMove={handleMove}
                />
              </div>

              {/* Reserved feedback slot so the modal never shifts height or clips on mobile */}
              <div className="min-h-[2.25rem] flex items-center justify-center">
                {phaseState === 'feedback' ? (
                  <div
                    className={`w-full rounded-xl border px-3 py-1.5 text-center text-xs font-bold ${
                      lastOutcome === 'hit'
                        ? 'border-emerald-400/40 bg-emerald-500/15 text-emerald-200'
                        : 'border-rose-400/40 bg-rose-500/15 text-rose-200'
                    }`}
                  >
                    {lastOutcome === 'hit'
                      ? `Locked in! ${activeItem.expectedSan}`
                      : lastOutcome === 'timeout'
                        ? `Time up! Best was ${activeItem.expectedSan}`
                        : `Missed — best was ${activeItem.expectedSan}`}
                  </div>
                ) : (
                  <div className="text-center text-[10px] text-slate-500">
                    Step {idx + 1} of {items.length} · Play the best move on the board
                  </div>
                )}
              </div>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
};
