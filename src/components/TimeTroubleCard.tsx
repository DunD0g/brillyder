import React from 'react';
import { AlarmClock, Flame, TimerOff, Zap } from 'lucide-react';
import type { ClockBucketStats, ClockLeakSummary } from '../types/chess';
import { useVibe } from '../utils/vibeCopy';

interface Props {
  buckets: ClockBucketStats[];
  clockLeaks?: ClockLeakSummary;
  onTrainBlunders?: () => void;
}

export const TimeTroubleCard: React.FC<Props> = ({ buckets, clockLeaks, onTrainBlunders }) => {
  const { copy } = useVibe();
  const totalMoves = buckets.reduce((sum, b) => sum + b.moves, 0);
  const lowBuckets = buckets.filter((b) => b.clockLimit <= 60);
  const lowMoves = lowBuckets.reduce((sum, b) => sum + b.moves, 0);
  const lowMistakes = lowBuckets.reduce((sum, b) => sum + b.mistakes, 0);
  const lowBlunders = lowBuckets.reduce((sum, b) => sum + b.blunders, 0);
  const lowErrors = lowMoves > 0 ? ((lowMistakes + lowBlunders) / lowMoves) * 10 : 0;
  const lowAccuracy = lowMoves > 0 ? lowBuckets.reduce((sum, b) => sum + b.accuracy * b.moves, 0) / lowMoves : 0;
  const hasClockData = totalMoves > 0;

  return (
    <div className="glass-card p-3.5">
      <div className="flex items-start justify-between gap-2">
        <div>
          <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
            <TimerOff className="h-4 w-4 text-blunder" /> Clock Leaks: Impulse vs. Time Trouble
          </div>
          <p className="mt-0.5 text-[11px] text-slate-400">
            Parsed from PGN <code className="font-mono text-[10px]">[%clk]</code> timestamps
          </p>
        </div>
        {hasClockData && (
          <span
            className={`rounded-full border px-2 py-1 text-[10px] font-bold ${
              lowErrors >= 2.5
                ? 'border-rose-500/30 bg-rose-500/10 text-rose-300'
                : 'border-emerald-500/30 bg-emerald-500/10 text-emerald-300'
            }`}
          >
            &lt;60s: {lowErrors.toFixed(1)} err/10
          </span>
        )}
      </div>

      {!hasClockData ? (
        <p className="py-5 text-center text-xs text-slate-500">
          No [%clk] clock data in these PGNs. Lichess and Chess.com live games include it automatically.
        </p>
      ) : (
        <>
          <div className="mt-3 grid grid-cols-3 gap-2">
            <div className="rounded-xl border border-amber-500/25 bg-amber-500/[0.06] p-2">
              <div className="flex items-center gap-1 text-[9px] font-bold uppercase tracking-wide text-amber-300">
                <Zap className="h-3 w-3" /> Impulse
              </div>
              <div className="mt-0.5 font-mono text-base font-extrabold text-amber-200">
                {clockLeaks?.impulseBlunders ?? 0}
              </div>
              <div className="text-[9px] text-slate-500">&lt;5s w/ &gt;3m left</div>
            </div>
            <div className="rounded-xl border border-rose-500/25 bg-rose-500/[0.06] p-2">
              <div className="flex items-center gap-1 text-[9px] font-bold uppercase tracking-wide text-rose-300">
                <Flame className="h-3 w-3" /> Time-Trouble
              </div>
              <div className="mt-0.5 font-mono text-base font-extrabold text-rose-200">
                {clockLeaks?.timeTroubleBlunders ?? lowMistakes + lowBlunders}
              </div>
              <div className="text-[9px] text-slate-500">under 60s left</div>
            </div>
            <div className="rounded-xl border border-slate-800 bg-void/50 p-2">
              <div className="text-[9px] font-bold uppercase tracking-wide text-slate-500">Low-clock acc</div>
              <div className="mt-0.5 font-mono text-base font-extrabold text-brilly">{lowAccuracy.toFixed(0)}%</div>
              <div className="text-[9px] text-slate-500">
                {clockLeaks && clockLeaks.avgTimeSpentSec > 0 ? `avg ${clockLeaks.avgTimeSpentSec}s/mv` : '<60s'}
              </div>
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
                    className={`h-full rounded-full ${
                      bucket.errorsPer10Moves >= 3
                        ? 'bg-gradient-to-r from-orange-400 to-rose-500'
                        : 'bg-gradient-to-r from-teal-400 to-emerald-400'
                    }`}
                    style={{ width: `${bucket.moves > 0 ? Math.max(6, Math.min(100, bucket.accuracy)) : 0}%` }}
                  />
                </div>
              </div>
            ))}
          </div>

          <div className="mt-2.5 flex flex-wrap items-center justify-between gap-2 rounded-lg border border-slate-800 bg-void/45 px-2.5 py-2 text-[10px] text-slate-400">
            <span className="min-w-0 flex-1 leading-relaxed">
              {(clockLeaks?.impulseBlunders ?? 0) > (clockLeaks?.timeTroubleBlunders ?? 0)
                ? 'Impulse moves are costing you more than time trouble — pause 5 seconds on Checks-Captures-Threats when >3m remain.'
                : lowErrors >= 2.5
                  ? `You make ${lowErrors.toFixed(1)} errors per 10 moves under 60s. Bank 20% of your clock before move 20.`
                  : `Clock discipline is holding steady. Keep running ${copy.radarPingLabel} checks on sharp turns.`}
            </span>
            {onTrainBlunders && (
              <button
                type="button"
                onClick={onTrainBlunders}
                className="shrink-0 rounded-lg border border-teal-400/35 bg-teal-400/10 px-2.5 py-1 text-[10px] font-extrabold text-teal-200 hover:bg-teal-400/20"
              >
                Train This →
              </button>
            )}
          </div>
        </>
      )}
    </div>
  );
};
