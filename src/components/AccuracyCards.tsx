import React from 'react';
import type { AnalyzedGame, LichessGameRecord, PlayerColor } from '../types/chess';
import { ProgressRing } from './ProgressRing';

interface Props {
  analyzed: AnalyzedGame;
  game: LichessGameRecord;
}

export const AccuracyCards: React.FC<Props> = ({ analyzed, game }) => (
  <div className="grid grid-cols-2 gap-2">
    {(['w', 'b'] as PlayerColor[]).map((color) => {
      const summary = color === 'w' ? analyzed.whiteSummary : analyzed.blackSummary;
      const player = color === 'w' ? game.white : game.black;
      return (
        <div key={color} className="glass-card flex items-center gap-2.5 p-2.5">
          <ProgressRing
            value={summary.accuracy}
            size={56}
            stroke={5}
            tone={summary.accuracy >= 85 ? 'emerald' : summary.accuracy >= 70 ? 'cyan' : 'amber'}
            label={`${summary.accuracy.toFixed(0)}%`}
          />
          <div className="min-w-0">
            <div className="flex items-center gap-1.5">
              <span className={`h-2.5 w-2.5 shrink-0 rounded-full border ${color === 'w' ? 'border-slate-300 bg-white' : 'border-slate-500 bg-slate-950'}`} />
              <span className="truncate text-[11px] font-bold text-slate-100">{player.name}</span>
            </div>
            <div className="mt-0.5 flex items-baseline gap-1">
              <span className="font-mono text-sm font-extrabold text-cyan-300">{summary.estimatedElo}</span>
              <span className="text-[9px] uppercase tracking-wide text-slate-500">est.</span>
            </div>
            <div className="mt-0.5 flex flex-wrap gap-x-1 text-[9px] font-bold">
              {summary.counts.brilliant > 0 && <span className="text-cyan-300">!! {summary.counts.brilliant}</span>}
              {summary.counts.great > 0 && <span className="text-blue-300">! {summary.counts.great}</span>}
              {summary.counts.mistake > 0 && <span className="text-orange-300">? {summary.counts.mistake}</span>}
              {summary.counts.blunder > 0 && <span className="text-red-400">?? {summary.counts.blunder}</span>}
            </div>
          </div>
        </div>
      );
    })}
  </div>
);
