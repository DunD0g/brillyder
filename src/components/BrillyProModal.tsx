import React, { useState } from 'react';
import { Check, Crown, Sparkles, X } from 'lucide-react';

export type ProTierId = 'monthly' | 'annual' | 'lifetime';

interface Props {
  open: boolean;
  highlightedFeature?: string;
  isFounderPro?: boolean;
  onClose: () => void;
}

const TIERS: Array<{
  id: ProTierId;
  title: string;
  price: string;
  cadence: string;
  detail: string;
  badge?: string;
}> = [
  {
    id: 'annual',
    title: 'Annual',
    price: '£24.99',
    cadence: '/yr',
    detail: '£2.08/mo · 7-day free trial included',
    badge: 'Best Value · 7-Day Free Trial',
  },
  {
    id: 'monthly',
    title: 'Monthly',
    price: '£3.99',
    cadence: '/mo',
    detail: 'Flexible monthly access · cancel anytime',
  },
  {
    id: 'lifetime',
    title: 'Lifetime',
    price: '£39.99',
    cadence: 'one-time',
    detail: 'Pay once, keep BrillyDer Pro forever',
    badge: 'One-Time',
  },
];

/**
 * Clean, non-intrusive BrillyDer Pro upgrade modal (Founder Pro stays unlocked by default).
 */
export const BrillyProModal: React.FC<Props> = ({
  open,
  highlightedFeature,
  isFounderPro = true,
  onClose,
}) => {
  const [selected, setSelected] = useState<ProTierId>('annual');

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-md"
      role="dialog"
      aria-modal="true"
      aria-label="BrillyDer Pro"
    >
      <div className="relative w-full max-w-md rounded-3xl border border-teal-400/25 bg-[#0E121A]/95 p-5 text-slate-100 shadow-2xl">
        <button
          type="button"
          onClick={onClose}
          aria-label="Close Pro modal"
          className="absolute right-4 top-4 flex h-8 w-8 items-center justify-center rounded-full bg-white/10 text-slate-300 transition active:scale-[0.98]"
        >
          <X className="h-4 w-4" />
        </button>

        <div className="flex items-center gap-2">
          <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-teal-400/25 to-purple-500/25 text-teal-300">
            <Crown className="h-5 w-5" />
          </span>
          <div>
            <h2 className="text-lg font-black tracking-tight">
              <span className="text-brilly">Brilly</span>
              <span className="mx-0.5 text-slate-400">/</span>
              <span className="text-blunder">Der</span>{' '}
              <span className="rounded-full bg-gradient-to-r from-teal-400 to-purple-400 px-2 py-0.5 text-[10px] font-black uppercase text-slate-950">
                Pro
              </span>
            </h2>
            <p className="text-xs text-slate-400">
              {highlightedFeature
                ? `Unlock ${highlightedFeature} & full offline coaching`
                : 'Unlimited sync, 25m Orbit Coach & Endgame Labs'}
            </p>
          </div>
        </div>

        {isFounderPro && (
          <div className="mt-3 flex items-center gap-2 rounded-xl border border-teal-400/35 bg-teal-400/12 px-3 py-2 text-xs font-bold text-teal-200">
            <Sparkles className="h-4 w-4 shrink-0 text-teal-300" />
            Founder Pro Active — all Pro features are unlocked on your build.
          </div>
        )}

        <ul className="mt-4 space-y-2 text-xs text-slate-300">
          {[
            'Unlimited Lichess & Chess.com game sync + batch Stockfish scans',
            '25-Minute Orbit Coach & Frozen Woodpecker Cycles',
            'Endgame Labs, 7-piece Syzygy Tablebase & Board Vision drills',
          ].map((item) => (
            <li key={item} className="flex items-start gap-2">
              <Check className="mt-0.5 h-3.5 w-3.5 shrink-0 text-brilly" />
              <span>{item}</span>
            </li>
          ))}
        </ul>

        <div className="mt-4 space-y-2.5">
          {TIERS.map((t) => {
            const active = selected === t.id;
            return (
              <button
                key={t.id}
                type="button"
                onClick={() => setSelected(t.id)}
                className={`w-full rounded-2xl border p-3 text-left transition active:scale-[0.98] ${
                  active
                    ? 'border-teal-400 bg-teal-400/12 shadow-lg shadow-teal-500/10'
                    : 'border-white/10 bg-white/[0.03] hover:border-white/20'
                }`}
              >
                {t.badge && (
                  <span className="mb-1 inline-block rounded-full bg-teal-400 px-2 py-0.5 text-[9px] font-black uppercase tracking-wide text-slate-950">
                    {t.badge}
                  </span>
                )}
                <div className="flex items-baseline justify-between gap-2">
                  <div>
                    <div className="text-sm font-extrabold text-white">{t.title}</div>
                    <div className="text-[11px] text-slate-400">{t.detail}</div>
                  </div>
                  <div className="shrink-0 font-mono text-base font-black text-teal-300">
                    {t.price}
                    <span className="ml-0.5 text-[10px] font-semibold text-slate-400">{t.cadence}</span>
                  </div>
                </div>
              </button>
            );
          })}
        </div>

        <button
          type="button"
          onClick={onClose}
          className="mt-4 w-full rounded-2xl bg-gradient-to-r from-teal-400 to-cyan-400 py-3 text-sm font-black text-slate-950 transition active:scale-[0.98]"
        >
          {isFounderPro ? 'Continue with Founder Pro' : 'Start 7-Day Free Trial'}
        </button>
      </div>
    </div>
  );
};
