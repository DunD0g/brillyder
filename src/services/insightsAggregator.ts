import type {
  AccuracyTrendPoint,
  AnalyzedGame,
  AnalyzedPly,
  ClockBucketStats,
  ColourSplit,
  GameHighlight,
  MultiGameInsights,
  OpeningStat,
  PhaseBlunderStats,
  PlayerColor,
} from '../types/chess';
import { clamp } from '../utils/chessMath';
import { resultForUser, resolveUserColor } from '../utils/player';

interface RatingBand {
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

const RATING_BANDS: RatingBand[] = [
  { label: 'Beginner', min: 0, max: 1000, expected: { openingAcc: 70, midAcc: 64, endAcc: 60, conversion: 42, resilience: 42, lowClockAcc: 58 } },
  { label: 'Novice', min: 1000, max: 1300, expected: { openingAcc: 76, midAcc: 71, endAcc: 67, conversion: 50, resilience: 50, lowClockAcc: 64 } },
  { label: 'Intermediate', min: 1300, max: 1600, expected: { openingAcc: 80, midAcc: 76, endAcc: 72, conversion: 56, resilience: 56, lowClockAcc: 69 } },
  { label: 'Advanced', min: 1600, max: 1900, expected: { openingAcc: 84, midAcc: 81, endAcc: 77, conversion: 62, resilience: 62, lowClockAcc: 74 } },
  { label: 'Expert', min: 1900, max: 2200, expected: { openingAcc: 88, midAcc: 85, endAcc: 82, conversion: 68, resilience: 68, lowClockAcc: 79 } },
  { label: 'Master', min: 2200, max: 4000, expected: { openingAcc: 91, midAcc: 89, endAcc: 87, conversion: 74, resilience: 74, lowClockAcc: 83 } },
];

function bandForRating(rating: number): RatingBand {
  return RATING_BANDS.find((b) => rating >= b.min && rating < b.max) ?? RATING_BANDS[2];
}

/** Scores a raw metric as 50 = exactly typical for the player's rating band. */
function relativeScore(raw: number, expected: number, spread: number): number {
  return clamp(Math.round(50 + ((raw - expected) / spread) * 34), 10, 99);
}

function emptyPhase(phase: 'Opening' | 'Middlegame' | 'Endgame'): PhaseBlunderStats {
  return { phase, moves: 0, inaccuracies: 0, mistakes: 0, blunders: 0, blunderRatePer10Moves: 0, accuracy: 0 };
}

function emptyClockBuckets(): ClockBucketStats[] {
  return [
    { label: '<30s', clockLimit: 30, moves: 0, mistakes: 0, blunders: 0, errorsPer10Moves: 0, accuracy: 0 },
    { label: '30–60s', clockLimit: 60, moves: 0, mistakes: 0, blunders: 0, errorsPer10Moves: 0, accuracy: 0 },
    { label: '1–3m', clockLimit: 180, moves: 0, mistakes: 0, blunders: 0, errorsPer10Moves: 0, accuracy: 0 },
    { label: '>3m', clockLimit: Number.POSITIVE_INFINITY, moves: 0, mistakes: 0, blunders: 0, errorsPer10Moves: 0, accuracy: 0 },
  ];
}

function emptyColour(): ColourSplit {
  return { games: 0, wins: 0, draws: 0, losses: 0, winRate: 0, accuracy: 0 };
}

function finishColour(split: ColourSplit, accuracySum: number): ColourSplit {
  return {
    ...split,
    winRate: split.games > 0 ? Math.round(((split.wins + split.draws * 0.5) / split.games) * 100) : 0,
    accuracy: split.games > 0 ? Number((accuracySum / split.games).toFixed(1)) : 0,
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
  const resultBonus = input.result === 'W' ? 18 : input.result === 'D' ? 4 : -14;
  const ratingGap = input.opponentRating > 0 && input.userRating > 0 ? input.opponentRating - input.userRating : 0;
  const opponentBonus = clamp(ratingGap / 12, -6, 8);
  return Number((input.accuracy + resultBonus + opponentBonus + Math.min(6, input.brilliants * 3) - Math.min(8, input.blunders * 2)).toFixed(1));
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
  const highlights: GameHighlight[] = [];
  const colourAcc: Record<PlayerColor, { split: ColourSplit; accSum: number }> = {
    w: { split: emptyColour(), accSum: 0 },
    b: { split: emptyColour(), accSum: 0 },
  };

  const openMap = new Map<string, { name: string; eco: string; games: number; wins: number; draws: number; losses: number; accSum: number }>();
  const phases: Record<'opening' | 'middlegame' | 'endgame', AnalyzedPly[]> = { opening: [], middlegame: [], endgame: [] };
  const clockMoves: AnalyzedPly[] = [];

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

    const result = resultForUser(ag.game, uc);
    if (result === 'W') wins++; else if (result === 'D') draws++; else losses++;

    const userRating = (uc === 'w' ? ag.game.white.rating : ag.game.black.rating) ?? 0;
    const opponentRating = (uc === 'w' ? ag.game.black.rating : ag.game.white.rating) ?? 0;
    const opponentName = uc === 'w' ? ag.game.black.name : ag.game.white.name;
    if (opponentRating > 0) {
      opponentRatingSum += opponentRating;
      opponentRatingCount++;
    }

    const rawOpen = ag.openingLineDetected || ag.game.openingName || 'Unknown Opening';
    const family = rawOpen.includes(':') ? rawOpen.slice(0, rawOpen.indexOf(':')).trim() : rawOpen.trim();
    const bucket = openMap.get(family) ?? { name: family, eco: ag.game.openingEco || '', games: 0, wins: 0, draws: 0, losses: 0, accSum: 0 };
    bucket.games++;
    bucket.accSum += sum.accuracy;
    if (result === 'W') bucket.wins++; else if (result === 'D') bucket.draws++; else bucket.losses++;
    openMap.set(family, bucket);

    const colour = colourAcc[uc];
    colour.split.games++;
    colour.accSum += sum.accuracy;
    if (result === 'W') colour.split.wins++; else if (result === 'D') colour.split.draws++; else colour.split.losses++;

    let hadClearAdvantage = false;
    let userBrilliants = 0;
    let userBlunders = 0;
    let userGreats = 0;
    let firstBrilliantPly = 0;
    let firstGreatPly = 0;
    let minWp = uc === 'w' ? ag.initialEval.winPercentWhite : 100 - ag.initialEval.winPercentWhite;
    let maxWp = minWp;

    for (const p of ag.plies) {
      const wpAll = uc === 'w' ? p.evalBefore.winPercentWhite : 100 - p.evalBefore.winPercentWhite;
      const wpAfter = uc === 'w' ? p.evalAfter.winPercentWhite : 100 - p.evalAfter.winPercentWhite;
      minWp = Math.min(minWp, wpAll, wpAfter);
      maxWp = Math.max(maxWp, wpAll, wpAfter);

      if (p.color !== uc) continue;
      phases[p.phase].push(p);
      if (p.clockSeconds !== undefined) clockMoves.push(p);
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
      const wp = uc === 'w' ? p.evalBefore.winPercentWhite : 100 - p.evalBefore.winPercentWhite;
      if (wp >= 68) hadClearAdvantage = true;
      if (wp >= 20 && wp <= 45) {
        defMoves++;
        if (p.winLoss <= 10) heldDef++;
      }
      if (p.secondBestGapWin >= 8 || p.classification === 'brilliant' || p.classification === 'great') {
        sharpTot++;
        if (p.winLoss <= 10) sharpOk++;
      }
    }
    if (hadClearAdvantage) {
      winPos++;
      if (result === 'W') convWinPos++;
    }

    if (result === 'W' && minWp <= 20) comebacks++;
    if (result === 'L' && maxWp >= 80) blownWins++;
    if (userBlunders === 0) blunderFreeGames++;
    bestAccuracy = Math.max(bestAccuracy, sum.accuracy);

    const highlightPly = firstBrilliantPly || firstGreatPly || ag.plies.length;
    const score = gameHighlightScore({
      accuracy: sum.accuracy,
      result,
      userRating,
      opponentRating,
      brilliants: userBrilliants,
      blunders: userBlunders,
    });
    const reasonBits = [`${sum.accuracy.toFixed(1)}% accuracy`];
    if (result === 'W' && opponentRating > 0) reasonBits.push(`beat ${opponentRating}`);
    if (userBrilliants > 0) reasonBits.push(`${userBrilliants} !!`);
    if (userGreats > 0) reasonBits.push(`${userGreats} great`);
    if (userBlunders === 0) reasonBits.push('0 blunders');
    const highlight: GameHighlight = {
      gameId: ag.id,
      opponent: opponentName,
      opponentRating,
      userRating,
      userColor: uc,
      result,
      accuracy: sum.accuracy,
      opening: rawOpen,
      playedAt: ag.game.createdAt,
      brilliants: userBrilliants,
      blunders: userBlunders,
      score,
      highlightPly,
      reason: reasonBits.join(' · '),
    };
    highlights.push(highlight);

    if (userRating > 0 && opponentRating >= userRating + 50) {
      giantGames++;
      if (result === 'W') {
        giantWins++;
        if (!giantBest || opponentRating > giantBest.opponentRating) giantBest = highlight;
      }
    }
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
    .map((o) => ({ ...o, winRate: Math.round(((o.wins + o.draws * 0.5) / o.games) * 100), avgAccuracy: Number((o.accSum / o.games).toFixed(1)) }))
    .sort((a, b) => b.games - a.games || b.winRate - a.winRate);

  const bestGames = highlights.slice().sort((a, b) => b.score - a.score).slice(0, 3);
  const worstGame = highlights.slice().sort((a, b) => a.score - b.score)[0] ?? null;
  const byDate = highlights.slice().sort((a, b) => b.playedAt - a.playedAt);
  const latestResult = byDate[0]?.result;
  const streakKind: 'W' | 'D' | 'L' | 'none' = latestResult ?? 'none';
  let streakCount = 0;
  if (latestResult) {
    for (const h of byDate) {
      if (h.result !== latestResult) break;
      streakCount++;
    }
  }
  const openingPool = openings.filter((o) => o.games >= 2);
  const ratedOpenings = openingPool.length > 0 ? openingPool : openings;
  const openingBest = ratedOpenings.slice().sort((a, b) => b.winRate - a.winRate || b.avgAccuracy - a.avgAccuracy)[0] ?? null;
  const openingWorst = ratedOpenings.length > 1
    ? ratedOpenings.slice().sort((a, b) => a.winRate - b.winRate || a.avgAccuracy - b.avgAccuracy)[0] ?? null
    : null;

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

  // Only score an axis when there is a real sample; otherwise leave it at the
  // band-neutral 50 instead of extrapolating from an unrelated phase.
  const measured: Record<'openings' | 'tactics' | 'endgames' | 'conversion' | 'resilience' | 'timeManagement', boolean> = {
    openings: phases.opening.length >= 4,
    tactics: sharpTot >= 4,
    endgames: phases.endgame.length >= 4,
    conversion: winPos >= 2,
    resilience: defMoves >= 4,
    timeManagement: lowClockMoves.length >= 5,
  };

  const skillProfile = {
    openings: measured.openings ? relativeScore(openingAcc, exp.openingAcc, 10) : 50,
    tactics: measured.tactics ? relativeScore(tacticsRaw, exp.midAcc + 2, 14) : 50,
    endgames: measured.endgames ? relativeScore(endAcc, exp.endAcc, 11) : 50,
    conversion: measured.conversion ? relativeScore(conversionRaw, exp.conversion, 22) : 50,
    resilience: measured.resilience ? relativeScore(resilienceRaw, exp.resilience, 22) : 50,
    timeManagement: measured.timeManagement ? relativeScore(lowClockAcc, exp.lowClockAcc, 10) : 50,
  };

  const trend: AccuracyTrendPoint[] = games
    .slice()
    .sort((a, b) => a.game.createdAt - b.game.createdAt)
    .slice(-12)
    .map((ag) => {
      const uc = resolveUserColor(ag.game, username);
      const sum = uc === 'w' ? ag.whiteSummary : ag.blackSummary;
      const opponent = uc === 'w' ? ag.game.black.name : ag.game.white.name;
      return {
        date: ag.game.createdAt,
        accuracy: sum.accuracy,
        result: resultForUser(ag.game, uc),
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
    endgames: `Endgame technique is your biggest lever (${skillProfile.endgames}/100 vs the ${band.label} band). Drill rook-and-pawn conversions and play them out against the bot.`,
    tactics: `Tactical sharpness (${skillProfile.tactics}/100) trails your band. Warm up with 10 forced-mate puzzles before playing, then blunder-check every capture.`,
    conversion: `You convert ${conversionRaw.toFixed(0)}% of clear advantages. Once +2.0, simplify: trade queens, activate the rook, and avoid unnecessary pawn pushes.`,
    openings: `Your opening accuracy is ${openingAcc.toFixed(0)}%. Trim your repertoire to two systems per colour and review the first deviation in each loss.`,
    resilience: `Defensive resilience (${skillProfile.resilience}/100) — when worse, prioritise king safety, blockading, and active counterplay over passive defence.`,
    timeManagement: `Time management: low-clock accuracy is ${lowClockAcc.toFixed(0)}%. Bank 20% of your clock before move 20 and pre-move only forced recaptures.`,
  };
  const measuredKeys = (Object.keys(skillProfile) as Array<keyof typeof skillProfile>).filter((k) => measured[k]);
  const focusKeys = measuredKeys.length > 0 ? measuredKeys : (Object.keys(skillProfile) as Array<keyof typeof skillProfile>);
  const weakest = focusKeys.sort((a, b) => skillProfile[a] - skillProfile[b])[0];
  const weakestScore = skillProfile[weakest];
  const recommendation = measuredKeys.length === 0
    ? 'Analyze a few more games — including endgames and low-clock positions — to unlock a reliable rating-relative focus.'
    : weakestScore >= 66
      ? `No glaring weakness in your band yet — ${labels[weakest].toLowerCase()} (${weakestScore}/100) is your lowest measured axis. Analyze more games for a sharper read.`
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
      white: finishColour(colourAcc.w.split, colourAcc.w.accSum),
      black: finishColour(colourAcc.b.split, colourAcc.b.accSum),
    },
    currentStreak: { kind: streakKind, count: streakCount },
    openingBest,
    openingWorst,
  };
}
