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
  <div className={`flex items-center justify-between gap-2 rounded-xl border px-2.5 py-1.5 transition ${isActiveTurn ? 'border-teal-400/45 bg-hull/95 shadow-sm shadow-teal-500/10' : 'border-slate-800 bg-slate-900/75'}`}>
    <div className="flex min-w-0 items-center gap-2">
      <span className={`h-3.5 w-3.5 shrink-0 rounded-sm border ${color === 'w' ? 'border-slate-300 bg-slate-100' : 'border-slate-600 bg-slate-950'}`} />
      <div className="min-w-0">
        <div className="flex items-center gap-1.5">
          <span className="truncate text-xs font-semibold text-slate-100 sm:text-sm">{name}</span>
          {rating && <span className="shrink-0 font-mono text-[11px] text-slate-400">({rating})</span>}
          {accuracy !== undefined && (
            <span className="shrink-0 rounded bg-emerald-500/15 px-1.5 py-0.5 text-[10px] font-bold text-emerald-300">{accuracy.toFixed(1)}%</span>
          )}
        </div>
        <div className="flex min-h-[14px] items-center gap-1 text-[11px] text-slate-400">
          {capturedPieces.slice(0, 10).map((p, idx) => (
            <span key={idx} className="leading-none text-slate-300">{SYMBOLS[p as Exclude<PieceSymbol, 'k'>] ?? ''}</span>
          ))}
          {materialDiff > 0 && <span className="font-mono text-[10px] font-bold text-cyan-300">+{materialDiff}</span>}
          {estimatedElo !== undefined && <span className="ml-1 shrink-0 text-[10px] text-slate-400">Est. {estimatedElo}</span>}
        </div>
      </div>
    </div>
    {clockText && (
      <span className={`shrink-0 rounded-md px-2 py-0.5 font-mono text-xs font-semibold ${isActiveTurn ? 'border border-cyan-500/30 bg-cyan-500/20 text-cyan-200' : 'bg-slate-800 text-slate-300'}`}>
        {clockText}
      </span>
    )}
  </div>
);
