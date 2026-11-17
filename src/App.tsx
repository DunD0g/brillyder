import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  BarChart3,
  Gem,
  GraduationCap,
  ListChecks,
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
import { getStoredBoardTheme, storeBoardTheme } from './chess/boardThemes';
import { analyzeGameToReview, AnalysisCancelledError } from './services/analysisRunner';
import { fetchGamesForPlatform, platformLabel } from './services/gameSource';
import { buildBrillyVault } from './services/vault';
import {
  extractLichessGameId,
  fetchLichessGameByUrlOrId,
  parseRawPgnToGame,
  SAMPLE_GAMES,
} from './services/lichessApi';
import { getAllAnalyzedGames, getPref, setPref } from './storage/gameDb';
import { stockfishService } from './engine/StockfishService';
import { soundManager } from './utils/sound';
import { AnalysisView } from './components/AnalysisView';
import { GameListView, type BatchState } from './components/GameListView';
import { InsightsView } from './components/InsightsView';
import { BrillyVaultView } from './components/BrillyVaultView';
import { MistakeTrainerView } from './components/MistakeTrainerView';
import { BoardThemePicker } from './components/BoardThemePicker';

type ActiveTab = 'games' | 'analyze' | 'vault' | 'train' | 'insights';

interface NavItem {
  id: ActiveTab;
  label: string;
  Icon: LucideIcon;
}

