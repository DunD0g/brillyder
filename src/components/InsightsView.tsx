import React, { useMemo, useState } from 'react';
import {
  Activity,
  AlertCircle,
  ArrowUpRight,
  CheckCircle2,
  Crown,
  Flame,
  Gem,
  Play,
  Search,
  Shield,
  ShieldCheck,
  Sparkles,
  Swords,
  Target,
  Timer,
  TrendingUp,
  Trophy,
  X,
} from 'lucide-react';
import type { AnalyzedGame, ColourSplit, GameHighlight, GamePlatform, ScoutState } from '../types/chess';
import { computeMultiGameInsights } from '../services/insightsAggregator';
import { PLATFORM_META, platformLabel, scopeAnalyzedGamesForPlatform } from '../services/gameSource';
import { ActivityTrendChart } from './ActivityTrendChart';
import { TimeTroubleCard } from './TimeTroubleCard';

interface Props {
  analyzedGames: AnalyzedGame[];
  username: string;
  platform: GamePlatform;
  scout: ScoutState | null;
  onPlatformChange: (platform: GamePlatform) => void;
  onScout: (name: string) => void;
  onCancelScout: () => void;
  onClearScout: () => void;
  onOpenGames: () => void;
  onOpenTrainer: () => void;
  onOpenGame: (gameId: string, ply: number) => void;
}

const AXIS_HINTS: Record<string, string> = {
  openings: 'Book precision and early-game accuracy, scored against your rating band.',
  tactics: 'Success rate on sharp, only-move positions and forced tactical sequences.',
  endgames: 'Accuracy once non-pawn material drops — conversion and technique.',
  conversion: 'How often a clear +68% advantage turns into a full point.',
  resilience: 'How well you hold difficult positions and limit damage when worse.',
  timeManagement: 'Accuracy under 60 seconds and error rate in low-clock buckets.',
};

