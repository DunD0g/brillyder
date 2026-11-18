import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Chess, type PieceSymbol, type Square } from 'chess.js';
import {
  ArrowRight,
  CalendarDays,
  CheckCircle2,
  Flame,
  GraduationCap,
  Lightbulb,
  Loader2,
  Play,
  RotateCcw,
  Sparkles,
  Target,
  Trophy,
  XCircle,
  Zap,
} from 'lucide-react';
import type { AnalyzedGame, BoardThemeId, DrillStreak, MistakeClassification, MistakeProgressRecord, MistakePuzzle } from '../types/chess';
import {
  buildMistakeDeck,
  dateKey,
  loadDailyDone,
  loadDrillStreak,
  loadMistakeProgress,
  loadRushBest,
  markDailyDone,
  pickDailyPuzzle,
  recordAttempt,
  recordDrillSolve,
} from '../services/mistakeDeck';
import { isSacrificeMove } from '../chess/classification';
import { getMoverWinPercent, uciToSquares } from '../utils/chessMath';
import { stockfishService } from '../engine/StockfishService';
import { soundManager } from '../utils/sound';
import { ChessgroundBoard } from './ChessgroundBoard';
import { ClassificationBadge } from './ClassificationBadge';
import { ProgressRing } from './ProgressRing';
import { AlienCelebration } from './AlienCelebration';
import { PuzzleRush } from './PuzzleRush';

interface Props {
  analyzedGames: AnalyzedGame[];
  username: string;
  boardTheme: BoardThemeId;
  onOpenGame: (gameId: string, ply: number) => void;
  onOpenGames: () => void;
}

type DrillStatus = 'idle' | 'evaluating' | 'wrong' | 'solved' | 'revealed';
type DeckFilter = 'unsolved' | 'all' | 'mastered';
type DeckPhaseFilter = 'all' | 'opening' | 'middlegame' | 'endgame';

const PIECE_NAMES: Record<PieceSymbol, string> = { p: 'pawn', n: 'knight', b: 'bishop', r: 'rook', q: 'queen', k: 'king' };

