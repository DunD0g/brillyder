import React from 'react';
import { Bot, Lightbulb, RotateCcw, Undo2 } from 'lucide-react';
import type { BotSession, RetrySession } from '../types/chess';

interface BotProps {
  session: BotSession;
  onExit: () => void;
  onEloChange: (elo: number) => void;
  onUndo: () => void;
}

export const BotPanel: React.FC<BotProps> = ({ session, onExit, onEloChange, onUndo }) => (
  <div className="glass-card border-cyan-500/35 p-3.5 space-y-2">
    <div className="flex items-center justify-between gap-2">
      <span className="inline-flex items-center gap-1.5 text-xs font-bold text-cyan-200">
        <Bot className="w-4 h-4" /> Play vs. Stockfish ({session.elo})
      </span>
      <button type="button" onClick={onExit} className="rounded-lg bg-slate-800 px-2.5 py-1 text-[11px] text-slate-300">Exit bot</button>
    </div>
    <p className="text-xs text-slate-200">{session.statusText}</p>
    <div className="flex items-center gap-1.5 flex-wrap">
      {[1200, 1400, 1600, 1800].map((elo) => (
        <button
          key={elo}
          type="button"
          onClick={() => onEloChange(elo)}
          className={`rounded-lg border px-2.5 py-1 text-[11px] font-bold ${session.elo === elo ? 'border-cyan-500/40 bg-cyan-500/20 text-cyan-200' : 'border-slate-700 bg-slate-800 text-slate-400'}`}
        >
          {elo}
        </button>
      ))}
      {session.historyFens.length >= 2 && !session.thinking && (
        <button type="button" onClick={onUndo} className="ml-auto inline-flex items-center gap-1 rounded-lg border border-amber-500/30 bg-amber-500/10 px-2.5 py-1 text-[11px] font-semibold text-amber-300">
          <Undo2 className="w-3 h-3" /> Undo
        </button>
      )}
    </div>
    <p className="text-[10px] text-slate-500">Drag a piece to move. Escape exits bot mode. BotElo 1200–1800 uses Stockfish UCI_LimitStrength.</p>
  </div>
);

interface RetryProps {
  session: RetrySession;
  onExit: () => void;
  onReveal: () => void;
  onReset: () => void;
  onNextMistake: () => void;
}

export const RetryPanel: React.FC<RetryProps> = ({ session, onExit, onReveal, onReset, onNextMistake }) => (
  <div className="glass-card border-amber-500/40 p-3.5 space-y-2">
    <div className="flex items-center justify-between gap-2">
      <span className="inline-flex items-center gap-1.5 text-xs font-bold text-amber-200">
        <RotateCcw className="w-3.5 h-3.5" /> Retry mistake
      </span>
      <button type="button" onClick={onExit} className="rounded-lg bg-slate-800 px-2.5 py-1 text-[11px] text-slate-300">Done</button>
    </div>
    <p className={`text-xs font-medium leading-relaxed ${session.status === 'solved' ? 'text-emerald-300' : session.status === 'try_again' ? 'text-orange-300' : 'text-slate-200'}`}>
      {session.feedback}
    </p>
    <div className="flex flex-wrap gap-1.5">
      <button type="button" onClick={onReveal} className="inline-flex items-center gap-1 rounded-lg border border-slate-700 bg-slate-800 px-2.5 py-1.5 text-[11px] font-semibold text-slate-200">
        <Lightbulb className="w-3.5 h-3.5 text-amber-400" /> Show best
      </button>
      <button type="button" onClick={onReset} className="rounded-lg border border-slate-700 bg-slate-800 px-2.5 py-1.5 text-[11px] font-semibold text-slate-300">
        Reset position
      </button>
      <button type="button" onClick={onNextMistake} className="rounded-lg border border-cyan-500/30 bg-cyan-500/15 px-2.5 py-1.5 text-[11px] font-semibold text-cyan-200">
        Next mistake
      </button>
      <span className="ml-auto self-center text-[10px] text-slate-500">Press r for next retry</span>
    </div>
  </div>
);
