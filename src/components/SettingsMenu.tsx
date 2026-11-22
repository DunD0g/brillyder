import React, { useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import {
  Bot,
  Check,
  Cpu,
  Database,
  Download,
  Orbit,
  Palette,
  Settings2,
  Sparkles,
  Trash2,
  Upload,
  X,
} from 'lucide-react';
import { BOARD_THEME_LIST } from '../chess/boardThemes';
import type { AnalysisDepthPreset, BoardThemeId } from '../types/chess';
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
  depthPreset: AnalysisDepthPreset;
  onDepthPresetChange: (depth: AnalysisDepthPreset) => void;
  maiaEnabled: boolean;
  onToggleMaia: () => void;
  explorerPrefs: ExplorerPrefSettings;
  onExplorerPrefsChange: (prefs: ExplorerPrefSettings) => void;
  onBackupImported: (summary: BackupImportSummary) => void;
}

const RATING_OPTIONS = [1000, 1200, 1400, 1600, 1800, 2000, 2200];
const SPEED_OPTIONS = ['bullet', 'blitz', 'rapid', 'classical'];
const DEPTH_OPTIONS: Array<{ value: AnalysisDepthPreset; label: string; sub: string }> = [
  { value: 12, label: 'Fast', sub: 'D12' },
  { value: 14, label: 'Balanced', sub: 'D14→18' },
  { value: 18, label: 'Deep', sub: 'D18→20' },
];

