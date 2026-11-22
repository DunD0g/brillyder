import React, { useMemo, useState } from 'react';
import {
  CheckCircle2,
  ChevronRight,
  ExternalLink,
  FileText,
  Grid3X3,
  Layers,
  Pause,
  Play,
  RefreshCw,
  Search,
  Sparkles,
  Swords,
  X,
  Zap,
} from 'lucide-react';
import type { AnalyzedGame, GamePlatform, LichessGameRecord } from '../types/chess';
import { formatTimeAgo } from '../utils/chessMath';
import { isCustomFenGame } from '../utils/customFen';
import { resolveUserColor } from '../utils/player';
import { PLATFORM_META, platformLabel } from '../services/gameSource';

export interface BatchState {
  active: boolean;
  paused: boolean;
  total: number;
  done: number;
  currentLabel: string;
  stageLabel?: string;
  plyDone?: number;
  plyTotal?: number;
  percent: number;
}

interface Props {
  username: string;
  platform: GamePlatform;
  games: LichessGameRecord[];
  analyzedMap: Map<string, AnalyzedGame>;
  loading: boolean;
  error: string | null;
  batch: BatchState | null;
  onPlatformChange: (platform: GamePlatform) => void;
  onUsernameChange: (name: string) => void;
  onSync: (usernameOverride?: string) => void;
  onSelectGame: (game: LichessGameRecord, autoAnalyze: boolean) => void;
  onImportInput: (input: string) => Promise<void>;
  onOpenPositionEditor?: () => void;
  onBatchAnalyze: () => void;
  onBatchPauseToggle: () => void;
  onBatchCancel: () => void;
}

