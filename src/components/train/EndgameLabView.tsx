import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Chess, type PieceSymbol, type Square } from 'chess.js';
import {
  AlertTriangle,
  CheckCircle2,
  Compass,
  ExternalLink,
  Lightbulb,
  Loader2,
  RotateCcw,
  ShieldCheck,
  Sparkles,
  Undo2,
} from 'lucide-react';
import type { AnalyzedGame, BoardThemeId } from '../../types/chess';
import {
  extractUserEndgameDrills,
  THEORETICAL_ENDGAME_DRILLS,
  type EndgameDrill,
  type EndgameLabCategory,
} from '../../data/endgameDrills';
import {
  fetchLichessTablebase,
  formatTablebaseWdl,
  isTablebaseEligible,
  type TablebaseResult,
} from '../../services/tablebaseApi';
import { stockfishService } from '../../engine/StockfishService';
import { getPref, setPref } from '../../storage/gameDb';
import { soundManager } from '../../utils/sound';
import { uciToSquares } from '../../utils/chessMath';
import type { UserHandleSpec } from '../../utils/player';
import { ChessgroundBoard } from '../ChessgroundBoard';

interface Props {
  analyzedGames: AnalyzedGame[];
  username: UserHandleSpec;
  boardTheme: BoardThemeId;
  initialCategory?: EndgameLabCategory | 'All' | 'My Slips' | null;
  onOpenGame: (gameId: string, ply: number) => void;
}

const MASTERED_PREF_KEY = 'brillyder_endgame_mastered_v1';
const CATEGORY_FILTERS: Array<'All' | 'My Slips' | EndgameLabCategory> = [
  'All',
  'My Slips',
  'Pawn',
  'Rook',
  'Minor Piece',
  'Queen',
  'Rook+Minor',
];

function isWinningTbForUser(tb: TablebaseResult, sideToMove: 'w' | 'b', userColor: 'w' | 'b'): boolean {
  const userToMove = sideToMove === userColor;
  if (userToMove) return tb.category === 'win' || tb.category === 'maybe-win';
  return tb.category === 'loss' || tb.category === 'maybe-loss';
}

function isLosingTbForUser(tb: TablebaseResult, sideToMove: 'w' | 'b', userColor: 'w' | 'b'): boolean {
  const userToMove = sideToMove === userColor;
  if (userToMove) return tb.category === 'loss' || tb.category === 'maybe-loss';
  return tb.category === 'win' || tb.category === 'maybe-win';
}

