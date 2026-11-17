import React, { useEffect, useRef, useState } from 'react';
import { Check, Palette, Sparkles, X } from 'lucide-react';
import { BOARD_THEME_LIST } from '../chess/boardThemes';
import type { BoardThemeId } from '../types/chess';

interface Props {
  theme: BoardThemeId;
  onThemeChange: (theme: BoardThemeId) => void;
  celebrationsEnabled: boolean;
  onToggleCelebrations: () => void;
}

export const BoardThemePicker: React.FC<Props> = ({ theme, onThemeChange, celebrationsEnabled, onToggleCelebrations }) => {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement | null>(null);
  const active = BOARD_THEME_LIST.find((t) => t.id === theme) ?? BOARD_THEME_LIST[0];

  useEffect(() => {
    if (!open) return;
    const onPointer = (e: PointerEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('pointerdown', onPointer);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('pointerdown', onPointer);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="inline-flex items-center gap-1.5 rounded-xl border border-slate-800 bg-slate-900/80 px-2.5 py-2 text-[11px] font-bold text-slate-300 hover:border-slate-600"
        aria-label="Board theme and celebration settings"
        aria-expanded={open}
      >
        <Palette className="w-4 h-4 text-cyan-400" />
        <span className="hidden sm:inline">{active.shortName}</span>
      </button>

      {open && (
        <div className="absolute right-0 top-full z-[80] mt-2 w-[19rem] anim-pop glass-card glass-card-strong p-3 shadow-2xl">
          <div className="flex items-center justify-between">
            <span className="text-[10px] font-black uppercase tracking-[0.16em] text-slate-300">Board &amp; pieces</span>
            <button type="button" onClick={() => setOpen(false)} className="text-slate-500 hover:text-slate-300" aria-label="Close settings"><X className="w-3.5 h-3.5" /></button>
          </div>

          <div className="mt-2 grid grid-cols-2 gap-1.5">
            {BOARD_THEME_LIST.map((t) => (
              <button
                key={t.id}
                type="button"
                onClick={() => onThemeChange(t.id)}
                className={`rounded-xl border p-2 text-left transition ${theme === t.id ? 'border-cyan-400/60 bg-cyan-500/10' : 'border-slate-800 bg-slate-950/50 hover:border-slate-600'}`}
              >
                <span className="grid grid-cols-4 overflow-hidden rounded-md border border-black/30" style={{ aspectRatio: '1 / 0.55' }}>
                  {Array.from({ length: 16 }).map((_, i) => {
                    const x = i % 4;
                    const y = Math.floor(i / 4);
                    return <span key={i} style={{ backgroundColor: (x + y) % 2 === 0 ? t.lightSquare : t.darkSquare }} />;
                  })}
                </span>
                <span className="mt-1.5 flex items-center gap-1 text-[10px] font-bold text-slate-200">
                  {t.shortName}
                  {theme === t.id && <Check className="w-3 h-3 text-cyan-300" />}
                </span>
              </button>
            ))}
          </div>

          <div className="mt-3 border-t border-slate-800/80 pt-2.5">
            <button type="button" onClick={onToggleCelebrations} className="flex w-full items-center justify-between gap-2 text-left">
              <span className="flex items-center gap-1.5 text-[11px] font-bold text-slate-200">
                <Sparkles className="w-3.5 h-3.5 text-cyan-300" /> Alien celebrations
              </span>
              <span className={`relative h-5 w-9 rounded-full transition ${celebrationsEnabled ? 'bg-cyan-500/80' : 'bg-slate-700'}`}>
                <span className={`absolute top-0.5 h-4 w-4 rounded-full bg-white shadow transition-all ${celebrationsEnabled ? 'left-[1.15rem]' : 'left-0.5'}`} />
              </span>
            </button>
            <p className="mt-1 text-[10px] leading-snug text-slate-500">UFO fly-bys on !! moves and cheeky facepalms on ??. Never blocks move stepping.</p>
          </div>
        </div>
      )}
    </div>
  );
};
