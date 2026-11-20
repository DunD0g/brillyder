import { describe, expect, it } from 'vitest';
import { Chess } from 'chess.js';
import starterCoursesRaw from '../data/starterCourses.json';
import type { OpeningCourse } from '../types/openings';
import {
  buildDailyWorkoutPlan,
  buildGravityCheckItems,
  FALLBACK_GRAVITY_FLASHES,
} from './dailyCoach';

const courses = starterCoursesRaw as OpeningCourse[];

describe('dailyCoach & Gravity Check', () => {
  it('verifies every fallback Gravity Check flash has a 100% legal chess.js UCI/SAN move', () => {
    for (const flash of FALLBACK_GRAVITY_FLASHES) {
      const c = new Chess(flash.fen);
      const from = flash.expectedUci.slice(0, 2);
      const to = flash.expectedUci.slice(2, 4);
      const mv = c.move({ from, to });
      expect(mv, `Illegal fallback move ${flash.expectedUci} in ${flash.id}`).toBeTruthy();
      expect(mv.san).toBe(flash.expectedSan);
    }
  });

  it('builds a 5-step Gravity Check (3 tactic flashes + 2 opening moves) even with empty user history', () => {
    const items = buildGravityCheckItems({
      deck: [],
      fsrsCards: [],
      courses,
    });
    expect(items).toHaveLength(5);
    expect(items.filter((i) => i.kind === 'tactic')).toHaveLength(3);
    expect(items.filter((i) => i.kind === 'opening')).toHaveLength(2);
    for (const item of items) {
      const c = new Chess(item.fen);
      const mv = c.move({
        from: item.expectedUci.slice(0, 2),
        to: item.expectedUci.slice(2, 4),
      });
      expect(mv).toBeTruthy();
    }
  });

  it('scales Daily Workout quotas cleanly across 10 / 15 / 25 min presets', () => {
    const p10 = buildDailyWorkoutPlan({ duration: 10, fsrsCards: [], deck: [], analyzedGames: [], username: 'Hero', activeCycle: null });
    const p15 = buildDailyWorkoutPlan({ duration: 15, fsrsCards: [], deck: [], analyzedGames: [], username: 'Hero', activeCycle: null });
    const p25 = buildDailyWorkoutPlan({ duration: 25, fsrsCards: [], deck: [], analyzedGames: [], username: 'Hero', activeCycle: null });
    expect(p10.quotas.woodpecker).toBeLessThan(p15.quotas.woodpecker);
    expect(p15.quotas.woodpecker).toBeLessThan(p25.quotas.woodpecker);
  });
});
