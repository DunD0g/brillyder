import { describe, expect, it } from 'vitest';
import starterCoursesRaw from '../data/starterCourses.json';
import type { AnalyzedGame, AnalyzedPly, LichessGameRecord, MistakePuzzle } from '../types/chess';
import type { OpeningCourse } from '../types/openings';
import { buildEngineScore } from '../utils/chessMath';
import { resolveUserColor, resultForUserStrict } from '../utils/player';
import { invertTablebaseMoveCategory } from './tablebaseApi';
import { buildBrillyVault } from './vault';
import { extractBlownLeadPositions } from './advantageConversion';
import { buildDailyWorkoutPlan, buildGravityCheckItems } from './dailyCoach';
import {
  CONSOLIDATION_COOLDOWN_MS,
  createFrozenWoodpeckerCycle,
  recordWoodpeckerPuzzleOutcome,
} from './woodpeckerCycles';
import { detectRepertoireDeviation } from './deviationDetector';
import { extractLichessGameId, parseRawPgnToGame } from './lichessApi';
import { computeMultiGameInsights } from './insightsAggregator';
import { loadDrillStreak, recordDrillSolve } from './mistakeDeck';
import { hydrateCourseCards } from '../lib/fsrsOpening';

const courses = starterCoursesRaw as OpeningCourse[];

function makePuzzle(id: string, winLoss: number, overrides: Partial<MistakePuzzle> = {}): MistakePuzzle {
  return {
    id,
    gameId: `g-${id}`,
    ply: 15,
    moveNumber: 8,
    color: 'w',
    beforeFen: 'r1bqkbnr/pppp1ppp/2n5/4p3/3P4/5N2/PPP1PPPP/RNBQKB1R w KQkq - 0 3',
    afterFen: 'r1bqkbnr/pppp1ppp/2n5/4p3/3P4/2N2N2/PPP1PPPP/R1BQKB1R b KQkq - 1 3',
    san: 'Nc3',
    bestMoveSan: 'dxe5',
    bestMoveUci: 'd4e5',
    classification: 'blunder',
    phase: 'middlegame',
    tacticalTag: 'Hanging Piece',
    headline: 'Dropped pawn',
    openingName: 'London System',
    openingEco: 'D02',
    playerName: 'Hero',
    opponentName: 'Rival',
    playedAt: Date.now() - 1000,
    evalBefore: buildEngineScore(300, null),
    evalAfter: buildEngineScore(-50, null),
    winLoss,
    ...overrides,
  };
}

function makePly(ply: number, color: 'w' | 'b', cpBefore: number, cpAfter: number, overrides: Partial<AnalyzedPly> = {}): AnalyzedPly {
  return {
    ply,
    moveNumber: Math.ceil(ply / 2),
    color,
    san: color === 'w' ? 'Nf3' : 'Nc6',
    uci: color === 'w' ? 'g1f3' : 'b8c6',
    from: color === 'w' ? 'g1' : 'b8',
    to: color === 'w' ? 'f3' : 'c6',
    beforeFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
    afterFen: `rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq - ${ply} 1`,
    bestMoveUci: color === 'w' ? 'g1f3' : 'b8c6',
    bestMoveSan: color === 'w' ? 'Nf3' : 'Nc6',
    bestPvSan: ['Nf3'],
    evalBefore: buildEngineScore(cpBefore, null),
    evalAfter: buildEngineScore(cpAfter, null),
    secondBestGapWin: 4,
    winLoss: 0,
    accuracy: 95,
    classification: 'best',
    phase: 'middlegame',
    coaching: { headline: 'Best', detail: '', tacticalTag: 'Engine Top' },
    ...overrides,
  };
}

