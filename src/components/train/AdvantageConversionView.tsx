import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Chess, type Square } from 'chess.js';
import {
  AlertTriangle,
  Bot,
  CheckCircle2,
  Loader2,
  RotateCcw,
  Sparkles,
  Undo2,
  Zap,
} from 'lucide-react';
import type { AnalyzedGame, BoardThemeId } from '../../types/chess';
import {
  evaluateConversionStatus,
  extractBlownLeadPositions,
  type BlownLeadPosition,
} from '../../services/advantageConversion';
import { stockfishService } from '../../engine/StockfishService';
import { maiaService } from '../../engine/MaiaService';
import {
  fetchLichessTablebase,
  formatTablebaseWdl,
  isTablebaseEligible,
  type TablebaseResult,
} from '../../services/tablebaseApi';
import { uciToSquares } from '../../utils/chessMath';
import { soundManager } from '../../utils/sound';
import { useVibe } from '../../utils/vibeCopy';
import { ChessgroundBoard } from '../ChessgroundBoard';

interface Props {
  analyzedGames: AnalyzedGame[];
  username: string;
  boardTheme: BoardThemeId;
  convertedIds: string[];
  focusedPosition?: BlownLeadPosition | null;
  onMarkConverted: (positionId: string) => Promise<void>;
  onOpenGames: () => void;
  onOpenGame: (gameId: string, ply: number) => void;
}

