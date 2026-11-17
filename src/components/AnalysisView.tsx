import React, { useEffect, useMemo, useState } from 'react';
import { Chess, type PieceSymbol, type Square } from 'chess.js';
import {
  AlertTriangle,
  ArrowLeft,
  BarChart3,
  Bot,
  ChevronLeft,
  ChevronRight,
  Eye,
  FlipVertical2,
  Lightbulb,
  Play,
  RotateCcw,
  SkipBack,
  SkipForward,
  Sparkles,
  Square as StopIcon,
} from 'lucide-react';
import {
  CLASSIFICATION_META,
  type AnalysisDepthPreset,
  type AnalyzedGame,
  type AnalyzedPly,
  type EngineScore,
  type LichessGameRecord,
  type MoveClassification,
  type PlayBotConfig,
  type PlayerColor,
} from '../types/chess';
import { loadPgnSafely } from '../chess/classification';
import { buildEngineScore, getMaterialBalance, getMoverWinPercent, uciToSquares } from '../utils/chessMath';
import { soundManager } from '../utils/sound';
import { stockfishService } from '../engine/StockfishService';
import { ChessgroundBoard } from './ChessgroundBoard';
import { ClassificationBadge } from './ClassificationBadge';
import { EvalBar } from './EvalBar';
import { EvalGraph } from './EvalGraph';
import { PlayerBar } from './PlayerBar';

interface Props {
  game: LichessGameRecord;
  analyzed: AnalyzedGame | null;
  analyzing: boolean;
  progress: { done: number; total: number } | null;
  depthPreset: AnalysisDepthPreset;
  onDepthPresetChange: (d: AnalysisDepthPreset) => void;
  onStartAnalysis: () => void;
  onCancelAnalysis: () => void;
  onBackToGames: () => void;
  onOpenInsights: () => void;
}

const START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

