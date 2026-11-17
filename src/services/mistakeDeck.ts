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
      if (!ply.bestMoveUci) continue;
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
        classification: ply.classification,
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

function startOfDay(ts: number): number {
  const d = new Date(ts);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

export function loadDrillStreak(): DrillStreak {
  const stored = getPref<DrillStreak>(STREAK_KEY, { current: 0, best: 0, lastSolvedAt: 0 });
  if (!stored.lastSolvedAt) return stored;
  const today = startOfDay(Date.now());
  const last = startOfDay(stored.lastSolvedAt);
  if (today - last > 86_400_000) return { ...stored, current: 0 };
  return stored;
}

export function recordDrillSolve(): DrillStreak {
  const current = loadDrillStreak();
  const today = startOfDay(Date.now());
  const last = startOfDay(current.lastSolvedAt);
  const nextCurrent = last === today ? current.current + 1 : 1;
  const next: DrillStreak = {
    current: nextCurrent,
    best: Math.max(current.best, nextCurrent),
    lastSolvedAt: Date.now(),
  };
  setPref(STREAK_KEY, next);
  return next;
}

export function resetMistakeProgress(): void {
  setPref(PROGRESS_KEY, {});
}
