import { describe, expect, it } from 'vitest';
import { Chess } from 'chess.js';
import starterCoursesRaw from './starterCourses.json';
import type { OpeningCourse } from '../types/openings';

const SQUARE_RE = /^[a-h][1-8]$/;
const courses = starterCoursesRaw as OpeningCourse[];

describe('starterCourses.json chess.js legality validation', () => {
  it('contains all 4 starter courses with unique ids', () => {
    expect(courses.length).toBeGreaterThanOrEqual(4);
    const ids = new Set(courses.map((c) => c.id));
    expect(ids.size).toBe(courses.length);
  });

  for (const course of courses) {
    describe(`Course: ${course.id} (${course.side})`, () => {
      it('replays mothershipSetup.previewMoves with 100% legal SAN and valid arrow/highlight squares', () => {
        const chess = new Chess();
        expect(course.mothershipSetup.previewMoves.length).toBeGreaterThan(0);

        for (let i = 0; i < course.mothershipSetup.previewMoves.length; i++) {
          const san = course.mothershipSetup.previewMoves[i];
          const mv = chess.move(san);
          expect(mv, `Illegal previewMove "${san}" at index ${i} in ${course.id}`).toBeTruthy();
        }

        for (const arrow of course.mothershipSetup.arrows) {
          expect(arrow.from).toMatch(SQUARE_RE);
          expect(arrow.to).toMatch(SQUARE_RE);
        }
        for (const hl of course.mothershipSetup.highlights) {
          expect(hl.square).toMatch(SQUARE_RE);
        }
      });

      for (const line of course.lines) {
        it(`replays line "${line.id}" moves, annotations, and wrongMoveTraps punishmentLines legally`, () => {
          const chess = new Chess();
          const fensBeforePly: string[] = [];
          const colorsAtPly: Array<'w' | 'b'> = [];

          expect(line.moves.length).toBeGreaterThan(0);
          for (let ply = 0; ply < line.moves.length; ply++) {
            const san = line.moves[ply];
            fensBeforePly.push(chess.fen());
            colorsAtPly.push(chess.turn());
            const mv = chess.move(san);
            expect(mv, `Illegal move "${san}" at ply ${ply} in ${course.id}/${line.id}`).toBeTruthy();
          }

          const courseColor = course.side === 'white' ? 'w' : 'b';

          for (const ann of line.annotations) {
            expect(ann.ply, `Annotation ply out of range in ${line.id}`).toBeGreaterThanOrEqual(0);
            expect(ann.ply, `Annotation ply out of range in ${line.id}`).toBeLessThan(line.moves.length);
            expect(colorsAtPly[ann.ply], `Annotation ply ${ann.ply} color mismatch in ${line.id}`).toBe(courseColor);

            for (const arrow of ann.arrows ?? []) {
              expect(arrow.from).toMatch(SQUARE_RE);
              expect(arrow.to).toMatch(SQUARE_RE);
            }
            for (const hl of ann.highlights ?? []) {
              expect(hl.square).toMatch(SQUARE_RE);
            }

            for (const trap of ann.wrongMoveTraps ?? []) {
              const trapBoard = new Chess(fensBeforePly[ann.ply]);
              const wrongMove = trapBoard.move(trap.playedSan);
              expect(
                wrongMove,
                `Illegal trap playedSan "${trap.playedSan}" at ply ${ann.ply} in ${course.id}/${line.id}`
              ).toBeTruthy();
              expect(trap.punishmentLine.length).toBeGreaterThan(0);

              for (let j = 0; j < trap.punishmentLine.length; j++) {
                const punishSan = trap.punishmentLine[j];
                const punishMove = trapBoard.move(punishSan);
                expect(
                  punishMove,
                  `Illegal punishmentLine move "${punishSan}" (step ${j}) after "${trap.playedSan}" at ply ${ann.ply} in ${course.id}/${line.id}`
                ).toBeTruthy();
              }

              for (const arrow of trap.arrows ?? []) {
                expect(arrow.from).toMatch(SQUARE_RE);
                expect(arrow.to).toMatch(SQUARE_RE);
              }
            }
          }
        });
      }
    });
  }
});
