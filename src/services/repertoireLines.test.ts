import { describe, expect, it } from 'vitest';
import starterCoursesRaw from '../data/starterCourses.json';
import type { OpeningCourse } from '../types/openings';
import {
  createCustomCourseLine,
  parseAndValidateLineMoves,
  removeLineFromCourse,
  upsertLineInCourse,
} from './repertoireLines';

const courses = starterCoursesRaw as OpeningCourse[];

describe('repertoireLines — custom line editor & validation', () => {
  it('parses numbered PGN SAN with comments/NAGs into canonical legal SAN', () => {
    const res = parseAndValidateLineMoves('1. e4 e5 2. Nf3! Nc6 {comment} 3. Bc4 Bc5 1-0');
    expect(res.ok).toBe(true);
    if (res.ok) {
      expect(res.moves).toEqual(['e4', 'e5', 'Nf3', 'Nc6', 'Bc4', 'Bc5']);
    }
  });

  it('rejects illegal moves with exact ply error', () => {
    const res = parseAndValidateLineMoves('1. e4 e5 2. Qh8');
    expect(res.ok).toBe(false);
    if (!res.ok) {
      expect(res.error).toContain('Qh8');
    }
  });

  it('adds, updates, and deletes individual lines while preserving at least 1 line', () => {
    const course = courses[0];
    const originalCount = course.lines.length;
    const newLine = createCustomCourseLine({
      course,
      title: 'Quick London Test',
      eco: 'd02',
      planNote: 'Control e5 early.',
      moves: ['d4', 'd5', 'Bf4', 'c5', 'e3'],
    });
    expect(newLine.eco).toBe('D02');
    expect(newLine.annotations).toHaveLength(1);
    expect(newLine.annotations[0].ply).toBe(4); // White's last move (e3)

    const withAdded = upsertLineInCourse(course, newLine);
    expect(withAdded.lines).toHaveLength(originalCount + 1);

    const edited = upsertLineInCourse(withAdded, { ...newLine, title: 'Renamed Line' });
    expect(edited.lines).toHaveLength(originalCount + 1);
    expect(edited.lines.find((l) => l.id === newLine.id)?.title).toBe('Renamed Line');

    const removed = removeLineFromCourse(edited, newLine.id);
    expect(removed.lines).toHaveLength(originalCount);

    // Guard against deleting the final remaining line in a course
    const singleLineCourse: OpeningCourse = { ...course, lines: [course.lines[0]] };
    expect(removeLineFromCourse(singleLineCourse, course.lines[0].id).lines).toHaveLength(1);
  });
});
