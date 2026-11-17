import React, { useState } from 'react';
import { CheckCircle2, ExternalLink, FileText, RefreshCw, Search, Sparkles, Swords, Zap } from 'lucide-react';
import type { LichessGameRecord } from '../types/chess';
import { formatTimeAgo } from '../utils/chessMath';

interface Props {
  username: string;
  onUsernameChange: (name: string) => void;
  games: LichessGameRecord[];
  analyzedIds: Set<string>;
  loading: boolean;
  error: string | null;
  onSyncLichess: (usernameOverride?: string) => void;
  onSelectGame: (game: LichessGameRecord, autoAnalyze: boolean) => void;
  onImportInput: (input: string) => Promise<void>;
}

export const GameListView: React.FC<Props> = ({
  username,
  onUsernameChange,
  games,
  analyzedIds,
  loading,
  error,
  onSyncLichess,
  onSelectGame,
  onImportInput,
}) => {
  const [showImport, setShowImport] = useState(false);
  const [importText, setImportText] = useState('');
  const [importing, setImporting] = useState(false);
  const [importError, setImportError] = useState<string | null>(null);

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
      <section className="rounded-2xl bg-slate-900/90 border border-slate-800 p-3.5 shadow-xl">
        <form onSubmit={(e) => { e.preventDefault(); onSyncLichess(username); }} className="space-y-2.5">
          <div className="flex items-center justify-between">
            <label htmlFor="lichess-user" className="text-xs font-semibold uppercase tracking-wider text-slate-400">
              Lichess Auto-Sync
            </label>
            <button
              type="button"
              onClick={() => setShowImport((v) => !v)}
              className="inline-flex items-center gap-1.5 text-xs font-semibold text-cyan-300 px-2 py-1 rounded-lg bg-cyan-500/10 border border-cyan-500/20"
            >
              <FileText className="w-3.5 h-3.5" />
              {showImport ? 'Close' : 'Paste PGN / URL'}
            </button>
          </div>
          <div className="flex gap-2">
            <div className="relative flex-1">
              <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
              <input
                id="lichess-user"
                type="text"
                value={username}
                onChange={(e) => onUsernameChange(e.target.value)}
                placeholder="Lichess username..."
                autoCapitalize="none"
                autoCorrect="off"
                className="w-full pl-9 pr-3 py-2.5 rounded-xl bg-slate-950 border border-slate-700/80 text-sm text-slate-100 placeholder-slate-500 focus:outline-none focus:border-cyan-400"
              />
            </div>
            <button
              type="submit"
              disabled={loading}
              className="inline-flex items-center gap-1.5 px-4 py-2.5 rounded-xl bg-gradient-to-r from-cyan-400 to-emerald-400 text-slate-950 font-bold text-sm shadow active:scale-[0.98] disabled:opacity-60"
            >
              <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
              <span>{loading ? 'Syncing' : 'Sync'}</span>
            </button>
          </div>
        </form>

        {showImport && (
          <form onSubmit={handleImport} className="mt-3 pt-3 border-t border-slate-800 space-y-2">
            <textarea
              rows={4}
              value={importText}
              onChange={(e) => setImportText(e.target.value)}
              placeholder="Paste raw PGN or Lichess game URL (e.g. https://lichess.org/AbCdEfGh)..."
              className="w-full rounded-xl bg-slate-950 border border-slate-700/80 p-2.5 text-xs font-mono text-slate-100 placeholder-slate-500 focus:outline-none focus:border-cyan-400"
            />
            {importError && <p className="text-xs text-red-400">{importError}</p>}
            <div className="flex justify-end">
              <button
                type="submit"
                disabled={importing || !importText.trim()}
                className="px-3.5 py-2 rounded-xl bg-cyan-500/20 text-cyan-200 border border-cyan-500/40 text-xs font-bold disabled:opacity-50"
              >
                {importing ? 'Loading...' : 'Load Game'}
              </button>
            </div>
          </form>
        )}

        {error && <div className="mt-3 rounded-xl bg-red-500/10 border border-red-500/30 px-3 py-2 text-xs text-red-300">{error}</div>}
      </section>

      <section className="space-y-2.5">
        <div className="flex items-center justify-between px-1">
          <h2 className="text-xs font-bold uppercase tracking-wider text-slate-400">Recent Games ({games.length})</h2>
          <span className="text-[11px] text-slate-500">On-device Stockfish WASM</span>
        </div>

        {games.map((g) => {
          const isWhite = g.userColor !== 'b';
          const me = isWhite ? g.white : g.black;
          const opp = isWhite ? g.black : g.white;
          const res =
            g.resultString === '1/2-1/2' ? 'DRAW' : (isWhite && g.resultString === '1-0') || (!isWhite && g.resultString === '0-1') ? 'WIN' : g.resultString === '*' ? 'GAME' : 'LOSS';
          const badgeCls =
            res === 'WIN' ? 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30' : res === 'LOSS' ? 'bg-red-500/15 text-red-300 border-red-500/30' : 'bg-slate-700/40 text-slate-300 border-slate-600/40';
          const isCached = analyzedIds.has(g.id);
          const isVariant = g.variant !== 'standard';

          return (
            <div key={g.id} className="rounded-2xl bg-slate-900/90 border border-slate-800 p-3.5">
              <div className="flex items-center gap-2 flex-wrap">
                <span className={`px-2 py-0.5 rounded-md text-[10px] font-extrabold border ${badgeCls}`}>{res}</span>
                <span className="inline-flex items-center gap-1 text-xs font-mono px-1.5 py-0.5 rounded bg-slate-800 text-slate-300">
                  <Zap className="w-3 h-3 text-amber-400" />
                  {g.timeControlLabel}
                </span>
                <span className="text-[11px] text-slate-400 capitalize">{g.speed}</span>
                {isCached && (
                  <span className="inline-flex items-center gap-1 text-[10px] font-semibold text-cyan-300">
                    <CheckCircle2 className="w-3 h-3" /> Analyzed
                  </span>
                )}
              </div>

              <div className="mt-2 flex items-center gap-1.5 text-sm font-semibold text-slate-100">
                <span className={`w-2.5 h-2.5 rounded-full border shrink-0 ${isWhite ? 'bg-white border-slate-300' : 'bg-slate-950 border-slate-500'}`} />
                <span className="truncate">{me.name}</span>
                {me.rating && <span className="text-xs font-mono text-slate-400">({me.rating})</span>}
                <Swords className="w-3.5 h-3.5 text-slate-500 shrink-0" />
                <span className="truncate">{opp.name}</span>
                {opp.rating && <span className="text-xs font-mono text-slate-400">({opp.rating})</span>}
              </div>

              <div className="mt-1 flex items-center justify-between text-xs text-slate-400">
                <span className="truncate">{g.openingEco ? `${g.openingEco} · ` : ''}{g.openingName}</span>
                <span className="shrink-0 text-[11px] text-slate-500">{formatTimeAgo(g.createdAt)}</span>
              </div>

              <div className="mt-3 flex items-center gap-2">
                <button
                  type="button"
                  disabled={isVariant}
                  onClick={() => onSelectGame(g, !isCached)}
                  className="flex-1 inline-flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl bg-cyan-500/15 hover:bg-cyan-500/25 border border-cyan-500/30 text-cyan-200 text-xs font-bold active:scale-[0.98] disabled:opacity-40"
                >
                  <Sparkles className="w-3.5 h-3.5" />
                  {isVariant ? `Unsupported (${g.variant})` : isCached ? 'Open Review' : 'Analyze Game'}
                </button>
                {g.url && (
                  <a href={g.url} target="_blank" rel="noreferrer" className="p-2 rounded-xl bg-slate-800 text-slate-300 border border-slate-700" aria-label="Open on Lichess">
                    <ExternalLink className="w-4 h-4" />
                  </a>
                )}
              </div>
            </div>
          );
        })}
      </section>
    </div>
  );
};
