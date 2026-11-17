import React from 'react';
import type { PieceSymbol } from 'chess.js';
import type { PlayerColor } from '../types/chess';

const SYMBOLS: Record<Exclude<PieceSymbol, 'k'>, string> = { q: '♛', r: '♜', b: '♝', n: '♞', p: '♟' };

interface Props {
  name: string;
  rating?: number;
  color: PlayerColor;
  isActiveTurn: boolean;
  accuracy?: number;
  estimatedElo?: number;
  clockText?: string;
  capturedPieces: PieceSymbol[];
  materialDiff: number;
}

export const PlayerBar: React.FC<Props> = ({ name, rating, color, isActiveTurn, accuracy, estimatedElo, clockText, capturedPieces, materialDiff }) => (
  <div className={`flex items-center justify-between gap-2 px-2.5 py-1.5 rounded-xl border ${isActiveTurn ? 'bg-slate-800/90 border-cyan-500/40' : 'bg-slate-900/75 border-slate-800'}`}>
    <div className="flex items-center gap-2 min-w-0">
      <span className={`w-3.5 h-3.5 rounded-sm border shrink-0 ${color === 'w' ? 'bg-slate-100 border-slate-300' : 'bg-slate-950 border-slate-600'}`} />
      <div className="min-w-0">
        <div className="flex items-center gap-1.5">
          <span className="font-semibold text-xs sm:text-sm text-slate-100 truncate max-w-[140px]">{name}</span>
          {rating && <span className="text-[11px] font-mono text-slate-400">({rating})</span>}
          {accuracy !== undefined && (
            <span className="px-1.5 py-0.5 rounded bg-emerald-500/15 text-emerald-300 text-[10px] font-bold">{accuracy.toFixed(1)}%</span>
          )}
        </div>
        <div className="flex items-center gap-1 text-[11px] text-slate-400 min-h-[14px]">
          {capturedPieces.slice(0, 10).map((p, idx) => (
            <span key={idx} className="leading-none text-slate-300">{SYMBOLS[p as Exclude<PieceSymbol, 'k'>] ?? ''}</span>
          ))}
          {materialDiff > 0 && <span className="text-[10px] font-mono font-bold text-cyan-300">+{materialDiff}</span>}
          {estimatedElo !== undefined && <span className="text-[10px] text-slate-400 ml-1">Est. {estimatedElo}</span>}
        </div>
      </div>
    </div>
    {clockText && (
      <span className={`px-2 py-0.5 rounded-md font-mono text-xs font-semibold shrink-0 ${isActiveTurn ? 'bg-cyan-500/20 text-cyan-200 border border-cyan-500/30' : 'bg-slate-800 text-slate-300'}`}>
        {clockText}
      </span>
    )}
  </div>
);
