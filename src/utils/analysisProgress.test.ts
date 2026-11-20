import { describe, expect, it } from 'vitest';
import {
  computeBatchProgressPercent,
  computeGameProgressFraction,
  computeSingleGamePercent,
  PASS1_TWO_PASS_WEIGHT,
} from './analysisProgress';

describe('analysisProgress', () => {
  it('progresses monotonically across Pass 1 and Pass 2 without resetting to 0', () => {
    let frac = 0;
    const history: number[] = [];

    // Pass 1: 0..40 plies
    for (let i = 0; i <= 40; i++) {
      frac = computeGameProgressFraction(i, 40, 1, true, frac);
      history.push(frac);
    }
    expect(frac).toBeCloseTo(PASS1_TWO_PASS_WEIGHT, 5);

    // Pass 2 starts at 0/10 turning points — must NOT drop below Pass 1 end!
    frac = computeGameProgressFraction(0, 10, 2, true, frac);
    expect(frac).toBeCloseTo(PASS1_TWO_PASS_WEIGHT, 5);
    history.push(frac);

    for (let k = 1; k <= 10; k++) {
      frac = computeGameProgressFraction(k, 10, 2, true, frac);
      history.push(frac);
    }
    expect(frac).toBe(1);

    // Strictly non-decreasing throughout
    for (let i = 1; i < history.length; i++) {
      expect(history[i]).toBeGreaterThanOrEqual(history[i - 1]);
    }
  });

  it('reaches 100% directly in single-pass mode', () => {
    expect(computeGameProgressFraction(20, 40, 1, false)).toBeCloseTo(0.5, 5);
    expect(computeGameProgressFraction(40, 40, 1, false)).toBe(1);
  });

  it('keeps single-game active bar visible at >= 2% while starting and caps at 99% until done', () => {
    expect(computeSingleGamePercent(0, 0, true)).toBe(2);
    expect(computeSingleGamePercent(0.5, 2, true)).toBe(50);
    expect(computeSingleGamePercent(0.996, 50, true)).toBe(99);
    expect(computeSingleGamePercent(1, 99, true)).toBe(100);
  });

  it('advances batch progress smoothly per ply across a 5-game batch without stepping backwards', () => {
    let pct = computeBatchProgressPercent(0, 5, 0, 0, true);
    expect(pct).toBe(2); // immediately visible while game 1 prepares

    // Halfway through game 1 (Pass 1)
    const midGame1 = computeGameProgressFraction(30, 60, 1, true, 0);
    pct = computeBatchProgressPercent(0, 5, midGame1, pct, true);
    expect(pct).toBeGreaterThan(2);
    expect(pct).toBeLessThan(20);

    // End of game 1 Pass 1 -> start of Pass 2
    const endPass1 = computeGameProgressFraction(60, 60, 1, true, midGame1);
    const pctEndPass1 = computeBatchProgressPercent(0, 5, endPass1, pct, true);
    const startPass2 = computeGameProgressFraction(0, 8, 2, true, endPass1);
    const pctStartPass2 = computeBatchProgressPercent(0, 5, startPass2, pctEndPass1, true);
    expect(pctStartPass2).toBeGreaterThanOrEqual(pctEndPass1);

    // Finish game 1 -> game 2 starts at 0 fraction
    const pctAfterGame1 = computeBatchProgressPercent(1, 5, 0, pctStartPass2, true);
    expect(pctAfterGame1).toBe(20);

    // Finish all 5 games
    expect(computeBatchProgressPercent(5, 5, 0, 99, true)).toBe(100);
  });
});
