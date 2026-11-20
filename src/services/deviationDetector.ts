import { Chess } from 'chess.js';
import type { AnalyzedGame, PlayerColor } from '../types/chess';
import type { OpeningCourse, Side } from '../types/openings';
import { buildOpeningCardId, normalizeFenKey } from '../lib/fsrsOpening';
import { resolveUserColor, resultForUser } from '../utils/player';

export interface RepertoireMoveTarget {
  courseId: string;
  courseName: string;
  lineId: string;
  lineTitle: string;
  ply: number;
  expectedSan: string;
  expectedUci: string;
  cardId: string;
  moveSequence: string[];
}

export interface RepertoireDeviation {
  kind: 'user-deviation' | 'opponent-novelty';
  /** 1-based ply index matching AnalyzedPly.ply */
  ply: number;
  moveNumber: number;
  color: PlayerColor;
  playedSan: string;
  beforeFen: string;
  afterFen: string;
  moveSequenceBefore: string[];
  moveSequenceAfter: string[];
  courseId: string;
  courseName: string;
  expectedMoves: RepertoireMoveTarget[];
  recommendedReplySan?: string;
  evalBeforeDisplay?: string;
  evalAfterDisplay?: string;
  winLoss?: number;
}

export interface MultiGameOpeningRow {
  eco: string;
  name: string;
  games: number;
  wins: number;
  draws: number;
  losses: number;
  winRate: number;
  avgAccuracy: number;
  avgEvalMove10: number | null;
  deviationCount: number;
  mostCostly: {
    gameId: string;
    ply: number;
    moveNumber: number;
    color: PlayerColor;
    san: string;
    bestMoveSan: string;
    winLoss: number;
  } | null;
}

interface RepertoireLookup {
  /** Keyed by normalized FEN BEFORE user move -> expected user replies */
  userPositions: Map<string, RepertoireMoveTarget[]>;
  /** Keyed by normalized FEN BEFORE opponent move -> course info + covered opponent replies */
  oppPositions: Map<string, { courseId: string; courseName: string; coveredOppMoves: Set<string> }>;
}

function buildRepertoireLookup(courses: OpeningCourse[], side: Side): RepertoireLookup {
  const userPositions = new Map<string, RepertoireMoveTarget[]>();
  const oppPositions = new Map<string, { courseId: string; courseName: string; coveredOppMoves: Set<string> }>();
  const targetColor = side === 'white' ? 'w' : 'b';

  for (const course of courses) {
    if (course.side !== side) continue;
    for (const line of course.lines) {
      const chess = new Chess();
      const seq: string[] = [];
      for (let ply = 0; ply < line.moves.length; ply++) {
        const fenBefore = chess.fen();
        const key = normalizeFenKey(fenBefore);
        const turn = chess.turn();
        const mv = chess.move(line.moves[ply]);
        const uci = `${mv.from}${mv.to}${mv.promotion ?? ''}`;

        if (turn === targetColor) {
          const list = userPositions.get(key) ?? [];
          if (!list.some((item) => item.expectedUci === uci && item.courseId === course.id)) {
            list.push({
              courseId: course.id,
              courseName: course.name,
              lineId: line.id,
              lineTitle: line.title,
              ply,
              expectedSan: mv.san,
              expectedUci: uci,
              cardId: buildOpeningCardId(course.id, line.id, ply, uci),
              moveSequence: [...seq],
            });
          }
          userPositions.set(key, list);
        } else {
          const existing = oppPositions.get(key) ?? {
            courseId: course.id,
            courseName: course.name,
            coveredOppMoves: new Set<string>(),
          };
          existing.coveredOppMoves.add(mv.san);
          oppPositions.set(key, existing);
        }

        seq.push(mv.san);
      }
    }
  }

  return { userPositions, oppPositions };
}

/**
 * Compares moves 1-12 (plies 1..24) of a game against the user's active side-specific
 * repertoire tree (using normalized FEN keys to recognize transpositions).
 */
