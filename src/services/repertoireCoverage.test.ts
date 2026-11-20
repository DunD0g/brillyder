import { describe, expect, it } from 'vitest';
import starterCoursesRaw from '../data/starterCourses.json';
import type { OpeningCourse } from '../types/openings';
import {
  addPatchedLineToCourse,
  computeCourseCoverage,
  type ExplorerFetcher,
} from './repertoireCoverage';

const courses = starterCoursesRaw as OpeningCourse[];
const london = courses.find((c) => c.id === 'london-system-core')!;

describe('repertoireCoverage & Patch Gap', () => {
  it('computes expected coverage % and ranks uncovered opponent replies >=5%', async () => {
    // Mock Explorer responses for 1. d4
    const mockFetcher: ExplorerFetcher = async (_fen, history) => {
      if (history.length === 1 && history[0] === 'd4') {
        return {
          games: 1000,
          source: 'lichess',
          moves: [
            { san: 'd5', uci: 'd7d5', white: 460, draws: 60, black: 480, games: 500 },
            { san: 'Nf6', uci: 'g8f6', white: 140, draws: 20, black: 140, games: 300 },
            { san: 'e6', uci: 'e7e6', white: 90, draws: 10, black: 100, games: 200 }, // Uncovered in starter London!
          ],
        };
      }
      return null;
    };

    const report = await computeCourseCoverage(london, {
      fetcher: mockFetcher,
      maxDepthPlies: 4,
    });

    expect(report.source).toBe('lichess');
    expect(report.expectedCoveragePct).toBe(80); // 500 + 300 covered out of 1000
    expect(report.uncoveredGaps.length).toBe(1);
    expect(report.uncoveredGaps[0].opponentSan).toBe('e6');
    expect(report.uncoveredGaps[0].replyShare).toBeCloseTo(0.2, 2);

    // 1-click Patch Gap with 2. Bf4 raises coverage to 100%!
    const { updatedCourse, newCards } = addPatchedLineToCourse(
      london,
      report.uncoveredGaps[0].moveSequence,
      'Bf4'
    );
    expect(newCards.length).toBeGreaterThan(0);
    expect(newCards.every((c) => c.unlocked)).toBe(true);

    const afterReport = await computeCourseCoverage(updatedCourse, {
      fetcher: mockFetcher,
      maxDepthPlies: 4,
    });
    expect(afterReport.expectedCoveragePct).toBe(100);
    expect(afterReport.uncoveredGaps.length).toBe(0);
  });
});
