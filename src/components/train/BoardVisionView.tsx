import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Crosshair, Eye, EyeOff, Play, RotateCcw, Trophy } from 'lucide-react';
import { BOARD_THEME_LIST, BOARD_THEMES } from '../../chess/boardThemes';
import type { BoardThemeId } from '../../types/chess';
import { getPref, setPref } from '../../storage/gameDb';
import { soundManager } from '../../utils/sound';

interface Props {
  boardTheme: BoardThemeId;
}

type PerspectiveMode = 'white' | 'black' | 'mixed';

const FILES = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'] as const;
const RANKS = ['8', '7', '6', '5', '4', '3', '2', '1'] as const;
const DURATION_SECONDS = 60;

function randomSquare(exclude?: string): string {
  let sq = 'e4';
  for (let tries = 0; tries < 8; tries++) {
    const f = FILES[Math.floor(Math.random() * 8)];
    const r = RANKS[Math.floor(Math.random() * 8)];
    sq = `${f}${r}`;
    if (sq !== exclude) break;
  }
  return sq;
}

function bestPrefKey(mode: PerspectiveMode): string {
  return `brillyder_vision_best_${mode}`;
}

export const BoardVisionView: React.FC<Props> = ({ boardTheme }) => {
  const palette = BOARD_THEMES[boardTheme] ?? BOARD_THEME_LIST[0];
  const [perspective, setPerspective] = useState<PerspectiveMode>('white');
  const [hideCoords, setHideCoords] = useState(true);
  const [running, setRunning] = useState(false);
  const [finished, setFinished] = useState(false);
  const [timeLeft, setTimeLeft] = useState(DURATION_SECONDS);
  const [target, setTarget] = useState<string>(() => randomSquare());
  const [orientation, setOrientation] = useState<'white' | 'black'>('white');
  const [score, setScore] = useState(0);
  const [misses, setMisses] = useState(0);
  const [streak, setStreak] = useState(0);
  const [bestStreak, setBestStreak] = useState(0);
  const [flash, setFlash] = useState<{ sq: string; ok: boolean } | null>(null);
  const [personalBest, setPersonalBest] = useState<number>(() =>
    getPref<number>(bestPrefKey('white'), 0)
  );

  const flashTimerRef = useRef<number | null>(null);

  useEffect(() => {
    setPersonalBest(getPref<number>(bestPrefKey(perspective), 0));
    if (!running) {
      setOrientation(perspective === 'black' ? 'black' : 'white');
    }
  }, [perspective, running]);

  useEffect(() => {
    if (!running) return;
    const id = window.setInterval(() => {
      setTimeLeft((prev) => {
        if (prev <= 1) {
          window.clearInterval(id);
          setRunning(false);
          setFinished(true);
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
    return () => window.clearInterval(id);
  }, [running]);

  useEffect(() => {
    if (!finished) return;
    if (score > personalBest) {
      setPersonalBest(score);
      setPref(bestPrefKey(perspective), score);
      soundManager.playBrilliantChord();
    }
  }, [finished, score, personalBest, perspective]);

  useEffect(() => {
    return () => {
      if (flashTimerRef.current !== null) window.clearTimeout(flashTimerRef.current);
    };
  }, []);

  const startSession = () => {
    setScore(0);
    setMisses(0);
    setStreak(0);
    setBestStreak(0);
    setTimeLeft(DURATION_SECONDS);
    setFinished(false);
    setRunning(true);
    setFlash(null);
    setOrientation(
      perspective === 'mixed'
        ? Math.random() < 0.5
          ? 'white'
          : 'black'
        : perspective
    );
    setTarget(randomSquare());
  };

  const handleSquareTap = (sq: string) => {
    if (!running) return;
    const ok = sq === target;
    setFlash({ sq, ok });
    if (flashTimerRef.current !== null) window.clearTimeout(flashTimerRef.current);
    flashTimerRef.current = window.setTimeout(() => setFlash(null), 260);

    if (ok) {
      soundManager.playSonarPing();
      setScore((s) => s + 1);
      setStreak((st) => {
        const next = st + 1;
        setBestStreak((b) => Math.max(b, next));
        return next;
      });
      setTarget((prev) => randomSquare(prev));
      if (perspective === 'mixed') {
        setOrientation(Math.random() < 0.5 ? 'white' : 'black');
      }
    } else {
      soundManager.playHullThud();
      setMisses((m) => m + 1);
      setStreak(0);
    }
  };

  const displayRanks = useMemo(
    () => (orientation === 'white' ? RANKS : [...RANKS].reverse()),
    [orientation]
  );
  const displayFiles = useMemo(
    () => (orientation === 'white' ? FILES : [...FILES].reverse()),
    [orientation]
  );

  const totalAttempts = score + misses;
  const accuracy = totalAttempts > 0 ? Math.round((score / totalAttempts) * 100) : 100;

  return (
    <div className="grid grid-cols-1 gap-3 lg:grid-cols-[minmax(0,400px)_minmax(0,1fr)]">
      <div className="min-w-0 glass-card p-3">
        <div className="mb-2 flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <Crosshair className="h-4 w-4 text-brilly" />
            <span className="text-xs font-black uppercase tracking-[0.14em] text-brilly">
              60s Board Vision
            </span>
          </div>
          <div className="flex items-center gap-2 font-mono text-xs font-black">
            <span className="text-teal-300">{score} hits</span>
            <span className={timeLeft <= 10 && running ? 'text-rose-400' : 'text-slate-300'}>
              {timeLeft}s
            </span>
          </div>
        </div>

        <div className="mb-2 tractor-beam-track h-1.5 w-full">
          <div
            className="tractor-beam-fill"
            style={{ width: `${(timeLeft / DURATION_SECONDS) * 100}%` }}
          />
        </div>

        {/* High-contrast target square readout */}
        <div className="mb-2.5 flex items-center justify-between rounded-xl border border-slate-800 bg-void/75 px-3 py-2">
          <span className="text-[10px] font-bold uppercase tracking-wider text-slate-400">
            {running ? `Tap square (${orientation} view)` : finished ? 'Round complete' : 'Ready'}
          </span>
          <span className="font-mono text-2xl font-black tracking-wider text-brilly">
            {running ? target : finished ? `${score}` : '--'}
          </span>
          <span className="font-mono text-[10px] font-bold text-slate-400">
            {streak > 1 ? `🔥 ${streak}x` : `${accuracy}%`}
          </span>
        </div>

        {/* Interactive 8x8 Coordinate Board */}
        <div className="relative mx-auto w-full max-w-[min(100%,calc(100dvh-22rem))] lg:max-w-none">
          <div
            className="grid aspect-square w-full grid-cols-8 overflow-hidden rounded-xl border border-slate-700/80 shadow-xl"
            style={{ touchAction: 'manipulation' }}
          >
            {displayRanks.map((rank, rIdx) =>
              displayFiles.map((file, fIdx) => {
                const sq = `${file}${rank}`;
                const isLight = (rIdx + fIdx) % 2 === 0;
                const isFlashed = flash?.sq === sq;
                const bg = isFlashed
                  ? flash.ok
                    ? '#2DD4BF'
                    : '#FB7185'
                  : isLight
                  ? palette.lightSquare
                  : palette.darkSquare;
                const showFileLabel = !hideCoords && rIdx === 7;
                const showRankLabel = !hideCoords && fIdx === 0;
                return (
                  <button
                    key={sq}
                    type="button"
                    disabled={!running}
                    onClick={() => handleSquareTap(sq)}
                    aria-label={sq}
                    style={{ backgroundColor: bg }}
                    className="relative flex aspect-square items-center justify-center transition-colors duration-100 active:brightness-110"
                  >
                    {showRankLabel && (
                      <span
                        className="pointer-events-none absolute left-0.5 top-0.5 font-mono text-[8px] font-black opacity-75"
                        style={{ color: isLight ? palette.darkSquare : palette.lightSquare }}
                      >
                        {rank}
                      </span>
                    )}
                    {showFileLabel && (
                      <span
                        className="pointer-events-none absolute bottom-0.5 right-0.5 font-mono text-[8px] font-black opacity-75"
                        style={{ color: isLight ? palette.darkSquare : palette.lightSquare }}
                      >
                        {file}
                      </span>
                    )}
                  </button>
                );
              })
            )}
          </div>

          {!running && (
            <div className="absolute inset-0 flex flex-col items-center justify-center rounded-xl bg-void/75 p-4 text-center backdrop-blur-[2px]">
              {finished ? (
                <>
                  <Trophy className="h-7 w-7 text-amber-300" />
                  <div className="mt-1.5 text-lg font-black text-white">
                    {score} squares in 60s
                  </div>
                  <div className="mt-0.5 font-mono text-xs text-slate-300">
                    {accuracy}% accuracy · Best streak {bestStreak} · PB {personalBest}
                  </div>
                  <button
                    type="button"
                    onClick={startSession}
                    className="mt-3 inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-purple-500 px-4 py-2 text-xs font-black text-slate-950"
                  >
                    <RotateCcw className="h-3.5 w-3.5" /> Play Again
                  </button>
                </>
              ) : (
                <>
                  <div className="text-sm font-black text-white">Coordinate Sniper</div>
                  <p className="mt-1 max-w-[230px] text-[11px] text-slate-300">
                    Tap as many target squares as you can in 60 seconds to sharpen calculation speed.
                  </p>
                  <button
                    type="button"
                    onClick={startSession}
                    className="mt-3 inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-purple-500 px-4 py-2 text-xs font-black text-slate-950"
                  >
                    <Play className="h-3.5 w-3.5" /> Start 60s Drill
                  </button>
                </>
              )}
            </div>
          )}
        </div>
      </div>

      {/* Controls & Stats */}
      <div className="min-w-0 space-y-3">
        <div className="glass-card p-3.5">
          <div className="text-[10px] font-black uppercase tracking-[0.14em] text-slate-400">
            Drill Settings
          </div>
          <div className="mt-2.5 flex flex-wrap items-center gap-1.5">
            {(['white', 'black', 'mixed'] as PerspectiveMode[]).map((mode) => (
              <button
                key={mode}
                type="button"
                disabled={running}
                onClick={() => setPerspective(mode)}
                className={`rounded-lg border px-2.5 py-1 text-[11px] font-bold capitalize transition disabled:opacity-50 ${
                  perspective === mode
                    ? 'border-teal-400/50 bg-teal-400/15 text-teal-200'
                    : 'border-slate-800 bg-void/60 text-slate-400 hover:border-slate-600'
                }`}
              >
                {mode === 'mixed' ? 'Flip Random' : `${mode} Side`}
              </button>
            ))}
          </div>

          <button
            type="button"
            onClick={() => setHideCoords((v) => !v)}
            className="mt-2.5 inline-flex items-center gap-1.5 rounded-xl border border-slate-800 bg-void/60 px-3 py-1.5 text-[11px] font-bold text-slate-300 hover:border-slate-600"
          >
            {hideCoords ? <EyeOff className="h-3.5 w-3.5 text-warp" /> : <Eye className="h-3.5 w-3.5 text-brilly" />}
            {hideCoords ? 'Coordinates Hidden (Pro)' : 'Coordinates Shown'}
          </button>

          <div className="mt-3 grid grid-cols-3 gap-2">
            <div className="rounded-xl border border-slate-800/80 bg-void/60 p-2 text-center">
              <div className="font-mono text-base font-black text-brilly">{personalBest}</div>
              <div className="text-[9px] font-bold uppercase text-slate-500">Personal Best</div>
            </div>
            <div className="rounded-xl border border-slate-800/80 bg-void/60 p-2 text-center">
              <div className="font-mono text-base font-black text-emerald-300">{accuracy}%</div>
              <div className="text-[9px] font-bold uppercase text-slate-500">Accuracy</div>
            </div>
            <div className="rounded-xl border border-slate-800/80 bg-void/60 p-2 text-center">
              <div className="font-mono text-base font-black text-amber-300">{bestStreak}</div>
              <div className="text-[9px] font-bold uppercase text-slate-500">Best Streak</div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
