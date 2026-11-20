import type { AnalyzedGame, MistakeProgressRecord, MistakePuzzle, PlayerColor } from '../types/chess';
import type { FsrsOpeningCard, OpeningCourse, WoodpeckerCycleRecord } from '../types/openings';
import { hydrateCourseCards, isCardDue } from '../lib/fsrsOpening';
import { extractBlownLeadPositions, type BlownLeadPosition } from './advantageConversion';
import {
  getCooldownRemainingMs,
  isWoodpeckerCycleMastered,
  selectSolvableWoodpeckerPuzzles,
} from './woodpeckerCycles';

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
  stage3OnCooldown?: boolean;
  stage3CooldownRemainingMs?: number;
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
  /** Present ONLY when this opening check is a real persisted due FSRS card to grade. */
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

function localDaySeed(nowMs: number): number {
  const d = new Date(nowMs);
  return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();
}

function pickWithoutDuplicates(
  primary: MistakePuzzle[],
  usedIds: Set<string>,
  quota: number,
  fallbackPool: MistakePuzzle[] = primary
): MistakePuzzle[] {
  const chosen: MistakePuzzle[] = [];
  for (const p of primary) {
    if (chosen.length >= quota) break;
    if (usedIds.has(p.id)) continue;
    chosen.push(p);
    usedIds.add(p.id);
  }
  // Only allow overlap with earlier stages if the user's deck is too small to fill the stage
  if (chosen.length < quota) {
    const chosenIds = new Set(chosen.map((p) => p.id));
    for (const p of fallbackPool) {
      if (chosen.length >= quota) break;
      if (chosenIds.has(p.id)) continue;
      chosen.push(p);
      chosenIds.add(p.id);
    }
  }
  return chosen;
}

export function buildDailyWorkoutPlan(params: {
  duration: DailyDurationMinutes;
  fsrsCards: FsrsOpeningCard[];
  deck: MistakePuzzle[];
  analyzedGames: AnalyzedGame[];
  username: string;
  activeCycle: WoodpeckerCycleRecord | null;
  convertedIds?: string[];
  mistakeProgress?: Record<string, MistakeProgressRecord>;
  daySeed?: number;
  nowMs?: number;
}): DailyWorkoutPlan {
  const { duration, fsrsCards, deck, analyzedGames, username, activeCycle, convertedIds, mistakeProgress } = params;
  const nowMs = params.nowMs ?? Date.now();
  const quotas = QUOTAS_BY_DURATION[duration];
  const convertedSet = new Set(convertedIds ?? []);

  // Helper to prioritize unsolved mistakes ahead of already mastered ones
  const preferUnsolved = (list: MistakePuzzle[]) => {
    if (!mistakeProgress) return list;
    return list.slice().sort((a, b) => {
      const sa = mistakeProgress[a.id]?.solved ? 1 : 0;
      const sb = mistakeProgress[b.id]?.solved ? 1 : 0;
      if (sa !== sb) return sa - sb;
      return b.winLoss - a.winLoss;
    });
  };

  // Stage 1: Due Opening FSRS (prioritize game-deviation boosts)
  const stage1Cards = fsrsCards
    .filter((c) => isCardDue(c, nowMs))
    .sort((a, b) => {
      const devDiff = (b.source === 'game-deviation' ? 1 : 0) - (a.source === 'game-deviation' ? 1 : 0);
      if (devDiff !== 0) return devDiff;
      return a.dueAt - b.dueAt;
    })
    .slice(0, quotas.openingDue);

  // Stage 3 (planned first so the Frozen Woodpecker Cycle stays 100% faithful to its frozen set,
  // while Stages 2 & 4 avoid handing the user back-to-back duplicate puzzles in the same sitting!):
  const deckById = new Map(deck.map((p) => [p.id, p]));
  let stage3Woodpecker: MistakePuzzle[] = [];
  let stage3OnCooldown = false;
  let stage3CooldownRemainingMs = 0;

  if (activeCycle && activeCycle.puzzleIds.length > 0 && !isWoodpeckerCycleMastered(activeCycle)) {
    const remainingCooldown = getCooldownRemainingMs(activeCycle, nowMs);
    if (remainingCooldown > 0) {
      // Honor the 24–48h consolidation rest instead of silently drilling a resting cycle
      stage3OnCooldown = true;
      stage3CooldownRemainingMs = remainingCooldown;
    } else {
      const remainingIds = activeCycle.puzzleIds.filter((id) => !(id in activeCycle.activeAttemptedIds));
      const poolIds = remainingIds.length > 0 ? remainingIds : activeCycle.puzzleIds;
      stage3Woodpecker = poolIds
        .map((id) => deckById.get(id))
        .filter((p): p is MistakePuzzle => Boolean(p))
        .slice(0, quotas.woodpecker);
    }
  }

  const usedInSession = new Set<string>(stage3Woodpecker.map((p) => p.id));

  // Stage 2: Blunder Rewind ("Worst First" from last 14 days, deduplicated against today's Stage 3 slice)
  const recentCutoff = nowMs - FOURTEEN_DAYS_MS;
  const recentWorst = preferUnsolved(
    deck.filter((p) => p.playedAt >= recentCutoff).sort((a, b) => b.winLoss - a.winLoss)
  );
  const allWorst = preferUnsolved([...deck].sort((a, b) => b.winLoss - a.winLoss));
  const stage2Primary = recentWorst.length >= 2 ? recentWorst : allWorst;
  const stage2Blunders = pickWithoutDuplicates(stage2Primary, usedInSession, quotas.blunderRewind, allWorst);

  // If no active Woodpecker cycle (and not on cooldown), fill Stage 3 from solvable pool excluding Stage 2!
  if (stage3Woodpecker.length === 0 && !stage3OnCooldown) {
    const solvable = selectSolvableWoodpeckerPuzzles(deck, 30);
    stage3Woodpecker = pickWithoutDuplicates(solvable, usedInSession, quotas.woodpecker, solvable);
  }

  // Stage 4: Targeted Weakness Drill rotation (Conversion -> Endgame -> Missed Motif)
  const allBlownLeads = extractBlownLeadPositions(analyzedGames, username);
  const unconvertedBlownLeads = allBlownLeads.filter((b) => !convertedSet.has(b.id));
  const blownLeads = unconvertedBlownLeads.length > 0 ? unconvertedBlownLeads : allBlownLeads;
  const endgamePuzzles = preferUnsolved(
    deck.filter((p) => p.phase === 'endgame').sort((a, b) => b.winLoss - a.winLoss)
  );

  // Find most missed tactical motif
  const motifCounts = new Map<string, MistakePuzzle[]>();
  for (const p of deck) {
    if (!p.tacticalTag || p.tacticalTag === 'Suboptimal' || p.tacticalTag === 'Eval Collapse') continue;
    const list = motifCounts.get(p.tacticalTag) ?? [];
    list.push(p);
    motifCounts.set(p.tacticalTag, list);
  }
  const topMotifEntry = Array.from(motifCounts.entries()).sort((a, b) => b[1].length - a[1].length)[0] ?? null;

  const dayBucket = params.daySeed ?? localDaySeed(nowMs);
  const rotationOrder: Stage4Focus[] = ['conversion', 'endgame', 'motif'];
  const preferred = rotationOrder[Math.abs(dayBucket) % 3];

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
    stage4Puzzles = pickWithoutDuplicates(endgamePuzzles, usedInSession, quotas.weakness, endgamePuzzles);
  } else if (topMotifEntry) {
    stage4Focus = 'motif';
    stage4FocusLabel = `Missed Motif: ${topMotifEntry[0]}`;
    const sortedMotif = preferUnsolved(topMotifEntry[1]);
    stage4Puzzles = pickWithoutDuplicates(sortedMotif, usedInSession, quotas.weakness, sortedMotif);
  } else {
    stage4Focus = 'motif';
    stage4FocusLabel = 'Sharp Tactic Closer';
    stage4Puzzles = pickWithoutDuplicates(allWorst, usedInSession, quotas.weakness, allWorst);
  }

  return {
    duration,
    quotas,
    stage1Cards,
    stage2Blunders,
    stage3Woodpecker,
    stage3OnCooldown,
    stage3CooldownRemainingMs,
    stage4Focus,
    stage4FocusLabel,
    stage4Conversion,
    stage4Puzzles,
  };
}

