import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Chess, type Square } from 'chess.js';
import {
  CheckCircle2,
  Clock,
  Lightbulb,
  Play,
  Radar,
  RefreshCw,
  RotateCcw,
  Sparkles,
  Target,
  TrendingUp,
} from 'lucide-react';
import type { BoardThemeId, MistakePuzzle } from '../../types/chess';
import type { BoardArrow, SquareHighlight, WoodpeckerCycleRecord } from '../../types/openings';
import {
  createFrozenWoodpeckerCycle,
  findRadarPingTargets,
  formatCooldownLabel,
  formatDurationShort,
  getCooldownRemainingMs,
  MAX_WOODPECKER_CYCLES,
  recordWoodpeckerPuzzleOutcome,
  selectSolvableWoodpeckerPuzzles,
  startNextWoodpeckerCycle,
} from '../../services/woodpeckerCycles';
import { stockfishService } from '../../engine/StockfishService';
import { getMoverWinPercent, uciToSquares } from '../../utils/chessMath';
import { soundManager } from '../../utils/sound';
import { useVibe } from '../../utils/vibeCopy';
import { ChessgroundBoard } from '../ChessgroundBoard';

interface Props {
  deck: MistakePuzzle[];
  cycles: WoodpeckerCycleRecord[];
  boardTheme: BoardThemeId;
  onSaveCycle: (cycle: WoodpeckerCycleRecord) => Promise<void>;
  onOpenGames: () => void;
}