export const InsightsView: React.FC<Props> = ({
  analyzedGames,
  username,
  platform,
  scout,
  onPlatformChange,
  onScout,
  onCancelScout,
  onClearScout,
  onOpenGames,
  onOpenTrainer,
  onOpenGame,
}) => {
  const [scoutName, setScoutName] = useState('');

  const scopedGames = useMemo(() => scopeAnalyzedGamesForPlatform(analyzedGames, platform), [analyzedGames, platform]);
  const scoutActive = scout?.status === 'ready' && scout.games.length > 0;
  const activeGames = scoutActive ? scout.games : scopedGames;
  const activeUsername = scoutActive ? scout.username : username;
  const insights = useMemo(() => computeMultiGameInsights(activeGames, activeUsername), [activeGames, activeUsername]);
  const bestGame = insights.bestGames[0] ?? null;
  const streakVisible = insights.currentStreak.count >= 2 && insights.currentStreak.kind !== 'none';

  const axes = useMemo(() => ([
    { key: 'openings', label: 'Openings', val: insights.skillProfile.openings, icon: Sparkles },
    { key: 'tactics', label: 'Tactics', val: insights.skillProfile.tactics, icon: Swords },
    { key: 'endgames', label: 'Endgames', val: insights.skillProfile.endgames, icon: Target },
    { key: 'conversion', label: 'Conversion', val: insights.skillProfile.conversion, icon: TrendingUp },
    { key: 'resilience', label: 'Defense', val: insights.skillProfile.resilience, icon: Shield },
    { key: 'timeManagement', label: 'Time mgmt', val: insights.skillProfile.timeManagement, icon: Timer },
  ]), [insights.skillProfile]);

  const cx = 150;
  const cy = 128;
  const maxR = 84;
  const pointAt = (idx: number, pct: number) => {
    const angle = (-Math.PI / 2) + (idx * 2 * Math.PI) / axes.length;
    const r = (pct / 100) * maxR;
    return { x: cx + Math.cos(angle) * r, y: cy + Math.sin(angle) * r };
  };
  const radarPath = axes.map((a, i) => { const p = pointAt(i, a.val); return `${i === 0 ? 'M' : 'L'} ${p.x.toFixed(1)} ${p.y.toFixed(1)}`; }).join(' ') + ' Z';

  const axisColor = (val: number) => (val >= 70 ? 'text-emerald-300' : val >= 50 ? 'text-cyan-300' : val >= 35 ? 'text-amber-300' : 'text-rose-300');
  const barColor = (val: number) => (val >= 70 ? 'from-emerald-400 to-lime-400' : val >= 50 ? 'from-cyan-400 to-emerald-400' : val >= 35 ? 'from-amber-400 to-orange-400' : 'from-rose-500 to-orange-400');

  const handleScoutSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!scoutName.trim() || scout?.status === 'loading') return;
    onScout(scoutName.trim());
  };

  return (
    <div className="space-y-3 pb-24">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-base font-extrabold tracking-tight text-white">Performance insights</h1>
          <p className="text-[11px] text-slate-400">
            {scoutActive ? `Scouting ${scout.username}` : `${scopedGames.length} analyzed ${platformLabel(platform)} game${scopedGames.length === 1 ? '' : 's'}`} · rating-relative 6-axis profile
          </p>
          {streakVisible && (
            <span className={`mt-1 inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] font-bold ${
              insights.currentStreak.kind === 'W'
                ? 'border-emerald-400/30 bg-emerald-500/10 text-emerald-200'
                : insights.currentStreak.kind === 'L'
                  ? 'border-rose-400/30 bg-rose-500/10 text-rose-200'
                  : 'border-slate-600 bg-slate-800/70 text-slate-300'
            }`}>
              <Flame className="h-3 w-3" /> {insights.currentStreak.count}{insights.currentStreak.kind} streak
            </span>
          )}
        </div>
        <div className="inline-flex rounded-xl border border-slate-800 bg-slate-950/60 p-0.5">
          {(['lichess', 'chesscom'] as GamePlatform[]).map((p) => (
            <button
              key={p}
              type="button"
              onClick={() => onPlatformChange(p)}
              className={`rounded-lg px-3 py-1.5 text-[11px] font-black transition ${platform === p ? 'bg-cyan-500/20 text-cyan-200' : 'text-slate-400 hover:text-slate-200'}`}
            >
              {PLATFORM_META[p].label}
            </button>
          ))}
        </div>
      </div>

      <section className="glass-card border-amber-500/20 p-3.5">
        <div className="flex items-start justify-between gap-2">
          <div>
            <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
              <Search className="h-4 w-4 text-amber-400" /> Opponent scout
            </div>
            <p className="mt-0.5 text-[11px] leading-relaxed text-slate-400">
              Pull a rival’s recent {platformLabel(platform)} games and analyze up to 3 on-device. See their radar, openings and clock leaks before you play.
            </p>
          </div>
          {scoutActive && (
            <button type="button" onClick={() => { onClearScout(); setScoutName(''); }} className="inline-flex shrink-0 items-center gap-1 rounded-lg border border-slate-700 bg-slate-800 px-2 py-1 text-[10px] font-bold text-slate-300">
              <X className="h-3 w-3" /> Exit scout
            </button>
          )}
        </div>

        <form onSubmit={handleScoutSubmit} className="mt-2.5 flex gap-2">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-500" />
            <input
              type="text"
              value={scoutName}
              onChange={(e) => setScoutName(e.target.value)}
              placeholder={`Opponent ${platformLabel(platform)} username…`}
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
              className="w-full rounded-xl border border-slate-700/80 bg-slate-950 py-2 pl-9 pr-3 text-xs text-slate-100 placeholder-slate-500 focus:border-amber-400 focus:outline-none"
            />
          </div>
          <button
            type="submit"
            disabled={!scoutName.trim() || scout?.status === 'loading'}
            className="inline-flex items-center gap-1.5 rounded-xl border border-amber-500/35 bg-amber-500/15 px-3 py-2 text-[11px] font-bold text-amber-200 disabled:opacity-40"
          >
            <Play className="h-3.5 w-3.5" /> Scout
          </button>
        </form>

        {scout?.status === 'loading' && (
          <div className="mt-2.5 rounded-xl border border-cyan-500/25 bg-cyan-500/5 p-2.5">
            <div className="flex items-center justify-between text-[11px]">
              <span className="inline-flex items-center gap-1.5 font-semibold text-cyan-200">
                <Activity className="h-3.5 w-3.5 animate-pulse" /> Scouting @{scout.username}… Stockfish D10
              </span>
              <div className="flex items-center gap-2">
                <span className="font-mono text-slate-400">{scout.progress ? `${scout.progress.done}/${scout.progress.total}` : 'fetching'}</span>
                <button type="button" onClick={onCancelScout} className="rounded bg-slate-800 px-1.5 py-0.5 text-[10px] font-bold text-rose-300">Cancel</button>
              </div>
            </div>
            <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-slate-800">
              <div className="h-full rounded-full bg-gradient-to-r from-amber-400 to-cyan-400 transition-all" style={{ width: `${scout.progress ? Math.round((scout.progress.done / Math.max(1, scout.progress.total)) * 100) : 8}%` }} />
            </div>
          </div>
        )}

        {scout?.status === 'error' && (
          <div className="mt-2.5 flex items-start gap-1.5 rounded-xl border border-rose-500/30 bg-rose-500/10 px-2.5 py-2 text-[11px] text-rose-200">
            <AlertCircle className="mt-0.5 h-3.5 w-3.5 shrink-0" /> {scout.error ?? 'Scouting failed.'}
          </div>
        )}

        {scoutActive && (
          <div className="mt-2.5 flex items-center gap-1.5 rounded-xl border border-amber-500/30 bg-amber-500/10 px-2.5 py-2 text-[11px] text-amber-100">
            <Target className="h-3.5 w-3.5 shrink-0" /> Scout mode: {scout.games.length} of @{scout.username}’s recent games analyzed live on your device.
          </div>
        )}
      </section>

      {activeGames.length === 0 ? (
        <section className="glass-card p-6 text-center">
          <Trophy className="mx-auto h-8 w-8 text-slate-600" />
          <h2 className="mt-2 text-sm font-bold text-slate-200">No analyzed {platformLabel(platform)} games yet</h2>
          <p className="mx-auto mt-1 max-w-md text-xs leading-relaxed text-slate-400">
            Sync your games, run an analysis, or scout an opponent above. The radar scores each axis relative to your rating band instead of absolute percentages.
          </p>
          <button type="button" onClick={onOpenGames} className="mt-3 inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-cyan-400 to-emerald-400 px-3.5 py-2 text-xs font-extrabold text-slate-950">
            <Sparkles className="h-3.5 w-3.5" /> Go to games
          </button>
        </section>
      ) : (
        <>
          <div className="grid grid-cols-2 gap-2 md:grid-cols-4">
            <StatCard icon={<Swords className="h-4 w-4 text-cyan-400" />} label="Games" value={String(insights.gamesCount)} sub={`${insights.record.wins}W-${insights.record.draws}D-${insights.record.losses}L`} />
            <StatCard icon={<Target className="h-4 w-4 text-emerald-400" />} label="Avg accuracy" value={`${insights.avgAccuracy}%`} sub={`Best ${insights.bestAccuracy}%`} />
            <StatCard icon={<TrendingUp className="h-4 w-4 text-cyan-300" />} label="Perf. Elo" value={String(insights.avgEstimatedElo)} sub={insights.ratingBand} />
            <StatCard icon={<Gem className="h-4 w-4 text-fuchsia-300" />} label="Brilliant !!" value={String(insights.brilliantCount)} sub="Galaxy-brain moves" />
          </div>

          <div className="grid grid-cols-2 gap-2 md:grid-cols-4">
            <StatCard icon={<Crown className="h-4 w-4 text-amber-300" />} label="Giant slayer" value={String(insights.giantSlayer.wins)} sub={`${insights.giantSlayer.games} games vs stronger`} />
            <StatCard icon={<Flame className="h-4 w-4 text-orange-300" />} label="Comebacks" value={String(insights.comebacks)} sub={`${insights.blownWins} blown leads`} />
            <StatCard icon={<ShieldCheck className="h-4 w-4 text-emerald-300" />} label="Clean games" value={String(insights.blunderFreeGames)} sub="No blunders" />
            <StatCard icon={<Activity className="h-4 w-4 text-cyan-300" />} label="Avg opponent" value={insights.avgOpponentRating > 0 ? String(insights.avgOpponentRating) : '—'} sub="Rating faced" />
          </div>

          <section className="glass-card border-amber-500/20 p-3.5">
            <div className="flex items-start justify-between gap-2">
              <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
                <Trophy className="h-4 w-4 text-amber-400" /> Best games
              </div>
              {bestGame && (
                <span className="rounded-full border border-amber-400/25 bg-amber-500/10 px-2 py-0.5 text-[9px] font-bold text-amber-200">
                  Top score {Math.round(bestGame.score)}
                </span>
              )}
            </div>
            {insights.bestGames.length === 0 ? (
              <p className="py-4 text-xs text-slate-500">Your best-game podium appears after one analysed game.</p>
            ) : (
              <div className="mt-2 grid gap-2 md:grid-cols-3">
                {insights.bestGames.map((game, index) => (
                  <BestGameCard key={game.gameId} game={game} rank={index + 1} onOpen={() => onOpenGame(game.gameId, game.highlightPly)} />
                ))}
              </div>
            )}
            {insights.worstGame && insights.worstGame.result === 'L' && (
              <button
                type="button"
                onClick={() => onOpenGame(insights.worstGame!.gameId, insights.worstGame!.highlightPly)}
                className="mt-2 flex w-full items-center gap-2 rounded-xl border border-rose-500/20 bg-rose-500/5 px-2.5 py-2 text-left text-[10px] text-rose-100/90 transition hover:border-rose-400/40"
              >
                <span className="rounded bg-rose-500/20 px-1.5 py-0.5 font-black text-rose-300">TOUGH</span>
                <span className="min-w-0 flex-1 truncate">
                  {insights.worstGame.opponent} ({insights.worstGame.opponentRating || '—'}) · {insights.worstGame.accuracy}% · {insights.worstGame.opening}
                </span>
                <span className="shrink-0 font-bold text-rose-200">Review <ArrowUpRight className="inline h-3 w-3" /></span>
              </button>
            )}
          </section>

          <div className="grid gap-3 lg:grid-cols-2">
            <ColourSplitCard
              white={insights.scoreByColour.white}
              black={insights.scoreByColour.black}
            />
            <div className="glass-card p-3.5">
              <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
                <Sparkles className="h-4 w-4 text-cyan-300" /> Record book
              </div>
              <div className="mt-2 grid grid-cols-2 gap-1.5">
                <MiniRecord label="Best accuracy" value={`${insights.bestAccuracy}%`} tone="text-emerald-300" />
                <MiniRecord label="Brilliant moves" value={String(insights.brilliantCount)} tone="text-fuchsia-300" />
                <MiniRecord label="Giant-slayer wins" value={String(insights.giantSlayer.wins)} tone="text-amber-300" />
                <MiniRecord label="Comeback wins" value={String(insights.comebacks)} tone="text-orange-300" />
                <MiniRecord label="Blown leads" value={String(insights.blownWins)} tone="text-rose-300" />
                <MiniRecord label="Clean games" value={String(insights.blunderFreeGames)} tone="text-cyan-300" />
              </div>
              {(insights.openingBest || insights.openingWorst) && (
                <div className="mt-2 space-y-1">
                  {insights.openingBest && (
                    <div className="flex items-center gap-1.5 rounded-lg border border-emerald-500/20 bg-emerald-500/5 px-2 py-1 text-[10px]">
                      <span className="font-black text-emerald-300">BEST</span>
                      <span className="min-w-0 flex-1 truncate text-slate-300">{insights.openingBest.name}</span>
                      <span className="font-mono font-bold text-emerald-300">{insights.openingBest.winRate}%</span>
                    </div>
                  )}
                  {insights.openingWorst && (
                    <div className="flex items-center gap-1.5 rounded-lg border border-rose-500/20 bg-rose-500/5 px-2 py-1 text-[10px]">
                      <span className="font-black text-rose-300">FIX</span>
                      <span className="min-w-0 flex-1 truncate text-slate-300">{insights.openingWorst.name}</span>
                      <span className="font-mono font-bold text-rose-300">{insights.openingWorst.winRate}%</span>
                    </div>
                  )}
                </div>
              )}
            </div>
          </div>

          <div className="glass-card border-cyan-500/25 p-3.5">
            <div className="flex items-start gap-2.5">
              <Target className="mt-0.5 h-5 w-5 shrink-0 text-cyan-400" />
              <div className="min-w-0">
                <div className="text-xs font-bold text-cyan-200">BrillyDer training focus</div>
                <p className="mt-0.5 text-xs leading-relaxed text-slate-300">{insights.recommendation}</p>
                <button type="button" onClick={onOpenTrainer} className="mt-2 inline-flex items-center gap-1 rounded-lg border border-amber-500/30 bg-amber-500/10 px-2 py-1 text-[10px] font-bold text-amber-200">
                  <Flame className="h-3 w-3" /> Train this in the mistake deck
                </button>
              </div>
            </div>
          </div>

          <div className="grid gap-3 lg:grid-cols-2">
            <div className="glass-card p-3.5">
              <div className="flex items-start justify-between gap-2">
                <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
                  <Trophy className="h-4 w-4 text-amber-400" /> 6-axis skill radar
                </div>
                <span className="rounded-full border border-slate-700 bg-slate-950/60 px-2 py-0.5 text-[9px] text-slate-400">50 = band average</span>
              </div>
              <svg viewBox="0 0 300 262" className="mx-auto w-full max-w-[340px]">
                {[25, 50, 75, 100].map((ring) => (
                  <polygon
                    key={ring}
                    points={axes.map((_, i) => { const p = pointAt(i, ring); return `${p.x.toFixed(1)},${p.y.toFixed(1)}`; }).join(' ')}
                    fill="none"
                    stroke={ring === 50 ? '#334155' : '#1e293b'}
                    strokeDasharray={ring === 50 ? '3 3' : undefined}
                    strokeWidth="1"
                  />
                ))}
                {axes.map((axis, i) => {
                  const end = pointAt(i, 100);
                  return <line key={axis.key} x1={cx} y1={cy} x2={end.x} y2={end.y} stroke="#1e293b" strokeWidth="1" />;
                })}
                <path d={radarPath} fill="rgba(34, 211, 238, 0.20)" stroke="#22d3ee" strokeWidth="2" strokeLinejoin="round" />
                {axes.map((axis, i) => {
                  const dot = pointAt(i, axis.val);
                  const label = pointAt(i, 118);
                  const anchor = label.x < cx - 8 ? 'end' : label.x > cx + 8 ? 'start' : 'middle';
                  return (
                    <g key={axis.key}>
                      <circle cx={dot.x} cy={dot.y} r="3" fill="#67e8f9" stroke="#0b0f19" strokeWidth="1" />
                      <text x={label.x} y={label.y} textAnchor={anchor} dominantBaseline="middle" fill="#cbd5e1" fontSize="9" fontWeight="700">
                        {axis.label}
                      </text>
                      <text x={label.x} y={label.y + 10} textAnchor={anchor} dominantBaseline="middle" fill="#64748b" fontSize="8" fontWeight="700">
                        {axis.val}
                      </text>
                    </g>
                  );
                })}
              </svg>
              <p className="mt-1 text-center text-[10px] text-slate-500">{insights.ratingBand}</p>
              <p className="mt-0.5 text-center text-[9px] text-slate-600">Axes with too few sample moves stay neutral at 50.</p>
            </div>

            <div className="glass-card p-3.5">
              <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
                <Activity className="h-4 w-4 text-emerald-400" /> Skill axes vs. rating band
              </div>
              <div className="mt-3 space-y-2.5">
                {axes.map((axis) => {
                  const Icon = axis.icon;
                  return (
                    <div key={axis.key} title={AXIS_HINTS[axis.key]}>
                      <div className="flex items-center justify-between text-[11px]">
                        <span className="inline-flex items-center gap-1.5 font-semibold text-slate-300">
                          <Icon className="h-3 w-3 text-slate-500" /> {axis.label}
                        </span>
                        <span className={`font-mono font-extrabold ${axisColor(axis.val)}`}>{axis.val}</span>
                      </div>
                      <div className="relative mt-1 h-2 overflow-hidden rounded-full bg-slate-800">
                        <div className={`h-full rounded-full bg-gradient-to-r ${barColor(axis.val)}`} style={{ width: `${axis.val}%` }} />
                        <span className="absolute inset-y-0 left-1/2 w-px bg-slate-400/50" />
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>

          <div className="grid gap-3 lg:grid-cols-2">
            <TimeTroubleCard buckets={insights.timeTrouble} />
            <ActivityTrendChart trend={insights.trend} />
          </div>

          <div className="grid gap-3 lg:grid-cols-2">
            <div className="glass-card p-3.5">
              <div className="flex items-center justify-between">
                <div className="text-xs font-bold text-slate-100">Opening repertoire</div>
                <span className="text-[10px] text-slate-500">{insights.openings.length} families</span>
              </div>
              {insights.openings.length === 0 ? (
                <p className="py-4 text-xs text-slate-500">Analyze games to reveal your opening win rates.</p>
              ) : (
                <div className="mt-2 space-y-2">
                  {insights.openings.slice(0, 8).map((op) => (
                    <div key={op.name} className="rounded-xl border border-slate-800 bg-slate-950/40 p-2">
                      <div className="flex items-center justify-between gap-2 text-[11px]">
                        <div className="min-w-0">
                          <div className="truncate font-semibold text-slate-100">{op.eco ? `${op.eco} · ` : ''}{op.name}</div>
                          <div className="text-[10px] text-slate-500">{op.games} games · {op.wins}W-{op.draws}D-{op.losses}L</div>
                        </div>
                        <div className="shrink-0 text-right">
                          <div className="font-mono font-bold text-cyan-300">{op.winRate}%</div>
                          <div className="font-mono text-[9px] text-emerald-300">{op.avgAccuracy}% acc</div>
                        </div>
                      </div>
                      <div className="mt-1 h-1 overflow-hidden rounded-full bg-slate-800">
                        <div className="h-full rounded-full bg-gradient-to-r from-cyan-400 to-emerald-400" style={{ width: `${op.winRate}%` }} />
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="glass-card p-3.5">
              <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
                <Flame className="h-4 w-4 text-rose-400" /> Blunder rate by phase
              </div>
              <div className="mt-2.5 space-y-3">
                {insights.phaseStats.map((ps) => (
                  <div key={ps.phase}>
                    <div className="flex items-center justify-between text-[11px]">
                      <span className="font-semibold text-slate-200">{ps.phase} <span className="text-[9px] text-slate-500">({ps.moves} moves)</span></span>
                      <span className="font-mono text-[10px] text-slate-400">{ps.accuracy}% acc · {ps.blunderRatePer10Moves}/10 err</span>
                    </div>
                    <div className="mt-1 flex h-2 overflow-hidden rounded-full bg-slate-800">
                      <div className="h-full bg-gradient-to-r from-cyan-400 to-emerald-400" style={{ width: `${Math.min(100, ps.accuracy)}%` }} />
                    </div>
                    <div className="mt-0.5 flex gap-2 text-[9px]">
                      <span className="text-yellow-300">?! {ps.inaccuracies}</span>
                      <span className="text-orange-300">? {ps.mistakes}</span>
                      <span className="text-red-400">?? {ps.blunders}</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>

          <div className="flex flex-wrap items-center justify-center gap-2 pt-1 text-[10px] text-slate-500">
            <span className="inline-flex items-center gap-1"><CheckCircle2 className="h-3 w-3 text-emerald-400" /> All analysis runs locally</span>
            <span>·</span>
            <span>{activeGames.filter((g) => g.game.source === 'chesscom').length} Chess.com / {activeGames.filter((g) => g.game.source !== 'chesscom').length} other</span>
          </div>
        </>
      )}
    </div>
  );
};

const StatCard: React.FC<{ icon: React.ReactNode; label: string; value: string; sub: string }> = ({ icon, label, value, sub }) => (
  <div className="glass-card p-3">
    <div className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wide text-slate-400">{icon}{label}</div>
    <div className="mt-1 text-lg font-extrabold text-white">{value}</div>
    <div className="truncate text-[10px] text-slate-400">{sub}</div>
  </div>
);

const RESULT_META: Record<'W' | 'D' | 'L', { label: string; tone: string }> = {
  W: { label: 'WIN', tone: 'border-emerald-400/30 bg-emerald-500/10 text-emerald-200' },
  D: { label: 'DRAW', tone: 'border-slate-500/30 bg-slate-500/10 text-slate-300' },
  L: { label: 'LOSS', tone: 'border-rose-400/30 bg-rose-500/10 text-rose-200' },
};

const BestGameCard: React.FC<{ game: GameHighlight; rank: number; onOpen: () => void }> = ({ game, rank, onOpen }) => {
  const meta = RESULT_META[game.result];
  const date = new Date(game.playedAt).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  return (
    <button
      type="button"
      onClick={onOpen}
      className={`group rounded-xl border bg-slate-950/45 p-2 text-left transition hover:bg-slate-900/70 ${
        rank === 1 ? 'border-amber-400/35' : 'border-slate-800'
      }`}
    >
      <div className="flex items-center justify-between gap-1">
        <span className={`inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-[9px] font-black ${rank === 1 ? 'bg-amber-500/15 text-amber-300' : 'bg-slate-800 text-slate-400'}`}>
          {rank === 1 ? '★' : '#'}{rank}
        </span>
        <span className={`rounded border px-1.5 py-0.5 text-[9px] font-black ${meta.tone}`}>{meta.label}</span>
      </div>
      <div className="mt-1 flex items-baseline justify-between gap-2">
        <span className="min-w-0 truncate text-[11px] font-bold text-slate-100">{game.opponent}</span>
        <span className="shrink-0 font-mono text-xs font-black text-cyan-300">{game.accuracy}%</span>
      </div>
      <div className="truncate text-[9px] text-slate-500">
        {game.opponentRating > 0 ? `${game.opponentRating} rated · ` : ''}{game.opening}
      </div>
      <div className="mt-1 min-h-[22px] text-[9px] leading-snug text-slate-400">{game.reason}</div>
      <div className="mt-1 flex items-center justify-between text-[9px] font-bold">
        <span className="text-slate-500">{date}</span>
        <span className="inline-flex items-center gap-0.5 text-cyan-300 opacity-80 group-hover:opacity-100">Replay <ArrowUpRight className="h-3 w-3" /></span>
      </div>
    </button>
  );
};

const ColourSplitCard: React.FC<{ white: ColourSplit; black: ColourSplit }> = ({ white, black }) => (
  <div className="glass-card p-3.5">
    <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
      <Activity className="h-4 w-4 text-cyan-300" /> Colour split
    </div>
    <p className="mt-0.5 text-[10px] text-slate-500">Score and accuracy as White vs Black.</p>
    <div className="mt-2 space-y-2">
      <ColourRow label="White" color="w" split={white} />
      <ColourRow label="Black" color="b" split={black} />
    </div>
  </div>
);

const ColourRow: React.FC<{ label: string; color: 'w' | 'b'; split: ColourSplit }> = ({ label, color, split }) => (
  <div className="rounded-xl border border-slate-800 bg-slate-950/40 p-2">
    <div className="flex items-center justify-between gap-2 text-[10px]">
      <span className="inline-flex items-center gap-1.5 font-bold text-slate-200">
        <span className={`h-2.5 w-2.5 rounded-full border ${color === 'w' ? 'border-slate-300 bg-white' : 'border-slate-500 bg-slate-950'}`} />
        {label}
      </span>
      <span className="font-mono text-slate-400">{split.wins}W-{split.draws}D-{split.losses}L</span>
    </div>
    <div className="mt-1 flex items-center justify-between text-[9px] text-slate-500">
      <span>{split.games} games</span>
      <span><span className="font-mono font-bold text-cyan-300">{split.winRate}%</span> score · <span className="font-mono font-bold text-emerald-300">{split.accuracy}%</span> acc</span>
    </div>
    <div className="mt-1 h-1 overflow-hidden rounded-full bg-slate-800">
      <div className="h-full rounded-full bg-gradient-to-r from-cyan-400 to-emerald-400" style={{ width: `${split.winRate}%` }} />
    </div>
  </div>
);

const MiniRecord: React.FC<{ label: string; value: string; tone: string }> = ({ label, value, tone }) => (
  <div className="rounded-lg border border-slate-800 bg-slate-950/40 px-2 py-1.5">
    <div className="text-[8px] font-bold uppercase tracking-wide text-slate-500">{label}</div>
    <div className={`mt-0.5 font-mono text-sm font-black ${tone}`}>{value}</div>
  </div>
);
