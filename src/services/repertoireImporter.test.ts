import { describe, expect, it } from 'vitest';
import { Chess } from 'chess.js';
import { extractLichessStudyIds, importPgnToCourse } from './repertoireImporter';

describe('repertoireImporter', () => {
  it('extracts Lichess study and optional chapter IDs from URLs', () => {
    expect(extractLichessStudyIds('https://lichess.org/study/AbCd1234')).toEqual({
      studyId: 'AbCd1234',
      chapterId: undefined,
    });
    expect(extractLichessStudyIds('https://lichess.org/study/AbCd1234/EfGh5678')).toEqual({
      studyId: 'AbCd1234',
      chapterId: 'EfGh5678',
    });
    expect(extractLichessStudyIds('1. e4 e5')).toBeNull();
  });

  it('parses PGN with RAV variations and comments into legal chess.js lines', () => {
    const pgn = `
[Event "London Study"]
[ECO "D02"]

1. d4 d5 2. Bf4 {Deploy outside the chain} Nf6 (2... c5 3. e3 Nc6 4. c3) 3. e3 e6 4. Nf3 *
`;
    const course = importPgnToCourse({ name: 'My London', side: 'white', pgn });
    expect(course.lines.length).toBe(2);
    expect(course.mothershipSetup.previewMoves.length).toBeGreaterThanOrEqual(4);

    for (const line of course.lines) {
      const c = new Chess();
      for (const san of line.moves) {
        expect(c.move(san)).toBeTruthy();
      }
    }

    const mainline = course.lines.find((l) => l.moves.includes('Nf6'));
    expect(mainline?.annotations.some((a) => a.plan.includes('Deploy outside'))).toBe(true);
  });

  it('splits multi-game PGN chunks into separate lines', () => {
    const multiPgn = `
[Event "Line 1"]
1. e4 c6 2. d4 d5 3. Nc3 dxe4 *

[Event "Line 2"]
1. e4 c6 2. d4 d5 3. e5 Bf5 *
`;
    const course = importPgnToCourse({ name: 'Caro-Kann', side: 'black', pgn: multiPgn });
    expect(course.lines.length).toBe(2);
    expect(course.side).toBe('black');
  });
});
