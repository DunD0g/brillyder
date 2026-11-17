import React, { useMemo, useState } from 'react';
import { ChevronRight } from 'lucide-react';
import { CLASSIFICATION_META, type AnalyzedPly } from '../types/chess';

interface Props {
  plies: AnalyzedPly[];
  currentPlyIndex: number;
  onJump: (plyIndex: number) => void;
}

export const MoveList: React.FC<Props> = ({ plies, currentPlyIndex, onJump }) => {
  const [collapsed, setCollapsed] = useState(false);

  const pairs = useMemo(() => {
    const out: Array<{ n: number; w?: AnalyzedPly; b?: AnalyzedPly }> = [];
    for (let i = 0; i < plies.length; i += 2) {
      out.push({ n: Math.floor(i / 2) + 1, w: plies[i], b: plies[i + 1] });
    }
    return out;
  }, [plies]);

  return (
    <div className="glass-card overflow-hidden">
      <button
        type="button"
        onClick={() => setCollapsed((c) => !c)}
        className="w-full flex items-center justify-between px-3 py-2.5 text-left"
      >
        <span className="text-[11px] font-black uppercase tracking-[0.14em] text-slate-300">Move list</span>
        <span className="flex items-center gap-2 text-[10px] text-slate-500">
          {plies.length} plies
          <ChevronRight className={`w-3.5 h-3.5 transition-transform ${collapsed ? '' : 'rotate-90'}`} />
        </span>
      </button>
      {!collapsed && (
        <div className="px-2 pb-2.5 max-h-48 lg:max-h-[19rem] overflow-y-auto nice-scroll">
          {pairs.length === 0 ? (
            <p className="px-2 py-4 text-xs text-slate-500">No moves in this game.</p>
          ) : (
            <div className="grid grid-cols-1 xl:grid-cols-2 gap-x-3 gap-y-0.5">
              {pairs.map((pair) => (
                <div key={pair.n} className="grid grid-cols-[28px_1fr_1fr] items-center gap-1 text-xs">
                  <span className="text-slate-500 font-mono text-[10px] pl-1">{pair.n}.</span>
                  <MoveCell ply={pair.w} active={Boolean(pair.w && pair.w.ply === currentPlyIndex)} onJump={onJump} />
                  <MoveCell ply={pair.b} active={Boolean(pair.b && pair.b.ply === currentPlyIndex)} onJump={onJump} />
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
};

const MoveCell: React.FC<{ ply?: AnalyzedPly; active: boolean; onJump: (ply: number) => void }> = ({ ply, active, onJump }) => {
  if (!ply) return <span />;
  const meta = CLASSIFICATION_META[ply.classification];
  return (
    <button
      type="button"
      onClick={() => onJump(ply.ply)}
      className={`group flex items-center justify-between gap-1 px-1.5 py-[3px] rounded-md font-mono transition ${
        active ? 'bg-cyan-500/20 text-cyan-100 border border-cyan-400/50' : 'text-slate-300 hover:bg-slate-800/70 border border-transparent'
      }`}
      title={`${meta.label}: ${ply.coaching.headline}`}
    >
      <span className="truncate">{ply.san}</span>
      <span className="text-[10px] font-sans font-black shrink-0" style={{ color: meta.color }}>{meta.symbol}</span>
    </button>
  );
};
