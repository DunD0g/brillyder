import { Chess } from 'chess.js';
import {
  createEmptyCard,
  fsrs,
  Rating,
  State,
  type Card,
  type Grade,
} from 'ts-fsrs';
import type { FsrsOpeningCard, OpeningCourse, OpeningLine, Side } from '../types/openings';

export type OpeningGradeLabel = 'Again' | 'Hard' | 'Good' | 'Easy';

export interface OpeningAttemptInput {
  correct: boolean;
  responseMs: number;
  hintUsed?: boolean;
}

export interface OpeningReviewResult {
  card: FsrsOpeningCard;
  grade: Grade;
  gradeLabel: OpeningGradeLabel;
  nextDueAt: number;
  recallPct: number;
}

const FAST_THRESHOLD_MS = 3_000;
const SLOW_THRESHOLD_MS = 10_000;

const scheduler = fsrs({
  request_retention: 0.9,
  enable_fuzz: false,
  enable_short_term: true,
});

export function normalizeFenKey(fen: string): string {
  return fen.split(' ').slice(0, 4).join(' ');
}

export function buildOpeningCardId(courseId: string, lineId: string, ply: number, expectedUci: string): string {
  return `${courseId}::${lineId}::${ply}::${expectedUci}`;
}

export function serializeFsrsCard(card: Card): Record<string, unknown> {
  return {
    due: card.due instanceof Date ? card.due.toISOString() : new Date(card.due).toISOString(),
    stability: card.stability,
    difficulty: card.difficulty,
    scheduled_days: card.scheduled_days,
    learning_steps: card.learning_steps,
    reps: card.reps,
    lapses: card.lapses,
    state: card.state,
    ...(card.last_review
      ? { last_review: card.last_review instanceof Date ? card.last_review.toISOString() : new Date(card.last_review).toISOString() }
      : {}),
  };
}

export function deserializeFsrsCard(raw: Record<string, unknown> | undefined, fallbackNow = new Date()): Card {
  if (!raw || typeof raw !== 'object') return createEmptyCard(fallbackNow);
  const dueRaw = raw.due;
  const due = dueRaw instanceof Date
    ? dueRaw
    : typeof dueRaw === 'string' || typeof dueRaw === 'number'
      ? new Date(dueRaw)
      : fallbackNow;
  const validDue = Number.isNaN(due.getTime()) ? fallbackNow : due;

  const lastRaw = raw.last_review;
  let lastReview: Date | undefined;
  if (lastRaw instanceof Date && !Number.isNaN(lastRaw.getTime())) {
    lastReview = lastRaw;
  } else if (typeof lastRaw === 'string' || typeof lastRaw === 'number') {
    const parsed = new Date(lastRaw);
    if (!Number.isNaN(parsed.getTime())) lastReview = parsed;
  }

  return {
    due: validDue,
    stability: typeof raw.stability === 'number' && Number.isFinite(raw.stability) ? raw.stability : 0,
    difficulty: typeof raw.difficulty === 'number' && Number.isFinite(raw.difficulty) ? raw.difficulty : 0,
    scheduled_days: typeof raw.scheduled_days === 'number' && Number.isFinite(raw.scheduled_days) ? raw.scheduled_days : 0,
    learning_steps: typeof raw.learning_steps === 'number' && Number.isFinite(raw.learning_steps) ? raw.learning_steps : 0,
    reps: typeof raw.reps === 'number' && Number.isFinite(raw.reps) ? raw.reps : 0,
    lapses: typeof raw.lapses === 'number' && Number.isFinite(raw.lapses) ? raw.lapses : 0,
    state: typeof raw.state === 'number' ? (raw.state as State) : State.New,
    ...(lastReview ? { last_review: lastReview } : {}),
  };
}

/**
 * Automatic response-time grading per BrillyDer v2.0 Blueprint §1.3:
 * - Wrong move -> Again
 * - Correct on 1st try, slow (>10s) or hint used -> Hard
 * - Correct on 1st try, normal (3–10s) -> Good
 * - Correct on 1st try, instant (<3s) -> Easy
 */
export function gradeOpeningAttempt(attempt: OpeningAttemptInput): { grade: Grade; label: OpeningGradeLabel } {
  if (!attempt.correct) {
    return { grade: Rating.Again, label: 'Again' };
  }
  if (attempt.hintUsed || attempt.responseMs > SLOW_THRESHOLD_MS) {
    return { grade: Rating.Hard, label: 'Hard' };
  }
  if (attempt.responseMs < FAST_THRESHOLD_MS) {
    return { grade: Rating.Easy, label: 'Easy' };
  }
  return { grade: Rating.Good, label: 'Good' };
}

export function createFsrsOpeningCard(params: {
  courseId: string;
  lineId: string;
  side: Side;
  fen: string;
  ply: number;
  moveSequence: string[];
  expectedSan: string;
  expectedUci: string;
  source?: 'course' | 'game-deviation';
  unlocked?: boolean;
  now?: Date;
}): FsrsOpeningCard {
  const now = params.now ?? new Date();
  const empty = createEmptyCard(now);
  return {
    cardId: buildOpeningCardId(params.courseId, params.lineId, params.ply, params.expectedUci),
    courseId: params.courseId,
    lineId: params.lineId,
    side: params.side,
    fen: params.fen,
    ply: params.ply,
    moveSequence: params.moveSequence,
    expectedSan: params.expectedSan,
    expectedUci: params.expectedUci,
    fsrsState: serializeFsrsCard(empty),
    dueAt: empty.due.getTime(),
    attempts: 0,
    firstTryHits: 0,
    avgResponseMs: 0,
    source: params.source ?? 'course',
    unlocked: params.unlocked ?? false,
  };
}

