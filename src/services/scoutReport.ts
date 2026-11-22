import type { AnalyzedGame, MultiGameInsights } from '../types/chess';
import { isUserGame, resolveUserColor, resultForUserStrict } from '../utils/player';

export interface ScoutOpeningLineStat {
  eco: string;
  openingName: string;
  side: 'w' | 'b';
  games: number;
  scorePct: number;
  avgAccuracy: number;
  sampleGameId: string;
}

export interface ScoutGameplan {
  opponentName: string;
  gamesCount: number;
  favoriteWhite: ScoutOpeningLineStat[];
  favoriteBlack: ScoutOpeningLineStat[];
  weakestTargets: ScoutOpeningLineStat[];
  tacticalTakeaways: string[];
}

/**
 * Generates an actionable "How to Beat <opponent>" Scout Gameplan
 * from analyzed scouted games + aggregated insights.
 */
export function buildScoutGameplan(
  opponentName: string,
  games: AnalyzedGame[],
  insights: MultiGameInsights
): ScoutGameplan {
  const buckets = new Map<
    string,
    {
      eco: string;
      openingName: string;
      side: 'w' | 'b';
      games: number;
      scoreSum: number;
      accSum: number;
      sampleGameId: string;
    }
  >();

  let matchedGames = 0;
  for (const ag of games) {
    if (!isUserGame(ag.game, opponentName)) continue;
    const side = resolveUserColor(ag.game, opponentName);
    const outcome = resultForUserStrict(ag.game, side);
    if (!outcome) continue;
    matchedGames += 1;
    const eco = ag.game.openingEco || '---';
    const openingName = (ag.game.openingName || 'Unknown Opening').split(':')[0].trim();
    const key = `${side}:${eco}:${openingName}`;
    const summary = side === 'w' ? ag.whiteSummary : ag.blackSummary;
    const pts = outcome === 'W' ? 1 : outcome === 'D' ? 0.5 : 0;

    const cur = buckets.get(key) ?? {
      eco,
      openingName,
      side,
      games: 0,
      scoreSum: 0,
      accSum: 0,
      sampleGameId: ag.id,
    };
    cur.games += 1;
    cur.scoreSum += pts;
    cur.accSum += summary.accuracy;
    buckets.set(key, cur);
  }

  const allStats: ScoutOpeningLineStat[] = Array.from(buckets.values()).map((b) => ({
    eco: b.eco,
    openingName: b.openingName,
    side: b.side,
    games: b.games,
    scorePct: Math.round((b.scoreSum / b.games) * 100),
    avgAccuracy: Math.round(b.accSum / b.games),
    sampleGameId: b.sampleGameId,
  }));

  const favoriteWhite = allStats
    .filter((s) => s.side === 'w')
    .sort((a, b) => b.games - a.games || b.scorePct - a.scorePct)
    .slice(0, 3);

  const favoriteBlack = allStats
    .filter((s) => s.side === 'b')
    .sort((a, b) => b.games - a.games || b.scorePct - a.scorePct)
    .slice(0, 3);

  const weakestTargets = [...allStats]
    .sort((a, b) => a.scorePct - b.scorePct || a.avgAccuracy - b.avgAccuracy)
    .slice(0, 3);

  const takeaways: string[] = [];

  if (insights.clockLeaks.timeTroubleBlunders >= 2) {
    takeaways.push(
      `Time-trouble target: ${insights.clockLeaks.timeTroubleBlunders} blunders under 60s — keep positions complex and press the clock.`
    );
  }
  if (insights.clockLeaks.impulsePerGame >= 0.4) {
    takeaways.push(
      `Impulsive mover (${insights.clockLeaks.impulsePerGame}/game fast blunders <5s) — pose concrete tactical questions early.`
    );
  }
  if (insights.blownWins >= 2) {
    takeaways.push(
      `Shaky converter (${insights.blownWins} blown winning positions) — stay resilient and create practical counterplay even when worse.`
    );
  }
  const tiltBuckets = insights.tiltGuard?.buckets ?? [];
  const tilt0 = tiltBuckets.find((t) => t.priorLosses === 0);
  const tilt2 = tiltBuckets.find((t) => t.priorLosses >= 2);
  if (tilt0 && tilt2 && tilt2.games >= 2 && tilt0.winRate - tilt2.winRate >= 15) {
    takeaways.push(
      `Rematch edge: win rate drops from ${tilt0.winRate}% to ${tilt2.winRate}% after 2+ losses.`
    );
  }
  const weakestPhase = [
    { name: 'Openings', score: insights.skillProfile.openings },
    { name: 'Tactics', score: insights.skillProfile.tactics },
    { name: 'Endgames', score: insights.skillProfile.endgames },
  ].sort((a, b) => a.score - b.score)[0];
  if (weakestPhase) {
    takeaways.push(
      `Lowest skill axis is ${weakestPhase.name} (${weakestPhase.score}/100) — steer the game toward ${weakestPhase.name.toLowerCase()}.`
    );
  }

  return {
    opponentName,
    gamesCount: matchedGames,
    favoriteWhite,
    favoriteBlack,
    weakestTargets,
    tacticalTakeaways: takeaways.slice(0, 4),
  };
}
