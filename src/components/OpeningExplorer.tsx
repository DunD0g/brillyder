import React, { useEffect, useMemo, useState } from 'react';
import { BookOpen, Compass, Loader2 } from 'lucide-react';
import { getBookPosition } from '../chess/openingBook';
import { fetchLichessExplorer, type ExplorerPosition } from '../services/openingExplorer';
import type { ExplorerPrefSettings } from './SettingsMenu';

interface Props {
  fen: string;
  sanHistory: string[];
  disabled?: boolean;
  explorerPrefs?: ExplorerPrefSettings;
  onPlaySan: (san: string) => void;
}

interface ExplorerRow {
  san: string;
  name: string;
  games: number;
  white: number;
  draws: number;
  black: number;
  share: number;
  lineCount: number;
}

function formatCount(value: number): string {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}M`;
  if (value >= 10_000) return `${Math.round(value / 1_000)}k`;
  if (value >= 1_000) return `${(value / 1_000).toFixed(1)}k`;
  return String(value);
}

function pct(value: number, total: number): number {
  return total > 0 ? Math.round((value / total) * 100) : 0;
}

const MoveBar: React.FC<{ row: ExplorerRow; live: boolean }> = ({ row, live }) => {
  if (live) {
    const total = Math.max(1, row.games);
    const white = pct(row.white, total);
    const draws = pct(row.draws, total);
    const black = Math.max(0, 100 - white - draws);
    return (
      <div className="mt-1">
        <div className="flex h-1.5 w-full overflow-hidden rounded-full bg-slate-800">
          <div className="h-full bg-slate-100" style={{ width: `${white}%` }} />
          <div className="h-full bg-slate-500" style={{ width: `${draws}%` }} />
          <div className="h-full border-l border-slate-700 bg-slate-950" style={{ width: `${black}%` }} />
        </div>
        <div className="mt-0.5 flex items-center justify-between text-[9px] font-mono text-slate-500">
          <span>W {white}%</span>
          <span>D {draws}%</span>
          <span>B {black}%</span>
        </div>
      </div>
    );
  }

  return (
    <div className="mt-1">
      <div className="flex h-1.5 w-full overflow-hidden rounded-full bg-slate-800">
        <div
          className="h-full rounded-full bg-gradient-to-r from-cyan-400 to-emerald-400"
          style={{ width: `${Math.max(2, Math.round(row.share * 100))}%` }}
        />
      </div>
      <div className="mt-0.5 text-[9px] text-slate-500">
        {row.lineCount} theory line{row.lineCount === 1 ? '' : 's'} · {Math.round(row.share * 100)}% of book
      </div>
    </div>
  );
};

export const OpeningExplorer: React.FC<Props> = ({ fen, sanHistory, disabled, explorerPrefs, onPlaySan }) => {
  const local = useMemo(() => getBookPosition(sanHistory), [sanHistory]);
  const [live, setLive] = useState<ExplorerPosition | null>(null);
  const [checking, setChecking] = useState(false);

  useEffect(() => {
    if (disabled) {
      setLive(null);
      setChecking(false);
      return;
    }
    let cancelled = false;
    setLive(null);
    setChecking(true);
    fetchLichessExplorer(fen, {
      ratingBand: explorerPrefs?.ratingBand,
      speeds: explorerPrefs?.speeds,
    })
      .then((data) => {
        if (!cancelled) setLive(data);
      })
      .finally(() => {
        if (!cancelled) setChecking(false);
      });
    return () => {
      cancelled = true;
    };
  }, [fen, disabled, explorerPrefs?.ratingBand, explorerPrefs?.speeds.join(',')]);

  const rows: ExplorerRow[] = live
    ? live.moves.slice(0, 10).map((move) => ({
        san: move.san,
        name: live.opening?.name ?? 'Community games',
        games: move.games,
        white: move.white,
        draws: move.draws,
        black: move.black,
        share: live.games > 0 ? move.games / live.games : 0,
        lineCount: 0,
      }))
    : local.continuations.slice(0, 10).map((move) => ({
        san: move.san,
        name: move.name,
        games: 0,
        white: 0,
        draws: 0,
        black: 0,
        share: move.share,
        lineCount: move.lineCount,
      }));

  const opening = live?.opening ?? local.recognized;
  const empty = rows.length === 0;

  return (
    <div className="glass-card border-cyan-500/25 p-3">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
            <Compass className="h-3.5 w-3.5 text-cyan-300" /> Opening Explorer
          </div>
          <div className="mt-0.5 flex items-center gap-1 text-[10px] text-slate-500">
            {checking && !live ? (
              <><Loader2 className="h-2.5 w-2.5 animate-spin text-cyan-300" /> checking Lichess</>
            ) : live ? (
              <>{formatCount(live.games)} community games</>
            ) : (
              <><BookOpen className="h-2.5 w-2.5" /> offline theory book</>
            )}
          </div>
        </div>
        <span className={`shrink-0 rounded-full border px-1.5 py-0.5 text-[8px] font-black uppercase tracking-wider ${live ? 'border-emerald-400/30 bg-emerald-500/10 text-emerald-300' : 'border-cyan-400/25 bg-cyan-500/10 text-cyan-300'}`}>
          {live ? 'Lichess' : 'Book'}
        </span>
      </div>

      {opening && (
        <div className="mt-2 flex items-center gap-1.5 rounded-lg border border-slate-800 bg-slate-950/45 px-2 py-1">
          {opening.eco && <span className="rounded bg-slate-800 px-1 py-0.5 text-[9px] font-bold text-slate-300">{opening.eco}</span>}
          <span className="min-w-0 truncate text-[10px] font-semibold text-slate-300">{opening.name}</span>
        </div>
      )}

      {empty ? (
        <div className="mt-2 rounded-xl border border-dashed border-slate-700 bg-slate-950/40 p-2.5 text-[10px] text-slate-400">
          <p className="font-bold text-slate-300">{local.inBook ? 'End of our book line' : 'Outside the opening book'}</p>
          <p className="mt-0.5 leading-relaxed">
            {local.inBook
              ? 'No recorded continuations from this position. Use What If? for engine ideas.'
              : `The game left the book at ply ${local.depth + 1}. Use What If? to explore engine continuations.`}
          </p>
        </div>
      ) : (
        <div className="mt-2 space-y-1.5">
          {rows.map((row) => (
            <button
              key={`${live ? 'live' : 'book'}-${row.san}`}
              type="button"
              disabled={disabled}
              onClick={() => onPlaySan(row.san)}
              title={`Play ${row.san} on the sandbox board`}
              className="group block w-full min-h-[44px] rounded-xl border border-slate-800 bg-slate-950/45 px-2.5 py-1.5 text-left touch-manipulation transition-colors hover:border-cyan-400/35 hover:bg-cyan-500/10 active:bg-cyan-500/15 disabled:opacity-50"
            >
              <div className="flex items-center gap-2">
                <span className="shrink-0 font-mono text-[12px] font-black text-cyan-200">{row.san}</span>
                <span className="min-w-0 flex-1 truncate text-[10px] text-slate-400">{row.name}</span>
                <span className="shrink-0 font-mono text-[10px] font-semibold text-slate-500">
                  {live ? formatCount(row.games) : `${Math.round(row.share * 100)}%`}
                </span>
              </div>
              <MoveBar row={row} live={Boolean(live)} />
            </button>
          ))}
        </div>
      )}

      <p className="mt-2 text-[9px] leading-relaxed text-slate-500">
        {live
          ? 'Tap a move to play it in the What If sandbox.'
          : 'Offline theory. Tap a move to explore it; What If? adds live engine lines.'}
      </p>
    </div>
  );
};