/**
 * Hydrates all user-move decision points from a single OpeningLine via chess.js.
 */
export function hydrateLineCards(
  courseId: string,
  side: Side,
  line: OpeningLine,
  existingById?: Map<string, FsrsOpeningCard>,
  options: { unlocked?: boolean; now?: Date } = {}
): FsrsOpeningCard[] {
  const chess = new Chess();
  const targetColor = side === 'white' ? 'w' : 'b';
  const cards: FsrsOpeningCard[] = [];
  const prefix: string[] = [];

  for (let ply = 0; ply < line.moves.length; ply++) {
    const san = line.moves[ply];
    const fenBefore = chess.fen();
    const move = chess.move(san);
    const uci = `${move.from}${move.to}${move.promotion ?? ''}`;

    if (move.color === targetColor) {
      const cardId = buildOpeningCardId(courseId, line.id, ply, uci);
      const existing = existingById?.get(cardId);
      if (existing) {
        cards.push(existing);
      } else {
        cards.push(
          createFsrsOpeningCard({
            courseId,
            lineId: line.id,
            side,
            fen: fenBefore,
            ply,
            moveSequence: [...prefix],
            expectedSan: move.san,
            expectedUci: uci,
            source: 'course',
            unlocked: options.unlocked ?? false,
            now: options.now,
          })
        );
      }
    }
    prefix.push(move.san);
  }

  return cards;
}

/**
 * Hydrates all user-move decision points across every line of an OpeningCourse.
 */
export function hydrateCourseCards(
  course: OpeningCourse,
  existingById?: Map<string, FsrsOpeningCard>,
  options: { unlocked?: boolean; now?: Date } = {}
): FsrsOpeningCard[] {
  const out: FsrsOpeningCard[] = [];
  const seen = new Set<string>();
  for (const line of course.lines) {
    for (const card of hydrateLineCards(course.id, course.side, line, existingById, options)) {
      if (seen.has(card.cardId)) continue;
      seen.add(card.cardId);
      out.push(card);
    }
  }
  return out;
}

export function reviewFsrsOpeningCard(
  card: FsrsOpeningCard,
  attempt: OpeningAttemptInput,
  now = new Date()
): OpeningReviewResult {
  const { grade, label } = gradeOpeningAttempt(attempt);
  const currentState = deserializeFsrsCard(card.fsrsState, now);
  const scheduled = scheduler.next(currentState, now, grade);
  const nextCardState = scheduled.card;
  const attempts = card.attempts + 1;
  const firstTryHits = card.firstTryHits + (attempt.correct && !attempt.hintUsed ? 1 : 0);
  const clampedMs = Math.max(0, Math.min(120_000, Math.round(attempt.responseMs)));
  const avgResponseMs = card.attempts === 0
    ? clampedMs
    : Math.round((card.avgResponseMs * card.attempts + clampedMs) / attempts);

  const updated: FsrsOpeningCard = {
    ...card,
    unlocked: true,
    fsrsState: serializeFsrsCard(nextCardState),
    dueAt: nextCardState.due.getTime(),
    attempts,
    firstTryHits,
    avgResponseMs,
  };

  return {
    card: updated,
    grade,
    gradeLabel: label,
    nextDueAt: updated.dueAt,
    recallPct: getRecallProbability(updated, now),
  };
}

/**
 * Returns estimated recall probability (0-100%) for UI ("Signal Strength: XX%").
 * New/unreviewed cards return 0% until first review; reviewed cards use FSRS-6 retrievability.
 */
export function getRecallProbability(card: FsrsOpeningCard, now = new Date()): number {
  const state = deserializeFsrsCard(card.fsrsState, now);
  if (state.state === State.New || state.reps === 0) return 0;
  const raw = scheduler.retrievability(state, now);
  if (typeof raw !== 'number' || !Number.isFinite(raw)) return 0;
  return Math.max(0, Math.min(100, Math.round(raw * 100)));
}

export function isCardDue(card: FsrsOpeningCard, nowMs = Date.now()): boolean {
  if (!card.unlocked) return false;
  return card.dueAt <= nowMs;
}

export function boostCardToDueNow(card: FsrsOpeningCard, now = new Date()): FsrsOpeningCard {
  const state = deserializeFsrsCard(card.fsrsState, now);
  const boosted: Card = { ...state, due: now };
  return {
    ...card,
    unlocked: true,
    source: 'game-deviation',
    fsrsState: serializeFsrsCard(boosted),
    dueAt: now.getTime(),
  };
}

export function firstTryAccuracyPct(card: FsrsOpeningCard): number {
  if (card.attempts <= 0) return 0;
  return Math.round((card.firstTryHits / card.attempts) * 100);
}
