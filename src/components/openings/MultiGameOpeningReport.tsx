import React, { useMemo } from 'react';
import { ArrowUpRight, BarChart2, Flame } from 'lucide-react';
import type { AnalyzedGame } from '../../types/chess';
import type { OpeningCourse } from '../../types/openings';
import { buildOpeningReportCards } from '../../services/deviationDetector';
import type { UserHandleSpec } from '../../utils/player';

interface Props {
  analyzedGames: AnalyzedGame[];
  username: UserHandleSpec;
  courses: OpeningCourse[];
  onOpenGame: (gameId: string, ply: number) => void;
}

export const MultiGameOpeningReport: React.FC<Props> = ({
  analyzedGames,
  username,
  courses,
  onOpenGame,
}) => {
  const rows = useMemo(
    () => buildOpeningReportCards(analyzedGames, username, courses),
    [analyzedGames, username, courses]
  );

  if (rows.length === 0) {
    return (
      <div className="glass-card p-6 text-center">
        <BarChart2 className="mx-auto h-8 w-8 text-slate-600" />
        <h3 className="mt-2 text-sm font-extrabold text-white">No Opening Report Card yet</h3>
        <p className="mx-auto mt-1 max-w-md text-xs text-slate-400">
          Analyze a few synced games to track Games Played, W/D/L %, Average Eval at Move 10, and your most costly opening positions.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-2.5">
      <div className="flex items-center justify-between">
        <div>
          <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.16em] text-brilly">
            <BarChart2 className="h-3.5 w-3.5" /> Opening Report Card
          </div>
          <p className="text-[11px] text-slate-400">
            Performance across {analyzedGames.length} analyzed game{analyzedGames.length === 1 ? '' : 's'} grouped by ECO family.
          </p>
        </div>
      </div>

      <div className="grid gap-2.5 md:grid-cols-2">
        {rows.map((row) => {
          const evalColor = row.avgEvalMove10 === null
            ? 'text-slate-400'
            : row.avgEvalMove10 >= 0.4
              ? 'text-clean'
              : row.avgEvalMove10 <= -0.4
                ? 'text-blunder'
                : 'text-slate-200';
          return (
            <div key={`${row.eco}-${row.name}`} className="glass-card p-3.5">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <div className="flex items-center gap-1.5">
                    {row.eco && (
                      <span className="rounded bg-hull px-1.5 py-0.5 font-mono text-[9px] font-bold text-slate-300">
                        {row.eco}
                      </span>
                    )}
                    <h4 className="truncate text-xs font-extrabold text-white">{row.name}</h4>
                  </div>
                  <div className="mt-0.5 flex flex-wrap items-center gap-1.5 text-[10px] text-slate-400">
                    <span>
                      {row.games} game{row.games === 1 ? '' : 's'} · {row.wins}W-{row.draws}D-{row.losses}L · {row.avgAccuracy}% acc
                    </span>
                    {row.deviationCount > 0 && (
                      <span className="rounded-full border border-amber-400/35 bg-amber-500/10 px-1.5 py-0.5 font-mono text-[9px] font-bold text-amber-200">
                        {row.deviationCount} dev{row.deviationCount === 1 ? '' : 's'}
                      </span>
                    )}
                  </div>
                </div>
                <div className="shrink-0 text-right">
                  <div className="font-mono text-sm font-black text-brilly">{row.winRate}%</div>
                  <div className={`font-mono text-[10px] font-bold ${evalColor}`}>
                    M10: {row.avgEvalMove10 === null ? '—' : `${row.avgEvalMove10 >= 0 ? '+' : ''}${row.avgEvalMove10.toFixed(1)}`}
                  </div>
                </div>
              </div>

              <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-slate-800">
                <div
                  className="h-full rounded-full bg-gradient-to-r from-teal-400 to-purple-500"
                  style={{ width: `${row.winRate}%` }}
                />
              </div>

              {row.mostCostly && (
                <button
                  type="button"
                  onClick={() => onOpenGame(row.mostCostly!.gameId, row.mostCostly!.ply)}
                  className="mt-2.5 flex w-full items-center justify-between gap-2 rounded-xl border border-rose-500/25 bg-rose-500/[0.06] px-2.5 py-1.5 text-left text-[10px] text-rose-100 transition hover:border-rose-400/50"
                >
                  <span className="inline-flex min-w-0 items-center gap-1.5 truncate">
                    <Flame className="h-3 w-3 shrink-0 text-blunder" />
                    <span className="truncate">
                      Costliest: <strong className="font-mono">{row.mostCostly.moveNumber}{row.mostCostly.color === 'w' ? '.' : '…'}{row.mostCostly.san}</strong> (best {row.mostCostly.bestMoveSan}, -{row.mostCostly.winLoss.toFixed(0)}%)
                    </span>
                  </span>
                  <span className="inline-flex shrink-0 items-center gap-0.5 font-bold text-rose-200">
                    Fix <ArrowUpRight className="h-3 w-3" />
                  </span>
                </button>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
};
