import { Chess } from 'chess.js';
import type { FsrsOpeningCard, OpeningCourse, OpeningLine } from '../types/openings';
import { getRecallProbability, isCardDue } from '../lib/fsrsOpening';

export interface RepertoireTreeNode {
  id: string;
  san: string;
  ply: number; // 1-based ply (0 = root)
  fen: string;
  lastMove?: [string, string];
  lineIds: string[];
  lineTitles: string[];
  isUserMove: boolean;
  recallPct: number | null; // Average FSRS Signal Strength across matching cards (0..100)
  dueCount: number;
  planNote?: string;
  children: RepertoireTreeNode[];
}

/**
 * Merges every line in an OpeningCourse into a branching move trie annotated
 * with per-node FSRS Signal Strength (recall probability) and due counts.
 */
export function buildRepertoireTree(
  course: OpeningCourse,
  cards: FsrsOpeningCard[] = []
): RepertoireTreeNode {
  const startChess = new Chess();
  const root: RepertoireTreeNode = {
    id: 'root',
    san: 'Start',
    ply: 0,
    fen: startChess.fen(),
    lineIds: course.lines.map((l) => l.id),
    lineTitles: course.lines.map((l) => l.title),
    isUserMove: false,
    recallPct: null,
    dueCount: 0,
    children: [],
  };

  // Index FSRS cards by normalized 4-field FEN + expected SAN
  const cardsByKey = new Map<string, FsrsOpeningCard[]>();
  for (const card of cards) {
    if (card.courseId !== course.id) continue;
    const normFen = card.fen.split(' ').slice(0, 4).join(' ');
    const key = `${normFen}|${card.expectedSan}`;
    const arr = cardsByKey.get(key) ?? [];
    arr.push(card);
    cardsByKey.set(key, arr);
  }

  for (const line of course.lines) {
    const chess = new Chess();
    let cursor = root;
    const noteByPly = new Map<number, string>();
    for (const ann of line.annotations ?? []) {
      if (ann.plan) noteByPly.set(ann.ply, ann.plan);
    }

    for (let i = 0; i < line.moves.length; i++) {
      const san = line.moves[i];
      const beforeNormFen = chess.fen().split(' ').slice(0, 4).join(' ');
      const mv = chess.move(san);
      if (!mv) break;

      const isUserMove =
        (course.side === 'white' && mv.color === 'w') ||
        (course.side === 'black' && mv.color === 'b');

      let child = cursor.children.find((c) => c.san === mv.san);
      if (!child) {
        const matchedCards = cardsByKey.get(`${beforeNormFen}|${mv.san}`) ?? [];
        const unlocked = matchedCards.filter((c) => c.unlocked);
        const recallPct =
          unlocked.length > 0
            ? Math.round(
                unlocked.reduce((sum, c) => sum + getRecallProbability(c), 0) / unlocked.length
              )
            : null;
        const dueCount = unlocked.filter((c) => isCardDue(c)).length;

        child = {
          id: `${cursor.id}/${mv.san}`,
          san: mv.san,
          ply: i + 1,
          fen: chess.fen(),
          lastMove: [mv.from, mv.to],
          lineIds: [],
          lineTitles: [],
          isUserMove,
          recallPct,
          dueCount,
          planNote: noteByPly.get(i),
          children: [],
        };
        cursor.children.push(child);
      } else if (!child.planNote && noteByPly.has(i)) {
        child.planNote = noteByPly.get(i);
      }

      if (!child.lineIds.includes(line.id)) {
        child.lineIds.push(line.id);
        child.lineTitles.push(line.title);
      }
      cursor = child;
    }
  }

  return root;
}

function escapePgnTag(val: string): string {
  return val.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\r?\n/g, ' ').trim();
}

function sanitizePgnComment(text: string): string {
  return text.replace(/[{}]/g, '').replace(/\s+/g, ' ').trim();
}

function formatLineMovesToPgn(line: OpeningLine): string {
  const noteByPly = new Map<number, string>();
  for (const ann of line.annotations ?? []) {
    if (ann.plan) noteByPly.set(ann.ply, ann.plan);
  }
  const chess = new Chess();
  const tokens: string[] = [];
  for (let i = 0; i < line.moves.length; i++) {
    const moveNum = Math.floor(i / 2) + 1;
    const isWhite = i % 2 === 0;
    const mv = chess.move(line.moves[i]);
    if (!mv) break;
    const san = mv.san;
    if (isWhite) {
      tokens.push(`${moveNum}. ${san}`);
    } else {
      tokens.push(i === 0 ? `${moveNum}... ${san}` : san);
    }
    const note = noteByPly.get(i);
    if (note) {
      const clean = sanitizePgnComment(note);
      if (clean) tokens.push(`{ ${clean} }`);
    }
  }
  return `${tokens.join(' ')} *`;
}

/**
 * Exports an entire OpeningCourse (all lines + ECO + plan comments) into
 * standard multi-chapter PGN suitable for Lichess Study import or backup.
 */
export function exportCourseToPgn(course: OpeningCourse): string {
  const chapters = course.lines.map((line) => {
    const headers = [
      `[Event "${escapePgnTag(course.name)}: ${escapePgnTag(line.title)}"]`,
      `[Site "BrillyDer Repertoire Studio"]`,
      `[White "${course.side === 'white' ? escapePgnTag(course.name) : 'Opponent'}"]`,
      `[Black "${course.side === 'black' ? escapePgnTag(course.name) : 'Opponent'}"]`,
      `[Result "*"]`,
      ...(line.eco ? [`[ECO "${escapePgnTag(line.eco)}"]`] : []),
    ];
    return `${headers.join('\n')}\n\n${formatLineMovesToPgn(line)}`;
  });

  return chapters.join('\n\n');
}
