import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Chess, type PieceSymbol, type Square } from 'chess.js';
import {
  ArrowLeft,
  BarChart3,
  FlaskConical,
  Gem,
  Loader2,
  RotateCcw,
  Sparkles,
  Square as StopIcon,
  X,
} from 'lucide-react';
import {
  type AnalysisDepthPreset,
  type AnalyzedGame,
  type AnalyzedPly,
  type BoardThemeId,
  type BotSession,
  type EngineEval,
  type EngineScore,
  type LichessGameRecord,
  type MoveClassification,
  type PlayerColor,
  type RetrySession,
} from '../types/chess';
import { isSacrificeMove, loadPgnSafely } from '../chess/classification';
import { buildOpeningReport } from '../chess/openingBook';
import type { OpeningCourse } from '../types/openings';
import { detectRepertoireDeviation, type RepertoireDeviation } from '../services/deviationDetector';
import type { ExplorerPrefSettings } from './SettingsMenu';
import { buildEngineScore, getMaterialBalance, getMoverWinPercent, uciToSquares } from '../utils/chessMath';
import { appendSandboxMoves, jumpSandboxEdge, stepSandboxNav, type SandboxNavMove } from '../utils/sandboxNav';
import { soundManager } from '../utils/sound';
import { stockfishService } from '../engine/StockfishService';
import { maiaService } from '../engine/MaiaService';
import {
  fetchLichessTablebase,
  formatTablebaseWdl,
  isTablebaseEligible,
  type TablebaseResult,
} from '../services/tablebaseApi';
import { ChessgroundBoard } from './ChessgroundBoard';
import { EvalBar } from './EvalBar';
import { EvalGraph } from './EvalGraph';
import { PlayerBar } from './PlayerBar';
import { CoachCard } from './CoachCard';
import { BotPanel, RetryPanel } from './AnalysisPanels';
import { KeyMomentsBar } from './KeyMomentsBar';
import { MoveList } from './MoveList';
import { VariationExplorer } from './VariationExplorer';
import { OpeningExplorer } from './OpeningExplorer';
import { OpeningReportCard } from './OpeningReportCard';
import { TransportControls } from './TransportControls';
import { AccuracyCards } from './AccuracyCards';
import { AlienCelebration, type CelebrationKind } from './AlienCelebration';

interface Props {
  game: LichessGameRecord;
  analyzed: AnalyzedGame | null;
  analyzing: boolean;
  progress: { done: number; total: number; stageLabel?: string; percent?: number } | null;
  depthPreset: AnalysisDepthPreset;
  onDepthPresetChange: (d: AnalysisDepthPreset) => void;
  onStartAnalysis: () => void;
  onCancelAnalysis: () => void;
  onBackToGames: () => void;
  onOpenInsights: () => void;
  onOpenVault: () => void;
  initialPly?: number | null;
  boardTheme: BoardThemeId;
  celebrationsEnabled: boolean;
  courses?: OpeningCourse[];
  explorerPrefs?: ExplorerPrefSettings;
  onBoostDeviationToFsrs?: (deviation: RepertoireDeviation) => Promise<void>;
  onPatchDeviationGap?: (deviation: RepertoireDeviation) => Promise<void>;
}

type BoardMode = 'bot' | 'retry' | 'sandbox';

type SandboxMove = SandboxNavMove;

interface SandboxState {
  fen: string;
  basePly: number;
  moves: SandboxMove[];
  cursor: number;
  eval: EngineEval | null;
  loading: boolean;
}

