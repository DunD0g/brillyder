import type {
  AccuracyTrendPoint,
  AnalyzedGame,
  AnalyzedPly,
  CheckpointMetrics,
  ColourSplit,
  EndgameCategory,
  EndgameCategoryStat,
  GameHighlight,
  MotifWeaknessStat,
  MultiGameInsights,
  OpeningStat,
  PhaseBlunderStats,
  PlayerColor,
  TiltStreakBucket,
  ClockBucketStats,
  TwentyGameCheckpoints,
} from '../types/chess';
import { clamp, computeMoveTimeSpent, parsePgnTimeControl } from '../utils/chessMath';
import { resultForUserStrict, resolveUserColor } from '../utils/player';
import { classifyEndgameCategory } from '../chess/tacticalMotifs';
import { ADVANTAGE_THRESHOLD_CP, userPerspectiveCp } from './advantageConversion';

const ENDGAME_CATEGORIES: EndgameCategory[] = ['Rook', 'Pawn', 'Minor Piece', 'Queen', 'Rook+Minor'];

interface RatingBandExpectation {
  label: string;
  min: number;
  max: number;
  expected: {
    openingAcc: number;
    midAcc: number;
    endAcc: number;
    conversion: number;
    resilience: number;
    lowClockAcc: number;
  };
}

const BANDS: RatingBandExpectation[] = [
  { label: 'Under 1000', min: 0, max: 999, expected: { openingAcc: 67, midAcc: 58, endAcc: 54, conversion: 56, resilience: 45, lowClockAcc: 52 } },
  { label: '1000–1299', min: 1000, max: 1299, expected: { openingAcc: 74, midAcc: 66, endAcc: 62, conversion: 65, resilience: 54, lowClockAcc: 59 } },
  { label: '1300–1599', min: 1300, max: 1599, expected: { openingAcc: 80, midAcc: 73, endAcc: 70, conversion: 73, resilience: 62, lowClockAcc: 66 } },
  { label: '1600–1899', min: 1600, max: 1899, expected: { openingAcc: 85, midAcc: 79, endAcc: 76, conversion: 80, resilience: 70, lowClockAcc: 73 } },
  { label: '1900–2199', min: 1900, max: 2199, expected: { openingAcc: 89, midAcc: 84, endAcc: 82, conversion: 85, resilience: 76, lowClockAcc: 79 } },
  { label: '2200+', min: 2200, max: 9999, expected: { openingAcc: 92, midAcc: 88, endAcc: 87, conversion: 90, resilience: 82, lowClockAcc: 84 } },
];

function bandForRating(rating: number): RatingBandExpectation {
  return BANDS.find((b) => rating >= b.min && rating <= b.max) ?? BANDS[2];
}

function relativeScore(actual: number, expected: number, spread: number): number {
  return Math.round(clamp(55 + ((actual - expected) / spread) * 24, 15, 99));
}

function emptyPhase(phase: 'Opening' | 'Middlegame' | 'Endgame'): PhaseBlunderStats {
  return { phase, moves: 0, inaccuracies: 0, mistakes: 0, blunders: 0, blunderRatePer10Moves: 0, accuracy: 0 };
}

function emptyClockBuckets(): ClockBucketStats[] {
  return [
    { label: '< 30s', clockLimit: 30, moves: 0, mistakes: 0, blunders: 0, accuracy: 0, errorsPer10Moves: 0 },
    { label: '30s–1m', clockLimit: 60, moves: 0, mistakes: 0, blunders: 0, accuracy: 0, errorsPer10Moves: 0 },
    { label: '1m–3m', clockLimit: 180, moves: 0, mistakes: 0, blunders: 0, accuracy: 0, errorsPer10Moves: 0 },
    { label: '3m+', clockLimit: Number.POSITIVE_INFINITY, moves: 0, mistakes: 0, blunders: 0, accuracy: 0, errorsPer10Moves: 0 },
  ];
}

function emptyColour(): ColourSplit {
  return { games: 0, wins: 0, draws: 0, losses: 0, winRate: 0, accuracy: 0 };
}

function finishColour(raw: ColourSplit, accSum: number, scoredGames: number): ColourSplit {
  if (raw.games === 0) return raw;
  return {
    ...raw,
    winRate: scoredGames > 0 ? Math.round(((raw.wins + raw.draws * 0.5) / scoredGames) * 100) : 0,
    accuracy: Number((accSum / raw.games).toFixed(1)),
  };
}

