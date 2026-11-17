import React, { useId } from 'react';
import { Activity, TrendingDown, TrendingUp } from 'lucide-react';
import type { AccuracyTrendPoint } from '../types/chess';

interface Props {
  trend: AccuracyTrendPoint[];
}

export const ActivityTrendChart: React.FC<Props> = ({ trend }) => {
  const gradientId = useId().replace(/:/g, '');
  const width = 360;
  const height = 120;
  const padX = 8;
  const top = 8;
  const bottom = 20;

  const values = trend.map((t) => t.accuracy);
  const avg = values.length > 0 ? values.reduce((a, b) => a + b, 0) / values.length : 0;
  const latest = values.length > 0 ? values[values.length - 1] : 0;
  const delta = latest - avg;

  const yFor = (acc: number) => top + (1 - Math.max(30, Math.min(100, acc)) / 100) * (height - top - bottom);
  const xFor = (i: number) => padX + (trend.length <= 1 ? 0 : (i / (trend.length - 1)) * (width - padX * 2));
  const line = trend.map((t, i) => `${i === 0 ? 'M' : 'L'} ${xFor(i).toFixed(1)} ${yFor(t.accuracy).toFixed(1)}`).join(' ');
  const area = trend.length > 0 ? `${line} L ${xFor(trend.length - 1)} ${height - bottom} L ${xFor(0)} ${height - bottom} Z` : '';

  const resultColor = (r: AccuracyTrendPoint['result']) => (r === 'W' ? '#34d399' : r === 'L' ? '#fb7185' : '#94a3b8');

  return (
    <div className="glass-card p-3.5">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
            <Activity className="h-4 w-4 text-cyan-400" /> Activity &amp; accuracy trend
          </div>
          <p className="mt-0.5 text-[11px] text-slate-400">Last {trend.length} analyzed game{trend.length === 1 ? '' : 's'}</p>
        </div>
        {trend.length > 0 && (
          <span className={`inline-flex items-center gap-1 rounded-full border px-2 py-1 text-[10px] font-bold ${delta >= 0 ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-300' : 'border-rose-500/30 bg-rose-500/10 text-rose-300'}`}>
            {delta >= 0 ? <TrendingUp className="h-3 w-3" /> : <TrendingDown className="h-3 w-3" />}
            {delta >= 0 ? '+' : ''}{delta.toFixed(1)}% vs avg
          </span>
        )}
      </div>

      {trend.length === 0 ? (
        <p className="py-6 text-center text-xs text-slate-500">Analyze games to build your accuracy trend.</p>
      ) : (
        <>
          <svg viewBox={`0 0 ${width} ${height}`} className="mt-2 w-full rounded-lg">
            <defs>
              <linearGradient id={`trend-${gradientId}`} x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#22d3ee" stopOpacity="0.38" />
                <stop offset="100%" stopColor="#22d3ee" stopOpacity="0.02" />
              </linearGradient>
            </defs>
            {[40, 55, 70, 85, 100].map((v) => (
              <g key={v}>
                <line x1={padX} x2={width - padX} y1={yFor(v)} y2={yFor(v)} stroke="#1e293b" strokeWidth="1" strokeDasharray={v === 70 ? '3 3' : undefined} />
                <text x={width - padX} y={yFor(v) - 2} textAnchor="end" fill="#475569" fontSize="7">{v}</text>
              </g>
            ))}
            <path d={area} fill={`url(#trend-${gradientId})`} />
            <path d={line} fill="none" stroke="#22d3ee" strokeWidth="2" strokeLinejoin="round" />
            {trend.map((t, i) => (
              <g key={`${t.date}-${i}`}>
                <circle cx={xFor(i)} cy={yFor(t.accuracy)} r="4" fill={resultColor(t.result)} stroke="#0b0f19" strokeWidth="1.5">
                  <title>{`${new Date(t.date).toLocaleDateString()} · ${t.accuracy.toFixed(1)}% · ${t.result} vs ${t.opponent} · ${t.opening}`}</title>
                </circle>
                <text x={xFor(i)} y={height - 5} textAnchor="middle" fill="#475569" fontSize="7">{t.result}</text>
              </g>
            ))}
          </svg>
          <div className="mt-1 flex items-center justify-between text-[10px] text-slate-500">
            <span>{new Date(trend[0].date).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}</span>
            <span className="font-mono">avg {avg.toFixed(1)}% · latest {latest.toFixed(1)}%</span>
            <span>{new Date(trend[trend.length - 1].date).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}</span>
          </div>
        </>
      )}
    </div>
  );
};
