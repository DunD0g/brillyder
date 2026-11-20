import React, { useEffect, useRef, useState } from 'react';
import {
  Bot,
  Check,
  Database,
  Download,
  Orbit,
  Settings2,
  Sparkles,
  Upload,
  X,
} from 'lucide-react';
import { BOARD_THEME_LIST } from '../chess/boardThemes';
import type { BoardThemeId } from '../types/chess';
import type { VibeMode } from '../utils/vibeCopy';
import { maiaService, type MaiaAvailability } from '../engine/MaiaService';
import {
  exportFullBackup,
  getStorageStats,
  importFullBackup,
  type BackupImportSummary,
  type StorageStats,
} from '../storage/brillyDb';

export interface ExplorerPrefSettings {
  ratingBand: number;
  speeds: string[];
}

interface Props {
  theme: BoardThemeId;
  onThemeChange: (theme: BoardThemeId) => void;
  celebrationsEnabled: boolean;
  onToggleCelebrations: () => void;
  vibe: VibeMode;
  onVibeChange: (vibe: VibeMode) => void;
  maiaEnabled: boolean;
  onToggleMaia: () => void;
  explorerPrefs: ExplorerPrefSettings;
  onExplorerPrefsChange: (prefs: ExplorerPrefSettings) => void;
  onBackupImported: (summary: BackupImportSummary) => void;
}

const RATING_OPTIONS = [1000, 1200, 1400, 1600, 1800, 2000, 2200];
const SPEED_OPTIONS = ['bullet', 'blitz', 'rapid', 'classical'];

