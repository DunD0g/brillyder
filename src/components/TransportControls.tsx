import React from 'react';
import { ChevronLeft, ChevronRight, FlipVertical2, Gauge, Pause, Play, RotateCcw, SkipBack, SkipForward } from 'lucide-react';

interface Props {
  current: number;
  total: number;
  playing: boolean;
  speed: 1 | 2;
  canRetry: boolean;
  onFirst: () => void;
  onPrev: () => void;
  onNext: () => void;
  onLast: () => void;
  onFlip: () => void;
  onTogglePlay: () => void;
  onToggleSpeed: () => void;
  onRetry: () => void;
  variant: 'desktop' | 'mobile';
}

export const TransportControls: React.FC<Props> = ({
  current, total, playing, speed, canRetry,
  onFirst, onPrev, onNext, onLast, onFlip, onTogglePlay, onToggleSpeed, onRetry, variant,
}) => {
  if (variant === 'mobile') {
    return (
      <div className="lg:hidden fixed bottom-0 left-0 right-0 z-40 border-t border-white/10 bg-[#070b13]/[0.94] backdrop-blur-xl px-2.5 pt-2 pb-[max(0.6rem,env(safe-area-inset-bottom))]">
        <div className="mx-auto grid max-w-lg grid-cols-8 gap-1">
          <TransportButton onClick={onFirst} label="First move"><SkipBack className="w-4 h-4" /></TransportButton>
          <TransportButton onClick={onPrev} label="Previous move"><ChevronLeft className="w-5 h-5" /></TransportButton>
          <button
            type="button"
            onClick={onTogglePlay}
            className="col-span-2 flex items-center justify-center gap-1 rounded-xl border border-cyan-400/40 bg-gradient-to-r from-cyan-500/25 to-emerald-500/20 py-3 text-cyan-100 active:scale-95"
            aria-label={playing ? 'Pause auto-play' : 'Start auto-play'}
          >
            {playing ? <Pause className="w-5 h-5" /> : <Play className="w-5 h-5" />}
            <span className="text-[10px] font-black">{playing ? 'PAUSE' : 'AUTO'}</span>
          </button>
          <TransportButton onClick={onNext} label="Next move"><ChevronRight className="w-5 h-5" /></TransportButton>
          <TransportButton onClick={onLast} label="Last move"><SkipForward className="w-4 h-4" /></TransportButton>
          <TransportButton onClick={onToggleSpeed} label="Auto-play speed"><span className="text-[11px] font-black">{speed}x</span></TransportButton>
          <TransportButton onClick={onFlip} label="Flip board"><FlipVertical2 className="w-4 h-4" /></TransportButton>
        </div>
        <div className="mx-auto mt-1 flex max-w-lg items-center justify-between gap-2 px-1 text-[10px] font-mono text-slate-500">
          <span>{current}/{total} plies</span>
          {canRetry ? (
            <button
              type="button"
              onClick={onRetry}
              className="inline-flex items-center gap-1 rounded-lg border border-amber-500/40 bg-amber-500/15 px-2 py-0.5 font-sans text-[10px] font-extrabold text-amber-200 active:scale-95"
            >
              <RotateCcw className="h-3 w-3" /> Retry mistake
            </button>
          ) : (
            <span className="font-sans text-[9px] text-slate-500">Swipe board to step</span>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="glass-card p-2.5">
      <div className="flex flex-wrap items-center gap-1.5">
        <TransportButton onClick={onFirst} label="First move"><SkipBack className="w-4 h-4" /></TransportButton>
        <TransportButton onClick={onPrev} label="Previous move"><ChevronLeft className="w-5 h-5" /></TransportButton>
        <button
          type="button"
          onClick={onTogglePlay}
          className="inline-flex items-center gap-1.5 rounded-xl border border-cyan-400/40 bg-cyan-500/15 px-3 py-2 text-xs font-bold text-cyan-100 hover:bg-cyan-500/25"
          aria-label={playing ? 'Pause auto-play' : 'Start auto-play'}
        >
          {playing ? <Pause className="w-4 h-4" /> : <Play className="w-4 h-4" />}
          {playing ? 'Pause' : 'Auto-play'}
        </button>
        <TransportButton onClick={onNext} label="Next move"><ChevronRight className="w-5 h-5" /></TransportButton>
        <TransportButton onClick={onLast} label="Last move"><SkipForward className="w-4 h-4" /></TransportButton>
        <TransportButton onClick={onFlip} label="Flip board"><FlipVertical2 className="w-4 h-4" /></TransportButton>

        <button
          type="button"
          onClick={onToggleSpeed}
          className="inline-flex items-center gap-1 rounded-xl border border-slate-700 bg-slate-800/70 px-2.5 py-2 text-[11px] font-bold text-slate-300 hover:border-slate-500"
          aria-label="Toggle auto-play speed"
        >
          <Gauge className="w-3.5 h-3.5 text-cyan-400" /> {speed}x
        </button>

        {canRetry && (
          <button
            type="button"
            onClick={onRetry}
            className="inline-flex items-center gap-1 rounded-xl border border-amber-500/35 bg-amber-500/15 px-2.5 py-2 text-[11px] font-bold text-amber-200 hover:bg-amber-500/25"
          >
            <RotateCcw className="w-3.5 h-3.5" /> Retry
          </button>
        )}

        <span className="ml-auto hidden xl:flex items-center gap-1 text-[10px] text-slate-500">
          <kbd className="keycap">←</kbd><kbd className="keycap">→</kbd>
          <kbd className="keycap">Home</kbd><kbd className="keycap">End</kbd>
          <kbd className="keycap">Space</kbd><kbd className="keycap">f</kbd><kbd className="keycap">r</kbd>
        </span>
      </div>
      <div className="mt-1.5 flex items-center gap-2 px-1">
        <div className="h-1 flex-1 overflow-hidden rounded-full bg-slate-800">
          <div className="h-full rounded-full bg-gradient-to-r from-cyan-400 to-emerald-400 transition-all duration-200" style={{ width: `${total > 0 ? (current / total) * 100 : 0}%` }} />
        </div>
        <span className="shrink-0 font-mono text-[10px] text-slate-500">{current}/{total}</span>
      </div>
    </div>
  );
};

const TransportButton: React.FC<{ onClick: () => void; label: string; children: React.ReactNode }> = ({ onClick, label, children }) => (
  <button
    type="button"
    onClick={onClick}
    aria-label={label}
    title={label}
    className="flex items-center justify-center rounded-xl border border-slate-700/80 bg-slate-900/80 px-2.5 py-2.5 text-slate-300 transition hover:border-slate-500 hover:text-white active:scale-95"
  >
    {children}
  </button>
);
