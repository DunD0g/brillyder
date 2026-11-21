import React from 'react';
import type { EngineScore, PlayerColor } from '../types/chess';

interface Props { score: EngineScore; orientation: PlayerColor; }

export const EvalBar: React.FC<Props> = ({ score, orientation }) => {
  const whitePct = Math.max(2, Math.min(98, score.winPercentWhite));
  const blackPct = 100 - whitePct;
  const whiteBottom = orientation === 'w';
  const topPct = whiteBottom ? blackPct : whitePct;
  const topIsWhite = !whiteBottom;
  const whiteWin = score.winPercentWhite >= 50;

  const compactText = score.display.length >= 5 ? 'text-[8px]' : 'text-[9px]';

  return (
    <div className="relative flex flex-col w-7 rounded-lg overflow-hidden border border-slate-700/80 bg-slate-900 select-none shrink-0">
      <div className={`w-full transition-all duration-300 ${topIsWhite ? 'bg-slate-100' : 'bg-slate-800'}`} style={{ height: `${topPct}%` }} />
      <div className={`w-full flex-1 transition-all duration-300 ${topIsWhite ? 'bg-slate-800' : 'bg-slate-100'}`} />
      <div
        className={`absolute left-0 right-0 text-center font-mono ${compactText} font-extrabold leading-none tracking-tighter py-1 ${
          whiteWin ? (whiteBottom ? 'bottom-0.5 text-slate-900' : 'top-0.5 text-slate-900') : whiteBottom ? 'top-0.5 text-slate-100' : 'bottom-0.5 text-slate-100'
        }`}
      >
        {score.display}
      </div>
    </div>
  );
};
