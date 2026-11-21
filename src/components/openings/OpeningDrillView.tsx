import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Chess, type Square } from 'chess.js';
import {
  AlertTriangle,
  ArrowRight,
  Bot,
  CheckCircle2,
  Flame,
  Lightbulb,
  Loader2,
  Orbit,
  RotateCcw,
  Sparkles,
  Swords,
} from 'lucide-react';
import type { BoardThemeId } from '../../types/chess';
import type {
  BoardArrow,
  FsrsOpeningCard,
  OpeningCourse,
  Side,
  WrongMoveTrap,
} from '../../types/openings';
import {
  firstTryAccuracyPct,
  getRecallProbability,
  isCardDue,
  normalizeFenKey,
  reviewFsrsOpeningCard,
  type OpeningGradeLabel,
} from '../../lib/fsrsOpening';
import { fetchLichessExplorer } from '../../services/openingExplorer';
import { buildCoursePositionGraph } from '../../services/repertoireCoverage';
import { stockfishService } from '../../engine/StockfishService';
import { maiaService } from '../../engine/MaiaService';
import { uciToSquares } from '../../utils/chessMath';
import { soundManager } from '../../utils/sound';
import { useVibe } from '../../utils/vibeCopy';
import type { ExplorerPrefSettings } from '../SettingsMenu';
import { ChessgroundBoard } from '../ChessgroundBoard';

export type DrillMode = 'due' | 'weakest' | 'sparring';

interface Props {
  courses: OpeningCourse[];
  side: Side;
  cards: FsrsOpeningCard[];
  boardTheme: BoardThemeId;
  explorerPrefs: ExplorerPrefSettings;
  focusCourseId?: string | null;
  focusLineId?: string | null;
  onCardReviewed: (updated: FsrsOpeningCard) => Promise<void>;
  onUnlockStarterLines: () => Promise<void>;
}

interface TrapState {
  reason: string;
  arrows: BoardArrow[];
  punishmentSeq: string;
  animating: boolean;
}

const GRADE_STYLE: Record<OpeningGradeLabel, string> = {
  Again: 'border-rose-400/40 bg-rose-500/15 text-rose-200',
  Hard: 'border-amber-400/40 bg-amber-500/15 text-amber-200',
  Good: 'border-teal-400/40 bg-teal-500/15 text-teal-200',
  Easy: 'border-emerald-400/40 bg-emerald-500/15 text-emerald-200',
};

