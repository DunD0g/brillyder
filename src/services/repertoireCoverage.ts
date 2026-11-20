import { Chess } from 'chess.js';
import type { FsrsOpeningCard, OpeningCourse, OpeningLine, Side } from '../types/openings';
import { getBookPosition } from '../chess/openingBook';
import { hydrateLineCards, normalizeFenKey } from '../lib/fsrsOpening';
import {
  fetchLichessExplorer,
  type ExplorerMoveStat,
  type ExplorerQueryOptions,
} from './openingExplorer';

export interface RepertoireGap {
  id: string;
  fen: string;
  moveSequence: string[];
  opponentSan: string;
  opponentUci: string;
  replyShare: number;
  lineProb: number;
  games: number;
  white: number;
  draws: number;
  black: number;
  source: 'lichess' | 'book';
}

export interface CoverageReport {
  courseId: string;
  side: Side;
  expectedCoveragePct: number;
  positionsScanned: number;
  coveredReplies: number;
  uncoveredGaps: RepertoireGap[];
  source: 'lichess' | 'book';
}

export interface RepertoireTreeNode {
  fen: string;
  moveSequence: string[];
  /** Map from SAN -> child FEN key */
  replies: Map<string, { san: string; uci: string; nextFen: string; nextKey: string }>;
}

/**
 * Builds a transposition-aware position graph from an OpeningCourse's lines.
 */
export function buildCoursePositionGraph(course: OpeningCourse): Map<string, RepertoireTreeNode> {
  const graph = new Map<string, RepertoireTreeNode>();

  for (const line of course.lines) {
    const chess = new Chess();
    const seq: string[] = [];
    for (const san of line.moves) {
      const fen = chess.fen();
      const key = normalizeFenKey(fen);
      let node = graph.get(key);
      if (!node) {
        node = { fen, moveSequence: [...seq], replies: new Map() };
        graph.set(key, node);
      }
      const mv = chess.move(san);
      const nextFen = chess.fen();
      const nextKey = normalizeFenKey(nextFen);
      const uci = `${mv.from}${mv.to}${mv.promotion ?? ''}`;
      if (!node.replies.has(mv.san)) {
        node.replies.set(mv.san, { san: mv.san, uci, nextFen, nextKey });
      }
      seq.push(mv.san);
    }
  }

  return graph;
}

export interface ExplorerFetcher {
  (fen: string, sanHistory: string[]): Promise<{
    games: number;
    moves: ExplorerMoveStat[];
    source: 'lichess' | 'book';
  } | null>;
}

function makeDefaultFetcher(options: ExplorerQueryOptions): ExplorerFetcher {
  return async (fen, sanHistory) => {
    const live = await fetchLichessExplorer(fen, options);
    if (live && live.games > 0) {
      return { games: live.games, moves: live.moves, source: 'lichess' };
    }
    const local = getBookPosition(sanHistory);
    if (local.continuations.length === 0) return null;
    const c = new Chess(fen);
    const total = local.continuations.reduce((s, m) => s + Math.max(1, m.lineCount), 0);
    const moves: ExplorerMoveStat[] = [];
    for (const cont of local.continuations) {
      const clone = new Chess(c.fen());
      try {
        const mv = clone.move(cont.san);
        const count = Math.max(1, cont.lineCount);
        moves.push({
          san: mv.san,
          uci: `${mv.from}${mv.to}${mv.promotion ?? ''}`,
          white: Math.round(count * 0.45),
          draws: Math.round(count * 0.15),
          black: Math.max(0, count - Math.round(count * 0.45) - Math.round(count * 0.15)),
          games: count,
        });
      } catch {
        // skip
      }
    }
    return moves.length > 0 ? { games: total, moves, source: 'book' } : null;
  };
}

/**
 * Evaluates Real-World Coverage % for a course against opponent replies played >= minReplyShare
 * down to cumulative probability >= minLineProb (default: >= 5% reply, >= 2% line prob).
 */