/**
 * Composes the 60-Second "Gravity Check" pre-game warmup:
 * - 3 timed 8-second hanging-piece / tactic flashes (rotated per run so they aren't always identical)
 * - 2 due FSRS opening moves (falling back to read-only starter course previews that NEVER overwrite real FSRS history!)
 */
export function buildGravityCheckItems(params: {
  deck: MistakePuzzle[];
  fsrsCards: FsrsOpeningCard[];
  courses: OpeningCourse[];
  nowMs?: number;
  sessionSeed?: number;
}): GravityFlashItem[] {
  const { deck, fsrsCards, courses } = params;
  const nowMs = params.nowMs ?? Date.now();
  const seed = params.sessionSeed ?? Math.floor(nowMs / 60_000);
  const items: GravityFlashItem[] = [];

  // 1. Pick 3 crisp hanging-piece / tactical puzzles from user deck with deterministic rotation
  const sharpPool = deck.filter(
    (p) => p.winLoss >= 18 || /Hanging|Fork|Mate|Back-?Rank|Pin|Skewer|Deflection/i.test(p.tacticalTag)
  );
  const sharpDeck: MistakePuzzle[] = [];
  if (sharpPool.length > 0) {
    const startOffset = Math.abs(seed) % sharpPool.length;
    for (let i = 0; i < Math.min(3, sharpPool.length); i++) {
      sharpDeck.push(sharpPool[(startOffset + i) % sharpPool.length]);
    }
  }

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

  // 2. Pick 2 due FSRS opening moves; fallback previews omit `card` so they NEVER overwrite real FSRS history!
  const dueCards = fsrsCards
    .filter((c) => isCardDue(c, nowMs))
    .sort((a, b) => a.dueAt - b.dueAt)
    .slice(0, 2);

  const openingPicks: Array<{ card: FsrsOpeningCard; isPersistedDue: boolean }> = dueCards.map((card) => ({
    card,
    isPersistedDue: true,
  }));

  if (openingPicks.length < 2) {
    const existingById = new Map(fsrsCards.map((c) => [c.cardId, c]));
    const pickedIds = new Set(openingPicks.map((p) => p.card.cardId));
    for (const course of courses) {
      // Pass existingById and unlocked: false so fallback previews never fabricate fresh cards overwriting IDB
      const hydrated = hydrateCourseCards(course, existingById, { unlocked: false });
      for (const card of hydrated) {
        if (openingPicks.length >= 2) break;
        if (card.ply < 2 || pickedIds.has(card.cardId)) continue;
        pickedIds.add(card.cardId);
        openingPicks.push({ card, isPersistedDue: false });
      }
      if (openingPicks.length >= 2) break;
    }
  }

  for (const { card, isPersistedDue } of openingPicks.slice(0, 2)) {
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
      card: isPersistedDue ? card : undefined,
    });
  }

  return items;
}
