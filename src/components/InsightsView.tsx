import React, { useMemo } from 'react';
import { Flame, Target, Trophy } from 'lucide-react';
import type { AnalyzedGame } from '../types/chess';
import { computeMultiGameInsights } from '../services/insightsAggregator';

interface Props {
  analyzedGames: AnalyzedGame[];
  username: string;
}

export const InsightsView: React.FC<Props> = ({ analyzedGames, username }) => {
  const insights = useMemo(() => computeMultiGameInsights(analyzedGames, username), [analyzedGames, username]);
  const axes = [
    { key: 'openings', label: 'Openings', val: insights.skillProfile.openings },
    { key: 'tactics', label: 'Tactics', val: insights.skillProfile.tactics },
    { key: 'endgames', label: 'Endgames', val: insights.skillProfile.endgames },
    { key: 'conversion', label: 'Conversion', val: insights.skillProfile.conversion },
    { key: 'resilience', label: 'Defense', val: insights.skillProfile.resilience },
  ];

  const cx = 120;
  const cy = 112;
  const maxR = 76;
  const pointAt = (idx: number, pct: number) => {
    const angle = (-Math.PI / 2) + (idx * 2 * Math.PI) / axes.length;
    const r = (pct / 100) * maxR;
    return { x: cx + Math.cos(angle) * r, y: cy + Math.sin(angle) * r };
  };
  const radarPath = axes.map((a, i) => { const p = pointAt(i, a.val); return `${i === 0 ? 'M' : 'L'} ${p.x.toFixed(1)} ${p.y.toFixed(1)}`; }).join(' ') + ' Z';

  return (
    <div className="space-y-4 pb-24">
      <div className="grid grid-cols-3 gap-2">
        <div className="rounded-2xl bg-slate-900 border border-slate-800 p-3">
          <div className="text-[10px] font-bold uppercase text-slate-400">Games</div>
          <div className="mt-1 text-lg font-extrabold text-white">{insights.gamesCount}</div>
          <div className="text-[10px] text-slate-400">{insights.record.wins}W-{insights.record.draws}D-{insights.record.losses}L</div>
        </div>
        <div className="rounded-2xl bg-slate-900 border border-slate-800 p-3">
          <div className="text-[10px] font-bold uppercase text-slate-400">Avg Accuracy</div>
          <div className="mt-1 text-lg font-extrabold text-emerald-300">{insights.avgAccuracy || '--'}%</div>
          <div className="text-[10px] text-slate-400">Across phases</div>
        </div>
        <div className="rounded-2xl bg-slate-900 border border-slate-800 p-3">
          <div className="text-[10px] font-bold uppercase text-slate-400">Perf. Elo</div>
          <div className="mt-1 text-lg font-extrabold text-cyan-300">{insights.avgEstimatedElo || '--'}</div>
          <div className="text-[10px] text-slate-400">Est. strength</div>
        </div>
      </div>

      <div className="rounded-2xl bg-slate-900 border border-cyan-500/25 p-3.5 flex items-start gap-2.5">
        <Target className="w-5 h-5 text-cyan-400 shrink-0 mt-0.5" />
        <div>
          <div className="text-xs font-bold text-cyan-200">BrillyDer Training Focus</div>
          <p className="text-xs text-slate-300 mt-0.5 leading-relaxed">{insights.recommendation}</p>
        </div>
      </div>

      <div className="rounded-2xl bg-slate-900 border border-slate-800 p-3.5">
        <div className="flex items-center gap-1.5 text-xs font-bold text-slate-200 mb-2">
          <Trophy className="w-4 h-4 text-amber-400" /> 5-Axis Skill Radar
        </div>
        <svg viewBox="0 0 240 225" className="w-full max-w-[260px] mx-auto">
          {[25, 50, 75, 100].map((ring) => (
            <polygon
              key={ring}
              points={axes.map((_, i) => { const p = pointAt(i, ring); return `${p.x.toFixed(1)},${p.y.toFixed(1)}`; }).join(' ')}
              fill="none" stroke="#1e293b" strokeWidth="1"
            />
          ))}
          {axes.map((a, i) => {
            const end = pointAt(i, 100);
            const lbl = pointAt(i, 122);
            return (
              <g key={a.key}>
                <line x1={cx} y1={cy} x2={end.x} y2={end.y} stroke="#1e293b" strokeWidth="1" />
                <text x={lbl.x} y={lbl.y} textAnchor="middle" dominantBaseline="middle" fill="#cbd5e1" fontSize="9" fontWeight="700">
                  {a.label} ({a.val})
                </text>
              </g>
            );
          })}
          <path d={radarPath} fill="rgba(34, 211, 238, 0.24)" stroke="#22d3ee" strokeWidth="2" />
        </svg>
      </div>

      <div className="rounded-2xl bg-slate-900 border border-slate-800 p-3.5 space-y-2.5">
        <div className="flex items-center gap-1.5 text-xs font-bold text-slate-200">
          <Flame className="w-4 h-4 text-rose-400" /> Blunder Rate by Game Phase
        </div>
        {insights.phaseStats.map((ps) => (
          <div key={ps.phase} className="space-y-1">
            <div className="flex justify-between text-xs">
              <span className="font-semibold text-slate-200">{ps.phase} ({ps.moves} moves)</span>
              <span className="font-mono text-slate-300">{ps.accuracy}% acc · {ps.blunderRatePer10Moves}/10 err</span>
            </div>
            <div className="w-full h-2 rounded-full bg-slate-800 overflow-hidden">
              <div className="h-full bg-gradient-to-r from-cyan-400 to-emerald-400" style={{ width: `${Math.min(100, ps.accuracy)}%` }} />
            </div>
          </div>
        ))}
      </div>

      <div className="rounded-2xl bg-slate-900 border border-slate-800 p-3.5 space-y-2">
        <div className="text-xs font-bold text-slate-200">Opening Repertoire Breakdown</div>
        {insights.openings.length === 0 ? (
          <p className="text-xs text-slate-400">Analyze games to see your London System, Modern Defense & opening win rates.</p>
        ) : (
          insights.openings.map((op) => (
            <div key={op.name} className="flex items-center justify-between gap-2 py-1.5 border-b border-slate-800/80 last:border-0 text-xs">
              <div className="min-w-0">
                <div className="font-semibold text-slate-100 truncate">{op.eco ? `${op.eco} · ` : ''}{op.name}</div>
                <div className="text-[11px] text-slate-400">{op.games} games ({op.wins}W-{op.draws}D-{op.losses}L)</div>
              </div>
              <div className="text-right shrink-0">
                <div className="font-mono font-bold text-cyan-300">{op.winRate}% win</div>
                <div className="text-[10px] font-mono text-emerald-300">{op.avgAccuracy}% acc</div>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
};
