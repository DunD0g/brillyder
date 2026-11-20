import { describe, expect, it } from 'vitest';
import starterCoursesRaw from '../data/starterCourses.json';
import type { OpeningCourse } from '../types/openings';
import { detectRepertoireDeviation } from './deviationDetector';

const courses = starterCoursesRaw as OpeningCourse[];

describe('deviationDetector (Leak Patcher)', () => {
  it('detects a White user deviation in moves 1-12 and returns expected repertoire move', () => {
    // Starter London expects 2. Bf4 or 2. Nc3 (Jobava) after 1. d4 d5; playing 2. e3 deviates
    const dev = detectRepertoireDeviation({
      sanHistory: ['d4', 'd5', 'e3', 'Nf6', 'Bd3'],
      userColor: 'w',
      courses,
    });
    expect(dev).not.toBeNull();
    expect(dev?.kind).toBe('user-deviation');
    expect(dev?.ply).toBe(3);
    expect(dev?.playedSan).toBe('e3');
    expect(dev?.expectedMoves.some((m) => m.expectedSan === 'Bf4')).toBe(true);
  });

  it('detects an opponent novelty against the active repertoire', () => {
    // 1. d4 d5 2. Bf4 c6 (c6 is not covered in starter London lines)
    const dev = detectRepertoireDeviation({
      sanHistory: ['d4', 'd5', 'Bf4', 'c6', 'e3'],
      userColor: 'w',
      courses,
    });
    expect(dev).not.toBeNull();
    expect(dev?.kind).toBe('opponent-novelty');
    expect(dev?.ply).toBe(4);
    expect(dev?.playedSan).toBe('c6');
    expect(dev?.moveSequenceAfter).toEqual(['d4', 'd5', 'Bf4', 'c6']);
  });

  it('returns null when user stays in repertoire or plays a totally unrelated 1st move', () => {
    const unrelated = detectRepertoireDeviation({
      sanHistory: ['e4', 'e5', 'Nf3', 'Nc6'],
      userColor: 'w',
      courses,
    });
    expect(unrelated).toBeNull();

    const clean = detectRepertoireDeviation({
      sanHistory: ['d4', 'd5', 'Bf4', 'Nf6', 'e3', 'e6', 'Nf3', 'c5', 'c3'],
      userColor: 'w',
      courses,
    });
    expect(clean).toBeNull();
  });
});
