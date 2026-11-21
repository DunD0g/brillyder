import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Chess, type Square } from 'chess.js';
import {
  ArrowRight,
  CheckCircle2,
  Clock,
  Flame,
  Lightbulb,
  Orbit,
  Radar,
  Rocket,
  Sparkles,
  Target,
  Zap,
} from 'lucide-react';
import type { AnalyzedGame, BoardThemeId, MistakePuzzle } from '../../types/chess';
import type {
  BoardArrow,
  FsrsOpeningCard,
  OpeningCourse,
  SquareHighlight,
  WoodpeckerCycleRecord,
} from '../../types/openings';
import {
  buildDailyWorkoutPlan,
  type DailyDurationMinutes,
} from '../../services/dailyCoach';
import {
  findRadarPingTargets,
  formatCooldownLabel,
  recordWoodpeckerPuzzleOutcome,
} from '../../services/woodpeckerCycles';
import {
  getRecallProbability,
  reviewFsrsOpeningCard,
} from '../../lib/fsrsOpening';
import { stockfishService } from '../../engine/StockfishService';
import { getMoverWinPercent, uciToSquares } from '../../utils/chessMath';
import {
  buildPuzzleSolutionLine,
  formatSolutionLineSan,
  userMoveCountForLine,
} from '../../utils/puzzleSequence';
import type { UserHandleSpec } from '../../utils/player';
import { soundManager } from '../../utils/sound';
import { useVibe } from '../../utils/vibeCopy';
import { ChessgroundBoard } from '../ChessgroundBoard';
import { AdvantageConversionView } from './AdvantageConversionView';

type StageNum = 1 | 2 | 3 | 4 | 5; // 5 = session complete!

interface Props {
  analyzedGames: AnalyzedGame[];
  username: UserHandleSpec;
  deck: MistakePuzzle[];
  courses: OpeningCourse[];
  fsrsCards: FsrsOpeningCard[];
  activeCycle: WoodpeckerCycleRecord | null;
  convertedIds: string[];
  boardTheme: BoardThemeId;
  onCardReviewed: (updated: FsrsOpeningCard) => Promise<void>;
  onSaveCycle: (cycle: WoodpeckerCycleRecord) => Promise<void>;
  onMarkConverted: (positionId: string) => Promise<void>;
  onRecordMistakeAttempt: (puzzleId: string, solved: boolean) => void;
  onUnlockStarterCards: () => Promise<void>;
  onOpenGravityCheck: () => void;
  onOpenGames: () => void;
  onOpenGame: (gameId: string, ply: number) => void;
  onSessionComplete: (summary: { duration: DailyDurationMinutes; completedItems: number }) => Promise<void>;
}

const STAGE_META: Array<{ num: 1 | 2 | 3 | 4; label: string; short: string }> = [
  { num: 1, label: 'Due Opening FSRS', short: '1. Openings' },
  { num: 2, label: 'Blunder Rewind', short: '2. Rewind' },
  { num: 3, label: 'Frozen Woodpecker', short: '3. Woodpecker' },
  { num: 4, label: 'Targeted Weakness', short: '4. Weakness' },
];

