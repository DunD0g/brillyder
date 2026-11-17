import React, { useMemo, useState } from 'react';
import { Zap } from 'lucide-react';
import { CLASSIFICATION_META, type AnalyzedPly, type MoveClassification } from '../types/chess';

interface Props {
  plies: AnalyzedPly[];
  currentPlyIndex: number;
  onJump: (plyIndex: number) => void;
}

type MomentFilter = 'all' | 'brilliant' | 'great' | 'mistake' | 'blunder';

const FILTERS: Array<{ key: MomentFilter; label: string; symbol: string; color: string }> = [
  { key: 'all', label: 'All turns', symbol: '⚡', color: '#cbd5e1' },
  { key: 'brilliant', label: 'Brilliant', symbol: '!!', color: CLASSIFICATION_META.brilliant.color },
  { key: 'great', label: 'Great', symbol: '!', color: CLASSIFICATION_META.great.color },
  { key: 'mistake', label: 'Mistakes', symbol: '?', color: CLASSIFICATION_META.mistake.color },
  { key: 'blunder', label: 'Blunders', symbol: '??', color: CLASSIFICATION_META.blunder.color },
];

export const KeyMomentsBar: React.FC<Props> = ({ plies, currentPlyIndex, onJump }) => {
  const [filter, setFilter] = useState<MomentFilter>('all');

  const moments = useMemo(() => {
    const wanted: MoveClassification[] = filter === 'all'
      ? ['brilliant', 'great', 'mistake', 'blunder']
      : filter === 'mistake'
        ? ['mistake', 'inaccuracy']
        : [filter];
    return plies.filter((p) => wanted.includes(p.classification));
  }, [plies, filter]);

  const counts = useMemo(() => {
    const c: Record<MomentFilter, number> = { all: 0, brilliant: 0, great: 0, mistake: 0, blunder: 0 };
    for (const p of plies) {
      if (p.classification === 'brilliant') { c.all++; c.brilliant++; }
      else if (p.classification === 'great') { c.all++; c.great++; }
      else if (p.classification === 'mistake' || p.classification === 'inaccuracy') { c.all++; c.mistake++; }
      else if (p.classification === 'blunder') { c.all++; c.blunder++; }
    }
    return c;
  }, [plies]);

  if (plies.length === 0) return null;

  return (
    <div className="glass-card p-3">
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-1.5 text-[11px] font-black uppercase tracking-[0.14em] text-slate-300">
          <Zap className="w-3.5 h-3.5 text-amber-400" /> Key moments
        </div>
        <span className="text-[10px] text-slate-500">{moments.length} turns</span>
      </div>

      <div className="mt-2 flex items-center gap-1.5 overflow-x-auto nice-scroll pb-1">
        {FILTERS.map((f) => (
          <button
            key={f.key}
            type="button"
            onClick={() => setFilter(f.key)}
            className={`shrink-0 inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[10px] font-bold border transition ${
              filter === f.key ? 'bg-slate-800 border-slate-500/70 text-white' : 'bg-slate-950/40 border-slate-800 text-slate-400 hover:border-slate-600'
            }`}
          >
            <span style={{ color: f.color }}>{f.symbol}</span>
            <span>{f.key === 'all' ? 'All' : CLASSIFICATION_META[f.key].label}</span>
            <span className="font-mono text-slate-500">{counts[f.key]}</span>
          </button>
        ))}
      </div>

      <div className="mt-1.5 max-h-28 overflow-y-auto nice-scroll pr-1">
        {moments.length === 0 ? (
          <p className="text-[11px] text-slate-500 py-2">No moments in this category — clean game!</p>
        ) : (
          <div className="flex flex-wrap gap-1.5">
            {moments.map((p) => {
              const meta = CLASSIFICATION_META[p.classification];
              const active = currentPlyIndex === p.ply;
              return (
                <button
                  key={p.ply}
                  type="button"
                  onClick={() => onJump(p.ply)}
                  className={`inline-flex items-center gap-1.5 rounded-lg px-2 py-1 text-[11px] font-mono border transition ${
                    active ? 'bg-cyan-500/20 border-cyan-400/60 text-cyan-100' : 'bg-slate-950/50 border-slate-800 text-slate-300 hover:border-slate-600'
                  }`}
                  title={`${p.coaching.headline} — jump to move`}
                >
                  <span className="text-slate-500">{p.moveNumber}{p.color === 'w' ? '.' : '…'}</span>
                  <span className="font-bold">{p.san}</span>
                  <span className="font-sans font-black" style={{ color: meta.color }}>{meta.symbol}</span>
                </button>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
};