export const GameListView: React.FC<Props> = ({
  username,
  platform,
  games,
  analyzedMap,
  loading,
  error,
  batch,
  onPlatformChange,
  onUsernameChange,
  onSync,
  onSelectGame,
  onImportInput,
  onOpenPositionEditor,
  onBatchAnalyze,
  onBatchPauseToggle,
  onBatchCancel,
}) => {
  const [showImport, setShowImport] = useState(false);
  const [importText, setImportText] = useState('');
  const [importing, setImporting] = useState(false);
  const [importError, setImportError] = useState<string | null>(null);
  const [gameFilter, setGameFilter] = useState<'all' | 'analyzed' | 'unanalyzed' | 'brilliant' | 'losses'>('all');
  const [query, setQuery] = useState('');

  const unanalyzed = useMemo(() => games.filter((g) => !analyzedMap.has(g.id) && g.variant === 'standard' && !isCustomFenGame(g)).length, [games, analyzedMap]);

  const filteredGames = useMemo(() => {
    const q = query.trim().toLowerCase();
    return games.filter((g) => {
      const analyzed = analyzedMap.get(g.id);
      const isWhite = resolveUserColor(g, username) === 'w';
      if (gameFilter === 'analyzed' && !analyzed) return false;
      if (gameFilter === 'unanalyzed' && (analyzed || g.variant !== 'standard')) return false;
      if (gameFilter === 'brilliant') {
        const br = analyzed ? (isWhite ? analyzed.whiteSummary.counts.brilliant : analyzed.blackSummary.counts.brilliant) : 0;
        if (br <= 0) return false;
      }
      if (gameFilter === 'losses') {
        const lost = (isWhite && g.resultString === '0-1') || (!isWhite && g.resultString === '1-0');
        if (!lost) return false;
      }
      if (q) {
        const hay = `${g.white.name} ${g.black.name} ${g.openingName} ${g.openingEco} ${g.speed}`.toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
  }, [games, analyzedMap, username, gameFilter, query]);

  const handleImport = async (e: React.FormEvent) => {
    e.preventDefault();
    setImportError(null);
    setImporting(true);
    try {
      await onImportInput(importText);
      setImportText('');
      setShowImport(false);
    } catch (err) {
      setImportError(err instanceof Error ? err.message : 'Could not import game.');
    } finally {
      setImporting(false);
    }
  };

  return (
    <div className="space-y-4 pb-24">
      <section className="glass-card p-3.5 shadow-xl">
        <div className="flex items-center justify-between gap-2">
          <div className="inline-flex rounded-xl border border-slate-800 bg-slate-950/60 p-0.5">
            {(['lichess', 'chesscom'] as GamePlatform[]).map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => onPlatformChange(p)}
                className={`rounded-lg px-3 py-1.5 text-[11px] font-black transition ${
                  platform === p ? 'bg-cyan-500/20 text-cyan-200 shadow-sm' : 'text-slate-400 hover:text-slate-200'
                }`}
              >
                {PLATFORM_META[p].label}
              </button>
            ))}
          </div>
          <div className="flex items-center gap-1.5">
            {onOpenPositionEditor && (
              <button
                type="button"
                onClick={onOpenPositionEditor}
                title="Set up custom board or paste a FEN to analyze"
                className="inline-flex items-center gap-1 rounded-lg border border-slate-800 bg-slate-950/70 px-2 py-1.5 text-[11px] font-semibold text-slate-300 transition hover:border-teal-400/40 hover:text-teal-200"
              >
                <Grid3X3 className="h-3.5 w-3.5 text-brilly" />
                <span className="hidden sm:inline">Board / FEN</span>
                <span className="sm:hidden">FEN</span>
              </button>
            )}
            <button
              type="button"
              onClick={() => setShowImport((v) => !v)}
              className="inline-flex items-center gap-1.5 rounded-lg border border-cyan-500/20 bg-cyan-500/10 px-2 py-1.5 text-xs font-semibold text-cyan-300"
            >
              <FileText className="w-3.5 h-3.5" />
              {showImport ? 'Close' : 'Paste PGN'}
            </button>
          </div>
        </div>

        <form onSubmit={(e) => { e.preventDefault(); onSync(username); }} className="mt-2.5 space-y-2.5">
          <label htmlFor="sync-user" className="flex items-center justify-between text-[10px] font-bold uppercase tracking-[0.16em] text-slate-400">
            <span>{platformLabel(platform)} auto-sync</span>
            <span className="font-mono text-[9px] normal-case tracking-normal text-slate-500">on-device analysis</span>
          </label>
          <div className="flex gap-2">
            <div className="relative flex-1">
              <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
              <input
                id="sync-user"
                type="text"
                value={username}
                onChange={(e) => onUsernameChange(e.target.value)}
                placeholder={`${platformLabel(platform)} username…`}
                autoCapitalize="none"
                autoCorrect="off"
                spellCheck={false}
                className="w-full rounded-xl border border-slate-700/80 bg-slate-950 py-2.5 pl-9 pr-3 text-sm text-slate-100 placeholder-slate-500 focus:border-cyan-400 focus:outline-none"
              />
            </div>
            <button
              type="submit"
              disabled={loading}
              className="inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-cyan-400 to-emerald-400 px-4 py-2.5 text-sm font-bold text-slate-950 shadow active:scale-[0.98] disabled:opacity-60"
            >
              <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
              <span>{loading ? 'Syncing' : 'Sync'}</span>
            </button>
          </div>
        </form>

        {showImport && (
          <form onSubmit={handleImport} className="mt-3 space-y-2 border-t border-slate-800 pt-3">
            <textarea
              rows={4}
              value={importText}
              onChange={(e) => setImportText(e.target.value)}
              placeholder="Paste raw PGN from Chess.com, Lichess, a tournament — or a Lichess game URL…"
              className="w-full rounded-xl border border-slate-700/80 bg-slate-950 p-2.5 font-mono text-xs text-slate-100 placeholder-slate-500 focus:border-cyan-400 focus:outline-none"
            />
            {importError && <p className="text-xs text-red-400">{importError}</p>}
            <div className="flex justify-end">
              <button
                type="submit"
                disabled={importing || !importText.trim()}
                className="rounded-xl border border-cyan-500/40 bg-cyan-500/20 px-3.5 py-2 text-xs font-bold text-cyan-200 disabled:opacity-50"
              >
                {importing ? 'Loading…' : 'Load game'}
              </button>
            </div>
          </form>
        )}

        {error && <div className="mt-3 rounded-xl border border-red-500/30 bg-red-500/10 px-3 py-2 text-xs text-red-300">{error}</div>}
      </section>

      <section className="glass-card overflow-hidden">
        <div className="flex flex-col gap-2.5 p-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="min-w-0">
            <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
              <Layers className="h-4 w-4 shrink-0 text-cyan-400" />
              <span className="truncate">Batch analyze</span>
              <span className="shrink-0 rounded bg-slate-800 px-1.5 py-0.5 font-mono text-[9px] text-slate-400">{unanalyzed} queued</span>
            </div>
            <p className="mt-0.5 text-[11px] leading-snug text-slate-400">Next 5 unanalyzed games, back-to-back with pause and cancel.</p>
          </div>
          {!batch?.active ? (
            <button
              type="button"
              onClick={onBatchAnalyze}
              disabled={unanalyzed === 0 || loading}
              className="inline-flex w-full shrink-0 items-center justify-center gap-1.5 rounded-xl border border-emerald-500/35 bg-emerald-500/15 px-3 py-2 text-[11px] font-bold text-emerald-200 transition hover:bg-emerald-500/25 active:scale-[0.98] disabled:opacity-40 sm:w-auto"
            >
              <Play className="h-3.5 w-3.5 shrink-0" /> Batch next 5
            </button>
          ) : (
            <div className="grid grid-cols-2 gap-1.5 sm:flex sm:shrink-0 sm:items-center">
              <button
                type="button"
                onClick={onBatchPauseToggle}
                className="inline-flex items-center justify-center gap-1 rounded-xl border border-amber-500/35 bg-amber-500/15 px-2.5 py-2 text-[11px] font-bold text-amber-200 transition hover:bg-amber-500/25 active:scale-[0.98]"
              >
                {batch.paused ? <Play className="h-3.5 w-3.5 shrink-0" /> : <Pause className="h-3.5 w-3.5 shrink-0" />}
                <span>{batch.paused ? 'Resume' : 'Pause'}</span>
              </button>
              <button
                type="button"
                onClick={onBatchCancel}
                className="inline-flex items-center justify-center gap-1 rounded-xl border border-red-500/35 bg-red-500/15 px-2.5 py-2 text-[11px] font-bold text-red-300 transition hover:bg-red-500/25 active:scale-[0.98]"
              >
                <X className="h-3.5 w-3.5 shrink-0" />
                <span>Cancel</span>
              </button>
            </div>
          )}
        </div>
        {batch?.active && (
          <div className="border-t border-slate-800/80 bg-slate-950/35 px-3 py-2.5">
            <div className="flex items-center justify-between gap-2 text-[11px]">
              <div className="flex min-w-0 flex-1 items-center gap-2">
                {batch.paused ? (
                  <Pause className="h-3.5 w-3.5 shrink-0 text-amber-300" />
                ) : (
                  <span className="radar-sweep h-3.5 w-3.5 shrink-0" aria-hidden="true" />
                )}
                <span className={`truncate font-semibold ${batch.paused ? 'text-amber-200' : 'text-teal-200'}`}>
                  {batch.paused
                    ? `Paused · ${batch.currentLabel || 'Waiting…'}`
                    : batch.currentLabel || 'Preparing engine…'}
                </span>
              </div>
              <div className="flex shrink-0 items-center gap-1.5 font-mono text-[11px] tabular-nums">
                <span className="rounded bg-slate-800/90 px-1.5 py-0.5 text-[10px] font-bold text-slate-300">
                  {Math.min(batch.done + 1, batch.total)}/{batch.total}
                </span>
                <span className="font-bold text-brilly">{batch.percent}%</span>
              </div>
            </div>
            <div
              className="mt-2 tractor-beam-track h-2.5 w-full"
              role="progressbar"
              aria-label="Batch analysis progress"
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={batch.percent}
            >
              <div
                className={`tractor-beam-fill ${batch.paused ? 'opacity-60' : ''}`}
                style={{ width: `${Math.max(2, Math.min(100, batch.percent))}%` }}
              />
            </div>
            <div className="mt-1.5 flex items-center justify-between gap-2 text-[10px] text-slate-400">
              <span className="min-w-0 truncate font-medium">
                {batch.paused
                  ? 'Paused — tap Resume to continue'
                  : batch.stageLabel || 'Initializing Stockfish WASM…'}
              </span>
              <span className="shrink-0 font-mono tabular-nums text-slate-400">
                {typeof batch.plyDone === 'number' && typeof batch.plyTotal === 'number' && batch.plyTotal > 0
                  ? `${batch.plyDone}/${batch.plyTotal} pos`
                  : `${batch.done}/${batch.total} done`}
              </span>
            </div>
          </div>
        )}
      </section>

      <section className="space-y-2.5">
        <div className="flex flex-wrap items-center justify-between gap-2 px-1">
          <h2 className="text-xs font-bold uppercase tracking-wider text-slate-400">
            Recent games ({filteredGames.length}{filteredGames.length !== games.length ? ` / ${games.length}` : ''})
          </h2>
          <span className="text-[10px] text-slate-500">{platformLabel(platform)} · Stockfish WASM</span>
        </div>

        {games.length > 0 && (
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-center gap-1 overflow-x-auto pb-0.5 nice-scroll">
              {([
                ['all', 'All'],
                ['analyzed', 'Analyzed'],
                ['unanalyzed', 'To analyze'],
                ['brilliant', '!! Brilliant'],
                ['losses', 'Losses'],
              ] as const).map(([key, label]) => (
                <button
                  key={key}
                  type="button"
                  onClick={() => setGameFilter(key)}
                  className={`shrink-0 rounded-full border px-2.5 py-1 text-[10px] font-bold transition ${
                    gameFilter === key
                      ? 'border-teal-400/50 bg-teal-400/15 text-teal-200'
                      : 'border-slate-800 bg-hull/65 text-slate-400 hover:border-slate-600 hover:text-slate-200'
                  }`}
                >
                  {label}
                </button>
              ))}
            </div>
            <div className="relative sm:w-52">
              <Search className="pointer-events-none absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-slate-500" />
              <input
                type="text"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Filter opponent or opening…"
                className="w-full rounded-xl border border-slate-800 bg-void/75 py-1.5 pl-8 pr-7 text-xs text-slate-200 placeholder-slate-500 focus:border-teal-400/60 focus:outline-none"
              />
              {query && (
                <button
                  type="button"
                  onClick={() => setQuery('')}
                  aria-label="Clear game search"
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-slate-500 hover:text-slate-200"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              )}
            </div>
          </div>
        )}

        {games.length === 0 && !loading && (
          <div className="glass-card p-6 text-center">
            <Swords className="mx-auto h-7 w-7 text-slate-600" />
            <h3 className="mt-2 text-sm font-bold text-slate-200">No {platformLabel(platform)} games loaded</h3>
            <p className="mt-1 text-xs text-slate-400">Enter a username above and hit Sync. Chess.com uses the public archives API; nothing leaves your device after download.</p>
          </div>
        )}

        {games.length > 0 && filteredGames.length === 0 && (
          <div className="glass-card p-5 text-center">
            <p className="text-xs font-semibold text-slate-300">No games match this filter.</p>
            <button
              type="button"
              onClick={() => { setGameFilter('all'); setQuery(''); }}
              className="mt-2 rounded-lg border border-teal-400/35 bg-teal-400/10 px-3 py-1 text-[11px] font-bold text-teal-200"
            >
              Reset filters
            </button>
          </div>
        )}

        <div className="grid grid-cols-1 gap-2.5 md:grid-cols-2 lg:grid-cols-3">
          {filteredGames.map((g) => {
            const isWhite = resolveUserColor(g, username) === 'w';
            const me = isWhite ? g.white : g.black;
            const opp = isWhite ? g.black : g.white;
            const res =
              g.resultString === '1/2-1/2' ? 'DRAW' : (isWhite && g.resultString === '1-0') || (!isWhite && g.resultString === '0-1') ? 'WIN' : g.resultString === '*' ? 'GAME' : 'LOSS';
            const badgeCls =
              res === 'WIN' ? 'border-emerald-500/30 bg-emerald-500/15 text-emerald-300' : res === 'LOSS' ? 'border-red-500/30 bg-red-500/15 text-red-300' : 'border-slate-600/40 bg-slate-700/40 text-slate-300';
            const edgeCls =
              res === 'WIN' ? 'border-l-2 border-l-emerald-400/60' : res === 'LOSS' ? 'border-l-2 border-l-rose-400/60' : 'border-l-2 border-l-slate-600/60';
            const analyzed = analyzedMap.get(g.id);
            const isVariant = g.variant !== 'standard';

            return (
              <div key={g.id} className={`glass-card glass-card-hover flex min-w-0 flex-col p-3.5 ${edgeCls}`}>
                <div className="flex flex-wrap items-center gap-1.5">
                  <span className={`rounded-md border px-2 py-0.5 text-[10px] font-extrabold ${badgeCls}`}>{res}</span>
                  <span className="inline-flex items-center gap-1 rounded bg-slate-800/90 px-1.5 py-0.5 font-mono text-[11px] text-slate-300">
                    <Zap className="h-3 w-3 text-amber-400" /> {g.timeControlLabel}
                  </span>
                  <span className="text-[10px] capitalize text-slate-400">{g.speed}</span>
                  {analyzed && (
                    <span className="inline-flex items-center gap-1 rounded bg-cyan-500/10 px-1.5 py-0.5 text-[10px] font-semibold text-cyan-300">
                      <CheckCircle2 className="h-3 w-3" /> {(isWhite ? analyzed.whiteSummary.accuracy : analyzed.blackSummary.accuracy).toFixed(1)}%
                    </span>
                  )}
                  {analyzed && (isWhite ? analyzed.whiteSummary.counts.brilliant : analyzed.blackSummary.counts.brilliant) > 0 && (
                    <span className="rounded bg-cyan-500/15 px-1.5 py-0.5 text-[10px] font-black text-cyan-200">
                      !! {(isWhite ? analyzed.whiteSummary.counts.brilliant : analyzed.blackSummary.counts.brilliant)}
                    </span>
                  )}
                </div>

                <div className="mt-2 flex min-w-0 items-center gap-1.5 text-sm font-semibold text-slate-100">
                  <span className={`h-2.5 w-2.5 shrink-0 rounded-full border ${isWhite ? 'border-slate-300 bg-white' : 'border-slate-500 bg-slate-950'}`} />
                  <span className="truncate">{me.name}</span>
                  {me.rating && <span className="shrink-0 font-mono text-xs text-slate-400">({me.rating})</span>}
                  <Swords className="h-3.5 w-3.5 shrink-0 text-slate-500" />
                  <span className="truncate">{opp.name}</span>
                  {opp.rating && <span className="shrink-0 font-mono text-xs text-slate-400">({opp.rating})</span>}
                </div>

                <div className="mt-1 flex items-center justify-between gap-2 text-xs text-slate-400">
                  <span className="truncate">{g.openingEco ? `${g.openingEco} · ` : ''}{g.openingName}</span>
                  <span className="shrink-0 text-[10px] text-slate-500">{formatTimeAgo(g.createdAt)}</span>
                </div>

                <div className="mt-auto flex items-center gap-2 pt-3">
                  <button
                    type="button"
                    disabled={isVariant}
                    onClick={() => onSelectGame(g, !analyzed)}
                    className="flex flex-1 items-center justify-center gap-1.5 rounded-xl border border-cyan-500/30 bg-cyan-500/15 px-3 py-2 text-xs font-bold text-cyan-200 hover:bg-cyan-500/25 active:scale-[0.98] disabled:opacity-40"
                  >
                    {analyzed ? <ChevronRight className="h-3.5 w-3.5" /> : <Sparkles className="h-3.5 w-3.5" />}
                    {isVariant ? `Unsupported (${g.variant})` : analyzed ? 'Open review' : 'Analyze game'}
                  </button>
                  {g.url && (
                    <a
                      href={g.url}
                      target="_blank"
                      rel="noreferrer"
                      className="rounded-xl border border-slate-700 bg-slate-800 p-2 text-slate-300"
                      aria-label={`Open on ${platformLabel(platform)}`}
                    >
                      <ExternalLink className="h-4 w-4" />
                    </a>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </section>
    </div>
  );
};
