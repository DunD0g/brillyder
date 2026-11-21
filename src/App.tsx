import React, { lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  BarChart3,
  BookOpen,
  Gem,
  GraduationCap,
  ListChecks,
  Pause,
  Play,
  Sparkles,
  Volume2,
  VolumeX,
  X,
  type LucideIcon,
} from 'lucide-react';
import type {
  AnalysisDepthPreset,
  AnalyzedGame,
  BoardThemeId,
  GamePlatform,
  LichessGameRecord,
  ScoutState,
} from './types/chess';
import type { FsrsOpeningCard, OpeningCourse, WoodpeckerCycleRecord } from './types/openings';
import starterCoursesData from './data/starterCourses.json';
import { getStoredBoardTheme, storeBoardTheme } from './chess/boardThemes';
import { refreshBrilliantClassifications } from './chess/classification';
import { analyzeGameToReview, AnalysisCancelledError } from './services/analysisRunner';
import { fetchGamesForPlatform, platformLabel } from './services/gameSource';
import { buildBrillyVault } from './services/vault';
import { buildMistakeDeck } from './services/mistakeDeck';
import type { DailyDurationMinutes } from './services/dailyCoach';
import {
  extractLichessGameId,
  fetchLichessGameByUrlOrId,
  parseRawPgnToGame,
  SAMPLE_GAMES,
} from './services/lichessApi';
import {
  getAllAnalyzedGames,
  getPref,
  hydrateStorageFromIndexedDb,
  saveAnalyzedGame,
  setPref,
} from './storage/gameDb';
import {
  deleteFsrsCardsByLine,
  deleteRepertoire,
  getAllFsrsCards,
  getAllRepertoires,
  getAllWoodpeckerCycles,
  getTrainingLog,
  saveFsrsCard,
  saveFsrsCardsBulk,
  saveRepertoire,
  saveTrainingLog,
  saveWoodpeckerCycle,
  type BackupImportSummary,
} from './storage/brillyDb';
import { removeLineFromCourse } from './services/repertoireLines';
import { stockfishService } from './engine/StockfishService';
import { maiaService } from './engine/MaiaService';
import { soundManager } from './utils/sound';
import { computeBatchProgressPercent, computeSingleGamePercent } from './utils/analysisProgress';
import { getVibeCopy, VibeProvider, type VibeMode } from './utils/vibeCopy';
import {
  boostCardToDueNow,
  createFsrsOpeningCard,
  hydrateCourseCards,
  isCardDue,
} from './lib/fsrsOpening';
import { addPatchedLineToCourse } from './services/repertoireCoverage';
import type { RepertoireDeviation } from './services/deviationDetector';
import { GameListView, type BatchState } from './components/GameListView';
import type { TrainSection } from './components/MistakeTrainerView';
import { SettingsMenu, type ExplorerPrefSettings } from './components/SettingsMenu';

const AnalysisView = lazy(() =>
  import('./components/AnalysisView').then((m) => ({ default: m.AnalysisView }))
);
const OpeningsView = lazy(() =>
  import('./components/OpeningsView').then((m) => ({ default: m.OpeningsView }))
);
const MistakeTrainerView = lazy(() =>
  import('./components/MistakeTrainerView').then((m) => ({ default: m.MistakeTrainerView }))
);
const InsightsView = lazy(() =>
  import('./components/InsightsView').then((m) => ({ default: m.InsightsView }))
);
const BrillyVaultModal = lazy(() =>
  import('./components/BrillyVaultModal').then((m) => ({ default: m.BrillyVaultModal }))
);
const GravityCheckModal = lazy(() =>
  import('./components/train/GravityCheckModal').then((m) => ({ default: m.GravityCheckModal }))
);

const TabLoadingCard: React.FC = () => (
  <div className="glass-card mx-auto flex max-w-md items-center justify-center gap-2.5 p-8 text-xs font-bold text-teal-200">
    <span className="radar-sweep h-4 w-4 shrink-0" aria-hidden="true" />
    Loading cockpit module…
  </div>
);

type ActiveTab = 'games' | 'analyze' | 'openings' | 'train' | 'insights';

interface NavItem {
  id: ActiveTab;
  label: string;
  Icon: LucideIcon;
}

const NAV_ITEMS: NavItem[] = [
  { id: 'games', label: 'Games', Icon: ListChecks },
  { id: 'analyze', label: 'Analyze', Icon: Sparkles },
  { id: 'openings', label: 'Openings', Icon: BookOpen },
  { id: 'train', label: 'Train', Icon: GraduationCap },
  { id: 'insights', label: 'Insights', Icon: BarChart3 },
];

const STARTER_COURSES = starterCoursesData as OpeningCourse[];

const wait = (ms: number) => new Promise<void>((resolve) => window.setTimeout(resolve, ms));

const LEGACY_USERNAME_KEY = 'brillyder_username';

function usernamePrefKey(platform: GamePlatform): string {
  return platform === 'chesscom' ? 'brillyder_username_chesscom' : 'brillyder_username_lichess';
}

function gamePlatformOf(game: LichessGameRecord): GamePlatform {
  if (game.source === 'chesscom') return 'chesscom';
  if (game.source === 'pgn' && game.url?.includes('chess.com')) return 'chesscom';
  return 'lichess';
}