export function detectRepertoireDeviation(params: {
  sanHistory: string[];
  userColor: PlayerColor;
  courses: OpeningCourse[];
  analyzed?: AnalyzedGame | null;
  maxMoveNumber?: number;
}): RepertoireDeviation | null {
  const { sanHistory, userColor, courses, analyzed, maxMoveNumber = 12 } = params;
  const side: Side = userColor === 'w' ? 'white' : 'black';
  const lookup = buildRepertoireLookup(courses, side);
  if (lookup.userPositions.size === 0) return null;

  const maxPlies = Math.min(sanHistory.length, maxMoveNumber * 2);
  const chess = new Chess();
  const seq: string[] = [];
  let matchedAtLeastOneUserMove = false;
  let lastMatchedCourse: { id: string; name: string } | null = null;

  for (let i = 0; i < maxPlies; i++) {
    const beforeFen = chess.fen();
    const keyBefore = normalizeFenKey(beforeFen);
    const turn = chess.turn();
    let mv;
    try {
      mv = chess.move(sanHistory[i]);
    } catch {
      break;
    }
    const afterFen = chess.fen();
    const plyNum = i + 1;
    const moveNumber = Math.floor(i / 2) + 1;
    const analyzedPly = analyzed?.plies[i];

    if (turn === userColor) {
      const expected = lookup.userPositions.get(keyBefore);
      if (expected && expected.length > 0) {
        const hit = expected.find((e) => e.expectedSan === mv.san);
        if (hit) {
          matchedAtLeastOneUserMove = true;
          lastMatchedCourse = { id: hit.courseId, name: hit.courseName };
        } else if (matchedAtLeastOneUserMove || i <= 3) {
          // Only flag a move-1 deviation if it's after move 1 or inside a matched course line;
          // for White move 1, skip flagging if user simply played a totally different 1st move (e.g. 1. e4 vs London).
          if (i === 0) return null;
          return {
            kind: 'user-deviation',
            ply: plyNum,
            moveNumber,
            color: turn,
            playedSan: mv.san,
            beforeFen,
            afterFen,
            moveSequenceBefore: [...seq],
            moveSequenceAfter: [...seq, mv.san],
            courseId: expected[0].courseId,
            courseName: expected[0].courseName,
            expectedMoves: expected,
            evalBeforeDisplay: analyzedPly?.evalBefore.display,
            evalAfterDisplay: analyzedPly?.evalAfter.display,
            winLoss: analyzedPly?.winLoss,
          };
        }
      }
    } else {
      const oppEntry = lookup.oppPositions.get(keyBefore);
      if (oppEntry && (matchedAtLeastOneUserMove || (side === 'black' && i === 0))) {
        if (!oppEntry.coveredOppMoves.has(mv.san)) {
          // Don't flag move 1 opponent move for Black if user doesn't have a course for it
          if (i === 0 && !matchedAtLeastOneUserMove) {
            seq.push(mv.san);
            continue;
          }
          const nextAnalyzed = analyzed?.plies[i + 1];
          return {
            kind: 'opponent-novelty',
            ply: plyNum,
            moveNumber,
            color: turn,
            playedSan: mv.san,
            beforeFen,
            afterFen,
            moveSequenceBefore: [...seq],
            moveSequenceAfter: [...seq, mv.san],
            courseId: lastMatchedCourse?.id ?? oppEntry.courseId,
            courseName: lastMatchedCourse?.name ?? oppEntry.courseName,
            expectedMoves: [],
            recommendedReplySan: nextAnalyzed?.bestMoveSan,
            evalBeforeDisplay: analyzedPly?.evalBefore.display,
            evalAfterDisplay: analyzedPly?.evalAfter.display,
          };
        }
      }
    }

    seq.push(mv.san);
  }

  return null;
}

/**
 * Multi-game Opening Report Card grouping analyzed games by ECO/Opening with:
 * Games Played, W/D/L %, Avg Eval at Move 10, Deviations, and Most Costly Recurring Position.
 */
export function buildOpeningReportCards(
  analyzedGames: AnalyzedGame[],
  username: string,
  courses: OpeningCourse[]
): MultiGameOpeningRow[] {
  const buckets = new Map<
    string,
    {
      eco: string;
      name: string;
      games: number;
      wins: number;
      draws: number;
      losses: number;
      accSum: number;
      eval10Sum: number;
      eval10Count: number;
      deviationCount: number;
      mostCostly: MultiGameOpeningRow['mostCostly'];
    }
  >();

  for (const ag of analyzedGames) {
    const uc = resolveUserColor(ag.game, username);
    const result = resultForUser(ag.game, uc);
    const sum = uc === 'w' ? ag.whiteSummary : ag.blackSummary;
    const rawName = ag.openingLineDetected || ag.game.openingName || 'Unknown Opening';
    const family = rawName.includes(':') ? rawName.slice(0, rawName.indexOf(':')).trim() : rawName.trim();
    const eco = ag.game.openingEco || '';
    const key = `${eco}|${family}`;

    const row = buckets.get(key) ?? {
      eco,
      name: family,
      games: 0,
      wins: 0,
      draws: 0,
      losses: 0,
      accSum: 0,
      eval10Sum: 0,
      eval10Count: 0,
      deviationCount: 0,
      mostCostly: null,
    };

    row.games++;
    row.accSum += sum.accuracy;
    if (result === 'W') row.wins++;
    else if (result === 'D') row.draws++;
    else row.losses++;

    // Eval around move 10 (ply index 19, or last opening ply if game ended earlier)
    const ply10Idx = Math.min(ag.plies.length - 1, 19);
    if (ply10Idx >= 0) {
      const score = ag.plies[ply10Idx].evalAfter;
      const userCp = (uc === 'w' ? score.cpWhite : -score.cpWhite) / 100;
      const clamped = Math.max(-8, Math.min(8, userCp));
      row.eval10Sum += clamped;
      row.eval10Count++;
    }

    const dev = detectRepertoireDeviation({
      sanHistory: ag.plies.map((p) => p.san),
      userColor: uc,
      courses,
      analyzed: ag,
    });
    if (dev?.kind === 'user-deviation') row.deviationCount++;

    // Most costly opening mistake (move 1-14)
    for (const p of ag.plies) {
      if (p.ply > 28 || p.color !== uc) continue;
      if (p.winLoss < 8) continue;
      if (!row.mostCostly || p.winLoss > row.mostCostly.winLoss) {
        row.mostCostly = {
          gameId: ag.id,
          ply: p.ply,
          moveNumber: p.moveNumber,
          color: p.color,
          san: p.san,
          bestMoveSan: p.bestMoveSan,
          winLoss: p.winLoss,
        };
      }
    }

    buckets.set(key, row);
  }

  return Array.from(buckets.values())
    .map((r) => ({
      eco: r.eco,
      name: r.name,
      games: r.games,
      wins: r.wins,
      draws: r.draws,
      losses: r.losses,
      winRate: r.games > 0 ? Math.round(((r.wins + r.draws * 0.5) / r.games) * 100) : 0,
      avgAccuracy: r.games > 0 ? Number((r.accSum / r.games).toFixed(1)) : 0,
      avgEvalMove10: r.eval10Count > 0 ? Number((r.eval10Sum / r.eval10Count).toFixed(2)) : null,
      deviationCount: r.deviationCount,
      mostCostly: r.mostCostly,
    }))
    .sort((a, b) => b.games - a.games || b.winRate - a.winRate);
}
