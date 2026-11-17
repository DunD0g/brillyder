import React from 'react';
import { AlarmClock, TimerOff } from 'lucide-react';
import type { ClockBucketStats } from '../types/chess';

interface Props {
  buckets: ClockBucketStats[];
}

export const TimeTroubleCard: React.FC<Props> = ({ buckets }) => {
  const totalMoves = buckets.reduce((sum, b) => sum + b.moves, 0);
  const lowBuckets = buckets.filter((b) => b.clockLimit <= 60);
  const lowMoves = lowBuckets.reduce((sum, b) => sum + b.moves, 0);
  const lowMistakes = lowBuckets.reduce((sum, b) => sum + b.mistakes, 0);
  const lowBlunders = lowBuckets.reduce((sum, b) => sum + b.blunders, 0);
  const lowErrors = lowMoves > 0 ? ((lowMistakes + lowBlunders) / lowMoves) * 10 : 0;
  const lowAccuracy = lowMoves > 0 ? lowBuckets.reduce((sum, b) => sum + b.accuracy * b.moves, 0) / lowMoves : 0;
  const worst = buckets.filter((b) => b.moves >= 3).sort((a, b) => b.errorsPer10Moves - a.errorsPer10Moves)[0];
  const hasClockData = totalMoves > 0;

  return (
    <div className="glass-card p-3.5">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
            <TimerOff className="h-4 w-4 text-rose-400" /> Time trouble analyzer
          </div>
          <p className="mt-0.5 text-[11px] text-slate-400">Blunder rate from PGN clock stamps</p>
        </div>
        {hasClockData && (
          <span className={`rounded-full border px-2 py-1 text-[10px] font-bold ${lowErrors >= 2.5 ? 'border-rose-500/30 bg-rose-500/10 text-rose-300' : 'border-emerald-500/30 bg-emerald-500/10 text-emerald-300'}`}>
            &lt;60s: {lowErrors.toFixed(1)} err/10
          </span>
        )}
      </div>

      {!hasClockData ? (
        <p className="py-5 text-center text-xs text-slate-500">No [%clk] clock data in these PGNs. Lichess and Chess.com live games usually include it.</p>
      ) : (
        <>
          <div className="mt-3 grid grid-cols-3 gap-2">
            <div className="rounded-xl border border-slate-800 bg-slate-950/50 p-2">
              <div className="text-[9px] font-bold uppercase tracking-wide text-slate-500">Low-clock acc</div>
              <div className="mt-0.5 font-mono text-base font-extrabold text-cyan-300">{lowAccuracy.toFixed(0)}%</div>
            </div>
            <div className="rounded-xl border border-slate-800 bg-slate-950/50 p-2">
              <div className="text-[9px] font-bold uppercase tracking-wide text-slate-500">Errors &lt;60s</div>
              <div className="mt-0.5 font-mono text-base font-extrabold text-orange-300">{lowMistakes + lowBlunders}</div>
            </div>
            <div className="rounded-xl border border-slate-800 bg-slate-950/50 p-2">
              <div className="text-[9px] font-bold uppercase tracking-wide text-slate-500">Worst bucket</div>
              <div className="mt-0.5 font-mono text-base font-extrabold text-rose-300">{worst ? worst.label : '—'}</div>
            </div>
          </div>

          <div className="mt-3 space-y-2">
            {buckets.map((bucket) => (
              <div key={bucket.label}>
                <div className="flex items-center justify-between text-[11px]">
                  <span className="inline-flex items-center gap-1 font-semibold text-slate-300">
                    <AlarmClock className="h-3 w-3 text-slate-500" /> {bucket.label}
                    <span className="text-[9px] text-slate-600">{bucket.moves} moves</span>
                  </span>
                  <span className="font-mono text-[10px] text-slate-400">
                    {bucket.moves > 0 ? `${bucket.accuracy}% · ${bucket.errorsPer10Moves}/10` : 'no samples'}
                  </span>
                </div>
                <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-slate-800">
                  <div
                    className={`h-full rounded-full ${bucket.errorsPer10Moves >= 3 ? 'bg-gradient-to-r from-orange-400 to-rose-500' : 'bg-gradient-to-r from-cyan-400 to-emerald-400'}`}
                    style={{ width: `${bucket.moves > 0 ? Math.max(6, Math.min(100, bucket.accuracy)) : 0}%` }}
                  />
                </div>
              </div>
            ))}
          </div>

          <p className="mt-2.5 rounded-lg border border-slate-800 bg-slate-950/40 px-2 py-1.5 text-[10px] leading-relaxed text-slate-400">
            {lowErrors >= 2.5
              ? `You make ${lowErrors.toFixed(1)} errors per 10 moves under one minute. Bank 20% of your clock before move 20 and pre-move only forced recaptures.`
              : 'Low-clock accuracy is holding up. Keep banking time and slow down before forcing captures.'}
          </p>
        </>
      )}
    </div>
  );
};