interface CelebrationState {
  trigger: number;
  kind: CelebrationKind;
  message?: string;
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
  onOpenVault,
  initialPly,
  boardTheme,
  celebrationsEnabled,
  courses = [],
  explorerPrefs,
  onBoostDeviationToFsrs,
  onPatchDeviationGap,
}) => {
  const rawMoves = useMemo(() => {
    try { return loadPgnSafely(game.pgn).history({ verbose: true }); } catch { return []; }
  }, [game.pgn]);

  const [currentPlyIndex, setCurrentPlyIndex] = useState(0);
  const [orientation, setOrientation] = useState<PlayerColor>(game.userColor ?? 'w');
  const [showThreat, setShowThreat] = useState(false);
  const [botElo, setBotElo] = useState(1400);
  const [pendingPromo, setPendingPromo] = useState<{ from: Square; to: Square; mode: BoardMode } | null>(null);
  const [retryState, setRetryState] = useState<RetrySession | null>(null);
  const [botState, setBotState] = useState<BotSession | null>(null);
  const [sandbox, setSandbox] = useState<SandboxState | null>(null);
  const [playing, setPlaying] = useState(false);
  const [speed, setSpeed] = useState<1 | 2>(1);
  const [celebration, setCelebration] = useState<CelebrationState | null>(null);
  const [tablebase, setTablebase] = useState<TablebaseResult | null>(null);
  const celebratedInitialRef = useRef('');
  const botGenerationRef = useRef(0);
  const retryGenerationRef = useRef(0);
  const boardRef = useRef<HTMLDivElement | null>(null);

  const sandboxFen = sandbox?.fen ?? null;

  const scrollBoardIntoView = () => {
    if (typeof window === 'undefined' || !window.matchMedia('(max-width: 1023px)').matches) return;
    window.setTimeout(() => {
      boardRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }, 80);
  };

  useEffect(() => {
    const start = initialPly && initialPly > 0 ? initialPly : 0;
    botGenerationRef.current += 1;
    retryGenerationRef.current += 1;
    setCurrentPlyIndex(start);
    setOrientation(game.userColor ?? 'w');
    setRetryState(null);
    setBotState(null);
    setPendingPromo(null);
    setSandbox(null);
    setPlaying(false);
    setCelebration(null);
  }, [game.id, game.userColor, initialPly]);

  const totalPlies = analyzed ? analyzed.plies.length : rawMoves.length;
  const currentPly: AnalyzedPly | null = analyzed && currentPlyIndex > 0 ? analyzed.plies[currentPlyIndex - 1] ?? null : null;

  const sanHistory = useMemo(
    () => (analyzed ? analyzed.plies.map((p) => p.san) : rawMoves.map((m) => m.san)),
    [analyzed, rawMoves],
  );
  const openingReport = useMemo(
    () => buildOpeningReport(sanHistory, game.userColor ?? 'w'),
    [sanHistory, game.userColor],
  );

  const repertoireDeviation = useMemo(
    () =>
      detectRepertoireDeviation({
        sanHistory,
        userColor: game.userColor ?? 'w',
        courses,
        analyzed,
        maxMoveNumber: 12,
      }),
    [sanHistory, game.userColor, courses, analyzed]
  );

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

  const historyForPly = (ply: number): string[] => {
    if (analyzed && analyzed.plies.length >= ply) {
      return analyzed.plies.slice(0, ply).map((p) => p.san);
    }
    return rawMoves.slice(0, ply).map((m) => m.san);
  };

  const activeSanHistory = useMemo(() => {
    if (sandbox) {
      return [...historyForPly(sandbox.basePly), ...sandbox.moves.slice(0, sandbox.cursor).map((m) => m.san)];
    }
    return historyForPly(currentPlyIndex);
  }, [sandbox, analyzed, rawMoves, currentPlyIndex]);

  const fenAtPly = (plyIndex: number): string => {
    if (plyIndex <= 0) return START_FEN;
    return analyzed?.plies[plyIndex - 1]?.afterFen ?? rawMoves[plyIndex - 1]?.after ?? START_FEN;
  };

  const currentScore: EngineScore = useMemo(() => {
    if (!analyzed) return buildEngineScore(20, null);
    return currentPlyIndex === 0 ? analyzed.initialEval : analyzed.plies[currentPlyIndex - 1]?.evalAfter ?? analyzed.initialEval;
  }, [analyzed, currentPlyIndex]);

  const activeFen = botState ? botState.fen : retryState ? retryState.fen : sandbox ? sandbox.fen : reviewFen;
  const activeTurn: PlayerColor = activeFen.split(' ')[1] === 'b' ? 'b' : 'w';
  const material = useMemo(() => getMaterialBalance(activeFen), [activeFen]);
  const activeScore = sandbox
    ? sandbox.eval?.score ?? currentScore
    : retryState
      ? currentPly?.evalBefore ?? currentScore
      : botState
        ? buildEngineScore(0, null)
        : currentScore;

  const isMistake = Boolean(currentPly && (currentPly.classification === 'inaccuracy' || currentPly.classification === 'mistake' || currentPly.classification === 'blunder'));

  const triggerCelebration = (kind: CelebrationKind, message?: string) => {
    if (!celebrationsEnabled) return;
    setCelebration({ trigger: Date.now() + Math.floor(Math.random() * 997), kind, message });
  };

  const jumpToPly = (idx: number) => {
    soundManager.unlock();
    const next = Math.max(0, Math.min(totalPlies, idx));
    botGenerationRef.current += 1;
    retryGenerationRef.current += 1;
    setRetryState(null);
    setBotState(null);
    setPendingPromo(null);
    setSandbox(null);
    setCurrentPlyIndex(next);

    if (next > 0 && analyzed) {
      const p = analyzed.plies[next - 1];
      if (p) {
        soundManager.playClassification(p.classification, Boolean(p.captured), p.san.includes('+'));
        if (next !== currentPlyIndex && p.classification === 'brilliant') triggerCelebration('brilliant');
        else if (next !== currentPlyIndex && p.classification === 'blunder') triggerCelebration('blunder');
      }
    } else if (next > 0 && rawMoves[next - 1]) {
      const m = rawMoves[next - 1];
      if (m.san.includes('+')) soundManager.playCheck();
      else if (m.captured) soundManager.playCapture();
      else soundManager.playMove();
    }
  };

  useEffect(() => {
    if (!initialPly || initialPly <= 0 || !analyzed || !celebrationsEnabled) return;
    const key = `${game.id}:${initialPly}`;
    if (celebratedInitialRef.current === key) return;
    celebratedInitialRef.current = key;
    const ply = analyzed.plies[initialPly - 1];
    if (ply?.classification === 'brilliant') {
      setCelebration({ trigger: Date.now(), kind: 'brilliant' });
    }
  }, [initialPly, analyzed, game.id, celebrationsEnabled]);

  const buildSandboxFen = (basePlyIdx: number, moves: SandboxMove[], cursor: number): string => {
    const c = new Chess(fenAtPly(basePlyIdx));
    for (const m of moves.slice(0, cursor)) {
      const parsed = uciToSquares(m.uci);
      if (!parsed) break;
      try { c.move({ from: parsed.from, to: parsed.to, promotion: parsed.promotion }); } catch { break; }
    }
    return c.fen();
  };

  const applySandboxNav = (nextNav: { basePly: number; moves: SandboxMove[]; cursor: number }) => {
    if (!sandbox) return;
    if (
      nextNav.basePly === sandbox.basePly &&
      nextNav.cursor === sandbox.cursor &&
      nextNav.moves.length === sandbox.moves.length
    ) {
      return;
    }
    soundManager.unlock();
    soundManager.playMove();
    if (nextNav.basePly !== currentPlyIndex) {
      setCurrentPlyIndex(nextNav.basePly);
    }
    const nextFen = buildSandboxFen(nextNav.basePly, nextNav.moves, nextNav.cursor);
    setSandbox((prev) =>
      prev
        ? {
            ...prev,
            basePly: nextNav.basePly,
            moves: nextNav.moves,
            cursor: nextNav.cursor,
            fen: nextFen,
            loading: true,
          }
        : null
    );
  };

  const handleJumpGamePly = (idx: number) => {
    if (sandbox) {
      const safe = Math.max(0, Math.min(totalPlies, idx));
      applySandboxNav({ basePly: safe, moves: [], cursor: 0 });
      return;
    }
    jumpToPly(idx);
  };

  const handleNavPrev = () => {
    if (sandbox) {
      applySandboxNav(stepSandboxNav(sandbox, -1, totalPlies));
      return;
    }
    if (botState) {
      if (botState.historyFens.length > 2 && !botState.thinking) {
        setBotState((prev) => {
          if (!prev || prev.historyFens.length <= 2) return prev;
          const h = prev.historyFens.slice(0, -2);
          return { ...prev, fen: h[h.length - 1], historyFens: h, lastMove: undefined, statusText: 'Turn undone.' };
        });
      }
      return;
    }
    if (retryState && currentPly) {
      retryGenerationRef.current += 1;
      setRetryState({ active: true, fen: currentPly.beforeFen, status: 'prompt', feedback: `Position reset. Find a better move than ${currentPly.san}.` });
      return;
    }
    jumpToPly(currentPlyIndex - 1);
  };

  const handleNavNext = () => {
    if (sandbox) {
      applySandboxNav(stepSandboxNav(sandbox, 1, totalPlies));
      return;
    }
    if (botState || retryState) return;
    jumpToPly(currentPlyIndex + 1);
  };

  const handleNavFirst = () => {
    if (sandbox) {
      applySandboxNav(jumpSandboxEdge(sandbox, 'first', totalPlies));
      return;
    }
    if (botState) return;
    if (retryState && currentPly) {
      retryGenerationRef.current += 1;
      setRetryState({ active: true, fen: currentPly.beforeFen, status: 'prompt', feedback: `Position reset. Find a better move than ${currentPly.san}.` });
      return;
    }
    jumpToPly(0);
  };

  const handleNavLast = () => {
    if (sandbox) {
      applySandboxNav(jumpSandboxEdge(sandbox, 'last', totalPlies));
      return;
    }
    if (botState || retryState) return;
    jumpToPly(totalPlies);
  };

  useEffect(() => {
    if (!playing) return;
    if (botState || retryState) { setPlaying(false); return; }
    if (sandbox) {
      const canAdvance =
        sandbox.cursor < sandbox.moves.length ||
        (sandbox.moves.length === 0 && sandbox.basePly < totalPlies);
      if (!canAdvance) { setPlaying(false); return; }
      const delay = speed === 2 ? 720 : 1450;
      const timer = window.setTimeout(() => handleNavNext(), delay);
      return () => window.clearTimeout(timer);
    }
    if (currentPlyIndex >= totalPlies) { setPlaying(false); return; }
    const delay = speed === 2 ? 720 : 1450;
    const timer = window.setTimeout(() => jumpToPly(currentPlyIndex + 1), delay);
    return () => window.clearTimeout(timer);
    // handleNavNext/jumpToPly intentionally read from the current render.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playing, currentPlyIndex, totalPlies, speed, botState, retryState, sandbox]);

  useEffect(() => {
    if (!isTablebaseEligible(activeFen)) {
      setTablebase(null);
      return;
    }
    let cancelled = false;
    void fetchLichessTablebase(activeFen).then((res) => {
      if (!cancelled) setTablebase(res);
    });
    return () => { cancelled = true; };
  }, [activeFen]);

  useEffect(() => {
    if (!sandboxFen) return;
    let cancelled = false;
    const timer = window.setTimeout(() => {
      setSandbox((prev) => (prev && prev.fen === sandboxFen ? { ...prev, loading: true } : prev));
      stockfishService
        .analyzePosition(sandboxFen, { depth: 10, multiPv: 3, timeoutMs: 10000 })
        .then((res) => {
          if (!cancelled) setSandbox((prev) => (prev && prev.fen === sandboxFen ? { ...prev, eval: res, loading: false } : prev));
        })
        .catch(() => {
          if (!cancelled) setSandbox((prev) => (prev && prev.fen === sandboxFen ? { ...prev, loading: false } : prev));
        });
    }, 180);
    return () => { cancelled = true; window.clearTimeout(timer); };
  }, [sandboxFen]);

  const startRetry = () => {
    if (!currentPly || botState) return;
    soundManager.unlock();
    retryGenerationRef.current += 1;
    setPlaying(false);
    setSandbox(null);
    setBotState(null);
    setRetryState({
      active: true,
      fen: currentPly.beforeFen,
      status: 'prompt',
      feedback: `Find a better move for ${currentPly.color === 'w' ? 'White' : 'Black'} instead of ${currentPly.san}.`,
    });
    scrollBoardIntoView();
  };

  const jumpToNextMistake = () => {
    if (!analyzed) return;
    const uc = game.userColor ?? 'w';
    const isErr = (c: MoveClassification) => c === 'inaccuracy' || c === 'mistake' || c === 'blunder';
    const target = analyzed.plies.find((p, i) => i + 1 > currentPlyIndex && p.color === uc && isErr(p.classification))
      ?? analyzed.plies.find((p) => p.color === uc && isErr(p.classification))
      ?? analyzed.plies.find((p) => isErr(p.classification));
    if (target) jumpToPly(target.ply);
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.tagName === 'SELECT' || target.isContentEditable)) return;
      if (pendingPromo) return;
      if (e.key === 'Escape') {
        botGenerationRef.current += 1;
        retryGenerationRef.current += 1;
        setRetryState(null); setBotState(null); setSandbox(null); setPlaying(false);
        return;
      }
      if (e.key === 'f' || e.key === 'F') { setOrientation((o) => (o === 'w' ? 'b' : 'w')); return; }
      if (e.key === 'ArrowLeft') { e.preventDefault(); handleNavPrev(); return; }
      if (e.key === 'ArrowRight') { e.preventDefault(); handleNavNext(); return; }
      if (e.key === 'Home') { e.preventDefault(); handleNavFirst(); return; }
      if (e.key === 'End') { e.preventDefault(); handleNavLast(); return; }
      if (botState || retryState) return;
      if (e.key === ' ') {
        e.preventDefault();
        if (sandbox) {
          const atBranchEnd = sandbox.moves.length > 0 ? sandbox.cursor >= sandbox.moves.length : sandbox.basePly >= totalPlies;
          if (!playing && atBranchEnd) handleNavFirst();
          setPlaying((p) => !p);
          return;
        }
        if (!playing && currentPlyIndex >= totalPlies) jumpToPly(0);
        setPlaying((p) => !p);
      } else if (e.key === 'r' || e.key === 'R') {
        if (isMistake && !sandbox) startRetry();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentPlyIndex, totalPlies, botState, retryState, sandbox, pendingPromo, isMistake, playing]);

  const celebrateIfSacrifice = (fenAfter: string, mv: { to: string; piece: PieceSymbol; captured?: PieceSymbol }, mover: PlayerColor) => {
    if (!currentPly) return;
    if (isSacrificeMove(currentPly.beforeFen, fenAfter, mover, mv.to, mv.piece, mv.captured)) {
      triggerCelebration('brilliant', 'Galaxy-brain retry confirmed — that sacrifice bends spacetime. 🛸');
    }
  };

  const executeRetryMove = async (from: Square, to: Square, promotion?: PieceSymbol) => {
    if (!currentPly) return;
    const generation = retryGenerationRef.current;
    const c = new Chess(currentPly.beforeFen);
    let mv;
    try { mv = c.move({ from, to, promotion }); } catch { return; }
    const uci = `${mv.from}${mv.to}${mv.promotion ?? ''}`;
    if (uci === currentPly.bestMoveUci) {
      soundManager.playSuccess();
      setRetryState({ active: true, fen: c.fen(), status: 'solved', feedback: `Spot on! ${mv.san} is Stockfish's #1 move.` });
      celebrateIfSacrifice(c.fen(), mv, currentPly.color);
      return;
    }
    setRetryState({ active: true, fen: c.fen(), status: 'evaluating', feedback: `Evaluating ${mv.san}…` });
    try {
      const res = await stockfishService.analyzePosition(c.fen(), { depth: 12, multiPv: 1, timeoutMs: 8000 });
      if (retryGenerationRef.current !== generation) return;
      const loss = Math.max(0, getMoverWinPercent(currentPly.evalBefore, currentPly.color) - getMoverWinPercent(res.score, currentPly.color));
      if (loss <= 6) {
        soundManager.playSuccess();
        setRetryState({ active: true, fen: c.fen(), status: 'solved', feedback: `Great alternative! ${mv.san} holds (${res.score.display}). Engine top was ${currentPly.bestMoveSan}.` });
        celebrateIfSacrifice(c.fen(), mv, currentPly.color);
      } else {
        soundManager.playError();
        if (loss > 22) triggerCelebration('blunder', 'Houston, we dropped a piece. Reset and try again.');
        setRetryState({ active: true, fen: currentPly.beforeFen, status: 'try_again', feedback: `${mv.san} drops ${loss.toFixed(0)}% win equity (${res.score.display}). Try another move!` });
      }
    } catch {
      if (retryGenerationRef.current !== generation) return;
      setRetryState({ active: true, fen: currentPly.beforeFen, status: 'try_again', feedback: `Try finding ${currentPly.bestMoveSan} or a stronger forcing move.` });
    }
  };

  const executeBotUserMove = async (from: Square, to: Square, promotion?: PieceSymbol) => {
    const session = botState;
    if (!session || session.thinking) return;
    const generation = botGenerationRef.current;
    const c = new Chess(session.fen);
    let mv;
    try { mv = c.move({ from, to, promotion }); } catch { return; }
    if (mv.captured) soundManager.playCapture(); else if (mv.san.includes('+')) soundManager.playCheck(); else soundManager.playMove();

    if (c.isGameOver()) {
      setBotState((prev) => prev ? {
        ...prev, fen: c.fen(), lastMove: [mv.from, mv.to], historyFens: [...prev.historyFens, c.fen()], thinking: false,
        statusText: c.isCheckmate() ? 'Checkmate! You beat the bot.' : 'Draw.',
      } : null);
      return;
    }
    const afterFen = c.fen();
    setBotState((prev) => prev ? {
      ...prev, fen: afterFen, lastMove: [mv.from, mv.to], historyFens: [...prev.historyFens, afterFen], thinking: true,
      statusText: `Stockfish (${prev.elo}) thinking…`,
    } : null);

    try {
      const { moveUci: botUci, engine: botEngine } = await maiaService.getSmartBotMove(afterFen, session.elo);
      if (botGenerationRef.current !== generation) return;
      const parsed = uciToSquares(botUci);
      if (!parsed) {
        setBotState((prev) => (prev ? { ...prev, thinking: false, statusText: 'Bot returned no move — try again.' } : null));
        return;
      }
      const bc = new Chess(afterFen);
      const bmv = bc.move({ from: parsed.from, to: parsed.to, promotion: parsed.promotion });
      if (bmv.captured) soundManager.playCapture(); else if (bmv.san.includes('+')) soundManager.playCheck(); else soundManager.playMove();
      const engineName = botEngine === 'maia' ? `Maia ${session.elo}` : `Stockfish ${session.elo}`;
      setBotState((prev) => prev ? {
        ...prev, fen: bc.fen(), lastMove: [bmv.from, bmv.to], historyFens: [...prev.historyFens, bc.fen()], thinking: false,
        statusText: bc.isGameOver() ? (bc.isCheckmate() ? `Checkmate — ${engineName} wins.` : 'Draw.') : `${engineName} played ${bmv.san}. Your turn!`,
      } : null);
    } catch {
      if (botGenerationRef.current !== generation) return;
      setBotState((prev) => prev ? { ...prev, thinking: false, statusText: 'Bot paused.' } : null);
    }
  };

  const startBot = () => {
    if (analyzing) return;
    soundManager.unlock();
    botGenerationRef.current += 1;
    setPlaying(false);
    setRetryState(null);
    setSandbox(null);
    const turn = activeTurn;
    setBotState({
      active: true,
      elo: botElo,
      userColor: turn,
      startFen: activeFen,
      fen: activeFen,
      lastMove: sandbox ? undefined : reviewLastMove,
      thinking: false,
      historyFens: [activeFen],
      statusText: `Your turn (${turn === 'w' ? 'White' : 'Black'}) vs Stockfish ${botElo}`,
    });
    scrollBoardIntoView();
  };

  const toSandboxMove = (mv: { san: string; from: string; to: string; promotion?: string }): SandboxMove => ({
    san: mv.san,
    uci: `${mv.from}${mv.to}${mv.promotion ?? ''}`,
    from: mv.from,
    to: mv.to,
  });

  const beginSandboxAt = (plyIndex: number, san?: string) => {
    const safePly = Math.max(0, Math.min(totalPlies, plyIndex));
    soundManager.unlock();
    const c = new Chess(fenAtPly(safePly));
    const moves: SandboxMove[] = [];
    if (san) {
      try { moves.push(toSandboxMove(c.move(san))); } catch { return; }
    }
    setPlaying(false);
    setRetryState(null);
    setBotState(null);
    setPendingPromo(null);
    setCurrentPlyIndex(safePly);
    setSandbox({ fen: c.fen(), basePly: safePly, moves, cursor: moves.length, eval: null, loading: true });
    scrollBoardIntoView();
  };

  const startSandbox = () => {
    if (!analyzed) return;
    beginSandboxAt(currentPlyIndex);
  };

  const playExplorerSan = (san: string) => {
    if (!sandbox) {
      beginSandboxAt(currentPlyIndex, san);
      return;
    }
    soundManager.unlock();
    const c = new Chess(sandbox.fen);
    let mv;
    try { mv = c.move(san); } catch { return; }
    if (mv.captured) soundManager.playCapture(); else if (mv.san.includes('+')) soundManager.playCheck(); else soundManager.playMove();
    const move = toSandboxMove(mv);
    setSandbox((prev) => {
      if (!prev) return null;
      const nextNav = appendSandboxMoves(prev, [move]);
      return { ...prev, ...nextNav, fen: c.fen(), loading: true };
    });
    scrollBoardIntoView();
  };

  const applySandboxMove = (from: Square, to: Square, promotion?: PieceSymbol) => {
    if (!sandbox) return;
    const c = new Chess(sandbox.fen);
    let mv;
    try { mv = c.move({ from, to, promotion }); } catch { return; }
    const uci = `${mv.from}${mv.to}${mv.promotion ?? ''}`;
    if (mv.captured) soundManager.playCapture(); else if (mv.san.includes('+')) soundManager.playCheck(); else soundManager.playMove();
    setSandbox((prev) => {
      if (!prev) return null;
      const nextNav = appendSandboxMoves(prev, [{ san: mv.san, uci, from: mv.from, to: mv.to }]);
      return { ...prev, ...nextNav, fen: c.fen(), loading: true };
    });
  };

  const playSandboxLine = (uciMoves: string[]) => {
    if (!sandbox) return;
    const c = new Chess(sandbox.fen);
    const applied: SandboxMove[] = [];
    for (const uci of uciMoves) {
      const parsed = uciToSquares(uci);
      if (!parsed) break;
      try {
        const mv = c.move({ from: parsed.from, to: parsed.to, promotion: parsed.promotion });
        applied.push({ san: mv.san, uci, from: mv.from, to: mv.to });
      } catch { break; }
    }
    if (applied.length === 0) return;
    soundManager.playMove();
    setSandbox((prev) => {
      if (!prev) return null;
      const nextNav = appendSandboxMoves(prev, applied);
      return { ...prev, ...nextNav, fen: c.fen(), loading: true };
    });
  };

  const handleBoardMove = (from: Square, to: Square) => {
    const mode: BoardMode | null = botState ? 'bot' : retryState ? 'retry' : sandbox ? 'sandbox' : null;
    if (!mode) return;
    const legal = new Chess(activeFen).moves({ square: from, verbose: true }).filter((m) => m.to === to);
    if (legal.length === 0) return;
    if (legal.some((m) => Boolean(m.promotion))) { setPendingPromo({ from, to, mode }); return; }
    if (mode === 'retry') void executeRetryMove(from, to);
    else if (mode === 'bot') void executeBotUserMove(from, to);
    else applySandboxMove(from, to);
  };

  const topColor: PlayerColor = orientation === 'w' ? 'b' : 'w';
  const bottomColor: PlayerColor = orientation;
  const getClock = (clr: PlayerColor) => {
    if (!analyzed || sandbox || botState || retryState) return undefined;
    for (let i = currentPlyIndex - 1; i >= 0; i--) {
      if (analyzed.plies[i].color === clr && analyzed.plies[i].clockText) return analyzed.plies[i].clockText;
    }
    return undefined;
  };

  const sandboxLastMove = useMemo<[string, string] | undefined>(() => {
    if (!sandbox) return undefined;
    if (sandbox.cursor > 0) {
      const m = sandbox.moves[sandbox.cursor - 1];
      return m ? [m.from, m.to] : undefined;
    }
    if (sandbox.basePly > 0) {
      const p = analyzed?.plies[sandbox.basePly - 1] ?? rawMoves[sandbox.basePly - 1];
      return p ? [p.from, p.to] : undefined;
    }
    return undefined;
  }, [sandbox, analyzed, rawMoves]);

  const boardInteractive = Boolean(
    (botState && !botState.thinking) ||
    (retryState && (retryState.status === 'prompt' || retryState.status === 'try_again')) ||
    sandbox
  );
  const boardTurnColor: PlayerColor | undefined = botState
    ? botState.userColor
    : retryState
      ? currentPly?.color
      : sandbox
        ? activeTurn
        : undefined;

  const bestArrow = sandbox
    ? sandbox.eval?.bestMoveUci
    : retryState
      ? (retryState.status === 'revealed' || retryState.status === 'solved' ? currentPly?.bestMoveUci : undefined)
      : botState
        ? undefined
        : currentPly?.bestMoveUci;
  const playedArrow = sandbox
    ? (sandbox.cursor > 0 ? sandbox.moves[sandbox.cursor - 1]?.uci : undefined)
    : botState || retryState
      ? undefined
      : currentPly?.uci;
  const threatArrow = !sandbox && !botState && !retryState && showThreat ? currentPly?.threatMoveUci : undefined;
  const showBestArrow = !botState && (!retryState || retryState.status === 'revealed' || retryState.status === 'solved');
  const showPlayedArrow = !botState && !retryState;

  const basePly = sandbox?.basePly ?? currentPlyIndex;
  const baseLabel = basePly === 0 ? 'the starting position' : `after ${Math.ceil(basePly / 2)}${basePly % 2 === 1 ? '.' : '…'}`;
  const sandboxBaseFen = fenAtPly(basePly);

  const resetSandbox = () => {
    if (!sandbox) return;
    soundManager.playMove();
    setSandbox((prev) => prev ? { ...prev, moves: [], cursor: 0, fen: sandboxBaseFen, loading: true } : null);
  };

  const transportCurrent = sandbox
    ? (sandbox.moves.length > 0 ? sandbox.cursor : sandbox.basePly)
    : currentPlyIndex;
  const transportTotal = sandbox
    ? (sandbox.moves.length > 0 ? sandbox.moves.length : totalPlies)
    : totalPlies;

  const startAnalysis = () => {
    botGenerationRef.current += 1;
    retryGenerationRef.current += 1;
    setPlaying(false);
    setSandbox(null);
    setRetryState(null);
    setBotState(null);
    onStartAnalysis();
  };

  return (
    <div className="space-y-3 pb-32 lg:pb-6">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-1.5">
          <button type="button" onClick={onBackToGames} className="inline-flex items-center gap-1 rounded-xl border border-slate-800 bg-slate-900/70 px-2.5 py-1.5 text-xs font-semibold text-slate-300">
            <ArrowLeft className="w-3.5 h-3.5" /> Games
          </button>
          <button type="button" onClick={onOpenInsights} className="inline-flex items-center gap-1 rounded-xl border border-slate-800 bg-slate-900/70 px-2.5 py-1.5 text-xs font-semibold text-slate-300">
            <BarChart3 className="w-3.5 h-3.5 text-cyan-400" /> Insights
          </button>
          <button type="button" onClick={onOpenVault} className="inline-flex items-center gap-1 rounded-xl border border-cyan-500/25 bg-cyan-500/10 px-2.5 py-1.5 text-xs font-semibold text-cyan-200">
            <Gem className="w-3.5 h-3.5" /> Vault
          </button>
        </div>

        <div className="flex items-center gap-1.5">
          <div className="inline-flex rounded-xl border border-slate-800 bg-slate-900/70 p-0.5 text-[11px] font-bold">
            {([14, 18] as AnalysisDepthPreset[]).map((d) => (
              <button key={d} type="button" disabled={analyzing} onClick={() => onDepthPresetChange(d)} className={`rounded-lg px-2 py-1 ${depthPreset === d ? 'bg-cyan-500/20 text-cyan-300' : 'text-slate-400'}`}>
                D{d}
              </button>
            ))}
          </div>
          {analyzing ? (
            <button type="button" onClick={onCancelAnalysis} className="inline-flex items-center gap-1 rounded-xl border border-red-500/40 bg-red-500/20 px-2.5 py-1.5 text-xs font-bold text-red-300">
              <StopIcon className="w-3.5 h-3.5" /> Stop
            </button>
          ) : (
            <button type="button" onClick={startAnalysis} className="inline-flex items-center gap-1 rounded-xl bg-gradient-to-r from-cyan-400 to-emerald-400 px-3 py-1.5 text-xs font-extrabold text-slate-950">
              <Sparkles className="w-3.5 h-3.5" /> {analyzed ? 'Re-run' : 'Analyze'}
            </button>
          )}
        </div>
      </div>

      <div className="flex items-center justify-between gap-2 text-[11px] text-slate-400">
        <span className="truncate">
          <span className="font-semibold text-slate-200">{game.white.name}</span> vs <span className="font-semibold text-slate-200">{game.black.name}</span>
          {game.rated && <span className="ml-1.5 rounded bg-slate-800 px-1 py-0.5 text-[9px] text-slate-400">rated</span>}
        </span>
        <span className="shrink-0 text-[10px] text-slate-500">{game.timeControlLabel} · {game.resultString} · {game.openingEco}</span>
      </div>

      {analyzing && progress && (() => {
        const pct = Math.max(
          2,
          Math.min(100, progress.percent ?? Math.round((progress.done / Math.max(1, progress.total)) * 100))
        );
        return (
          <div className="glass-card border-teal-400/35 p-2.5">
            <div className="flex items-center justify-between gap-2 text-xs">
              <div className="flex min-w-0 flex-1 items-center gap-2 font-semibold text-teal-200">
                <span className="radar-sweep h-4 w-4 shrink-0" aria-hidden="true" />
                <span className="truncate">{progress.stageLabel || `Stockfish WASM · Two-Pass D${depthPreset}`}</span>
              </div>
              <div className="flex shrink-0 items-center gap-1.5 font-mono text-[11px] tabular-nums">
                <span className="text-slate-400">{progress.done}/{progress.total}</span>
                <span className="font-bold text-brilly">{pct}%</span>
              </div>
            </div>
            <div
              className="mt-1.5 tractor-beam-track h-2 w-full"
              role="progressbar"
              aria-label="Game analysis progress"
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={pct}
            >
              <div className="tractor-beam-fill" style={{ width: `${pct}%` }} />
            </div>
          </div>
        );
      })()}

      <div className="grid items-start gap-3 lg:grid-cols-[minmax(0,1fr)_minmax(420px,500px)] xl:gap-5">
        <section className="min-w-0">
          <div className="mx-auto w-full lg:max-w-[calc(100dvh-19rem)]">
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

            <div className="mt-1.5 flex items-stretch gap-1.5 sm:gap-2">
              <EvalBar score={activeScore} orientation={orientation} />
              <div className="relative min-w-0 flex-1" ref={boardRef}>
                <ChessgroundBoard
                  fen={activeFen}
                  orientation={orientation}
                  lastMove={botState ? botState.lastMove : retryState ? undefined : sandbox ? sandboxLastMove : reviewLastMove}
                  interactive={boardInteractive}
                  turnColor={boardTurnColor}
                  bestMoveUci={bestArrow}
                  playedMoveUci={playedArrow}
                  threatMoveUci={threatArrow}
                  showBestArrow={showBestArrow}
                  showPlayedArrow={showPlayedArrow}
                  showThreatArrow={Boolean(threatArrow)}
                  badgeSquare={!botState && !retryState && !sandbox ? currentPly?.to : undefined}
                  badgeClassification={!botState && !retryState && !sandbox ? currentPly?.classification : undefined}
                  theme={boardTheme}
                  onUserMove={handleBoardMove}
                  onSwipePrev={handleNavPrev}
                  onSwipeNext={handleNavNext}
                />

                {sandbox && (
                  <div className="pointer-events-none absolute left-2 top-2 z-30 inline-flex items-center gap-1 rounded-full border border-fuchsia-400/40 bg-[#1a0b24]/[0.85] px-2 py-1 text-[9px] font-black uppercase tracking-wider text-fuchsia-200 backdrop-blur">
                    <FlaskConical className="w-3 h-3" /> What if? · ply {sandbox.basePly}
                  </div>
                )}
                {(sandbox?.loading || (botState?.thinking ?? false)) && (
                  <div className="pointer-events-none absolute right-2 top-2 z-30 inline-flex items-center gap-1 rounded-full border border-cyan-400/30 bg-slate-950/80 px-2 py-1 text-[9px] font-bold text-cyan-200 backdrop-blur">
                    <Loader2 className="w-3 h-3 animate-spin" /> thinking
                  </div>
                )}

                {pendingPromo && (
                  <div className="absolute inset-0 z-40 flex items-center justify-center rounded-xl bg-slate-950/75 backdrop-blur-sm">
                    <div className="glass-card-strong flex gap-2 rounded-2xl border border-slate-700 p-3">
                      {(['q', 'r', 'b', 'n'] as PieceSymbol[]).map((p) => (
                        <button
                          key={p}
                          type="button"
                          onClick={() => {
                            const { from, to, mode } = pendingPromo;
                            setPendingPromo(null);
                            if (mode === 'retry') void executeRetryMove(from, to, p);
                            else if (mode === 'bot') void executeBotUserMove(from, to, p);
                            else applySandboxMove(from, to, p);
                          }}
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

            {sandbox && (
              <div className="mt-1.5 space-y-1.5">
                <div className="flex items-center gap-1.5">
                  <span className="inline-flex items-center gap-1 rounded-lg border border-fuchsia-400/30 bg-fuchsia-500/10 px-2 py-1 text-[10px] font-black text-fuchsia-200">
                    <FlaskConical className="h-3 w-3" /> {sandbox.cursor}/{sandbox.moves.length} explored
                  </span>
                  <button
                    type="button"
                    onClick={handleNavPrev}
                    disabled={sandbox.cursor === 0 && sandbox.basePly === 0}
                    className="inline-flex flex-1 items-center justify-center gap-1 rounded-xl border border-fuchsia-400/40 bg-fuchsia-500/10 px-2 py-2 text-[11px] font-black text-fuchsia-100 active:bg-fuchsia-500/20 disabled:opacity-40"
                  >
                    ← Back
                  </button>
                  <button
                    type="button"
                    onClick={handleNavNext}
                    disabled={sandbox.moves.length > 0 ? sandbox.cursor >= sandbox.moves.length : sandbox.basePly >= totalPlies}
                    className="inline-flex flex-1 items-center justify-center gap-1 rounded-xl border border-fuchsia-400/40 bg-fuchsia-500/10 px-2 py-2 text-[11px] font-black text-fuchsia-100 active:bg-fuchsia-500/20 disabled:opacity-40"
                  >
                    Forward →
                  </button>
                  <button
                    type="button"
                    onClick={resetSandbox}
                    disabled={sandbox.moves.length === 0}
                    className="inline-flex items-center justify-center gap-1 rounded-xl border border-slate-700 bg-slate-900/80 px-2.5 py-2 text-[11px] font-bold text-slate-200 active:bg-slate-800 disabled:opacity-40"
                  >
                    <RotateCcw className="h-3.5 w-3.5" />
                  </button>
                  <button
                    type="button"
                    onClick={() => setSandbox(null)}
                    className="inline-flex items-center justify-center gap-1 rounded-xl border border-rose-500/35 bg-rose-500/10 px-2.5 py-2 text-[11px] font-black text-rose-200 active:bg-rose-500/20"
                  >
                    <X className="h-3.5 w-3.5" /> Exit
                  </button>
                </div>

                {sandbox.moves.length > 0 && (
                  <div className="flex flex-wrap items-center gap-1 rounded-xl border border-fuchsia-400/20 bg-void/60 px-2 py-1.5">
                    <button
                      type="button"
                      onClick={() => applySandboxNav({ ...sandbox, cursor: 0 })}
                      className={`rounded-md px-1.5 py-0.5 font-mono text-[10px] font-bold transition ${
                        sandbox.cursor === 0
                          ? 'bg-fuchsia-500/30 text-fuchsia-100 ring-1 ring-fuchsia-400/60'
                          : 'text-slate-400 hover:text-slate-200'
                      }`}
                    >
                      Base
                    </button>
                    {sandbox.moves.map((m, i) => {
                      const plyNum = sandbox.basePly + i;
                      const active = sandbox.cursor === i + 1;
                      return (
                        <button
                          key={`${m.uci}-${i}`}
                          type="button"
                          onClick={() => applySandboxNav({ ...sandbox, cursor: i + 1 })}
                          className={`rounded-md px-1.5 py-0.5 font-mono text-[10px] font-bold transition ${
                            active
                              ? 'bg-fuchsia-500/30 text-fuchsia-100 ring-1 ring-fuchsia-400/60'
                              : 'text-slate-300 hover:bg-slate-800'
                          }`}
                        >
                          {plyNum % 2 === 0 ? `${Math.floor(plyNum / 2) + 1}.` : i === 0 ? `${Math.floor(plyNum / 2) + 1}…` : ''}
                          {m.san}
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>
            )}

            <div className="mt-1.5">
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
            </div>

            <div className="mt-2 hidden lg:block">
              <TransportControls
                variant="desktop"
                current={transportCurrent}
                total={transportTotal}
                playing={playing}
                speed={speed}
                canRetry={isMistake && !botState && !retryState && !sandbox}
                onFirst={handleNavFirst}
                onPrev={handleNavPrev}
                onNext={handleNavNext}
                onLast={handleNavLast}
                onFlip={() => setOrientation((o) => (o === 'w' ? 'b' : 'w'))}
                onTogglePlay={() => {
                  if (sandbox) {
                    const atBranchEnd = sandbox.moves.length > 0 ? sandbox.cursor >= sandbox.moves.length : sandbox.basePly >= totalPlies;
                    if (!playing && atBranchEnd) handleNavFirst();
                    setPlaying((p) => !p);
                    return;
                  }
                  if (!playing && currentPlyIndex >= totalPlies) jumpToPly(0);
                  setPlaying((p) => !p);
                }}
                onToggleSpeed={() => setSpeed((s) => (s === 1 ? 2 : 1))}
                onRetry={startRetry}
              />
            </div>
          </div>
        </section>

        <aside className="min-w-0 space-y-2.5 lg:sticky lg:top-[4.75rem] lg:max-h-[calc(100dvh-5.5rem)] lg:overflow-y-auto lg:pr-1 nice-scroll">
          {botState && (
            <BotPanel
              session={botState}
              onExit={() => { botGenerationRef.current += 1; setBotState(null); }}
              onEloChange={(elo) => { setBotElo(elo); setBotState((prev) => prev ? { ...prev, elo } : null); }}
              onUndo={() => {
                setBotState((prev) => {
                  if (!prev) return null;
                  const h = prev.historyFens.slice(0, -2);
                  return { ...prev, fen: h[h.length - 1], historyFens: h, lastMove: undefined, statusText: 'Turn undone.' };
                });
              }}
            />
          )}

          {!botState && retryState && currentPly && (
            <RetryPanel
              session={retryState}
              onExit={() => { retryGenerationRef.current += 1; setRetryState(null); }}
              onReveal={() => { retryGenerationRef.current += 1; setRetryState({ active: true, fen: currentPly.beforeFen, status: 'revealed', feedback: `Best was ${currentPly.bestMoveSan}. Line: ${currentPly.bestPvSan.join(' ')}` }); }}
              onReset={() => { retryGenerationRef.current += 1; setRetryState({ active: true, fen: currentPly.beforeFen, status: 'prompt', feedback: `Position reset. Find a better move than ${currentPly.san}.` }); }}
              onNextMistake={jumpToNextMistake}
            />
          )}

          {!botState && !retryState && !sandbox && (
            <>
              <CoachCard
                game={game}
                analyzed={analyzed}
                currentPly={currentPly}
                analyzing={analyzing}
                isMistake={isMistake}
                showThreat={showThreat}
                botElo={botElo}
                onAnalyze={startAnalysis}
                onToggleThreat={() => setShowThreat((s) => !s)}
                onStartRetry={startRetry}
                onStartBot={startBot}
                onStartSandbox={startSandbox}
                onNextMistake={jumpToNextMistake}
              />
              {tablebase && (
                <div className="glass-card border-teal-400/35 p-3">
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-[10px] font-black uppercase tracking-[0.16em] text-brilly">
                      7-Piece Syzygy Tablebase
                    </span>
                    <span className="rounded-full border border-teal-400/35 bg-teal-400/10 px-2 py-0.5 font-mono text-[10px] font-bold text-teal-200">
                      {formatTablebaseWdl(tablebase.category, activeTurn).label}
                      {tablebase.dtz !== null ? ` · DTZ ${Math.abs(tablebase.dtz)}` : ''}
                    </span>
                  </div>
                  {tablebase.moves.length > 0 && (
                    <div className="mt-2 flex flex-wrap gap-1.5">
                      {tablebase.moves.slice(0, 5).map((mv) => (
                        <button
                          key={mv.uci}
                          type="button"
                          onClick={() => playExplorerSan(mv.san)}
                          className="rounded-lg border border-slate-700 bg-void/70 px-2 py-1 font-mono text-[10px] font-bold text-slate-200 hover:border-teal-400/50"
                        >
                          {mv.san} <span className="text-slate-400">({mv.category})</span>
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              )}
              <OpeningReportCard
                report={openingReport}
                repertoireDeviation={repertoireDeviation}
                onJumpToPly={jumpToPly}
                onExplorePly={beginSandboxAt}
                onPlayBookMove={beginSandboxAt}
                onBoostDeviationToFsrs={onBoostDeviationToFsrs}
                onPatchDeviationGap={onPatchDeviationGap}
              />
              <OpeningExplorer
                fen={reviewFen}
                sanHistory={activeSanHistory}
                explorerPrefs={explorerPrefs}
                onPlaySan={playExplorerSan}
              />
              <VariationExplorer
                active={false}
                baseLabel={baseLabel}
                fen={reviewFen}
                evalResult={null}
                loading={false}
                disabled={!analyzed}
                onStart={startSandbox}
                onExit={() => undefined}
                onPlayLine={playSandboxLine}
              />
            </>
          )}

          {!botState && !retryState && sandbox && (
            <>
              <OpeningExplorer
                fen={sandbox.fen}
                sanHistory={activeSanHistory}
                explorerPrefs={explorerPrefs}
                onPlaySan={playExplorerSan}
              />
              <VariationExplorer
                active
                baseLabel={baseLabel}
                fen={sandbox.fen}
                evalResult={sandbox.eval}
                loading={sandbox.loading}
                onStart={startSandbox}
                onExit={() => setSandbox(null)}
                onPlayLine={playSandboxLine}
              />
            </>
          )}

          {analyzed && (
            <EvalGraph initialEval={analyzed.initialEval} plies={analyzed.plies} currentPlyIndex={currentPlyIndex} onSelectPly={handleJumpGamePly} />
          )}

          {analyzed && <KeyMomentsBar plies={analyzed.plies} currentPlyIndex={currentPlyIndex} onJump={handleJumpGamePly} />}

          {analyzed && <AccuracyCards analyzed={analyzed} game={game} />}

          {analyzed && <MoveList plies={analyzed.plies} currentPlyIndex={currentPlyIndex} onJump={handleJumpGamePly} />}

          {!analyzed && (
            <div className="glass-card p-3 text-[11px] text-slate-400">
              <strong className="text-slate-200">Tip:</strong> analysis detects book moves, brilliancies, tactical motifs and clock-trouble blunders. Everything runs locally after the first engine boot.
            </div>
          )}

          <div className="hidden lg:flex items-center justify-center gap-1.5 pb-2 pt-1 text-[9px] text-slate-600">
            <kbd className="keycap">←</kbd><kbd className="keycap">→</kbd> step
            <kbd className="keycap">Home</kbd><kbd className="keycap">End</kbd> jump
            <kbd className="keycap">f</kbd> flip
            <kbd className="keycap">Space</kbd> auto
            <kbd className="keycap">r</kbd> retry
            <kbd className="keycap">Esc</kbd> exit
          </div>
        </aside>
      </div>

      <TransportControls
        variant="mobile"
        current={transportCurrent}
        total={transportTotal}
        playing={playing}
        speed={speed}
        canRetry={isMistake && !botState && !retryState && !sandbox}
        onFirst={handleNavFirst}
        onPrev={handleNavPrev}
        onNext={handleNavNext}
        onLast={handleNavLast}
        onFlip={() => setOrientation((o) => (o === 'w' ? 'b' : 'w'))}
        onTogglePlay={() => {
          if (sandbox) {
            const atBranchEnd = sandbox.moves.length > 0 ? sandbox.cursor >= sandbox.moves.length : sandbox.basePly >= totalPlies;
            if (!playing && atBranchEnd) handleNavFirst();
            setPlaying((p) => !p);
            return;
          }
          if (!playing && currentPlyIndex >= totalPlies) jumpToPly(0);
          setPlaying((p) => !p);
        }}
        onToggleSpeed={() => setSpeed((s) => (s === 1 ? 2 : 1))}
        onRetry={startRetry}
      />

      {celebration && (
        <AlienCelebration
          key={celebration.trigger}
          kind={celebration.kind}
          trigger={celebration.trigger}
          message={celebration.message}
          onDismiss={() => setCelebration(null)}
        />
      )}
    </div>
  );
};