export const SettingsMenu: React.FC<Props> = ({
  theme,
  onThemeChange,
  celebrationsEnabled,
  onToggleCelebrations,
  vibe,
  onVibeChange,
  maiaEnabled,
  onToggleMaia,
  explorerPrefs,
  onExplorerPrefsChange,
  onBackupImported,
}) => {
  const [open, setOpen] = useState(false);
  const [stats, setStats] = useState<StorageStats | null>(null);
  const [maiaStatus, setMaiaStatus] = useState<MaiaAvailability>(() => maiaService.getAvailability());
  const [backupMsg, setBackupMsg] = useState<{ kind: 'ok' | 'err'; text: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [importMode, setImportMode] = useState<'merge' | 'replace'>('merge');
  const ref = useRef<HTMLDivElement | null>(null);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    if (!open) return;
    setBackupMsg(null);
    void getStorageStats().then(setStats);
    if (maiaEnabled && !maiaService.getAvailability().checked) {
      void maiaService.probeAvailableModels().then(setMaiaStatus);
    }
    const onPointer = (e: PointerEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('pointerdown', onPointer);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('pointerdown', onPointer);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  const handleExport = async () => {
    setBusy(true);
    setBackupMsg(null);
    try {
      const payload = await exportFullBackup();
      const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      const stamp = new Date().toISOString().slice(0, 10);
      a.href = url;
      a.download = `brillyder-backup-${stamp}.json`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
      setBackupMsg({
        kind: 'ok',
        text: `Exported ${payload.stores.analyzed_games.length} games & ${payload.stores.fsrs_cards.length} FSRS cards.`,
      });
    } catch (err) {
      setBackupMsg({
        kind: 'err',
        text: err instanceof Error ? err.message : 'Export failed.',
      });
    } finally {
      setBusy(false);
    }
  };

  const handleImportFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setBusy(true);
    setBackupMsg(null);
    try {
      const text = await file.text();
      const summary = await importFullBackup(text, { mode: importMode });
      const updatedStats = await getStorageStats();
      setStats(updatedStats);
      setBackupMsg({
        kind: 'ok',
        text: `Imported ${summary.analyzedGames} games, ${summary.repertoires} courses, ${summary.fsrsCards} FSRS cards (${importMode}).`,
      });
      onBackupImported(summary);
    } catch (err) {
      setBackupMsg({
        kind: 'err',
        text: err instanceof Error ? err.message : 'Import failed.',
      });
    } finally {
      setBusy(false);
    }
  };

  const toggleSpeed = (speed: string) => {
    const has = explorerPrefs.speeds.includes(speed);
    const next = has
      ? explorerPrefs.speeds.filter((s) => s !== speed)
      : [...explorerPrefs.speeds, speed];
    if (next.length === 0) return;
    onExplorerPrefsChange({ ...explorerPrefs, speeds: next });
  };

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="inline-flex items-center gap-1.5 rounded-xl border border-slate-800 bg-hull/90 px-2.5 py-2 text-[11px] font-bold text-slate-300 transition hover:border-teal-400/50 hover:text-white"
        aria-label="BrillyDer settings, theme, vibe, and backup"
        aria-expanded={open}
      >
        <Settings2 className="h-4 w-4 text-brilly" />
        <span className="hidden sm:inline">Settings</span>
      </button>

      {open && (
        <div className="absolute right-0 top-full z-[80] mt-2 max-h-[82dvh] w-[min(21rem,calc(100vw-1.5rem))] overflow-y-auto anim-pop glass-card glass-card-strong p-3.5 shadow-2xl nice-scroll">
          <div className="flex items-center justify-between">
            <span className="text-[10px] font-black uppercase tracking-[0.16em] text-brilly">
              Cockpit Settings
            </span>
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="text-slate-500 hover:text-slate-200"
              aria-label="Close settings"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>

          {/* Vibe Toggle */}
          <div className="mt-3 rounded-xl border border-slate-800/90 bg-void/60 p-2.5">
            <div className="flex items-center justify-between">
              <span className="flex items-center gap-1.5 text-[11px] font-bold text-slate-200">
                <Orbit className="h-3.5 w-3.5 text-warp" /> Vibe Copy
              </span>
              <div className="inline-flex rounded-lg border border-slate-800 bg-hull p-0.5">
                {(['cosmic', 'classic'] as VibeMode[]).map((mode) => (
                  <button
                    key={mode}
                    type="button"
                    onClick={() => onVibeChange(mode)}
                    className={`rounded-md px-2.5 py-1 text-[10px] font-black capitalize transition ${
                      vibe === mode
                        ? mode === 'cosmic'
                          ? 'bg-gradient-to-r from-teal-400/25 to-purple-500/25 text-teal-200'
                          : 'bg-slate-700 text-white'
                        : 'text-slate-400 hover:text-slate-200'
                    }`}
                  >
                    {mode}
                  </button>
                ))}
              </div>
            </div>
            <p className="mt-1 text-[10px] leading-snug text-slate-500">
              {vibe === 'cosmic'
                ? 'Space-probe copy: Hull Breach, Tractor Beam, Signal Strength.'
                : 'Classic chess labels: Blunder, Advantage Conversion, Recall %.'}
            </p>
          </div>

          {/* Board Theme */}
          <div className="mt-3">
            <div className="text-[10px] font-black uppercase tracking-[0.14em] text-slate-400">
              Board &amp; Pieces
            </div>
            <div className="mt-1.5 grid grid-cols-2 gap-1.5">
              {BOARD_THEME_LIST.map((t) => (
                <button
                  key={t.id}
                  type="button"
                  onClick={() => onThemeChange(t.id)}
                  className={`rounded-xl border p-2 text-left transition ${
                    theme === t.id
                      ? 'border-teal-400/60 bg-teal-500/10'
                      : 'border-slate-800 bg-void/50 hover:border-slate-600'
                  }`}
                >
                  <span
                    className="grid grid-cols-4 overflow-hidden rounded-md border border-black/30"
                    style={{ aspectRatio: '1 / 0.55' }}
                  >
                    {Array.from({ length: 16 }).map((_, i) => {
                      const x = i % 4;
                      const y = Math.floor(i / 4);
                      return (
                        <span
                          key={i}
                          style={{ backgroundColor: (x + y) % 2 === 0 ? t.lightSquare : t.darkSquare }}
                        />
                      );
                    })}
                  </span>
                  <span className="mt-1.5 flex items-center gap-1 text-[10px] font-bold text-slate-200">
                    {t.shortName}
                    {theme === t.id && <Check className="h-3 w-3 text-brilly" />}
                  </span>
                </button>
              ))}
            </div>
          </div>

          {/* Celebrations */}
          <div className="mt-3 border-t border-slate-800/80 pt-2.5">
            <button
              type="button"
              onClick={onToggleCelebrations}
              className="flex w-full items-center justify-between gap-2 text-left"
            >
              <span className="flex items-center gap-1.5 text-[11px] font-bold text-slate-200">
                <Sparkles className="h-3.5 w-3.5 text-brilly" /> Alien celebrations
              </span>
              <span
                className={`relative h-5 w-9 rounded-full transition ${
                  celebrationsEnabled ? 'bg-teal-500/80' : 'bg-slate-700'
                }`}
              >
                <span
                  className={`absolute top-0.5 h-4 w-4 rounded-full bg-white shadow transition-all ${
                    celebrationsEnabled ? 'left-[1.15rem]' : 'left-0.5'
                  }`}
                />
              </span>
            </button>
            <p className="mt-1 text-[10px] leading-snug text-slate-500">
              Non-blocking UFO toasts on !! and ?? moves.
            </p>
          </div>

          {/* Optional Maia ONNX Human-Like Bot */}
          <div className="mt-3 border-t border-slate-800/80 pt-2.5">
            <button
              type="button"
              onClick={() => {
                const next = !maiaEnabled;
                onToggleMaia();
                if (next) void maiaService.probeAvailableModels().then(setMaiaStatus);
              }}
              className="flex w-full items-center justify-between gap-2 text-left"
            >
              <span className="flex items-center gap-1.5 text-[11px] font-bold text-slate-200">
                <Bot className="h-3.5 w-3.5 text-warp" /> Human-Like Bot (Maia ONNX)
              </span>
              <span
                className={`relative h-5 w-9 rounded-full transition ${
                  maiaEnabled ? 'bg-purple-500/80' : 'bg-slate-700'
                }`}
              >
                <span
                  className={`absolute top-0.5 h-4 w-4 rounded-full bg-white shadow transition-all ${
                    maiaEnabled ? 'left-[1.15rem]' : 'left-0.5'
                  }`}
                />
              </span>
            </button>
            <p className="mt-1 text-[10px] leading-snug text-slate-500">
              {maiaEnabled
                ? maiaStatus.checked
                  ? maiaStatus.availableRatings.length > 0
                    ? `Active models: ${maiaStatus.availableRatings.join(', ')} (ONNX Web Worker).`
                    : 'No public/models/maia-*.onnx detected — falling back cleanly to rating-capped Stockfish.'
                  : 'Checking public/models/maia-*.onnx…'
                : 'Optional ONNX bot for Sparring & Conversion when public/models/maia-*.onnx files are present.'}
            </p>
          </div>

          {/* Explorer Target Band */}
          <div className="mt-3 border-t border-slate-800/80 pt-2.5">
            <div className="flex items-center justify-between text-[10px] font-black uppercase tracking-[0.14em] text-slate-400">
              <span>Explorer Target Pool</span>
              <span className="font-mono text-brilly">{explorerPrefs.ratingBand}+</span>
            </div>
            <div className="mt-1.5 flex flex-wrap gap-1">
              {RATING_OPTIONS.map((r) => (
                <button
                  key={r}
                  type="button"
                  onClick={() => onExplorerPrefsChange({ ...explorerPrefs, ratingBand: r })}
                  className={`rounded-lg border px-2 py-0.5 font-mono text-[10px] font-bold transition ${
                    explorerPrefs.ratingBand === r
                      ? 'border-teal-400/50 bg-teal-400/15 text-teal-200'
                      : 'border-slate-800 bg-void/50 text-slate-400 hover:border-slate-600'
                  }`}
                >
                  {r}
                </button>
              ))}
            </div>
            <div className="mt-1.5 flex flex-wrap gap-1">
              {SPEED_OPTIONS.map((sp) => {
                const active = explorerPrefs.speeds.includes(sp);
                return (
                  <button
                    key={sp}
                    type="button"
                    onClick={() => toggleSpeed(sp)}
                    className={`rounded-lg border px-2 py-0.5 text-[10px] font-bold capitalize transition ${
                      active
                        ? 'border-purple-400/50 bg-purple-500/15 text-purple-200'
                        : 'border-slate-800 bg-void/50 text-slate-500 hover:border-slate-600'
                    }`}
                  >
                    {sp}
                  </button>
                );
              })}
            </div>
          </div>

          {/* IndexedDB Backup / Restore */}
          <div className="mt-3 border-t border-slate-800/80 pt-2.5">
            <div className="flex items-center justify-between">
              <span className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.14em] text-slate-300">
                <Database className="h-3.5 w-3.5 text-brilly" /> Local IndexedDB Backup
              </span>
              {stats && (
                <span className="font-mono text-[9px] text-slate-500">
                  {stats.analyzedGames}g · {stats.fsrsCards}c
                </span>
              )}
            </div>
            <p className="mt-1 text-[10px] leading-snug text-slate-500">
              All games, repertoires, FSRS states, and Woodpecker cycles live locally on this device.
            </p>

            <div className="mt-2 flex items-center justify-between text-[10px]">
              <span className="text-slate-400">Import mode:</span>
              <div className="inline-flex rounded-lg border border-slate-800 bg-void/70 p-0.5">
                {(['merge', 'replace'] as const).map((m) => (
                  <button
                    key={m}
                    type="button"
                    onClick={() => setImportMode(m)}
                    className={`rounded px-2 py-0.5 text-[9px] font-bold capitalize ${
                      importMode === m ? 'bg-teal-500/20 text-teal-200' : 'text-slate-500'
                    }`}
                  >
                    {m}
                  </button>
                ))}
              </div>
            </div>

            <div className="mt-2 grid grid-cols-2 gap-1.5">
              <button
                type="button"
                disabled={busy}
                onClick={() => void handleExport()}
                className="inline-flex items-center justify-center gap-1.5 rounded-xl border border-teal-400/35 bg-teal-400/10 px-2.5 py-2 text-[11px] font-bold text-teal-200 transition hover:bg-teal-400/20 disabled:opacity-50"
              >
                <Download className="h-3.5 w-3.5" /> Export JSON
              </button>
              <button
                type="button"
                disabled={busy}
                onClick={() => fileInputRef.current?.click()}
                className="inline-flex items-center justify-center gap-1.5 rounded-xl border border-purple-400/35 bg-purple-500/10 px-2.5 py-2 text-[11px] font-bold text-purple-200 transition hover:bg-purple-500/20 disabled:opacity-50"
              >
                <Upload className="h-3.5 w-3.5" /> Import JSON
              </button>
              <input
                ref={fileInputRef}
                type="file"
                accept="application/json,.json"
                onChange={(e) => void handleImportFile(e)}
                className="hidden"
              />
            </div>

            {backupMsg && (
              <div
                className={`mt-2 rounded-lg border px-2 py-1.5 text-[10px] leading-snug ${
                  backupMsg.kind === 'ok'
                    ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-200'
                    : 'border-rose-500/30 bg-rose-500/10 text-rose-200'
                }`}
              >
                {backupMsg.text}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