export const WoodpeckerCycleView: React.FC<Props> = ({
  deck,
  cycles,
  boardTheme,
  onSaveCycle,
  onOpenGames,
}) => {
  const { copy } = useVibe();
  const [selectedBatchSize, setSelectedBatchSize] = useState<30 | 50 | 100>(30);
  const [radarPingEnabled, setRadarPingEnabled] = useState(true);
  const [radarCleared, setRadarCleared] = useState(false);
  const [radarFeedback, setRadarFeedback] = useState('');
  const [fen, setFen] = useState('');
  const [lastMove, setLastMove] = useState<[string, string] | undefined>(undefined);
  const [wrongCount, setWrongCount] = useState(0);
  const [hintsUsed, setHintsUsed] = useState(0);
  const [status, setStatus] = useState<'idle' | 'checking' | 'solved' | 'revealed'>('idle');
  const [feedback, setFeedback] = useState('');
  const [nowMs, setNowMs] = useState(() => Date.now());
  const runRef = useRef(0);

  const activeCycle = cycles[0] ?? null;
  const deckById = useMemo(() => new Map(deck.map((p) => [p.id, p])), [deck]);

  const solvableCount = useMemo(
    () => selectSolvableWoodpeckerPuzzles(deck, 100).length,
    [deck]
  );

  // Live timer tick for elapsed stopwatch & cooldown countdown
  useEffect(() => {
    const id = window.setInterval(() => setNowMs(Date.now()), 1000);
    return () => window.clearInterval(id);
  }, []);

  const [pinnedPuzzle, setPinnedPuzzle] = useState<MistakePuzzle | null>(null);
  const availableDeckIds = useMemo(() => new Set(deck.map((p) => p.id)), [deck]);

  const cyclePuzzles = useMemo(() => {
    if (!activeCycle) return [];
    return activeCycle.puzzleIds
      .map((id) => deckById.get(id))
      .filter((p): p is MistakePuzzle => Boolean(p));
  }, [activeCycle, deckById]);

  const nextCyclePuzzle = useMemo(() => {
    if (!activeCycle || cyclePuzzles.length === 0) return null;
    const unattempted = cyclePuzzles.find((p) => !(p.id in activeCycle.activeAttemptedIds));
    return unattempted ?? cyclePuzzles[activeCycle.activeIndex] ?? cyclePuzzles[0];
  }, [activeCycle, cyclePuzzles]);

  const activePuzzle = pinnedPuzzle ?? nextCyclePuzzle;

  const radarInfo = useMemo(
    () =>
      activePuzzle
        ? findRadarPingTargets(
            activePuzzle.beforeFen,
            activePuzzle.color,
            activePuzzle.bestMoveUci,
            activePuzzle.threatMoveUci
          )
        : null,
    [activePuzzle]
  );

  // Reset board ONLY when moving to a genuinely new puzzle/cycle — NEVER when toggling Radar Ping!
  useEffect(() => {
    runRef.current += 1;
    if (!activePuzzle) return;
    setFen(activePuzzle.beforeFen);
    setLastMove(undefined);
    setWrongCount(0);
    setHintsUsed(0);
    setStatus('idle');
    setFeedback('');
    setRadarCleared(!radarPingEnabled);
    setRadarFeedback('');
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activePuzzle?.id, activeCycle?.currentCycle]);

  const advanceToNextPuzzle = () => {
    setPinnedPuzzle(null);
  };

  const cooldownMs = activeCycle ? getCooldownRemainingMs(activeCycle, nowMs) : 0;
  const inCooldown = cooldownMs > 0;
  const allSevenCompleted = Boolean(
    activeCycle && activeCycle.completedCycles.length >= MAX_WOODPECKER_CYCLES
  );

  const handleCreateCycle = async (batchSize: 30 | 50 | 100) => {
    const created = createFrozenWoodpeckerCycle(deck, batchSize);
    await onSaveCycle(created);
  };

  const handleStartEarlyOrResume = async () => {
    if (!activeCycle) return;
    const started = startNextWoodpeckerCycle(activeCycle);
    await onSaveCycle(started);
  };

  const handleRadarTap = (sq: Square) => {
    if (!radarInfo || radarCleared) return;
    soundManager.unlock();
    const hit = radarInfo.targetSquares.length === 0 || radarInfo.targetSquares.includes(sq);
    if (hit) {
      soundManager.playSonarPing();
      setRadarCleared(true);
      setRadarFeedback(`Radar locked on ${sq}! Now play the winning move.`);
    } else {
      soundManager.playError();
      setRadarFeedback(
        radarInfo.primarySquare
          ? `Look closer at ${radarInfo.primarySquare} — threat spotted! Unlocked to move.`
          : 'Threat scan complete — play your move.'
      );
      window.setTimeout(() => setRadarCleared(true), 650);
    }
  };

  const completeCurrentPuzzle = async (solved: boolean, finalWrong: number, finalHints: number) => {
    if (!activeCycle || !activePuzzle) return;
    // Pin the current puzzle so solved / revealed feedback stays visible until the user clicks Next Puzzle!
    setPinnedPuzzle(activePuzzle);
    const { updated } = recordWoodpeckerPuzzleOutcome(
      activeCycle,
      activePuzzle.id,
      {
        solved,
        wrongMoves: finalWrong,
        hintsUsed: finalHints,
      },
      Date.now(),
      availableDeckIds
    );
    await onSaveCycle(updated);
  };

  const handleMove = async (from: Square, to: Square) => {
    if (!activePuzzle || !activeCycle || status !== 'idle' || (radarPingEnabled && !radarCleared)) return;
    soundManager.unlock();
    const gen = runRef.current;
    const c = new Chess(fen);
    let mv;
    try {
      mv = c.move({ from, to, promotion: 'q' });
    } catch {
      return;
    }
    const uci = `${mv.from}${mv.to}${mv.promotion ?? ''}`;
    if (uci === activePuzzle.bestMoveUci || c.isCheckmate()) {
      soundManager.playSonarPing();
      setFen(c.fen());
      setLastMove([mv.from, mv.to]);
      setStatus('solved');
      const isFirstTry = wrongCount === 0 && hintsUsed === 0;
      setFeedback(
        isFirstTry
          ? `First-Try Hit! ${mv.san} mastered.`
          : `Solved with ${mv.san} (${wrongCount} retries, ${hintsUsed} hints).`
      );
      await completeCurrentPuzzle(true, wrongCount, hintsUsed);
      return;
    }

    setFen(c.fen());
    setLastMove([mv.from, mv.to]);
    setStatus('checking');
    setFeedback('Checking alternative with Stockfish…');
    try {
      const res = await stockfishService.analyzePosition(c.fen(), { depth: 10, multiPv: 1, timeoutMs: 8000 });
      if (runRef.current !== gen) return;
      const loss = Math.max(
        0,
        getMoverWinPercent(activePuzzle.evalBefore, activePuzzle.color) -
          getMoverWinPercent(res.score, activePuzzle.color)
      );
      if (loss <= 6) {
        soundManager.playSonarPing();
        setStatus('solved');
        setFeedback(`Strong alternative! ${mv.san} holds (${res.score.display}).`);
        await completeCurrentPuzzle(true, wrongCount, hintsUsed);
      } else {
        soundManager.playHullThud();
        setWrongCount((w) => w + 1);
        setFeedback(`${mv.san} loses ${loss.toFixed(0)}% win equity. Resetting—try again!`);
        window.setTimeout(() => {
          if (runRef.current !== gen) return;
          setFen(activePuzzle.beforeFen);
          setLastMove(undefined);
          setStatus('idle');
        }, 900);
      }
    } catch {
      if (runRef.current !== gen) return;
      setFen(activePuzzle.beforeFen);
      setLastMove(undefined);
      setStatus('idle');
      setFeedback('Engine busy — try again.');
    }
  };

  const revealSolution = async () => {
    if (!activePuzzle || !activeCycle) return;
    const sq = uciToSquares(activePuzzle.bestMoveUci);
    if (sq) {
      const c = new Chess(activePuzzle.beforeFen);
      try {
        const mv = c.move({ from: sq.from, to: sq.to, promotion: sq.promotion });
        setFen(c.fen());
        setLastMove([mv.from, mv.to]);
      } catch {
        // ignore
      }
    }
    setStatus('revealed');
    setFeedback(`Best was ${activePuzzle.bestMoveSan}. Recorded as miss for this cycle.`);
    await completeCurrentPuzzle(false, wrongCount + 1, hintsUsed + 1);
  };

  if (deck.length === 0) {
    return (
      <div className="glass-card p-6 text-center">
        <Target className="mx-auto h-9 w-9 text-slate-600" />
        <h3 className="mt-2 text-sm font-extrabold text-white">No analyzed mistakes for a Frozen Cycle yet</h3>
        <p className="mx-auto mt-1 max-w-md text-xs text-slate-400">
          Analyze a few games first so BrillyDer can build a frozen 30 / 50 / 100-puzzle Woodpecker cycle from your real games.
        </p>
        <button
          type="button"
          onClick={onOpenGames}
          className="mt-3 inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-3.5 py-2 text-xs font-extrabold text-slate-950"
        >
          <Sparkles className="h-3.5 w-3.5" /> Analyze Games
        </button>
      </div>
    );
  }

  const doneInCycle = activeCycle ? Object.keys(activeCycle.activeAttemptedIds).length : 0;
  const totalInCycle = activeCycle ? activeCycle.puzzleIds.length : 0;
  const firstTrySoFar = activeCycle
    ? Object.values(activeCycle.activeAttemptedIds).filter((r) => r.firstTry).length
    : 0;
  const firstTryRateLive = doneInCycle > 0 ? Math.round((firstTrySoFar / doneInCycle) * 100) : 0;
  const elapsedLiveSec = activeCycle?.activeStartedAt
    ? Math.max(0, Math.round((nowMs - activeCycle.activeStartedAt) / 1000))
    : 0;

  const hintArrow: BoardArrow[] | undefined =
    hintsUsed > 0 && activePuzzle
      ? (() => {
          const sq = uciToSquares(activePuzzle.bestMoveUci);
          return sq ? [{ from: sq.from, to: sq.to, color: 'plan' as const }] : undefined;
        })()
      : undefined;

  const radarHighlights: SquareHighlight[] | undefined =
    radarPingEnabled && radarCleared && radarInfo?.primarySquare
      ? [{ square: radarInfo.primarySquare, color: 'threat' }]
      : undefined;

  return (
    <div className="space-y-3">
      {/* Frozen Cycle Setup / Header */}
      <section className="glass-card glass-card-strong p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-amber-300">
              <Target className="h-4 w-4" /> True Woodpecker Frozen Cycles
            </div>
            <h2 className="mt-0.5 text-base font-extrabold text-white">
              {activeCycle
                ? `Cycle #${activeCycle.currentCycle} of ${MAX_WOODPECKER_CYCLES} · ${totalInCycle} Frozen Puzzles`
                : 'Freeze a Fixed Puzzle Set (30 / 50 / 100)'}
            </h2>
            <p className="mt-0.5 text-[11px] text-slate-400">
              Repeat the exact same solvable mistakes across 7 cycles to wire instant tactical intuition.
            </p>
          </div>

          <div className="flex flex-wrap items-center gap-1.5">
            {([30, 50, 100] as const).map((sz) => (
              <button
                key={sz}
                type="button"
                onClick={() => setSelectedBatchSize(sz)}
                className={`rounded-lg border px-2.5 py-1 font-mono text-[10px] font-black ${
                  selectedBatchSize === sz
                    ? 'border-teal-400/50 bg-teal-400/15 text-teal-200'
                    : 'border-slate-800 bg-void/60 text-slate-400'
                }`}
              >
                {sz}
              </button>
            ))}
            <button
              type="button"
              onClick={() => void handleCreateCycle(selectedBatchSize)}
              className="inline-flex items-center gap-1 rounded-xl bg-gradient-to-r from-teal-400 to-purple-500 px-3 py-1.5 text-[11px] font-extrabold text-slate-950"
            >
              <RefreshCw className="h-3.5 w-3.5" /> {activeCycle ? 'New Frozen Set' : 'Freeze Set'}
            </button>
          </div>
        </div>

        <div className="mt-2.5 flex flex-wrap items-center gap-2 text-[10px] text-slate-400">
          <span>{solvableCount} solvable mistakes available (eval swing ≥1.5)</span>
          {activeCycle && (
            <>
              <span>·</span>
              <span className="font-mono text-brilly">{doneInCycle}/{totalInCycle} done</span>
              <span>·</span>
              <span className="font-mono text-clean">1st-Try: {firstTryRateLive}%</span>
              {elapsedLiveSec > 0 && (
                <>
                  <span>·</span>
                  <span className="inline-flex items-center gap-1 font-mono text-purple-300">
                    <Clock className="h-3 w-3" /> {formatDurationShort(elapsedLiveSec)}
                  </span>
                </>
              )}
            </>
          )}
        </div>

        {activeCycle && (
          <div className="mt-2.5 tractor-beam-track h-2 w-full">
            <div
              className="tractor-beam-fill"
              style={{ width: `${totalInCycle > 0 ? Math.round((doneInCycle / totalInCycle) * 100) : 0}%` }}
            />
          </div>
        )}
      </section>

      {/* Consolidation Cooldown Banner */}
      {activeCycle && inCooldown && (
        <section className="glass-card border-amber-400/40 bg-amber-500/[0.07] p-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <div className="flex items-center gap-1.5 text-xs font-extrabold text-amber-200">
                <Clock className="h-4 w-4" /> {copy.woodpeckerRest}
              </div>
              <p className="mt-0.5 text-[11px] text-slate-300">
                Cycle #{activeCycle.currentCycle - 1} complete! A 24–48h rest window boosts pattern consolidation.
                Recommended wait remaining: <strong className="font-mono text-amber-200">{formatCooldownLabel(cooldownMs)}</strong>.
              </p>
            </div>
            <button
              type="button"
              onClick={() => void handleStartEarlyOrResume()}
              className="inline-flex items-center gap-1.5 rounded-xl border border-amber-400/45 bg-amber-500/20 px-3 py-2 text-[11px] font-black text-amber-100 hover:bg-amber-500/30"
            >
              <Play className="h-3.5 w-3.5" /> Start Cycle #{activeCycle.currentCycle} Early
            </button>
          </div>
        </section>
      )}

      {/* Active Puzzle Board */}
      {activeCycle && !inCooldown && !allSevenCompleted && activePuzzle && (
        <div className="grid gap-3 lg:grid-cols-[minmax(0,400px)_minmax(0,1fr)]">
          <div className="glass-card glass-card-strong p-3">
            <div className="mb-2 flex items-center justify-between gap-2 text-[10px]">
              <span className="font-bold text-slate-200">
                Puzzle {doneInCycle + 1}/{totalInCycle} · Cycle #{activeCycle.currentCycle}
              </span>
              <button
                type="button"
                onClick={() => {
                  const next = !radarPingEnabled;
                  setRadarPingEnabled(next);
                  if (!next) setRadarCleared(true);
                }}
                className={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[9px] font-black ${
                  radarPingEnabled
                    ? 'border-teal-400/45 bg-teal-400/15 text-teal-200'
                    : 'border-slate-700 bg-void/60 text-slate-400'
                }`}
              >
                <Radar className="h-3 w-3" /> {copy.radarPingLabel}: {radarPingEnabled ? 'ON' : 'OFF'}
              </button>
            </div>

            <ChessgroundBoard
              fen={fen || activePuzzle.beforeFen}
              orientation={activePuzzle.color}
              lastMove={lastMove}
              interactive={status === 'idle' && (!radarPingEnabled || radarCleared)}
              turnColor={activePuzzle.color}
              showBestArrow={status === 'revealed'}
              bestMoveUci={status === 'revealed' ? activePuzzle.bestMoveUci : undefined}
              showPlayedArrow={false}
              customArrows={hintArrow}
              squareHighlights={radarHighlights}
              theme={boardTheme}
              onSquareClick={radarPingEnabled && !radarCleared ? handleRadarTap : undefined}
              onUserMove={(from, to) => void handleMove(from, to)}
            />
          </div>

          <div className="glass-card p-4 space-y-3">
            <div className="flex items-center justify-between gap-2">
              <span className="rounded-lg bg-hull px-2 py-1 text-[10px] font-black uppercase tracking-wider text-brilly">
                {activePuzzle.tacticalTag}
              </span>
              <span className="font-mono text-[10px] text-slate-400">
                Game move: {activePuzzle.moveNumber}{activePuzzle.color === 'w' ? '.' : '…'}{activePuzzle.san}
              </span>
            </div>

            {radarPingEnabled && !radarCleared ? (
              <div className="rounded-xl border border-teal-400/40 bg-teal-400/10 p-3 space-y-2">
                <div className="flex items-center gap-1.5 text-xs font-extrabold text-teal-200">
                  <Radar className="h-4 w-4 animate-pulse" /> {copy.radarPingLabel} Pre-Step (2s)
                </div>
                <p className="text-xs leading-relaxed text-slate-200">
                  {radarInfo?.prompt ?? 'Tap the threatened piece or key square before moving.'}
                </p>
                {radarFeedback && <p className="text-[11px] font-bold text-amber-200">{radarFeedback}</p>}
                <button
                  type="button"
                  onClick={() => setRadarCleared(true)}
                  className="rounded-lg border border-slate-700 bg-void/70 px-2.5 py-1 text-[10px] font-bold text-slate-300"
                >
                  Skip threat tap → Move
                </button>
              </div>
            ) : (
              <div className="rounded-xl border border-slate-800 bg-void/60 p-3">
                <div className="text-xs font-bold text-white">
                  Find the best move for {activePuzzle.color === 'w' ? 'White' : 'Black'}.
                </div>
                {radarFeedback && <p className="mt-1 text-[10px] text-teal-300">{radarFeedback}</p>}
                {feedback && (
                  <p className={`mt-1.5 text-xs font-bold ${status === 'solved' ? 'text-clean' : 'text-amber-300'}`}>
                    {feedback}
                  </p>
                )}
              </div>
            )}

            <div className="flex flex-wrap gap-1.5">
              {(status === 'solved' || status === 'revealed') && (
                <button
                  type="button"
                  onClick={advanceToNextPuzzle}
                  className="inline-flex items-center gap-1 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-3.5 py-1.5 text-[11px] font-extrabold text-slate-950"
                >
                  Next Puzzle →
                </button>
              )}
              {status === 'idle' && (
                <>
                  <button
                    type="button"
                    onClick={() => {
                      setHintsUsed((h) => h + 1);
                      setRadarCleared(true);
                    }}
                    className="inline-flex items-center gap-1 rounded-xl border border-amber-400/35 bg-amber-500/10 px-3 py-1.5 text-[11px] font-bold text-amber-200"
                  >
                    <Lightbulb className="h-3.5 w-3.5" /> Hint
                  </button>
                  <button
                    type="button"
                    onClick={() => void revealSolution()}
                    className="rounded-xl border border-rose-500/35 bg-rose-500/10 px-3 py-1.5 text-[11px] font-bold text-rose-200"
                  >
                    Reveal Solution
                  </button>
                </>
              )}
              {status !== 'solved' && status !== 'revealed' && (
                <button
                  type="button"
                  onClick={() => {
                    setFen(activePuzzle.beforeFen);
                    setLastMove(undefined);
                    setStatus('idle');
                    setFeedback('');
                  }}
                  className="inline-flex items-center gap-1 rounded-xl border border-slate-700 bg-hull px-3 py-1.5 text-[11px] font-bold text-slate-300"
                >
                  <RotateCcw className="h-3 w-3" /> Reset
                </button>
              )}
            </div>
          </div>
        </div>
      )}

      {activeCycle && !inCooldown && !allSevenCompleted && cyclePuzzles.length === 0 && (
        <div className="glass-card border-amber-400/35 p-5 text-center">
          <p className="text-xs font-bold text-amber-200">
            This frozen cycle references games that are no longer in the active account deck.
          </p>
          <p className="mt-1 text-[11px] text-slate-400">
            Freeze a fresh 30 / 50 / 100 puzzle batch above from your current games to continue.
          </p>
        </div>
      )}

      {allSevenCompleted && (
        <div className="glass-card border-emerald-400/40 p-6 text-center">
          <CheckCircle2 className="mx-auto h-10 w-10 text-clean" />
          <h3 className="mt-2 text-base font-extrabold text-white">All 7 Woodpecker Cycles Mastered!</h3>
          <p className="mt-1 text-xs text-slate-400">
            Freeze a fresh 30 / 50 / 100 puzzle batch above to start your next training block.
          </p>
        </div>
      )}

      {/* Cycle Speed-Up Chart */}
      {activeCycle && activeCycle.completedCycles.length > 0 && (
        <CycleSpeedUpChart completedCycles={activeCycle.completedCycles} />
      )}
    </div>
  );
};

const CycleSpeedUpChart: React.FC<{
  completedCycles: WoodpeckerCycleRecord['completedCycles'];
}> = ({ completedCycles }) => {
  const maxSec = Math.max(10, ...completedCycles.map((c) => c.elapsedSeconds));
  const width = 420;
  const height = 140;
  const padX = 32;
  const padY = 18;
  const innerW = width - padX * 2;
  const innerH = height - padY * 2;

  const xFor = (i: number) =>
    completedCycles.length <= 1 ? width / 2 : padX + (i / (completedCycles.length - 1)) * innerW;
  const yTime = (sec: number) => padY + (1 - sec / maxSec) * innerH;
  const yAcc = (pct: number) => padY + (1 - pct / 100) * innerH;

  const timePath = completedCycles
    .map((c, i) => `${i === 0 ? 'M' : 'L'} ${xFor(i).toFixed(1)} ${yTime(c.elapsedSeconds).toFixed(1)}`)
    .join(' ');
  const accPath = completedCycles
    .map((c, i) => `${i === 0 ? 'M' : 'L'} ${xFor(i).toFixed(1)} ${yAcc(c.firstTryPct).toFixed(1)}`)
    .join(' ');

  return (
    <section className="glass-card p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-1.5 text-xs font-extrabold text-white">
          <TrendingUp className="h-4 w-4 text-brilly" /> Cycle Speed-Up &amp; First-Try Chart
        </div>
        <div className="flex items-center gap-3 text-[10px]">
          <span className="inline-flex items-center gap-1 text-purple-300">
            <span className="h-2 w-2 rounded-full bg-warp" /> Time
          </span>
          <span className="inline-flex items-center gap-1 text-brilly">
            <span className="h-2 w-2 rounded-full bg-brilly" /> 1st-Try %
          </span>
        </div>
      </div>

      <svg viewBox={`0 0 ${width} ${height}`} className="mt-2 h-36 w-full rounded-xl bg-void/70">
        {[0, 0.5, 1].map((t) => (
          <line
            key={t}
            x1={padX}
            y1={padY + t * innerH}
            x2={width - padX}
            y2={padY + t * innerH}
            stroke="#1e293b"
            strokeDasharray="3 3"
          />
        ))}
        <path d={timePath} fill="none" stroke="#A855F7" strokeWidth="2.4" strokeLinecap="round" />
        <path d={accPath} fill="none" stroke="#2DD4BF" strokeWidth="2.4" strokeLinecap="round" />
        {completedCycles.map((c, i) => (
          <g key={c.cycleNumber}>
            <circle cx={xFor(i)} cy={yTime(c.elapsedSeconds)} r="4" fill="#A855F7" stroke="#070B14" strokeWidth="1.5" />
            <circle cx={xFor(i)} cy={yAcc(c.firstTryPct)} r="4" fill="#2DD4BF" stroke="#070B14" strokeWidth="1.5" />
            <text x={xFor(i)} y={height - 4} textAnchor="middle" fill="#94a3b8" fontSize="9" fontWeight="700">
              C{c.cycleNumber}
            </text>
          </g>
        ))}
      </svg>

      <div className="mt-2 grid grid-cols-2 gap-1.5 sm:grid-cols-4">
        {completedCycles.map((c) => (
          <div key={c.cycleNumber} className="rounded-lg border border-slate-800 bg-void/55 p-2 text-[10px]">
            <div className="font-black text-slate-200">Cycle #{c.cycleNumber}</div>
            <div className="font-mono text-purple-300">{formatDurationShort(c.elapsedSeconds)}</div>
            <div className="font-mono text-brilly">1st-Try {c.firstTryPct}% · Acc {c.accuracyPct}%</div>
          </div>
        ))}
      </div>
    </section>
  );
};
