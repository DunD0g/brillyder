import React, { useEffect, useRef, useState } from 'react';
import {
  AlertTriangle,
  CheckCircle2,
  Compass,
  Loader2,
  Plus,
  RefreshCw,
  ShieldAlert,
  Sparkles,
} from 'lucide-react';
import type { BoardThemeId } from '../../types/chess';
import type { OpeningCourse } from '../../types/openings';
import {
  computeCourseCoverage,
  type CoverageReport,
  type RepertoireGap,
} from '../../services/repertoireCoverage';
import { fetchLichessExplorer, type ExplorerMoveStat } from '../../services/openingExplorer';
import { stockfishService } from '../../engine/StockfishService';
import { uciLineToSan } from '../../utils/chessMath';
import type { ExplorerPrefSettings } from '../SettingsMenu';
import { ChessgroundBoard } from '../ChessgroundBoard';
import { ProgressRing } from '../ProgressRing';

interface Props {
  course: OpeningCourse;
  boardTheme: BoardThemeId;
  explorerPrefs: ExplorerPrefSettings;
  onPatchGap: (course: OpeningCourse, gap: RepertoireGap, replySan: string, note: string) => Promise<void>;
}

interface CandidateReply {
  san: string;
  evalDisplay: string;
  pvSan: string;
  humanWinPct: number | null;
  humanGames: number;
}

