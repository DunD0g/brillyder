import type { AnalyzedGame, MistakePuzzle, PlayerColor } from '../types/chess';
import type { FsrsOpeningCard, OpeningCourse, WoodpeckerCycleRecord } from '../types/openings';
import { hydrateCourseCards, isCardDue } from '../lib/fsrsOpening';
import { extractBlownLeadPositions, type BlownLeadPosition } from './advantageConversion';
import { selectSolvableWoodpeckerPuzzles } from './woodpeckerCycles';

export type DailyDurationMinutes = 10 | 15 | 25;

export type Stage4Focus = 'conversion' | 'endgame' | 'motif';

export interface DailyWorkoutQuotas {
  openingDue: number;
  blunderRewind: number;
  woodpecker: number;
  weakness: number;
}

export interface DailyWorkoutPlan {
  duration: DailyDurationMinutes;
  quotas: DailyWorkoutQuotas;
  stage1Cards: FsrsOpeningCard[];
  stage2Blunders: MistakePuzzle[];
  stage3Woodpecker: MistakePuzzle[];
  stage4Focus: Stage4Focus;
  stage4FocusLabel: string;
  stage4Conversion: BlownLeadPosition | null;
  stage4Puzzles: MistakePuzzle[];
}

export interface GravityFlashItem {
  id: string;
  kind: 'tactic' | 'opening';
  fen: string;
  orientation: PlayerColor;
  expectedUci: string;
  expectedSan: string;
  prompt: string;
  subtitle: string;
  timeLimitSec: number;
  card?: FsrsOpeningCard;
}

const QUOTAS_BY_DURATION: Record<DailyDurationMinutes, DailyWorkoutQuotas> = {
  10: { openingDue: 5, blunderRewind: 3, woodpecker: 8, weakness: 2 },
  15: { openingDue: 7, blunderRewind: 4, woodpecker: 10, weakness: 3 },
  25: { openingDue: 10, blunderRewind: 5, woodpecker: 15, weakness: 4 },
};

/**
 * Curated chess.js-verified tactical / hanging-piece flashes used as instant
 * fallback in the 60-Second Gravity Check when the user has < 3 personal mistakes.
 */
export const FALLBACK_GRAVITY_FLASHES: Array<{
  id: string;
  fen: string;
  orientation: PlayerColor;
  expectedUci: string;
  expectedSan: string;
  prompt: string;
  subtitle: string;
}> = [
  {
    id: 'gravity-fb-1',
    fen: 'r1bqkbnr/pppp1ppp/2n5/4p3/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 0 3',
    orientation: 'w',
    expectedUci: 'd4e5',
    expectedSan: 'dxe5',
    prompt: 'Hanging central pawn — grab it fast!',
    subtitle: 'Center Capture Flash',
  },
  {
    id: 'gravity-fb-2',
    fen: 'r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4',
    orientation: 'w',
    expectedUci: 'h5f7',
    expectedSan: 'Qxf7#',
    prompt: 'Checkmate in 1 — spot the exposed f7 square!',
    subtitle: 'Mate-in-1 Flash',
  },
  {
    id: 'gravity-fb-3',
    fen: '6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1',
    orientation: 'w',
    expectedUci: 'd1d8',
    expectedSan: 'Rd8#',
    prompt: 'Back-rank checkmate — deliver the blow!',
    subtitle: 'Back-Rank Flash',
  },
  {
    id: 'gravity-fb-4',
    fen: 'r2qk2r/ppp2ppp/2n2n2/3pp3/1b1P4/2NBPN2/PPP2PPP/R1BQK2R w KQkq - 0 6',
    orientation: 'w',
    expectedUci: 'd4e5',
    expectedSan: 'dxe5',
    prompt: 'Win the hanging e5 pawn with tempo on f6!',
    subtitle: 'Hanging Piece Flash',
  },
];

const FOURTEEN_DAYS_MS = 14 * 24 * 60 * 60 * 1000;

