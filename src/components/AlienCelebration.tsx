import React, { useEffect, useMemo, useState } from 'react';
import { X } from 'lucide-react';

export type CelebrationKind = 'brilliant' | 'blunder';

export const BRILLIANT_LINES = [
  'Beam me up, Magnus — that sacrifice isn’t from this planet!',
  'Area 51 called. They want their tactics back.',
  'Humans aren’t supposed to calculate that!',
  'Certified Galaxy-Brain Sacrifice 🛸',
  'Stockfish just filed a UFO sighting report.',
  'The mothership requests your engine eval immediately.',
  'That move broke the Prime Directive: No brilliant moves.',
  'Somewhere, a grandmaster just spilled their coffee.',
  'Gravity? Never heard of her. — this piece',
  'NASA renamed a constellation after that move.',
  'The aliens graded it “finally, a worthy opponent.”',
  'This is the move that makes pigeons nervous.',
];

export const BLUNDER_LINES = [
  'Houston, we dropped a piece.',
  'The UFO is facepalming. Slowly.',
  'Alien scan complete: “yep, that one hurts.”',
  'Beam malfunction — material did not survive transport.',
  'Mission Control: “We recommend not doing that.”',
  'The mothership has muted the game.',
];

export function pickCelebrationLine(kind: CelebrationKind, seed = Date.now()): string {
  const pool = kind === 'brilliant' ? BRILLIANT_LINES : BLUNDER_LINES;
  return pool[Math.abs(seed) % pool.length];
}

interface Props {
  kind: CelebrationKind;
  trigger: number;
  message?: string;
  autoDismissMs?: number;
  onDismiss: () => void;
}

export const AlienCelebration: React.FC<Props> = ({ kind, trigger, message, autoDismissMs, onDismiss }) => {
  const [entered, setEntered] = useState(true);
  const fallback = useMemo(() => pickCelebrationLine(kind, trigger), [kind, trigger]);
  const text = message ?? fallback;
  const brilliant = kind === 'brilliant';

  useEffect(() => {
    setEntered(true);
    const ms = autoDismissMs ?? (brilliant ? 2600 : 1900);
    const timer = window.setTimeout(() => setEntered(false), ms);
    return () => window.clearTimeout(timer);
  }, [trigger, kind, autoDismissMs]);

  if (!entered) return null;

  return (
    <div className="pointer-events-none fixed z-[70] left-3 right-3 bottom-[5.75rem] lg:left-auto lg:right-6 lg:bottom-6 lg:w-[23rem]">
      <button
        type="button"
        onClick={() => { setEntered(false); onDismiss(); }}
        className={`pointer-events-auto alien-enter relative w-full text-left rounded-2xl border p-3 pr-9 flex items-center gap-3 overflow-hidden backdrop-blur-xl shadow-2xl ${
          brilliant
            ? 'border-cyan-400/45 bg-[#071820]/[0.92] shadow-cyan-500/25'
            : 'border-rose-400/40 bg-[#1a0a10]/[0.92] shadow-rose-500/20'
        }`}
        aria-live="polite"
        aria-label={`${brilliant ? 'Brilliant move' : 'Blunder'} celebration. Tap to dismiss.`}
      >
        <span className={`absolute inset-0 opacity-40 ${brilliant ? 'bg-[radial-gradient(circle_at_18%_20%,rgba(34,211,238,0.35),transparent_55%)]' : 'bg-[radial-gradient(circle_at_18%_20%,rgba(244,63,94,0.28),transparent_55%)]'}`} />
        <div className="relative shrink-0 w-[76px] h-[68px]">
          <UfoAlien kind={kind} />
        </div>
        <div className="relative min-w-0">
          <div className={`text-[10px] font-black uppercase tracking-[0.16em] ${brilliant ? 'text-cyan-300' : 'text-rose-300'}`}>
            {brilliant ? 'Brilliant move detected' : 'Blunder detected'}
          </div>
          <p className="mt-0.5 text-[13px] font-bold leading-snug text-slate-50">{text}</p>
          <div className="mt-1 text-[10px] text-slate-400">Tap to dismiss · never blocks the board</div>
        </div>
        <X className="absolute right-2.5 top-2.5 w-3.5 h-3.5 text-slate-400" />
      </button>
    </div>
  );
};