export const AnalysisView: React.FC<Props> = ({
  game,
  analyzed,
  analyzing,
  progress,
  depthPreset,
  onDepthPresetChange,
  onStartAnalysis,
  onCancelAnalysis,
  onBackToGames,
  onOpenInsights,
}) => {
  const rawMoves = useMemo(() => {
    try { return loadPgnSafely(game.pgn).history({ verbose: true }); } catch { return []; }
  }, [game.pgn]);

  const [currentPlyIndex, setCurrentPlyIndex] = useState(0);
  const [orientation, setOrientation] = useState<PlayerColor>(game.userColor ?? 'w');
  const [showThreat, setShowThreat] = useState(false);
  const [botElo, setBotElo] = useState(1400);
  const [pendingPromo, setPendingPromo] = useState<{ from: Square; to: Square; mode: 'retry' | 'bot' } | null>(null);

  const [retryState, setRetryState] = useState<{
    active: boolean;
    fen: string;
    status: 'prompt' | 'solved' | 'try_again' | 'revealed';
    feedback: string;
  } | null>(null);

  const [botState, setBotState] = useState<
    (PlayBotConfig & { fen: string; lastMove?: [string, string]; thinking: boolean; historyFens: string[]; statusText: string }) | null
  >(null);

  useEffect(() => {
    setCurrentPlyIndex(0);
    setOrientation(game.userColor ?? 'w');
    setRetryState(null);
    setBotState(null);
    setPendingPromo(null);
  }, [game.id, game.userColor]);

  const totalPlies = analyzed ? analyzed.plies.length : rawMoves.length;
  const currentPly: AnalyzedPly | null = analyzed && currentPlyIndex > 0 ? analyzed.plies[currentPlyIndex - 1] ?? null : null;

  const reviewFen = useMemo(() => {
    if (currentPlyIndex === 0) return START_FEN;
    if (analyzed?.plies[currentPlyIndex - 1]) return analyzed.plies[currentPlyIndex - 1].afterFen;
    return rawMoves[currentPlyIndex - 1]?.after ?? START_FEN;
  }, [currentPlyIndex, analyzed, rawMoves]);

  const reviewLastMove = useMemo<[string, string] | undefined>(() => {
    if (currentPlyIndex === 0) return undefined;
    const p = analyzed?.plies[currentPlyIndex - 1] ?? rawMoves[currentPlyIndex - 1];
    return p ? [p.from, p.to] : undefined;
  }, [currentPlyIndex, analyzed, rawMoves]);

  const currentScore: EngineScore = useMemo(() => {
    if (!analyzed) return buildEngineScore(20, null);
    return currentPlyIndex === 0 ? analyzed.initialEval : analyzed.plies[currentPlyIndex - 1]?.evalAfter ?? analyzed.initialEval;
  }, [analyzed, currentPlyIndex]);

  const activeFen = botState ? botState.fen : retryState ? retryState.fen : reviewFen;
  const activeTurn: PlayerColor = activeFen.split(' ')[1] === 'b' ? 'b' : 'w';
  const material = useMemo(() => getMaterialBalance(activeFen), [activeFen]);

  const jumpToPly = (idx: number) => {
    soundManager.unlock();
    const next = Math.max(0, Math.min(totalPlies, idx));
    setRetryState(null); setBotState(null); setPendingPromo(null); setCurrentPlyIndex(next);
    if (next > 0 && analyzed) {
      const p = analyzed.plies[next - 1];
      soundManager.playClassification(p.classification, Boolean(p.captured), p.san.includes('+'));
    } else if (next > 0 && rawMoves[next - 1]) {
      const m = rawMoves[next - 1];
      if (m.san.includes('+')) soundManager.playCheck(); else if (m.captured) soundManager.playCapture(); else soundManager.playMove();
    }
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (botState || retryState) return;
      if (e.key === 'ArrowLeft') jumpToPly(currentPlyIndex - 1);
      else if (e.key === 'ArrowRight') jumpToPly(currentPlyIndex + 1);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [currentPlyIndex, totalPlies, botState, retryState]);

  const jumpToNextMistake = () => {
    if (!analyzed) return;
    const uc = game.userColor ?? orientation;
    const isErr = (c: MoveClassification) => c === 'inaccuracy' || c === 'mistake' || c === 'blunder';
    const target = analyzed.plies.find((p, i) => i + 1 > currentPlyIndex && p.color === uc && isErr(p.classification))
      ?? analyzed.plies.find((p) => p.color === uc && isErr(p.classification))
      ?? analyzed.plies.find((p) => isErr(p.classification));
    if (target) jumpToPly(target.ply);
  };

  const executeRetryMove = async (from: Square, to: Square, promotion?: PieceSymbol) => {
    if (!currentPly) return;
    const c = new Chess(currentPly.beforeFen);
    let mv;
    try { mv = c.move({ from, to, promotion }); } catch { return; }
    const uci = `${mv.from}${mv.to}${mv.promotion ?? ''}`;
    if (uci === currentPly.bestMoveUci) {
      soundManager.playSuccess();
      setRetryState({ active: true, fen: c.fen(), status: 'solved', feedback: `Spot on! ${mv.san} is Stockfish's #1 move.` });
      return;
    }
    setRetryState({ active: true, fen: c.fen(), status: 'prompt', feedback: `Evaluating ${mv.san}...` });
    try {
      const res = await stockfishService.analyzePosition(c.fen(), { depth: 12, multiPv: 1, timeoutMs: 8000 });
      const loss = Math.max(0, getMoverWinPercent(currentPly.evalBefore, currentPly.color) - getMoverWinPercent(res.score, currentPly.color));
      if (loss <= 6) {
        soundManager.playSuccess();
        setRetryState({ active: true, fen: c.fen(), status: 'solved', feedback: `Great alternative! ${mv.san} holds (${res.score.display}). Engine top was ${currentPly.bestMoveSan}.` });
      } else {
        soundManager.playError();
        setRetryState({ active: true, fen: currentPly.beforeFen, status: 'try_again', feedback: `${mv.san} drops ${loss.toFixed(0)}% win equity (${res.score.display}). Try another move!` });
      }
    } catch {
      setRetryState({ active: true, fen: currentPly.beforeFen, status: 'try_again', feedback: `Try finding ${currentPly.bestMoveSan} or a stronger forcing move.` });
    }
  };

  const executeBotUserMove = async (from: Square, to: Square, promotion?: PieceSymbol) => {
    if (!botState || botState.thinking) return;
    const c = new Chess(botState.fen);
    let mv;
    try { mv = c.move({ from, to, promotion }); } catch { return; }
    if (mv.captured) soundManager.playCapture(); else if (mv.san.includes('+')) soundManager.playCheck(); else soundManager.playMove();

    if (c.isGameOver()) {
      setBotState({ ...botState, fen: c.fen(), lastMove: [mv.from, mv.to], historyFens: [...botState.historyFens, c.fen()], thinking: false, statusText: c.isCheckmate() ? 'Checkmate! You beat the bot.' : 'Draw.' });
      return;
    }
    const afterFen = c.fen();
    setBotState({ ...botState, fen: afterFen, lastMove: [mv.from, mv.to], historyFens: [...botState.historyFens, afterFen], thinking: true, statusText: `Stockfish (${botState.elo}) thinking...` });

    try {
      const botUci = await stockfishService.getBotMove(afterFen, botState.elo);
      const parsed = uciToSquares(botUci);
      if (!parsed) return;
      const bc = new Chess(afterFen);
      const bmv = bc.move({ from: parsed.from, to: parsed.to, promotion: parsed.promotion });
      if (bmv.captured) soundManager.playCapture(); else if (bmv.san.includes('+')) soundManager.playCheck(); else soundManager.playMove();
      setBotState((prev) => prev ? {
        ...prev, fen: bc.fen(), lastMove: [bmv.from, bmv.to], historyFens: [...prev.historyFens, bc.fen()], thinking: false,
        statusText: bc.isGameOver() ? (bc.isCheckmate() ? `Checkmate — Stockfish (${botState.elo}) wins.` : 'Draw.') : `Bot played ${bmv.san}. Your turn!`,
      } : null);
    } catch {
      setBotState((prev) => prev ? { ...prev, thinking: false, statusText: 'Bot paused.' } : null);
    }
  };

  const handleBoardMove = (from: Square, to: Square) => {
    const mode = botState ? 'bot' : retryState ? 'retry' : null;
    if (!mode) return;
    const legal = new Chess(activeFen).moves({ square: from, verbose: true }).filter((m) => m.to === to);
    if (legal.length === 0) return;
    if (legal.some((m) => Boolean(m.promotion))) { setPendingPromo({ from, to, mode }); return; }
    if (mode === 'retry') void executeRetryMove(from, to); else void executeBotUserMove(from, to);
  };

  const topColor: PlayerColor = orientation === 'w' ? 'b' : 'w';
  const bottomColor: PlayerColor = orientation;
  const getClock = (clr: PlayerColor) => {
    if (!analyzed) return undefined;
    for (let i = currentPlyIndex - 1; i >= 0; i--) if (analyzed.plies[i].color === clr && analyzed.plies[i].clockText) return analyzed.plies[i].clockText;
    return undefined;
  };

  const movePairs = useMemo(() => {
    const items = analyzed ? analyzed.plies : rawMoves;
    const pairs: Array<{ n: number; wI?: number; wS?: string; wC?: MoveClassification; bI?: number; bS?: string; bC?: MoveClassification }> = [];
    for (let i = 0; i < items.length; i += 2) {
      const w = items[i]; const b = items[i + 1];
      pairs.push({
        n: Math.floor(i / 2) + 1,
        wI: w ? i + 1 : undefined, wS: w?.san, wC: analyzed && w ? (w as AnalyzedPly).classification : undefined,
        bI: b ? i + 2 : undefined, bS: b?.san, bC: analyzed && b ? (b as AnalyzedPly).classification : undefined,
      });
    }
    return pairs;
  }, [analyzed, rawMoves]);

  const isMistake = Boolean(currentPly && (currentPly.classification === 'inaccuracy' || currentPly.classification === 'mistake' || currentPly.classification === 'blunder'));

  return (
    <div className="space-y-2.5 pb-28">
      <div className="flex items-center justify-between gap-1.5">
        <div className="flex items-center gap-1.5">
          <button type="button" onClick={onBackToGames} className="inline-flex items-center gap-1 text-xs font-semibold text-slate-300 px-2.5 py-1.5 rounded-xl bg-slate-900 border border-slate-800">
            <ArrowLeft className="w-3.5 h-3.5" /> Games
          </button>
          <button type="button" onClick={onOpenInsights} className="inline-flex items-center gap-1 text-xs font-semibold text-slate-300 px-2.5 py-1.5 rounded-xl bg-slate-900 border border-slate-800">
            <BarChart3 className="w-3.5 h-3.5 text-cyan-400" /> Insights
          </button>
        </div>

        <div className="flex items-center gap-1.5">
          <div className="inline-flex rounded-xl bg-slate-900 border border-slate-800 p-0.5 text-[11px] font-bold">
            {([14, 18] as AnalysisDepthPreset[]).map((d) => (
              <button key={d} type="button" disabled={analyzing} onClick={() => onDepthPresetChange(d)} className={`px-2 py-1 rounded-lg ${depthPreset === d ? 'bg-cyan-500/20 text-cyan-300' : 'text-slate-400'}`}>
                D{d}
              </button>
            ))}
          </div>
          {analyzing ? (
            <button type="button" onClick={onCancelAnalysis} className="inline-flex items-center gap-1 px-2.5 py-1.5 rounded-xl bg-red-500/20 text-red-300 border border-red-500/40 text-xs font-bold">
              <StopIcon className="w-3.5 h-3.5" /> Stop
            </button>
          ) : (
            <button type="button" onClick={onStartAnalysis} className="inline-flex items-center gap-1 px-3 py-1.5 rounded-xl bg-gradient-to-r from-cyan-400 to-emerald-400 text-slate-950 text-xs font-extrabold">
              <Sparkles className="w-3.5 h-3.5" /> {analyzed ? 'Re-Run' : 'Analyze'}
            </button>
          )}
        </div>
      </div>

      {analyzing && progress && (
        <div className="rounded-xl bg-slate-900 border border-cyan-500/30 p-2.5 space-y-1.5">
          <div className="flex justify-between text-xs">
            <span className="font-semibold text-cyan-300">Stockfish WASM (D{depthPreset}, MultiPV 2)...</span>
            <span className="font-mono text-slate-300">{progress.done}/{progress.total}</span>
          </div>
          <div className="w-full h-2 rounded-full bg-slate-800 overflow-hidden">
            <div className="h-full bg-gradient-to-r from-cyan-400 to-emerald-400 transition-all duration-200" style={{ width: `${Math.round((progress.done / Math.max(1, progress.total)) * 100)}%` }} />
          </div>
        </div>
      )}

      <PlayerBar
        name={topColor === 'w' ? game.white.name : game.black.name}
        rating={topColor === 'w' ? game.white.rating : game.black.rating}
        color={topColor}
        isActiveTurn={activeTurn === topColor}
        accuracy={analyzed ? (topColor === 'w' ? analyzed.whiteSummary.accuracy : analyzed.blackSummary.accuracy) : undefined}
        estimatedElo={analyzed ? (topColor === 'w' ? analyzed.whiteSummary.estimatedElo : analyzed.blackSummary.estimatedElo) : undefined}
        clockText={getClock(topColor)}
        capturedPieces={topColor === 'w' ? material.capturedByWhite : material.capturedByBlack}
        materialDiff={topColor === 'w' ? Math.max(0, material.whiteAdvantage) : Math.max(0, -material.whiteAdvantage)}
      />

      <div className="relative flex items-stretch gap-1.5 sm:gap-2">
        <EvalBar score={currentScore} orientation={orientation} />
        <div className="flex-1 min-w-0 relative">
          <ChessgroundBoard
            fen={activeFen}
            orientation={orientation}
            lastMove={botState ? botState.lastMove : retryState ? undefined : reviewLastMove}
            interactive={Boolean(botState || (retryState && retryState.status !== 'solved' && retryState.status !== 'revealed'))}
            turnColor={botState ? botState.userColor : retryState ? currentPly?.color : undefined}
            bestMoveUci={!botState && (!retryState || retryState.status === 'revealed' || retryState.status === 'solved') ? currentPly?.bestMoveUci : undefined}
            playedMoveUci={!botState && !retryState ? currentPly?.uci : undefined}
            threatMoveUci={!botState && !retryState ? currentPly?.threatMoveUci : undefined}
            showBestArrow={!botState && (!retryState || retryState.status === 'revealed' || retryState.status === 'solved')}
            showPlayedArrow={!botState && !retryState}
            showThreatArrow={!botState && !retryState && showThreat}
            badgeSquare={!botState && !retryState ? currentPly?.to : undefined}
            badgeClassification={!botState && !retryState ? currentPly?.classification : undefined}
            onUserMove={handleBoardMove}
            onSwipePrev={() => jumpToPly(currentPlyIndex - 1)}
            onSwipeNext={() => jumpToPly(currentPlyIndex + 1)}
          />
          {pendingPromo && (
            <div className="absolute inset-0 z-40 bg-slate-950/75 backdrop-blur-sm flex items-center justify-center rounded-xl">
              <div className="bg-slate-900 border border-slate-700 rounded-2xl p-3 flex gap-2">
                {(['q', 'r', 'b', 'n'] as PieceSymbol[]).map((p) => (
                  <button
                    key={p}
                    type="button"
                    onClick={() => {
                      const { from, to, mode } = pendingPromo;
                      setPendingPromo(null);
                      if (mode === 'retry') void executeRetryMove(from, to, p); else void executeBotUserMove(from, to, p);
                    }}
                    className="w-11 h-11 rounded-xl bg-slate-800 border border-slate-700 text-lg text-white"
                  >
                    {p === 'q' ? '♕' : p === 'r' ? '♖' : p === 'b' ? '♗' : '♘'}
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>

      <PlayerBar
        name={bottomColor === 'w' ? game.white.name : game.black.name}
        rating={bottomColor === 'w' ? game.white.rating : game.black.rating}
        color={bottomColor}
        isActiveTurn={activeTurn === bottomColor}
        accuracy={analyzed ? (bottomColor === 'w' ? analyzed.whiteSummary.accuracy : analyzed.blackSummary.accuracy) : undefined}
        estimatedElo={analyzed ? (bottomColor === 'w' ? analyzed.whiteSummary.estimatedElo : analyzed.blackSummary.estimatedElo) : undefined}
        clockText={getClock(bottomColor)}
        capturedPieces={bottomColor === 'w' ? material.capturedByWhite : material.capturedByBlack}
        materialDiff={bottomColor === 'w' ? Math.max(0, material.whiteAdvantage) : Math.max(0, -material.whiteAdvantage)}
      />

      {botState ? (
        <div className="rounded-2xl bg-slate-900 border border-cyan-500/40 p-3 space-y-2">
          <div className="flex items-center justify-between">
            <span className="inline-flex items-center gap-1.5 text-xs font-bold text-cyan-300"><Bot className="w-4 h-4" /> Play vs. Stockfish ({botState.elo})</span>
            <button type="button" onClick={() => setBotState(null)} className="text-xs px-2.5 py-1 rounded-lg bg-slate-800 text-slate-300">Exit Bot</button>
          </div>
          <p className="text-xs text-slate-200">{botState.statusText}</p>
          <div className="flex items-center gap-1.5 flex-wrap">
            {[1200, 1400, 1600, 1800].map((elo) => (
              <button key={elo} type="button" onClick={() => { setBotElo(elo); setBotState((p) => p ? { ...p, elo } : null); }} className={`px-2.5 py-1 rounded-lg text-[11px] font-bold border ${botState.elo === elo ? 'bg-cyan-500/20 text-cyan-300 border-cyan-500/40' : 'bg-slate-800 text-slate-400 border-slate-700'}`}>
                {elo}
              </button>
            ))}
            {botState.historyFens.length >= 3 && !botState.thinking && (
              <button type="button" onClick={() => { const h = botState.historyFens.slice(0, -2); setBotState({ ...botState, fen: h[h.length - 1], historyFens: h, lastMove: undefined, statusText: 'Turn undone.' }); }} className="ml-auto text-xs text-amber-300 px-2.5 py-1 rounded-lg bg-amber-500/10 border border-amber-500/30">
                Undo
              </button>
            )}
          </div>
        </div>
      ) : retryState && currentPly ? (
        <div className="rounded-2xl bg-slate-900 border border-amber-500/40 p-3 space-y-2">
          <div className="flex items-center justify-between">
            <span className="inline-flex items-center gap-1.5 text-xs font-bold text-amber-300"><RotateCcw className="w-3.5 h-3.5" /> Retry Mistake</span>
            <button type="button" onClick={() => setRetryState(null)} className="text-xs px-2 py-0.5 rounded bg-slate-800 text-slate-300">Done</button>
          </div>
          <p className={`text-xs font-medium ${retryState.status === 'solved' ? 'text-emerald-300' : retryState.status === 'try_again' ? 'text-orange-300' : 'text-slate-200'}`}>{retryState.feedback}</p>
          <div className="flex gap-2">
            <button type="button" onClick={() => setRetryState({ active: true, fen: currentPly.beforeFen, status: 'revealed', feedback: `Best was ${currentPly.bestMoveSan}. Line: ${currentPly.bestPvSan.join(' ')}` })} className="inline-flex items-center gap-1 text-xs font-semibold px-2.5 py-1.5 rounded-lg bg-slate-800 text-slate-200 border border-slate-700">
              <Lightbulb className="w-3.5 h-3.5 text-amber-400" /> Show Best
            </button>
            <button type="button" onClick={jumpToNextMistake} className="text-xs font-semibold px-2.5 py-1.5 rounded-lg bg-cyan-500/15 text-cyan-300 border border-cyan-500/30">Next Mistake</button>
          </div>
        </div>
      ) : (
        <div className="rounded-2xl bg-slate-900/95 border border-slate-800 p-3 space-y-2">
          {!analyzed && !analyzing ? (
            <div className="flex items-center justify-between gap-2">
              <p className="text-xs text-slate-300"><strong className="text-white">Ready for Review.</strong> Run Stockfish to detect !! brilliancies & ?? blunders.</p>
              <button type="button" onClick={onStartAnalysis} className="shrink-0 inline-flex items-center gap-1 px-3 py-1.5 rounded-xl bg-cyan-400 text-slate-950 text-xs font-extrabold"><Play className="w-3.5 h-3.5" /> Analyze</button>
            </div>
          ) : currentPly ? (
            <>
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-2 min-w-0">
                  <ClassificationBadge classification={currentPly.classification} showLabel />
                  <span className="font-bold text-sm text-white">{currentPly.moveNumber}{currentPly.color === 'w' ? '.' : '...'}{currentPly.san}</span>
                  <span className="text-[11px] font-mono text-slate-400">({currentPly.evalAfter.display})</span>
                </div>
                <span className="text-[10px] font-bold uppercase px-2 py-0.5 rounded bg-slate-800 text-slate-400">{currentPly.coaching.tacticalTag}</span>
              </div>
              <p className="text-xs font-bold text-slate-100">{currentPly.coaching.headline}</p>
              <p className="text-xs text-slate-300 leading-relaxed">{currentPly.coaching.detail}</p>
              {currentPly.bestPvSan.length > 0 && (
                <div className="text-[11px] font-mono text-emerald-300 bg-slate-950/80 rounded-lg px-2 py-1 truncate">Best: {currentPly.bestPvSan.join(' ')}</div>
              )}
            </>
          ) : (
            <div className="flex items-center justify-between text-xs text-slate-300">
              <span><strong className="text-white">{game.openingEco}</strong> {analyzed?.openingLineDetected || game.openingName}</span>
              <span className="text-slate-400">Swipe board or tap &gt;</span>
            </div>
          )}

          <div className="flex items-center gap-2 pt-1 flex-wrap">
            {isMistake && (
              <button type="button" onClick={() => { soundManager.unlock(); setBotState(null); setRetryState({ active: true, fen: currentPly!.beforeFen, status: 'prompt', feedback: `Find a better move for ${currentPly!.color === 'w' ? 'White' : 'Black'} instead of ${currentPly!.san}.` }); }} className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-amber-500/20 text-amber-200 border border-amber-500/40 text-xs font-bold">
                <RotateCcw className="w-3.5 h-3.5" /> Retry Move
              </button>
            )}
            <button type="button" onClick={() => { soundManager.unlock(); setRetryState(null); const t = activeTurn; setBotState({ active: true, elo: botElo, userColor: t, startFen: reviewFen, fen: reviewFen, lastMove: reviewLastMove, thinking: false, historyFens: [reviewFen], statusText: `Your turn (${t === 'w' ? 'White' : 'Black'}) vs Stockfish ${botElo}` }); }} className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-slate-800 text-slate-200 border border-slate-700 text-xs font-semibold">
              <Bot className="w-3.5 h-3.5 text-cyan-400" /> Play Bot ({botElo})
            </button>
            {analyzed && (
              <button type="button" onClick={() => setShowThreat((s) => !s)} className={`inline-flex items-center gap-1 px-2.5 py-1.5 rounded-xl text-xs font-semibold border ${showThreat ? 'bg-red-500/20 text-red-200 border-red-500/40' : 'bg-slate-800 text-slate-400 border-slate-700'}`}>
                <Eye className="w-3.5 h-3.5" /> Threat
              </button>
            )}
            {analyzed && (
              <button type="button" onClick={jumpToNextMistake} className="ml-auto inline-flex items-center gap-1 px-2.5 py-1.5 rounded-xl bg-slate-800 text-orange-300 border border-slate-700 text-xs font-semibold">
                <AlertTriangle className="w-3.5 h-3.5" /> Mistake
              </button>
            )}
          </div>
        </div>
      )}

      {analyzed && <EvalGraph initialEval={analyzed.initialEval} plies={analyzed.plies} currentPlyIndex={currentPlyIndex} onSelectPly={jumpToPly} />}

      {analyzed && (
        <div className="grid grid-cols-2 gap-2">
          {(['w', 'b'] as PlayerColor[]).map((clr) => {
            const sum = clr === 'w' ? analyzed.whiteSummary : analyzed.blackSummary;
            const pl = clr === 'w' ? game.white : game.black;
            return (
              <div key={clr} className="rounded-2xl bg-slate-900/90 border border-slate-800 p-2.5">
                <div className="flex items-center justify-between text-xs">
                  <span className="font-semibold text-slate-200 truncate">{pl.name}</span>
                  <span className="font-mono font-extrabold text-emerald-300">{sum.accuracy.toFixed(1)}%</span>
                </div>
                <div className="mt-1 flex items-center justify-between text-[11px] text-slate-400">
                  <span>Est. Rating</span>
                  <span className="font-mono font-bold text-cyan-300">{sum.estimatedElo}</span>
                </div>
                <div className="mt-1.5 flex items-center gap-1.5 flex-wrap text-[10px]">
                  {sum.counts.brilliant > 0 && <span className="text-cyan-300 font-bold">!! {sum.counts.brilliant}</span>}
                  {sum.counts.great > 0 && <span className="text-blue-300 font-bold">! {sum.counts.great}</span>}
                  <span className="text-yellow-300">?! {sum.counts.inaccuracy}</span>
                  <span className="text-orange-300">? {sum.counts.mistake}</span>
                  <span className="text-red-400">?? {sum.counts.blunder}</span>
                </div>
              </div>
            );
          })}
        </div>
      )}

      <div className="rounded-2xl bg-slate-900/90 border border-slate-800 p-2.5">
        <div className="text-[11px] font-bold uppercase tracking-wider text-slate-400 mb-1.5 px-1">Moves</div>
        <div className="max-h-44 overflow-y-auto space-y-0.5 pr-1">
          {movePairs.map((p) => (
            <div key={p.n} className="grid grid-cols-[30px_1fr_1fr] items-center gap-1 text-xs">
              <span className="text-slate-500 font-mono text-[11px] pl-1">{p.n}.</span>
              {p.wI && p.wS ? (
                <button type="button" onClick={() => jumpToPly(p.wI!)} className={`flex items-center justify-between px-2 py-1 rounded-lg font-mono ${currentPlyIndex === p.wI ? 'bg-cyan-500/20 text-cyan-200 border border-cyan-500/40' : 'hover:bg-slate-800 text-slate-200'}`}>
                  <span>{p.wS}</span>
                  {p.wC && <span className="text-[10px] font-sans font-bold" style={{ color: CLASSIFICATION_META[p.wC].color }}>{CLASSIFICATION_META[p.wC].symbol}</span>}
                </button>
              ) : <span />}
              {p.bI && p.bS ? (
                <button type="button" onClick={() => jumpToPly(p.bI!)} className={`flex items-center justify-between px-2 py-1 rounded-lg font-mono ${currentPlyIndex === p.bI ? 'bg-cyan-500/20 text-cyan-200 border border-cyan-500/40' : 'hover:bg-slate-800 text-slate-200'}`}>
                  <span>{p.bS}</span>
                  {p.bC && <span className="text-[10px] font-sans font-bold" style={{ color: CLASSIFICATION_META[p.bC].color }}>{CLASSIFICATION_META[p.bC].symbol}</span>}
                </button>
              ) : <span />}
            </div>
          ))}
        </div>
      </div>

      <div className="fixed bottom-0 left-0 right-0 z-40 bg-slate-950/95 backdrop-blur-md border-t border-slate-800 px-3 pt-2 pb-[max(0.65rem,env(safe-area-inset-bottom))]">
        <div className="max-w-lg mx-auto grid grid-cols-6 gap-1.5">
          <button type="button" onClick={() => jumpToPly(0)} className="flex items-center justify-center py-3 rounded-xl bg-slate-900 border border-slate-800 text-slate-300 active:scale-95" aria-label="First move">
            <SkipBack className="w-4 h-4" />
          </button>
          <button type="button" onClick={() => jumpToPly(currentPlyIndex - 1)} className="col-span-1 flex items-center justify-center py-3 rounded-xl bg-slate-800 border border-slate-700 text-white active:scale-95" aria-label="Previous move">
            <ChevronLeft className="w-5 h-5" />
          </button>
          <button type="button" onClick={() => jumpToPly(currentPlyIndex + 1)} className="col-span-2 flex items-center justify-center py-3 rounded-xl bg-gradient-to-r from-cyan-500/25 to-emerald-500/25 border border-cyan-500/40 text-cyan-200 font-bold active:scale-95" aria-label="Next move">
            <ChevronRight className="w-5 h-5" />
          </button>
          <button type="button" onClick={() => jumpToPly(totalPlies)} className="flex items-center justify-center py-3 rounded-xl bg-slate-900 border border-slate-800 text-slate-300 active:scale-95" aria-label="Last move">
            <SkipForward className="w-4 h-4" />
          </button>
          <button type="button" onClick={() => setOrientation((o) => (o === 'w' ? 'b' : 'w'))} className="flex items-center justify-center py-3 rounded-xl bg-slate-900 border border-slate-800 text-slate-300 active:scale-95" aria-label="Flip board">
            <FlipVertical2 className="w-4 h-4" />
          </button>
        </div>
      </div>
    </div>
  );
};