export const App: React.FC = () => {
  const [tab, setTab] = useState<ActiveTab>('games');
  const [platform, setPlatform] = useState<GamePlatform>(() => getPref<GamePlatform>('brillyder_platform', 'lichess'));
  const [usernames, setUsernames] = useState<Record<GamePlatform, string>>(() => ({
    lichess: getPref<string>(usernamePrefKey('lichess'), getPref<string>(LEGACY_USERNAME_KEY, 'Lukedunwell')),
    chesscom: getPref<string>(usernamePrefKey('chesscom'), ''),
  }));
  const [depthPreset, setDepthPreset] = useState<AnalysisDepthPreset>(() => getPref<AnalysisDepthPreset>('brillyder_depth', 14));
  const [gamesByPlatform, setGamesByPlatform] = useState<Record<GamePlatform, LichessGameRecord[]>>({
    lichess: SAMPLE_GAMES,
    chesscom: [],
  });
  const [analyzedMap, setAnalyzedMap] = useState<Map<string, AnalyzedGame>>(() => new Map());
  const [selectedGame, setSelectedGame] = useState<LichessGameRecord | null>(null);
  const [initialJump, setInitialJump] = useState<{ ply: number; nonce: number } | null>(null);
  const [loadingGames, setLoadingGames] = useState(false);
  const [syncError, setSyncError] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ kind: 'info' | 'error'; text: string } | null>(null);
  const [analyzing, setAnalyzing] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number; stageLabel?: string; percent?: number } | null>(null);
  const [batch, setBatch] = useState<BatchState | null>(null);
  const [scout, setScout] = useState<ScoutState | null>(null);
  const [muted, setMuted] = useState<boolean>(() => soundManager.isMuted());
  const [showIosTip, setShowIosTip] = useState(false);
  const [boardTheme, setBoardTheme] = useState<BoardThemeId>(() => getStoredBoardTheme());
  const [celebrationsEnabled, setCelebrationsEnabled] = useState<boolean>(() => getPref('brillyder_celebrations', true));
  const [vibe, setVibe] = useState<VibeMode>(() => getPref<VibeMode>('brillyder_vibe', 'cosmic'));
  const [maiaEnabled, setMaiaEnabled] = useState<boolean>(() => maiaService.isEnabled());
  const [explorerPrefs, setExplorerPrefs] = useState<ExplorerPrefSettings>(() =>
    getPref<ExplorerPrefSettings>('brillyder_explorer_prefs', { ratingBand: 1400, speeds: ['blitz', 'rapid'] })
  );
  const [vaultOpen, setVaultOpen] = useState(false);
  const [gravityCheckOpen, setGravityCheckOpen] = useState(false);
  const [trainSection, setTrainSection] = useState<TrainSection>('daily');
  const [trainMotif, setTrainMotif] = useState<string | null>(null);
  const [trainNavToken, setTrainNavToken] = useState(0);
  const [storageRevision, setStorageRevision] = useState(0);
  const [fsrsCards, setFsrsCards] = useState<FsrsOpeningCard[]>([]);
  const [customRepertoires, setCustomRepertoires] = useState<OpeningCourse[]>([]);
  const [woodpeckerCycles, setWoodpeckerCycles] = useState<WoodpeckerCycleRecord[]>([]);
  const [convertedIds, setConvertedIds] = useState<string[]>([]);

  const hydratedRef = useRef(false);
  const syncRunRef = useRef(0);
  const jumpNonceRef = useRef(0);
  const cancelAnalysisRef = useRef(false);
  const analysisRunRef = useRef(0);
  const batchCancelRef = useRef(false);
  const batchPauseRef = useRef(false);
  const batchRunRef = useRef(0);
  const scoutCancelRef = useRef(false);
  const scoutRunRef = useRef(0);

  const username = usernames[platform];
  const games = gamesByPlatform[platform];

  useEffect(() => {
    const isIos = /iPad|iPhone|iPod/.test(navigator.userAgent);
    const isStandalone =
      window.matchMedia('(display-mode: standalone)').matches ||
      (navigator as unknown as { standalone?: boolean }).standalone === true;
    if (isIos && !isStandalone && !getPref('brillyder_ios_tip_dismissed', false)) {
      setShowIosTip(true);
    }
  }, []);

  useEffect(() => {
    if (!hydratedRef.current) return;
    setPref('brillyder_platform', platform);
    setPref(usernamePrefKey(platform), usernames[platform]);
    setPref(LEGACY_USERNAME_KEY, usernames.lichess);
  }, [platform, usernames]);

  useEffect(() => {
    if (!hydratedRef.current) return;
    storeBoardTheme(boardTheme);
  }, [boardTheme]);

  useEffect(() => {
    if (!hydratedRef.current) return;
    setPref('brillyder_celebrations', celebrationsEnabled);
  }, [celebrationsEnabled]);

  useEffect(() => {
    if (!hydratedRef.current) return;
    setPref('brillyder_vibe', vibe);
  }, [vibe]);

  useEffect(() => {
    if (!hydratedRef.current) return;
    setPref('brillyder_explorer_prefs', explorerPrefs);
  }, [explorerPrefs]);

  const setUsernameFor = useCallback((name: string) => {
    setSyncError(null);
    setUsernames((prev) => ({ ...prev, [platform]: name }));
  }, [platform]);

  const syncGames = useCallback(async (targetPlatform: GamePlatform, userOverride?: string) => {
    const target = (userOverride ?? usernames[targetPlatform]).trim();
    if (!target) {
      setSyncError(`Enter a ${platformLabel(targetPlatform)} username to sync.`);
      return;
    }
    const runId = ++syncRunRef.current;
    setLoadingGames(true);
    setSyncError(null);
    const streamed: LichessGameRecord[] = [];
    try {
      const result = await fetchGamesForPlatform(
        targetPlatform,
        target,
        (g) => {
          if (syncRunRef.current !== runId) return;
          streamed.push(g);
          setGamesByPlatform((prev) => ({ ...prev, [targetPlatform]: [...streamed] }));
        },
        15
      );
      if (syncRunRef.current !== runId) return;
      setGamesByPlatform((prev) => ({ ...prev, [targetPlatform]: result }));
      setSelectedGame((prev) => prev ?? result[0] ?? null);
    } catch (err) {
      if (syncRunRef.current !== runId) return;
      setSyncError(err instanceof Error ? `${err.message} Showing previously loaded games.` : 'Sync failed.');
    } finally {
      if (syncRunRef.current === runId) {
        setLoadingGames(false);
      }
    }
  }, [usernames]);

  const reloadFromIndexedDb = useCallback(async () => {
    await hydrateStorageFromIndexedDb();
    const [cachedGames, cards, reps, cycles, convLog] = await Promise.all([
      getAllAnalyzedGames(),
      getAllFsrsCards(),
      getAllRepertoires(),
      getAllWoodpeckerCycles(),
      getTrainingLog('conversion_completed'),
    ]);
    const map = new Map<string, AnalyzedGame>();
    const refreshed: AnalyzedGame[] = [];
    for (const ag of cachedGames) {
      const next = refreshBrilliantClassifications(ag);
      if (next !== ag) refreshed.push(next);
      map.set(next.id, next);
    }
    setAnalyzedMap(map);
    setFsrsCards(cards);
    setCustomRepertoires(reps);
    setWoodpeckerCycles(cycles);
    const savedIds = Array.isArray(convLog?.data?.ids) ? (convLog.data.ids as string[]) : [];
    setConvertedIds(savedIds);
    setPlatform(getPref<GamePlatform>('brillyder_platform', 'lichess'));
    setUsernames({
      lichess: getPref<string>(usernamePrefKey('lichess'), getPref<string>(LEGACY_USERNAME_KEY, 'Lukedunwell')),
      chesscom: getPref<string>(usernamePrefKey('chesscom'), ''),
    });
    setDepthPreset(getPref<AnalysisDepthPreset>('brillyder_depth', 14));
    setMuted(soundManager.syncFromStorage());
    setVibe(getPref<VibeMode>('brillyder_vibe', 'cosmic'));
    setMaiaEnabled(maiaService.isEnabled());
    setBoardTheme(getStoredBoardTheme());
    setCelebrationsEnabled(getPref('brillyder_celebrations', true));
    setExplorerPrefs(
      getPref<ExplorerPrefSettings>('brillyder_explorer_prefs', { ratingBand: 1400, speeds: ['blitz', 'rapid'] })
    );
    hydratedRef.current = true;
    setStorageRevision((r) => r + 1);
    for (const ag of refreshed) void saveAnalyzedGame(ag);
  }, []);

  useEffect(() => {
    void reloadFromIndexedDb().then(() => {
      const initialPlatform = getPref<GamePlatform>('brillyder_platform', 'lichess');
      const storedName = initialPlatform === 'chesscom'
        ? getPref<string>(usernamePrefKey('chesscom'), '')
        : getPref<string>(usernamePrefKey('lichess'), getPref<string>(LEGACY_USERNAME_KEY, 'Lukedunwell'));
      if (storedName.trim()) void syncGames(initialPlatform, storedName);
    });
    // Boot-time hydration should only run once.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const analyzedGamesList = useMemo(() => Array.from(analyzedMap.values()), [analyzedMap]);
  const vibeCopy = useMemo(() => getVibeCopy(vibe), [vibe]);
  const dueOpeningCount = useMemo(() => fsrsCards.filter((c) => isCardDue(c)).length, [fsrsCards]);

  const allCourses = useMemo<OpeningCourse[]>(() => {
    const customById = new Map<string, OpeningCourse>();
    for (const c of customRepertoires) customById.set(c.id, c);
    const merged: OpeningCourse[] = STARTER_COURSES.map((s) => customById.get(s.id) ?? s);
    for (const c of customRepertoires) {
      if (!STARTER_COURSES.some((s) => s.id === c.id)) merged.push(c);
    }
    return merged;
  }, [customRepertoires]);

  const upsertFsrsCards = useCallback(async (incoming: FsrsOpeningCard[]) => {
    if (incoming.length === 0) return;
    await saveFsrsCardsBulk(incoming);
    setFsrsCards((prev) => {
      const map = new Map(prev.map((c) => [c.cardId, c]));
      for (const c of incoming) map.set(c.cardId, c);
      return Array.from(map.values());
    });
  }, []);

  const handleCardReviewed = useCallback(async (updated: FsrsOpeningCard) => {
    await saveFsrsCard(updated);
    setFsrsCards((prev) => {
      const idx = prev.findIndex((c) => c.cardId === updated.cardId);
      if (idx === -1) return [...prev, updated];
      const next = [...prev];
      next[idx] = updated;
      return next;
    });
  }, []);

  const modifiedStarterIds = useMemo(() => {
    const starterIds = new Set(STARTER_COURSES.map((s) => s.id));
    return new Set(customRepertoires.filter((c) => starterIds.has(c.id)).map((c) => c.id));
  }, [customRepertoires]);

  const handleSaveCourse = useCallback(async (course: OpeningCourse, newCards?: FsrsOpeningCard[], replacedLineId?: string) => {
    await saveRepertoire(course);
    setCustomRepertoires((prev) => {
      const idx = prev.findIndex((c) => c.id === course.id);
      if (idx === -1) return [...prev, course];
      const next = [...prev];
      next[idx] = course;
      return next;
    });
    if (replacedLineId) {
      await deleteFsrsCardsByLine(course.id, replacedLineId);
      setFsrsCards((prev) => prev.filter((c) => !(c.courseId === course.id && c.lineId === replacedLineId)));
    }
    if (newCards && newCards.length > 0) {
      await upsertFsrsCards(newCards);
    }
  }, [upsertFsrsCards]);

  const handleDeleteCourse = useCallback(async (courseId: string) => {
    await deleteRepertoire(courseId);
    setCustomRepertoires((prev) => prev.filter((c) => c.id !== courseId));
    setFsrsCards((prev) => prev.filter((c) => c.courseId !== courseId));
  }, []);

  const handleDeleteLine = useCallback(async (course: OpeningCourse, lineId: string) => {
    const updated = removeLineFromCourse(course, lineId);
    if (updated === course) return;
    await saveRepertoire(updated);
    await deleteFsrsCardsByLine(course.id, lineId);
    setCustomRepertoires((prev) => {
      const idx = prev.findIndex((c) => c.id === updated.id);
      if (idx === -1) return [...prev, updated];
      const next = [...prev];
      next[idx] = updated;
      return next;
    });
    setFsrsCards((prev) => prev.filter((c) => !(c.courseId === course.id && c.lineId === lineId)));
  }, []);

  const handleBoostDeviationToFsrs = useCallback(async (deviation: RepertoireDeviation) => {
    const target = deviation.expectedMoves[0];
    if (!target) return;
    const existing = fsrsCards.find((c) => c.cardId === target.cardId);
    const base = existing ?? createFsrsOpeningCard({
      courseId: target.courseId,
      lineId: target.lineId,
      side: deviation.color === 'w' ? 'white' : 'black',
      fen: deviation.beforeFen,
      ply: target.ply,
      moveSequence: target.moveSequence,
      expectedSan: target.expectedSan,
      expectedUci: target.expectedUci,
      source: 'game-deviation',
      unlocked: true,
    });
    const boosted = boostCardToDueNow(base);
    await handleCardReviewed(boosted);
    setNotice({
      kind: 'info',
      text: `Boosted ${target.expectedSan} (${target.courseName}) directly to today’s FSRS review queue.`,
    });
  }, [fsrsCards, handleCardReviewed]);

  const handlePatchDeviationGap = useCallback(async (deviation: RepertoireDeviation) => {
    if (!deviation.recommendedReplySan) return;
    const course = allCourses.find((c) => c.id === deviation.courseId);
    if (!course) return;
    const { updatedCourse, newCards } = addPatchedLineToCourse(
      course,
      deviation.moveSequenceAfter,
      deviation.recommendedReplySan,
      { planNote: `Patched from analyzed game novelty ${deviation.playedSan} with Stockfish reply ${deviation.recommendedReplySan}.` }
    );
    await handleSaveCourse(updatedCourse, newCards);
    setNotice({
      kind: 'info',
      text: `Patched ${deviation.recommendedReplySan} vs ${deviation.playedSan} into ${course.name} & added to FSRS.`,
    });
  }, [allCourses, handleSaveCourse]);

  const mistakeDeck = useMemo(
    () => buildMistakeDeck(analyzedGamesList, usernames),
    [analyzedGamesList, usernames]
  );

  const handleSaveWoodpeckerCycle = useCallback(async (cycle: WoodpeckerCycleRecord) => {
    await saveWoodpeckerCycle(cycle);
    setWoodpeckerCycles((prev) => {
      const others = prev.filter((c) => c.id !== cycle.id);
      return [cycle, ...others].sort((a, b) => b.createdAt - a.createdAt);
    });
  }, []);

  const handleMarkConverted = useCallback(async (positionId: string) => {
    const next = Array.from(new Set([...convertedIds, positionId]));
    setConvertedIds(next);
    await saveTrainingLog({
      id: 'conversion_completed',
      kind: 'conversion',
      updatedAt: Date.now(),
      data: { ids: next },
    });
  }, [convertedIds]);

  const handleUnlockAllStarterCards = useCallback(async () => {
    const cardMap = new Map(fsrsCards.map((c) => [c.cardId, c]));
    const batch: FsrsOpeningCard[] = [];
    for (const course of allCourses) {
      for (const c of hydrateCourseCards(course, cardMap, { unlocked: true })) {
        batch.push({ ...c, unlocked: true });
      }
    }
    await upsertFsrsCards(batch);
  }, [allCourses, fsrsCards, upsertFsrsCards]);

  const handleDailySessionComplete = useCallback(async (summary: { duration: DailyDurationMinutes; completedItems: number }) => {
    const day = new Date().toISOString().slice(0, 10);
    await saveTrainingLog({
      id: `daily_${day}`,
      kind: 'daily-session',
      updatedAt: Date.now(),
      data: summary,
    });
    setNotice({
      kind: 'info',
      text: `Daily Coach (${summary.duration}m) complete — ${summary.completedItems} training positions logged!`,
    });
  }, []);

  const openTrainerFocus = useCallback((section: TrainSection = 'daily', motif?: string | null) => {
    setTrainSection(section);
    setTrainMotif(motif ?? null);
    setTrainNavToken((n) => n + 1);
    setTab('train');
  }, []);

  const handleSelectNavTab = useCallback((nextTab: ActiveTab) => {
    if (nextTab === 'train') setTrainMotif(null);
    setTab(nextTab);
  }, []);

  const closeVault = useCallback(() => setVaultOpen(false), []);
  const closeGravityCheck = useCallback(() => setGravityCheckOpen(false), []);

  const handleBackupImported = useCallback((summary: BackupImportSummary) => {
    void reloadFromIndexedDb();
    setNotice({
      kind: 'info',
      text: `Backup restored — ${summary.analyzedGames} games, ${summary.repertoires} courses, ${summary.fsrsCards} FSRS cards loaded.`,
    });
  }, [reloadFromIndexedDb]);

  const vault = useMemo(
    () => buildBrillyVault(analyzedGamesList, usernames),
    [analyzedGamesList, usernames]
  );

  const addAnalyzedGame = useCallback((analyzed: AnalyzedGame) => {
    setAnalyzedMap((prev) => {
      const next = new Map(prev);
      next.set(analyzed.id, analyzed);
      return next;
    });
  }, []);

  const abortBatch = useCallback(() => {
    batchRunRef.current += 1;
    batchCancelRef.current = true;
    batchPauseRef.current = false;
    setBatch(null);
    void stockfishService.cancelCurrent();
  }, []);

  const abortScout = useCallback(() => {
    scoutRunRef.current += 1;
    scoutCancelRef.current = true;
    setScout(null);
    void stockfishService.cancelCurrent();
  }, []);

  const runSingleAnalysis = useCallback(async (targetGame: LichessGameRecord, depth: AnalysisDepthPreset) => {
    abortBatch();
    abortScout();
    cancelAnalysisRef.current = false;
    const runId = analysisRunRef.current + 1;
    analysisRunRef.current = runId;
    const isStale = () => analysisRunRef.current !== runId || cancelAnalysisRef.current;
    setNotice(null);
    await stockfishService.cancelCurrent();
    if (isStale()) return;
    setAnalyzing(true);
    setProgress(null);
    let maxPct = 2;
    try {
      const analyzed = await analyzeGameToReview(targetGame, depth, {
        persist: true,
        shouldCancel: isStale,
        onProgress: (done, total, stageLabel, meta) => {
          if (isStale()) return;
          const frac = meta?.gameFraction ?? (total > 0 ? done / total : 0);
          maxPct = computeSingleGamePercent(frac, maxPct, true);
          setProgress({ done, total, stageLabel, percent: maxPct });
        },
      });
      if (isStale()) return;
      addAnalyzedGame(analyzed);
      setNotice({
        kind: 'info',
        text: `Review ready — ${analyzed.whiteSummary.counts.brilliant + analyzed.blackSummary.counts.brilliant} brilliant move(s) and ${analyzed.whiteSummary.counts.blunder + analyzed.blackSummary.counts.blunder} blunder(s) found.`,
      });
    } catch (err) {
      if (err instanceof AnalysisCancelledError || isStale()) return;
      setNotice({ kind: 'error', text: err instanceof Error ? err.message : 'Stockfish analysis failed.' });
    } finally {
      if (analysisRunRef.current === runId) {
        setAnalyzing(false);
        setProgress(null);
      }
    }
  }, [abortBatch, abortScout, addAnalyzedGame]);

  const cancelAnalysis = useCallback(() => {
    analysisRunRef.current += 1;
    cancelAnalysisRef.current = true;
    void stockfishService.cancelCurrent();
    setAnalyzing(false);
    setProgress(null);
  }, []);

  const runBatchAnalysis = useCallback(async () => {
    if (analyzing) {
      setNotice({ kind: 'error', text: 'A single-game review is running. Stop it before starting a batch.' });
      return;
    }
    abortScout();
    await stockfishService.cancelCurrent();
    const queue = games
      .filter((g) => g.variant === 'standard' && !analyzedMap.has(g.id))
      .slice(0, 5);
    if (queue.length === 0) {
      setNotice({ kind: 'info', text: 'All loaded games are already analyzed.' });
      return;
    }

    const runId = batchRunRef.current + 1;
    batchRunRef.current = runId;
    batchCancelRef.current = false;
    batchPauseRef.current = false;
    const isStale = () => batchRunRef.current !== runId || batchCancelRef.current;
    const waitIfPaused = async () => {
      while (batchPauseRef.current && !isStale()) await wait(160);
    };
    setNotice(null);
    let maxBatchPct = 2;
    setBatch({
      active: true,
      paused: false,
      total: queue.length,
      done: 0,
      currentLabel: 'Preparing engine…',
      stageLabel: 'Starting Stockfish WASM…',
      percent: maxBatchPct,
    });

    let completed = 0;
    let failed = 0;

    for (let i = 0; i < queue.length; i++) {
      await waitIfPaused();
      if (isStale()) return;

      const game = queue[i];
      setBatch((prev) =>
        !isStale() && prev
          ? {
              ...prev,
              currentLabel: `${game.white.name} vs ${game.black.name}`,
              stageLabel: 'Loading game positions…',
              plyDone: 0,
              plyTotal: undefined,
            }
          : prev
      );
      try {
        const analyzed = await analyzeGameToReview(game, depthPreset, {
          persist: true,
          shouldCancel: isStale,
          waitIfPaused,
          onProgress: (done, total, stageLabel, meta) => {
            if (isStale()) return;
            const gameFraction = meta?.gameFraction ?? (total > 0 ? done / total : 0);
            maxBatchPct = computeBatchProgressPercent(i, queue.length, gameFraction, maxBatchPct, true);
            setBatch((prev) =>
              !isStale() && prev
                ? {
                    ...prev,
                    stageLabel: meta?.shortStage ?? stageLabel,
                    plyDone: done,
                    plyTotal: total,
                    percent: maxBatchPct,
                  }
                : prev
            );
          },
        });
        if (isStale()) return;
        addAnalyzedGame(analyzed);
        completed++;
      } catch (err) {
        if (err instanceof AnalysisCancelledError || isStale()) return;
        failed++;
      }
      const nextDone = i + 1;
      maxBatchPct = computeBatchProgressPercent(
        nextDone,
        queue.length,
        0,
        maxBatchPct,
        nextDone < queue.length
      );
      setBatch((prev) =>
        !isStale() && prev
          ? {
              ...prev,
              done: nextDone,
              plyDone: undefined,
              plyTotal: undefined,
              percent: maxBatchPct,
            }
          : prev
      );
    }

    if (isStale()) return;
    batchCancelRef.current = false;
    batchPauseRef.current = false;
    setBatch((prev) => (prev ? { ...prev, active: false, paused: false, currentLabel: '', percent: 100 } : prev));
    window.setTimeout(() => setBatch((prev) => (prev && !prev.active ? null : prev)), 900);

    setNotice({
      kind: failed > 0 ? 'error' : 'info',
      text:
        failed > 0
          ? `Batch finished — ${completed} analyzed, ${failed} failed. Check the games above.`
          : `Batch complete — ${completed} game${completed === 1 ? '' : 's'} analyzed and saved on-device.`,
    });
  }, [abortScout, addAnalyzedGame, analyzedMap, analyzing, depthPreset, games]);

  const toggleBatchPause = useCallback(() => {
    const next = !(batch?.paused ?? false);
    batchPauseRef.current = next;
    setBatch((prev) => (prev ? { ...prev, paused: next } : prev));
  }, [batch?.paused]);

  const cancelBatch = useCallback(() => {
    batchRunRef.current += 1;
    batchCancelRef.current = true;
    batchPauseRef.current = false;
    setBatch(null);
    void stockfishService.cancelCurrent();
  }, []);

  const runScout = useCallback(async (name: string) => {
    const target = name.trim();
    if (!target) return;
    if (analyzing) {
      setNotice({ kind: 'error', text: 'Finish the current single-game review before scouting.' });
      return;
    }
    abortBatch();
    await stockfishService.cancelCurrent();
    scoutCancelRef.current = false;
    const runId = scoutRunRef.current + 1;
    scoutRunRef.current = runId;
    const isStale = () => scoutRunRef.current !== runId || scoutCancelRef.current;
    setNotice(null);
    setScout({
      username: target,
      platform,
      status: 'loading',
      games: [],
      progress: null,
      error: null,
    });

    try {
      const fetched = await fetchGamesForPlatform(platform, target, undefined, 8);
      if (isStale()) return;
      const candidates = fetched.filter((g) => g.variant === 'standard').slice(0, 3);
      if (candidates.length === 0) {
        throw new Error(`No standard ${platformLabel(platform)} games found for "${target}" to scout.`);
      }
      const analyzed: AnalyzedGame[] = [];
      let maxScoutPct = 4;
      for (let i = 0; i < candidates.length; i++) {
        if (isStale()) return;
        maxScoutPct = computeBatchProgressPercent(i, candidates.length, 0, maxScoutPct, true);
        setScout((prev) =>
          prev ? { ...prev, progress: { done: i, total: candidates.length, percent: maxScoutPct } } : prev
        );
        const result = await analyzeGameToReview(candidates[i], 10, {
          persist: false,
          shouldCancel: isStale,
          onProgress: (done, total, _stage, meta) => {
            if (isStale()) return;
            const frac = meta?.gameFraction ?? (total > 0 ? done / total : 0);
            maxScoutPct = computeBatchProgressPercent(i, candidates.length, frac, maxScoutPct, true);
            setScout((prev) =>
              prev
                ? {
                    ...prev,
                    progress: {
                      done: i,
                      total: candidates.length,
                      percent: maxScoutPct,
                      plyDone: done,
                      plyTotal: total,
                    },
                  }
                : prev
            );
          },
        });
        if (isStale()) return;
        analyzed.push(result);
        const nextDone = i + 1;
        maxScoutPct = computeBatchProgressPercent(
          nextDone,
          candidates.length,
          0,
          maxScoutPct,
          nextDone < candidates.length
        );
        setScout((prev) =>
          prev
            ? { ...prev, games: [...analyzed], progress: { done: nextDone, total: candidates.length, percent: maxScoutPct } }
            : prev
        );
      }
      if (isStale()) return;
      setScout((prev) => (prev ? { ...prev, status: 'ready' } : prev));
    } catch (err) {
      if (err instanceof AnalysisCancelledError || isStale()) return;
      setScout((prev) => (prev ? { ...prev, status: 'error', error: err instanceof Error ? err.message : 'Scouting failed.' } : prev));
    }
  }, [abortBatch, analyzing, platform]);

  const cancelScout = useCallback(() => {
    scoutRunRef.current += 1;
    scoutCancelRef.current = true;
    setScout(null);
    void stockfishService.cancelCurrent();
  }, []);

  const handlePlatformChange = useCallback((next: GamePlatform) => {
    if (next === platform) return;
    setPlatform(next);
    setSyncError(null);
    abortScout();
    abortBatch();
  }, [abortBatch, abortScout, platform]);

  const handleSelectGame = useCallback((game: LichessGameRecord, autoAnalyze: boolean) => {
    soundManager.unlock();
    if (analyzing && selectedGame?.id !== game.id) cancelAnalysis();
    setSelectedGame(game);
    setInitialJump(null);
    setTab('analyze');
    if (autoAnalyze && !analyzedMap.has(game.id)) void runSingleAnalysis(game, depthPreset);
  }, [analyzedMap, analyzing, cancelAnalysis, depthPreset, runSingleAnalysis, selectedGame?.id]);

  const handleImportInput = useCallback(async (input: string) => {
    const game = extractLichessGameId(input)
      ? await fetchLichessGameByUrlOrId(input, username)
      : parseRawPgnToGame(input, username);
    const targetPlatform = gamePlatformOf(game);
    setGamesByPlatform((prev) => ({
      ...prev,
      [targetPlatform]: [game, ...prev[targetPlatform].filter((g) => g.id !== game.id)],
    }));
    if (targetPlatform !== platform) setPlatform(targetPlatform);
    handleSelectGame(game, true);
  }, [handleSelectGame, platform, username]);

  const openReviewedPly = useCallback((gameId: string, ply: number) => {
    const localAnalyzed = analyzedMap.get(gameId);
    const scoutAnalyzed = !localAnalyzed ? scout?.games.find((g) => g.id === gameId) : undefined;
    const analyzed = localAnalyzed ?? scoutAnalyzed;
    if (!analyzed) {
      setNotice({ kind: 'error', text: 'Analyze that game first so the exact moment is available.' });
      return;
    }
    if (analyzing && selectedGame?.id !== analyzed.game.id) {
      cancelAnalysis();
    }
    if (localAnalyzed) {
      const targetPlatform = gamePlatformOf(analyzed.game);
      setPlatform(targetPlatform);
      setGamesByPlatform((prev) =>
        prev[targetPlatform].some((g) => g.id === analyzed.game.id)
          ? prev
          : { ...prev, [targetPlatform]: [analyzed.game, ...prev[targetPlatform]] }
      );
    }
    jumpNonceRef.current += 1;
    setSelectedGame(analyzed.game);
    setInitialJump({ ply, nonce: jumpNonceRef.current });
    setTab('analyze');
  }, [analyzedMap, analyzing, cancelAnalysis, scout?.games, selectedGame?.id]);

  const handleDepthChange = useCallback((depth: AnalysisDepthPreset) => {
    setDepthPreset(depth);
    setPref('brillyder_depth', depth);
  }, []);

  const toggleSound = () => {
    const next = !muted;
    soundManager.setMuted(next);
    setMuted(next);
  };

  return (
    <VibeProvider vibe={vibe} setVibe={setVibe}>
      <div className="min-h-screen text-slate-100">
        <header className="sticky top-0 z-40 border-b border-slate-800/70 bg-void/[0.90] pt-[env(safe-area-inset-top)] backdrop-blur-xl">
          <div className="mx-auto flex w-full max-w-lg items-center gap-1.5 px-3 py-2.5 sm:gap-2 sm:px-4 md:max-w-3xl lg:max-w-7xl lg:px-6">
            <button
              type="button"
              onClick={() => setTab('games')}
              className="flex min-w-0 items-center gap-2 text-left"
              aria-label="BrillyDer home"
            >
              <img src="./icon.svg" alt="" className="h-7 w-7 rounded-lg shadow-lg shadow-teal-500/15 sm:h-8 sm:w-8" />
              <span className="min-w-0">
                <span className="flex items-center gap-1.5 text-sm font-black leading-none tracking-tight sm:text-base">
                  <span>
                    <span className="text-brilly">Brilly</span>
                    <span className="text-blunder">Der</span>
                  </span>
                  <span className="hidden rounded bg-cockpit px-1.5 py-0.5 font-mono text-[9px] font-bold text-slate-300 sm:inline">v2</span>
                </span>
                <span className="mt-0.5 hidden text-[10px] leading-tight text-slate-400 sm:block">{vibeCopy.appSubtitle}</span>
              </span>
            </button>

            <nav className="mx-auto hidden items-center gap-0.5 rounded-xl border border-slate-800/80 bg-hull/70 p-0.5 lg:flex">
              {NAV_ITEMS.map(({ id, label, Icon }) => (
                <button
                  key={id}
                  type="button"
                  onClick={() => handleSelectNavTab(id)}
                  aria-current={tab === id ? 'page' : undefined}
                  className={`inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-[11px] font-bold transition lg:px-3 ${
                    tab === id
                      ? 'bg-teal-400/15 text-teal-200 shadow-sm'
                      : 'text-slate-400 hover:bg-slate-800/60 hover:text-slate-200'
                  }`}
                >
                  <Icon className="h-3.5 w-3.5" />
                  {label}
                  {id === 'openings' && dueOpeningCount > 0 && (
                    <span className="rounded-full bg-purple-500/25 px-1.5 py-0.5 font-mono text-[9px] text-purple-200">
                      {dueOpeningCount}
                    </span>
                  )}
                </button>
              ))}
            </nav>

            <div className="ml-auto flex items-center gap-1.5 lg:ml-0">
              <button
                type="button"
                onClick={() => setVaultOpen(true)}
                className="inline-flex items-center gap-1 rounded-xl border border-teal-400/35 bg-teal-400/10 px-2 py-1.5 text-teal-200 transition hover:border-teal-300/60 hover:bg-teal-400/20"
                aria-label={`Open Brilly Vault: ${vault.stats.userMoves} brilliant move${vault.stats.userMoves === 1 ? '' : 's'}`}
                title="Open Brilly Vault modal"
              >
                <Gem className="h-3.5 w-3.5 text-brilly" />
                <span className="font-mono text-xs font-black tabular-nums">{vault.stats.userMoves}</span>
                <span className="hidden text-[10px] font-bold sm:inline">Vault</span>
              </button>

              <SettingsMenu
                theme={boardTheme}
                onThemeChange={setBoardTheme}
                celebrationsEnabled={celebrationsEnabled}
                onToggleCelebrations={() => setCelebrationsEnabled((v) => !v)}
                vibe={vibe}
                onVibeChange={setVibe}
                maiaEnabled={maiaEnabled}
                onToggleMaia={() => {
                  const next = !maiaEnabled;
                  maiaService.setEnabled(next);
                  setMaiaEnabled(next);
                }}
                explorerPrefs={explorerPrefs}
                onExplorerPrefsChange={setExplorerPrefs}
                onBackupImported={handleBackupImported}
              />

              <button
                type="button"
                onClick={toggleSound}
                className="rounded-xl border border-slate-800 bg-hull/90 p-2 text-slate-300 transition hover:border-slate-600"
                aria-label={muted ? 'Unmute sounds' : 'Mute sounds'}
              >
                {muted ? <VolumeX className="h-4 w-4 text-slate-500" /> : <Volume2 className="h-4 w-4 text-brilly" />}
              </button>
            </div>
          </div>
        </header>

      <main className="mx-auto w-full max-w-lg px-3 pt-3 sm:px-4 md:max-w-3xl lg:max-w-7xl lg:px-6 lg:pt-4">
        {showIosTip && (
          <div className="mb-3 flex items-center justify-between gap-2 rounded-2xl border border-cyan-500/30 bg-cyan-500/10 p-3 text-xs text-cyan-100">
            <span>
              Install on iPhone: tap <strong>Share</strong> → <strong>Add to Home Screen</strong> for full-screen native play.
            </span>
            <button
              type="button"
              onClick={() => {
                setShowIosTip(false);
                setPref('brillyder_ios_tip_dismissed', true);
              }}
              className="shrink-0 rounded bg-slate-900 px-2 py-1 text-slate-300"
            >
              Got it
            </button>
          </div>
        )}

        {notice && (
          <div
            className={`mb-3 flex items-start gap-2 rounded-2xl border px-3 py-2 text-xs ${
              notice.kind === 'error'
                ? 'border-rose-500/30 bg-rose-500/10 text-rose-200'
                : 'border-cyan-500/30 bg-cyan-500/10 text-cyan-100'
            }`}
          >
            <span className="flex-1 leading-relaxed">{notice.text}</span>
            <button type="button" onClick={() => setNotice(null)} aria-label="Dismiss message" className="shrink-0 opacity-70 hover:opacity-100">
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        )}

        {batch?.active && tab !== 'games' && (
          <div className="mb-3 glass-card overflow-hidden border-teal-400/30 px-3 py-2">
            <div className="flex items-center justify-between gap-2 text-[11px]">
              <button
                type="button"
                onClick={() => setTab('games')}
                className="flex min-w-0 flex-1 items-center gap-2 text-left"
              >
                {batch.paused ? (
                  <Pause className="h-3.5 w-3.5 shrink-0 text-amber-300" />
                ) : (
                  <span className="radar-sweep h-3.5 w-3.5 shrink-0" aria-hidden="true" />
                )}
                <span className="truncate font-semibold text-teal-200">
                  {batch.paused ? 'Batch paused' : `Batch ${Math.min(batch.done + 1, batch.total)}/${batch.total}`}
                  {batch.currentLabel ? ` · ${batch.currentLabel}` : ''}
                </span>
              </button>
              <div className="flex shrink-0 items-center gap-1.5">
                <span className="font-mono text-[11px] font-bold tabular-nums text-brilly">{batch.percent}%</span>
                <button
                  type="button"
                  onClick={toggleBatchPause}
                  aria-label={batch.paused ? 'Resume batch analysis' : 'Pause batch analysis'}
                  className="rounded-lg border border-amber-500/35 bg-amber-500/15 p-1 text-amber-200"
                >
                  {batch.paused ? <Play className="h-3 w-3" /> : <Pause className="h-3 w-3" />}
                </button>
                <button
                  type="button"
                  onClick={cancelBatch}
                  aria-label="Cancel batch analysis"
                  className="rounded-lg border border-red-500/35 bg-red-500/15 p-1 text-red-300"
                >
                  <X className="h-3 w-3" />
                </button>
              </div>
            </div>
            <div
              className="mt-1.5 tractor-beam-track h-1.5 w-full"
              role="progressbar"
              aria-label="Batch analysis progress"
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={batch.percent}
            >
              <div
                className={`tractor-beam-fill ${batch.paused ? 'opacity-60' : ''}`}
                style={{ width: `${Math.max(2, Math.min(100, batch.percent))}%` }}
              />
            </div>
          </div>
        )}

        {scout?.status === 'loading' && tab !== 'insights' && (() => {
          const pct = Math.max(4, Math.min(100, scout.progress?.percent ?? 4));
          return (
            <div className="mb-3 glass-card overflow-hidden border-fuchsia-400/30 px-3 py-2">
              <div className="flex items-center justify-between gap-2 text-[11px]">
                <button
                  type="button"
                  onClick={() => setTab('insights')}
                  className="flex min-w-0 flex-1 items-center gap-2 text-left"
                >
                  <span className="radar-sweep h-3.5 w-3.5 shrink-0" aria-hidden="true" />
                  <span className="truncate font-semibold text-fuchsia-200">
                    Scouting {scout.username}
                    {scout.progress ? ` · game ${Math.min(scout.progress.done + 1, scout.progress.total)}/${scout.progress.total}` : '…'}
                  </span>
                </button>
                <div className="flex shrink-0 items-center gap-1.5">
                  <span className="font-mono text-[11px] font-bold tabular-nums text-fuchsia-200">{pct}%</span>
                  <button
                    type="button"
                    onClick={cancelScout}
                    aria-label="Cancel opponent scout"
                    className="rounded-lg border border-red-500/35 bg-red-500/15 p-1 text-red-300"
                  >
                    <X className="h-3 w-3" />
                  </button>
                </div>
              </div>
              <div
                className="mt-1.5 tractor-beam-track h-1.5 w-full"
                role="progressbar"
                aria-label="Opponent scouting progress"
                aria-valuemin={0}
                aria-valuemax={100}
                aria-valuenow={pct}
              >
                <div className="tractor-beam-fill" style={{ width: `${pct}%` }} />
              </div>
            </div>
          );
        })()}

        {tab === 'games' && (
          <GameListView
            username={username}
            platform={platform}
            games={games}
            analyzedMap={analyzedMap}
            loading={loadingGames}
            error={syncError}
            batch={batch}
            onPlatformChange={handlePlatformChange}
            onUsernameChange={setUsernameFor}
            onSync={(u) => void syncGames(platform, u)}
            onSelectGame={handleSelectGame}
            onImportInput={handleImportInput}
            onBatchAnalyze={() => void runBatchAnalysis()}
            onBatchPauseToggle={toggleBatchPause}
            onBatchCancel={cancelBatch}
          />
        )}

        {tab === 'analyze' && (
          selectedGame ? (() => {
            const localAnalyzed = analyzedMap.get(selectedGame.id) ?? null;
            const scoutAnalyzed = !localAnalyzed ? scout?.games.find((g) => g.id === selectedGame.id) ?? null : null;
            const effectiveUsername = !localAnalyzed && scoutAnalyzed && scout ? scout.username : usernames;
            return (
              <Suspense fallback={<TabLoadingCard />}>
                <AnalysisView
                  game={selectedGame}
                  username={effectiveUsername}
                  analyzed={localAnalyzed ?? scoutAnalyzed}
                  analyzing={analyzing}
                  progress={progress}
                  depthPreset={depthPreset}
                  onDepthPresetChange={handleDepthChange}
                  onStartAnalysis={() => void runSingleAnalysis(selectedGame, depthPreset)}
                  onCancelAnalysis={cancelAnalysis}
                  onBackToGames={() => setTab('games')}
                  onOpenInsights={() => setTab('insights')}
                  onOpenVault={() => setVaultOpen(true)}
                  initialJump={initialJump}
                  boardTheme={boardTheme}
                  celebrationsEnabled={celebrationsEnabled}
                  courses={allCourses}
                  explorerPrefs={explorerPrefs}
                  onBoostDeviationToFsrs={handleBoostDeviationToFsrs}
                  onPatchDeviationGap={handlePatchDeviationGap}
                />
              </Suspense>
            );
          })() : (
            <div className="glass-card mx-auto max-w-lg p-8 text-center">
              <Sparkles className="mx-auto h-9 w-9 text-cyan-300/70" />
              <h1 className="mt-2 text-base font-extrabold text-white">No game selected</h1>
              <p className="mx-auto mt-1 max-w-sm text-xs leading-relaxed text-slate-400">
                Pick a game from Games — or open a Brilliant from the Vault — to launch the analysis cockpit.
              </p>
              <button
                type="button"
                onClick={() => setTab('games')}
                className="mt-3 inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-cyan-400 to-emerald-400 px-3.5 py-2 text-xs font-extrabold text-slate-950"
              >
                <ListChecks className="h-3.5 w-3.5" /> Browse games
              </button>
            </div>
          )
        )}

        {tab === 'openings' && (
          <Suspense fallback={<TabLoadingCard />}>
            <OpeningsView
              courses={allCourses}
              modifiedStarterIds={modifiedStarterIds}
              fsrsCards={fsrsCards}
              analyzedGames={analyzedGamesList}
              username={usernames}
              boardTheme={boardTheme}
              explorerPrefs={explorerPrefs}
              onSaveCourse={handleSaveCourse}
              onDeleteCourse={handleDeleteCourse}
              onDeleteLine={handleDeleteLine}
              onUnlockCards={upsertFsrsCards}
              onCardReviewed={handleCardReviewed}
              onOpenGame={openReviewedPly}
            />
          </Suspense>
        )}

        {tab === 'train' && (
          <Suspense fallback={<TabLoadingCard />}>
            <MistakeTrainerView
              analyzedGames={analyzedGamesList}
              username={usernames}
              boardTheme={boardTheme}
              courses={allCourses}
              fsrsCards={fsrsCards}
              woodpeckerCycles={woodpeckerCycles}
              convertedIds={convertedIds}
              initialSection={trainSection}
              initialMotifFilter={trainMotif}
              navToken={trainNavToken}
              storageRevision={storageRevision}
              onCardReviewed={handleCardReviewed}
              onSaveWoodpeckerCycle={handleSaveWoodpeckerCycle}
              onMarkConverted={handleMarkConverted}
              onUnlockStarterCards={handleUnlockAllStarterCards}
              onOpenGravityCheck={() => setGravityCheckOpen(true)}
              onDailySessionComplete={handleDailySessionComplete}
              onOpenGame={openReviewedPly}
              onOpenGames={() => setTab('games')}
            />
          </Suspense>
        )}

        {tab === 'insights' && (
          <Suspense fallback={<TabLoadingCard />}>
            <InsightsView
              analyzedGames={analyzedGamesList}
              username={username}
              userHandles={usernames}
              platform={platform}
              scout={scout}
              onPlatformChange={handlePlatformChange}
              onScout={(name) => void runScout(name)}
              onCancelScout={cancelScout}
              onClearScout={() => setScout(null)}
              onOpenGames={() => setTab('games')}
              onOpenOpenings={() => setTab('openings')}
              onOpenGravityCheck={() => setGravityCheckOpen(true)}
              onOpenTrainer={(section, motif) => openTrainerFocus(section ?? 'daily', motif)}
              onOpenGame={(gameId, ply) => openReviewedPly(gameId, ply)}
            />
          </Suspense>
        )}
      </main>

        {(tab !== 'analyze' || !selectedGame) && (
          <nav className="fixed bottom-0 left-0 right-0 z-40 border-t border-white/10 bg-void/[0.95] px-2 pt-1.5 pb-[max(0.5rem,env(safe-area-inset-bottom))] backdrop-blur-xl lg:hidden">
            <div className="mx-auto grid max-w-lg grid-cols-5 gap-1">
              {NAV_ITEMS.map(({ id, label, Icon }) => (
                <button
                  key={id}
                  type="button"
                  onClick={() => handleSelectNavTab(id)}
                  aria-current={tab === id ? 'page' : undefined}
                  className={`relative flex flex-col items-center rounded-xl py-1.5 text-[9px] font-bold transition ${
                    tab === id ? 'bg-teal-400/12 text-brilly' : 'text-slate-400 active:bg-slate-800/50'
                  }`}
                >
                  <Icon className="mb-0.5 h-[18px] w-[18px]" />
                  {label}
                  {id === 'openings' && dueOpeningCount > 0 && (
                    <span className="absolute right-2 top-1 h-2 w-2 rounded-full bg-warp" />
                  )}
                </button>
              ))}
            </div>
          </nav>
        )}

        {vaultOpen && (
          <Suspense fallback={null}>
            <BrillyVaultModal
              open={vaultOpen}
              onClose={closeVault}
              entries={vault.entries}
              stats={vault.stats}
              username={username}
              boardTheme={boardTheme}
              onOpenEntry={(entry) => openReviewedPly(entry.gameId, entry.ply)}
              onOpenGames={() => setTab('games')}
            />
          </Suspense>
        )}

        {gravityCheckOpen && (
          <Suspense fallback={null}>
            <GravityCheckModal
              open={gravityCheckOpen}
              onClose={closeGravityCheck}
              deck={mistakeDeck}
              fsrsCards={fsrsCards}
              courses={allCourses}
              boardTheme={boardTheme}
              onCardReviewed={handleCardReviewed}
              onCompleted={(summary) => {
                void saveTrainingLog({
                  id: `gravity_${Date.now()}`,
                  kind: 'gravity-check',
                  updatedAt: Date.now(),
                  data: summary,
                });
              }}
            />
          </Suspense>
        )}
      </div>
    </VibeProvider>
  );
};

export default App;