function gameHighlightScore(input: {
  accuracy: number;
  result: 'W' | 'D' | 'L';
  userRating: number;
  opponentRating: number;
  brilliants: number;
  blunders: number;
}): number {
  const resultBonus = input.result === 'W' ? 7 : input.result === 'D' ? 1 : -5;
  const ratingGap = input.opponentRating > 0 && input.userRating > 0 ? input.opponentRating - input.userRating : 0;
  const opponentBonus = clamp(ratingGap / 12, -6, 8);
  return Number((input.accuracy + resultBonus + opponentBonus + Math.min(6, input.brilliants * 3) - Math.min(8, input.blunders * 2)).toFixed(1));
}

function resolveClockMetricsForGame(ag: AnalyzedGame, uc: PlayerColor): {
  impulseBlunders: number;
  timeTroubleBlunders: number;
  spentSum: number;
  spentCount: number;
  hasClockData: boolean;
} {
  const tc = parsePgnTimeControl(ag.game.pgn, ag.game.timeControlLabel);
  let prevClock = tc.baseSeconds ?? undefined;
  let impulseBlunders = 0;
  let timeTroubleBlunders = 0;
  let spentSum = 0;
  let spentCount = 0;
  let hasClockData = false;

  for (const p of ag.plies) {
    if (p.color !== uc) continue;
    if (p.clockSeconds !== undefined) hasClockData = true;
    const spent =
      p.timeSpentSeconds ??
      computeMoveTimeSpent(prevClock, p.clockSeconds, tc.incrementSeconds, p.moveNumber === 1);
    if (spent !== undefined) {
      spentSum += spent;
      spentCount++;
    }
    const isErr = p.classification === 'blunder' || p.classification === 'mistake';
    if (isErr) {
      if (p.clockTag === 'time-trouble' || (p.clockSeconds !== undefined && p.clockSeconds < 60)) {
        timeTroubleBlunders++;
      } else if (
        p.clockTag === 'impulse' ||
        (spent !== undefined && spent < 5 && (prevClock ?? p.clockSeconds ?? 0) > 180)
      ) {
        impulseBlunders++;
      }
    }
    if (p.clockSeconds !== undefined) prevClock = p.clockSeconds;
  }

  return { impulseBlunders, timeTroubleBlunders, spentSum, spentCount, hasClockData };
}

function computeCheckpointSlice(games: AnalyzedGame[], username: string): CheckpointMetrics {
  let eval10Sum = 0;
  let eval10Count = 0;
  let impulseTotal = 0;
  let clockGamesCount = 0;
  let winningGames = 0;
  let blownGames = 0;

  for (const ag of games) {
    const uc = resolveUserColor(ag.game, username);
    const result = resultForUserStrict(ag.game, uc);
    const sign = uc === 'w' ? 1 : -1;

    // Require >= 16 plies (8 full moves) so early checkmates/aborts don't skew Move-10 eval
    if (ag.plies.length >= 16) {
      const ply10Idx = Math.min(ag.plies.length - 1, 19);
      const cp = Math.max(-800, Math.min(800, ag.plies[ply10Idx].evalAfter.cpWhite * sign));
      eval10Sum += cp / 100;
      eval10Count++;
    }

    const cm = resolveClockMetricsForGame(ag, uc);
    impulseTotal += cm.impulseBlunders;
    if (cm.hasClockData) clockGamesCount++;

    if (result) {
      let hadClearLead = false;
      for (const p of ag.plies) {
        if (p.color !== uc) continue;
        if (userPerspectiveCp(p.evalBefore, uc) >= ADVANTAGE_THRESHOLD_CP) {
          hadClearLead = true;
          break;
        }
      }
      if (hadClearLead) {
        winningGames++;
        if (result !== 'W') blownGames++;
      }
    }
  }

  const impulseDenom = clockGamesCount > 0 ? clockGamesCount : games.length;
  return {
    games: games.length,
    avgEvalMove10: eval10Count > 0 ? Number((eval10Sum / eval10Count).toFixed(2)) : null,
    impulseBlundersPerGame: impulseDenom > 0 ? Number((impulseTotal / impulseDenom).toFixed(2)) : 0,
    blownLeadPct: winningGames > 0 ? Math.round((blownGames / winningGames) * 100) : null,
  };
}