export const AdvantageConversionView: React.FC<Props> = ({
  analyzedGames,
  username,
  boardTheme,
  convertedIds,
  focusedPosition,
  onMarkConverted,
  onOpenGames,
  onOpenGame,
}) => {
  const { copy } = useVibe();
  const positions = useMemo(
    () => extractBlownLeadPositions(analyzedGames, username),
    [analyzedGames, username]
  );

  const [selectedId, setSelectedId] = useState<string>('');
  const [fen, setFen] = useState('');
  const [historyFens, setHistoryFens] = useState<string[]>([]);
  const [lastMove, setLastMove] = useState<[string, string] | undefined>(undefined);
  const [botElo, setBotElo] = useState(1400);
  const [thinking, setThinking] = useState(false);
  const [evalPawns, setEvalPawns] = useState<number>(3.0);
  const [verdict, setVerdict] = useState<'holding' | 'slipping' | 'won' | 'lost'>('holding');
  const [statusText, setStatusText] = useState('');
  const [everSlipped, setEverSlipped] = useState(false);
  const [tablebase, setTablebase] = useState<TablebaseResult | null>(null);
  const genRef = useRef(0);

  const activePos = useMemo(() => {
    if (focusedPosition) return focusedPosition;
    return positions.find((p) => p.id === selectedId) ?? positions[0] ?? null;
  }, [focusedPosition, positions, selectedId]);

  useEffect(() => {
    const checkFen = fen || activePos?.fen || '';
    if (!checkFen || !isTablebaseEligible(checkFen)) {
      setTablebase(null);
      return;
    }
    let cancelled = false;
    void fetchLichessTablebase(checkFen).then((res) => {
      if (!cancelled) setTablebase(res);
    });
    return () => { cancelled = true; };
  }, [fen, activePos?.fen]);

  const loadPosition = (pos: BlownLeadPosition) => {
    genRef.current += 1;
    setSelectedId(pos.id);
    setFen(pos.fen);
    setHistoryFens([pos.fen]);
    setLastMove(undefined);
    setBotElo(Math.min(2200, Math.max(1000, Math.round(pos.opponentRating / 100) * 100 || 1400)));
    setThinking(false);
    setEvalPawns(pos.peakEvalPawns);
    setVerdict('holding');
    setEverSlipped(false);
    setStatusText(
      `Convert this +${pos.peakEvalPawns.toFixed(1)} advantage vs Stockfish ${Math.round(pos.opponentRating / 100) * 100 || 1400}. Reach mate or +8.0 without slipping below +1.5!`
    );
  };

  useEffect(() => {
    if (activePos && activePos.id !== selectedId) {
      loadPosition(activePos);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activePos?.id]);

  const handleUserMove = async (from: Square, to: Square) => {
    if (!activePos || thinking || verdict === 'won' || verdict === 'lost') return;
    soundManager.unlock();
    const gen = genRef.current;
    const chess = new Chess(fen);
    let mv;
    try {
      mv = chess.move({ from, to, promotion: 'q' });
    } catch {
      return;
    }

    const afterUserFen = chess.fen();
    setFen(afterUserFen);
    setLastMove([mv.from, mv.to]);
    setHistoryFens((h) => [...h, afterUserFen]);

    if (chess.isGameOver()) {
      if (chess.isCheckmate()) {
        soundManager.playBrilliantChord();
        setVerdict('won');
        setEvalPawns(99);
        setStatusText(`${copy.advantageConversionShort} locked — Checkmate! Advantage cleanly converted.`);
        await onMarkConverted(activePos.id);
      } else {
        soundManager.playHullThud();
        setVerdict('lost');
        setStatusText('Game ended in a draw — rewind and keep the winning bind!');
      }
      return;
    }

    if (mv.captured) soundManager.playCapture();
    else soundManager.playMove();

    setThinking(true);
    setStatusText(`Stockfish (${botElo}) defending…`);
    try {
      const { moveUci: botUci, engine: botEngine } = await maiaService.getSmartBotMove(afterUserFen, botElo);
      if (genRef.current !== gen) return;
      const parsed = uciToSquares(botUci);
      if (!parsed) {
        setThinking(false);
        return;
      }
      const bc = new Chess(afterUserFen);
      const bmv = bc.move({ from: parsed.from, to: parsed.to, promotion: parsed.promotion });
      const afterBotFen = bc.fen();
      setFen(afterBotFen);
      setLastMove([bmv.from, bmv.to]);
      setHistoryFens((h) => [...h, afterBotFen]);

      if (bc.isGameOver()) {
        if (bc.isCheckmate()) {
          soundManager.playHullThud();
          setVerdict('lost');
          setStatusText('Checkmated by the defender — reset and simplify cleanly!');
        } else {
          soundManager.playError();
          setVerdict('lost');
          setStatusText('Stalemate / Draw! Rewind and convert cleanly.');
        }
        return;
      }

      // Evaluate position with Stockfish to check Tractor Beam bounds (+1.5 floor, +8.0 lock)
      const evalRes = await stockfishService.analyzePosition(afterBotFen, { depth: 10, multiPv: 1, timeoutMs: 8000 });
      if (genRef.current !== gen) return;
      const check = evaluateConversionStatus(evalRes.score, activePos.userColor, false);
      setEvalPawns(check.pawns);

      const defenderName = botEngine === 'maia' ? `Maia ${botElo}` : `Bot`;
      if (check.verdict === 'won') {
        soundManager.playBrilliantChord();
        setVerdict('won');
        setStatusText(
          everSlipped
            ? `Converted (+${check.pawns.toFixed(1)})! Next time try keeping it above +1.5 the whole way.`
            : `${copy.advantageConversionShort} locked (+${check.pawns.toFixed(1)})! Clean conversion!`
        );
        await onMarkConverted(activePos.id);
      } else if (check.verdict === 'slipping') {
        soundManager.playHullThud();
        setEverSlipped(true);
        setVerdict('slipping');
        setStatusText(
          `${copy.advantageConversionShort} slipping! Eval dropped to ${check.pawns >= 0 ? '+' : ''}${check.pawns.toFixed(1)} (< +1.5). Rewind a move or fight back!`
        );
      } else {
        setVerdict('holding');
        setStatusText(`${defenderName} played ${bmv.san}. Advantage holding at +${check.pawns.toFixed(1)} — keep simplifying!`);
      }
    } finally {
      if (genRef.current === gen) setThinking(false);
    }
  };

  const rewindTurn = () => {
    if (historyFens.length <= 1) return;
    genRef.current += 1;
    const nextHist = historyFens.slice(0, Math.max(1, historyFens.length - 2));
    setHistoryFens(nextHist);
    setFen(nextHist[nextHist.length - 1]);
    setLastMove(undefined);
    setThinking(false);
    setVerdict('holding');
    setStatusText('Rewound one full turn — find the cleaner consolidating move!');
  };

  if (positions.length === 0 && !focusedPosition) {
    return (
      <div className="glass-card p-6 text-center">
        <Zap className="mx-auto h-9 w-9 text-slate-600" />
        <h3 className="mt-2 text-sm font-extrabold text-white">No blown-lead games found yet</h3>
        <p className="mx-auto mt-1 max-w-md text-xs text-slate-400">
          Analyze games where you reached ≥ +2.5 (or ≤ -2.5 as Black) and let the win slip. They appear here for live conversion drills against a rating-capped bot.
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

  const beamFillPct = Math.max(0, Math.min(100, Math.round((evalPawns / 8) * 100)));

  return (
    <div className="space-y-3">
      {!focusedPosition && (
        <section className="glass-card glass-card-strong p-3.5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-brilly">
                <Zap className="h-4 w-4" /> {copy.advantageConversion}
              </div>
              <p className="mt-0.5 text-[11px] text-slate-400">
                {positions.length} blown-lead position{positions.length === 1 ? '' : 's'} extracted · {convertedIds.length} locked in
              </p>
            </div>
          </div>

          <div className="mt-2.5 flex gap-1.5 overflow-x-auto pb-1 nice-scroll">
            {positions.slice(0, 10).map((pos) => {
              const active = activePos?.id === pos.id;
              const converted = convertedIds.includes(pos.id);
              return (
                <button
                  key={pos.id}
                  type="button"
                  onClick={() => loadPosition(pos)}
                  className={`shrink-0 rounded-xl border px-2.5 py-1.5 text-left text-[10px] transition ${
                    active
                      ? 'border-teal-400/60 bg-teal-400/15 text-teal-100'
                      : 'border-slate-800 bg-void/60 text-slate-300 hover:border-slate-600'
                  }`}
                >
                  <div className="flex items-center gap-1.5 font-bold">
                    <span className="font-mono text-brilly">+{pos.peakEvalPawns.toFixed(1)}</span>
                    <span>vs {pos.opponentName}</span>
                    {converted && <CheckCircle2 className="h-3 w-3 text-clean" />}
                  </div>
                  <div className="text-[9px] text-slate-500">
                    Move {pos.moveNumber} · ended {pos.finalResult}
                  </div>
                </button>
              );
            })}
          </div>
        </section>
      )}

      {activePos && (
        <div className="grid gap-3 lg:grid-cols-[minmax(0,400px)_minmax(0,1fr)]">
          <div className="glass-card glass-card-strong p-3">
            <div className="mb-2 flex items-center justify-between gap-2 text-[10px]">
              <span className="truncate font-bold text-slate-200">
                Move {activePos.moveNumber} vs {activePos.opponentName}
              </span>
              <span
                className={`font-mono font-black ${
                  verdict === 'won'
                    ? 'text-clean'
                    : verdict === 'slipping'
                      ? 'text-blunder'
                      : 'text-brilly'
                }`}
              >
                {evalPawns >= 90 ? 'MATE' : `${evalPawns >= 0 ? '+' : ''}${evalPawns.toFixed(1)}`} / +8.0
              </span>
            </div>

            <div className="mb-2 tractor-beam-track h-2 w-full">
              <div
                className="tractor-beam-fill"
                style={{
                  width: `${beamFillPct}%`,
                  background:
                    verdict === 'slipping'
                      ? 'linear-gradient(90deg, #FB7185, #FBBF24)'
                      : undefined,
                }}
              />
            </div>

            <div className="relative">
              <ChessgroundBoard
                fen={fen || activePos.fen}
                orientation={activePos.userColor}
                lastMove={lastMove}
                interactive={!thinking && verdict !== 'won' && verdict !== 'lost'}
                turnColor={activePos.userColor}
                showBestArrow={false}
                showPlayedArrow={false}
                theme={boardTheme}
                onUserMove={(from, to) => void handleUserMove(from, to)}
              />
              {thinking && (
                <div className="pointer-events-none absolute right-2 top-2 z-30 inline-flex items-center gap-1 rounded-full border border-teal-400/35 bg-void/90 px-2.5 py-1 text-[10px] font-bold text-teal-200">
                  <Loader2 className="h-3 w-3 animate-spin" /> bot thinking
                </div>
              )}
            </div>
          </div>

          <div className="glass-card p-4 space-y-3">
            <div className="flex items-center justify-between gap-2">
              <span className="inline-flex items-center gap-1.5 text-xs font-extrabold text-white">
                <Bot className="h-4 w-4 text-brilly" /> Conversion Cockpit
              </span>
              <button
                type="button"
                onClick={() => onOpenGame(activePos.gameId, activePos.ply)}
                className="text-[10px] font-bold text-brilly hover:underline"
              >
                Open original game →
              </button>
            </div>

            <div
              className={`rounded-xl border p-3 text-xs leading-relaxed ${
                verdict === 'won'
                  ? 'border-emerald-400/40 bg-emerald-500/15 text-emerald-100'
                  : verdict === 'slipping' || verdict === 'lost'
                    ? 'border-rose-400/40 bg-rose-500/15 text-rose-100'
                    : 'border-slate-800 bg-void/60 text-slate-200'
              }`}
            >
              {verdict === 'slipping' && <AlertTriangle className="mb-1 inline h-4 w-4 text-blunder mr-1" />}
              {verdict === 'won' && <CheckCircle2 className="mb-1 inline h-4 w-4 text-clean mr-1" />}
              {statusText}
            </div>

            {tablebase && (
              <div className="rounded-xl border border-teal-400/35 bg-teal-400/10 px-3 py-2 text-[11px] text-teal-200">
                <strong>Syzygy ≤7-Piece Exact:</strong>{' '}
                {formatTablebaseWdl(tablebase.category, (fen || activePos.fen).split(' ')[1] === 'b' ? 'b' : 'w').label}
                {tablebase.dtz !== null ? ` (DTZ ${Math.abs(tablebase.dtz)})` : ''}
                {tablebase.moves[0] ? ` · Best: ${tablebase.moves[0].san}` : ''}
              </div>
            )}

            <div>
              <div className="flex items-center justify-between text-[10px] font-bold text-slate-400">
                <span>Defender Strength</span>
                <span className="font-mono text-brilly">Stockfish {botElo}</span>
              </div>
              <input
                type="range"
                min={1000}
                max={2200}
                step={100}
                value={botElo}
                onChange={(e) => setBotElo(Number(e.target.value))}
                className="mt-1 w-full accent-teal-400"
              />
            </div>

            <div className="flex flex-wrap gap-2">
              <button
                type="button"
                disabled={historyFens.length <= 1 || thinking}
                onClick={rewindTurn}
                className="inline-flex items-center gap-1 rounded-xl border border-amber-400/35 bg-amber-500/10 px-3 py-2 text-[11px] font-bold text-amber-200 disabled:opacity-40"
              >
                <Undo2 className="h-3.5 w-3.5" /> Rewind Turn
              </button>
              <button
                type="button"
                onClick={() => loadPosition(activePos)}
                className="inline-flex items-center gap-1 rounded-xl border border-slate-700 bg-hull px-3 py-2 text-[11px] font-bold text-slate-200"
              >
                <RotateCcw className="h-3.5 w-3.5" /> Restart Position
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