function makeGame(id: string, overrides: Partial<LichessGameRecord> = {}, plies: AnalyzedPly[] = []): AnalyzedGame {
  const game: LichessGameRecord = {
    id,
    source: 'lichess',
    rated: true,
    variant: 'standard',
    speed: 'rapid',
    perf: 'rapid',
    createdAt: 1_700_000_000_000,
    status: 'resign',
    resultString: '1-0',
    timeControlLabel: '10+0',
    pgn: '[TimeControl "600+0"]\n1. d4 d5 2. Bf4 Nf6',
    openingName: 'London System',
    openingEco: 'D02',
    white: { name: 'Hero', rating: 1500 },
    black: { name: 'Rival', rating: 1500 },
    userColor: 'w',
    ...overrides,
  };
  return {
    id,
    analyzedAt: game.createdAt,
    depth: 14,
    game,
    initialEval: buildEngineScore(20, null),
    plies,
    whiteSummary: { accuracy: 90, estimatedElo: 1580, counts: { brilliant: 0, great: 0, best: 10, excellent: 0, inaccuracy: 0, mistake: 0, blunder: 0, book: 0 }, avgWinLoss: 1 },
    blackSummary: { accuracy: 75, estimatedElo: 1420, counts: { brilliant: 0, great: 0, best: 8, excellent: 0, inaccuracy: 0, mistake: 1, blunder: 1, book: 0 }, avgWinLoss: 8 },
  };
}

