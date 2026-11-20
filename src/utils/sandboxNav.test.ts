import { describe, expect, it } from 'vitest';
import { appendSandboxMoves, jumpSandboxEdge, stepSandboxNav, type SandboxNavMove } from './sandboxNav';

const mv = (san: string): SandboxNavMove => ({ san, uci: 'e2e4', from: 'e2', to: 'e4' });

describe('sandboxNav (Explore / What-If non-exiting navigation)', () => {
  it('steps back and forward through explored moves without discarding the branch', () => {
    let s = appendSandboxMoves({ basePly: 8, moves: [], cursor: 0 }, [mv('Nf3'), mv('Nc6'), mv('Bb5')]);
    expect(s.cursor).toBe(3);

    // Back inside explored line preserves all 3 moves
    s = stepSandboxNav(s, -1, 40);
    expect(s.cursor).toBe(2);
    expect(s.moves).toHaveLength(3);

    // Forward steps back into Bb5
    s = stepSandboxNav(s, 1, 40);
    expect(s.cursor).toBe(3);

    // Home jumps to branch root (cursor 0), keeping moves; second Home jumps to ply 0
    s = jumpSandboxEdge(s, 'first', 40);
    expect(s.cursor).toBe(0);
    expect(s.basePly).toBe(8);
    expect(s.moves).toHaveLength(3);

    s = jumpSandboxEdge(s, 'last', 40);
    expect(s.cursor).toBe(3);
  });

  it('steps smoothly along base game plies when at branch root without exiting sandbox', () => {
    let s = { basePly: 8, moves: [mv('Nf3')], cursor: 1 };
    // Step back to branch root
    s = stepSandboxNav(s, -1, 40);
    expect(s.cursor).toBe(0);
    expect(s.basePly).toBe(8);

    // Step back again -> moves basePly to 7 and stays in sandbox
    s = stepSandboxNav(s, -1, 40);
    expect(s.basePly).toBe(7);
    expect(s.moves).toHaveLength(0);
    expect(s.cursor).toBe(0);

    // Step forward along mainline -> basePly 8 while staying in sandbox
    s = stepSandboxNav(s, 1, 40);
    expect(s.basePly).toBe(8);
    expect(s.moves).toHaveLength(0);
  });

  it('forks cleanly when playing a different move from mid-branch', () => {
    let s = appendSandboxMoves({ basePly: 4, moves: [], cursor: 0 }, [mv('Nf3'), mv('Nc6'), mv('Bc4')]);
    s = stepSandboxNav(s, -1, 40); // cursor = 2 (after Nc6)
    s = appendSandboxMoves(s, [mv('Bb5')]);
    expect(s.moves.map((m) => m.san)).toEqual(['Nf3', 'Nc6', 'Bb5']);
    expect(s.cursor).toBe(3);
  });
});
