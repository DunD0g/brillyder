import React, { useMemo, useState } from 'react';
import {
  Calendar,
  Filter,
  Gem,
  Orbit,
  ShieldCheck,
  Sparkles,
  Swords,
  Trophy,
  UserRound,
} from 'lucide-react';
import type { BoardThemeId, BrillyVaultEntry, BrillyVaultStats, VaultCategory } from '../types/chess';
import { useVibe } from '../utils/vibeCopy';
import { MiniBoard } from './MiniBoard';

interface Props {
  entries: BrillyVaultEntry[];
  stats: BrillyVaultStats;
  username: string;
  boardTheme: BoardThemeId;
  inModal?: boolean;
  onOpenEntry: (entry: BrillyVaultEntry) => void;
  onOpenGames: () => void;
}

type Scope = 'mine' | 'opponent';

const CATEGORY_TABS: Array<{ id: VaultCategory; label: string; Icon: typeof Gem }> = [
  { id: 'brilliant', label: '!! Brilliant', Icon: Gem },
  { id: 'clutch', label: 'Clutch Saves', Icon: ShieldCheck },
  { id: 'traps', label: 'Traps Punished', Icon: Swords },
  { id: 'clean', label: 'Clean Sweeps', Icon: Trophy },
];

export const BrillyVaultView: React.FC<Props> = ({
  entries,
  stats,
  username,
  boardTheme,
  inModal = false,
  onOpenEntry,
  onOpenGames,
}) => {
  const { copy } = useVibe();
  const [category, setCategory] = useState<VaultCategory>('brilliant');
  const [scope, setScope] = useState<Scope>('mine');
  const [opening, setOpening] = useState('');
  const [month, setMonth] = useState('');
  const [visible, setVisible] = useState(12);

  const categoryEntries = useMemo(
    () => entries.filter((e) => (e.category ?? 'brilliant') === category),
    [entries, category]
  );

  const scopeEntries = useMemo(
    () =>
      category === 'brilliant'
        ? categoryEntries.filter((entry) => (scope === 'mine' ? entry.isUserMove : !entry.isUserMove))
        : categoryEntries,
    [category, categoryEntries, scope]
  );

  const filtered = useMemo(
    () =>
      scopeEntries.filter((entry) => {
        if (opening && entry.openingName !== opening) return false;
        if (month) {
          const d = new Date(entry.playedAt);
          const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
          if (key !== month) return false;
        }
        return true;
      }),
    [scopeEntries, opening, month]
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

  const countForCategory = (cat: VaultCategory) => {
    if (cat === 'brilliant') return stats.userMoves;
    if (cat === 'clutch') return stats.clutchSaves;
    if (cat === 'traps') return stats.trapsPunished;
    return stats.cleanSweeps;
  };

  const resetVisible = () => setVisible(12);
  const switchCategory = (next: VaultCategory) => {
    setCategory(next);
    setOpening('');
    setMonth('');
    resetVisible();
  };
  const switchScope = (next: Scope) => {
    setScope(next);
    setOpening('');
    setMonth('');
    resetVisible();
  };

  const scopeEmpty = scopeEntries.length === 0;

  return (
    <div className={`space-y-3 ${inModal ? 'pb-4' : 'pb-24'}`}>
      <section className="glass-card glass-card-strong relative overflow-hidden p-4">
        <div className="pointer-events-none absolute -right-6 -top-8 h-32 w-32 rounded-full bg-teal-500/15 blur-2xl" />
        <div className="pointer-events-none absolute -bottom-10 left-10 h-28 w-28 rounded-full bg-purple-500/10 blur-2xl" />
        <div className="relative flex items-start justify-between gap-3">
          <div>
            <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-brilly">
              <Orbit className="h-4 w-4" /> Brilly Vault
            </div>
            <h1 className="mt-1 text-lg font-extrabold leading-tight text-white">{copy.vaultTitle}</h1>
            <p className="mt-1 max-w-lg text-[11px] leading-relaxed text-slate-400">
              {copy.vaultSubtitle}
            </p>
          </div>
          <div className="shrink-0 text-right">
            <div className="bg-gradient-to-br from-teal-300 to-purple-300 bg-clip-text text-4xl font-black leading-none text-transparent">
              {stats.userMoves}
            </div>
            <div className="mt-1 text-[9px] font-bold uppercase tracking-wider text-slate-500">brilliant !!</div>
          </div>
        </div>

        <div className="relative mt-3 grid grid-cols-2 gap-2 sm:grid-cols-4">
          <VaultStat icon={<Gem className="h-3.5 w-3.5 text-brilly" />} label="!! Brilliant" value={stats.userMoves} />
          <VaultStat icon={<ShieldCheck className="h-3.5 w-3.5 text-purple-300" />} label="Clutch Saves" value={stats.clutchSaves} />
          <VaultStat icon={<Swords className="h-3.5 w-3.5 text-amber-300" />} label="Traps Punished" value={stats.trapsPunished} />
          <VaultStat icon={<Trophy className="h-3.5 w-3.5 text-clean" />} label="Clean Sweeps" value={stats.cleanSweeps} />
        </div>

        {/* 4 Vault Category Tabs */}
        <div className="relative mt-3 flex flex-wrap gap-1.5 border-t border-slate-800/80 pt-3">
          {CATEGORY_TABS.map(({ id, label, Icon }) => {
            const active = category === id;
            const count = countForCategory(id);
            return (
              <button
                key={id}
                type="button"
                onClick={() => switchCategory(id)}
                className={`inline-flex items-center gap-1.5 rounded-xl border px-2.5 py-1.5 text-[11px] font-bold transition ${
                  active
                    ? 'border-teal-400/55 bg-teal-400/15 text-teal-100'
                    : 'border-slate-800 bg-void/60 text-slate-400 hover:border-slate-600 hover:text-slate-200'
                }`}
              >
                <Icon className="h-3.5 w-3.5" />
                {label}
                <span className="rounded-full bg-hull px-1.5 py-0.5 font-mono text-[9px] text-slate-300">
                  {count}
                </span>
              </button>
            );
          })}
        </div>
      </section>

      {entries.length === 0 ? (
        <section className="glass-card p-7 text-center">
          <Orbit className="mx-auto h-9 w-9 text-slate-600" />
          <h2 className="mt-2 text-sm font-bold text-slate-200">The vault is waiting for its first highlight</h2>
          <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-slate-400">
            Analyze your games to collect !! sacrifices, Clutch Saves, punished opening traps, and blunder-free Clean Sweeps.
          </p>
          <button
            type="button"
            onClick={onOpenGames}
            className="mt-3 inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-3.5 py-2 text-xs font-extrabold text-slate-950"
          >
            <Sparkles className="h-3.5 w-3.5" /> Analyze games
          </button>
        </section>
      ) : (
        <>
          <section className="glass-card p-3">
            <div className="flex flex-wrap items-center gap-2">
              {category === 'brilliant' ? (
                <div className="inline-flex rounded-xl border border-slate-800 bg-void/60 p-0.5">
                  {([
                    ['mine', `Mine${username ? ` (${username})` : ''}`],
                    ['opponent', 'Opponents'],
                  ] as Array<[Scope, string]>).map(([key, label]) => (
                    <button
                      key={key}
                      type="button"
                      onClick={() => switchScope(key)}
                      className={`rounded-lg px-2.5 py-1.5 text-[10px] font-bold ${
                        scope === key ? 'bg-teal-400/20 text-teal-200' : 'text-slate-400'
                      }`}
                    >
                      {label}
                    </button>
                  ))}
                </div>
              ) : (
                <div className="inline-flex items-center gap-1.5 text-[11px] font-bold text-slate-200">
                  <UserRound className="h-3.5 w-3.5 text-brilly" /> Personal highlights
                </div>
              )}
              <div className="ml-auto flex items-center gap-1.5 text-[10px] text-slate-500">
                {category === 'brilliant' ? (
                  <>
                    <Calendar className="h-3 w-3" /> {stats.thisMonth} !! this month ·
                  </>
                ) : (
                  <>
                    <Calendar className="h-3 w-3" /> {categoryEntries.length} total ·
                  </>
                )}{' '}
                <Filter className="h-3.5 w-3.5" /> {filtered.length} shown
              </div>
            </div>

            {!scopeEmpty && (
              <div className="mt-2 grid grid-cols-1 gap-1.5 sm:grid-cols-2">
                <Select
                  label="Opening"
                  value={opening}
                  onChange={(v) => { setOpening(v); resetVisible(); }}
                  options={scopeOpenings.map((o) => ({ value: o.name, label: `${o.name} (${o.count})` }))}
                />
                <Select
                  label="Month"
                  value={month}
                  onChange={(v) => { setMonth(v); resetVisible(); }}
                  options={scopeMonths.map((m) => ({ value: m.key, label: `${m.label} (${m.count})` }))}
                />
              </div>
            )}
          </section>

          {scopeEmpty ? (
            <section className="glass-card p-7 text-center">
              <Orbit className="mx-auto h-9 w-9 text-slate-600" />
              <h2 className="mt-2 text-sm font-bold text-slate-200">No entries in this Vault tab yet</h2>
              <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-slate-400">
                {category === 'clutch'
                  ? 'Find only-move defensive or tactical saves (≥2.0 pawn MultiPV gap under pressure) to earn Clutch Save badges.'
                  : category === 'traps'
                    ? 'Punish opponent opening or early-middlegame blunders with the top engine reply to fill Traps Punished.'
                    : category === 'clean'
                      ? 'Win a game with 0 blunders and ≥82% accuracy to log a Clean Sweep.'
                      : 'Keep analyzing your sharpest games to archive personal brilliancies.'}
              </p>
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
                        badgeClassification={
                          entry.category === 'brilliant'
                            ? 'brilliant'
                            : entry.category === 'clutch'
                              ? 'great'
                              : 'best'
                        }
                      />
                      <span className="pointer-events-none absolute right-3 top-3 rounded-full border border-teal-300/40 bg-void/85 px-2 py-0.5 text-[9px] font-black text-brilly backdrop-blur">
                        {entry.badgeText ?? '!!'}
                      </span>
                    </div>
                    <div className="flex flex-1 flex-col p-3">
                      <div className="flex items-baseline justify-between gap-2">
                        <span className="font-mono text-sm font-extrabold text-white">
                          {entry.moveNumber}{entry.color === 'w' ? '.' : '…'} {entry.san}
                        </span>
                        <span
                          className={`shrink-0 rounded px-1.5 py-0.5 text-[9px] font-black ${
                            entry.isUserMove ? 'bg-teal-400/15 text-teal-300' : 'bg-slate-800 text-slate-400'
                          }`}
                        >
                          {entry.isUserMove ? 'YOUR MOVE' : 'OPPONENT'}
                        </span>
                      </div>
                      <div className="mt-0.5 truncate text-[11px] text-slate-300">
                        {entry.playerName} <span className="text-slate-500">vs</span> {entry.opponentName}
                      </div>
                      {entry.reason && (
                        <div className="mt-1 line-clamp-2 text-[10px] leading-snug text-slate-400">
                          {entry.reason}
                        </div>
                      )}
                      <div className="mt-auto flex items-center justify-between gap-2 pt-2 text-[10px] text-slate-500">
                        <span className="truncate">
                          {entry.openingEco ? `${entry.openingEco} · ` : ''}
                          {entry.openingName}
                        </span>
                        <span className="shrink-0">
                          {new Date(entry.playedAt).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}
                        </span>
                      </div>
                      <div className="mt-1.5 flex items-center gap-1 text-[10px] font-bold text-brilly opacity-80 group-hover:opacity-100">
                        <Sparkles className="h-3 w-3" /> Replay this moment →
                      </div>
                    </div>
                  </button>
                ))}
              </div>

              {visible < filtered.length && (
                <div className="flex justify-center">
                  <button
                    type="button"
                    onClick={() => setVisible((v) => v + 12)}
                    className="rounded-xl border border-slate-700 bg-slate-800/80 px-4 py-2 text-xs font-bold text-slate-200"
                  >
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
  <div className="rounded-xl border border-slate-800/80 bg-void/50 px-2.5 py-2">
    <div className="flex items-center gap-1 text-[9px] font-bold uppercase tracking-wide text-slate-500">
      {icon}
      {label}
    </div>
    <div className="mt-0.5 font-mono text-base font-extrabold text-slate-100">{value}</div>
  </div>
);

const Select: React.FC<{
  label: string;
  value: string;
  onChange: (v: string) => void;
  options: Array<{ value: string; label: string }>;
}> = ({ label, value, onChange, options }) => (
  <label className="flex items-center gap-1.5 rounded-lg border border-slate-800 bg-void/55 px-2 py-1.5">
    <span className="shrink-0 text-[9px] font-bold uppercase tracking-wide text-slate-500">{label}</span>
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="min-w-0 flex-1 bg-transparent text-[10px] font-semibold text-slate-200 focus:outline-none"
    >
      <option value="">All</option>
      {options.map((o) => (
        <option key={o.value} value={o.value}>
          {o.label}
        </option>
      ))}
    </select>
  </label>
);