export const MistakeTrainerView: React.FC<Props> = ({ analyzedGames, username, boardTheme, onOpenGame, onOpenGames }) => {
  const deck = useMemo(() => buildMistakeDeck(analyzedGames, username), [analyzedGames, username]);
  const dailyPuzzle = useMemo(() => pickDailyPuzzle(deck), [deck]);
  const [progress, setProgress] = useState<Record<string, MistakeProgressRecord>>(() => loadMistakeProgress());
  const [streak, setStreak] = useState<DrillStreak>(() => loadDrillStreak());
  const [mode, setMode] = useState<'practice' | 'rush'>('practice');
  const [filter, setFilter] = useState<DeckFilter>('unsolved');
  const [phaseFilter, setPhaseFilter] = useState<DeckPhaseFilter>('all');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [fen, setFen] = useState('');
  const [status, setStatus] = useState<DrillStatus>('idle');
  const [feedback, setFeedback] = useState('');
  const [hintLevel, setHintLevel] = useState(0);
  const [lastMove, setLastMove] = useState<[string, string] | null>(null);
  const [pendingPromo, setPendingPromo] = useState<{ from: Square; to: Square } | null>(null);
  const [celebration, setCelebration] = useState<{ trigger: number; message: string } | null>(null);
  const [dailyDoneDate, setDailyDoneDate] = useState(() => loadDailyDone());
  const [rushBest, setRushBest] = useState(() => loadRushBest());
  const resetTimerRef = useRef<number | null>(null);
  const puzzleRunRef = useRef(0);
  const boardRef = useRef<HTMLDivElement | null>(null);

  const solvedCount = deck.filter((p) => progress[p.id]?.solved).length;
  const unsolvedCount = deck.length - solvedCount;
  const selected = deck.find((p) => p.id === selectedId) ?? null;
  const dailyDone = dailyDoneDate === dateKey();

  const selectPuzzle = (puzzle: MistakePuzzle, options?: { scroll?: boolean }) => {
    if (resetTimerRef.current) window.clearTimeout(resetTimerRef.current);
    puzzleRunRef.current += 1;
    setSelectedId(puzzle.id);
    setFen(puzzle.beforeFen);
    setStatus('idle');
    setFeedback('');
    setHintLevel(0);
    setLastMove(null);
    setPendingPromo(null);
    if (options?.scroll && typeof window !== 'undefined' && window.matchMedia('(max-width: 1023px)').matches) {
      window.setTimeout(() => boardRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' }), 60);
    }
  };

  useEffect(() => {
    if (deck.length === 0) return;
    if (selectedId && deck.some((p) => p.id === selectedId)) return;
    const next = deck.find((p) => !progress[p.id]?.solved) ?? deck[0];
    selectPuzzle(next);
    // selectPuzzle is intentionally scoped to this effect.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [deck, selectedId]);

  useEffect(() => () => { if (resetTimerRef.current) window.clearTimeout(resetTimerRef.current); }, []);

  const chooseNext = () => {
    if (!selected) return;
    const next = deck.find((p) => p.id !== selected.id && !progress[p.id]?.solved) ?? deck.find((p) => p.id !== selected.id);
    if (next) selectPuzzle(next);
  };

  const solve = (puzzle: MistakePuzzle, fenAfter: string, san: string, detail: string, mover?: { to: string; piece: PieceSymbol; captured?: PieceSymbol }) => {
    setProgress((prev) => recordAttempt(prev, puzzle.id, true));
    setStreak(recordDrillSolve());
    if (dailyPuzzle?.id === puzzle.id) setDailyDoneDate(markDailyDone());
    setFen(fenAfter);
    setStatus('solved');
    setFeedback(`${san} — ${detail}`);
    soundManager.playSuccess();
    if (mover && isSacrificeMove(puzzle.beforeFen, fenAfter, puzzle.color, mover.to, mover.piece, mover.captured)) {
      setCelebration({ trigger: Date.now(), message: 'Certified Galaxy-Brain — you found the sacrifice under pressure! 🛸' });
    }
  };

  const attemptMove = async (from: Square, to: Square, promotion?: PieceSymbol) => {
    if (!selected || status === 'solved' || status === 'revealed' || status === 'evaluating') return;
    const generation = puzzleRunRef.current;
    const c = new Chess(fen);
    let mv;
    try { mv = c.move({ from, to, promotion }); } catch { return; }
    const uci = `${mv.from}${mv.to}${mv.promotion ?? ''}`;
    if (uci === selected.bestMoveUci) {
      solve(selected, c.fen(), mv.san, `Stockfish's top choice. Puzzle mastered.`, mv);
      return;
    }

    soundManager.playMove();
    setFen(c.fen());
    setLastMove([mv.from, mv.to]);
    setStatus('evaluating');
    setFeedback('Checking your idea…');
    try {
      const analysis = stockfishService.analyzePosition(c.fen(), { depth: 10, multiPv: 1, timeoutMs: 8000 });
      const timeout = new Promise<never>((_, reject) => {
        window.setTimeout(() => reject(new Error('Engine timeout')), 9500);
      });
      const res = await Promise.race([analysis, timeout]);
      if (puzzleRunRef.current !== generation) return;
      const loss = Math.max(0, getMoverWinPercent(selected.evalBefore, selected.color) - getMoverWinPercent(res.score, selected.color));
      if (loss <= 6) {
        solve(selected, c.fen(), mv.san, `A strong alternative that holds (${res.score.display}).`, mv);
      } else {
        soundManager.playError();
        setProgress((prev) => recordAttempt(prev, selected.id, false));
        setStatus('wrong');
        setFeedback(`${mv.san} drops ${loss.toFixed(0)}% win equity (${res.score.display}). The position resets — try another idea.`);
        if (resetTimerRef.current) window.clearTimeout(resetTimerRef.current);
        resetTimerRef.current = window.setTimeout(() => {
          if (puzzleRunRef.current !== generation) return;
          setFen(selected.beforeFen);
          setLastMove(null);
          setStatus('idle');
        }, 1100);
      }
    } catch {
      if (puzzleRunRef.current !== generation) return;
      setStatus('idle');
      setFen(selected.beforeFen);
      setLastMove(null);
      setFeedback('Engine timed out. Tap a piece to try again.');
    }
  };

  const handleMove = (from: Square, to: Square) => {
    if (!selected || status !== 'idle') return;
    const legal = new Chess(fen).moves({ square: from, verbose: true }).filter((m) => m.to === to);
    if (legal.length === 0) return;
    if (legal.some((m) => Boolean(m.promotion))) { setPendingPromo({ from, to }); return; }
    void attemptMove(from, to);
  };

  const revealSolution = () => {
    if (!selected) return;
    const parsed = uciToSquares(selected.bestMoveUci);
    if (!parsed) return;
    const c = new Chess(selected.beforeFen);
    let after = selected.beforeFen;
    try {
      const mv = c.move({ from: parsed.from, to: parsed.to, promotion: parsed.promotion });
      after = c.fen();
      setLastMove([mv.from, mv.to]);
    } catch { /* ignore */ }
    setFen(after);
    setStatus('revealed');
    setFeedback(`Best was ${selected.bestMoveSan}. ${selected.headline}`);
    setProgress((prev) => recordAttempt(prev, selected.id, false));
  };

  const hintedPiece = useMemo(() => {
    if (!selected) return null;
    const parsed = uciToSquares(selected.bestMoveUci);
    if (!parsed) return null;
    try {
      const piece = new Chess(selected.beforeFen).get(parsed.from);
      return piece?.type ?? null;
    } catch {
      return null;
    }
  }, [selected]);

  const filteredDeck = deck.filter((p) => {
    if (phaseFilter !== 'all' && p.phase !== phaseFilter) return false;
    if (filter === 'all') return true;
    if (filter === 'mastered') return Boolean(progress[p.id]?.solved);
    return !progress[p.id]?.solved;
  });

  const handleRushSolved = (puzzle: MistakePuzzle) => {
    setProgress((prev) => recordAttempt(prev, puzzle.id, true));
    setStreak(recordDrillSolve());
  };

  const handleRushWrong = (puzzle: MistakePuzzle) => {
    setProgress((prev) => recordAttempt(prev, puzzle.id, false));
  };

  const handleRushFinished = () => {
    setRushBest(loadRushBest());
  };

  const solvedPct = deck.length > 0 ? Math.round((solvedCount / deck.length) * 100) : 0;
  const interactive = Boolean(selected) && status === 'idle';
  const classificationTone: Record<MistakeClassification, string> = {
    blunder: 'text-red-300',
    mistake: 'text-orange-300',
    inaccuracy: 'text-yellow-300',
  };

  if (deck.length === 0) {
    return (
      <div className="space-y-3 pb-24">
        <section className="glass-card p-7 text-center">
          <GraduationCap className="mx-auto h-9 w-9 text-slate-600" />
          <h1 className="mt-2 text-base font-extrabold text-slate-100">Mistake deck is empty</h1>
          <p className="mx-auto mt-1 max-w-md text-xs leading-relaxed text-slate-400">
            Analyze games and every <span className="font-bold text-orange-300">?</span> mistake and <span className="font-bold text-red-400">??</span> blunder you played becomes a personal puzzle — position, best move, and all.
          </p>
          <button type="button" onClick={onOpenGames} className="mt-3 inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-cyan-400 to-emerald-400 px-3.5 py-2 text-xs font-extrabold text-slate-950">
            <Sparkles className="h-3.5 w-3.5" /> Analyze games
          </button>
        </section>
      </div>
    );
  }

  if (mode === 'rush') {
    return (
      <PuzzleRush
        puzzles={deck}
        boardTheme={boardTheme}
        onExit={() => setMode('practice')}
        onSolved={handleRushSolved}
        onWrong={handleRushWrong}
        onFinished={handleRushFinished}
      />
    );
  }

  return (
    <div className="space-y-3 pb-24">
      <section className="glass-card glass-card-strong p-3.5">
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-amber-300">
              <Target className="h-4 w-4" /> Woodpecker deck
            </div>
            <h1 className="mt-1 text-lg font-extrabold text-white">Train your real mistakes</h1>
            <p className="mt-0.5 text-[11px] text-slate-400">{unsolvedCount} unsolved · {solvedCount} mastered · {deck.length} total</p>
          </div>
          <div className="flex items-center gap-2">
            <ProgressRing value={solvedPct} size={62} stroke={6} tone="emerald" label={`${solvedPct}%`} sublabel="solved" />
          </div>
        </div>
        <div className="mt-3 grid grid-cols-3 gap-2">
          <div className="rounded-xl border border-slate-800 bg-slate-950/45 p-2">
            <div className="flex items-center gap-1 text-[9px] font-bold uppercase tracking-wide text-slate-500"><Flame className="h-3 w-3 text-orange-400" /> Streak</div>
            <div className="mt-0.5 font-mono text-base font-extrabold text-orange-300">{streak.current}</div>
            <div className="text-[9px] text-slate-500">best {streak.best}</div>
          </div>
          <div className="rounded-xl border border-slate-800 bg-slate-950/45 p-2">
            <div className="flex items-center gap-1 text-[9px] font-bold uppercase tracking-wide text-slate-500"><Trophy className="h-3 w-3 text-amber-300" /> Mastered</div>
            <div className="mt-0.5 font-mono text-base font-extrabold text-emerald-300">{solvedCount}</div>
            <div className="text-[9px] text-slate-500">{deck.length > 0 ? `${solvedPct}% of deck` : '—'}</div>
          </div>
          <div className="rounded-xl border border-slate-800 bg-slate-950/45 p-2">
            <div className="flex items-center gap-1 text-[9px] font-bold uppercase tracking-wide text-slate-500"><XCircle className="h-3 w-3 text-rose-400" /> Unsolved</div>
            <div className="mt-0.5 font-mono text-base font-extrabold text-rose-300">{unsolvedCount}</div>
            <div className="text-[9px] text-slate-500">back-to-back</div>
          </div>
        </div>

        <div className="mt-2 grid grid-cols-2 gap-1.5">
          <button
            type="button"
            onClick={() => setMode('practice')}
            className="inline-flex items-center justify-center gap-1.5 rounded-xl border border-cyan-400/35 bg-cyan-500/15 px-2 py-2 text-[11px] font-black text-cyan-100"
          >
            <GraduationCap className="h-3.5 w-3.5" /> Practice deck
          </button>
          <button
            type="button"
            onClick={() => setMode('rush')}
            className="inline-flex items-center justify-center gap-1.5 rounded-xl border border-fuchsia-400/35 bg-fuchsia-500/10 px-2 py-2 text-[11px] font-black text-fuchsia-200"
          >
            <Zap className="h-3.5 w-3.5" /> Puzzle rush
            <span className="rounded bg-fuchsia-400/20 px-1 font-mono text-[9px] text-fuchsia-100">best {rushBest}</span>
          </button>
        </div>
      </section>

      {dailyPuzzle && (
        <section className={`glass-card p-3 ${dailyDone ? 'border-emerald-500/25' : 'border-amber-500/25'}`}>
          <div className="flex items-center justify-between gap-2">
            <div className={`flex items-center gap-1.5 text-xs font-bold ${dailyDone ? 'text-emerald-200' : 'text-amber-200'}`}>
              <CalendarDays className="h-4 w-4" /> Daily puzzle
            </div>
            <span className={`rounded-full border px-2 py-0.5 text-[9px] font-bold ${
              dailyDone ? 'border-emerald-400/30 bg-emerald-500/10 text-emerald-200' : 'border-slate-700 bg-slate-800/70 text-slate-400'
            }`}>
              {dailyDone ? 'Done today' : 'Fresh every day'}
            </span>
          </div>
          <div className="mt-1.5 flex items-center justify-between gap-2">
            <div className="min-w-0">
              <div className="font-mono text-[11px] font-bold text-slate-100">
                {dailyPuzzle.moveNumber}{dailyPuzzle.color === 'w' ? '.' : '…'} {dailyPuzzle.san}
                <span className="ml-1 text-slate-500">· {dailyPuzzle.openingEco}</span>
              </div>
              <div className="truncate text-[10px] text-slate-500">{dailyPuzzle.openingName}</div>
            </div>
            <button
              type="button"
              onClick={() => selectPuzzle(dailyPuzzle, { scroll: true })}
              className="inline-flex shrink-0 items-center gap-1 rounded-xl border border-amber-500/35 bg-amber-500/15 px-3 py-2 text-[11px] font-black text-amber-200"
            >
              {dailyDone ? <RotateCcw className="h-3 w-3" /> : <Play className="h-3 w-3" />}
              {dailyDone ? 'Replay' : 'Solve'}
            </button>
          </div>
        </section>
      )}

      <div className="grid items-start gap-3 lg:grid-cols-[minmax(0,1fr)_minmax(400px,480px)]">
        <section className="min-w-0">
          <div className="mx-auto w-full lg:max-w-[calc(100dvh-20rem)]">
            {selected ? (
              <>
                <div className="mb-1.5 flex items-center justify-between gap-2 rounded-xl border border-slate-800 bg-slate-900/75 px-2.5 py-1.5">
                  <div className="flex min-w-0 items-center gap-2">
                    <span className={`h-2.5 w-2.5 shrink-0 rounded-full border ${selected.color === 'w' ? 'border-slate-300 bg-white' : 'border-slate-500 bg-slate-950'}`} />
                    <span className="truncate text-[11px] font-bold text-slate-200">{selected.playerName}</span>
                    <span className="text-[10px] text-slate-500">to move</span>
                  </div>
                  <span className="shrink-0 font-mono text-[10px] text-slate-500">{selected.evalBefore.display}</span>
                </div>

                <div className="relative flex items-stretch gap-1.5">
                  <div className="relative w-6 shrink-0 overflow-hidden rounded-lg border border-slate-700/80 bg-slate-900">
                    <div className="absolute inset-x-0 bottom-0 bg-slate-100 transition-all duration-300" style={{ height: `${Math.max(3, Math.min(97, selected.evalBefore.winPercentWhite))}%` }} />
                  </div>
                  <div className="relative min-w-0 flex-1" ref={boardRef}>
                    <ChessgroundBoard
                      fen={fen || selected.beforeFen}
                      orientation={selected.color}
                      interactive={interactive}
                      turnColor={selected.color}
                      lastMove={lastMove ?? undefined}
                      bestMoveUci={status === 'revealed' ? selected.bestMoveUci : undefined}
                      showBestArrow={status === 'revealed'}
                      showPlayedArrow={false}
                      theme={boardTheme}
                      onUserMove={handleMove}
                    />
                    {status === 'evaluating' && (
                      <div className="absolute inset-0 z-30 flex items-center justify-center rounded-xl bg-slate-950/45 backdrop-blur-[2px]">
                        <span className="inline-flex items-center gap-1.5 rounded-full border border-cyan-400/30 bg-slate-950/85 px-3 py-1.5 text-[11px] font-bold text-cyan-200">
                          <Loader2 className="h-3.5 w-3.5 animate-spin" /> checking…
                        </span>
                      </div>
                    )}
                    {pendingPromo && (
                      <div className="absolute inset-0 z-40 flex items-center justify-center rounded-xl bg-slate-950/75 backdrop-blur-sm">
                        <div className="flex gap-2 rounded-2xl border border-slate-700 bg-slate-900 p-3">
                          {(['q', 'r', 'b', 'n'] as PieceSymbol[]).map((p) => (
                            <button
                              key={p}
                              type="button"
                              onClick={() => { const promo = pendingPromo; setPendingPromo(null); void attemptMove(promo.from, promo.to, p); }}
                              className="h-11 w-11 rounded-xl border border-slate-700 bg-slate-800 text-lg text-white"
                            >
                              {p === 'q' ? '♕' : p === 'r' ? '♖' : p === 'b' ? '♗' : '♘'}
                            </button>
                          ))}
                        </div>
                      </div>
                    )}
                  </div>
                </div>

                <div className="mt-1.5 grid grid-cols-3 gap-1.5 lg:hidden">
                  {status !== 'solved' && status !== 'revealed' ? (
                    <>
                      <button
                        type="button"
                        onClick={() => setHintLevel((h) => Math.min(2, h + 1))}
                        className="inline-flex items-center justify-center gap-1 rounded-xl border border-slate-700 bg-slate-900/85 px-2 py-2.5 text-[11px] font-bold text-slate-200 active:bg-slate-800"
                      >
                        <Lightbulb className="h-3.5 w-3.5 text-amber-400" /> Hint {hintLevel > 0 ? `${hintLevel}/2` : ''}
                      </button>
                      <button
                        type="button"
                        onClick={revealSolution}
                        className="inline-flex items-center justify-center gap-1 rounded-xl border border-rose-500/30 bg-rose-500/10 px-2 py-2.5 text-[11px] font-bold text-rose-200 active:bg-rose-500/20"
                      >
                        Solution
                      </button>
                    </>
                  ) : (
                    <button
                      type="button"
                      onClick={() => selectPuzzle(selected)}
                      className="inline-flex items-center justify-center gap-1 rounded-xl border border-slate-700 bg-slate-900/85 px-2 py-2.5 text-[11px] font-bold text-slate-200 active:bg-slate-800"
                    >
                      <RotateCcw className="h-3.5 w-3.5" /> Retry
                    </button>
                  )}
                  <button
                    type="button"
                    onClick={chooseNext}
                    className="inline-flex items-center justify-center gap-1 rounded-xl border border-cyan-500/35 bg-cyan-500/15 px-2 py-2.5 text-[11px] font-black text-cyan-200 active:bg-cyan-500/25"
                  >
                    Next <ArrowRight className="h-3.5 w-3.5" />
                  </button>
                </div>

                {hintLevel > 0 && status !== 'solved' && status !== 'revealed' && (
                  <div className="mt-1.5 space-y-0.5 rounded-xl border border-amber-500/20 bg-amber-500/5 px-2.5 py-2 text-[10px] text-amber-100 lg:hidden">
                    <p><strong>Hint 1:</strong> {selected.tacticalTag} — look for a {hintedPiece ? PIECE_NAMES[hintedPiece] : 'piece'} move.</p>
                    {hintLevel > 1 && <p><strong>Hint 2:</strong> The move starts on {uciToSquares(selected.bestMoveUci)?.from ?? 'the key square'} and is worth {selected.winLoss.toFixed(0)}% of win equity.</p>}
                  </div>
                )}

                <div className="mt-1.5 flex items-center justify-between gap-2 rounded-xl border border-slate-800 bg-slate-900/75 px-2.5 py-1.5">
                  <span className="truncate text-[10px] text-slate-400">{selected.openingEco ? `${selected.openingEco} · ` : ''}{selected.openingName}</span>
                  <button type="button" onClick={() => onOpenGame(selected.gameId, selected.ply)} className="shrink-0 text-[10px] font-bold text-cyan-300">Open full review →</button>
                </div>
              </>
            ) : null}
          </div>
        </section>

        <aside className="min-w-0 space-y-2.5 lg:sticky lg:top-[4.75rem] lg:max-h-[calc(100dvh-5.5rem)] lg:overflow-y-auto lg:pr-1 nice-scroll">
          {selected && (
            <div className={`glass-card p-3.5 ${status === 'solved' ? 'border-emerald-500/40' : 'border-amber-500/25'}`}>
              <div className="flex flex-wrap items-center gap-1.5">
                <ClassificationBadge classification={selected.classification} showLabel />
                <span className="font-mono text-xs font-bold text-slate-200">Puzzle {selected.moveNumber}{selected.color === 'w' ? '.' : '…'}</span>
                <span className={`text-[10px] font-bold ${classificationTone[selected.classification]}`}>You played {selected.san}</span>
                <span className="ml-auto text-[9px] text-slate-500">{progress[selected.id]?.attempts ?? 0} tries</span>
              </div>

              {status === 'solved' ? (
                <div className="mt-2 flex items-start gap-2 rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-2.5">
                  <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-300" />
                  <div>
                    <div className="text-xs font-bold text-emerald-200">Puzzle mastered!</div>
                    <p className="mt-0.5 text-[11px] leading-relaxed text-emerald-100/90">{feedback}</p>
                  </div>
                </div>
              ) : status === 'revealed' ? (
                <div className="mt-2 rounded-xl border border-amber-500/30 bg-amber-500/10 p-2.5">
                  <div className="text-xs font-bold text-amber-200">Solution revealed</div>
                  <p className="mt-0.5 text-[11px] leading-relaxed text-amber-100/90">{feedback}</p>
                </div>
              ) : (
                <div className="mt-2 rounded-xl border border-slate-800 bg-slate-950/40 p-2.5">
                  <div className="text-xs font-bold text-slate-100">Find the best move for {selected.color === 'w' ? 'White' : 'Black'}.</div>
                  <p className="mt-0.5 text-[11px] leading-relaxed text-slate-400">
                    You played <span className="font-mono font-bold text-orange-300">{selected.san}</span> here and the eval fell from {selected.evalBefore.display} to {selected.evalAfter.display}. There is a much stronger idea.
                  </p>
                  {feedback && <p className={`mt-1.5 text-[11px] font-semibold ${status === 'wrong' ? 'text-orange-300' : 'text-slate-300'}`}>{feedback}</p>}
                </div>
              )}

              <div className="mt-2 flex flex-wrap gap-1.5">
                {status !== 'solved' && status !== 'revealed' && (
                  <button
                    type="button"
                    onClick={() => setHintLevel((h) => Math.min(2, h + 1))}
                    className="inline-flex items-center gap-1 rounded-lg border border-slate-700 bg-slate-800/80 px-2.5 py-1.5 text-[11px] font-semibold text-slate-200"
                  >
                    <Lightbulb className="h-3.5 w-3.5 text-amber-400" /> Hint {hintLevel > 0 ? `(${hintLevel}/2)` : ''}
                  </button>
                )}
                {status !== 'solved' && status !== 'revealed' && (
                  <button type="button" onClick={revealSolution} className="rounded-lg border border-rose-500/30 bg-rose-500/10 px-2.5 py-1.5 text-[11px] font-semibold text-rose-200">
                    Show solution
                  </button>
                )}
                <button type="button" onClick={() => selectPuzzle(selected)} className="inline-flex items-center gap-1 rounded-lg border border-slate-700 bg-slate-800/80 px-2.5 py-1.5 text-[11px] font-semibold text-slate-300">
                  <RotateCcw className="h-3 w-3" /> Reset
                </button>
                <button type="button" onClick={chooseNext} className="ml-auto inline-flex items-center gap-1 rounded-lg border border-cyan-500/35 bg-cyan-500/15 px-2.5 py-1.5 text-[11px] font-bold text-cyan-200">
                  Next puzzle <ArrowRight className="h-3 w-3" />
                </button>
              </div>

              {hintLevel > 0 && status !== 'solved' && status !== 'revealed' && (
                <div className="mt-2 space-y-1 rounded-xl border border-amber-500/20 bg-amber-500/5 p-2 text-[11px] text-amber-100">
                  <p><strong>Hint 1:</strong> {selected.tacticalTag} — look for a {hintedPiece ? PIECE_NAMES[hintedPiece] : 'piece'} move.</p>
                  {hintLevel > 1 && <p><strong>Hint 2:</strong> The move starts on {uciToSquares(selected.bestMoveUci)?.from ?? 'the key square'} and is worth {selected.winLoss.toFixed(0)}% of win equity.</p>}
                </div>
              )}
            </div>
          )}

          <div className="glass-card overflow-hidden">
            <div className="flex items-center justify-between gap-2 p-3 pb-2">
              <span className="text-[11px] font-black uppercase tracking-[0.14em] text-slate-300">Deck</span>
              <div className="inline-flex rounded-lg border border-slate-800 bg-slate-950/60 p-0.5">
                {([['unsolved', 'To do'], ['all', 'All'], ['mastered', 'Done']] as Array<[DeckFilter, string]>).map(([key, label]) => (
                  <button
                    key={key}
                    type="button"
                    onClick={() => setFilter(key)}
                    className={`rounded px-2 py-1 text-[9px] font-bold ${filter === key ? 'bg-cyan-500/20 text-cyan-200' : 'text-slate-400'}`}
                  >
                    {label}
                  </button>
                ))}
              </div>
            </div>
            <div className="flex flex-wrap gap-1 px-2 pb-2">
              {([['all', 'All phases'], ['opening', 'Opening'], ['middlegame', 'Middlegame'], ['endgame', 'Endgame']] as Array<[DeckPhaseFilter, string]>).map(([key, label]) => (
                <button
                  key={key}
                  type="button"
                  onClick={() => setPhaseFilter(key)}
                  className={`rounded-full border px-2 py-0.5 text-[9px] font-bold transition ${
                    phaseFilter === key
                      ? 'border-amber-400/40 bg-amber-500/15 text-amber-200'
                      : 'border-slate-800 bg-slate-950/50 text-slate-400'
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
            <div className="max-h-72 space-y-1 overflow-y-auto px-2 pb-2 nice-scroll">
              {filteredDeck.length === 0 && <p className="px-2 py-4 text-center text-[11px] text-slate-500">No puzzles in this filter.</p>}
              {filteredDeck.map((puzzle) => {
                const solved = Boolean(progress[puzzle.id]?.solved);
                const active = puzzle.id === selectedId;
                return (
                  <button
                    key={puzzle.id}
                    type="button"
                    onClick={() => selectPuzzle(puzzle)}
                    className={`flex w-full items-center gap-2 rounded-xl border px-2 py-1.5 text-left text-[11px] transition ${
                      active ? 'border-cyan-400/50 bg-cyan-500/15' : 'border-transparent hover:border-slate-700 hover:bg-slate-800/50'
                    }`}
                  >
                    <span className={`inline-flex h-4 min-w-[20px] items-center justify-center rounded px-1 text-[9px] font-black ${puzzle.classification === 'blunder' ? 'bg-red-500/20 text-red-300' : puzzle.classification === 'mistake' ? 'bg-orange-500/20 text-orange-300' : 'bg-yellow-500/20 text-yellow-300'}`}>
                      {puzzle.classification === 'blunder' ? '??' : puzzle.classification === 'mistake' ? '?' : '?!'}
                    </span>
                    <span className="font-mono text-slate-300">{puzzle.moveNumber}{puzzle.color === 'w' ? '.' : '…'} {puzzle.san}</span>
                    <span className="min-w-0 flex-1 truncate text-[10px] text-slate-500">{puzzle.openingEco} {puzzle.openingName}</span>
                    {solved ? <CheckCircle2 className="h-3.5 w-3.5 shrink-0 text-emerald-400" /> : <span className="h-3.5 w-3.5 shrink-0 rounded-full border border-slate-600" />}
                  </button>
                );
              })}
            </div>
          </div>

          <p className="px-1 text-[10px] leading-relaxed text-slate-500">
            Drill until each pattern is automatic. Solved puzzles stay mastered; “Show solution” does not mark a puzzle complete.
          </p>
        </aside>
      </div>

      {celebration && (
        <AlienCelebration
          key={celebration.trigger}
          kind="brilliant"
          trigger={celebration.trigger}
          message={celebration.message}
          onDismiss={() => setCelebration(null)}
        />
      )}
    </div>
  );
};
