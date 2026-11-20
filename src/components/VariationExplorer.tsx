import React from 'react';
import { FlaskConical, Loader2, RotateCcw, Sparkles } from 'lucide-react';
import type { EngineEval } from '../types/chess';
import { uciLineToSan } from '../utils/chessMath';

interface Props {
  active: boolean;
  baseLabel: string;
  fen: string;
  evalResult: EngineEval | null;
  loading: boolean;
  disabled?: boolean;
  onStart: () => void;
  onExit: () => void;
  onPlayLine: (uciMoves: string[]) => void;
}

export const VariationExplorer: React.FC<Props> = ({ active, baseLabel, fen, evalResult, loading, disabled, onStart, onExit, onPlayLine }) => {
  if (!active) {
    return (
      <div className="glass-card p-3 flex items-center justify-between gap-3">
        <div>
          <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
            <FlaskConical className="w-3.5 h-3.5 text-fuchsia-300" /> What If? Sandbox
          </div>
          <p className="mt-0.5 text-[11px] text-slate-400">Tap a piece, then tap a highlighted square to explore with live MultiPV 3.</p>
        </div>
        <button
          type="button"
          onClick={onStart}
          disabled={disabled}
          className="shrink-0 inline-flex items-center gap-1 rounded-xl bg-fuchsia-500/15 border border-fuchsia-400/35 px-2.5 py-2 text-[11px] font-bold text-fuchsia-200 disabled:opacity-40"
        >
          <Sparkles className="w-3.5 h-3.5" /> Explore
        </button>
      </div>
    );
  }

  const freshEval = evalResult && evalResult.fen === fen ? evalResult : null;
  const lines = freshEval?.lines ?? [];
  return (
    <div className="glass-card border-fuchsia-400/25 p-3">
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-1.5 text-xs font-bold text-fuchsia-100">
          <FlaskConical className="w-3.5 h-3.5 text-fuchsia-300" /> Live variation explorer
        </div>
        <button
          type="button"
          onClick={onExit}
          className="inline-flex items-center gap-1 rounded-lg bg-slate-800/80 border border-slate-700 px-2 py-1 text-[10px] font-bold text-slate-300"
        >
          <RotateCcw className="w-3 h-3" /> Back to game line
        </button>
      </div>
      <div className="mt-1 flex items-center justify-between text-[10px] text-slate-500">
        <span>Branch from {baseLabel}</span>
        <span className="inline-flex items-center gap-1 font-mono">
          {loading ? <><Loader2 className="w-3 h-3 animate-spin text-fuchsia-300" /> thinking</> : freshEval ? `D${freshEval.depth} · MultiPV 3` : 'waiting'}
        </span>
      </div>

      <div className="mt-2 space-y-1.5">
        {lines.length === 0 && (
          <div className={`h-14 rounded-xl border border-slate-800 ${loading ? 'shimmer' : 'bg-slate-950/40'}`} />
        )}
        {lines.map((line) => {
          const sanMoves = uciLineToSan(fen, line.pv, 9);
          return (
            <div key={line.multipv} className={`rounded-xl border px-2 py-1.5 ${line.multipv === 1 ? 'border-fuchsia-400/30 bg-fuchsia-500/10' : 'border-slate-800 bg-slate-950/45'}`}>
              <div className="flex items-center gap-2">
                <span className={`inline-flex h-4 min-w-[18px] items-center justify-center rounded px-1 text-[9px] font-black ${line.multipv === 1 ? 'bg-fuchsia-400 text-slate-950' : 'bg-slate-800 text-slate-400'}`}>
                  {line.multipv}
                </span>
                <span className={`font-mono text-[11px] font-extrabold ${line.multipv === 1 ? 'text-fuchsia-200' : 'text-slate-300'}`}>{line.score.display}</span>
                <div className="min-w-0 flex flex-wrap gap-x-0.5 gap-y-0.5 text-[11px] font-mono text-slate-300">
                  {sanMoves.map((san, idx) => (
                    <button
                      key={`${line.multipv}-${idx}`}
                      type="button"
                      onClick={() => onPlayLine(line.pv.slice(0, idx + 1))}
                      className="inline-flex min-h-[24px] items-center rounded-md px-1.5 py-0.5 touch-manipulation hover:bg-fuchsia-500/20 hover:text-fuchsia-200 active:bg-fuchsia-500/30"
                      title={`Play ${san}`}
                    >
                      {san}
                    </button>
                  ))}
                  {sanMoves.length > 0 && <span className="self-center text-slate-600">…</span>}
                </div>
              </div>
            </div>
          );
        })}
      </div>
      <p className="mt-2 text-[10px] text-slate-500">Tap any PV move to play it on the sandbox board. Eval updates live.</p>
    </div>
  );
};
