import React, { useMemo, useState } from 'react';
import { Calendar, Filter, Gem, Orbit, Sparkles, UserRound } from 'lucide-react';
import type { BoardThemeId, BrillyVaultEntry, BrillyVaultStats } from '../types/chess';
import { MiniBoard } from './MiniBoard';

interface Props {
  entries: BrillyVaultEntry[];
  stats: BrillyVaultStats;
  username: string;
  boardTheme: BoardThemeId;
  onOpenEntry: (entry: BrillyVaultEntry) => void;
  onOpenGames: () => void;
}

type Scope = 'mine' | 'opponent';

export const BrillyVaultView: React.FC<Props> = ({ entries, stats, username, boardTheme, onOpenEntry, onOpenGames }) => {
  const [scope, setScope] = useState<Scope>('mine');
  const [opening, setOpening] = useState('');
  const [month, setMonth] = useState('');
  const [visible, setVisible] = useState(12);

  const filtered = useMemo(() => entries.filter((entry) => {
    if (scope === 'mine' && !entry.isUserMove) return false;
    if (scope === 'opponent' && entry.isUserMove) return false;
    if (opening && entry.openingName !== opening) return false;
    if (month) {
      const d = new Date(entry.playedAt);
      const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      if (key !== month) return false;
    }
    return true;
  }), [entries, scope, opening, month]);

  const scopeEntries = useMemo(
    () => entries.filter((entry) => (scope === 'mine' ? entry.isUserMove : !entry.isUserMove)),
    [entries, scope],
  );

  const scopeOpenings = useMemo(() => {
    const counts = new Map<string, number>();
    for (const entry of scopeEntries) counts.set(entry.openingName, (counts.get(entry.openingName) ?? 0) + 1);
    return Array.from(counts.entries())
      .map(([name, count]) => ({ name, count }))
      .sort((a, b) => b.count - a.count);
  }, [scopeEntries]);

  const scopeMonths = useMemo(() => {
    const counts = new Map<string, { label: string; count: number }>();
    for (const entry of scopeEntries) {
      const d = new Date(entry.playedAt);
      const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
      const label = d.toLocaleDateString(undefined, { month: 'short', year: 'numeric' });
      counts.set(key, { label, count: (counts.get(key)?.count ?? 0) + 1 });
    }
    return Array.from(counts.entries())
      .map(([key, value]) => ({ key, ...value }))
      .sort((a, b) => (a.key < b.key ? 1 : -1));
  }, [scopeEntries]);

  const resetVisible = () => setVisible(12);
  const switchScope = (next: Scope) => {
    setScope(next);
    setOpening('');
    setMonth('');
    resetVisible();
  };

  const scopeEmpty = scopeEntries.length === 0;

  return (
    <div className="space-y-3 pb-24">
      <section className="glass-card glass-card-strong relative overflow-hidden p-4">
        <div className="pointer-events-none absolute -right-6 -top-8 h-32 w-32 rounded-full bg-cyan-500/15 blur-2xl" />
        <div className="pointer-events-none absolute -bottom-10 left-10 h-28 w-28 rounded-full bg-fuchsia-500/10 blur-2xl" />
        <div className="relative flex items-start justify-between gap-3">
          <div>
            <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-cyan-300">
              <Orbit className="h-4 w-4" /> Brilly Vault
            </div>
            <h1 className="mt-1 text-lg font-extrabold leading-tight text-white">Certified galaxy-brain archive</h1>
            <p className="mt-1 max-w-lg text-[11px] leading-relaxed text-slate-400">
              Your <span className="font-bold text-cyan-300">!!</span> brilliant moves from analyzed games. Opponent brilliancies have their own tab and still appear in their game reviews.
            </p>
          </div>
          <div className="shrink-0 text-right">
            <div className="text-4xl font-black leading-none text-transparent bg-clip-text bg-gradient-to-br from-cyan-300 to-emerald-300">{stats.total}</div>
            <div className="mt-1 text-[9px] font-bold uppercase tracking-wider text-slate-500">your total !!</div>
          </div>
        </div>

        <div className="relative mt-3 grid grid-cols-2 gap-2 sm:grid-cols-3">
          <VaultStat icon={<UserRound className="h-3.5 w-3.5 text-cyan-300" />} label="Yours" value={stats.userMoves} />
          <VaultStat icon={<Calendar className="h-3.5 w-3.5 text-emerald-300" />} label="This month" value={stats.thisMonth} />
          <VaultStat icon={<Gem className="h-3.5 w-3.5 text-fuchsia-300" />} label="Top opener" value={stats.topUserOpening?.count ?? 0} />
        </div>
      </section>

      {entries.length === 0 ? (
        <section className="glass-card p-7 text-center">
          <Orbit className="mx-auto h-9 w-9 text-slate-600" />
          <h2 className="mt-2 text-sm font-bold text-slate-200">The vault is waiting for its first UFO</h2>
          <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-slate-400">
            Brilliant moves are rare: a sound sacrifice that Stockfish confirms is clearly best. Analyze your sharpest games to fill the archive. Opponent brilliancies stay visible in their game reviews.
          </p>
          <button type="button" onClick={onOpenGames} className="mt-3 inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-cyan-400 to-emerald-400 px-3.5 py-2 text-xs font-extrabold text-slate-950">
            <Sparkles className="h-3.5 w-3.5" /> Analyze games
          </button>
        </section>
      ) : (
        <>
          <section className="glass-card p-3">
            <div className="flex flex-wrap items-center gap-2">
              <div className="inline-flex rounded-xl border border-slate-800 bg-slate-950/60 p-0.5">
                {([['mine', `Mine${username ? ` (${username})` : ''}`], ['opponent', 'Opponents']] as Array<[Scope, string]>).map(([key, label]) => (
                  <button
                    key={key}
                    type="button"
                    onClick={() => switchScope(key)}
                    className={`rounded-lg px-2.5 py-1.5 text-[10px] font-bold ${scope === key ? 'bg-cyan-500/20 text-cyan-200' : 'text-slate-400'}`}
                  >
                    {label}
                  </button>
                ))}
              </div>
              <div className="ml-auto flex items-center gap-1.5 text-[10px] text-slate-500">
                <Filter className="h-3.5 w-3.5" /> {filtered.length} shown
              </div>
            </div>

            {!scopeEmpty && (
              <>
                <div className="mt-2 grid grid-cols-1 gap-1.5 sm:grid-cols-2">
                  <Select label="Opening" value={opening} onChange={(v) => { setOpening(v); resetVisible(); }} options={scopeOpenings.map((o) => ({ value: o.name, label: `${o.name} (${o.count})` }))} />
                  <Select label="Month" value={month} onChange={(v) => { setMonth(v); resetVisible(); }} options={scopeMonths.map((m) => ({ value: m.key, label: `${m.label} (${m.count})` }))} />
                </div>

                <div className="mt-2 flex flex-wrap gap-1.5">
                  {scopeOpenings.slice(0, 3).map((o) => (
                    <button
                      key={o.name}
                      type="button"
                      onClick={() => { setOpening(opening === o.name ? '' : o.name); resetVisible(); }}
                      className={`rounded-full border px-2 py-0.5 text-[10px] font-semibold ${opening === o.name ? 'border-fuchsia-400/50 bg-fuchsia-500/15 text-fuchsia-200' : 'border-slate-800 bg-slate-950/40 text-slate-400 hover:border-slate-600'}`}
                    >
                      {o.name.length > 24 ? `${o.name.slice(0, 24)}…` : o.name} <span className="font-mono text-slate-500">{o.count}</span>
                    </button>
                  ))}
                </div>
              </>
            )}
          </section>

          {scopeEmpty ? (
            <section className="glass-card p-7 text-center">
              <Orbit className="mx-auto h-9 w-9 text-slate-600" />
              <h2 className="mt-2 text-sm font-bold text-slate-200">
                {scope === 'mine' ? 'No personal brilliancies yet' : 'No opponent brilliancies yet'}
              </h2>
              <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-slate-400">
                {scope === 'mine'
                  ? 'Your own sacrifices have not been tagged yet. Opponent brilliancies are kept out of your counter but are still available to review.'
                  : 'No brilliant moves by your opponents have been found in the analyzed games yet.'}
              </p>
              <button
                type="button"
                onClick={() => switchScope(scope === 'mine' ? 'opponent' : 'mine')}
                className="mt-3 inline-flex items-center gap-1.5 rounded-xl border border-slate-700 bg-slate-800/80 px-3.5 py-2 text-xs font-bold text-slate-200"
              >
                {scope === 'mine' ? 'View opponent brilliancies' : 'Back to my brilliancies'}
              </button>
            </section>
          ) : (
            <>
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
                {filtered.slice(0, visible).map((entry) => (
                  <button
                    key={entry.id}
                    type="button"
                    onClick={() => onOpenEntry(entry)}
                    className="glass-card glass-card-hover group flex flex-col overflow-hidden text-left"
                  >
                    <div className="relative p-2 pb-0">
                      <MiniBoard
                        fen={entry.afterFen}
                        orientation={entry.color}
                        theme={boardTheme}
                        lastMove={[entry.from, entry.to]}
                        badgeSquare={entry.to}
                        badgeClassification="brilliant"
                      />
                      <span className="pointer-events-none absolute right-3 top-3 rounded-full border border-cyan-300/40 bg-cyan-500/20 px-2 py-0.5 text-[9px] font-black text-cyan-100 backdrop-blur">
                        !!
                      </span>
                    </div>
                    <div className="flex flex-1 flex-col p-3">
                      <div className="flex items-baseline justify-between gap-2">
                        <span className="font-mono text-sm font-extrabold text-white">
                          {entry.moveNumber}{entry.color === 'w' ? '.' : '…'} {entry.san}
                        </span>
                        <span className={`shrink-0 rounded px-1.5 py-0.5 text-[9px] font-black ${entry.isUserMove ? 'bg-cyan-500/15 text-cyan-300' : 'bg-slate-800 text-slate-400'}`}>
                          {entry.isUserMove ? 'YOUR MOVE' : 'OPPONENT'}
                        </span>
                      </div>
                      <div className="mt-0.5 truncate text-[11px] text-slate-300">
                        {entry.playerName} <span className="text-slate-500">vs</span> {entry.opponentName}
                      </div>
                      <div className="mt-1 flex items-center justify-between gap-2 text-[10px] text-slate-500">
                        <span className="truncate">{entry.openingEco ? `${entry.openingEco} · ` : ''}{entry.openingName}</span>
                        <span className="shrink-0">{new Date(entry.playedAt).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}</span>
                      </div>
                      <div className="mt-2 flex items-center gap-1 text-[10px] font-bold text-cyan-300 opacity-80 group-hover:opacity-100">
                        <Sparkles className="h-3 w-3" /> Replay this moment →
                      </div>
                    </div>
                  </button>
                ))}
              </div>

              {filtered.length === 0 && (
                <div className="glass-card p-6 text-center text-xs text-slate-400">No brilliancies match these filters. Try clearing one.</div>
              )}

              {visible < filtered.length && (
                <div className="flex justify-center">
                  <button type="button" onClick={() => setVisible((v) => v + 12)} className="rounded-xl border border-slate-700 bg-slate-800/80 px-4 py-2 text-xs font-bold text-slate-200">
                    Load more ({filtered.length - visible} left)
                  </button>
                </div>
              )}
            </>
          )}
        </>
      )}
    </div>
  );
};

const VaultStat: React.FC<{ icon: React.ReactNode; label: string; value: number }> = ({ icon, label, value }) => (
  <div className="rounded-xl border border-slate-800/80 bg-slate-950/45 px-2.5 py-2">
    <div className="flex items-center gap-1 text-[9px] font-bold uppercase tracking-wide text-slate-500">{icon}{label}</div>
    <div className="mt-0.5 font-mono text-base font-extrabold text-slate-100">{value}</div>
  </div>
);

const Select: React.FC<{ label: string; value: string; onChange: (v: string) => void; options: Array<{ value: string; label: string }> }> = ({ label, value, onChange, options }) => (
  <label className="flex items-center gap-1.5 rounded-lg border border-slate-800 bg-slate-950/50 px-2 py-1.5">
    <span className="shrink-0 text-[9px] font-bold uppercase tracking-wide text-slate-500">{label}</span>
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="min-w-0 flex-1 bg-transparent text-[10px] font-semibold text-slate-200 focus:outline-none"
    >
      <option value="">All</option>
      {options.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
    </select>
  </label>
);