export function buildDailyWorkoutPlan(params: {
  duration: DailyDurationMinutes;
  fsrsCards: FsrsOpeningCard[];
  deck: MistakePuzzle[];
  analyzedGames: AnalyzedGame[];
  username: string;
  activeCycle: WoodpeckerCycleRecord | null;
  daySeed?: number;
  nowMs?: number;
}): DailyWorkoutPlan {
  const { duration, fsrsCards, deck, analyzedGames, username, activeCycle } = params;
  const nowMs = params.nowMs ?? Date.now();
  const quotas = QUOTAS_BY_DURATION[duration];

  // Stage 1: Due Opening FSRS (prioritize game-deviation boosts)
  const stage1Cards = fsrsCards
    .filter((c) => isCardDue(c, nowMs))
    .sort((a, b) => {
      const devDiff = (b.source === 'game-deviation' ? 1 : 0) - (a.source === 'game-deviation' ? 1 : 0);
      if (devDiff !== 0) return devDiff;
      return a.dueAt - b.dueAt;
    })
    .slice(0, quotas.openingDue);

  // Stage 2: Blunder Rewind ("Worst First" from last 14 days, fallback to all-time worst)
  const recentCutoff = nowMs - FOURTEEN_DAYS_MS;
  const recentWorst = deck
    .filter((p) => p.playedAt >= recentCutoff)
    .sort((a, b) => b.winLoss - a.winLoss);
  const stage2Source = recentWorst.length >= 2 ? recentWorst : [...deck].sort((a, b) => b.winLoss - a.winLoss);
  const stage2Blunders = stage2Source.slice(0, quotas.blunderRewind);

  // Stage 3: Active Frozen Woodpecker Cycle (remaining puzzles in active cycle, else solvable pool)
  const deckById = new Map(deck.map((p) => [p.id, p]));
  let stage3Woodpecker: MistakePuzzle[] = [];
  if (activeCycle && activeCycle.puzzleIds.length > 0) {
    const remainingIds = activeCycle.puzzleIds.filter((id) => !(id in activeCycle.activeAttemptedIds));
    const poolIds = remainingIds.length > 0 ? remainingIds : activeCycle.puzzleIds;
    stage3Woodpecker = poolIds
      .map((id) => deckById.get(id))
      .filter((p): p is MistakePuzzle => Boolean(p))
      .slice(0, quotas.woodpecker);
  }
  if (stage3Woodpecker.length === 0) {
    stage3Woodpecker = selectSolvableWoodpeckerPuzzles(deck, 30).slice(0, quotas.woodpecker);
  }

  // Stage 4: Targeted Weakness Drill rotation (Conversion -> Endgame -> Missed Motif)
  const blownLeads = extractBlownLeadPositions(analyzedGames, username);
  const endgamePuzzles = deck.filter((p) => p.phase === 'endgame').sort((a, b) => b.winLoss - a.winLoss);

  // Find most missed tactical motif
  const motifCounts = new Map<string, MistakePuzzle[]>();
  for (const p of deck) {
    if (!p.tacticalTag || p.tacticalTag === 'Suboptimal' || p.tacticalTag === 'Eval Collapse') continue;
    const list = motifCounts.get(p.tacticalTag) ?? [];
    list.push(p);
    motifCounts.set(p.tacticalTag, list);
  }
  const topMotifEntry = Array.from(motifCounts.entries()).sort((a, b) => b[1].length - a[1].length)[0] ?? null;

  const dayBucket = params.daySeed ?? Math.floor(nowMs / 86_400_000);
  const rotationOrder: Stage4Focus[] = ['conversion', 'endgame', 'motif'];
  const preferred = rotationOrder[dayBucket % 3];

  let stage4Focus: Stage4Focus = preferred;
  if (preferred === 'conversion' && blownLeads.length === 0) {
    stage4Focus = endgamePuzzles.length > 0 ? 'endgame' : 'motif';
  } else if (preferred === 'endgame' && endgamePuzzles.length === 0) {
    stage4Focus = blownLeads.length > 0 ? 'conversion' : 'motif';
  } else if (preferred === 'motif' && !topMotifEntry) {
    stage4Focus = blownLeads.length > 0 ? 'conversion' : 'endgame';
  }

  let stage4FocusLabel = 'Missed Motif Drill';
  let stage4Puzzles: MistakePuzzle[] = [];
  let stage4Conversion: BlownLeadPosition | null = null;

  if (stage4Focus === 'conversion' && blownLeads.length > 0) {
    stage4FocusLabel = 'Advantage Conversion';
    stage4Conversion = blownLeads[0];
  } else if (stage4Focus === 'endgame' && endgamePuzzles.length > 0) {
    stage4FocusLabel = 'Weakest Endgame Drill';
    stage4Puzzles = endgamePuzzles.slice(0, quotas.weakness);
  } else if (topMotifEntry) {
    stage4Focus = 'motif';
    stage4FocusLabel = `Missed Motif: ${topMotifEntry[0]}`;
    stage4Puzzles = topMotifEntry[1].slice(0, quotas.weakness);
  } else {
    stage4Focus = 'motif';
    stage4FocusLabel = 'Sharp Tactic Closer';
    stage4Puzzles = deck.slice(0, quotas.weakness);
  }

  return {
    duration,
    quotas,
    stage1Cards,
    stage2Blunders,
    stage3Woodpecker,
    stage4Focus,
    stage4FocusLabel,
    stage4Conversion,
    stage4Puzzles,
  };
}