export const EndgameLabView: React.FC<Props> = ({
  analyzedGames,
  username,
  boardTheme,
  initialCategory = null,
  onOpenGame,
}) => {
  const userDrills = useMemo(
    () => extractUserEndgameDrills(analyzedGames, username, 10),
    [analyzedGames, username]
  );
  const allDrills = useMemo(
    () => [...userDrills, ...THEORETICAL_ENDGAME_DRILLS],
    [userDrills]
  );

  const [category, setCategory] = useState<'All' | 'My Slips' | EndgameLabCategory>(
    initialCategory ?? 'All'
  );
  const [masteredIds, setMasteredIds] = useState<string[]>(() =>
    getPref<string[]>(MASTERED_PREF_KEY, [])
  );

  useEffect(() => {
    if (initialCategory) setCategory(initialCategory);
  }, [initialCategory]);

  const filteredDrills = useMemo(() => {
    if (category === 'All') return allDrills;
    if (category === 'My Slips') return userDrills;
    return allDrills.filter((d) => d.category === category);
  }, [allDrills, userDrills, category]);

  const [selectedId, setSelectedId] = useState<string>(
    () => filteredDrills[0]?.id ?? THEORETICAL_ENDGAME_DRILLS[0].id
  );

  useEffect(() => {
    if (filteredDrills.length > 0 && !filteredDrills.some((d) => d.id === selectedId)) {
      setSelectedId(filteredDrills[0].id);
    }
  }, [filteredDrills, selectedId]);

  const activeDrill: EndgameDrill =
    allDrills.find((d) => d.id === selectedId) ?? THEORETICAL_ENDGAME_DRILLS[0];

  const [fen, setFen] = useState(activeDrill.fen);
  const [historyFens, setHistoryFens] = useState<string[]>([activeDrill.fen]);
  const [lastMove, setLastMove] = useState<[string, string] | undefined>(undefined);
  const [thinking, setThinking] = useState(false);
  const [status, setStatus] = useState<'playing' | 'warning' | 'mastered'>('playing');
  const [statusNote, setStatusNote] = useState(activeDrill.keyIdea);
  const [tbResult, setTbResult] = useState<TablebaseResult | null>(null);
  const [tbLoading, setTbLoading] = useState(false);
  const [showHint, setShowHint] = useState(false);
  const [userMovesMade, setUserMovesMade] = useState(0);
  const [pendingPromo, setPendingPromo] = useState<{ from: Square; to: Square } | null>(null);

  const runRef = useRef(0);
  const abortRef = useRef<AbortController | null>(null);

  const markMastered = (id: string) => {
    setMasteredIds((prev) => {
      if (prev.includes(id)) return prev;
      const next = [...prev, id];
      setPref(MASTERED_PREF_KEY, next);
      return next;
    });
  };

  const resetDrill = (drill: EndgameDrill) => {
    runRef.current += 1;
    abortRef.current?.abort();
    abortRef.current = null;
    setFen(drill.fen);
    setHistoryFens([drill.fen]);
    setLastMove(undefined);
    setThinking(false);
    setStatus('playing');
    setStatusNote(drill.keyIdea);
    setShowHint(false);
    setUserMovesMade(0);
    setPendingPromo(null);
  };

  useEffect(() => {
    resetDrill(activeDrill);
  }, [activeDrill.id]);

  useEffect(() => {
    return () => {
      runRef.current += 1;
      abortRef.current?.abort();
    };
  }, []);

  // Live Syzygy 7-piece query on every board position
  useEffect(() => {
    let cancelled = false;
    if (!isTablebaseEligible(fen)) {
      setTbResult(null);
      setTbLoading(false);
      return;
    }
    setTbLoading(true);
    void fetchLichessTablebase(fen).then((res) => {
      if (cancelled) return;
      setTbResult(res);
      setTbLoading(false);
    });
    return () => {
      cancelled = true;
    };
  }, [fen]);

  const hintArrow = useMemo(() => {
    if (!showHint) return [];
    const tbBest = tbResult?.moves?.[0]?.uci;
    if (tbBest) {
      const sq = uciToSquares(tbBest);
      if (sq) return [{ from: sq.from, to: sq.to, color: 'best' as const }];
    }
    if (fen === activeDrill.fen) {
      try {
        const c = new Chess(fen);
        const mv = c.move(activeDrill.firstHintSan);
        if (mv) return [{ from: mv.from, to: mv.to, color: 'best' as const }];
      } catch {
        // ignore
      }
    }
    return [];
  }, [showHint, tbResult, fen, activeDrill]);

  const completeMove = async (from: Square, to: Square, promotion?: PieceSymbol) => {
    const chess = new Chess(fen);
    if (chess.turn() !== activeDrill.userColor || chess.isGameOver()) return;

    const move = chess.move({ from, to, promotion });
    if (!move) return;

    const runId = ++runRef.current;
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    const afterUserFen = chess.fen();
    const nextUserMoves = userMovesMade + 1;
    setFen(afterUserFen);
    setHistoryFens((prev) => [...prev, afterUserFen]);
    setLastMove([move.from, move.to]);
    setShowHint(false);
    setUserMovesMade(nextUserMoves);
    if (chess.inCheck()) soundManager.playCheck();
    else if (move.captured) soundManager.playCapture();
    else soundManager.playMove();

    // Immediate terminal outcomes
    if (chess.isCheckmate()) {
      if (activeDrill.goal === 'win') {
        setStatus('mastered');
        setStatusNote('Checkmate! Endgame converted cleanly.');
        markMastered(activeDrill.id);
        soundManager.playBrilliantChord();
      } else {
        setStatus('mastered');
        setStatusNote('Checkmate delivered — even better than a draw!');
        markMastered(activeDrill.id);
        soundManager.playBrilliantChord();
      }
      return;
    }

    if (chess.isDraw()) {
      if (activeDrill.goal === 'draw') {
        setStatus('mastered');
        setStatusNote('Draw locked in — textbook defensive technique!');
        markMastered(activeDrill.id);
        soundManager.playBrilliantChord();
      } else {
        setStatus('warning');
        setStatusNote('Position ended in a draw — tap Undo to keep the win alive.');
        soundManager.playHullThud();
      }
      return;
    }

    setThinking(true);
    try {
      // Grade user's move via Syzygy if <=7 pieces, otherwise Stockfish
      let droppedGoal = false;
      let sealedWin = false;
      let sealedDraw = false;
      let tbReplyUci: string | null = null;

      const tbAfter = isTablebaseEligible(afterUserFen)
        ? await fetchLichessTablebase(afterUserFen)
        : null;
      if (runRef.current !== runId) return;

      if (tbAfter) {
        const oppTurn = chess.turn();
        const stillWinning = isWinningTbForUser(tbAfter, oppTurn, activeDrill.userColor);
        const nowLosing = isLosingTbForUser(tbAfter, oppTurn, activeDrill.userColor);

        if (activeDrill.goal === 'win' && !stillWinning) {
          droppedGoal = true;
        } else if (activeDrill.goal === 'draw' && nowLosing) {
          droppedGoal = true;
        } else if (activeDrill.goal === 'draw' && !nowLosing && nextUserMoves >= 6) {
          sealedDraw = true;
        } else if (
          activeDrill.goal === 'win' &&
          stillWinning &&
          Boolean(move.promotion) &&
          nextUserMoves >= 3
        ) {
          sealedWin = true;
        }

        // Syzygy optimal defender move makes endgame practice razor-sharp
        if (tbAfter.moves.length > 0) {
          tbReplyUci = tbAfter.moves[0].uci;
        }
      } else {
        const ev = await stockfishService.analyzePosition(afterUserFen, {
          depth: 12,
          multiPv: 1,
          timeoutMs: 8000,
          signal: controller.signal,
        });
        if (runRef.current !== runId) return;
        const userCp = activeDrill.userColor === 'w' ? ev.score.cpWhite : -ev.score.cpWhite;
        const userMate =
          ev.score.mateWhite !== null
            ? activeDrill.userColor === 'w'
              ? ev.score.mateWhite
              : -ev.score.mateWhite
            : null;
        if (activeDrill.goal === 'win' && userCp < 120 && (userMate === null || userMate <= 0)) {
          droppedGoal = true;
        } else if (activeDrill.goal === 'draw' && (userCp < -180 || (userMate !== null && userMate < 0))) {
          droppedGoal = true;
        } else if (activeDrill.goal === 'win' && (userCp >= 850 || (userMate !== null && userMate > 0 && userMate <= 4)) && nextUserMoves >= 4) {
          sealedWin = true;
        } else if (activeDrill.goal === 'draw' && userCp >= -60 && nextUserMoves >= 6) {
          sealedDraw = true;
        }
      }

      if (droppedGoal) {
        setThinking(false);
        setStatus('warning');
        setStatusNote(
          activeDrill.goal === 'win'
            ? `Careful — ${move.san} lets the win slip according to the tablebase/engine. Undo and try a stronger move.`
            : `Careful — ${move.san} loses the fortress. Undo and keep the defense tight.`
        );
        soundManager.playHullThud();
        return;
      }

      if (sealedWin) {
        setThinking(false);
        setStatus('mastered');
        setStatusNote('Decisive winning conversion reached — Endgame mastered!');
        markMastered(activeDrill.id);
        soundManager.playBrilliantChord();
        return;
      }

      if (sealedDraw) {
        setThinking(false);
        setStatus('mastered');
        setStatusNote('6 accurate defensive moves in a row — Fortress held!');
        markMastered(activeDrill.id);
        soundManager.playBrilliantChord();
        return;
      }

      // Opponent reply: use Syzygy toughest defense if available, else Stockfish
      const replyUci =
        tbReplyUci ??
        (await stockfishService.getBotMove(afterUserFen, activeDrill.botElo, controller.signal));
      if (runRef.current !== runId) return;

      const parsed = uciToSquares(replyUci);
      if (!parsed) {
        setThinking(false);
        return;
      }
      const replyChess = new Chess(afterUserFen);
      const replyMv = replyChess.move({
        from: parsed.from,
        to: parsed.to,
        promotion: parsed.promotion ?? 'q',
      });
      if (!replyMv) {
        setThinking(false);
        return;
      }
      const afterReplyFen = replyChess.fen();
      setFen(afterReplyFen);
      setHistoryFens((prev) => [...prev, afterReplyFen]);
      setLastMove([replyMv.from, replyMv.to]);
      if (replyChess.inCheck()) soundManager.playCheck();
      else if (replyMv.captured) soundManager.playCapture();
      else soundManager.playMove();

      if (replyChess.isDraw()) {
        setStatus(activeDrill.goal === 'draw' ? 'mastered' : 'warning');
        setStatusNote(
          activeDrill.goal === 'draw'
            ? 'Draw achieved — fortress held!'
            : 'Opponent forced a draw — tap Undo to find the winning path.'
        );
        if (activeDrill.goal === 'draw') markMastered(activeDrill.id);
      } else if (replyChess.isCheckmate()) {
        setStatus('warning');
        setStatusNote('Opponent delivered checkmate — tap Undo or Reset to retry.');
      } else {
        setStatus('playing');
        setStatusNote(`Opponent replied ${replyMv.san}. Keep going — ${activeDrill.goal === 'win' ? 'convert the win.' : 'hold the draw.'}`);
      }
    } catch {
      if (runRef.current !== runId) return;
    } finally {
      if (runRef.current === runId) setThinking(false);
    }
  };

  const handleUserMove = (from: Square, to: Square) => {
    if (thinking || status === 'mastered') return;
    const chess = new Chess(fen);
    if (chess.turn() !== activeDrill.userColor) return;
    const piece = chess.get(from);
    const isPromo =
      piece?.type === 'p' &&
      ((piece.color === 'w' && to[1] === '8') || (piece.color === 'b' && to[1] === '1'));
    if (isPromo) {
      setPendingPromo({ from, to });
      return;
    }
    void completeMove(from, to);
  };

  const handleUndo = () => {
    if (historyFens.length <= 1) return;
    runRef.current += 1;
    abortRef.current?.abort();
    setThinking(false);
    setPendingPromo(null);
    // Step back to the most recent user-to-move position
    let idx = historyFens.length - 2;
    while (idx > 0) {
      try {
        if (new Chess(historyFens[idx]).turn() === activeDrill.userColor) break;
      } catch {
        break;
      }
      idx--;
    }
    const targetFen = historyFens[idx];
    setHistoryFens(historyFens.slice(0, idx + 1));
    setFen(targetFen);
    setLastMove(undefined);
    setStatus('playing');
    setStatusNote('Stepped back — find the accurate continuation.');
  };

  const sideToMove = useMemo(() => {
    try {
      return new Chess(fen).turn();
    } catch {
      return activeDrill.userColor;
    }
  }, [fen, activeDrill.userColor]);

  const wdlBadge = tbResult ? formatTablebaseWdl(tbResult.category, sideToMove) : null;
  const masteredCount = allDrills.filter((d) => masteredIds.includes(d.id)).length;

  return (
    <div className="space-y-3">
      {/* Header & Category Filter */}
      <div className="glass-card p-3.5">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <Compass className="h-4 w-4 text-brilly" />
              <span className="text-xs font-black uppercase tracking-[0.14em] text-brilly">
                Syzygy Endgame Lab
              </span>
              <span className="rounded-full border border-teal-400/30 bg-teal-400/10 px-2 py-0.5 font-mono text-[10px] font-bold text-teal-200">
                {masteredCount}/{allDrills.length} mastered
              </span>
            </div>
            <p className="mt-0.5 text-[11px] text-slate-400">
              Practice essential 7-piece endgames + your own analyzed endgame slips with exact Syzygy tablebase feedback.
            </p>
          </div>
        </div>

        <div className="mt-2.5 flex flex-wrap gap-1.5">
          {CATEGORY_FILTERS.map((cat) => {
            const count =
              cat === 'All'
                ? allDrills.length
                : cat === 'My Slips'
                ? userDrills.length
                : allDrills.filter((d) => d.category === cat).length;
            return (
              <button
                key={cat}
                type="button"
                disabled={cat === 'My Slips' && userDrills.length === 0}
                onClick={() => setCategory(cat)}
                className={`rounded-lg border px-2.5 py-1 text-[10px] font-bold transition disabled:opacity-40 ${
                  category === cat
                    ? 'border-teal-400/50 bg-teal-400/15 text-teal-200'
                    : 'border-slate-800 bg-void/60 text-slate-400 hover:border-slate-600'
                }`}
              >
                {cat} <span className="font-mono opacity-75">({count})</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Main Board + Coaching Panel */}
      <div className="grid grid-cols-1 gap-3 lg:grid-cols-[minmax(0,400px)_minmax(0,1fr)]">
        <div className="min-w-0 glass-card p-3">
          <div className="mb-2 flex items-center justify-between gap-2 text-[11px]">
            <div className="min-w-0">
              <div className="truncate font-bold text-slate-100">{activeDrill.title}</div>
              <div className="flex flex-wrap items-center gap-1.5 text-[10px] text-slate-400">
                <span className="rounded bg-slate-800 px-1.5 py-0.5 font-bold text-slate-300">
                  {activeDrill.category}
                </span>
                <span
                  className={`rounded px-1.5 py-0.5 font-black uppercase ${
                    activeDrill.goal === 'win'
                      ? 'bg-emerald-500/15 text-emerald-300'
                      : 'bg-cyan-500/15 text-cyan-200'
                  }`}
                >
                  Goal: {activeDrill.goal === 'win' ? 'Win' : 'Hold Draw'}
                </span>
                <span>Play as {activeDrill.userColor === 'w' ? 'White' : 'Black'}</span>
              </div>
            </div>
            {masteredIds.includes(activeDrill.id) && (
              <ShieldCheck className="h-4 w-4 shrink-0 text-emerald-400" aria-label="Mastered" />
            )}
          </div>

          <div className="relative mx-auto w-full max-w-[min(100%,calc(100dvh-21rem))] lg:max-w-none">
            <ChessgroundBoard
              fen={fen}
              orientation={activeDrill.userColor}
              interactive={!thinking && status !== 'mastered'}
              lastMove={lastMove}
              customArrows={hintArrow}
              theme={boardTheme}
              onUserMove={handleUserMove}
            />
            {pendingPromo && (
              <div className="absolute inset-0 z-30 flex items-center justify-center rounded-xl bg-void/80 backdrop-blur-sm">
                <div className="rounded-2xl border border-teal-400/40 bg-hull p-3 shadow-2xl">
                  <div className="mb-2 text-center text-[10px] font-black uppercase tracking-wider text-brilly">
                    Promote Pawn
                  </div>
                  <div className="flex items-center gap-1.5">
                    {(['q', 'r', 'b', 'n'] as PieceSymbol[]).map((p) => (
                      <button
                        key={p}
                        type="button"
                        onClick={() => {
                          const req = pendingPromo;
                          setPendingPromo(null);
                          void completeMove(req.from, req.to, p);
                        }}
                        className="rounded-xl border border-slate-700 bg-void px-3 py-2 font-mono text-sm font-black uppercase text-slate-100 hover:border-teal-400 hover:text-brilly"
                      >
                        {p}
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            )}
          </div>

          {/* Live Syzygy + Action Strip */}
          <div className="mt-2.5 flex flex-wrap items-center justify-between gap-1.5">
            <div className="flex items-center gap-1.5 text-[10px]">
              {tbLoading ? (
                <span className="inline-flex items-center gap-1 text-slate-400">
                  <Loader2 className="h-3 w-3 animate-spin" /> Syzygy…
                </span>
              ) : wdlBadge ? (
                <span
                  className={`rounded-full border px-2 py-0.5 font-mono font-bold ${
                    wdlBadge.tone === 'win'
                      ? 'border-emerald-400/40 bg-emerald-500/15 text-emerald-200'
                      : wdlBadge.tone === 'loss'
                      ? 'border-rose-400/40 bg-rose-500/15 text-rose-200'
                      : 'border-cyan-400/40 bg-cyan-500/15 text-cyan-200'
                  }`}
                >
                  {wdlBadge.label}
                  {tbResult?.dtz !== null && tbResult?.dtz !== undefined
                    ? ` · DTZ ${Math.abs(tbResult.dtz)}`
                    : ''}
                </span>
              ) : (
                <span className="text-slate-500">Stockfish offline grading</span>
              )}
            </div>

            <div className="flex items-center gap-1">
              <button
                type="button"
                onClick={() => setShowHint((v) => !v)}
                className="inline-flex items-center gap-1 rounded-lg border border-amber-400/35 bg-amber-500/10 px-2 py-1 text-[10px] font-bold text-amber-200 hover:bg-amber-500/20"
              >
                <Lightbulb className="h-3 w-3" /> Hint
              </button>
              <button
                type="button"
                onClick={handleUndo}
                disabled={historyFens.length <= 1}
                className="inline-flex items-center gap-1 rounded-lg border border-slate-700 bg-void/70 px-2 py-1 text-[10px] font-bold text-slate-300 hover:border-slate-500 disabled:opacity-40"
              >
                <Undo2 className="h-3 w-3" /> Undo
              </button>
              <button
                type="button"
                onClick={() => resetDrill(activeDrill)}
                className="inline-flex items-center gap-1 rounded-lg border border-slate-700 bg-void/70 px-2 py-1 text-[10px] font-bold text-slate-300 hover:border-slate-500"
              >
                <RotateCcw className="h-3 w-3" /> Reset
              </button>
            </div>
          </div>
        </div>

        {/* Right Panel: Feedback + Drill List */}
        <div className="min-w-0 space-y-3">
          <div
            className={`glass-card p-3.5 ${
              status === 'mastered'
                ? 'border-emerald-400/45 bg-emerald-500/10'
                : status === 'warning'
                ? 'border-rose-400/45 bg-rose-500/10'
                : 'border-teal-400/25'
            }`}
          >
            <div className="flex items-start gap-2">
              {status === 'mastered' ? (
                <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0 text-emerald-300" />
              ) : status === 'warning' ? (
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-rose-300" />
              ) : thinking ? (
                <Loader2 className="mt-0.5 h-4 w-4 shrink-0 animate-spin text-brilly" />
              ) : (
                <Sparkles className="mt-0.5 h-4 w-4 shrink-0 text-brilly" />
              )}
              <div className="min-w-0 flex-1">
                <div className="text-[11px] font-black uppercase tracking-wider text-slate-200">
                  {status === 'mastered'
                    ? 'Endgame Mastered'
                    : status === 'warning'
                    ? 'Technique Slip'
                    : thinking
                    ? 'Syzygy / Stockfish defending…'
                    : 'Key Technique'}
                </div>
                <p className="mt-1 text-xs leading-relaxed text-slate-300">{statusNote}</p>
                {showHint && (
                  <p className="mt-1.5 font-mono text-[11px] text-amber-200">
                    Best move: {tbResult?.moves?.[0]?.san ?? activeDrill.firstHintSan}
                  </p>
                )}
                {activeDrill.source === 'user-game' && activeDrill.sourceGameId && (
                  <button
                    type="button"
                    onClick={() => onOpenGame(activeDrill.sourceGameId!, activeDrill.sourcePly ?? 1)}
                    className="mt-2 inline-flex items-center gap-1 rounded-lg border border-cyan-400/35 bg-cyan-500/10 px-2 py-1 text-[10px] font-bold text-cyan-200 hover:bg-cyan-500/20"
                  >
                    <ExternalLink className="h-3 w-3" /> Open original game
                  </button>
                )}
              </div>
            </div>
          </div>

          <div className="glass-card p-3">
            <div className="mb-2 flex items-center justify-between text-[10px] font-black uppercase tracking-[0.14em] text-slate-400">
              <span>Select Endgame ({filteredDrills.length})</span>
              <span className="font-mono text-slate-500">≤7 pieces · Syzygy</span>
            </div>
            <div className="max-h-72 space-y-1.5 overflow-y-auto pr-0.5 nice-scroll">
              {filteredDrills.map((d) => {
                const isActive = d.id === activeDrill.id;
                const done = masteredIds.includes(d.id);
                return (
                  <button
                    key={d.id}
                    type="button"
                    onClick={() => setSelectedId(d.id)}
                    className={`flex w-full items-center justify-between gap-2 rounded-xl border px-2.5 py-2 text-left transition ${
                      isActive
                        ? 'border-teal-400/50 bg-teal-400/12 text-white'
                        : 'border-slate-800/80 bg-void/50 text-slate-300 hover:border-slate-600'
                    }`}
                  >
                    <div className="min-w-0">
                      <div className="truncate text-[11px] font-bold">{d.title}</div>
                      <div className="mt-0.5 flex items-center gap-1.5 text-[9px] text-slate-500">
                        <span>{d.category}</span>
                        <span>·</span>
                        <span className={d.goal === 'win' ? 'text-emerald-400' : 'text-cyan-300'}>
                          {d.goal === 'win' ? 'Win' : 'Draw'}
                        </span>
                        <span>·</span>
                        <span>{d.source === 'user-game' ? 'Your game' : d.difficulty}</span>
                      </div>
                    </div>
                    {done && <CheckCircle2 className="h-3.5 w-3.5 shrink-0 text-emerald-400" />}
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
