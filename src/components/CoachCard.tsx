import React from 'react';
import { AlertTriangle, Bot, Eye, FlaskConical, Lightbulb, Play, RotateCcw, Sparkles, Zap } from 'lucide-react';
import { CLASSIFICATION_META, type AnalyzedGame, type AnalyzedPly, type LichessGameRecord } from '../types/chess';
import { ClassificationBadge } from './ClassificationBadge';

interface Props {
  game: LichessGameRecord;
  analyzed: AnalyzedGame | null;
  currentPly: AnalyzedPly | null;
  analyzing: boolean;
  isMistake: boolean;
  showThreat: boolean;
  botElo: number;
  onAnalyze: () => void;
  onToggleThreat: () => void;
  onStartRetry: () => void;
  onStartBot: () => void;
  onStartSandbox: () => void;
  onNextMistake: () => void;
}

export const CoachCard: React.FC<Props> = ({
  game,
  analyzed,
  currentPly,
  analyzing,
  isMistake,
  showThreat,
  botElo,
  onAnalyze,
  onToggleThreat,
  onStartRetry,
  onStartBot,
  onStartSandbox,
  onNextMistake,
}) => {
  if (!analyzed) {
    return (
      <div className="glass-card glass-card-strong overflow-hidden">
        <div className="h-0.5 w-full bg-gradient-to-r from-cyan-400 via-emerald-400 to-transparent" />
        <div className="p-4">
          <div className="flex items-center gap-2 text-xs font-black uppercase tracking-[0.16em] text-cyan-300">
            <Sparkles className="w-4 h-4" /> Coach cockpit
          </div>
          <h2 className="mt-2 text-base font-extrabold text-white">Ready for review{analyzing ? '…' : '.'}</h2>
          <p className="mt-1 text-xs leading-relaxed text-slate-300">
            {analyzing
              ? 'Stockfish WASM is walking through every position on this device. Sit tight — the board stays interactive.'
              : 'Run the on-device engine to detect brilliancies, blunders, best-move alternatives and tactical themes.'}
          </p>
          <div className="mt-3 flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={onAnalyze}
              disabled={analyzing}
              className="inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-cyan-400 to-emerald-400 px-3.5 py-2 text-xs font-extrabold text-slate-950 disabled:opacity-60"
            >
              <Play className="w-3.5 h-3.5" /> Analyze with Stockfish
            </button>
            <span className="text-[11px] text-slate-500">{game.openingEco ? `${game.openingEco} · ` : ''}{game.openingName}</span>
          </div>
        </div>
      </div>
    );
  }

  if (!currentPly) {
    return (
      <div className="glass-card p-4">
        <div className="flex items-center gap-2 text-xs font-black uppercase tracking-[0.16em] text-slate-300">
          <Zap className="w-4 h-4 text-amber-400" /> Opening position
        </div>
        <h2 className="mt-2 text-sm font-extrabold text-white">{analyzed.openingLineDetected || game.openingName}</h2>
        <p className="mt-1 text-xs leading-relaxed text-slate-300">
          {game.white.name} ({game.white.rating ?? '?'}) vs {game.black.name} ({game.black.rating ?? '?'}) · {game.timeControlLabel} {game.rated ? 'rated' : 'casual'}.
          Step forward to see Stockfish&apos;s verdict on every move.
        </p>
        <div className="mt-3 flex flex-wrap gap-2">
          <button type="button" onClick={onStartSandbox} className="inline-flex items-center gap-1 rounded-xl border border-fuchsia-400/35 bg-fuchsia-500/15 px-2.5 py-1.5 text-[11px] font-bold text-fuchsia-200">
            <FlaskConical className="w-3.5 h-3.5" /> Explore from here
          </button>
          <button type="button" onClick={onStartBot} className="inline-flex items-center gap-1 rounded-xl border border-slate-700 bg-slate-800/80 px-2.5 py-1.5 text-[11px] font-semibold text-slate-200">
            <Bot className="w-3.5 h-3.5 text-cyan-400" /> Play bot ({botElo})
          </button>
        </div>
      </div>
    );
  }

  const meta = CLASSIFICATION_META[currentPly.classification];
  const brilliant = currentPly.classification === 'brilliant';

  return (
    <div className={`glass-card glass-card-strong overflow-hidden ${brilliant ? 'accent-glow border-cyan-400/40' : ''}`}>
      <div className="h-0.5 w-full" style={{ background: `linear-gradient(90deg, ${meta.badgeBg}, rgba(15,23,42,0))` }} />
      <div className="p-3.5">
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2 min-w-0">
            <ClassificationBadge classification={currentPly.classification} showLabel />
            <span className="font-extrabold text-sm text-white truncate">
              {currentPly.moveNumber}{currentPly.color === 'w' ? '.' : '…'}{currentPly.san}
            </span>
          </div>
          <span className="shrink-0 rounded-lg bg-slate-950/70 border border-slate-800 px-2 py-1 font-mono text-[11px] font-bold text-slate-300">
            {currentPly.evalAfter.display}
          </span>
        </div>

        <div className="mt-2 flex flex-wrap items-center gap-1.5">
          <span className="text-[9px] font-black uppercase tracking-[0.16em] px-1.5 py-0.5 rounded bg-slate-800 text-slate-300">
            {currentPly.coaching.tacticalTag}
          </span>
          <span className="text-[10px] text-slate-500 capitalize">{currentPly.phase}</span>
          {currentPly.isClutchSave && (
            <span className="rounded-full border border-teal-400/45 bg-teal-400/15 px-2 py-0.5 text-[9px] font-black uppercase tracking-wider text-teal-200">
              Clutch Save
            </span>
          )}
          {currentPly.isCriticalMoment && !currentPly.isClutchSave && (
            <span className="rounded-full border border-purple-400/40 bg-purple-500/15 px-2 py-0.5 text-[9px] font-black uppercase tracking-wider text-purple-200">
              Critical{currentPly.secondBestGapPawns ? ` +${currentPly.secondBestGapPawns.toFixed(1)}` : ''}
            </span>
          )}
          {currentPly.clockTag === 'impulse' && (
            <span className="rounded-full border border-amber-400/45 bg-amber-500/15 px-2 py-0.5 text-[9px] font-black uppercase tracking-wider text-amber-200">
              Impulse ({currentPly.timeSpentSeconds ?? '<5'}s)
            </span>
          )}
          {currentPly.clockTag === 'time-trouble' && (
            <span className="rounded-full border border-rose-400/45 bg-rose-500/15 px-2 py-0.5 text-[9px] font-black uppercase tracking-wider text-rose-200">
              Time Trouble ({currentPly.clockText ?? '<60s'})
            </span>
          )}
          {currentPly.deepened && (
            <span className="ml-auto rounded bg-void/70 px-1.5 py-0.5 font-mono text-[8px] font-bold text-brilly">
              D18
            </span>
          )}
        </div>

        <h3 className="mt-2 text-sm font-extrabold leading-snug text-slate-50">{currentPly.coaching.headline}</h3>
        <p className="mt-1 text-xs leading-relaxed text-slate-300">{currentPly.coaching.detail}</p>

        {currentPly.topLines && currentPly.topLines.length > 1 ? (
          <div className="mt-2 space-y-1 rounded-xl border border-emerald-500/15 bg-slate-950/70 px-2.5 py-2">
            <div className="text-[9px] font-black uppercase tracking-[0.14em] text-emerald-400/80">
              Stockfish MultiPV Top {currentPly.topLines.length}
            </div>
            {currentPly.topLines.map((line, idx) => (
              <div key={idx} className="flex items-center gap-2 font-mono text-[10px]">
                <span className={`shrink-0 rounded px-1 py-0.5 font-bold ${idx === 0 ? 'bg-teal-400/15 text-teal-200' : 'bg-slate-800 text-slate-400'}`}>
                  {line.evalDisplay}
                </span>
                <span className={`truncate ${idx === 0 ? 'text-emerald-200 font-bold' : 'text-slate-400'}`}>
                  {line.pvSan.join(' ')}
                </span>
              </div>
            ))}
          </div>
        ) : currentPly.bestPvSan.length > 0 ? (
          <div className="mt-2 rounded-xl bg-slate-950/70 border border-emerald-500/15 px-2 py-1.5">
            <div className="text-[9px] font-black uppercase tracking-[0.14em] text-emerald-400/80">Engine line</div>
            <div className="mt-0.5 truncate font-mono text-[11px] text-emerald-200">{currentPly.bestPvSan.join(' ')}</div>
          </div>
        ) : null}

        {currentPly.threatMoveSan && (
          <div className="mt-2 flex items-center gap-1.5 text-[11px] text-red-300">
            <AlertTriangle className="w-3.5 h-3.5 shrink-0" /> Opponent threat: <span className="font-mono font-bold">{currentPly.threatMoveSan}</span>
          </div>
        )}

        <div className="mt-3 flex flex-wrap items-center gap-1.5">
          {isMistake && (
            <button type="button" onClick={onStartRetry} className="inline-flex items-center gap-1.5 rounded-xl border border-amber-500/40 bg-amber-500/20 px-2.5 py-1.5 text-[11px] font-bold text-amber-200">
              <RotateCcw className="w-3.5 h-3.5" /> Retry move
            </button>
          )}
          <button type="button" onClick={onStartSandbox} className="inline-flex items-center gap-1.5 rounded-xl border border-fuchsia-400/35 bg-fuchsia-500/15 px-2.5 py-1.5 text-[11px] font-bold text-fuchsia-200">
            <FlaskConical className="w-3.5 h-3.5" /> What if?
          </button>
          <button type="button" onClick={onStartBot} className="inline-flex items-center gap-1.5 rounded-xl border border-slate-700 bg-slate-800/80 px-2.5 py-1.5 text-[11px] font-semibold text-slate-200">
            <Bot className="w-3.5 h-3.5 text-cyan-400" /> Play bot ({botElo})
          </button>
          <button
            type="button"
            onClick={onToggleThreat}
            className={`inline-flex items-center gap-1.5 rounded-xl border px-2.5 py-1.5 text-[11px] font-semibold ${showThreat ? 'border-red-500/40 bg-red-500/20 text-red-200' : 'border-slate-700 bg-slate-800/70 text-slate-400'}`}
          >
            <Eye className="w-3.5 h-3.5" /> Threat
          </button>
          <button type="button" onClick={onNextMistake} className="ml-auto inline-flex items-center gap-1 rounded-xl border border-slate-700 bg-slate-800/70 px-2.5 py-1.5 text-[11px] font-semibold text-orange-300">
            <Lightbulb className="w-3.5 h-3.5" /> Next mistake
          </button>
        </div>
      </div>
    </div>
  );
};