export const OpeningDrillView: React.FC<Props> = ({
  courses,
  side,
  cards,
  boardTheme,
  explorerPrefs,
  focusCourseId,
  focusLineId,
  onCardReviewed,
  onUnlockStarterLines,
}) => {
  const { copy } = useVibe();
  const [drillMode, setDrillMode] = useState<DrillMode>('due');
  const [cardIndex, setCardIndex] = useState(0);
  const [boardFen, setBoardFen] = useState('');
  const [lastMove, setLastMove] = useState<[string, string] | undefined>(undefined);
  const [customArrows, setCustomArrows] = useState<BoardArrow[] | undefined>(undefined);
  const [hintUsed, setHintUsed] = useState(false);
  const [hadWrongThisCard, setHadWrongThisCard] = useState(false);
  const [solvedInfo, setSolvedInfo] = useState<{ gradeLabel: OpeningGradeLabel; recallPct: number; ms: number; san: string } | null>(null);
  const [trapState, setTrapState] = useState<TrapState | null>(null);
  const [feedback, setFeedback] = useState('');
  const [sessionCount, setSessionCount] = useState(0);

  // Sparring state
  const [sparringFen, setSparringFen] = useState(() => new Chess().fen());
  const [sparringLastMove, setSparringLastMove] = useState<[string, string] | undefined>(undefined);
  const [sparringMoves, setSparringMoves] = useState<string[]>([]);
  const [sparringPhase, setSparringPhase] = useState<'book' | 'middlegame' | 'finished'>('book');
  const [sparringOutOfBookPlies, setSparringOutOfBookPlies] = useState(0);
  const [sparringStatus, setSparringStatus] = useState('Play your repertoire moves. Opponent responds with real Lichess frequencies.');
  const [sparringThinking, setSparringThinking] = useState(false);
  const [sparringElo, setSparringElo] = useState(explorerPrefs.ratingBand);
  const [sparringEvalDisplay, setSparringEvalDisplay] = useState<string | null>(null);

  const cardStartRef = useRef<number>(performance.now());
  const timersRef = useRef<number[]>([]);
  const sparringGenRef = useRef(0);

  const clearTimers = () => {
    for (const id of timersRef.current) window.clearTimeout(id);
    timersRef.current = [];
  };

  useEffect(() => () => clearTimers(), []);

  const sideCourses = useMemo(
    () => courses.filter((c) => c.side === side && (!focusCourseId || c.id === focusCourseId)),
    [courses, side, focusCourseId]
  );

  // Lookup annotations for trap matching
  const trapLookup = useMemo(() => {
    const map = new Map<string, WrongMoveTrap[]>();
    for (const course of courses) {
      for (const line of course.lines) {
        for (const ann of line.annotations) {
          if (ann.wrongMoveTraps && ann.wrongMoveTraps.length > 0) {
            map.set(`${course.id}::${line.id}::${ann.ply}`, ann.wrongMoveTraps);
          }
        }
      }
    }
    return map;
  }, [courses]);

  const metaLookup = useMemo(() => {
    const map = new Map<string, { courseName: string; lineTitle: string; plan?: string }>();
    for (const course of courses) {
      for (const line of course.lines) {
        for (const ann of line.annotations) {
          map.set(`${course.id}::${line.id}::${ann.ply}`, {
            courseName: course.name,
            lineTitle: line.title,
            plan: ann.plan,
          });
        }
        map.set(`${course.id}::${line.id}`, {
          courseName: course.name,
          lineTitle: line.title,
        });
      }
    }
    return map;
  }, [courses]);

  const sideCards = useMemo(
    () =>
      cards.filter((c) => {
        if (c.side !== side || !c.unlocked) return false;
        if (focusCourseId && c.courseId !== focusCourseId) return false;
        if (focusLineId && c.lineId !== focusLineId) return false;
        return true;
      }),
    [cards, side, focusCourseId, focusLineId]
  );

  const queue = useMemo(() => {
    const now = Date.now();
    if (drillMode === 'weakest') {
      return [...sideCards].sort((a, b) => {
        const devDiff = (b.source === 'game-deviation' ? 1 : 0) - (a.source === 'game-deviation' ? 1 : 0);
        if (devDiff !== 0) return devDiff;
        const accA = a.attempts > 0 ? firstTryAccuracyPct(a) : 50;
        const accB = b.attempts > 0 ? firstTryAccuracyPct(b) : 50;
        if (accA !== accB) return accA - accB;
        return a.dueAt - b.dueAt;
      });
    }
    const due = sideCards.filter((c) => isCardDue(c, now));
    // Prioritize game-deviation boosts, then interleave by dueAt
    return due.sort((a, b) => {
      const devDiff = (b.source === 'game-deviation' ? 1 : 0) - (a.source === 'game-deviation' ? 1 : 0);
      if (devDiff !== 0) return devDiff;
      return a.dueAt - b.dueAt;
    });
  }, [sideCards, drillMode]);

  // Pin the card currently being drilled so ts-fsrs pushing dueAt forward (even on Again)
  // NEVER evicts the card before trap animations, retries, or solved grades finish!
  const [pinnedCard, setPinnedCard] = useState<FsrsOpeningCard | null>(null);
  const safeCardIndex = queue.length > 0 ? Math.min(cardIndex, queue.length - 1) : 0;
  const activeCard = pinnedCard ?? queue[safeCardIndex] ?? null;

  useEffect(() => {
    setPinnedCard(null);
    setCardIndex(0);
  }, [side, drillMode, focusCourseId, focusLineId]);

  useEffect(() => {
    clearTimers();
    if (!activeCard) return;
    setBoardFen(activeCard.fen);
    // Compute opponent's last move leading into this card for orientation context
    let prevLast: [string, string] | undefined;
    if (activeCard.moveSequence.length > 0) {
      const c = new Chess();
      for (const s of activeCard.moveSequence) {
        try {
          const m = c.move(s);
          prevLast = [m.from, m.to];
        } catch {
          break;
        }
      }
    }
    setLastMove(prevLast);
    setCustomArrows(undefined);
    setHintUsed(false);
    setHadWrongThisCard(false);
    setSolvedInfo(null);
    setTrapState(null);
    setFeedback('');
    cardStartRef.current = performance.now();
  }, [activeCard?.cardId, drillMode]);

  const advanceCard = () => {
    clearTimers();
    const wasPinnedId = pinnedCard?.cardId;
    setPinnedCard(null);
    if (queue.length === 0) {
      setCardIndex(0);
      return;
    }
    if (wasPinnedId && !queue.some((c) => c.cardId === wasPinnedId)) {
      // Card already left the due queue — clamp cleanly to current index
      setCardIndex((prev) => Math.min(prev, Math.max(0, queue.length - 1)));
      return;
    }
    if (queue.length <= 1) {
      setCardIndex(0);
      return;
    }
    setCardIndex((prev) => (prev + 1) % queue.length);
  };

  const handleDrillMove = async (from: Square, to: Square) => {
    if (!activeCard || solvedInfo || trapState?.animating) return;
    soundManager.unlock();
    const chess = new Chess(activeCard.fen);
    let mv;
    try {
      mv = chess.move({ from, to, promotion: 'q' });
    } catch {
      return;
    }
    const playedUci = `${mv.from}${mv.to}${mv.promotion ?? ''}`;
    const responseMs = Math.max(150, Math.round(performance.now() - cardStartRef.current));

    if (playedUci === activeCard.expectedUci || mv.san === activeCard.expectedSan) {
      const result = reviewFsrsOpeningCard(activeCard, {
        correct: !hadWrongThisCard,
        responseMs,
        hintUsed,
      });
      // Pin the solved card so the user can read their FSRS grade & plan note and click Next Card!
      setPinnedCard(result.card);
      setBoardFen(chess.fen());
      setLastMove([mv.from, mv.to]);
      setCustomArrows([{ from: mv.from, to: mv.to, color: 'best' }]);
      setTrapState(null);
      setSolvedInfo({
        gradeLabel: result.gradeLabel,
        recallPct: result.recallPct,
        ms: responseMs,
        san: mv.san,
      });
      setSessionCount((c) => c + 1);
      setFeedback(`Correct! ${mv.san} graded ${result.gradeLabel} (${(responseMs / 1000).toFixed(1)}s).`);
      soundManager.playSonarPing();
      await onCardReviewed(result.card);
      return;
    }

    // Wrong move -> pin card BEFORE updating FSRS so trap punishment animation & retry are never cancelled!
    setHadWrongThisCard(true);
    const againRes = reviewFsrsOpeningCard(activeCard, { correct: false, responseMs });
    setPinnedCard(againRes.card);
    await onCardReviewed(againRes.card);

    const traps = trapLookup.get(`${activeCard.courseId}::${activeCard.lineId}::${activeCard.ply}`) ?? [];
    const matchedTrap = traps.find((t) => t.playedSan === mv.san);

    if (matchedTrap) {
      clearTimers();
      soundManager.playHullThud();
      setBoardFen(chess.fen());
      setLastMove([mv.from, mv.to]);
      const baseArrows: BoardArrow[] = matchedTrap.arrows?.length
        ? matchedTrap.arrows
        : [{ from: mv.from, to: mv.to, color: 'threat' }];
      setCustomArrows(baseArrows);
      setTrapState({
        reason: matchedTrap.reason,
        arrows: baseArrows,
        punishmentSeq: matchedTrap.punishmentLine.join(' '),
        animating: true,
      });
      setFeedback(`Trap triggered by ${mv.san}! Watch the refutation, then retry.`);

      const frames: Array<{ fen: string; lastMove: [string, string]; arrow: BoardArrow }> = [];
      for (const pSan of matchedTrap.punishmentLine) {
        try {
          const pmv = chess.move(pSan);
          frames.push({
            fen: chess.fen(),
            lastMove: [pmv.from, pmv.to],
            arrow: { from: pmv.from, to: pmv.to, color: 'threat' },
          });
        } catch {
          break;
        }
      }

      frames.forEach((frame, idx) => {
        const id = window.setTimeout(() => {
          soundManager.playCapture();
          setBoardFen(frame.fen);
          setLastMove(frame.lastMove);
          setCustomArrows([...baseArrows, frame.arrow]);
        }, 650 * (idx + 1));
        timersRef.current.push(id);
      });

      const resetId = window.setTimeout(() => {
        setBoardFen(activeCard.fen);
        setTrapState((prev) => (prev ? { ...prev, animating: false } : null));
        setCustomArrows(baseArrows);
        setFeedback(`Retry now — find the repertoire move instead of ${mv.san}.`);
      }, 650 * (frames.length + 1) + 750);
      timersRef.current.push(resetId);
    } else {
      soundManager.playError();
      const expSq = uciToSquares(activeCard.expectedUci);
      setBoardFen(chess.fen());
      setLastMove([mv.from, mv.to]);
      setCustomArrows(expSq ? [{ from: expSq.from, to: expSq.to, color: 'plan' }] : undefined);
      setFeedback(`Played ${mv.san}, but repertoire expects ${activeCard.expectedSan}. Retry the move now!`);
      const resetId = window.setTimeout(() => {
        setBoardFen(activeCard.fen);
      }, 900);
      timersRef.current.push(resetId);
    }
  };

  /* ---------- Opening Sparring (Play-Out Mode) ---------- */
  const sparringGraph = useMemo(() => {
    const merged: OpeningCourse = {
      id: 'sparring-merged',
      name: 'Sparring',
      codename: 'Sparring',
      side,
      difficulty: 'Intermediate',
      tagline: '',
      mothershipSetup: { previewMoves: [], arrows: [], highlights: [], corePlans: [], goldenRules: [] },
      lines: sideCourses.flatMap((c) => c.lines),
    };
    return buildCoursePositionGraph(merged);
  }, [sideCourses, side]);

  const startSparring = async () => {
    sparringGenRef.current += 1;
    const gen = sparringGenRef.current;
    const start = new Chess();
    setSparringFen(start.fen());
    setSparringLastMove(undefined);
    setSparringMoves([]);
    setSparringPhase('book');
    setSparringOutOfBookPlies(0);
    setSparringEvalDisplay(null);
    setSparringThinking(false);

    if (side === 'black') {
      setSparringStatus('Opponent choosing a popular 1st move at your rating band…');
      await playSparringOpponentReply(start.fen(), [], 'book', 0, gen);
    } else {
      setSparringStatus('Your move as White! Play your opening repertoire.');
    }
  };

  useEffect(() => {
    if (drillMode === 'sparring') {
      void startSparring();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [drillMode, side]);

  const pickWeightedMove = <T extends { games: number }>(items: T[]): T => {
    const total = items.reduce((s, it) => s + Math.max(1, it.games), 0);
    let r = Math.random() * total;
    for (const it of items) {
      r -= Math.max(1, it.games);
      if (r <= 0) return it;
    }
    return items[0];
  };

  const playSparringOpponentReply = async (
    fen: string,
    movesSoFar: string[],
    phase: 'book' | 'middlegame',
    outOfBookCount: number,
    gen: number
  ) => {
    setSparringThinking(true);
    try {
      const chess = new Chess(fen);
      if (chess.isGameOver()) {
        setSparringPhase('finished');
        setSparringStatus('Sparring game concluded!');
        return;
      }

      if (phase === 'book') {
        // Weighted pick from Lichess Explorer filtered by rating & speed
        const live = await fetchLichessExplorer(fen, {
          ratingBand: sparringElo,
          speeds: explorerPrefs.speeds,
          moves: 6,
        });
        if (sparringGenRef.current !== gen) return;

        let chosenSan: string | null = null;
        if (live && live.moves.length > 0) {
          const topMoves = live.moves.filter((m) => m.games / live.games >= 0.05);
          const pool = topMoves.length > 0 ? topMoves : live.moves.slice(0, 4);
          chosenSan = pickWeightedMove(pool).san;
        } else {
          // Offline fallback: pick from course graph if available
          const node = sparringGraph.get(normalizeFenKey(fen));
          const replies = node ? Array.from(node.replies.keys()) : [];
          if (replies.length > 0) {
            chosenSan = replies[Math.floor(Math.random() * replies.length)];
          }
        }

        if (chosenSan) {
          const mv = chess.move(chosenSan);
          const nextFen = chess.fen();
          const nextMoves = [...movesSoFar, mv.san];
          soundManager.playMove();
          setSparringFen(nextFen);
          setSparringLastMove([mv.from, mv.to]);
          setSparringMoves(nextMoves);

          const inRep = sparringGraph.has(normalizeFenKey(nextFen));
          if (!inRep && nextMoves.length >= 4) {
            setSparringPhase('middlegame');
            setSparringStatus(`Opponent played ${mv.san} (out of book!) — play out 8 middlegame moves vs Stockfish ${sparringElo}.`);
          } else {
            setSparringStatus(`Opponent played ${mv.san} (Lichess ${sparringElo} pool). Your turn!`);
          }
          return;
        }
      }

      // Out of book: Maia ONNX (if enabled & present) or rating-capped Stockfish middlegame play-out
      const { moveUci: botUci, engine: botEngine } = await maiaService.getSmartBotMove(fen, sparringElo);
      if (sparringGenRef.current !== gen) return;
      const parsed = uciToSquares(botUci);
      if (!parsed) {
        setSparringPhase('finished');
        setSparringStatus('Sparring play-out complete.');
        return;
      }
      const mv = chess.move({ from: parsed.from, to: parsed.to, promotion: parsed.promotion });
      const nextFen = chess.fen();
      const nextMoves = [...movesSoFar, mv.san];
      const nextOut = outOfBookCount + 1;
      soundManager.playMove();
      setSparringFen(nextFen);
      setSparringLastMove([mv.from, mv.to]);
      setSparringMoves(nextMoves);
      setSparringOutOfBookPlies(nextOut);

      const engineTag = botEngine === 'maia' ? `Maia ${sparringElo}` : `Bot (${sparringElo})`;
      if (nextOut >= 8 || chess.isGameOver()) {
        try {
          const evalRes = await stockfishService.analyzePosition(nextFen, { depth: 12, multiPv: 1, timeoutMs: 8000 });
          if (sparringGenRef.current !== gen) return;
          setSparringEvalDisplay(evalRes.score.display);
          setSparringPhase('finished');
          setSparringStatus(`Sparring complete! Final Stockfish eval: ${evalRes.score.display}.`);
        } catch {
          if (sparringGenRef.current !== gen) return;
          setSparringPhase('finished');
          setSparringStatus('Sparring play-out complete!');
        }
      } else {
        setSparringStatus(`${engineTag} played ${mv.san}. Play-out move ${nextOut}/8.`);
      }
    } catch {
      if (sparringGenRef.current !== gen) return;
      // Never soft-lock on opponent's turn if engine is busy or cancelled — roll back last move cleanly
      const rollback = new Chess();
      const kept = movesSoFar.slice(0, Math.max(0, movesSoFar.length - 1));
      for (const s of kept) {
        try { rollback.move(s); } catch { break; }
      }
      setSparringFen(rollback.fen());
      setSparringMoves(kept);
      setSparringLastMove(undefined);
      setSparringStatus('Engine busy or interrupted — play your move again.');
    } finally {
      if (sparringGenRef.current === gen) setSparringThinking(false);
    }
  };

  const handleSparringUserMove = async (from: Square, to: Square) => {
    if (sparringThinking || sparringPhase === 'finished') return;
    soundManager.unlock();
    const gen = sparringGenRef.current;
    const chess = new Chess(sparringFen);
    let mv;
    try {
      mv = chess.move({ from, to, promotion: 'q' });
    } catch {
      return;
    }
    const nextFen = chess.fen();
    const nextMoves = [...sparringMoves, mv.san];
    soundManager.playMove();
    setSparringFen(nextFen);
    setSparringLastMove([mv.from, mv.to]);
    setSparringMoves(nextMoves);

    let nextPhase = sparringPhase;
    if (sparringPhase === 'book') {
      const node = sparringGraph.get(normalizeFenKey(sparringFen));
      if (node && !node.replies.has(mv.san)) {
        nextPhase = 'middlegame';
        setSparringPhase('middlegame');
        const expected = Array.from(node.replies.keys()).join(' / ');
        setSparringStatus(`You deviated with ${mv.san} (book: ${expected}). Playing out middlegame vs bot!`);
      }
    }

    await playSparringOpponentReply(nextFen, nextMoves, nextPhase, sparringOutOfBookPlies, gen);
  };

  const orientation = side === 'white' ? 'w' : 'b';
  const activeMeta = activeCard
    ? metaLookup.get(`${activeCard.courseId}::${activeCard.lineId}::${activeCard.ply}`)
      ?? metaLookup.get(`${activeCard.courseId}::${activeCard.lineId}`)
    : null;
  const activeRecall = activeCard ? getRecallProbability(activeCard) : 0;

  return (
    <div className="space-y-3">
      {/* Mode Switcher */}
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="inline-flex rounded-xl border border-slate-800 bg-void/70 p-0.5">
          {([
            ['due', `Due Reviews (${sideCards.filter((c) => isCardDue(c)).length})`],
            ['weakest', 'Weakest Lines'],
            ['sparring', 'Opening Sparring'],
          ] as Array<[DrillMode, string]>).map(([m, label]) => (
            <button
              key={m}
              type="button"
              onClick={() => { setDrillMode(m); setCardIndex(0); }}
              className={`rounded-lg px-2.5 py-1.5 text-[10px] font-black transition ${
                drillMode === m
                  ? 'bg-gradient-to-r from-teal-400/20 to-purple-500/20 text-teal-200'
                  : 'text-slate-400 hover:text-slate-200'
              }`}
            >
              {label}
            </button>
          ))}
        </div>
        {sessionCount > 0 && drillMode !== 'sparring' && (
          <span className="inline-flex items-center gap-1 rounded-full border border-teal-400/30 bg-teal-400/10 px-2.5 py-1 font-mono text-[10px] font-bold text-teal-200">
            <Flame className="h-3 w-3 text-amber-400" /> {sessionCount} reviewed
          </span>
        )}
      </div>

      {drillMode === 'sparring' ? (
        <div className="grid gap-3 lg:grid-cols-[minmax(0,400px)_minmax(0,1fr)]">
          <div className="glass-card glass-card-strong p-3">
            <div className="mb-2 flex items-center justify-between text-[10px]">
              <span className="inline-flex items-center gap-1 font-bold text-teal-200">
                <Swords className="h-3.5 w-3.5" />
                {sparringPhase === 'book' ? 'Book Phase (Lichess Frequencies)' : 'Middlegame Play-Out'}
              </span>
              <span className="font-mono text-slate-400">Bot {sparringElo}</span>
            </div>

            <div className="relative">
              <ChessgroundBoard
                fen={sparringFen}
                orientation={orientation}
                lastMove={sparringLastMove}
                interactive={!sparringThinking && sparringPhase !== 'finished'}
                turnColor={orientation}
                showBestArrow={false}
                showPlayedArrow={false}
                theme={boardTheme}
                onUserMove={(from, to) => void handleSparringUserMove(from, to)}
              />
              {sparringThinking && (
                <div className="pointer-events-none absolute right-2 top-2 z-30 inline-flex items-center gap-1 rounded-full border border-teal-400/35 bg-void/90 px-2.5 py-1 text-[10px] font-bold text-teal-200">
                  <Loader2 className="h-3 w-3 animate-spin" /> thinking
                </div>
              )}
            </div>
          </div>

          <div className="glass-card p-4 space-y-3">
            <div className="flex items-center justify-between gap-2">
              <div className="flex items-center gap-1.5 text-xs font-extrabold text-white">
                <Bot className="h-4 w-4 text-brilly" /> Opening Sparring Arena
              </div>
              <button
                type="button"
                onClick={() => void startSparring()}
                className="inline-flex items-center gap-1 rounded-xl border border-slate-700 bg-hull px-2.5 py-1.5 text-[10px] font-bold text-slate-200 hover:border-teal-400/50"
              >
                <RotateCcw className="h-3 w-3" /> New Spar
              </button>
            </div>

            <p className="rounded-xl border border-slate-800 bg-void/60 p-3 text-xs leading-relaxed text-slate-200">
              {sparringStatus}
            </p>

            {sparringEvalDisplay && (
              <div className="rounded-xl border border-teal-400/35 bg-teal-400/10 px-3 py-2 text-xs font-bold text-teal-200">
                Stockfish Verdict: <span className="font-mono">{sparringEvalDisplay}</span>
              </div>
            )}

            <div>
              <div className="flex items-center justify-between text-[10px] font-bold text-slate-400">
                <span>Sparring Strength (Rating Bracket)</span>
                <span className="font-mono text-brilly">{sparringElo} Elo</span>
              </div>
              <input
                type="range"
                min={1000}
                max={2200}
                step={100}
                value={sparringElo}
                onChange={(e) => setSparringElo(Number(e.target.value))}
                className="mt-1 w-full accent-teal-400"
              />
            </div>

            {sparringMoves.length > 0 && (
              <div className="rounded-xl border border-slate-800 bg-void/50 p-2.5">
                <div className="text-[9px] font-black uppercase tracking-wider text-slate-500">Moves Played</div>
                <div className="mt-1 font-mono text-[11px] leading-relaxed text-slate-300">
                  {sparringMoves.map((m, i) => (i % 2 === 0 ? `${Math.floor(i / 2) + 1}.${m}` : m)).join(' ')}
                </div>
              </div>
            )}
          </div>
        </div>
      ) : sideCards.length === 0 ? (
        <div className="glass-card p-6 text-center">
          <Orbit className="mx-auto h-9 w-9 text-purple-300/70" />
          <h3 className="mt-2 text-sm font-extrabold text-white">No lines unlocked in FSRS yet</h3>
          <p className="mx-auto mt-1 max-w-md text-xs leading-relaxed text-slate-400">
            Walk through a line first to lock in the ideas—or unlock your starter {side} course lines right now to start FSRS active recall.
          </p>
          <button
            type="button"
            onClick={() => void onUnlockStarterLines()}
            className="mt-3 inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-purple-500 px-4 py-2 text-xs font-extrabold text-slate-950"
          >
            <Sparkles className="h-3.5 w-3.5" /> Unlock All {side === 'white' ? 'White' : 'Black'} Starter Lines
          </button>
        </div>
      ) : !activeCard ? (
        <div className="glass-card border-emerald-500/30 p-6 text-center">
          <CheckCircle2 className="mx-auto h-9 w-9 text-clean" />
          <h3 className="mt-2 text-sm font-extrabold text-white">All due FSRS reviews complete!</h3>
          <p className="mx-auto mt-1 max-w-md text-xs leading-relaxed text-slate-400">
            Your {side} repertoire signals are locked in for today. Switch to Weakest Lines or Opening Sparring to keep sharpening.
          </p>
          <div className="mt-3 flex justify-center gap-2">
            <button
              type="button"
              onClick={() => setDrillMode('weakest')}
              className="rounded-xl border border-purple-400/40 bg-purple-500/15 px-3 py-1.5 text-xs font-bold text-purple-200"
            >
              Drill Weakest Lines
            </button>
            <button
              type="button"
              onClick={() => setDrillMode('sparring')}
              className="rounded-xl border border-teal-400/40 bg-teal-400/15 px-3 py-1.5 text-xs font-bold text-teal-200"
            >
              Launch Sparring
            </button>
          </div>
        </div>
      ) : (
        <div className="grid gap-3 lg:grid-cols-[minmax(0,400px)_minmax(0,1fr)]">
          <div className="glass-card glass-card-strong p-3">
            <div className="mb-2 flex items-center justify-between gap-2 text-[10px]">
              <span className="truncate font-bold text-slate-200">
                {activeMeta?.courseName ?? activeCard.courseId} · Move {Math.floor(activeCard.ply / 2) + 1}
              </span>
              <span className="shrink-0 font-mono font-bold text-purple-300">
                {activeCard.attempts > 0 ? copy.recallProbability(activeRecall) : 'New Card'}
              </span>
            </div>

            <ChessgroundBoard
              fen={boardFen || activeCard.fen}
              orientation={orientation}
              lastMove={lastMove}
              interactive={!solvedInfo && !trapState?.animating}
              turnColor={orientation}
              showBestArrow={false}
              showPlayedArrow={false}
              customArrows={customArrows}
              theme={boardTheme}
              onUserMove={(from, to) => void handleDrillMove(from, to)}
            />
          </div>

          <div className="glass-card p-4 space-y-3">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.16em] text-brilly">
                  <Orbit className="h-3.5 w-3.5" /> FSRS Active Recall
                  {activeCard.source === 'game-deviation' && (
                    <span className="rounded-full border border-amber-400/40 bg-amber-500/15 px-2 py-0.5 text-[9px] text-amber-200">
                      Boosted Leak
                    </span>
                  )}
                </div>
                <h3 className="mt-0.5 text-sm font-extrabold text-white">
                  {activeMeta?.lineTitle ?? 'Find your repertoire move'}
                </h3>
              </div>
              <span className="rounded-lg border border-slate-800 bg-void/70 px-2 py-1 font-mono text-[10px] text-slate-400">
                {queue.length > 0 ? `${safeCardIndex + 1}/${queue.length}` : '1/1'} in queue
              </span>
            </div>

            {activeCard.moveSequence.length > 0 && (
              <div className="rounded-xl border border-slate-800/80 bg-void/50 px-2.5 py-1.5 font-mono text-[11px] text-slate-400">
                Line: {activeCard.moveSequence.map((m, i) => (i % 2 === 0 ? `${Math.floor(i / 2) + 1}.${m}` : m)).join(' ')}
              </div>
            )}

            {solvedInfo ? (
              <div className="space-y-2 rounded-xl border border-emerald-500/35 bg-emerald-500/10 p-3">
                <div className="flex items-center justify-between gap-2">
                  <span className="inline-flex items-center gap-1.5 text-xs font-extrabold text-emerald-200">
                    <CheckCircle2 className="h-4 w-4" /> {solvedInfo.san} locked in!
                  </span>
                  <span className={`rounded-full border px-2 py-0.5 text-[10px] font-black ${GRADE_STYLE[solvedInfo.gradeLabel]}`}>
                    {solvedInfo.gradeLabel} · {(solvedInfo.ms / 1000).toFixed(1)}s
                  </span>
                </div>
                {activeMeta?.plan && <p className="text-xs leading-relaxed text-emerald-100/90">{activeMeta.plan}</p>}
                <div className="flex items-center justify-between text-[10px] text-slate-300">
                  <span>{copy.recallProbability(solvedInfo.recallPct)}</span>
                  <button
                    type="button"
                    onClick={advanceCard}
                    className="inline-flex items-center gap-1 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-3 py-1.5 text-xs font-extrabold text-slate-950"
                  >
                    Next Card <ArrowRight className="h-3.5 w-3.5" />
                  </button>
                </div>
              </div>
            ) : trapState ? (
              <div className="space-y-1.5 rounded-xl border border-rose-500/40 bg-rose-500/10 p-3">
                <div className="flex items-center gap-1.5 text-xs font-extrabold text-blunder">
                  <AlertTriangle className="h-4 w-4" /> {copy.blunderLabel} — Punishment Animated
                </div>
                <p className="text-xs leading-relaxed text-rose-100">{trapState.reason}</p>
                <div className="font-mono text-[10px] text-rose-300">Refutation: {trapState.punishmentSeq}</div>
                <div className="text-[10px] font-bold text-slate-300">
                  {trapState.animating ? 'Animating opponent punishment…' : 'Graded Again — play the right move now to continue.'}
                </div>
              </div>
            ) : (
              <div className="rounded-xl border border-slate-800 bg-void/60 p-3 text-xs text-slate-300">
                {feedback || `Play your ${side} repertoire move on the board. Instant (<3s) = Easy · 3–10s = Good · >10s or Hint = Hard.`}
              </div>
            )}

            <div className="flex flex-wrap items-center gap-2">
              {!solvedInfo && (
                <button
                  type="button"
                  onClick={() => {
                    setHintUsed(true);
                    const sq = uciToSquares(activeCard.expectedUci);
                    if (sq) setCustomArrows([{ from: sq.from, to: sq.to, color: 'plan' }]);
                    setFeedback(`Hint: move from ${sq?.from ?? '?'} (graded Hard max).`);
                  }}
                  className="inline-flex items-center gap-1 rounded-xl border border-amber-400/35 bg-amber-500/10 px-3 py-1.5 text-[11px] font-bold text-amber-200"
                >
                  <Lightbulb className="h-3.5 w-3.5" /> Hint
                </button>
              )}
              <button
                type="button"
                onClick={advanceCard}
                className="ml-auto inline-flex items-center gap-1 rounded-xl border border-slate-700 bg-hull px-3 py-1.5 text-[11px] font-bold text-slate-300 hover:border-slate-500"
              >
                Skip <ArrowRight className="h-3.5 w-3.5" />
              </button>
            </div>

            <div className="grid grid-cols-3 gap-2 border-t border-slate-800/80 pt-2.5 text-center">
              <div className="rounded-lg border border-slate-800/80 bg-void/50 p-1.5">
                <div className="font-mono text-xs font-black text-brilly">{activeCard.attempts}</div>
                <div className="text-[9px] text-slate-500">Reviews</div>
              </div>
              <div className="rounded-lg border border-slate-800/80 bg-void/50 p-1.5">
                <div className="font-mono text-xs font-black text-clean">{firstTryAccuracyPct(activeCard)}%</div>
                <div className="text-[9px] text-slate-500">1st-Try</div>
              </div>
              <div className="rounded-lg border border-slate-800/80 bg-void/50 p-1.5">
                <div className="font-mono text-xs font-black text-purple-300">
                  {activeCard.avgResponseMs > 0 ? `${(activeCard.avgResponseMs / 1000).toFixed(1)}s` : '—'}
                </div>
                <div className="text-[9px] text-slate-500">Avg Speed</div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