export const CoverageGapPanel: React.FC<Props> = ({
  course,
  boardTheme,
  explorerPrefs,
  onPatchGap,
}) => {
  const [loading, setLoading] = useState(false);
  const [report, setReport] = useState<CoverageReport | null>(null);
  const [selectedGap, setSelectedGap] = useState<RepertoireGap | null>(null);
  const [candidates, setCandidates] = useState<CandidateReply[]>([]);
  const [analyzingGap, setAnalyzingGap] = useState(false);
  const [patching, setPatching] = useState<string | null>(null);
  const [patchedNotice, setPatchedNotice] = useState<string | null>(null);
  const [scanError, setScanError] = useState<string | null>(null);
  const scanIdRef = useRef(0);
  const gapIdRef = useRef(0);

  const runCoverageScan = async (preserveNotice = false) => {
    const id = scanIdRef.current + 1;
    scanIdRef.current = id;
    setLoading(true);
    setScanError(null);
    if (!preserveNotice) setPatchedNotice(null);
    setSelectedGap(null);
    setCandidates([]);
    try {
      const res = await computeCourseCoverage(course, {
        ratingBand: explorerPrefs.ratingBand,
        speeds: explorerPrefs.speeds,
        shouldCancel: () => scanIdRef.current !== id,
      });
      if (scanIdRef.current !== id) return;
      setReport(res);
      if (res.uncoveredGaps.length > 0) {
        void inspectGap(res.uncoveredGaps[0]);
      }
    } catch (err) {
      if (scanIdRef.current === id) {
        setScanError(err instanceof Error ? err.message : 'Coverage scan failed — tap Rescan to retry.');
      }
    } finally {
      if (scanIdRef.current === id) setLoading(false);
    }
  };

  useEffect(() => {
    setPatchedNotice(null);
  }, [course.id]);

  useEffect(() => {
    void runCoverageScan(true);
    return () => {
      scanIdRef.current += 1;
      gapIdRef.current += 1;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [course.id, course.lines.length, explorerPrefs.ratingBand, explorerPrefs.speeds.join(',')]);

  const inspectGap = async (gap: RepertoireGap) => {
    const id = gapIdRef.current + 1;
    gapIdRef.current = id;
    setSelectedGap(gap);
    setCandidates([]);
    setScanError(null);
    setAnalyzingGap(true);
    try {
      const [sfRes, expRes] = await Promise.all([
        stockfishService.analyzePosition(gap.fen, { depth: 14, multiPv: 3, timeoutMs: 12000 }),
        fetchLichessExplorer(gap.fen, {
          ratingBand: explorerPrefs.ratingBand,
          speeds: explorerPrefs.speeds,
          moves: 10,
        }),
      ]);
      if (gapIdRef.current !== id) return;

      const expMap = new Map<string, ExplorerMoveStat>();
      for (const m of expRes?.moves ?? []) expMap.set(m.san, m);

      const list: CandidateReply[] = [];
      for (const line of sfRes.lines.slice(0, 3)) {
        const sanLine = uciLineToSan(gap.fen, line.pv, 4);
        const firstSan = sanLine[0];
        if (!firstSan || list.some((c) => c.san === firstSan)) continue;
        const exp = expMap.get(firstSan);
        let winPct: number | null = null;
        if (exp && exp.games > 0) {
          const userScore = course.side === 'white'
            ? (exp.white + exp.draws * 0.5) / exp.games
            : (exp.black + exp.draws * 0.5) / exp.games;
          winPct = Math.round(userScore * 100);
        }
        list.push({
          san: firstSan,
          evalDisplay: line.score.display,
          pvSan: sanLine.join(' '),
          humanWinPct: winPct,
          humanGames: exp?.games ?? 0,
        });
      }
      setCandidates(list);
    } catch {
      if (gapIdRef.current === id) {
        setScanError('Stockfish busy or offline — click this gap again to retry analysis.');
      }
    } finally {
      if (gapIdRef.current === id) setAnalyzingGap(false);
    }
  };

  const handlePatch = async (cand: CandidateReply) => {
    if (!selectedGap) return;
    setPatching(cand.san);
    setScanError(null);
    try {
      const note = `Stockfish candidate ${cand.san} (${cand.evalDisplay}${cand.humanWinPct !== null ? `, ${cand.humanWinPct}% human score` : ''}). Line: ${cand.pvSan}`;
      await onPatchGap(course, selectedGap, cand.san, note);
      setPatchedNotice(`Patched ${cand.san} against ${selectedGap.opponentSan} — added to repertoire & unlocked in FSRS!`);
    } catch (err) {
      setScanError(err instanceof Error ? err.message : 'Could not patch gap.');
    } finally {
      setPatching(null);
    }
  };

  const orientation = course.side === 'white' ? 'w' : 'b';

  return (
    <div className="space-y-3">
      <div className="glass-card glass-card-strong p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.16em] text-brilly">
              <Compass className="h-3.5 w-3.5" /> Real-World Coverage Scanner
            </div>
            <h3 className="mt-0.5 text-base font-extrabold text-white">
              {course.name} vs {explorerPrefs.ratingBand}+ ({explorerPrefs.speeds.join('/')})
            </h3>
            <p className="mt-0.5 text-[11px] text-slate-400">
              Measures coverage of opponent replies played ≥5% down to ≥2% line probability via Lichess Explorer.
            </p>
          </div>
          <div className="flex items-center gap-3">
            {report && (
              <ProgressRing
                value={report.expectedCoveragePct}
                size={64}
                stroke={6}
                tone={report.expectedCoveragePct >= 75 ? 'emerald' : 'cyan'}
                label={`${report.expectedCoveragePct}%`}
                sublabel="covered"
              />
            )}
            <button
              type="button"
              disabled={loading}
              onClick={() => void runCoverageScan()}
              className="inline-flex items-center gap-1.5 rounded-xl border border-slate-700 bg-hull px-3 py-2 text-[11px] font-bold text-slate-200 hover:border-teal-400/50 disabled:opacity-50"
            >
              {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin text-brilly" /> : <RefreshCw className="h-3.5 w-3.5 text-brilly" />}
              {loading ? 'Scanning…' : 'Rescan'}
            </button>
          </div>
        </div>

        {report && (
          <div className="mt-3 flex flex-wrap gap-2 text-[10px]">
            <span className="rounded-full border border-slate-700 bg-void/70 px-2.5 py-0.5 text-slate-300">
              Source: <strong className="text-brilly">{report.source === 'lichess' ? 'Lichess Explorer' : 'Offline ECO Book'}</strong>
            </span>
            <span className="rounded-full border border-slate-700 bg-void/70 px-2.5 py-0.5 text-slate-300">
              {report.positionsScanned} branch points scanned
            </span>
            <span className="rounded-full border border-slate-700 bg-void/70 px-2.5 py-0.5 text-slate-300">
              {report.uncoveredGaps.length} gap{report.uncoveredGaps.length === 1 ? '' : 's'} found
            </span>
          </div>
        )}

        {patchedNotice && (
          <div className="mt-2.5 flex items-center gap-2 rounded-xl border border-emerald-400/35 bg-emerald-500/10 px-3 py-2 text-xs text-emerald-200">
            <CheckCircle2 className="h-4 w-4 shrink-0" /> {patchedNotice}
          </div>
        )}

        {scanError && (
          <div className="mt-2.5 flex items-center gap-2 rounded-xl border border-rose-500/35 bg-rose-500/10 px-3 py-2 text-xs text-rose-200">
            <AlertTriangle className="h-4 w-4 shrink-0" /> {scanError}
          </div>
        )}
      </div>

      {loading && !report ? (
        <div className="glass-card flex items-center justify-center gap-2.5 p-8 text-xs text-slate-300">
          <div className="radar-sweep h-6 w-6 shrink-0" />
          Scanning Lichess Opening Explorer for uncovered replies…
        </div>
      ) : report && report.uncoveredGaps.length === 0 ? (
        <div className="glass-card border-emerald-500/30 p-6 text-center">
          <CheckCircle2 className="mx-auto h-8 w-8 text-clean" />
          <h4 className="mt-2 text-sm font-extrabold text-white">No major gaps detected!</h4>
          <p className="mt-1 text-xs text-slate-400">
            Your {course.name} repertoire covers every frequent opponent reply at the {explorerPrefs.ratingBand}+ bracket.
          </p>
        </div>
      ) : report ? (
        <div className="grid grid-cols-1 gap-3 lg:grid-cols-[minmax(0,1fr)_minmax(0,420px)]">
          {/* Gap List */}
          <div className="min-w-0 glass-card p-3.5">
            <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.16em] text-amber-300">
              <ShieldAlert className="h-3.5 w-3.5" /> Top Uncovered Opponent Replies
            </div>
            <div className="mt-2 space-y-1.5">
              {report.uncoveredGaps.slice(0, 8).map((gap, idx) => {
                const active = selectedGap?.id === gap.id;
                return (
                  <button
                    key={gap.id}
                    type="button"
                    onClick={() => void inspectGap(gap)}
                    className={`flex w-full items-center justify-between gap-2 rounded-xl border p-2.5 text-left transition ${
                      active
                        ? 'border-teal-400/55 bg-teal-400/12'
                        : 'border-slate-800 bg-void/50 hover:border-slate-600'
                    }`}
                  >
                    <div className="min-w-0">
                      <div className="flex items-center gap-1.5">
                        {idx === 0 && (
                          <span className="rounded bg-rose-500/20 px-1.5 py-0.5 text-[9px] font-black text-rose-300">
                            #1 GAP
                          </span>
                        )}
                        <span className="font-mono text-xs font-extrabold text-white">
                          {gap.opponentSan}
                        </span>
                        <span className="text-[10px] text-slate-400">
                          ({Math.round(gap.replyShare * 100)}% reply share)
                        </span>
                      </div>
                      <div className="mt-0.5 truncate font-mono text-[10px] text-slate-500">
                        {gap.moveSequence.map((m, i) => (i % 2 === 0 ? `${Math.floor(i / 2) + 1}.${m}` : m)).join(' ')}
                      </div>
                    </div>
                    <span className="shrink-0 rounded-lg border border-purple-400/30 bg-purple-500/10 px-2 py-1 font-mono text-[10px] font-bold text-purple-200">
                      {(gap.lineProb * 100).toFixed(1)}% line
                    </span>
                  </button>
                );
              })}
            </div>
          </div>

          {/* Selected Gap Patcher */}
          {selectedGap && (
            <div className="min-w-0 glass-card glass-card-strong p-3.5 space-y-3">
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-1.5 text-xs font-extrabold text-white">
                  <Sparkles className="h-4 w-4 text-brilly" /> Patch Gap vs {selectedGap.opponentSan}
                </div>
                <span className="font-mono text-[10px] text-slate-400">
                  {selectedGap.games.toLocaleString()} games
                </span>
              </div>

              <div className="mx-auto max-w-[260px]">
                <ChessgroundBoard
                  fen={selectedGap.fen}
                  orientation={orientation}
                  interactive={false}
                  showBestArrow={false}
                  showPlayedArrow={false}
                  theme={boardTheme}
                />
              </div>

              <div>
                <div className="text-[10px] font-black uppercase tracking-[0.14em] text-slate-400">
                  Stockfish Top 3 Candidates + Human Win Rate
                </div>
                {analyzingGap ? (
                  <div className="mt-2 flex items-center gap-2 rounded-xl border border-slate-800 bg-void/60 p-3 text-xs text-slate-300">
                    <Loader2 className="h-3.5 w-3.5 animate-spin text-brilly" /> Calculating Stockfish MultiPV=3…
                  </div>
                ) : (
                  <div className="mt-2 space-y-1.5">
                    {candidates.map((cand) => (
                      <div
                        key={cand.san}
                        className="flex items-center justify-between gap-2 rounded-xl border border-slate-800 bg-void/60 p-2.5"
                      >
                        <div className="min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="font-mono text-sm font-black text-brilly">{cand.san}</span>
                            <span className="rounded bg-hull px-1.5 py-0.5 font-mono text-[10px] font-bold text-slate-200">
                              {cand.evalDisplay}
                            </span>
                            {cand.humanWinPct !== null && (
                              <span className="text-[10px] font-bold text-clean">
                                {cand.humanWinPct}% score ({cand.humanGames.toLocaleString()})
                              </span>
                            )}
                          </div>
                          <div className="mt-0.5 truncate font-mono text-[10px] text-slate-500">
                            {cand.pvSan}
                          </div>
                        </div>
                        <button
                          type="button"
                          disabled={patching !== null}
                          onClick={() => void handlePatch(cand)}
                          className="inline-flex shrink-0 items-center gap-1 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-2.5 py-1.5 text-[11px] font-extrabold text-slate-950 disabled:opacity-50"
                        >
                          {patching === cand.san ? (
                            <Loader2 className="h-3 w-3 animate-spin" />
                          ) : (
                            <Plus className="h-3.5 w-3.5" />
                          )}
                          Patch Gap
                        </button>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      ) : null}
    </div>
  );
};