const NAV_ITEMS: NavItem[] = [
  { id: 'games', label: 'Games', Icon: ListChecks },
  { id: 'analyze', label: 'Analyze', Icon: Sparkles },
  { id: 'vault', label: 'Vault', Icon: Gem },
  { id: 'train', label: 'Train', Icon: GraduationCap },
  { id: 'insights', label: 'Insights', Icon: BarChart3 },
];

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
  const [initialPly, setInitialPly] = useState<number | null>(null);
  const [loadingGames, setLoadingGames] = useState(false);
  const [syncError, setSyncError] = useState<string | null>(null);
  const [notice, setNotice] = useState<{ kind: 'info' | 'error'; text: string } | null>(null);
  const [analyzing, setAnalyzing] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [batch, setBatch] = useState<BatchState | null>(null);
  const [scout, setScout] = useState<ScoutState | null>(null);
  const [muted, setMuted] = useState<boolean>(() => soundManager.isMuted());
  const [showIosTip, setShowIosTip] = useState(false);
  const [boardTheme, setBoardTheme] = useState<BoardThemeId>(() => getStoredBoardTheme());
  const [celebrationsEnabled, setCelebrationsEnabled] = useState<boolean>(() => getPref('brillyder_celebrations', true));

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
    setPref('brillyder_platform', platform);
    setPref(usernamePrefKey(platform), usernames[platform]);
    setPref(LEGACY_USERNAME_KEY, usernames.lichess);
  }, [platform, usernames]);

  useEffect(() => {
    storeBoardTheme(boardTheme);
  }, [boardTheme]);

  useEffect(() => {
    setPref('brillyder_celebrations', celebrationsEnabled);
  }, [celebrationsEnabled]);

  const setUsernameFor = useCallback((name: string) => {
    setUsernames((prev) => ({ ...prev, [platform]: name }));
  }, [platform]);

  const syncGames = useCallback(async (targetPlatform: GamePlatform, userOverride?: string) => {
    const target = (userOverride ?? usernames[targetPlatform]).trim();
    if (!target) {
      setSyncError(`Enter a ${platformLabel(targetPlatform)} username to sync.`);
      return;
    }
    setLoadingGames(true);
    setSyncError(null);
    const streamed: LichessGameRecord[] = [];
    try {
      const result = await fetchGamesForPlatform(
        targetPlatform,
        target,
        (g) => {
          streamed.push(g);
          setGamesByPlatform((prev) => ({ ...prev, [targetPlatform]: [...streamed] }));
        },
        15
      );
      setGamesByPlatform((prev) => ({ ...prev, [targetPlatform]: result }));
      setSelectedGame((prev) => prev ?? result[0] ?? null);
    } catch (err) {
      setSyncError(err instanceof Error ? `${err.message} Showing previously loaded games.` : 'Sync failed.');
    } finally {
      setLoadingGames(false);
    }
  }, [usernames]);

  useEffect(() => {
    getAllAnalyzedGames().then((cached) => {
      if (cached.length === 0) return;
      const map = new Map<string, AnalyzedGame>();
      for (const ag of cached) map.set(ag.id, ag);
      setAnalyzedMap(map);
    });
    const initialPlatform = getPref<GamePlatform>('brillyder_platform', 'lichess');
    const storedName = initialPlatform === 'chesscom'
      ? getPref<string>(usernamePrefKey('chesscom'), '')
      : getPref<string>(usernamePrefKey('lichess'), getPref<string>(LEGACY_USERNAME_KEY, 'Lukedunwell'));
    if (storedName.trim()) void syncGames(initialPlatform, storedName);
    // Boot-time hydration should only run once.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const analyzedGamesList = useMemo(() => Array.from(analyzedMap.values()), [analyzedMap]);

  const vault = useMemo(
    () => buildBrillyVault(analyzedGamesList, username),
    [analyzedGamesList, username]
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
  }, []);

  const abortScout = useCallback(() => {
    scoutRunRef.current += 1;
    scoutCancelRef.current = true;
    setScout(null);
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
    try {
      const analyzed = await analyzeGameToReview(targetGame, depth, {
        persist: true,
        shouldCancel: isStale,
        onProgress: (done, total) => {
          if (!isStale()) setProgress({ done, total });
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
    setNotice(null);
    setBatch({ active: true, paused: false, total: queue.length, done: 0, currentLabel: 'Preparing engine…' });

    let completed = 0;
    let failed = 0;

    for (let i = 0; i < queue.length; i++) {
      while (batchPauseRef.current && !isStale()) await wait(160);
      if (isStale()) return;

      const game = queue[i];
      setBatch((prev) => (!isStale() && prev ? { ...prev, currentLabel: `${game.white.name} vs ${game.black.name}` } : prev));
      try {
        const analyzed = await analyzeGameToReview(game, depthPreset, {
          persist: true,
          shouldCancel: isStale,
        });
        if (isStale()) return;
        addAnalyzedGame(analyzed);
        completed++;
      } catch (err) {
        if (err instanceof AnalysisCancelledError || isStale()) return;
        failed++;
      }
      setBatch((prev) => (!isStale() && prev ? { ...prev, done: prev.done + 1 } : prev));
    }

    if (isStale()) return;
    batchCancelRef.current = false;
    batchPauseRef.current = false;
    setBatch((prev) => (prev ? { ...prev, active: false, paused: false, currentLabel: '' } : prev));
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
      for (let i = 0; i < candidates.length; i++) {
        if (isStale()) return;
        setScout((prev) => (prev ? { ...prev, progress: { done: i, total: candidates.length } } : prev));
        const result = await analyzeGameToReview(candidates[i], 10, {
          persist: false,
          shouldCancel: isStale,
        });
        if (isStale()) return;
        analyzed.push(result);
        setScout((prev) => (prev ? { ...prev, games: [...analyzed], progress: { done: i + 1, total: candidates.length } } : prev));
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
    setInitialPly(null);
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
    const analyzed = analyzedMap.get(gameId);
    if (!analyzed) {
      setNotice({ kind: 'error', text: 'Analyze that game first so the exact moment is available.' });
      return;
    }
    const targetPlatform = gamePlatformOf(analyzed.game);
    setPlatform(targetPlatform);
    setGamesByPlatform((prev) =>
      prev[targetPlatform].some((g) => g.id === analyzed.game.id)
        ? prev
        : { ...prev, [targetPlatform]: [analyzed.game, ...prev[targetPlatform]] }
    );
    setSelectedGame(analyzed.game);
    setInitialPly(ply);
    setTab('analyze');
  }, [analyzedMap]);

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
    <div className="min-h-screen text-slate-100">
      <header className="sticky top-0 z-40 border-b border-slate-800/70 bg-[#070b13]/[0.88] pt-[env(safe-area-inset-top)] backdrop-blur-xl">
        <div className="mx-auto flex w-full max-w-lg items-center gap-1.5 px-3 py-2.5 sm:gap-2 sm:px-4 md:max-w-3xl lg:max-w-7xl lg:px-6">
          <button
            type="button"
            onClick={() => setTab('games')}
            className="flex min-w-0 items-center gap-2 text-left"
            aria-label="BrillyDer home"
          >
            <img src="./icon.svg" alt="" className="h-7 w-7 rounded-lg shadow-lg shadow-cyan-500/10 sm:h-8 sm:w-8" />
            <span className="min-w-0">
              <span className="flex items-center gap-1.5 text-sm font-black leading-none tracking-tight sm:text-base">
                <span>
                  <span className="text-cyan-300">Brilly</span>
                  <span className="text-rose-400">Der</span>
                </span>
                <span className="hidden rounded bg-slate-800 px-1.5 py-0.5 font-mono text-[9px] font-bold text-slate-300 sm:inline">!!/??</span>
              </span>
              <span className="mt-0.5 hidden text-[10px] leading-tight text-slate-400 sm:block">On-device Stockfish coach</span>
            </span>
          </button>

          <nav className="mx-auto hidden items-center gap-0.5 rounded-xl border border-slate-800/80 bg-slate-950/50 p-0.5 lg:flex">
            {NAV_ITEMS.map(({ id, label, Icon }) => (
              <button
                key={id}
                type="button"
                onClick={() => setTab(id)}
                aria-current={tab === id ? 'page' : undefined}
                className={`inline-flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-[11px] font-bold transition lg:px-3 ${
                  tab === id ? 'bg-cyan-500/15 text-cyan-200 shadow-sm' : 'text-slate-400 hover:bg-slate-800/60 hover:text-slate-200'
                }`}
              >
                <Icon className="h-3.5 w-3.5" />
                {label}
                {id === 'vault' && vault.stats.total > 0 && (
                  <span className="rounded-full bg-cyan-400/20 px-1.5 py-0.5 font-mono text-[9px] text-cyan-200">{vault.stats.total}</span>
                )}
              </button>
            ))}
          </nav>

          <div className="ml-auto flex items-center gap-1.5 lg:ml-0">
            <button
              type="button"
              onClick={() => setTab('vault')}
              className="inline-flex items-center gap-1 rounded-xl border border-cyan-500/30 bg-cyan-500/10 px-2 py-1.5 text-cyan-200 transition hover:border-cyan-400/60 hover:bg-cyan-500/20"
              aria-label={`Brilly Vault: ${vault.stats.total} brilliant moves`}
              title="Brilly Vault — every brilliant move"
            >
              <Gem className="h-3.5 w-3.5" />
              <span className="font-mono text-xs font-black tabular-nums">{vault.stats.total}</span>
              <span className="hidden text-[10px] font-bold sm:inline">Vault</span>
            </button>

            <BoardThemePicker
              theme={boardTheme}
              onThemeChange={setBoardTheme}
              celebrationsEnabled={celebrationsEnabled}
              onToggleCelebrations={() => setCelebrationsEnabled((v) => !v)}
            />

            <button
              type="button"
              onClick={toggleSound}
              className="rounded-xl border border-slate-800 bg-slate-900/80 p-2 text-slate-300 transition hover:border-slate-600"
              aria-label={muted ? 'Unmute sounds' : 'Mute sounds'}
            >
              {muted ? <VolumeX className="h-4 w-4 text-slate-500" /> : <Volume2 className="h-4 w-4 text-cyan-400" />}
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
          selectedGame ? (
            <AnalysisView
              game={selectedGame}
              analyzed={analyzedMap.get(selectedGame.id) ?? null}
              analyzing={analyzing}
              progress={progress}
              depthPreset={depthPreset}
              onDepthPresetChange={handleDepthChange}
              onStartAnalysis={() => void runSingleAnalysis(selectedGame, depthPreset)}
              onCancelAnalysis={cancelAnalysis}
              onBackToGames={() => setTab('games')}
              onOpenInsights={() => setTab('insights')}
              onOpenVault={() => setTab('vault')}
              initialPly={initialPly}
              boardTheme={boardTheme}
              celebrationsEnabled={celebrationsEnabled}
            />
          ) : (
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

        {tab === 'vault' && (
          <BrillyVaultView
            entries={vault.entries}
            stats={vault.stats}
            username={username}
            boardTheme={boardTheme}
            onOpenEntry={(entry) => openReviewedPly(entry.gameId, entry.ply)}
            onOpenGames={() => setTab('games')}
          />
        )}

        {tab === 'train' && (
          <MistakeTrainerView
            analyzedGames={analyzedGamesList}
            username={username}
            boardTheme={boardTheme}
            onOpenGame={openReviewedPly}
            onOpenGames={() => setTab('games')}
          />
        )}

        {tab === 'insights' && (
          <InsightsView
            analyzedGames={analyzedGamesList}
            username={username}
            platform={platform}
            scout={scout}
            onPlatformChange={handlePlatformChange}
            onScout={(name) => void runScout(name)}
            onCancelScout={cancelScout}
            onClearScout={() => setScout(null)}
            onOpenGames={() => setTab('games')}
            onOpenTrainer={() => setTab('train')}
          />
        )}
      </main>

      {tab !== 'analyze' && (
        <nav className="fixed bottom-0 left-0 right-0 z-40 border-t border-white/10 bg-[#070b13]/[0.95] px-2 pt-1.5 pb-[max(0.5rem,env(safe-area-inset-bottom))] backdrop-blur-xl lg:hidden">
          <div className="mx-auto grid max-w-lg grid-cols-5 gap-1">
            {NAV_ITEMS.map(({ id, label, Icon }) => (
              <button
                key={id}
                type="button"
                onClick={() => setTab(id)}
                aria-current={tab === id ? 'page' : undefined}
                className={`flex flex-col items-center rounded-xl py-1.5 text-[9px] font-bold transition ${
                  tab === id ? 'bg-cyan-500/10 text-cyan-300' : 'text-slate-400 active:bg-slate-800/50'
                }`}
              >
                <Icon className="mb-0.5 h-[18px] w-[18px]" />
                {label}
              </button>
            ))}
          </div>
        </nav>
      )}
    </div>
  );
};

export default App;