/**
 * Composes the 60-Second "Gravity Check" pre-game warmup:
 * - 3 timed 8-second hanging-piece / tactic flashes
 * - 2 due FSRS opening moves (falling back to starter course critical nodes)
 */
export function buildGravityCheckItems(params: {
  deck: MistakePuzzle[];
  fsrsCards: FsrsOpeningCard[];
  courses: OpeningCourse[];
  nowMs?: number;
}): GravityFlashItem[] {
  const { deck, fsrsCards, courses } = params;
  const nowMs = params.nowMs ?? Date.now();
  const items: GravityFlashItem[] = [];

  // 1. Pick 3 crisp hanging-piece / tactical puzzles from user deck
  const sharpDeck = deck
    .filter((p) => p.winLoss >= 18 || /Hanging|Fork|Mate|Back Rank|Capture/i.test(p.tacticalTag))
    .slice(0, 3);

  for (const p of sharpDeck) {
    items.push({
      id: `gc-tactic-${p.id}`,
      kind: 'tactic',
      fen: p.beforeFen,
      orientation: p.color,
      expectedUci: p.bestMoveUci,
      expectedSan: p.bestMoveSan,
      prompt: `${p.tacticalTag} — find the best move fast!`,
      subtitle: `From vs ${p.opponentName}`,
      timeLimitSec: 8,
    });
  }

  // Pad up to 3 with verified built-in flashes
  for (const fb of FALLBACK_GRAVITY_FLASHES) {
    if (items.length >= 3) break;
    items.push({
      ...fb,
      kind: 'tactic',
      timeLimitSec: 8,
    });
  }

  // 2. Pick 2 due FSRS opening moves (or critical starter course moves if none due)
  const dueCards = fsrsCards
    .filter((c) => isCardDue(c, nowMs))
    .sort((a, b) => a.dueAt - b.dueAt)
    .slice(0, 2);

  const openingPicks: FsrsOpeningCard[] = [...dueCards];
  if (openingPicks.length < 2) {
    const existingIds = new Set(openingPicks.map((c) => c.cardId));
    for (const course of courses) {
      const hydrated = hydrateCourseCards(course, undefined, { unlocked: true });
      for (const card of hydrated) {
        if (openingPicks.length >= 2) break;
        if (card.ply < 2 || existingIds.has(card.cardId)) continue;
        existingIds.add(card.cardId);
        openingPicks.push(card);
      }
      if (openingPicks.length >= 2) break;
    }
  }

  for (const card of openingPicks.slice(0, 2)) {
    const courseName = courses.find((c) => c.id === card.courseId)?.name ?? 'Opening Repertoire';
    items.push({
      id: `gc-open-${card.cardId}`,
      kind: 'opening',
      fen: card.fen,
      orientation: card.side === 'white' ? 'w' : 'b',
      expectedUci: card.expectedUci,
      expectedSan: card.expectedSan,
      prompt: `Play your ${card.side} repertoire move!`,
      subtitle: `${courseName} · Move ${Math.floor(card.ply / 2) + 1}`,
      timeLimitSec: 12,
      card,
    });
  }

  return items;
}
