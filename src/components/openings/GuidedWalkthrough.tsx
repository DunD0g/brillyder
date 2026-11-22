import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Chess } from 'chess.js';
import {
  AlertTriangle,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  LockOpen,
  Play,
  RotateCcw,
  Sparkles,
} from 'lucide-react';
import type { BoardThemeId } from '../../types/chess';
import type { BoardArrow, OpeningCourse, OpeningLine, WrongMoveTrap } from '../../types/openings';
import { soundManager } from '../../utils/sound';
import { useVibe } from '../../utils/vibeCopy';
import { ChessgroundBoard } from '../ChessgroundBoard';

interface Props {
  course: OpeningCourse;
  line: OpeningLine;
  boardTheme: BoardThemeId;
  unlocked: boolean;
  onUnlockLine: (line: OpeningLine) => void;
  onStartDrillForLine: (line: OpeningLine) => void;
}

interface TrapPlayback {
  trap: WrongMoveTrap;
  fen: string;
  lastMove?: [string, string];
  stepLabel: string;
  arrows: BoardArrow[];
  done: boolean;
}

export const GuidedWalkthrough: React.FC<Props> = ({
  course,
  line,
  boardTheme,
  unlocked,
  onUnlockLine,
  onStartDrillForLine,
}) => {
  const { vibe } = useVibe();
  const [step, setStep] = useState(0);
  const [trapPlayback, setTrapPlayback] = useState<TrapPlayback | null>(null);
  const timersRef = useRef<number[]>([]);

  const clearTimers = () => {
    for (const id of timersRef.current) window.clearTimeout(id);
    timersRef.current = [];
  };

  useEffect(() => {
    clearTimers();
    setStep(0);
    setTrapPlayback(null);
    return clearTimers;
  }, [line.id]);

  const positions = useMemo(() => {
    const chess = new Chess();
    const list: Array<{ fen: string; lastMove?: [string, string]; san?: string }> = [
      { fen: chess.fen() },
    ];
    for (const san of line.moves) {
      const mv = chess.move(san);
      list.push({ fen: chess.fen(), lastMove: [mv.from, mv.to], san: mv.san });
    }
    return list;
  }, [line.moves]);

  // Active annotation is either the move just played (step - 1) or the upcoming move (step)
  const activeAnnotation = useMemo(() => {
    if (step > 0) {
      const justPlayed = line.annotations.find((a) => a.ply === step - 1);
      if (justPlayed) return justPlayed;
    }
    return line.annotations.find((a) => a.ply === step) ?? null;
  }, [line.annotations, step]);

  const currentPos = positions[Math.min(step, positions.length - 1)] ?? positions[0];
  const atEnd = step >= line.moves.length;
  const orientation = course.side === 'white' ? 'w' : 'b';

  const stepTo = (next: number) => {
    clearTimers();
    setTrapPlayback(null);
    const clamped = Math.max(0, Math.min(line.moves.length, next));
    setStep(clamped);
    if (clamped > step) soundManager.playMove();
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      if (document.querySelector('[aria-modal="true"]')) return;
      const target = e.target as HTMLElement | null;
      if (target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.tagName === 'SELECT' || target.isContentEditable)) return;
      if (e.key === 'ArrowLeft') { e.preventDefault(); stepTo(step - 1); }
      else if (e.key === 'ArrowRight') { e.preventDefault(); stepTo(step + 1); }
      else if (e.key === 'Home') { e.preventDefault(); stepTo(0); }
      else if (e.key === 'End') { e.preventDefault(); stepTo(line.moves.length); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [step, line.moves.length]);

  const previewTrap = (trap: WrongMoveTrap, annPly: number) => {
    clearTimers();
    soundManager.unlock();
    const baseFen = positions[annPly]?.fen;
    if (!baseFen) return;

    const board = new Chess(baseFen);
    let wrongMv;
    try {
      wrongMv = board.move(trap.playedSan);
    } catch {
      return;
    }
    soundManager.playHullThud();
    const firstArrows: BoardArrow[] = trap.arrows?.length
      ? trap.arrows
      : [{ from: wrongMv.from, to: wrongMv.to, color: 'threat' }];

    setTrapPlayback({
      trap,
      fen: board.fen(),
      lastMove: [wrongMv.from, wrongMv.to],
      stepLabel: `Mistake: ${wrongMv.san}`,
      arrows: firstArrows,
      done: trap.punishmentLine.length === 0,
    });

    const seqBoards: Array<{ fen: string; lastMove: [string, string]; san: string; arrow: BoardArrow }> = [];
    for (const pSan of trap.punishmentLine) {
      try {
        const pmv = board.move(pSan);
        seqBoards.push({
          fen: board.fen(),
          lastMove: [pmv.from, pmv.to],
          san: pmv.san,
          arrow: { from: pmv.from, to: pmv.to, color: 'threat' },
        });
      } catch {
        break;
      }
    }

    seqBoards.forEach((frame, idx) => {
      const id = window.setTimeout(() => {
        soundManager.playCapture();
        setTrapPlayback({
          trap,
          fen: frame.fen,
          lastMove: frame.lastMove,
          stepLabel: `Punishment: ${frame.san}`,
          arrows: [...(trap.arrows ?? []), frame.arrow],
          done: idx === seqBoards.length - 1,
        });
      }, 750 * (idx + 1));
      timersRef.current.push(id);
    });
  };

  const activeFen = trapPlayback ? trapPlayback.fen : currentPos.fen;
  const activeLastMove = trapPlayback ? trapPlayback.lastMove : currentPos.lastMove;
  const activeArrows = trapPlayback ? trapPlayback.arrows : activeAnnotation?.arrows;
  const activeHighlights = trapPlayback ? undefined : activeAnnotation?.highlights;

  const progressPct = line.moves.length > 0 ? Math.round((step / line.moves.length) * 100) : 0;

  return (
    <div className="grid grid-cols-1 gap-3 lg:grid-cols-[minmax(0,400px)_minmax(0,1fr)]">
      <div className="min-w-0 glass-card glass-card-strong p-3">
        <div className="mb-1.5 flex items-center justify-between gap-2 text-[10px]">
          <span className="min-w-0 truncate font-bold text-slate-200">
            {line.eco ? `${line.eco} · ` : ''}{line.title}
          </span>
          <span className="shrink-0 font-mono text-brilly">
            Ply {step}/{line.moves.length}
          </span>
        </div>

        <div className="mb-2 tractor-beam-track h-1 w-full">
          <div className="tractor-beam-fill" style={{ width: `${progressPct}%` }} />
        </div>

        <div className="mx-auto w-full max-w-[min(100%,calc(100dvh-21rem))] lg:max-w-none">
          <ChessgroundBoard
            fen={activeFen}
            orientation={orientation}
            lastMove={activeLastMove}
            interactive={false}
            showBestArrow={false}
            showPlayedArrow={false}
            customArrows={activeArrows}
            squareHighlights={activeHighlights}
            theme={boardTheme}
            onSwipePrev={() => stepTo(step - 1)}
            onSwipeNext={() => stepTo(step + 1)}
          />
        </div>

        <div className="mt-2.5 flex items-center gap-1.5">
          <button
            type="button"
            onClick={() => stepTo(0)}
            disabled={step === 0 && !trapPlayback}
            className="rounded-xl border border-slate-800 bg-void/70 p-2.5 text-slate-300 transition hover:border-slate-600 active:scale-95 disabled:opacity-40"
            aria-label="Back to start"
          >
            <RotateCcw className="h-4 w-4" />
          </button>
          <button
            type="button"
            onClick={() => stepTo(step - 1)}
            disabled={step === 0}
            className="inline-flex flex-1 items-center justify-center gap-1 rounded-xl border border-slate-800 bg-void/70 py-2.5 text-xs font-bold text-slate-200 transition hover:border-slate-600 active:scale-[0.98] disabled:opacity-40"
          >
            <ChevronLeft className="h-4 w-4" /> Prev
          </button>
          <button
            type="button"
            onClick={() => stepTo(step + 1)}
            disabled={atEnd}
            className="inline-flex flex-1 items-center justify-center gap-1 rounded-xl border border-teal-400/40 bg-teal-400/15 py-2.5 text-xs font-black text-teal-200 transition hover:bg-teal-400/25 active:scale-[0.98] disabled:opacity-40"
          >
            Next <ChevronRight className="h-4 w-4" />
          </button>
        </div>

        {/* Inline live step callout on mobile so users see the active plan right below the board without scrolling */}
        <div className="mt-2 rounded-xl border border-slate-800/90 bg-void/70 px-2.5 py-2 lg:hidden">
          {trapPlayback ? (
            <div className="space-y-1">
              <div className="flex items-center justify-between gap-2">
                <span className="inline-flex items-center gap-1 text-[10px] font-black uppercase tracking-wider text-blunder">
                  <AlertTriangle className="h-3 w-3 shrink-0" /> {trapPlayback.stepLabel}
                </span>
                <button
                  type="button"
                  onClick={() => { clearTimers(); setTrapPlayback(null); }}
                  className="rounded-md border border-slate-700 bg-hull px-1.5 py-0.5 text-[9px] font-bold text-slate-300"
                >
                  Mainline
                </button>
              </div>
              <p className="text-[11px] leading-snug text-rose-100">{trapPlayback.trap.reason}</p>
            </div>
          ) : activeAnnotation ? (
            <div className="space-y-1">
              <div className="flex items-center justify-between gap-2">
                <span className="rounded bg-teal-400/15 px-1.5 py-0.5 font-mono text-[10px] font-black text-brilly">
                  {Math.floor(activeAnnotation.ply / 2) + 1}
                  {activeAnnotation.ply % 2 === 0 ? '.' : '…'}
                  {line.moves[activeAnnotation.ply]}
                </span>
                {activeAnnotation.wrongMoveTraps && activeAnnotation.wrongMoveTraps.length > 0 && (
                  <button
                    type="button"
                    onClick={() => previewTrap(activeAnnotation.wrongMoveTraps![0], activeAnnotation.ply)}
                    className="inline-flex items-center gap-1 rounded-md border border-rose-400/40 bg-rose-500/15 px-2 py-0.5 text-[9px] font-black text-rose-200"
                  >
                    <Play className="h-2.5 w-2.5" /> Why not {activeAnnotation.wrongMoveTraps[0].playedSan}?
                  </button>
                )}
              </div>
              <p className="text-[11px] leading-snug text-slate-200">{activeAnnotation.plan}</p>
            </div>
          ) : (
            <p className="text-[11px] leading-snug text-slate-400">
              {step === 0
                ? 'Tap Next or swipe the board to step through the line.'
                : `Development move (${line.moves[step - 1]}). Tap Next for the next key idea.`}
            </p>
          )}
        </div>

        <div className="mt-2 flex flex-wrap gap-1">
          {line.moves.map((san, idx) => {
            const isCurrent = step === idx + 1;
            const hasAnn = line.annotations.some((a) => a.ply === idx);
            return (
              <button
                key={idx}
                type="button"
                onClick={() => stepTo(idx + 1)}
                className={`rounded-lg px-1.5 py-0.5 font-mono text-[10px] font-bold transition ${
                  isCurrent
                    ? 'bg-teal-400/25 text-teal-100 ring-1 ring-teal-400/60'
                    : hasAnn
                      ? 'bg-purple-500/15 text-purple-200 hover:bg-purple-500/25'
                      : 'bg-void/60 text-slate-400 hover:text-slate-200'
                }`}
              >
                {idx % 2 === 0 ? `${Math.floor(idx / 2) + 1}.` : ''}{san}
              </button>
            );
          })}
        </div>
      </div>

      <div className="min-w-0 space-y-3">
        <div className="glass-card p-4">
          <div className="flex items-start justify-between gap-2">
            <div>
              <div className="text-[10px] font-black uppercase tracking-[0.16em] text-brilly">
                Guided Walkthrough
              </div>
              <h3 className="mt-0.5 text-base font-extrabold text-white">{line.title}</h3>
              <p className="mt-0.5 text-[11px] text-slate-400">{line.subtitle}</p>
            </div>
            {unlocked ? (
              <span className="inline-flex shrink-0 items-center gap-1 rounded-full border border-emerald-400/35 bg-emerald-500/15 px-2.5 py-1 text-[10px] font-bold text-emerald-200">
                <CheckCircle2 className="h-3 w-3" /> In FSRS
              </span>
            ) : (
              <span className="inline-flex shrink-0 items-center gap-1 rounded-full border border-amber-400/35 bg-amber-500/10 px-2.5 py-1 text-[10px] font-bold text-amber-200">
                Not unlocked
              </span>
            )}
          </div>

          <div className="mt-3 rounded-xl border border-slate-800/90 bg-void/60 p-3">
            {trapPlayback ? (
              <div className="space-y-1.5">
                <div className="flex items-center justify-between gap-2">
                  <span className="inline-flex items-center gap-1 text-[10px] font-black uppercase tracking-wider text-blunder">
                    <AlertTriangle className="h-3.5 w-3.5" /> Trap Spotlight · {trapPlayback.stepLabel}
                  </span>
                  <button
                    type="button"
                    onClick={() => { clearTimers(); setTrapPlayback(null); }}
                    className="rounded-lg border border-slate-700 bg-hull px-2 py-0.5 text-[10px] font-bold text-slate-300"
                  >
                    Back to mainline
                  </button>
                </div>
                <p className="text-xs leading-relaxed text-rose-100">{trapPlayback.trap.reason}</p>
                <div className="font-mono text-[10px] text-rose-300">
                  Refutation: {trapPlayback.trap.playedSan} → {trapPlayback.trap.punishmentLine.join(' ')}
                </div>
              </div>
            ) : activeAnnotation ? (
              <div className="space-y-1.5">
                <div className="flex items-center gap-2">
                  <span className="rounded bg-teal-400/15 px-1.5 py-0.5 font-mono text-[10px] font-black text-brilly">
                    {Math.floor(activeAnnotation.ply / 2) + 1}
                    {activeAnnotation.ply % 2 === 0 ? '.' : '…'}
                    {line.moves[activeAnnotation.ply]}
                  </span>
                  {activeAnnotation.isCritical && (
                    <span className="rounded-full border border-purple-400/40 bg-purple-500/15 px-2 py-0.5 text-[9px] font-black uppercase text-purple-200">
                      Critical Node
                    </span>
                  )}
                </div>
                {vibe === 'cosmic' && activeAnnotation.cosmicCue && (
                  <div className="text-[11px] font-bold italic text-purple-300">
                    “{activeAnnotation.cosmicCue}”
                  </div>
                )}
                <p className="text-xs leading-relaxed text-slate-200">{activeAnnotation.plan}</p>
              </div>
            ) : (
              <p className="text-xs leading-relaxed text-slate-400">
                {step === 0
                  ? `Tap Next to walk through ${line.title}. Key move notes and trap refutations highlight as you step.`
                  : `Standard development move (${line.moves[step - 1]}). Continue stepping to reach the next key idea.`}
              </p>
            )}
          </div>

          {/* Trap Spotlight Buttons */}
          {activeAnnotation?.wrongMoveTraps && activeAnnotation.wrongMoveTraps.length > 0 && (
            <div className="mt-3 rounded-xl border border-rose-500/30 bg-rose-500/[0.07] p-3">
              <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-wider text-blunder">
                <AlertTriangle className="h-3.5 w-3.5" /> Common Mistake Trap Spotlight
              </div>
              <div className="mt-2 space-y-1.5">
                {activeAnnotation.wrongMoveTraps.map((trap, idx) => (
                  <div key={idx} className="flex items-center justify-between gap-2 rounded-lg border border-rose-500/20 bg-void/60 px-2.5 py-2">
                    <div className="min-w-0 flex-1">
                      <div className="font-mono text-xs font-bold text-rose-200">
                        Why not {trap.playedSan}?
                      </div>
                      <div className="line-clamp-2 text-[10px] leading-snug text-slate-400">{trap.reason}</div>
                    </div>
                    <button
                      type="button"
                      onClick={() => previewTrap(trap, activeAnnotation.ply)}
                      className="inline-flex shrink-0 items-center gap-1 rounded-lg border border-rose-400/40 bg-rose-500/20 px-2.5 py-1.5 text-[10px] font-black text-rose-100 hover:bg-rose-500/30"
                    >
                      <Play className="h-3 w-3" /> Animate
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Unlock / Drill Footer */}
          <div className="mt-3 flex flex-wrap items-center gap-2 border-t border-slate-800/80 pt-3">
            {!unlocked ? (
              <button
                type="button"
                onClick={() => onUnlockLine(line)}
                className="inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-purple-500 px-3.5 py-2 text-xs font-extrabold text-slate-950 transition hover:brightness-110"
              >
                <LockOpen className="h-3.5 w-3.5" />
                {atEnd ? 'Walkthrough Complete — Unlock Drill' : 'Unlock Line in FSRS Queue'}
              </button>
            ) : (
              <button
                type="button"
                onClick={() => onStartDrillForLine(line)}
                className="inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-3.5 py-2 text-xs font-extrabold text-slate-950"
              >
                <Sparkles className="h-3.5 w-3.5" /> Drill This Line Now
              </button>
            )}
            <span className="text-[10px] text-slate-500">{line.frequencyNote}</span>
          </div>
        </div>
      </div>
    </div>
  );
};
