import { describe, expect, it } from 'vitest';
import { buildShareCardFilename, parseFenToBoardMatrix } from './shareCard';

describe('shareCard helpers', () => {
  it('parses starting FEN cleanly into an 8x8 matrix', () => {
    const mat = parseFenToBoardMatrix('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
    expect(mat.length).toBe(8);
    expect(mat[0]).toEqual(['r', 'n', 'b', 'q', 'k', 'b', 'n', 'r']);
    expect(mat[3]).toEqual([null, null, null, null, null, null, null, null]);
    expect(mat[7]).toEqual(['R', 'N', 'B', 'Q', 'K', 'B', 'N', 'R']);
  });

  it('builds safe filenames for PNG downloads', () => {
    expect(buildShareCardFilename('Brilliant !! 14. Bxh7+')).toBe('brillyder-brilliant-14-bxh7.png');
    expect(buildShareCardFilename('   ')).toBe('brillyder-highlight.png');
  });
});
