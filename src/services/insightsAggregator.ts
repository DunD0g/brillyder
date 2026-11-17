import type { AnalyzedGame, AnalyzedPly, MultiGameInsights, OpeningStat, PhaseBlunderStats, PlayerColor } from '../types/chess';
import { clamp } from '../utils/chessMath';

function userColorFor(ag: AnalyzedGame, username: string): PlayerColor {
  if (ag.game.userColor) return ag.game.userColor;
  return ag.game.black.name.toLowerCase() === username.trim().toLowerCase() ? 'b' : 'w';
}

export function computeMultiGameInsights(games: AnalyzedGame[], username: string): MultiGameInsights {
  if (games.length === 0) {
    return {
      gamesCount: 0, avgAccuracy: 0, avgEstimatedElo: 0, record: { wins: 0, draws: 0, losses: 0 },
      skillProfile: { openings: 50, tactics: 50, endgames: 50, conversion: 50, resilience: 50 },
      openings: [],
      phaseStats: [
        { phase: 'Opening', moves: 0, inaccuracies: 0, mistakes: 0, blunders: 0, blunderRatePer10Moves: 0, accuracy: 0 },
        { phase: 'Middlegame', moves: 0, inaccuracies: 0, mistakes: 0, blunders: 0, blunderRatePer10Moves: 0, accuracy: 0 },
        { phase: 'Endgame', moves: 0, inaccuracies: 0, mistakes: 0, blunders: 0, blunderRatePer10Moves: 0, accuracy: 0 },
      ],
      recommendation: 'Analyze at least 2 games to populate your BrillyDer skill radar.',
    };
  }

  let accSum = 0, eloSum = 0, wins = 0, draws = 0, losses = 0;
  let winPos = 0, convWinPos = 0, defMoves = 0, heldDef = 0, sharpTot = 0, sharpOk = 0;
  const openMap = new Map<string, { name: string; eco: string; games: number; wins: number; draws: number; losses: number; accSum: number }>();
  const phases: Record<'opening' | 'middlegame' | 'endgame', AnalyzedPly[]> = { opening: [], middlegame: [], endgame: [] };

  for (const ag of games) {
    const uc = userColorFor(ag, username);
    const sum = uc === 'w' ? ag.whiteSummary : ag.blackSummary;
    accSum += sum.accuracy;
    eloSum += sum.estimatedElo;
    const res = ag.game.resultString;
    const isWin = (uc === 'w' && res === '1-0') || (uc === 'b' && res === '0-1');
    const isDraw = res === '1/2-1/2';
    if (isWin) wins++; else if (isDraw) draws++; else losses++;

    const rawOpen = ag.openingLineDetected || ag.game.openingName || 'Unknown Opening';
    const family = rawOpen.includes(':') ? rawOpen.slice(0, rawOpen.indexOf(':')).trim() : rawOpen.trim();
    const b = openMap.get(family) ?? { name: family, eco: ag.game.openingEco || '', games: 0, wins: 0, draws: 0, losses: 0, accSum: 0 };
    b.games++; b.accSum += sum.accuracy;
    if (isWin) b.wins++; else if (isDraw) b.draws++; else b.losses++;
    openMap.set(family, b);

    let hadClearAdv = false;
    for (const p of ag.plies.filter((x) => x.color === uc)) {
      phases[p.phase].push(p);
      const wp = uc === 'w' ? p.evalBefore.winPercentWhite : 100 - p.evalBefore.winPercentWhite;
      if (wp >= 68) hadClearAdv = true;
      if (wp >= 20 && wp <= 45) { defMoves++; if (p.winLoss <= 10) heldDef++; }
      if (p.secondBestGapWin >= 8 || p.classification === 'brilliant' || p.classification === 'great') {
        sharpTot++; if (p.winLoss <= 10) sharpOk++;
      }
    }
    if (hadClearAdv) { winPos++; if (isWin) convWinPos++; }
  }

  const mkPhase = (label: 'Opening' | 'Middlegame' | 'Endgame', list: AnalyzedPly[]): PhaseBlunderStats => {
    if (list.length === 0) return { phase: label, moves: 0, inaccuracies: 0, mistakes: 0, blunders: 0, blunderRatePer10Moves: 0, accuracy: 0 };
    let inac = 0, mis = 0, blun = 0, acc = 0;
    for (const p of list) {
      acc += p.accuracy;
      if (p.classification === 'inaccuracy') inac++; else if (p.classification === 'mistake') mis++; else if (p.classification === 'blunder') blun++;
    }
    return {
      phase: label, moves: list.length, inaccuracies: inac, mistakes: mis, blunders: blun,
      blunderRatePer10Moves: Number((((mis + blun) / list.length) * 10).toFixed(2)),
      accuracy: Number((acc / list.length).toFixed(1)),
    };
  };

  const phaseStats = [mkPhase('Opening', phases.opening), mkPhase('Middlegame', phases.middlegame), mkPhase('Endgame', phases.endgame)];
  const openings: OpeningStat[] = Array.from(openMap.values())
    .map((o) => ({ ...o, winRate: Math.round(((o.wins + o.draws * 0.5) / o.games) * 100), avgAccuracy: Number((o.accSum / o.games).toFixed(1)) }))
    .sort((a, b) => b.games - a.games || b.winRate - a.winRate);

  const skillProfile = {
    openings: phaseStats[0].moves > 0 ? clamp(Math.round(phaseStats[0].accuracy), 25, 99) : 65,
    tactics: sharpTot > 0 ? clamp(Math.round((sharpOk / sharpTot) * 100), 25, 99) : clamp(Math.round(phaseStats[1].accuracy || 65), 25, 99),
    endgames: phaseStats[2].moves > 0 ? clamp(Math.round(phaseStats[2].accuracy), 25, 99) : 65,
    conversion: winPos > 0 ? clamp(Math.round((convWinPos / winPos) * 100), 25, 99) : 70,
    resilience: defMoves > 0 ? clamp(Math.round((heldDef / defMoves) * 100), 25, 99) : 68,
  };

  const weakest = Object.entries(skillProfile).sort((a, b) => a[1] - b[1])[0][0];
  const recMap: Record<string, string> = {
    endgames: `Endgame accuracy (${skillProfile.endgames}/100) is your top lever — play out critical endgames vs. the 1500 Elo bot.`,
    tactics: `Sharp tactics (${skillProfile.tactics}/100) — drill ?! and ?? positions with Retry Move to spot forks and checks first.`,
    conversion: `Advantage conversion (${skillProfile.conversion}%) — once ahead +2.0, trade queens and eliminate counterplay.`,
    openings: `Opening precision (${skillProfile.openings}/100) — review early book deviations in your core repertoire.`,
    resilience: `Defensive grit (${skillProfile.resilience}/100) — prioritize king safety and active piece counterplay when worse.`,
  };

  return {
    gamesCount: games.length,
    avgAccuracy: Number((accSum / games.length).toFixed(1)),
    avgEstimatedElo: Math.round(eloSum / games.length),
    record: { wins, draws, losses },
    skillProfile,
    openings,
    phaseStats,
    recommendation: recMap[weakest] || 'Keep reviewing mistakes right after games.',
  };
}