export const DailyCoachSession: React.FC<Props> = ({
  analyzedGames,
  username,
  deck,
  courses,
  fsrsCards,
  activeCycle,
  convertedIds,
  boardTheme,
  onCardReviewed,
  onSaveCycle,
  onMarkConverted,
  onRecordMistakeAttempt,
  onUnlockStarterCards,
  onOpenGravityCheck,
  onOpenGames,
  onOpenGame,
  onSessionComplete,
}) => {
  const { copy } = useVibe();
  const [duration, setDuration] = useState<DailyDurationMinutes>(15);
  const [stage, setStage] = useState<StageNum>(1);
  const [itemIndex, setItemIndex] = useState(0);
  const [completedCount, setCompletedCount] = useState(0);
  const [completedStages, setCompletedStages] = useState<Set<number>>(() => new Set());
  const [stage1CardOverride, setStage1CardOverride] = useState<FsrsOpeningCard | null>(null);
  const [radarPingEnabled, setRadarPingEnabled] = useState(true);
  const [radarCleared, setRadarCleared] = useState(false);
  const [radarNote, setRadarNote] = useState('');
  const [fen, setFen] = useState('');
  const [stepIndex, setStepIndex] = useState(0);
  const [lastMove, setLastMove] = useState<[string, string] | undefined>(undefined);
  const [customArrows, setCustomArrows] = useState<BoardArrow[] | undefined>(undefined);
  const [status, setStatus] = useState<'idle' | 'checking' | 'replying' | 'solved' | 'wrong'>('idle');
  const [feedback, setFeedback] = useState('');
  const [wrongCount, setWrongCount] = useState(0);
  const [hintUsed, setHintUsed] = useState(false);
  const startedAtRef = useRef<number>(performance.now());
  const genRef = useRef(0);
  const availableDeckIds = useMemo(() => new Set(deck.map((p) => p.id)), [deck]);

  // Snapshot the workout plan when duration/account changes so completed items don't shift indices mid-stage
  const [planSeed, setPlanSeed] = useState(0);
  const plan = useMemo(
    () =>
      buildDailyWorkoutPlan({
        duration,
        fsrsCards,
        deck,
        analyzedGames,
        username,
        activeCycle,
        convertedIds,
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [duration, planSeed, analyzedGames.length, activeCycle?.id, username]
  );

  const stageCounts = useMemo(() => {
    const s1 = plan.stage1Cards.length;
    const s2 = plan.stage2Blunders.length;
    const s3 = plan.stage3Woodpecker.length;
    const s4 = plan.stage4Conversion ? 1 : plan.stage4Puzzles.length;
    return { s1, s2, s3, s4, total: Math.max(1, s1 + s2 + s3 + s4) };
  }, [plan]);

  const activeStage1Card = stage === 1 ? plan.stage1Cards[itemIndex] ?? null : null;
  const activeStage2Puzzle = stage === 2 ? plan.stage2Blunders[itemIndex] ?? null : null;
  const activeStage3Puzzle = stage === 3 ? plan.stage3Woodpecker[itemIndex] ?? null : null;
  const activeStage4Puzzle = stage === 4 && !plan.stage4Conversion ? plan.stage4Puzzles[itemIndex] ?? null : null;
  const activePuzzle: MistakePuzzle | null = activeStage2Puzzle ?? activeStage3Puzzle ?? activeStage4Puzzle;

  const solutionLine = useMemo(
    () =>
      activePuzzle
        ? buildPuzzleSolutionLine({
            beforeFen: activePuzzle.beforeFen,
            bestMoveUci: activePuzzle.bestMoveUci,
            bestPvSan: activePuzzle.bestPvSan,
            tacticalTag: activePuzzle.tacticalTag,
          })
        : [],
    [activePuzzle]
  );
  const expectedStep = solutionLine[stepIndex] ?? solutionLine[0] ?? null;
  const totalUserMoves = userMoveCountForLine(solutionLine);
  const currentUserMoveNum = Math.min(totalUserMoves, Math.floor(stepIndex / 2) + 1);

  const radarInfo = useMemo(
    () =>
      stage === 2 && activeStage2Puzzle
        ? findRadarPingTargets(
            activeStage2Puzzle.beforeFen,
            activeStage2Puzzle.color,
            activeStage2Puzzle.bestMoveUci,
            activeStage2Puzzle.threatMoveUci
          )
        : null,
    [stage, activeStage2Puzzle]
  );

  // Reset puzzle state ONLY on stage/item change — NEVER when toggling Radar Ping!
  useEffect(() => {
    genRef.current += 1;
    setStepIndex(0);
    setStatus('idle');
    setFeedback('');
    setCustomArrows(undefined);
    setLastMove(undefined);
    setWrongCount(0);
    setHintUsed(false);
    setRadarNote('');
    setStage1CardOverride(null);
    setRadarCleared(!(stage === 2 && radarPingEnabled));
    startedAtRef.current = performance.now();

    if (activeStage1Card) {
      setFen(activeStage1Card.fen);
    } else if (activePuzzle) {
      setFen(activePuzzle.beforeFen);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stage, itemIndex, activeStage1Card?.cardId, activePuzzle?.id]);

  const progressPct = stage === 5
    ? 100
    : Math.min(99, Math.round((completedCount / stageCounts.total) * 100));

  const moveToNextStageOrItem = (currentStage: 1 | 2 | 3 | 4, currentIdx: number) => {
    const stageLen =
      currentStage === 1
        ? stageCounts.s1
        : currentStage === 2
          ? stageCounts.s2
          : currentStage === 3
            ? stageCounts.s3
            : stageCounts.s4;
    if (currentIdx + 1 < stageLen) {
      setItemIndex(currentIdx + 1);
      return;
    }
    setCompletedStages((prev) => new Set(prev).add(currentStage));
    if (currentStage < 4) {
      setStage((currentStage + 1) as StageNum);
      setItemIndex(0);
    } else {
      setStage(5);
      void onSessionComplete({ duration, completedItems: completedCount });
    }
  };

  const handleStage1Move = async (from: Square, to: Square) => {
    const currentCard = stage1CardOverride ?? activeStage1Card;
    if (!currentCard || status === 'solved') return;
    soundManager.unlock();
    const chess = new Chess(currentCard.fen);
    let mv;
    try {
      mv = chess.move({ from, to, promotion: 'q' });
    } catch {
      return;
    }
    const uci = `${mv.from}${mv.to}${mv.promotion ?? ''}`;
    const responseMs = Math.max(150, Math.round(performance.now() - startedAtRef.current));

    if (uci === currentCard.expectedUci || mv.san === currentCard.expectedSan) {
      const reviewed = reviewFsrsOpeningCard(currentCard, {
        correct: wrongCount === 0,
        responseMs,
        hintUsed,
      });
      setStage1CardOverride(reviewed.card);
      setFen(chess.fen());
      setLastMove([mv.from, mv.to]);
      setCustomArrows([{ from: mv.from, to: mv.to, color: 'best' }]);
      setStatus('solved');
      setCompletedCount((c) => c + 1);
      setFeedback(`${mv.san} locked in (${reviewed.gradeLabel} · ${copy.recallProbability(reviewed.recallPct)})`);
      soundManager.playSonarPing();
      await onCardReviewed(reviewed.card);
    } else {
      soundManager.playHullThud();
      setWrongCount((w) => w + 1);
      const again = reviewFsrsOpeningCard(currentCard, { correct: false, responseMs });
      setStage1CardOverride(again.card);
      await onCardReviewed(again.card);
      const sq = uciToSquares(currentCard.expectedUci);
      if (sq) setCustomArrows([{ from: sq.from, to: sq.to, color: 'plan' }]);
      setFeedback(`Played ${mv.san}; repertoire expects ${currentCard.expectedSan}. Retry to continue!`);
    }
  };

  const handleRadarTap = (sq: Square) => {
    if (!radarInfo || radarCleared) return;
    soundManager.unlock();
    const hit = radarInfo.targetSquares.length === 0 || radarInfo.targetSquares.includes(sq);
    if (hit) {
      soundManager.playSonarPing();
      setRadarCleared(true);
      setRadarNote(`Threat pinged on ${sq}! Now play the best reply.`);
    } else {
      soundManager.playError();
      setRadarNote(
        radarInfo.primarySquare
          ? `Key threat is on ${radarInfo.primarySquare} — unlocked to play your move.`
          : 'Radar scan done — play your move.'
      );
      window.setTimeout(() => setRadarCleared(true), 600);
    }
  };

  const handlePuzzleMove = async (from: Square, to: Square) => {
    if (!activePuzzle || status !== 'idle') return;
    if (stage === 2 && radarPingEnabled && !radarCleared) return;
    soundManager.unlock();
    const gen = genRef.current;
    const stepFen = expectedStep?.beforeFen ?? activePuzzle.beforeFen;
    const prevOppStep = stepIndex > 0 ? solutionLine[stepIndex - 1] : null;
    const resetLastMove: [string, string] | undefined = prevOppStep ? [prevOppStep.from, prevOppStep.to] : undefined;
    const c = new Chess(fen || stepFen);
    let mv;
    try {
      mv = c.move({ from, to, promotion: 'q' });
    } catch {
      return;
    }
    const uci = `${mv.from}${mv.to}${mv.promotion ?? ''}`;
    const expectedUci = expectedStep?.uci ?? activePuzzle.bestMoveUci;

    const finishSolved = async (msg: string) => {
      soundManager.playSonarPing();
      setFen(c.fen());
      setLastMove([mv.from, mv.to]);
      setCustomArrows([{ from: mv.from, to: mv.to, color: 'best' }]);
      setStatus('solved');
      setCompletedCount((n) => n + 1);
      setFeedback(msg);
      onRecordMistakeAttempt(activePuzzle.id, true);
      if (stage === 3 && activeCycle && !plan.stage3OnCooldown && activeCycle.puzzleIds.includes(activePuzzle.id)) {
        const { updated } = recordWoodpeckerPuzzleOutcome(
          activeCycle,
          activePuzzle.id,
          {
            solved: true,
            wrongMoves: wrongCount,
            hintsUsed: hintUsed ? 1 : 0,
          },
          Date.now(),
          availableDeckIds
        );
        await onSaveCycle(updated);
      }
    };

    if (uci === expectedUci || c.isCheckmate()) {
      if (!c.isCheckmate() && stepIndex + 2 < solutionLine.length) {
        const oppStep = solutionLine[stepIndex + 1];
        if (mv.captured) soundManager.playCapture();
        else if (mv.san.includes('+')) soundManager.playCheck();
        else soundManager.playMove();
        setFen(c.fen());
        setLastMove([mv.from, mv.to]);
        setCustomArrows(undefined);
        setStatus('replying');
        setFeedback(`Good! ${mv.san} — opponent responds…`);
        window.setTimeout(() => {
          if (genRef.current !== gen) return;
          if (oppStep.isCapture) soundManager.playCapture();
          else if (oppStep.isCheck) soundManager.playCheck();
          else soundManager.playMove();
          setFen(oppStep.afterFen);
          setLastMove([oppStep.from, oppStep.to]);
          setStepIndex(stepIndex + 2);
          setStatus('idle');
          setFeedback(`Opponent played ${oppStep.san}. Move ${Math.floor((stepIndex + 2) / 2) + 1}/${totalUserMoves} — finish the tactic!`);
        }, 420);
        return;
      }
      const suffix = totalUserMoves > 1 ? ` (${formatSolutionLineSan(solutionLine)})` : '';
      await finishSolved(`Spot on! ${mv.san} is the top move${suffix}.`);
      return;
    }

    setFen(c.fen());
    setLastMove([mv.from, mv.to]);
    setStatus('checking');
    setFeedback('Checking alternative with Stockfish…');
    try {
      const res = await stockfishService.analyzePosition(c.fen(), { depth: 10, multiPv: 1, timeoutMs: 8000 });
      if (genRef.current !== gen) return;
      const loss = Math.max(
        0,
        getMoverWinPercent(activePuzzle.evalBefore, activePuzzle.color) -
          getMoverWinPercent(res.score, activePuzzle.color)
      );
      if (loss <= 6) {
        await finishSolved(`Strong alternative! ${mv.san} holds (${res.score.display}).`);
      } else {
        soundManager.playHullThud();
        setWrongCount((w) => w + 1);
        onRecordMistakeAttempt(activePuzzle.id, false);
        setStatus('wrong');
        setFeedback(`${mv.san} drops ${loss.toFixed(0)}% equity (${res.score.display}). Try another move!`);
        window.setTimeout(() => {
          if (genRef.current !== gen) return;
          setFen(stepFen);
          setLastMove(resetLastMove);
          setStatus('idle');
        }, 900);
      }
    } catch {
      if (genRef.current !== gen) return;
      setFen(stepFen);
      setLastMove(resetLastMove);
      setStatus('idle');
    }
  };

  const radarHighlights: SquareHighlight[] | undefined =
    stage === 2 && radarPingEnabled && radarCleared && radarInfo?.primarySquare
      ? [{ square: radarInfo.primarySquare, color: 'threat' }]
      : undefined;

  return (
    <div className="space-y-3">
      {/* Daily Coach Header + Tractor Beam Progress Bar */}
      <section className="glass-card glass-card-strong p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-brilly">
              <Flame className="h-4 w-4 text-amber-400" /> Daily Coach Loop ({duration}m)
            </div>
            <h2 className="mt-0.5 text-base font-extrabold text-white">
              4-Stage High-ROI Training Session
            </h2>
          </div>

          <div className="flex flex-wrap items-center gap-1.5">
            <div className="inline-flex rounded-xl border border-slate-800 bg-void/70 p-0.5">
              {([10, 15, 25] as DailyDurationMinutes[]).map((d) => (
                <button
                  key={d}
                  type="button"
                  onClick={() => { setDuration(d); setStage(1); setItemIndex(0); setCompletedCount(0); }}
                  className={`rounded-lg px-2.5 py-1 font-mono text-[10px] font-black ${
                    duration === d ? 'bg-teal-400/20 text-teal-200' : 'text-slate-400'
                  }`}
                >
                  {d}m
                </button>
              ))}
            </div>
            <button
              type="button"
              onClick={onOpenGravityCheck}
              className="inline-flex items-center gap-1 rounded-xl border border-purple-400/40 bg-purple-500/15 px-2.5 py-1.5 text-[11px] font-extrabold text-purple-200 hover:bg-purple-500/25"
            >
              <Rocket className="h-3.5 w-3.5" />{' '}
              {copy.gravityCheckTitle.startsWith('60s') ? copy.gravityCheckTitle : `60s ${copy.gravityCheckTitle}`}
            </button>
          </div>
        </div>

        {/* Glowing Tractor Beam Progress Bar */}
        <div className="mt-3">
          <div className="mb-1 flex items-center justify-between text-[10px]">
            <span className="font-bold text-slate-300">
              {stage === 5 ? 'Session Complete!' : STAGE_META[stage - 1].label}
            </span>
            <span className="font-mono font-bold text-brilly">{progressPct}%</span>
          </div>
          <div className="tractor-beam-track h-2.5 w-full">
            <div className="tractor-beam-fill" style={{ width: `${progressPct}%` }} />
          </div>
        </div>

        {/* Stage Pills */}
        <div className="mt-3 grid grid-cols-2 gap-1.5 sm:grid-cols-4">
          {STAGE_META.map((st) => {
            const count =
              st.num === 1 ? stageCounts.s1 : st.num === 2 ? stageCounts.s2 : st.num === 3 ? stageCounts.s3 : stageCounts.s4;
            const active = stage === st.num;
            const done = completedStages.has(st.num);
            return (
              <button
                key={st.num}
                type="button"
                onClick={() => { setStage(st.num); setItemIndex(0); }}
                className={`flex items-center justify-between rounded-xl border px-2.5 py-1.5 text-left text-[10px] font-bold transition ${
                  active
                    ? 'border-teal-400/60 bg-teal-400/15 text-teal-100'
                    : done
                      ? 'border-emerald-500/35 bg-emerald-500/10 text-emerald-200'
                      : 'border-slate-800 bg-void/50 text-slate-400 hover:border-slate-600'
                }`}
              >
                <span className="truncate">{st.short}</span>
                <span className="font-mono text-[9px]">{done ? '✓' : count}</span>
              </button>
            );
          })}
        </div>
      </section>

      {/* Stage 5: Completed Summary */}
      {stage === 5 ? (
        <section className="glass-card border-emerald-400/40 p-6 text-center space-y-3">
          <CheckCircle2 className="mx-auto h-11 w-11 text-clean" />
          <h3 className="text-lg font-extrabold text-white">Daily Coach Session Complete!</h3>
          <p className="mx-auto max-w-md text-xs text-slate-300">
            You completed {completedCount} targeted training positions across Openings FSRS, Blunder Rewind, Woodpecker, and {plan.stage4FocusLabel}.
          </p>
          <div className="flex justify-center gap-2">
            <button
              type="button"
              onClick={onOpenGravityCheck}
              className="inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-purple-500 px-4 py-2 text-xs font-extrabold text-slate-950"
            >
              <Rocket className="h-3.5 w-3.5" /> Launch {copy.gravityCheckTitle}
            </button>
            <button
              type="button"
              onClick={() => {
                setPlanSeed((s) => s + 1);
                setStage(1);
                setItemIndex(0);
                setCompletedCount(0);
                setCompletedStages(new Set());
              }}
              className="rounded-xl border border-slate-700 bg-hull px-3.5 py-2 text-xs font-bold text-slate-200"
            >
              Run Another Loop
            </button>
          </div>
        </section>
      ) : stage === 1 ? (
        activeStage1Card ? (
          <div className="grid gap-3 lg:grid-cols-[minmax(0,400px)_minmax(0,1fr)]">
            <div className="glass-card glass-card-strong p-3">
              <div className="mb-2 flex items-center justify-between text-[10px]">
                <span className="inline-flex items-center gap-1 font-bold text-purple-200">
                  <Orbit className="h-3.5 w-3.5" /> Stage 1 · Opening {itemIndex + 1}/{plan.stage1Cards.length}
                </span>
                <span className="font-mono text-brilly">
                  {activeStage1Card.attempts > 0 ? copy.recallProbability(getRecallProbability(activeStage1Card)) : 'Due'}
                </span>
              </div>
              <ChessgroundBoard
                fen={fen || activeStage1Card.fen}
                orientation={activeStage1Card.side === 'white' ? 'w' : 'b'}
                lastMove={lastMove}
                interactive={status !== 'solved'}
                turnColor={activeStage1Card.side === 'white' ? 'w' : 'b'}
                showBestArrow={false}
                showPlayedArrow={false}
                customArrows={customArrows}
                theme={boardTheme}
                onUserMove={(from, to) => void handleStage1Move(from, to)}
              />
            </div>

            <div className="glass-card p-4 space-y-3">
              <div className="text-[10px] font-black uppercase tracking-[0.16em] text-purple-300">
                Stage 1: Due Opening FSRS
              </div>
              <h3 className="text-sm font-extrabold text-white">
                {courses.find((c) => c.id === activeStage1Card.courseId)?.name ?? 'Opening Repertoire'} · Move{' '}
                {Math.floor(activeStage1Card.ply / 2) + 1}
              </h3>
              <p className="rounded-xl border border-slate-800 bg-void/60 p-3 text-xs text-slate-200">
                {feedback || `Recall your ${activeStage1Card.side} repertoire move cleanly from memory.`}
              </p>
              <div className="flex flex-wrap gap-2">
                {status !== 'solved' && (
                  <button
                    type="button"
                    onClick={() => {
                      setHintUsed(true);
                      const sq = uciToSquares(activeStage1Card.expectedUci);
                      if (sq) setCustomArrows([{ from: sq.from, to: sq.to, color: 'plan' }]);
                    }}
                    className="inline-flex items-center gap-1 rounded-xl border border-amber-400/35 bg-amber-500/10 px-3 py-1.5 text-[11px] font-bold text-amber-200"
                  >
                    <Lightbulb className="h-3.5 w-3.5" /> Hint
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => moveToNextStageOrItem(1, itemIndex)}
                  className="ml-auto inline-flex items-center gap-1 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-3.5 py-1.5 text-xs font-extrabold text-slate-950"
                >
                  {status === 'solved' ? 'Next' : 'Skip'} <ArrowRight className="h-3.5 w-3.5" />
                </button>
              </div>
            </div>
          </div>
        ) : (
          <div className="glass-card p-5 text-center space-y-2.5">
            <Orbit className="mx-auto h-8 w-8 text-purple-300" />
            <h3 className="text-sm font-extrabold text-white">No due Opening FSRS cards right now</h3>
            <p className="mx-auto max-w-md text-xs text-slate-400">
              Unlock your starter courses into FSRS now or jump straight to Stage 2 (Blunder Rewind).
            </p>
            <div className="flex flex-wrap justify-center gap-2">
              <button
                type="button"
                onClick={() => void onUnlockStarterCards().then(() => setPlanSeed((s) => s + 1))}
                className="inline-flex items-center gap-1 rounded-xl border border-purple-400/40 bg-purple-500/15 px-3 py-1.5 text-xs font-bold text-purple-200"
              >
                <Sparkles className="h-3.5 w-3.5" /> Unlock Starter Openings
              </button>
              <button
                type="button"
                onClick={() => { setStage(2); setItemIndex(0); }}
                className="inline-flex items-center gap-1 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-3.5 py-1.5 text-xs font-extrabold text-slate-950"
              >
                Continue to Stage 2 <ArrowRight className="h-3.5 w-3.5" />
              </button>
            </div>
          </div>
        )
      ) : stage === 4 && plan.stage4Conversion ? (
        <div className="space-y-2.5">
          <div className="flex items-center justify-between rounded-xl border border-teal-400/30 bg-teal-400/10 px-3 py-2 text-xs">
            <span className="inline-flex items-center gap-1.5 font-bold text-teal-200">
              <Zap className="h-3.5 w-3.5" /> Stage 4 Focus: {copy.advantageConversion}
            </span>
            <button
              type="button"
              onClick={() => moveToNextStageOrItem(4, 0)}
              className="rounded-lg bg-teal-400 px-2.5 py-1 text-[10px] font-black text-slate-950"
            >
              Finish Session ✓
            </button>
          </div>
          <AdvantageConversionView
            analyzedGames={analyzedGames}
            username={username}
            boardTheme={boardTheme}
            convertedIds={convertedIds}
            focusedPosition={plan.stage4Conversion}
            onMarkConverted={async (id) => {
              await onMarkConverted(id);
              setCompletedCount((c) => c + 1);
            }}
            onOpenGames={onOpenGames}
            onOpenGame={onOpenGame}
          />
        </div>
      ) : activePuzzle ? (
        <div className="grid gap-3 lg:grid-cols-[minmax(0,400px)_minmax(0,1fr)]">
          <div className="glass-card glass-card-strong p-3">
            <div className="mb-2 flex items-center justify-between gap-2 text-[10px]">
              <span className="font-bold text-slate-200">
                Stage {stage} · {stage === 2 ? 'Blunder Rewind' : stage === 3 ? 'Frozen Woodpecker' : plan.stage4FocusLabel} ({itemIndex + 1}/
                {stage === 2 ? stageCounts.s2 : stage === 3 ? stageCounts.s3 : stageCounts.s4})
              </span>
              {stage === 2 && (
                <button
                  type="button"
                  onClick={() => {
                    const next = !radarPingEnabled;
                    setRadarPingEnabled(next);
                    if (!next) setRadarCleared(true);
                  }}
                  className={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[9px] font-black ${
                    radarPingEnabled ? 'border-teal-400/45 bg-teal-400/15 text-teal-200' : 'border-slate-700 text-slate-400'
                  }`}
                >
                  <Radar className="h-3 w-3" /> {copy.radarPingLabel}: {radarPingEnabled ? 'ON' : 'OFF'}
                </button>
              )}
            </div>

            <ChessgroundBoard
              fen={fen || activePuzzle.beforeFen}
              orientation={activePuzzle.color}
              lastMove={lastMove}
              interactive={status === 'idle' && (stage !== 2 || !radarPingEnabled || radarCleared)}
              turnColor={activePuzzle.color}
              showBestArrow={false}
              showPlayedArrow={false}
              customArrows={customArrows}
              squareHighlights={radarHighlights}
              theme={boardTheme}
              onSquareClick={stage === 2 && radarPingEnabled && !radarCleared ? handleRadarTap : undefined}
              onUserMove={(from, to) => void handlePuzzleMove(from, to)}
            />
          </div>

          <div className="glass-card p-4 space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div className="flex items-center gap-1.5">
                <span className="inline-flex items-center gap-1 rounded-lg bg-hull px-2 py-1 text-[10px] font-black uppercase tracking-wider text-brilly">
                  <Target className="h-3 w-3" /> {activePuzzle.tacticalTag}
                </span>
                {totalUserMoves > 1 && (
                  <span className="rounded-full border border-teal-400/35 bg-teal-400/15 px-2 py-0.5 font-mono text-[9px] font-black text-teal-200">
                    Move {currentUserMoveNum}/{totalUserMoves}
                  </span>
                )}
              </div>
              <span className="inline-flex items-center gap-1 font-mono text-[10px] text-slate-400">
                <Clock className="h-3 w-3" /> Played {activePuzzle.san} (-{activePuzzle.winLoss.toFixed(0)}%)
              </span>
            </div>

            {stage === 2 && radarPingEnabled && !radarCleared ? (
              <div className="rounded-xl border border-teal-400/40 bg-teal-400/10 p-3 space-y-2">
                <div className="flex items-center gap-1.5 text-xs font-extrabold text-teal-200">
                  <Radar className="h-4 w-4 animate-pulse" /> 2-Second {copy.radarPingLabel}
                </div>
                <p className="text-xs text-slate-200">{radarInfo?.prompt}</p>
                {radarNote && <p className="text-[11px] font-bold text-amber-200">{radarNote}</p>}
                <button
                  type="button"
                  onClick={() => setRadarCleared(true)}
                  className="rounded-lg border border-slate-700 bg-void/70 px-2.5 py-1 text-[10px] font-bold text-slate-300"
                >
                  Skip ping → Move
                </button>
              </div>
            ) : (
              <div className="rounded-xl border border-slate-800 bg-void/60 p-3 text-xs text-slate-200">
                <div className="font-bold text-white">
                  Find the winning move for {activePuzzle.color === 'w' ? 'White' : 'Black'}.
                </div>
                {radarNote && <p className="mt-1 text-[10px] text-teal-300">{radarNote}</p>}
                {feedback && (
                  <p className={`mt-1.5 font-bold ${status === 'solved' ? 'text-clean' : 'text-amber-300'}`}>
                    {feedback}
                  </p>
                )}
              </div>
            )}

            <div className="flex flex-wrap gap-2">
              {status !== 'solved' && (
                <button
                  type="button"
                  onClick={() => {
                    setHintUsed(true);
                    setRadarCleared(true);
                    const sq = uciToSquares(expectedStep?.uci ?? activePuzzle.bestMoveUci);
                    if (sq) setCustomArrows([{ from: sq.from, to: sq.to, color: 'plan' }]);
                  }}
                  className="inline-flex items-center gap-1 rounded-xl border border-amber-400/35 bg-amber-500/10 px-3 py-1.5 text-[11px] font-bold text-amber-200"
                >
                  <Lightbulb className="h-3.5 w-3.5" /> Hint
                </button>
              )}
              <button
                type="button"
                onClick={() => moveToNextStageOrItem(stage, itemIndex)}
                className="ml-auto inline-flex items-center gap-1 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-3.5 py-1.5 text-xs font-extrabold text-slate-950"
              >
                {status === 'solved' ? 'Next' : 'Skip'} <ArrowRight className="h-3.5 w-3.5" />
              </button>
            </div>
          </div>
        </div>
      ) : stage === 3 && plan.stage3OnCooldown ? (
        <div className="glass-card border-amber-400/35 p-6 text-center space-y-2.5">
          <Clock className="mx-auto h-8 w-8 text-amber-300" />
          <h3 className="text-sm font-extrabold text-amber-200">{copy.woodpeckerRest}</h3>
          <p className="mx-auto max-w-md text-xs text-slate-300">
            Your Frozen Woodpecker Cycle is in its 24h memory consolidation rest
            {plan.stage3CooldownRemainingMs ? ` (${formatCooldownLabel(plan.stage3CooldownRemainingMs)} remaining)` : ''}.
            Let those patterns settle, then move on to Stage 4!
          </p>
          <button
            type="button"
            onClick={() => {
              setCompletedStages((prev) => new Set(prev).add(3));
              setStage(4);
              setItemIndex(0);
            }}
            className="inline-flex items-center gap-1 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-3.5 py-2 text-xs font-extrabold text-slate-950"
          >
            Continue to Stage 4 <ArrowRight className="h-3.5 w-3.5" />
          </button>
        </div>
      ) : (
        <div className="glass-card p-6 text-center space-y-2.5">
          <Sparkles className="mx-auto h-8 w-8 text-slate-600" />
          <h3 className="text-sm font-extrabold text-white">No puzzles available for Stage {stage} yet</h3>
          <p className="mx-auto max-w-md text-xs text-slate-400">
            Analyze a few games to populate Blunder Rewind, Frozen Woodpecker cycles, and Weakness Drills.
          </p>
          <div className="flex justify-center gap-2">
            <button
              type="button"
              onClick={onOpenGames}
              className="rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-3.5 py-2 text-xs font-extrabold text-slate-950"
            >
              Analyze Games
            </button>
            {stage < 4 && (
              <button
                type="button"
                onClick={() => { setStage((stage + 1) as StageNum); setItemIndex(0); }}
                className="rounded-xl border border-slate-700 bg-hull px-3.5 py-2 text-xs font-bold text-slate-200"
              >
                Skip to Stage {stage + 1}
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
