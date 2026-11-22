import { Chess } from 'chess.js';
import { describe, expect, it } from 'vitest';
import starterCoursesData from '../data/starterCourses.json';
import type { OpeningCourse } from '../types/openings';
import { hydrateCourseCards } from '../lib/fsrsOpening';
import { importPgnToCourse } from './repertoireImporter';
import { buildRepertoireTree, exportCourseToPgn } from './repertoireTree';

const starterCourses = starterCoursesData as unknown as OpeningCourse[];

describe('repertoireTree & PGN export', () => {
  it('merges shared move prefixes into a branching trie with FSRS signal strength', () => {
    const london = starterCourses.find((c) => c.id === 'london-system-core')!;
    const cards = hydrateCourseCards(london, undefined, { unlocked: true });
    const tree = buildRepertoireTree(london, cards);

    expect(tree.children.length).toBe(1);
    expect(tree.children[0].san).toBe('d4');
    expect(tree.children[0].lineIds.length).toBe(london.lines.length);
    expect(tree.children[0].isUserMove).toBe(true);
    expect(tree.children[0].recallPct).not.toBeNull();
    // After 1. d4, London has multiple opponent branches (e.g. ...d5, ...Nf6)
    expect(tree.children[0].children.length).toBeGreaterThanOrEqual(2);
  });

  it('exports every starter course to valid PGN that round-trips through repertoireImporter', () => {
    for (const course of starterCourses) {
      const pgn = exportCourseToPgn(course);
      expect(pgn).toContain(`[Event "${course.name}:`);
      const imported = importPgnToCourse({
        pgn,
        name: `${course.name} Export`,
        side: course.side,
        source: 'pgn',
      });
      expect(imported.lines.length).toBeGreaterThanOrEqual(course.lines.length);
      const importedFens = imported.lines.map((l) => {
        const c = new Chess();
        for (const san of l.moves) c.move(san);
        return `${l.moves.length}:${c.fen()}`;
      });
      course.lines.forEach((line, idx) => {
        const c = new Chess();
        for (const san of line.moves) c.move(san);
        expect(importedFens[idx], `${course.id} line ${line.id} should round-trip identically`).toBe(
          `${line.moves.length}:${c.fen()}`
        );
      });
    }
  });
});
