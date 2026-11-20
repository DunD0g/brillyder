import React, { useMemo, useState } from 'react';
import { Chess } from 'chess.js';
import {
  ChevronLeft,
  ChevronRight,
  Compass,
  Play,
  RotateCcw,
  ShieldCheck,
  Sparkles,
  Target,
} from 'lucide-react';
import type { BoardThemeId } from '../../types/chess';
import type { OpeningCourse } from '../../types/openings';
import { useVibe } from '../../utils/vibeCopy';
import { ChessgroundBoard } from '../ChessgroundBoard';

interface Props {
  course: OpeningCourse;
  boardTheme: BoardThemeId;
  onStartWalkthrough: () => void;
  onStartDrill: () => void;
}

export const MothershipCard: React.FC<Props> = ({
  course,
  boardTheme,
  onStartWalkthrough,
  onStartDrill,
}) => {
  const { vibe, copy } = useVibe();
  const { previewMoves, arrows, highlights, corePlans, goldenRules } = course.mothershipSetup;
  const [step, setStep] = useState(previewMoves.length);

  // Reset step to final target shape whenever the course changes
  React.useEffect(() => {
    setStep(course.mothershipSetup.previewMoves.length);
  }, [course.id, course.mothershipSetup.previewMoves.length]);

  React.useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.tagName === 'SELECT' || target.isContentEditable)) return;
      if (e.key === 'ArrowLeft') { e.preventDefault(); setStep((s) => Math.max(0, s - 1)); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); setStep((s) => Math.min(previewMoves.length, s + 1)); }
      else if (e.key === 'Home') { e.preventDefault(); setStep(0); }
      else if (e.key === 'End') { e.preventDefault(); setStep(previewMoves.length); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [previewMoves.length]);

  const { fen, lastMove } = useMemo(() => {
    const chess = new Chess();
    let last: [string, string] | undefined;
    const limit = Math.min(step, previewMoves.length);
    for (let i = 0; i < limit; i++) {
      try {
        const mv = chess.move(previewMoves[i]);
        last = [mv.from, mv.to];
      } catch {
        break;
      }
    }
    return { fen: chess.fen(), lastMove: last };
  }, [previewMoves, step]);

  const atTarget = step >= previewMoves.length;
  const orientation = course.side === 'white' ? 'w' : 'b';

  return (
    <div className="grid gap-3 lg:grid-cols-[minmax(0,380px)_minmax(0,1fr)]">
      <div className="glass-card glass-card-strong p-3">
        <div className="mb-2 flex items-center justify-between gap-2">
          <span className="inline-flex items-center gap-1 rounded-full border border-teal-400/35 bg-teal-400/10 px-2 py-0.5 text-[9px] font-black uppercase tracking-wider text-teal-200">
            <Compass className="h-3 w-3" /> {copy.mothershipBadge}
          </span>
          <span className="font-mono text-[10px] text-slate-400">
            {step}/{previewMoves.length} plies
          </span>
        </div>

        <ChessgroundBoard
          fen={fen}
          orientation={orientation}
          lastMove={lastMove}
          interactive={false}
          showBestArrow={false}
          showPlayedArrow={false}
          customArrows={atTarget ? arrows : undefined}
          squareHighlights={atTarget ? highlights : undefined}
          theme={boardTheme}
        />

        <div className="mt-2.5 flex items-center gap-1.5">
          <button
            type="button"
            onClick={() => setStep(0)}
            disabled={step === 0}
            className="rounded-xl border border-slate-800 bg-void/70 p-2 text-slate-300 hover:border-slate-600 disabled:opacity-40"
            aria-label="Reset formation preview"
          >
            <RotateCcw className="h-3.5 w-3.5" />
          </button>
          <button
            type="button"
            onClick={() => setStep((s) => Math.max(0, s - 1))}
            disabled={step === 0}
            className="rounded-xl border border-slate-800 bg-void/70 p-2 text-slate-300 hover:border-slate-600 disabled:opacity-40"
            aria-label="Previous setup move"
          >
            <ChevronLeft className="h-3.5 w-3.5" />
          </button>
          <button
            type="button"
            onClick={() => setStep(previewMoves.length)}
            className={`flex-1 rounded-xl border px-2.5 py-2 text-[10px] font-black uppercase tracking-wider transition ${
              atTarget
                ? 'border-teal-400/45 bg-teal-400/15 text-teal-200'
                : 'border-slate-700 bg-hull text-slate-300 hover:border-teal-400/40'
            }`}
          >
            Target Shape
          </button>
          <button
            type="button"
            onClick={() => setStep((s) => Math.min(previewMoves.length, s + 1))}
            disabled={atTarget}
            className="rounded-xl border border-slate-800 bg-void/70 p-2 text-slate-300 hover:border-slate-600 disabled:opacity-40"
            aria-label="Next setup move"
          >
            <ChevronRight className="h-3.5 w-3.5" />
          </button>
        </div>

        <div className="mt-2 flex flex-wrap gap-2 text-[9px] text-slate-400">
          <span className="inline-flex items-center gap-1">
            <span className="h-2 w-2 rounded-full bg-brilly" /> Plan
          </span>
          <span className="inline-flex items-center gap-1">
            <span className="h-2 w-2 rounded-full bg-warp" /> Outpost
          </span>
          <span className="inline-flex items-center gap-1">
            <span className="h-2 w-2 rounded-full bg-clean" /> Key Move
          </span>
          <span className="inline-flex items-center gap-1">
            <span className="h-2 w-2 rounded-full bg-blunder" /> Target / Threat
          </span>
        </div>
      </div>

      <div className="flex flex-col gap-3">
        <div className="glass-card p-4">
          <div className="flex items-start justify-between gap-2">
            <div>
              <div className="text-[10px] font-black uppercase tracking-[0.16em] text-warp">
                {vibe === 'cosmic' ? course.codename : `${course.side} repertoire`}
              </div>
              <h2 className="mt-0.5 text-lg font-extrabold text-white">{course.name}</h2>
            </div>
            <span className="rounded-lg border border-slate-700 bg-void/70 px-2 py-1 text-[10px] font-bold text-slate-300">
              {course.difficulty}
            </span>
          </div>
          <p className="mt-1.5 text-xs leading-relaxed text-slate-300">{course.tagline}</p>

          <div className="mt-3 flex flex-wrap gap-2">
            <button
              type="button"
              onClick={onStartWalkthrough}
              className="inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-3.5 py-2 text-xs font-extrabold text-slate-950 transition hover:brightness-110"
            >
              <Play className="h-3.5 w-3.5" /> Guided Walkthrough
            </button>
            <button
              type="button"
              onClick={onStartDrill}
              className="inline-flex items-center gap-1.5 rounded-xl border border-purple-400/40 bg-purple-500/15 px-3.5 py-2 text-xs font-extrabold text-purple-200 transition hover:bg-purple-500/25"
            >
              <Sparkles className="h-3.5 w-3.5" /> FSRS Drill
            </button>
          </div>
        </div>

        <div className="glass-card p-3.5">
          <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.16em] text-brilly">
            <Target className="h-3.5 w-3.5" /> 3 Middlegame Plans
          </div>
          <ul className="mt-2 space-y-2 text-xs leading-relaxed text-slate-200">
            {corePlans.map((plan, idx) => (
              <li key={idx} className="flex gap-2 rounded-xl border border-slate-800/80 bg-void/50 p-2.5">
                <span className="inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-lg bg-teal-400/15 font-mono text-[10px] font-black text-brilly">
                  {idx + 1}
                </span>
                <span>{plan}</span>
              </li>
            ))}
          </ul>
        </div>

        <div className="glass-card p-3.5">
          <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.16em] text-amber-300">
            <ShieldCheck className="h-3.5 w-3.5" /> Golden Rules
          </div>
          <ul className="mt-2 space-y-1.5 text-[11px] leading-relaxed text-slate-300">
            {goldenRules.map((rule, idx) => (
              <li key={idx} className="flex gap-2">
                <span className="font-black text-amber-400">•</span>
                <span>{rule}</span>
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
};