export const SettingsMenu: React.FC<Props> = ({
  theme,
  onThemeChange,
  celebrationsEnabled,
  onToggleCelebrations,
  vibe,
  onVibeChange,
  depthPreset,
  onDepthPresetChange,
  maiaEnabled,
  onToggleMaia,
  explorerPrefs,
  onExplorerPrefsChange,
  onBackupImported,
}) => {
  const [open, setOpen] = useState(false);
  const [stats, setStats] = useState<StorageStats | null>(null);
  const [maiaStatus, setMaiaStatus] = useState<MaiaAvailability>(() => maiaService.getAvailability());
  const [maiaUploadMsg, setMaiaUploadMsg] = useState<{ kind: 'ok' | 'err'; text: string } | null>(null);
  const [maiaBusy, setMaiaBusy] = useState(false);
  const [backupMsg, setBackupMsg] = useState<{ kind: 'ok' | 'err'; text: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [importMode, setImportMode] = useState<'merge' | 'replace'>('merge');
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const maiaInputRef = useRef<HTMLInputElement | null>(null);

  useEffect(() => {
    if (!open) return;
    setBackupMsg(null);
    setMaiaUploadMsg(null);
    void getStorageStats().then(setStats);

    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';

    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        setOpen(false);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => {
      document.body.style.overflow = prevOverflow;
      window.removeEventListener('keydown', onKey);
    };
  }, [open]);

  useEffect(() => {
    if (open && maiaEnabled && !maiaService.getAvailability().checked) {
      void maiaService.probeAvailableModels().then(setMaiaStatus);
    }
  }, [open, maiaEnabled]);

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
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);
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

  const handleMaiaFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    setMaiaBusy(true);
    setMaiaUploadMsg(null);
    try {
      const info = await maiaService.importLocalModel(file);
      setMaiaStatus(maiaService.getAvailability());
      const mb = (info.sizeBytes / (1024 * 1024)).toFixed(1);
      setMaiaUploadMsg({ kind: 'ok', text: `Cached Maia ${info.rating} (${mb} MB) on-device.` });
    } catch (err) {
      setMaiaUploadMsg({ kind: 'err', text: err instanceof Error ? err.message : 'Model load failed.' });
    } finally {
      setMaiaBusy(false);
    }
  };

  const handleRemoveMaiaModel = async (rating: number) => {
    setMaiaBusy(true);
    try {
      const next = await maiaService.removeLocalModel(rating);
      setMaiaStatus(next);
      setMaiaUploadMsg({ kind: 'ok', text: `Removed local Maia ${rating} model.` });
    } finally {
      setMaiaBusy(false);
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

  const sheetTitle = vibe === 'cosmic' ? 'Cockpit Settings' : 'Settings';

  const modalContent = open ? (
    <div
      className="fixed inset-0 z-[95] flex items-end justify-center bg-[#04070e]/80 backdrop-blur-md sm:items-center sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-label={sheetTitle}
      onClick={(e) => {
        if (e.target === e.currentTarget) setOpen(false);
      }}
    >
      <div
        className="anim-pop flex max-h-[88dvh] w-full flex-col overflow-hidden rounded-t-3xl border border-b-0 border-teal-400/25 bg-[#0B1220] text-slate-100 shadow-[0_24px_80px_rgba(0,0,0,0.85)] sm:max-h-[85dvh] sm:max-w-md sm:rounded-2xl sm:border-b"
      >
        {/* Mobile drag-handle hint */}
        <div className="flex justify-center pt-2 sm:hidden" aria-hidden="true">
          <span className="h-1 w-10 rounded-full bg-slate-700" />
        </div>

        {/* Sticky Sheet Header */}
        <div className="flex items-center justify-between gap-2 border-b border-slate-800/90 px-4 py-3">
          <div className="flex items-center gap-2.5">
            <span className="inline-flex h-8 w-8 items-center justify-center rounded-xl border border-teal-400/35 bg-teal-400/10 text-brilly">
              <Settings2 className="h-4 w-4" />
            </span>
            <div>
              <div className="text-xs font-black uppercase tracking-[0.16em] text-brilly">
                {sheetTitle}
              </div>
              <div className="text-[10px] text-slate-400">
                Theme, engine depth, bots &amp; local backup
              </div>
            </div>
          </div>
          <button
            type="button"
            onClick={() => setOpen(false)}
            className="inline-flex h-9 w-9 items-center justify-center rounded-xl border border-slate-700/80 bg-slate-900/90 text-slate-300 transition hover:border-teal-400/50 hover:text-white active:scale-95"
            aria-label="Close settings"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Scrollable Sheet Body */}
        <div className="flex-1 space-y-4 overflow-y-auto overscroll-contain px-4 py-3.5 nice-scroll pb-[max(1.5rem,env(safe-area-inset-bottom))]">
          {/* SECTION 1: Appearance & Feel */}
          <section className="space-y-2.5">
            <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.16em] text-slate-400">
              <Palette className="h-3.5 w-3.5 text-brilly" /> Appearance &amp; Vibe
            </div>

            {/* Vibe Copy */}
            <div className="rounded-2xl border border-slate-800/90 bg-[#070B14]/85 p-3">
              <div className="flex items-center justify-between gap-2">
                <div className="min-w-0">
                  <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
                    <Orbit className="h-3.5 w-3.5 shrink-0 text-warp" /> Copy Style
                  </div>
                  <p className="mt-0.5 text-[10px] leading-snug text-slate-400">
                    {vibe === 'cosmic'
                      ? 'Hull Breach, Tractor Beam, Signal Strength.'
                      : 'Standard labels: Blunder, Conversion, Recall %.'}
                  </p>
                </div>
                <div className="inline-flex shrink-0 rounded-xl border border-slate-800 bg-hull p-0.5">
                  {(['cosmic', 'classic'] as VibeMode[]).map((mode) => (
                    <button
                      key={mode}
                      type="button"
                      onClick={() => onVibeChange(mode)}
                      className={`rounded-lg px-2.5 py-1.5 text-[11px] font-black capitalize transition ${
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
            </div>

            {/* Board Theme */}
            <div className="rounded-2xl border border-slate-800/90 bg-[#070B14]/85 p-3">
              <div className="text-[11px] font-bold text-slate-200">Board Theme</div>
              <div className="mt-2 grid grid-cols-2 gap-2">
                {BOARD_THEME_LIST.map((t) => {
                  const active = theme === t.id;
                  return (
                    <button
                      key={t.id}
                      type="button"
                      onClick={() => onThemeChange(t.id)}
                      className={`flex flex-col rounded-xl border p-2 text-left transition active:scale-[0.98] ${
                        active
                          ? 'border-teal-400/65 bg-teal-400/12 ring-1 ring-teal-400/25'
                          : 'border-slate-800 bg-hull/60 hover:border-slate-600'
                      }`}
                    >
                      <span
                        className="grid w-full grid-cols-4 overflow-hidden rounded-lg border border-black/30"
                        style={{ aspectRatio: '2 / 1' }}
                      >
                        {Array.from({ length: 8 }).map((_, i) => {
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
                      <span className="mt-1.5 flex items-center justify-between gap-1 text-[11px] font-bold text-slate-100">
                        <span className="truncate">{t.shortName}</span>
                        {active && <Check className="h-3.5 w-3.5 shrink-0 text-brilly" />}
                      </span>
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Move Celebrations */}
            <button
              type="button"
              onClick={onToggleCelebrations}
              className="flex w-full items-center justify-between gap-3 rounded-2xl border border-slate-800/90 bg-[#070B14]/85 p-3 text-left transition hover:border-slate-700"
            >
              <div className="min-w-0">
                <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
                  <Sparkles className="h-3.5 w-3.5 shrink-0 text-brilly" />
                  {vibe === 'cosmic' ? 'Alien Celebrations' : 'Move Celebrations'}
                </div>
                <p className="mt-0.5 text-[10px] leading-snug text-slate-400">
                  {vibe === 'cosmic'
                    ? 'Non-blocking UFO toasts on !! and ?? moves.'
                    : 'Non-blocking banners on brilliant (!!) and blunder (??) moves.'}
                </p>
              </div>
              <span
                className={`relative h-6 w-11 shrink-0 rounded-full transition ${
                  celebrationsEnabled ? 'bg-teal-500/85' : 'bg-slate-700'
                }`}
              >
                <span
                  className={`absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-all ${
                    celebrationsEnabled ? 'left-[1.35rem]' : 'left-0.5'
                  }`}
                />
              </span>
            </button>
          </section>

          {/* SECTION 2: Engine, Bots & Explorer */}
          <section className="space-y-2.5">
            <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.16em] text-slate-400">
              <Cpu className="h-3.5 w-3.5 text-brilly" /> Engine &amp; Opening Pool
            </div>

            {/* Engine Depth */}
            <div className="rounded-2xl border border-slate-800/90 bg-[#070B14]/85 p-3">
              <div className="flex items-center justify-between text-xs font-bold text-slate-100">
                <span>Stockfish Review Depth</span>
                <span className="font-mono text-[11px] text-brilly">D{depthPreset}</span>
              </div>
              <div className="mt-2 grid grid-cols-3 gap-1.5">
                {DEPTH_OPTIONS.map((opt) => (
                  <button
                    key={opt.value}
                    type="button"
                    onClick={() => onDepthPresetChange(opt.value)}
                    className={`rounded-xl border px-2 py-2 text-center transition active:scale-[0.98] ${
                      depthPreset === opt.value
                        ? 'border-teal-400/55 bg-teal-400/15 text-teal-100'
                        : 'border-slate-800 bg-hull/60 text-slate-400 hover:border-slate-600'
                    }`}
                  >
                    <div className="text-[11px] font-black">{opt.label}</div>
                    <div className="font-mono text-[9px] text-slate-400">{opt.sub}</div>
                  </button>
                ))}
              </div>
            </div>

            {/* Explorer Target Pool */}
            <div className="rounded-2xl border border-slate-800/90 bg-[#070B14]/85 p-3">
              <div className="flex items-center justify-between text-xs font-bold text-slate-100">
                <span>Lichess Explorer Pool</span>
                <span className="font-mono text-[11px] text-brilly">{explorerPrefs.ratingBand}+</span>
              </div>
              <div className="mt-2 flex flex-wrap gap-1.5">
                {RATING_OPTIONS.map((r) => (
                  <button
                    key={r}
                    type="button"
                    onClick={() => onExplorerPrefsChange({ ...explorerPrefs, ratingBand: r })}
                    className={`rounded-lg border px-2.5 py-1 font-mono text-[11px] font-bold transition ${
                      explorerPrefs.ratingBand === r
                        ? 'border-teal-400/55 bg-teal-400/15 text-teal-200'
                        : 'border-slate-800 bg-hull/60 text-slate-400 hover:border-slate-600'
                    }`}
                  >
                    {r}
                  </button>
                ))}
              </div>
              <div className="mt-2 grid grid-cols-4 gap-1.5">
                {SPEED_OPTIONS.map((sp) => {
                  const active = explorerPrefs.speeds.includes(sp);
                  return (
                    <button
                      key={sp}
                      type="button"
                      onClick={() => toggleSpeed(sp)}
                      className={`rounded-lg border py-1.5 text-center text-[10px] font-bold capitalize transition ${
                        active
                          ? 'border-purple-400/55 bg-purple-500/15 text-purple-200'
                          : 'border-slate-800 bg-hull/60 text-slate-500 hover:border-slate-600'
                      }`}
                    >
                      {sp}
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Maia ONNX Human-Like Bot */}
            <div className="rounded-2xl border border-slate-800/90 bg-[#070B14]/85 p-3">
              <button
                type="button"
                onClick={() => {
                  const next = !maiaEnabled;
                  onToggleMaia();
                  if (next) void maiaService.probeAvailableModels().then(setMaiaStatus);
                }}
                className="flex w-full items-center justify-between gap-3 text-left"
              >
                <div className="min-w-0">
                  <div className="flex items-center gap-1.5 text-xs font-bold text-slate-100">
                    <Bot className="h-3.5 w-3.5 shrink-0 text-warp" /> Human-Like Bot (Maia ONNX)
                  </div>
                  <p className="mt-0.5 text-[10px] leading-snug text-slate-400">
                    {maiaEnabled
                      ? maiaStatus.checked
                        ? maiaStatus.availableRatings.length > 0
                          ? `Active models: ${maiaStatus.availableRatings.join(', ')}`
                          : 'No local .onnx loaded yet — using Stockfish fallback.'
                        : 'Checking local Maia models…'
                      : 'Optional ONNX bot for Sparring & Conversion.'}
                  </p>
                </div>
                <span
                  className={`relative h-6 w-11 shrink-0 rounded-full transition ${
                    maiaEnabled ? 'bg-purple-500/85' : 'bg-slate-700'
                  }`}
                >
                  <span
                    className={`absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-all ${
                      maiaEnabled ? 'left-[1.35rem]' : 'left-0.5'
                    }`}
                  />
                </span>
              </button>

              {maiaEnabled && (
                <div className="mt-2.5 space-y-2 rounded-xl border border-purple-500/25 bg-hull/60 p-2.5">
                  <input
                    ref={maiaInputRef}
                    type="file"
                    accept=".onnx"
                    onChange={(e) => void handleMaiaFile(e)}
                    className="hidden"
                  />
                  <div className="flex items-center justify-between gap-2">
                    <button
                      type="button"
                      disabled={maiaBusy}
                      onClick={() => maiaInputRef.current?.click()}
                      className="inline-flex items-center gap-1.5 rounded-lg border border-purple-400/40 bg-purple-500/15 px-2.5 py-1.5 text-[11px] font-bold text-purple-200 hover:bg-purple-500/25 disabled:opacity-50"
                    >
                      <Upload className="h-3.5 w-3.5" /> {maiaBusy ? 'Caching…' : 'Load .onnx file'}
                    </button>
                    <span className="text-[10px] text-slate-400">Cached on-device</span>
                  </div>
                  {maiaStatus.localModels.length > 0 && (
                    <div className="flex flex-wrap gap-1.5">
                      {maiaStatus.localModels.map((m) => (
                        <span
                          key={m.rating}
                          className="inline-flex items-center gap-1.5 rounded-lg border border-purple-400/35 bg-purple-500/10 px-2 py-1 font-mono text-[10px] font-bold text-purple-200"
                        >
                          {m.rating}
                          {m.sizeBytes > 0 ? ` (${(m.sizeBytes / (1024 * 1024)).toFixed(1)}M)` : ''}
                          <button
                            type="button"
                            onClick={() => void handleRemoveMaiaModel(m.rating)}
                            aria-label={`Remove local Maia ${m.rating}`}
                            className="text-slate-400 hover:text-rose-300"
                          >
                            <Trash2 className="h-3 w-3" />
                          </button>
                        </span>
                      ))}
                    </div>
                  )}
                  {maiaUploadMsg && (
                    <p className={`text-[10px] ${maiaUploadMsg.kind === 'ok' ? 'text-teal-300' : 'text-rose-300'}`}>
                      {maiaUploadMsg.text}
                    </p>
                  )}
                </div>
              )}
            </div>
          </section>

          {/* SECTION 3: Local Data & Backup */}
          <section className="space-y-2.5">
            <div className="flex items-center justify-between">
              <span className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.16em] text-slate-400">
                <Database className="h-3.5 w-3.5 text-brilly" /> Local IndexedDB Backup
              </span>
              {stats && (
                <span className="rounded-full border border-slate-800 bg-void px-2 py-0.5 font-mono text-[9px] text-slate-400">
                  {stats.analyzedGames} games · {stats.fsrsCards} FSRS
                </span>
              )}
            </div>

            <div className="rounded-2xl border border-slate-800/90 bg-[#070B14]/85 p-3">
              <p className="text-[10px] leading-relaxed text-slate-400">
                100% local-first storage — games, repertoires, FSRS cards, bookmarks, and Woodpecker cycles stay on your device.
              </p>

              <div className="mt-2.5 flex items-center justify-between text-[11px]">
                <span className="text-slate-300">Import mode</span>
                <div className="inline-flex rounded-lg border border-slate-800 bg-hull p-0.5">
                  {(['merge', 'replace'] as const).map((m) => (
                    <button
                      key={m}
                      type="button"
                      onClick={() => setImportMode(m)}
                      className={`rounded-md px-2.5 py-1 text-[10px] font-bold capitalize ${
                        importMode === m ? 'bg-teal-500/20 text-teal-200' : 'text-slate-400'
                      }`}
                    >
                      {m}
                    </button>
                  ))}
                </div>
              </div>

              <div className="mt-2.5 grid grid-cols-2 gap-2">
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => void handleExport()}
                  className="inline-flex items-center justify-center gap-1.5 rounded-xl border border-teal-400/40 bg-teal-400/12 px-3 py-2.5 text-xs font-bold text-teal-200 transition hover:bg-teal-400/20 disabled:opacity-50"
                >
                  <Download className="h-3.5 w-3.5" /> Export JSON
                </button>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => fileInputRef.current?.click()}
                  className="inline-flex items-center justify-center gap-1.5 rounded-xl border border-purple-400/40 bg-purple-500/12 px-3 py-2.5 text-xs font-bold text-purple-200 transition hover:bg-purple-500/20 disabled:opacity-50"
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
                  className={`mt-2.5 rounded-xl border px-2.5 py-2 text-[11px] leading-snug ${
                    backupMsg.kind === 'ok'
                      ? 'border-emerald-500/35 bg-emerald-500/10 text-emerald-200'
                      : 'border-rose-500/35 bg-rose-500/10 text-rose-200'
                  }`}
                >
                  {backupMsg.text}
                </div>
              )}
            </div>
          </section>
        </div>
      </div>
    </div>
  ) : null;

  return (
    <>
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

      {typeof document !== 'undefined' && modalContent
        ? createPortal(modalContent, document.body)
        : modalContent}
    </>
  );
};
