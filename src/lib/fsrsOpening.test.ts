import { describe, expect, it } from 'vitest';
import { Rating } from 'ts-fsrs';
import starterCoursesRaw from '../data/starterCourses.json';
import type { OpeningCourse } from '../types/openings';
import {
  boostCardToDueNow,
  getRecallProbability,
  gradeOpeningAttempt,
  hydrateCourseCards,
  isCardDue,
  reviewFsrsOpeningCard,
} from './fsrsOpening';

const courses = starterCoursesRaw as OpeningCourse[];

describe('fsrsOpening scheduler & response-time auto-grading', () => {
  it('auto-grades response times and mistakes into Again / Hard / Good / Easy', () => {
    expect(gradeOpeningAttempt({ correct: false, responseMs: 1200 })).toEqual({
      grade: Rating.Again,
      label: 'Again',
    });
    expect(gradeOpeningAttempt({ correct: true, responseMs: 12500 })).toEqual({
      grade: Rating.Hard,
      label: 'Hard',
    });
    expect(gradeOpeningAttempt({ correct: true, responseMs: 2100, hintUsed: true })).toEqual({
      grade: Rating.Hard,
      label: 'Hard',
    });
    expect(gradeOpeningAttempt({ correct: true, responseMs: 5500 })).toEqual({
      grade: Rating.Good,
      label: 'Good',
    });
    expect(gradeOpeningAttempt({ correct: true, responseMs: 1800 })).toEqual({
      grade: Rating.Easy,
      label: 'Easy',
    });
  });

  it('hydrates all user-turn cards from starter courses with valid FEN and UCI', () => {
    for (const course of courses) {
      const cards = hydrateCourseCards(course, undefined, { unlocked: true });
      expect(cards.length).toBeGreaterThan(0);
      for (const card of cards) {
        expect(card.side).toBe(course.side);
        expect(card.expectedUci.length).toBeGreaterThanOrEqual(4);
        const turn = card.fen.split(' ')[1];
        expect(turn).toBe(course.side === 'white' ? 'w' : 'b');
      }
    }
  });

  it('schedules intervals, tracks recall probability, and survives JSON round-trip', () => {
    const london = courses[0];
    const [firstCard] = hydrateCourseCards(london, undefined, { unlocked: true });
    const t0 = new Date('2026-01-01T12:00:00.000Z');

    expect(getRecallProbability(firstCard, t0)).toBe(0);

    const easyRes = reviewFsrsOpeningCard(firstCard, { correct: true, responseMs: 1900 }, t0);
    expect(easyRes.gradeLabel).toBe('Easy');
    expect(easyRes.card.attempts).toBe(1);
    expect(easyRes.card.firstTryHits).toBe(1);
    expect(easyRes.nextDueAt).toBeGreaterThan(t0.getTime());

    // Verify JSON serialization round-trip preserves valid FSRS state
    const cloned = JSON.parse(JSON.stringify(easyRes.card));
    const recallShortlyAfter = getRecallProbability(cloned, new Date(t0.getTime() + 60_000));
    expect(recallShortlyAfter).toBeGreaterThanOrEqual(90);
    expect(recallShortlyAfter).toBeLessThanOrEqual(100);

    // Boosting a card makes it due immediately and tags game-deviation
    const boosted = boostCardToDueNow(cloned, t0);
    expect(boosted.source).toBe('game-deviation');
    expect(isCardDue(boosted, t0.getTime())).toBe(true);

    // Wrong attempt grades Again and schedules much sooner than Easy
    const againRes = reviewFsrsOpeningCard(boosted, { correct: false, responseMs: 4000 }, t0);
    expect(againRes.gradeLabel).toBe('Again');
    expect(againRes.nextDueAt).toBeLessThan(easyRes.nextDueAt);
  });
});
