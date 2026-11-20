import React, { useState } from 'react';
import {
  AlertTriangle,
  ArrowRight,
  BookOpen,
  CheckCircle2,
  Compass,
  Plus,
  Search,
  Zap,
} from 'lucide-react';
import type { OpeningReport } from '../chess/openingBook';
import type { RepertoireDeviation } from '../services/deviationDetector';
import { useVibe } from '../utils/vibeCopy';

interface Props {
  report: OpeningReport;
  repertoireDeviation?: RepertoireDeviation | null;
  onJumpToPly: (ply: number) => void;
  onExplorePly: (plyIndex: number) => void;
  onPlayBookMove: (plyIndex: number, san: string) => void;
  onBoostDeviationToFsrs?: (deviation: RepertoireDeviation) => Promise<void>;
  onPatchDeviationGap?: (deviation: RepertoireDeviation) => Promise<void>;
}

export const OpeningReportCard: React.FC<Props> = ({
  report,
  repertoireDeviation,
  onJumpToPly,
  onExplorePly,
  onPlayBookMove,
  onBoostDeviationToFsrs,
  onPatchDeviationGap,
}) => {
  const { copy } = useVibe();
  const [boostedKey, setBoostedKey] = useState<string | null>(null);
  const [patchedKey, setPatchedKey] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const devKey = repertoireDeviation
    ? `${repertoireDeviation.kind}:${repertoireDeviation.ply}:${repertoireDeviation.playedSan}`
    : null;

  const handleBoost = async () => {
    if (!repertoireDeviation || !onBoostDeviationToFsrs || busy) return;
    setBusy(true);
    try {
      await onBoostDeviationToFsrs(repertoireDeviation);
      setBoostedKey(devKey);
    } finally {
      setBusy(false);
    }
  };

  const handlePatch = async () => {
    if (!repertoireDeviation || !onPatchDeviationGap || busy) return;
    setBusy(true);
    try {
      await onPatchDeviationGap(repertoireDeviation);
      setPatchedKey(devKey);
    } finally {
      setBusy(false);
    }
  };

  const leakPatcherBlock = repertoireDeviation ? (
    <div
      className={`glass-card p-3 ${
        repertoireDeviation.kind === 'user-deviation'
          ? 'border-purple-400/45 bg-purple-500/[0.08]'
          : 'border-teal-400/40 bg-teal-400/[0.06]'
      }`}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-1.5 text-xs font-extrabold text-white">
          {repertoireDeviation.kind === 'user-deviation' ? (
            <Zap className="h-3.5 w-3.5 text-warp" />
          ) : (
            <Compass className="h-3.5 w-3.5 text-brilly" />
          )}
          {repertoireDeviation.kind === 'user-deviation'
            ? `${copy.openingDeviation} (${repertoireDeviation.courseName})`
            : `Opponent Novelty vs ${repertoireDeviation.courseName}`}
        </div>
        <span className="shrink-0 rounded bg-void/70 px-1.5 py-0.5 font-mono text-[9px] font-bold text-slate-300">
          Move {repertoireDeviation.moveNumber}
        </span>
      </div>

      {repertoireDeviation.kind === 'user-deviation' ? (
        <>
          <p className="mt-1 text-[11px] leading-relaxed text-slate-200">
            You played{' '}
            <span className="font-mono font-black text-amber-300">
              {repertoireDeviation.moveNumber}{repertoireDeviation.color === 'w' ? '.' : '…'}{repertoireDeviation.playedSan}
            </span>{' '}
            instead of repertoire{' '}
            <span className="font-mono font-black text-brilly">
              {repertoireDeviation.expectedMoves.map((m) => m.expectedSan).join(' / ')}
            </span>
            {repertoireDeviation.evalBeforeDisplay && repertoireDeviation.evalAfterDisplay && (
              <span className="text-slate-400">
                {' '}({repertoireDeviation.evalBeforeDisplay} → {repertoireDeviation.evalAfterDisplay})
              </span>
            )}
            .
          </p>
          <div className="mt-2 flex flex-wrap gap-1.5">
            <button
              type="button"
              onClick={() => onJumpToPly(repertoireDeviation.ply)}
              className="inline-flex items-center gap-1 rounded-xl border border-slate-700 bg-hull px-2.5 py-1.5 text-[10px] font-bold text-slate-200"
            >
              <ArrowRight className="h-3 w-3" /> Jump to move
            </button>
            {onBoostDeviationToFsrs && (
              <button
                type="button"
                disabled={busy || boostedKey === devKey}
                onClick={() => void handleBoost()}
                className="inline-flex flex-1 items-center justify-center gap-1 rounded-xl bg-gradient-to-r from-purple-500 to-teal-400 px-2.5 py-1.5 text-[10px] font-extrabold text-slate-950 disabled:opacity-75"
              >
                {boostedKey === devKey ? (
                  <><CheckCircle2 className="h-3.5 w-3.5" /> Boosted to Today’s FSRS!</>
                ) : (
                  <><Zap className="h-3.5 w-3.5" /> Boost to Today’s FSRS Queue</>
                )}
              </button>
            )}
          </div>
        </>
      ) : (
        <>
          <p className="mt-1 text-[11px] leading-relaxed text-slate-200">
            Opponent surprised you with{' '}
            <span className="font-mono font-black text-teal-200">
              {repertoireDeviation.moveNumber}{repertoireDeviation.color === 'w' ? '.' : '…'}{repertoireDeviation.playedSan}
            </span>
            {repertoireDeviation.recommendedReplySan
              ? `. Stockfish suggests ${repertoireDeviation.recommendedReplySan} in reply.`
              : ' — not covered in your repertoire yet.'}
          </p>
          <div className="mt-2 flex flex-wrap gap-1.5">
            <button
              type="button"
              onClick={() => onJumpToPly(repertoireDeviation.ply)}
              className="inline-flex items-center gap-1 rounded-xl border border-slate-700 bg-hull px-2.5 py-1.5 text-[10px] font-bold text-slate-200"
            >
              <ArrowRight className="h-3 w-3" /> Inspect
            </button>
            {onPatchDeviationGap && repertoireDeviation.recommendedReplySan && (
              <button
                type="button"
                disabled={busy || patchedKey === devKey}
                onClick={() => void handlePatch()}
                className="inline-flex flex-1 items-center justify-center gap-1 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-2.5 py-1.5 text-[10px] font-extrabold text-slate-950 disabled:opacity-75"
              >
                {patchedKey === devKey ? (
                  <><CheckCircle2 className="h-3.5 w-3.5" /> Patched into Repertoire!</>
                ) : (
                  <><Plus className="h-3.5 w-3.5" /> Patch Gap ({repertoireDeviation.recommendedReplySan})</>
                )}
              </button>
            )}
          </div>
        </>
      )}
    </div>
  ) : null;

  const deviation = report.firstDeviation;
  const isUser = Boolean(deviation?.isUserMove);
  const openingName = report.openingName;

  if (!deviation && !report.recognized) {
    return (
      <div className="space-y-2.5">
        {leakPatcherBlock}
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
      </div>
    );
  }

  if (!deviation && report.recognized) {
    return (
      <div className="space-y-2.5">
        {leakPatcherBlock}
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
      </div>
    );
  }

  if (!deviation) return leakPatcherBlock;

  const moveLabel = `${deviation.moveNumber}${deviation.color === 'w' ? '.' : '…'} ${deviation.san}`;
  const accent = isUser
    ? {
        card: 'border-amber-500/35 bg-amber-500/[0.06]',
        text: 'text-amber-200',
        icon: 'text-amber-300',
        chip: 'border-amber-400/30 bg-amber-500/10 text-amber-200',
        button: 'border-amber-400/35 bg-amber-500/10 text-amber-100 active:bg-amber-500/20',
      }
    : {
        card: 'border-sky-500/30 bg-sky-500/[0.05]',
        text: 'text-sky-200',
        icon: 'text-sky-300',
        chip: 'border-sky-400/30 bg-sky-500/10 text-sky-200',
        button: 'border-sky-400/35 bg-sky-500/10 text-sky-100 active:bg-sky-500/20',
      };

  return (
    <div className="space-y-2.5">
      {leakPatcherBlock}
      <div className={`glass-card ${accent.card} p-3`}>
        <div className="flex items-start justify-between gap-2">
          <div className={`flex items-center gap-1.5 text-xs font-bold ${accent.text}`}>
            {isUser ? <AlertTriangle className={`h-3.5 w-3.5 ${accent.icon}`} /> : <Compass className={`h-3.5 w-3.5 ${accent.icon}`} />}
            {isUser ? copy.openingDeviation : 'Opponent left the book'}
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
      </div>
    </div>
  );
};