export async function computeCourseCoverage(
  course: OpeningCourse,
  options: ExplorerQueryOptions & {
    minReplyShare?: number;
    minLineProb?: number;
    maxDepthPlies?: number;
    maxApiCalls?: number;
    fetcher?: ExplorerFetcher;
    shouldCancel?: () => boolean;
  } = {}
): Promise<CoverageReport> {
  const minReplyShare = options.minReplyShare ?? 0.05;
  const minLineProb = options.minLineProb ?? 0.02;
  const maxDepthPlies = options.maxDepthPlies ?? 10;
  const maxApiCalls = options.maxApiCalls ?? 14;
  const fetcher = options.fetcher ?? makeDefaultFetcher(options);
  const graph = buildCoursePositionGraph(course);
  const userTurn = course.side === 'white' ? 'w' : 'b';

  const startFen = new Chess().fen();
  const startKey = normalizeFenKey(startFen);

  interface QueueItem {
    key: string;
    fen: string;
    moveSequence: string[];
    prob: number;
    depth: number;
  }

  const queue: QueueItem[] = [{ key: startKey, fen: startFen, moveSequence: [], prob: 1, depth: 0 }];
  const visited = new Set<string>();
  const gapMap = new Map<string, RepertoireGap>();

  let positionsScanned = 0;
  let coveredWeight = 0;
  let uncoveredWeight = 0;
  let coveredReplies = 0;
  let usedLichess = false;

  while (queue.length > 0 && positionsScanned < maxApiCalls) {
    if (options.shouldCancel?.()) break;
    queue.sort((a, b) => b.prob - a.prob);
    const cur = queue.shift()!;
    if (cur.depth >= maxDepthPlies || cur.prob < minLineProb) continue;
    if (visited.has(cur.key)) continue;
    visited.add(cur.key);

    const node = graph.get(cur.key);
    const turn = cur.fen.split(' ')[1] === 'b' ? 'b' : 'w';

    if (turn === userTurn) {
      if (!node || node.replies.size === 0) continue;
      // On user turns, follow our repertoire replies (split weight if multiple user choices exist)
      const choices = Array.from(node.replies.values());
      const share = 1 / choices.length;
      for (const reply of choices) {
        queue.push({
          key: reply.nextKey,
          fen: reply.nextFen,
          moveSequence: [...cur.moveSequence, reply.san],
          prob: cur.prob * share,
          depth: cur.depth + 1,
        });
      }
      continue;
    }

    // Opponent turn: query Lichess Explorer (or fallback) for real opponent replies
    positionsScanned++;
    const stats = await fetcher(cur.fen, cur.moveSequence);
    if (!stats || stats.games <= 0 || stats.moves.length === 0) continue;
    if (stats.source === 'lichess') usedLichess = true;

    for (const oppMove of stats.moves) {
      const replyShare = oppMove.games / stats.games;
      const branchProb = cur.prob * replyShare;
      if (replyShare < minReplyShare || branchProb < minLineProb) continue;

      const repEdge = node?.replies.get(oppMove.san);
      const afterNode = repEdge ? graph.get(repEdge.nextKey) : undefined;
      const hasUserAnswer = Boolean(afterNode && afterNode.replies.size > 0);

      if (repEdge && hasUserAnswer) {
        coveredWeight += branchProb;
        coveredReplies++;
        queue.push({
          key: repEdge.nextKey,
          fen: repEdge.nextFen,
          moveSequence: [...cur.moveSequence, oppMove.san],
          prob: branchProb,
          depth: cur.depth + 1,
        });
      } else {
        uncoveredWeight += branchProb;
        const c = new Chess(cur.fen);
        let afterFen = '';
        try {
          c.move(oppMove.san);
          afterFen = c.fen();
        } catch {
          continue;
        }
        const gapKey = `${normalizeFenKey(afterFen)}::${oppMove.san}`;
        const existing = gapMap.get(gapKey);
        if (!existing || branchProb > existing.lineProb) {
          gapMap.set(gapKey, {
            id: gapKey,
            fen: afterFen,
            moveSequence: [...cur.moveSequence, oppMove.san],
            opponentSan: oppMove.san,
            opponentUci: oppMove.uci,
            replyShare,
            lineProb: branchProb,
            games: oppMove.games,
            white: oppMove.white,
            draws: oppMove.draws,
            black: oppMove.black,
            source: stats.source,
          });
        }
      }
    }
  }

  const totalWeight = coveredWeight + uncoveredWeight;
  const expectedCoveragePct = totalWeight > 0
    ? Math.round((coveredWeight / totalWeight) * 100)
    : 100;

  const uncoveredGaps = Array.from(gapMap.values()).sort((a, b) => b.lineProb - a.lineProb);

  return {
    courseId: course.id,
    side: course.side,
    expectedCoveragePct,
    positionsScanned,
    coveredReplies,
    uncoveredGaps,
    source: usedLichess ? 'lichess' : 'book',
  };
}

/**
 * Adds a 1-click "Patch Gap" line to an OpeningCourse and generates unlocked FSRS cards.
 */
export function addPatchedLineToCourse(
  course: OpeningCourse,
  moveSequenceToGap: string[],
  userReplySan: string,
  options: { title?: string; planNote?: string; now?: Date } = {}
): { updatedCourse: OpeningCourse; newLine: OpeningLine; newCards: FsrsOpeningCard[] } {
  const chess = new Chess();
  const fullMoves: string[] = [];
  for (const san of moveSequenceToGap) {
    const mv = chess.move(san);
    fullMoves.push(mv.san);
  }
  const replyMv = chess.move(userReplySan);
  const replyPly = fullMoves.length;
  fullMoves.push(replyMv.san);

  const expectedTurn = course.side === 'white' ? 'w' : 'b';
  if (replyMv.color !== expectedTurn) {
    throw new Error(`Reply "${userReplySan}" does not belong to ${course.side}.`);
  }

  const oppLast = moveSequenceToGap[moveSequenceToGap.length - 1] ?? 'sideline';
  const moveNum = Math.floor(replyPly / 2) + 1;
  const lineId = `${course.id}-patch-${Date.now().toString(36)}`;
  const newLine: OpeningLine = {
    id: lineId,
    title: options.title ?? `Patched vs ...${oppLast} (${moveNum}${replyMv.color === 'w' ? '.' : '…'}${replyMv.san})`,
    subtitle: `Added via 1-click Gap Patcher`,
    eco: course.lines[0]?.eco ?? '',
    frequencyNote: 'Patched real-world gap at your rating band',
    moves: fullMoves,
    annotations: [
      {
        ply: replyPly,
        isCritical: true,
        plan: options.planNote ?? `Patched repertoire answer ${replyMv.san} against ${oppLast}.`,
        arrows: [{ from: replyMv.from, to: replyMv.to, color: 'best' }],
      },
    ],
  };

  const updatedCourse: OpeningCourse = {
    ...course,
    lines: [...course.lines, newLine],
  };

  const newCards = hydrateLineCards(course.id, course.side, newLine, undefined, {
    unlocked: true,
    now: options.now,
  });

  return { updatedCourse, newLine, newCards };
}