describe('Pass 2 — Stats, Vault, Tablebase, Sync, Daily Coach & Streak integrity', () => {
  it('inverts Lichess Syzygy candidate move WDL categories to mover perspective', () => {
    expect(invertTablebaseMoveCategory('loss')).toBe('win');
    expect(invertTablebaseMoveCategory('win')).toBe('loss');
    expect(invertTablebaseMoveCategory('cursed-win')).toBe('blessed-loss');
    expect(invertTablebaseMoveCategory('blessed-loss')).toBe('cursed-win');
    expect(invertTablebaseMoveCategory('draw')).toBe('draw');
  });

  it('never attaches writable FSRS cards for Gravity Check non-due fallback previews', () => {
    const existing = hydrateCourseCards(courses[0], undefined, { unlocked: true }).map((c) => ({
      ...c,
      dueAt: Date.now() + 86_400_000 * 7, // NOT due for 7 days
      reps: 5,
    }));
    const items = buildGravityCheckItems({
      deck: [],
      fsrsCards: existing,
      courses,
      nowMs: Date.now(),
    });
    const openingItems = items.filter((i) => i.kind === 'opening');
    expect(openingItems).toHaveLength(2);
    // Fallback previews MUST NOT attach a card that would overwrite reps=5 in IDB!
    expect(openingItems.every((i) => i.card === undefined)).toBe(true);
  });

  it('deduplicates Stage 2/3/4 inside one Daily Session and respects Woodpecker cooldown', () => {
    const now = 1_700_000_000_000;
    const deck = Array.from({ length: 18 }, (_, i) =>
      makePuzzle(`p${i + 1}`, 40 - i, { playedAt: now - i * 1000 })
    );
    const activeCycle = createFrozenWoodpeckerCycle(deck.slice(0, 10), 30, now);

    // Active cycle (not on cooldown): Stage 2 should NOT duplicate puzzles already in Stage 3!
    const plan = buildDailyWorkoutPlan({
      duration: 10,
      fsrsCards: [],
      deck,
      analyzedGames: [],
      username: 'Hero',
      activeCycle,
      daySeed: 2, // motif
      nowMs: now,
    });
    const s3Ids = new Set(plan.stage3Woodpecker.map((p) => p.id));
    expect(plan.stage2Blunders.some((p) => s3Ids.has(p.id))).toBe(false);
    expect(plan.stage3OnCooldown).toBe(false);

    // When active cycle is on 24h consolidation cooldown, Daily Coach respects it
    const coolingCycle = { ...activeCycle, cooldownUntil: now + CONSOLIDATION_COOLDOWN_MS };
    const coolingPlan = buildDailyWorkoutPlan({
      duration: 10,
      fsrsCards: [],
      deck,
      analyzedGames: [],
      username: 'Hero',
      activeCycle: coolingCycle,
      nowMs: now,
    });
    expect(coolingPlan.stage3OnCooldown).toBe(true);
    expect(coolingPlan.stage3Woodpecker).toHaveLength(0);

    // Mastered 7-cycle record refuses duplicate Cycle #7 completions
    const mastered = {
      ...activeCycle,
      currentCycle: 7,
      completedCycles: Array.from({ length: 7 }, (_, i) => ({
        cycleNumber: i + 1,
        completedAt: now,
        elapsedSeconds: 30,
        accuracyPct: 100,
        firstTryPct: 100,
        solvedCount: 10,
        totalCount: 10,
      })),
    };
    const afterAttempt = recordWoodpeckerPuzzleOutcome(mastered, 'p1', { solved: true, wrongMoves: 0, hintsUsed: 0 }, now);
    expect(afterAttempt.updated.completedCycles).toHaveLength(7);
  });

  it('spotlights the user move (never opponent final move) in Vault Clean Sweeps & filters hopeless Clutch Saves', () => {
    const plies: AnalyzedPly[] = [];
    for (let i = 1; i <= 10; i++) {
      plies.push(makePly(i, i % 2 === 1 ? 'w' : 'b', 40, 40, { san: i === 9 ? 'Qd7' : i === 10 ? 'Bxb2' : 'Nf3' }));
    }
    // Add a dead-lost -9.5 move falsely marked isClutchSave
    plies.push(
      makePly(11, 'w', -950, -950, {
        san: 'Kh1',
        isClutchSave: true,
        secondBestGapPawns: 3.0,
      })
    );
    // Final ply is Black's move (ply 12) while White (Hero) won 1-0!
    plies.push(makePly(12, 'b', 400, 400, { san: 'Bxb2' }));

    const ag = makeGame('clean-1', { resultString: '1-0' }, plies);
    const vault = buildBrillyVault([ag], 'Hero');
    const cleanEntry = vault.entries.find((e) => e.category === 'clean');
    expect(cleanEntry).toBeTruthy();
    expect(cleanEntry?.ply).toBe(11); // User's own last move, NOT Black's ply 12!
    expect(cleanEntry?.san).toBe('Kh1');
    // Dead-lost -9.5 position must NOT qualify as Clutch Save
    expect(vault.stats.clutchSaves).toBe(0);
  });

  it('matches active username before baked userColor and treats "*" games strictly as null', () => {
    const g = makeGame('u1', { userColor: 'w', white: { name: 'OldUser' }, black: { name: 'NewUser' }, resultString: '*' });
    expect(resolveUserColor(g.game, 'NewUser')).toBe('b');
    expect(resultForUserStrict(g.game, 'b')).toBeNull();
    // Unfinished '*' games must NOT be extracted as blown leads
    const unfinishedLead = makeGame('u2', { resultString: '*' }, [makePly(11, 'w', 350, 50)]);
    expect(extractBlownLeadPositions([unfinishedLead], 'Hero')).toHaveLength(0);
  });

  it('preserves playable [+2.5, +7.5] Advantage Conversion peaks instead of already-won +8.5 positions', () => {
    const plies = [
      makePly(11, 'w', 360, 320), // playable peak before slip
      makePly(13, 'w', 850, 50), // huge peak right before blunder
    ];
    const ag = makeGame('conv-1', { resultString: '0-1' }, plies);
    const extracted = extractBlownLeadPositions([ag], 'Hero');
    expect(extracted).toHaveLength(1);
    expect(extracted[0].ply).toBe(11);
    expect(extracted[0].peakEvalPawns).toBe(3.6);
  });

  it('routes pasted Chess.com PGNs cleanly and rejects reserved Lichess paths', () => {
    const ccPgn = `[Event "Live Chess"]
[Site "Chess.com"]
[UTCDate "2026.03.10"]
[UTCTime "14:20:00"]
[White "Hero"]
[Black "Rival"]
[Result "1-0"]
[ECOUrl "https://www.chess.com/openings/Caro-Kann-Defense-Advance-Variation"]
[Link "https://www.chess.com/game/live/123456789"]

1. e4 c6 2. d4 d5 3. e5 1-0`;
    const parsed = parseRawPgnToGame(ccPgn, 'Hero');
    expect(parsed.source).toBe('chesscom');
    expect(parsed.url).toBe('https://www.chess.com/game/live/123456789');
    expect(parsed.openingName).toContain('Caro Kann');
    expect(parsed.createdAt).toBe(Date.parse('2026-03-10T14:20:00Z'));

    expect(extractLichessGameId('https://lichess.org/training')).toBeNull();
    expect(extractLichessGameId('https://lichess.org/analysis')).toBeNull();
    expect(extractLichessGameId('https://lichess.org/AbCdEf12')).toBe('AbCdEf12');
  });

  it('handles malformed custom course SAN safely and treats Black move 1 symmetrically', () => {
    const brokenCourse: OpeningCourse = {
      ...courses[0],
      id: 'broken-custom',
      lines: [{ ...courses[0].lines[0], id: 'l1', title: 'Bad', moves: ['d4', 'ILLEGAL_MOVE_XYZ'] }],
    };
    expect(() =>
      detectRepertoireDeviation({
        sanHistory: ['d4', 'd5', 'Bf4'],
        userColor: 'w',
        courses: [brokenCourse],
      })
    ).not.toThrow();

    // Playing 1. e4 b6 (Owen's Defense) as Black when starter repertoire has other 1. e4 defenses should NOT flag move 1!
    const blackMove1 = detectRepertoireDeviation({
      sanHistory: ['e4', 'b6', 'd4', 'Bb7'],
      userColor: 'b',
      courses,
    });
    expect(blackMove1).toBeNull();
  });

  it('keeps openingBest and openingWorst distinct on tied win rates', () => {
    const g1 = makeGame('o1', { openingName: 'London System', resultString: '1-0' }, [makePly(1, 'w', 20, 20)]);
    const g2 = makeGame('o2', { openingName: 'Caro-Kann Defense', resultString: '1-0' }, [makePly(1, 'w', 20, 20)]);
    const insights = computeMultiGameInsights([g1, g2], 'Hero');
    expect(insights.openingBest).not.toBeNull();
    expect(insights.openingWorst).not.toBeNull();
    expect(insights.openingBest?.name).not.toBe(insights.openingWorst?.name);
  });

  it('continues drill streak cleanly across consecutive calendar days instead of resetting to 1', () => {
    const day1 = new Date(2026, 2, 10, 22, 0, 0);
    const day2 = new Date(2026, 2, 11, 8, 0, 0);
    recordDrillSolve(day1);
    const s1 = recordDrillSolve(day1);
    expect(s1.current).toBeGreaterThanOrEqual(2);
    const beforeDay2 = loadDrillStreak(day2);
    expect(beforeDay2.current).toBe(s1.current);
    const s2 = recordDrillSolve(day2);
    expect(s2.current).toBe(s1.current + 1);
  });

  it('resolves distinct Lichess and Chess.com handles per game platform accurately', () => {
    const lichessGame = makeGame('dual-1', {
      source: 'lichess',
      userColor: 'w',
      white: { name: 'RivalA' },
      black: { name: 'LichessLuke' },
    });
    const chessComGame = makeGame('dual-2', {
      source: 'chesscom',
      userColor: 'b',
      white: { name: 'ChessComLuke' },
      black: { name: 'RivalB' },
    });
    const handles = { lichess: 'LichessLuke', chesscom: 'ChessComLuke' };
    expect(resolveUserColor(lichessGame.game, handles)).toBe('b');
    expect(resolveUserColor(chessComGame.game, handles)).toBe('w');
  });
});
