import React from 'react';
import { AlertTriangle, ArrowRight, BookOpen, Compass, Search } from 'lucide-react';
import type { OpeningReport } from '../chess/openingBook';

interface Props {
  report: OpeningReport;
  onJumpToPly: (ply: number) => void;
  onExplorePly: (plyIndex: number) => void;
  onPlayBookMove: (plyIndex: number, san: string) => void;
}

export const OpeningReportCard: React.FC<Props> = ({ report, onJumpToPly, onExplorePly, onPlayBookMove }) => {
  const deviation = report.firstDeviation;
  const isUser = Boolean(deviation?.isUserMove);
  const openingName = report.openingName;

  if (!deviation && !report.recognized) {
    return (
      <div className="glass-card border-slate-700/70 p-3">
        <div className="flex items-center gap-1.5 text-xs font-bold text-slate-200">
          <Compass className="h-3.5 w-3.5 text-slate-400" /> Opening lab
        </div>
        <p className="mt-1 text-[11px] leading-relaxed text-slate-400">
          No book line recognised yet. Step through the opening or jump into the explorer to see theory moves.
        </p>
        <button
          type="button"
          onClick={() => onExplorePly(0)}
          className="mt-2 inline-flex min-h-[36px] items-center gap-1 rounded-xl border border-cyan-400/30 bg-cyan-500/10 px-2.5 py-1.5 text-[11px] font-bold text-cyan-200 active:bg-cyan-500/20"
        >
          <Search className="h-3.5 w-3.5" /> Explore from start
        </button>
      </div>
    );
  }

  if (!deviation && report.recognized) {
    return (
      <div className="glass-card border-emerald-500/30 p-3">
        <div className="flex items-start justify-between gap-2">
          <div className="flex min-w-0 items-center gap-1.5 text-xs font-bold text-emerald-200">
            <BookOpen className="h-3.5 w-3.5 text-emerald-300" /> Book opening
          </div>
          {report.recognized.eco && (
            <span className="shrink-0 rounded bg-emerald-500/15 px-1.5 py-0.5 text-[9px] font-bold text-emerald-300">{report.recognized.eco}</span>
          )}
        </div>
        <p className="mt-1 truncate text-[11px] font-semibold text-slate-200">{report.recognized.name}</p>
        <p className="mt-1 text-[10px] leading-relaxed text-slate-400">
          You followed book theory for {report.bookPlies} {report.bookPlies === 1 ? 'ply' : 'plies'}.
          {report.bookPlies < report.totalPlies ? ' Our recorded line ends here; the rest is your own plan.' : ' A clean start.'}
        </p>
        <div className="mt-2 flex items-center gap-1.5">
          <button
            type="button"
            onClick={() => onJumpToPly(Math.min(report.bookPlies, report.totalPlies))}
            className="inline-flex min-h-[36px] flex-1 items-center justify-center gap-1 rounded-xl border border-slate-700 bg-slate-900/80 px-2 py-1.5 text-[11px] font-bold text-slate-200 active:bg-slate-800"
          >
            <BookOpen className="h-3.5 w-3.5" /> Book end
          </button>
          <button
            type="button"
            onClick={() => onExplorePly(Math.min(report.bookPlies, report.totalPlies))}
            className="inline-flex min-h-[36px] flex-1 items-center justify-center gap-1 rounded-xl border border-emerald-400/30 bg-emerald-500/10 px-2 py-1.5 text-[11px] font-bold text-emerald-200 active:bg-emerald-500/20"
          >
            <Compass className="h-3.5 w-3.5" /> Explore
          </button>
        </div>
      </div>
    );
  }

  if (!deviation) return null;

  const moveLabel = `${deviation.moveNumber}${deviation.color === 'w' ? '.' : '…'} ${deviation.san}`;
  const accent = isUser
    ? {
        card: 'border-amber-500/35 bg-amber-500/[0.06]',
        text: 'text-amber-200',
        icon: 'text-amber-300',
        chip: 'border-amber-400/30 bg-amber-500/10 text-amber-200',
        button: 'border-amber-400/35 bg-amber-500/10 text-amber-100 active:bg-amber-500/20',
        bar: 'bg-amber-400',
      }
    : {
        card: 'border-sky-500/30 bg-sky-500/[0.05]',
        text: 'text-sky-200',
        icon: 'text-sky-300',
        chip: 'border-sky-400/30 bg-sky-500/10 text-sky-200',
        button: 'border-sky-400/35 bg-sky-500/10 text-sky-100 active:bg-sky-500/20',
        bar: 'bg-sky-400',
      };

  return (
    <div className={`glass-card ${accent.card} p-3`}>
      <div className="flex items-start justify-between gap-2">
        <div className={`flex items-center gap-1.5 text-xs font-bold ${accent.text}`}>
          {isUser ? <AlertTriangle className={`h-3.5 w-3.5 ${accent.icon}`} /> : <Compass className={`h-3.5 w-3.5 ${accent.icon}`} />}
          {isUser ? 'Book deviation' : 'Opponent left the book'}
        </div>
        {report.openingEco && (
          <span className={`shrink-0 rounded px-1.5 py-0.5 text-[9px] font-bold ${accent.chip}`}>{report.openingEco}</span>
        )}
      </div>

      {openingName && <p className="mt-1 truncate text-[11px] font-semibold text-slate-200">{openingName}</p>}

      <p className="mt-1 text-[11px] leading-relaxed text-slate-300">
        {isUser ? 'You left the book with ' : 'Your opponent left the book with '}
        <span className={`font-mono font-black ${accent.text}`}>{moveLabel}</span>
        {isUser ? '.' : '. You stayed in theory; the rest is now your own plan.'}
      </p>

      {deviation.expected.length > 0 && (
        <div className="mt-2">
          <div className="text-[9px] font-bold uppercase tracking-wider text-slate-500">Book expected</div>
          <div className="mt-1 flex flex-wrap gap-1">
            {deviation.expected.map((san) => (
              <button
                key={san}
                type="button"
                onClick={() => onPlayBookMove(deviation.ply - 1, san)}
                title={`Try the book move ${san}`}
                className={`inline-flex min-h-[30px] items-center rounded-lg border px-2 py-1 font-mono text-[11px] font-bold touch-manipulation ${accent.chip} active:brightness-125`}
              >
                {san}
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="mt-2 flex items-center gap-1.5">
        <button
          type="button"
          onClick={() => onJumpToPly(deviation.ply)}
          className={`inline-flex min-h-[36px] flex-1 items-center justify-center gap-1 rounded-xl border px-2 py-1.5 text-[11px] font-bold ${accent.button}`}
        >
          <ArrowRight className="h-3.5 w-3.5" /> Review move
        </button>
        <button
          type="button"
          onClick={() => onExplorePly(deviation.ply - 1)}
          className="inline-flex min-h-[36px] flex-1 items-center justify-center gap-1 rounded-xl border border-slate-700 bg-slate-900/80 px-2 py-1.5 text-[11px] font-bold text-slate-200 active:bg-slate-800"
        >
          <Compass className="h-3.5 w-3.5" /> Explore
        </button>
      </div>

      <p className="mt-1.5 text-[9px] leading-relaxed text-slate-500">
        Based on BrillyDer's offline opening book, not an engine verdict. Tap a book move to try it in the sandbox.
      </p>
    </div>
  );
};
