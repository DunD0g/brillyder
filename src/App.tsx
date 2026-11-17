import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { BarChart3, ListChecks, Sparkles, Volume2, VolumeX } from 'lucide-react';
import type { AnalysisDepthPreset, AnalyzedGame, EngineEval, LichessGameRecord } from './types/chess';
import { buildAnalyzedGame, loadPgnSafely } from './chess/classification';
import { stockfishService } from './engine/StockfishService';
import { extractLichessGameId, fetchLichessGameByUrlOrId, fetchLichessGames, parseRawPgnToGame, SAMPLE_GAMES } from './services/lichessApi';
import { getAllAnalyzedGames, getPref, saveAnalyzedGame, setPref } from './storage/gameDb';
import { soundManager } from './utils/sound';
import { AnalysisView } from './components/AnalysisView';
import { GameListView } from './components/GameListView';
import { InsightsView } from './components/InsightsView';

type ActiveTab = 'games' | 'analyze' | 'insights';

export const App: React.FC = () => {
  const [tab, setTab] = useState<ActiveTab>('games');
  const [username, setUsername] = useState<string>(() => getPref('brillyder_username', 'Lukedunwell'));
  const [depthPreset, setDepthPreset] = useState<AnalysisDepthPreset>(() => getPref('brillyder_depth', 14));
  const [games, setGames] = useState<LichessGameRecord[]>(SAMPLE_GAMES);
  const [analyzedMap, setAnalyzedMap] = useState<Map<string, AnalyzedGame>>(() => new Map());
  const [selectedGame, setSelectedGame] = useState<LichessGameRecord>(SAMPLE_GAMES[0]);
  const [loadingGames, setLoadingGames] = useState(false);
  const [syncError, setSyncError] = useState<string | null>(null);
  const [analyzing, setAnalyzing] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const [muted, setMuted] = useState<boolean>(() => soundManager.isMuted());
  const [showIosTip, setShowIosTip] = useState(false);
  const cancelFlagRef = useRef(false);

  useEffect(() => {
    const isIos = /iPad|iPhone|iPod/.test(navigator.userAgent);
    const isStandalone = window.matchMedia('(display-mode: standalone)').matches || (navigator as unknown as { standalone?: boolean }).standalone === true;
    if (isIos && !isStandalone && !getPref('brillyder_ios_tip_dismissed', false)) {
      setShowIosTip(true);
    }
  }, []);

  const syncLichess = useCallback(async (userOverride?: string) => {
    const target = (userOverride ?? username).trim();
    if (!target) return;
    setPref('brillyder_username', target);
    setLoadingGames(true);
    setSyncError(null);
    const streamed: LichessGameRecord[] = [];
    try {
      await fetchLichessGames(target, (g) => {
        streamed.push(g);
        setGames([...streamed]);
      });
      if (streamed.length > 0) {
        setSelectedGame((prev) => (prev.source === 'sample' ? streamed[0] : prev));
      }
    } catch (err) {
      setSyncError(err instanceof Error ? `${err.message} Showing cached / sample games.` : 'Sync failed.');
    } finally {
      setLoadingGames(false);
    }
  }, [username]);

  useEffect(() => {
    getAllAnalyzedGames().then((cached) => {
      if (cached.length > 0) {
        const map = new Map<string, AnalyzedGame>();
        for (const ag of cached) map.set(ag.id, ag);
        setAnalyzedMap(map);
      }
    });
    void syncLichess(getPref('brillyder_username', 'Lukedunwell'));
  }, []);

  const runFullAnalysis = useCallback(async (targetGame: LichessGameRecord, depth: AnalysisDepthPreset) => {
    cancelFlagRef.current = false;
    await stockfishService.cancelCurrent();
    setAnalyzing(true);
    setSyncError(null);
    try {
      const chess = loadPgnSafely(targetGame.pgn);
      const moves = chess.history({ verbose: true });
      const fens = ['rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', ...moves.map((m) => m.after)];
      setProgress({ done: 0, total: fens.length });
      const evals: EngineEval[] = [];

      for (let i = 0; i < fens.length; i++) {
        if (cancelFlagRef.current) return;
        const res = await stockfishService.analyzePosition(fens[i], { depth, multiPv: 2 });
        if (cancelFlagRef.current) return;
        evals.push(res);
        setProgress({ done: i + 1, total: fens.length });
      }

      const analyzedGame = buildAnalyzedGame(targetGame, evals, depth);
      await saveAnalyzedGame(analyzedGame);
      setAnalyzedMap((prev) => {
        const next = new Map(prev);
        next.set(analyzedGame.id, analyzedGame);
        return next;
      });
    } catch (err) {
      setSyncError(err instanceof Error ? err.message : 'Stockfish analysis failed.');
    } finally {
      setAnalyzing(false);
      setProgress(null);
    }
  }, []);

  const handleSelectGame = (g: LichessGameRecord, autoAnalyze: boolean) => {
    soundManager.unlock();
    setSelectedGame(g);
    setTab('analyze');
    if (autoAnalyze && !analyzedMap.has(g.id)) void runFullAnalysis(g, depthPreset);
  };

  const handleImportInput = async (input: string) => {
    const game = extractLichessGameId(input)
      ? await fetchLichessGameByUrlOrId(input, username)
      : parseRawPgnToGame(input, username);
    setGames((prev) => [game, ...prev.filter((x) => x.id !== game.id)]);
    handleSelectGame(game, true);
  };

  const analyzedIds = useMemo(() => new Set(analyzedMap.keys()), [analyzedMap]);
  const analyzedGamesList = useMemo(() => Array.from(analyzedMap.values()), [analyzedMap]);

  return (
    <div className="min-h-screen bg-[#0b0f19] text-slate-100">
      <header className="sticky top-0 z-30 bg-[#0b0f19]/90 backdrop-blur-md border-b border-slate-800/80 pt-[env(safe-area-inset-top)]">
        <div className="max-w-lg mx-auto px-3.5 py-2.5 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <img src="./icon.svg" alt="BrillyDer" className="w-7 h-7 rounded-lg" />
            <div>
              <div className="font-black text-base tracking-tight leading-none">
                <span className="text-cyan-300">Brilly</span>
                <span className="text-rose-400">Der</span>
                <span className="ml-1.5 text-[10px] font-mono px-1.5 py-0.5 rounded bg-slate-800 text-slate-300">!!/??</span>
              </div>
              <p className="text-[10px] text-slate-400 leading-tight">On-Device Stockfish Coach</p>
            </div>
          </div>
          <button
            type="button"
            onClick={() => { const next = !muted; soundManager.setMuted(next); setMuted(next); }}
            className="p-2 rounded-xl bg-slate-900 border border-slate-800 text-slate-300"
            aria-label={muted ? 'Unmute sounds' : 'Mute sounds'}
          >
            {muted ? <VolumeX className="w-4 h-4 text-slate-500" /> : <Volume2 className="w-4 h-4 text-cyan-400" />}
          </button>
        </div>
      </header>

      <main className="max-w-lg mx-auto px-3 pt-3">
        {showIosTip && (
          <div className="mb-3 rounded-2xl bg-cyan-500/10 border border-cyan-500/30 p-3 flex items-center justify-between gap-2 text-xs text-cyan-100">
            <span>Install on iPhone: tap <strong>Share</strong> → <strong>Add to Home Screen</strong> for full-screen native play.</span>
            <button type="button" onClick={() => { setShowIosTip(false); setPref('brillyder_ios_tip_dismissed', true); }} className="px-2 py-1 rounded bg-slate-900 text-slate-300 shrink-0">Got it</button>
          </div>
        )}

        {tab === 'games' && (
          <GameListView
            username={username}
            onUsernameChange={setUsername}
            games={games}
            analyzedIds={analyzedIds}
            loading={loadingGames}
            error={syncError}
            onSyncLichess={(u) => void syncLichess(u)}
            onSelectGame={handleSelectGame}
            onImportInput={handleImportInput}
          />
        )}

        {tab === 'analyze' && (
          <AnalysisView
            game={selectedGame}
            analyzed={analyzedMap.get(selectedGame.id) ?? null}
            analyzing={analyzing}
            progress={progress}
            depthPreset={depthPreset}
            onDepthPresetChange={(d) => { setDepthPreset(d); setPref('brillyder_depth', d); }}
            onStartAnalysis={() => void runFullAnalysis(selectedGame, depthPreset)}
            onCancelAnalysis={() => { cancelFlagRef.current = true; void stockfishService.cancelCurrent(); setAnalyzing(false); setProgress(null); }}
            onBackToGames={() => setTab('games')}
            onOpenInsights={() => setTab('insights')}
          />
        )}

        {tab === 'insights' && <InsightsView analyzedGames={analyzedGamesList} username={username} />}
      </main>

      {tab !== 'analyze' && (
        <nav className="fixed bottom-0 left-0 right-0 z-40 bg-slate-950/95 backdrop-blur-md border-t border-slate-800 px-4 pt-2 pb-[max(0.6rem,env(safe-area-inset-bottom))]">
          <div className="max-w-lg mx-auto grid grid-cols-3 gap-2">
            <button type="button" onClick={() => setTab('games')} className={`flex flex-col items-center py-1.5 rounded-xl text-[11px] font-bold ${tab === 'games' ? 'text-cyan-300 bg-cyan-500/10' : 'text-slate-400'}`}>
              <ListChecks className="w-4 h-4 mb-0.5" /> Games
            </button>
            <button type="button" onClick={() => setTab('analyze')} className="flex flex-col items-center py-1.5 rounded-xl text-[11px] font-bold text-slate-400">
              <Sparkles className="w-4 h-4 mb-0.5" /> Analyze
            </button>
            <button type="button" onClick={() => setTab('insights')} className={`flex flex-col items-center py-1.5 rounded-xl text-[11px] font-bold ${tab === 'insights' ? 'text-cyan-300 bg-cyan-500/10' : 'text-slate-400'}`}>
              <BarChart3 className="w-4 h-4 mb-0.5" /> Insights
            </button>
          </div>
        </nav>
      )}
    </div>
  );
};

export default App;