const UfoAlien: React.FC<{ kind: CelebrationKind }> = ({ kind }) => {
  const brilliant = kind === 'brilliant';
  const bodyFrom = brilliant ? '#22d3ee' : '#fb7185';
  const bodyTo = brilliant ? '#0ea5e9' : '#be123c';
  const alienFrom = brilliant ? '#a3e635' : '#fca5a5';
  const alienTo = brilliant ? '#22c55e' : '#f43f5e';
  return (
    <svg viewBox="0 0 120 108" className="w-full h-full overflow-visible" aria-hidden="true">
      <defs>
        <linearGradient id={`ufo-body-${kind}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={bodyFrom} />
          <stop offset="100%" stopColor={bodyTo} />
        </linearGradient>
        <linearGradient id={`alien-head-${kind}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={alienFrom} />
          <stop offset="100%" stopColor={alienTo} />
        </linearGradient>
        <linearGradient id={`ufo-beam-${kind}`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={bodyFrom} stopOpacity="0.55" />
          <stop offset="100%" stopColor={bodyFrom} stopOpacity="0" />
        </linearGradient>
      </defs>

      <path className="alien-beam" d="M46 58 L30 104 L92 104 L76 58 Z" fill={`url(#ufo-beam-${kind})`} />

      <g className={brilliant ? 'alien-float' : 'alien-wobble'}>
        <ellipse cx="60" cy="52" rx="40" ry="10" fill={`url(#ufo-body-${kind})`} opacity="0.95" />
        <ellipse cx="60" cy="49" rx="30" ry="7" fill="#0b1220" opacity="0.55" />
        <path d="M38 50 Q40 27 60 25 Q80 27 82 50 Z" fill={`url(#ufo-body-${kind})`} opacity="0.35" stroke={bodyFrom} strokeWidth="1.5" />
        {[30, 42, 54, 66, 78, 90].map((cx) => (
          <circle key={cx} cx={cx} cy="53" r="1.9" fill={brilliant ? '#facc15' : '#fda4af'} className="alien-sparkle" />
        ))}

        <g>
          <line x1="51" y1="31" x2="47" y2="23" stroke={alienTo} strokeWidth="2" strokeLinecap="round" />
          <line x1="69" y1="31" x2="73" y2="23" stroke={alienTo} strokeWidth="2" strokeLinecap="round" />
          <circle cx="46.5" cy="22" r="2.4" fill={brilliant ? '#fde047' : '#fda4af'} className="alien-sparkle" />
          <circle cx="73.5" cy="22" r="2.4" fill={brilliant ? '#fde047' : '#fda4af'} className="alien-sparkle" />
          <ellipse cx="60" cy="37" rx="15" ry="12" fill={`url(#alien-head-${kind})`} stroke="#052e16" strokeOpacity="0.3" />
          {brilliant ? (
            <>
              <ellipse cx="54.5" cy="36.5" rx="3.6" ry="4.8" fill="#071018" />
              <ellipse cx="65.5" cy="36.5" rx="3.6" ry="4.8" fill="#071018" />
              <circle cx="53.4" cy="34.8" r="1.1" fill="#e0f2fe" />
              <circle cx="64.4" cy="34.8" r="1.1" fill="#e0f2fe" />
              <path d="M54 43 Q60 47 66 43" fill="none" stroke="#052e16" strokeWidth="1.8" strokeLinecap="round" />
            </>
          ) : (
            <>
              <path d="M51 35 L58 40 M58 35 L51 40" stroke="#071018" strokeWidth="2" strokeLinecap="round" />
              <path d="M62 35 L69 40 M69 35 L62 40" stroke="#071018" strokeWidth="2" strokeLinecap="round" />
              <path d="M55 45 Q60 41 65 45" fill="none" stroke="#071018" strokeWidth="1.8" strokeLinecap="round" />
              <path d="M75 38 q4 3 2 7 q-4 -1 -2 -7" fill="#93c5fd" opacity="0.85" />
            </>
          )}
        </g>
      </g>

      <g fill={brilliant ? '#67e8f9' : '#fda4af'}>
        <path d="M14 30 l1.8 4.2 L20 36 l-4.2 1.8 L14 42 l-1.8 -4.2 L8 36 l4.2 -1.8 Z" className="alien-sparkle" />
        <path d="M104 20 l1.4 3.3 L109 25 l-3.6 1.4 L104 30 l-1.4 -3.6 L99 25 l3.6 -1.7 Z" className="alien-sparkle" style={{ animationDelay: '0.35s' }} />
        <circle cx="98" cy="68" r="1.7" className="alien-sparkle" style={{ animationDelay: '0.55s' }} />
        <circle cx="21" cy="63" r="1.4" className="alien-sparkle" style={{ animationDelay: '0.7s' }} />
      </g>
    </svg>
  );
};