export function computeMultiGameInsights(games: AnalyzedGame[], username: string): MultiGameInsights {
  if (games.length === 0) {
    return {
      gamesCount: 0,
      avgAccuracy: 0,
      avgEstimatedElo: 0,
      record: { wins: 0, draws: 0, losses: 0 },
      skillProfile: { openings: 50, tactics: 50, endgames: 50, conversion: 50, resilience: 50, timeManagement: 50 },
      openings: [],
      phaseStats: [emptyPhase('Opening'), emptyPhase('Middlegame'), emptyPhase('Endgame')],
      timeTrouble: emptyClockBuckets(),
      clockLeaks: { impulseBlunders: 0, timeTroubleBlunders: 0, avgTimeSpentSec: 0, impulsePerGame: 0 },
      tiltGuard: { buckets: [], activeWarning: false, consecutiveLosses: 0 },
      checkpoints: null,
      missedMotifs: [],
      endgameCategories: [],
      trend: [],
      ratingBand: 'Unrated',
      brilliantCount: 0,
      recommendation: 'Analyze at least two games to unlock your rating-relative BrillyDer skill radar.',
      bestGames: [],
      worstGame: null,
      bestAccuracy: 0,
      avgOpponentRating: 0,
      giantSlayer: { wins: 0, games: 0, best: null },
      comebacks: 0,
      blownWins: 0,
      blunderFreeGames: 0,
      scoreByColour: { white: emptyColour(), black: emptyColour() },
      currentStreak: { kind: 'none', count: 0 },
      openingBest: null,
      openingWorst: null,
    };
  }

  let accSum = 0;
  let eloSum = 0;
  let ratingAnchorSum = 0;
  let ratingAnchorCount = 0;
  let wins = 0;
  let draws = 0;
  let losses = 0;
  let brilliantCount = 0;
  let winPos = 0;
  let convWinPos = 0;
  let defMoves = 0;
  let heldDef = 0;
  let sharpTot = 0;
  let sharpOk = 0;
  let bestAccuracy = 0;
  let opponentRatingSum = 0;
  let opponentRatingCount = 0;
  let comebacks = 0;
  let blownWins = 0;
  let blunderFreeGames = 0;
  let giantWins = 0;
  let giantGames = 0;
  let giantBest: GameHighlight | null = null;
  let impulseBlunders = 0;
  let timeTroubleBlunders = 0;
  let clockAnnotatedGames = 0;
  let spentSumTotal = 0;
  let spentCountTotal = 0;

  const highlights: Array<GameHighlight & { worstPly: number; hasFinishedResult: boolean }> = [];
  const colourAcc: Record<PlayerColor, { split: ColourSplit; accSum: number; scoredGames: number }> = {
    w: { split: emptyColour(), accSum: 0, scoredGames: 0 },
    b: { split: emptyColour(), accSum: 0, scoredGames: 0 },
  };
  const openMap = new Map<
    string,
    { name: string; eco: string; games: number; scoredGames: number; wins: number; draws: number; losses: number; accSum: number }
  >();
  const phases: Record<'opening' | 'middlegame' | 'endgame', AnalyzedPly[]> = { opening: [], middlegame: [], endgame: [] };
  const clockMoves: AnalyzedPly[] = [];
  const motifMap = new Map<string, { count: number; winLossSum: number }>();
  const endgameMap = new Map<EndgameCategory, { moves: number; accSum: number; blunders: number }>();
  for (const cat of ENDGAME_CATEGORIES) endgameMap.set(cat, { moves: 0, accSum: 0, blunders: 0 });

  for (const ag of games) {
    const uc = resolveUserColor(ag.game, username);
    const sum = uc === 'w' ? ag.whiteSummary : ag.blackSummary;
    accSum += sum.accuracy;
    eloSum += sum.estimatedElo;
    const anchorRating = uc === 'w' ? ag.game.white.rating : ag.game.black.rating;
    if (anchorRating) {
      ratingAnchorSum += anchorRating;
      ratingAnchorCount++;
    }

    const strictResult = resultForUserStrict(ag.game, uc);
    if (strictResult === 'W') wins++;
    else if (strictResult === 'D') draws++;
    else if (strictResult === 'L') losses++;

    const cm = resolveClockMetricsForGame(ag, uc);
    impulseBlunders += cm.impulseBlunders;
    timeTroubleBlunders += cm.timeTroubleBlunders;
    if (cm.hasClockData) clockAnnotatedGames++;
    spentSumTotal += cm.spentSum;
    spentCountTotal += cm.spentCount;

    const userRating = (uc === 'w' ? ag.game.white.rating : ag.game.black.rating) ?? 0;
    const opponentRating = (uc === 'w' ? ag.game.black.rating : ag.game.white.rating) ?? 0;
    const opponentName = uc === 'w' ? ag.game.black.name : ag.game.white.name;
    if (opponentRating > 0) {
      opponentRatingSum += opponentRating;
      opponentRatingCount++;
    }

    const rawOpen = ag.openingLineDetected || ag.game.openingName || 'Unknown Opening';
    const family = rawOpen.includes(':') ? rawOpen.slice(0, rawOpen.indexOf(':')).trim() : rawOpen.trim();
    const bucket = openMap.get(family) ?? {
      name: family,
      eco: ag.game.openingEco || '',
      games: 0,
      scoredGames: 0,
      wins: 0,
      draws: 0,
      losses: 0,
      accSum: 0,
    };
    if (!bucket.eco && ag.game.openingEco) bucket.eco = ag.game.openingEco;
    bucket.games++;
    bucket.accSum += sum.accuracy;
    if (strictResult === 'W') { bucket.wins++; bucket.scoredGames++; }
    else if (strictResult === 'D') { bucket.draws++; bucket.scoredGames++; }
    else if (strictResult === 'L') { bucket.losses++; bucket.scoredGames++; }
    openMap.set(family, bucket);

    const colour = colourAcc[uc];
    colour.split.games++;
    colour.accSum += sum.accuracy;
    if (strictResult === 'W') { colour.split.wins++; colour.scoredGames++; }
    else if (strictResult === 'D') { colour.split.draws++; colour.scoredGames++; }
    else if (strictResult === 'L') { colour.split.losses++; colour.scoredGames++; }

    let hadClearAdvantage = false;
    let userBrilliants = 0;
    let userBlunders = 0;
    let userGreats = 0;
    let firstBrilliantPly = 0;
    let firstGreatPly = 0;
    let worstPly = 0;
    let maxWinLoss = -1;
    let minWp = uc === 'w' ? ag.initialEval.winPercentWhite : 100 - ag.initialEval.winPercentWhite;

    for (const p of ag.plies) {
      const wpAll = uc === 'w' ? p.evalBefore.winPercentWhite : 100 - p.evalBefore.winPercentWhite;
      const wpAfter = uc === 'w' ? p.evalAfter.winPercentWhite : 100 - p.evalAfter.winPercentWhite;
      minWp = Math.min(minWp, wpAll, wpAfter);

      if (p.color !== uc) continue;
      phases[p.phase].push(p);
      if (p.clockSeconds !== undefined) clockMoves.push(p);

      if (p.winLoss > maxWinLoss) {
        maxWinLoss = p.winLoss;
        worstPly = p.ply;
      }

      // Motif tracking for mistakes & blunders
      if (p.classification === 'mistake' || p.classification === 'blunder') {
        const tag = p.coaching.tacticalTag;
        if (tag && tag !== 'Suboptimal' && tag !== 'Eval Collapse') {
          const prev = motifMap.get(tag) ?? { count: 0, winLossSum: 0 };
          prev.count++;
          prev.winLossSum += p.winLoss;
          motifMap.set(tag, prev);
        }
      }

      // Endgame category tracking
      if (p.phase === 'endgame') {
        try {
          const cat = classifyEndgameCategory(p.beforeFen);
          const stat = endgameMap.get(cat)!;
          stat.moves++;
          stat.accSum += p.accuracy;
          if (p.classification === 'blunder' || p.classification === 'mistake') stat.blunders++;
        } catch {
          // ignore invalid FEN
        }
      }

      if (p.classification === 'brilliant') {
        brilliantCount++;
        userBrilliants++;
        if (firstBrilliantPly === 0) firstBrilliantPly = p.ply;
      }
      if (p.classification === 'great') {
        userGreats++;
        if (firstGreatPly === 0) firstGreatPly = p.ply;
      }
      if (p.classification === 'blunder') userBlunders++;

      // Unified clear-lead threshold (+2.5 pawns) aligned across Conversion, Checkpoints, and Blown Wins
      if (userPerspectiveCp(p.evalBefore, uc) >= ADVANTAGE_THRESHOLD_CP) {
        hadClearAdvantage = true;
      }

      const wp = uc === 'w' ? p.evalBefore.winPercentWhite : 100 - p.evalBefore.winPercentWhite;
      if (wp >= 20 && wp <= 45) {
        defMoves++;
        if (p.winLoss <= 10) heldDef++;
      }
      if (p.secondBestGapWin >= 8 || p.classification === 'brilliant' || p.classification === 'great') {
        sharpTot++;
        if (p.winLoss <= 10) sharpOk++;
      }
    }

    if (strictResult) {
      if (hadClearAdvantage) {
        winPos++;
        if (strictResult === 'W') convWinPos++;
        else blownWins++;
      }
      if (strictResult === 'W' && minWp <= 20) comebacks++;
    }
    if (userBlunders === 0 && ag.plies.length >= 2) blunderFreeGames++;
    bestAccuracy = Math.max(bestAccuracy, sum.accuracy);

    const displayResult: 'W' | 'D' | 'L' = strictResult ?? 'D';
    const highlightPly = firstBrilliantPly || firstGreatPly || ag.plies.length;
    const score = gameHighlightScore({
      accuracy: sum.accuracy,
      result: displayResult,
      userRating,
      opponentRating,
      brilliants: userBrilliants,
      blunders: userBlunders,
    });
    const reasonBits = [`${sum.accuracy.toFixed(1)}% accuracy`];
    if (strictResult === 'W' && opponentRating > 0) reasonBits.push(`beat ${opponentRating}`);
    if (userBrilliants > 0) reasonBits.push(`${userBrilliants} !!`);
    if (userGreats > 0) reasonBits.push(`${userGreats} great`);
    if (userBlunders === 0) reasonBits.push('0 blunders');
    const highlight: GameHighlight & { worstPly: number; hasFinishedResult: boolean } = {
      gameId: ag.id,
      opponent: opponentName,
      opponentRating,
      userRating,
      userColor: uc,
      result: displayResult,
      accuracy: sum.accuracy,
      opening: rawOpen,
      playedAt: ag.game.createdAt,
      brilliants: userBrilliants,
      blunders: userBlunders,
      score,
      highlightPly,
      worstPly: worstPly || ag.plies.length,
      hasFinishedResult: strictResult !== null,
      reason: reasonBits.join(' · '),
    };
    highlights.push(highlight);

    if (strictResult && userRating > 0 && opponentRating >= userRating + 50) {
      giantGames++;
      if (strictResult === 'W') {
        giantWins++;
        if (!giantBest || opponentRating > giantBest.opponentRating) giantBest = highlight;
      }
    }
  }

  // Deterministic chronological ordering (ties broken by id)
  const chronological = games
    .slice()
    .sort((a, b) => a.game.createdAt - b.game.createdAt || a.id.localeCompare(b.id));

  // Tilt Guard: chronological win-rate by consecutive prior losses (0L, 1L, 2L, 3L+)
  // Excludes unfinished '*' games so aborts never distort or reset tilt streaks.
  const tiltBuckets: TiltStreakBucket[] = [
    { label: 'Fresh (0L)', priorLosses: 0, games: 0, wins: 0, draws: 0, losses: 0, winRate: 0 },
    { label: 'After 1L', priorLosses: 1, games: 0, wins: 0, draws: 0, losses: 0, winRate: 0 },
    { label: 'After 2L', priorLosses: 2, games: 0, wins: 0, draws: 0, losses: 0, winRate: 0 },
    { label: '3L+ Tilt', priorLosses: 3, games: 0, wins: 0, draws: 0, losses: 0, winRate: 0 },
  ];
  let runningLosses = 0;
  for (const ag of chronological) {
    const uc = resolveUserColor(ag.game, username);
    const res = resultForUserStrict(ag.game, uc);
    if (!res) continue;
    const bIdx = Math.min(3, runningLosses);
    const tb = tiltBuckets[bIdx];
    tb.games++;
    if (res === 'W') tb.wins++;
    else if (res === 'D') tb.draws++;
    else tb.losses++;
    runningLosses = res === 'L' ? runningLosses + 1 : 0;
  }
  for (const tb of tiltBuckets) {
    tb.winRate = tb.games > 0 ? Math.round(((tb.wins + tb.draws * 0.5) / tb.games) * 100) : 0;
  }

  // 20-Game Checkpoints (adapts smoothly to half-split if 4..39 rated games exist)
  const ratedChrono = chronological.filter((g) => g.game.rated);
  const poolForCp = ratedChrono.length >= 4 ? ratedChrono : chronological;
  let checkpoints: TwentyGameCheckpoints | null = null;
  if (poolForCp.length >= 4) {
    const windowSize = Math.min(20, Math.floor(poolForCp.length / 2));
    const recentSlice = poolForCp.slice(-windowSize);
    const prevSlice = poolForCp.slice(-(windowSize * 2), -windowSize);
    checkpoints = {
      windowSize,
      recent: computeCheckpointSlice(recentSlice, username),
      previous: computeCheckpointSlice(prevSlice, username),
    };
  }

  const mkPhase = (label: 'Opening' | 'Middlegame' | 'Endgame', list: AnalyzedPly[]): PhaseBlunderStats => {
    if (list.length === 0) return emptyPhase(label);
    let inac = 0, mis = 0, blun = 0, acc = 0;
    for (const p of list) {
      acc += p.accuracy;
      if (p.classification === 'inaccuracy') inac++;
      else if (p.classification === 'mistake') mis++;
      else if (p.classification === 'blunder') blun++;
    }
    return {
      phase: label,
      moves: list.length,
      inaccuracies: inac,
      mistakes: mis,
      blunders: blun,
      blunderRatePer10Moves: Number((((mis + blun) / list.length) * 10).toFixed(2)),
      accuracy: Number((acc / list.length).toFixed(1)),
    };
  };

  const phaseStats = [mkPhase('Opening', phases.opening), mkPhase('Middlegame', phases.middlegame), mkPhase('Endgame', phases.endgame)];

  const timeTrouble = emptyClockBuckets();
  for (const p of clockMoves) {
    if (p.clockSeconds === undefined) continue;
    const bucket = timeTrouble.find((b) => p.clockSeconds! < b.clockLimit) ?? timeTrouble[timeTrouble.length - 1];
    bucket.moves++;
    bucket.accuracy += p.accuracy;
    if (p.classification === 'mistake') bucket.mistakes++;
    if (p.classification === 'blunder') bucket.blunders++;
  }
  for (const bucket of timeTrouble) {
    if (bucket.moves > 0) {
      bucket.accuracy = Number((bucket.accuracy / bucket.moves).toFixed(1));
      bucket.errorsPer10Moves = Number((((bucket.mistakes + bucket.blunders) / bucket.moves) * 10).toFixed(2));
    }
  }

  const openings: OpeningStat[] = Array.from(openMap.values())
    .map((o) => ({
      name: o.name,
      eco: o.eco,
      games: o.games,
      wins: o.wins,
      draws: o.draws,
      losses: o.losses,
      winRate: o.scoredGames > 0 ? Math.round(((o.wins + o.draws * 0.5) / o.scoredGames) * 100) : 0,
      avgAccuracy: Number((o.accSum / o.games).toFixed(1)),
    }))
    .sort((a, b) => b.games - a.games || b.winRate - a.winRate);

  const missedMotifs: MotifWeaknessStat[] = Array.from(motifMap.entries())
    .map(([motif, stat]) => ({
      motif,
      count: stat.count,
      avgWinLoss: Number((stat.winLossSum / Math.max(1, stat.count)).toFixed(1)),
    }))
    .sort((a, b) => b.count - a.count || b.avgWinLoss - a.avgWinLoss)
    .slice(0, 6);

  const endgameCategories: EndgameCategoryStat[] = ENDGAME_CATEGORIES.map((category) => {
    const s = endgameMap.get(category)!;
    return {
      category,
      moves: s.moves,
      accuracy: s.moves > 0 ? Number((s.accSum / s.moves).toFixed(1)) : 0,
      blunders: s.blunders,
    };
  }).filter((c) => c.moves > 0);

  const bestGames: GameHighlight[] = highlights
    .slice()
    .sort((a, b) => b.score - a.score || b.playedAt - a.playedAt)
    .slice(0, 3);
  const worstCandidate =
    highlights.length > 1
      ? highlights.slice().sort((a, b) => a.score - b.score || a.playedAt - b.playedAt)[0]
      : null;
  const worstGame: GameHighlight | null = worstCandidate
    ? { ...worstCandidate, highlightPly: worstCandidate.worstPly }
    : null;

  // Reverse chronological for current streak (strictly matching chronological tie-breaker)
  const finishedByDate = highlights
    .filter((h) => h.hasFinishedResult)
    .sort((a, b) => b.playedAt - a.playedAt || b.gameId.localeCompare(a.gameId));
  const latestResult = finishedByDate[0]?.result;
  const streakKind: 'W' | 'D' | 'L' | 'none' = latestResult ?? 'none';
  let streakCount = 0;
  if (latestResult) {
    for (const h of finishedByDate) {
      if (h.result !== latestResult) break;
      streakCount++;
    }
  }
  const consecutiveLosses = streakKind === 'L' ? streakCount : 0;

  // Opening Best vs Worst: fall back to full openings if <2 openings meet games>=2, and NEVER return the same opening for both!
  const openingPool = openings.filter((o) => o.games >= 2);
  const ratedOpenings = openingPool.length >= 2 ? openingPool : openings;
  const openingBest =
    ratedOpenings
      .slice()
      .sort((a, b) => b.winRate - a.winRate || b.avgAccuracy - a.avgAccuracy || b.games - a.games)[0] ?? null;
  const worstPool = openingBest ? ratedOpenings.filter((o) => o.name !== openingBest.name) : ratedOpenings;
  const openingWorst =
    worstPool
      .slice()
      .sort((a, b) => a.winRate - b.winRate || a.avgAccuracy - b.avgAccuracy || b.games - a.games)[0] ?? null;

  const avgAccuracy = Number((accSum / games.length).toFixed(1));
  const avgEstimatedElo = Math.round(eloSum / games.length);
  const ratingAnchor = ratingAnchorCount > 0 ? ratingAnchorSum / ratingAnchorCount : avgEstimatedElo;
  const band = bandForRating(ratingAnchor);
  const exp = band.expected;

  const openingAcc = phaseStats[0].moves > 0 ? phaseStats[0].accuracy : avgAccuracy;
  const midAcc = phaseStats[1].moves > 0 ? phaseStats[1].accuracy : avgAccuracy;
  const endAcc = phaseStats[2].moves > 0 ? phaseStats[2].accuracy : avgAccuracy;
  const tacticsRaw = sharpTot >= 4 ? (sharpOk / sharpTot) * 100 : midAcc;
  const conversionRaw = winPos > 0 ? (convWinPos / winPos) * 100 : exp.conversion;
  const resilienceRaw = defMoves > 0 ? (heldDef / defMoves) * 100 : exp.resilience;

  const lowClockMoves = clockMoves.filter((p) => (p.clockSeconds ?? Number.POSITIVE_INFINITY) < 60);
  const lowClockAcc = lowClockMoves.length > 0
    ? lowClockMoves.reduce((sum, p) => sum + p.accuracy, 0) / lowClockMoves.length
    : avgAccuracy;
  const impulseDenom = clockAnnotatedGames > 0 ? clockAnnotatedGames : games.length;
  const impulsePerGame = Number((impulseBlunders / Math.max(1, impulseDenom)).toFixed(2));
  // Factor impulse blunders into effective time-management accuracy
  const impulsePenalty = Math.min(14, impulsePerGame * 6);
  const effectiveTimeAcc = clamp(lowClockAcc - impulsePenalty, 0, 100);

  const measured: Record<'openings' | 'tactics' | 'endgames' | 'conversion' | 'resilience' | 'timeManagement', boolean> = {
    openings: phases.opening.length >= 4,
    tactics: sharpTot >= 4,
    endgames: phases.endgame.length >= 4,
    conversion: winPos >= 2,
    resilience: defMoves >= 4,
    timeManagement: lowClockMoves.length >= 5 || clockAnnotatedGames >= 2,
  };

  const skillProfile = {
    openings: measured.openings ? relativeScore(openingAcc, exp.openingAcc, 10) : 50,
    tactics: measured.tactics ? relativeScore(tacticsRaw, exp.midAcc + 2, 14) : 50,
    endgames: measured.endgames ? relativeScore(endAcc, exp.endAcc, 11) : 50,
    conversion: measured.conversion ? relativeScore(conversionRaw, exp.conversion, 22) : 50,
    resilience: measured.resilience ? relativeScore(resilienceRaw, exp.resilience, 22) : 50,
    timeManagement: measured.timeManagement ? relativeScore(effectiveTimeAcc, exp.lowClockAcc, 10) : 50,
  };

  const trend: AccuracyTrendPoint[] = chronological
    .slice(-12)
    .map((ag) => {
      const uc = resolveUserColor(ag.game, username);
      const sum = uc === 'w' ? ag.whiteSummary : ag.blackSummary;
      const opponent = uc === 'w' ? ag.game.black.name : ag.game.white.name;
      return {
        date: ag.game.createdAt,
        accuracy: sum.accuracy,
        result: resultForUserStrict(ag.game, uc) ?? 'D',
        opening: ag.openingLineDetected || ag.game.openingName || 'Unknown Opening',
        opponent,
      };
    });

  const labels: Record<keyof typeof skillProfile, string> = {
    openings: 'Opening precision',
    tactics: 'Tactical sharpness',
    endgames: 'Endgame technique',
    conversion: 'Advantage conversion',
    resilience: 'Defensive resilience',
    timeManagement: 'Time management',
  };
  const advice: Record<keyof typeof skillProfile, string> = {
    endgames: `Endgame technique is your biggest lever (${skillProfile.endgames}/100 vs the ${band.label} band). Drill rook-and-pawn conversions and Syzygy positions.`,
    tactics: `Tactical sharpness (${skillProfile.tactics}/100) trails your band. Warm up with a 60s Gravity Check before queuing and drill missed motifs.`,
    conversion: `You convert ${conversionRaw.toFixed(0)}% of clear advantages. Launch Tractor Beam Conversion drills to practice simplifying +2.5 leads.`,
    openings: `Your opening accuracy is ${openingAcc.toFixed(0)}%. Lock in your starter repertoires with FSRS and patch uncovered replies.`,
    resilience: `Defensive resilience (${skillProfile.resilience}/100) — when worse, prioritise king safety, blockading, and active counterplay.`,
    timeManagement: `Time management: low-clock accuracy is ${lowClockAcc.toFixed(0)}% with ${impulsePerGame.toFixed(2)} impulse mistakes/game. Slow down on critical turns when >3m remain.`,
  };
  const measuredKeys = (Object.keys(skillProfile) as Array<keyof typeof skillProfile>).filter((k) => measured[k]);
  const focusKeys = measuredKeys.length > 0 ? measuredKeys : (Object.keys(skillProfile) as Array<keyof typeof skillProfile>);
  const weakest = focusKeys.sort((a, b) => skillProfile[a] - skillProfile[b])[0];
  const weakestScore = skillProfile[weakest];
  const recommendation = measuredKeys.length === 0
    ? 'Analyze a few more games — including endgames and low-clock positions — to unlock a reliable rating-relative focus.'
    : weakestScore >= 66
      ? `No glaring weakness in your band yet — ${labels[weakest].toLowerCase()} (${weakestScore}/100) is your lowest measured axis.`
      : `${labels[weakest]} is your focus. ${advice[weakest]}`;

  return {
    gamesCount: games.length,
    avgAccuracy,
    avgEstimatedElo,
    record: { wins, draws, losses },
    skillProfile,
    openings,
    phaseStats,
    timeTrouble,
    clockLeaks: {
      impulseBlunders,
      timeTroubleBlunders,
      avgTimeSpentSec: spentCountTotal > 0 ? Math.round(spentSumTotal / spentCountTotal) : 0,
      impulsePerGame,
    },
    tiltGuard: {
      buckets: tiltBuckets,
      activeWarning: consecutiveLosses >= 2,
      consecutiveLosses,
    },
    checkpoints,
    missedMotifs,
    endgameCategories,
    trend,
    ratingBand: `${band.label} (${Math.round(ratingAnchor)} anchor)`,
    brilliantCount,
    recommendation,
    bestGames,
    worstGame,
    bestAccuracy,
    avgOpponentRating: opponentRatingCount > 0 ? Math.round(opponentRatingSum / opponentRatingCount) : 0,
    giantSlayer: { wins: giantWins, games: giantGames, best: giantBest },
    comebacks,
    blownWins,
    blunderFreeGames,
    scoreByColour: {
      white: finishColour(colourAcc.w.split, colourAcc.w.accSum, colourAcc.w.scoredGames),
      black: finishColour(colourAcc.b.split, colourAcc.b.accSum, colourAcc.b.scoredGames),
    },
    currentStreak: { kind: streakKind, count: streakCount },
    openingBest,
    openingWorst,
  };
}
