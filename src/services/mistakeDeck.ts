import type {
  AnalyzedGame,
  DrillStreak,
  MistakeClassification,
  MistakeProgressRecord,
  MistakePuzzle,
} from '../types/chess';
import { getPref, setPref } from '../storage/gameDb';
import { resolveUserColor } from '../utils/player';

const PROGRESS_KEY = 'brillyder_mistake_progress';
const STREAK_KEY = 'brillyder_mistake_streak';
const RUSH_BEST_KEY = 'brillyder_rush_best';
const DAILY_DONE_KEY = 'brillyder_daily_done';

const SEVERITY: Record<MistakeClassification, number> = { blunder: 0, mistake: 1, inaccuracy: 2 };

export function buildMistakeDeck(games: AnalyzedGame[], username: string): MistakePuzzle[] {
  const puzzles: MistakePuzzle[] = [];
  for (const analyzed of games) {
    const color = resolveUserColor(analyzed.game, username);
    const playerName = color === 'w' ? analyzed.game.white.name : analyzed.game.black.name;
    const opponentName = color === 'w' ? analyzed.game.black.name : analyzed.game.white.name;
    for (const ply of analyzed.plies) {
      if (ply.color !== color) continue;
      if (ply.classification !== 'mistake' && ply.classification !== 'blunder') continue;
      if (!ply.bestMoveUci || ply.bestMoveUci === ply.uci) continue;
      puzzles.push({
        id: `${analyzed.id}_${ply.ply}`,
        gameId: analyzed.id,
        ply: ply.ply,
        moveNumber: ply.moveNumber,
        color: ply.color,
        beforeFen: ply.beforeFen,
        afterFen: ply.afterFen,
        san: ply.san,
        bestMoveSan: ply.bestMoveSan,
        bestMoveUci: ply.bestMoveUci,
        threatMoveUci: ply.threatMoveUci,
        classification: ply.classification,
        phase: ply.phase,
        tacticalTag: ply.coaching.tacticalTag,
        headline: ply.coaching.headline,
        openingName: analyzed.openingLineDetected || analyzed.game.openingName || 'Unknown Opening',
        openingEco: analyzed.game.openingEco,
        playerName,
        opponentName,
        playedAt: analyzed.game.createdAt,
        evalBefore: ply.evalBefore,
        evalAfter: ply.evalAfter,
        winLoss: ply.winLoss,
      });
    }
  }
  return puzzles.sort((a, b) => SEVERITY[a.classification] - SEVERITY[b.classification] || b.winLoss - a.winLoss || b.playedAt - a.playedAt);
}

export function loadMistakeProgress(): Record<string, MistakeProgressRecord> {
  return getPref<Record<string, MistakeProgressRecord>>(PROGRESS_KEY, {});
}

export function saveMistakeProgress(progress: Record<string, MistakeProgressRecord>): void {
  setPref(PROGRESS_KEY, progress);
}

export function recordAttempt(progress: Record<string, MistakeProgressRecord>, id: string, solved: boolean): Record<string, MistakeProgressRecord> {
  const prev = progress[id] ?? { solved: false, attempts: 0, lastAt: 0 };
  const next: Record<string, MistakeProgressRecord> = {
    ...progress,
    [id]: {
      solved: prev.solved || solved,
      attempts: prev.attempts + 1,
      lastAt: Date.now(),
    },
  };
  saveMistakeProgress(next);
  return next;
}

export function dateKey(date = new Date()): string {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
}

function yesterdayKey(now = new Date()): string {
  const prev = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  return dateKey(prev);
}

export function loadDrillStreak(now = new Date()): DrillStreak {
  const stored = getPref<DrillStreak>(STREAK_KEY, { current: 0, best: 0, lastSolvedAt: 0 });
  if (!stored.lastSolvedAt) return stored;
  const lastDay = dateKey(new Date(stored.lastSolvedAt));
  const today = dateKey(now);
  const yesterday = yesterdayKey(now);
  // DST-safe calendar check: streak stays alive on same day or consecutive next day
  if (lastDay !== today && lastDay !== yesterday) {
    return { ...stored, current: 0 };
  }
  return stored;
}

export function recordDrillSolve(now = new Date()): DrillStreak {
  const current = loadDrillStreak(now);
  const today = dateKey(now);
  const yesterday = yesterdayKey(now);
  const lastDay = current.lastSolvedAt ? dateKey(new Date(current.lastSolvedAt)) : '';
  const continues = lastDay === today || lastDay === yesterday;
  const nextCurrent = continues ? current.current + 1 : 1;
  const next: DrillStreak = {
    current: nextCurrent,
    best: Math.max(current.best, nextCurrent),
    lastSolvedAt: now.getTime(),
  };
  setPref(STREAK_KEY, next);
  return next;
}

export function resetMistakeProgress(): void {
  setPref(PROGRESS_KEY, {});
}

export function pickDailyPuzzle(deck: MistakePuzzle[], date = new Date()): MistakePuzzle | null {
  if (deck.length === 0) return null;
  const key = dateKey(date);
  let hash = 2166136261;
  for (let i = 0; i < key.length; i++) {
    hash ^= key.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return deck[Math.abs(hash) % deck.length] ?? null;
}

export function loadDailyDone(): string {
  return getPref<string>(DAILY_DONE_KEY, '');
}

export function markDailyDone(): string {
  const key = dateKey();
  setPref(DAILY_DONE_KEY, key);
  return key;
}

export function loadRushBest(): number {
  return getPref<number>(RUSH_BEST_KEY, 0);
}

export function saveRushBest(score: number): number {
  const best = Math.max(loadRushBest(), score);
  setPref(RUSH_BEST_KEY, best);
  return best;
}
