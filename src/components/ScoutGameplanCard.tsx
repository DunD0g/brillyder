import React from 'react';
import { Crosshair, ExternalLink, Swords, Target } from 'lucide-react';
import type { ScoutGameplan } from '../services/scoutReport';

interface Props {
  gameplan: ScoutGameplan;
  onOpenGame: (gameId: string, ply: number) => void;
}

export const ScoutGameplanCard: React.FC<Props> = ({ gameplan, onOpenGame }) => {
  return (
    <section className="glass-card border-fuchsia-400/35 bg-gradient-to-br from-fuchsia-500/10 via-hull/90 to-void/90 p-3.5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <Crosshair className="h-4 w-4 text-fuchsia-300" />
          <span className="text-xs font-black uppercase tracking-[0.14em] text-fuchsia-200">
            Scout Gameplan · How to Beat {gameplan.opponentName}
          </span>
        </div>
        <span className="rounded-full border border-fuchsia-400/30 bg-fuchsia-500/15 px-2 py-0.5 font-mono text-[10px] font-bold text-fuchsia-200">
          {gameplan.gamesCount} games scouted
        </span>
      </div>

      {/* Favorite Openings + Weakest Targets */}
      <div className="mt-3 grid grid-cols-1 gap-2.5 md:grid-cols-3">
        <div className="min-w-0 rounded-xl border border-slate-800/90 bg-void/65 p-2.5">
          <div className="text-[10px] font-black uppercase tracking-wider text-slate-300">
            Their White Weapons
          </div>
          {gameplan.favoriteWhite.length === 0 ? (
            <p className="mt-1.5 text-[11px] text-slate-500">No White games in sample.</p>
          ) : (
            <ul className="mt-1.5 space-y-1">
              {gameplan.favoriteWhite.map((line) => (
                <li key={`w_${line.eco}_${line.openingName}`} className="flex items-center justify-between gap-2 text-[11px]">
                  <span className="min-w-0 truncate text-slate-200">
                    <span className="font-mono text-[9px] text-slate-500">{line.eco}</span> {line.openingName}
                  </span>
                  <span className="shrink-0 font-mono text-[10px] text-slate-400">
                    {line.games}g · {line.scorePct}%
                  </span>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="min-w-0 rounded-xl border border-slate-800/90 bg-void/65 p-2.5">
          <div className="text-[10px] font-black uppercase tracking-wider text-slate-300">
            Their Black Defenses
          </div>
          {gameplan.favoriteBlack.length === 0 ? (
            <p className="mt-1.5 text-[11px] text-slate-500">No Black games in sample.</p>
          ) : (
            <ul className="mt-1.5 space-y-1">
              {gameplan.favoriteBlack.map((line) => (
                <li key={`b_${line.eco}_${line.openingName}`} className="flex items-center justify-between gap-2 text-[11px]">
                  <span className="min-w-0 truncate text-slate-200">
                    <span className="font-mono text-[9px] text-slate-500">{line.eco}</span> {line.openingName}
                  </span>
                  <span className="shrink-0 font-mono text-[10px] text-slate-400">
                    {line.games}g · {line.scorePct}%
                  </span>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="min-w-0 rounded-xl border border-rose-500/25 bg-rose-500/5 p-2.5">
          <div className="flex items-center gap-1 text-[10px] font-black uppercase tracking-wider text-rose-300">
            <Target className="h-3 w-3" /> Softest Targets
          </div>
          {gameplan.weakestTargets.length === 0 ? (
            <p className="mt-1.5 text-[11px] text-slate-500">Not enough opening data yet.</p>
          ) : (
            <ul className="mt-1.5 space-y-1">
              {gameplan.weakestTargets.map((line) => (
                <li key={`t_${line.side}_${line.eco}_${line.openingName}`}>
                  <button
                    type="button"
                    onClick={() => onOpenGame(line.sampleGameId, 1)}
                    className="flex w-full items-center justify-between gap-1.5 rounded-lg px-1 py-0.5 text-left text-[11px] transition hover:bg-rose-500/10"
                  >
                    <span className="min-w-0 truncate text-slate-200">
                      <span className="mr-1 rounded bg-slate-800 px-1 font-mono text-[9px] uppercase text-slate-400">
                        {line.side === 'w' ? 'W' : 'B'}
                      </span>
                      {line.openingName}
                    </span>
                    <span className="inline-flex shrink-0 items-center gap-1 font-mono text-[10px] font-bold text-rose-300">
                      {line.scorePct}% <ExternalLink className="h-2.5 w-2.5" />
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>

      {/* Actionable Takeaways */}
      {gameplan.tacticalTakeaways.length > 0 && (
        <div className="mt-2.5 rounded-xl border border-slate-800/80 bg-void/55 p-2.5">
          <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-wider text-teal-300">
            <Swords className="h-3 w-3" /> Practical Match Plan
          </div>
          <ul className="mt-1.5 space-y-1">
            {gameplan.tacticalTakeaways.map((tip, idx) => (
              <li key={idx} className="text-[11px] leading-snug text-slate-300">
                • {tip}
              </li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
};
