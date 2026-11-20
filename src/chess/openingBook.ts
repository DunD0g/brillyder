import type { PlayerColor } from '../types/chess';
import { OPENING_BOOK, OPENING_FAMILIES, type OpeningEntry, type OpeningFamily } from './openingBookData';

export type { OpeningEntry } from './openingBookData';

export interface RecognizedOpening {
  matchedPlies: number;
  eco: string;
  name: string;
}

export interface BookContinuation {
  san: string;
  eco: string;
  name: string;
  lineCount: number;
  weight: number;
  share: number;
}

export interface BookPosition {
  inBook: boolean;
  /** Number of plies that still match the offline book. */
  depth: number;
  recognized: RecognizedOpening | null;
  continuations: BookContinuation[];
  totalWeight: number;
}

export interface OpeningDeviation {
  /** 1-based ply index of the first move outside the book. */
  ply: number;
  moveNumber: number;
  color: PlayerColor;
  san: string;
  isUserMove: boolean;
  openingName: string;
  openingEco: string;
  /** Number of plies that matched the book before this move. */
  bookPlies: number;
  expected: string[];
  expectedNames: Array<{ san: string; name: string }>;
  confidence: 'high' | 'medium' | 'low';
}

export interface OpeningReport {
  recognized: RecognizedOpening | null;
  openingName: string | null;
  openingEco: string;
  bookPlies: number;
  totalPlies: number;
  firstDeviation: OpeningDeviation | null;
  userDeviation: OpeningDeviation | null;
  opponentDeviation: OpeningDeviation | null;
  followedBook: boolean;
}

interface BookNode {
  children: Map<string, BookNode>;
  bestEntry: OpeningEntry | null;
  weight: number;
  lineCount: number;
  depth: number;
}

const MIN_DEVIATION_PLY = 2; // judge from the third ply; 1.e4 / 1.d4 choices stay free
const DEFAULT_MAX_PLY = 16;

export const OPENING_BOOK_SIZE = OPENING_BOOK.length;

function makeNode(depth: number): BookNode {
  return { children: new Map(), bestEntry: null, weight: 0, lineCount: 0, depth };
}

function isBetterEntry(candidate: OpeningEntry, current: OpeningEntry | null): boolean {
  if (!current) return true;
  if (candidate.weight !== current.weight) return candidate.weight > current.weight;
  return candidate.moves.length > current.moves.length;
}

function buildBook(): BookNode {
  const root = makeNode(0);
  for (const entry of OPENING_BOOK) {
    const weight = Math.max(1, entry.weight);
    let node = root;
    node.weight += weight;
    node.lineCount += 1;
    if (isBetterEntry(entry, node.bestEntry)) node.bestEntry = entry;

    for (const san of entry.moves) {
      let child = node.children.get(san);
      if (!child) {
        child = makeNode(node.depth + 1);
        node.children.set(san, child);
      }
      node = child;
      node.weight += weight;
      node.lineCount += 1;
      if (isBetterEntry(entry, node.bestEntry)) node.bestEntry = entry;
    }
  }
  return root;
}

const BOOK_ROOT = buildBook();

function walkBook(sanHistory: string[], limit = sanHistory.length): { node: BookNode; depth: number } {
  let node = BOOK_ROOT;
  let depth = 0;
  const max = Math.min(limit, sanHistory.length);
  for (; depth < max; depth++) {
    const child = node.children.get(sanHistory[depth]);
    if (!child) break;
    node = child;
  }
  return { node, depth };
}

function recognizedAt(node: BookNode, depth: number): RecognizedOpening | null {
  if (!node.bestEntry || depth < 3) return null;
  return { matchedPlies: depth, eco: node.bestEntry.eco, name: node.bestEntry.name };
}

export function lookupOpeningByMoves(sanHistory: string[]): RecognizedOpening | null {
  const { node, depth } = walkBook(sanHistory);
  return recognizedAt(node, depth);
}

/**
 * A short, stable opening name for the current prefix. This is what the UI
 * shows for rows such as 1...c5 ("Sicilian Defense") instead of naming the
 * deepest book line that happens to pass through the move.
 */
export function lookupOpeningFamily(sanHistory: string[]): RecognizedOpening | null {
  let best: OpeningFamily | null = null;
  for (const family of OPENING_FAMILIES) {
    if (family.moves.length > sanHistory.length) continue;
    let matches = true;
    for (let i = 0; i < family.moves.length; i++) {
      if (sanHistory[i] !== family.moves[i]) { matches = false; break; }
    }
    if (matches && (!best || family.moves.length > best.moves.length)) best = family;
  }
  return best ? { matchedPlies: best.moves.length, eco: best.eco, name: best.name } : null;
}

/**
 * The theory moves available from a position. When the position has left the
 * book the continuation list is empty; `depth` still says how many plies of
 * the supplied history were recognised.
 */
export function getBookPosition(sanHistory: string[]): BookPosition {
  const { node, depth } = walkBook(sanHistory);
  const inBook = depth === sanHistory.length;
  const totalWeight = node.weight;
  const continuations: BookContinuation[] = inBook
    ? [...node.children.entries()]
        .map(([san, child]) => {
          const nextFamily = lookupOpeningFamily([...sanHistory, san]);
          return {
            san,
            eco: nextFamily?.eco ?? child.bestEntry?.eco ?? '',
            name: nextFamily?.name ?? child.bestEntry?.name ?? 'Opening',
            lineCount: child.lineCount,
            weight: child.weight,
            share: totalWeight > 0 ? child.weight / totalWeight : 0,
          };
        })
        .sort((a, b) => b.weight - a.weight || a.san.localeCompare(b.san))
    : [];

  return {
    inBook,
    depth,
    recognized: lookupOpeningFamily(sanHistory) ?? recognizedAt(node, depth),
    continuations,
    totalWeight,
  };
}

interface DeviationWalk {
  deviation: OpeningDeviation | null;
  depth: number;
}

function findFirstDeviation(sanHistory: string[], userColor: PlayerColor, maxPly: number): DeviationWalk {
  let node = BOOK_ROOT;
  const limit = Math.min(sanHistory.length, Math.max(0, maxPly));

  for (let i = 0; i < limit; i++) {
    if (node.children.size === 0) return { deviation: null, depth: i };
    const child = node.children.get(sanHistory[i]);
    if (!child) {
      // The opening choice itself (1.e4, 1.d4, 1.Nf3, ...) is deliberately
      // left alone. From the third ply onward an unknown move is actionable.
      if (i < MIN_DEVIATION_PLY) return { deviation: null, depth: i };

      const color: PlayerColor = i % 2 === 0 ? 'w' : 'b';
      const prefix = sanHistory.slice(0, i);
      const family = lookupOpeningFamily(prefix);
      const expectedNames = [...node.children.entries()]
        .sort(([, a], [, b]) => b.weight - a.weight || 0)
        .slice(0, 6)
        .map(([san, next]) => {
          const nextFamily = lookupOpeningFamily([...prefix, san]);
          return { san, name: nextFamily?.name ?? next.bestEntry?.name ?? 'Opening' };
        });

      return {
        deviation: {
          ply: i + 1,
          moveNumber: Math.floor(i / 2) + 1,
          color,
          san: sanHistory[i],
          isUserMove: color === userColor,
          openingName: family?.name ?? node.bestEntry?.name ?? 'Opening',
          openingEco: family?.eco ?? node.bestEntry?.eco ?? '',
          bookPlies: i,
          expected: expectedNames.map((entry) => entry.san),
          expectedNames,
          confidence: node.lineCount >= 4 ? 'high' : node.lineCount >= 2 ? 'medium' : 'low',
        },
        depth: i,
      };
    }
    node = child;
  }

  return { deviation: null, depth: Math.min(limit, sanHistory.length) };
}

/**
 * Returns the first move by `userColor` that leaves the offline opening book,
 * or null when the player stayed in theory (or the book ran out first).
 */
export function findOpeningDeviation(
  sanHistory: string[],
  userColor: PlayerColor,
  maxPly = DEFAULT_MAX_PLY,
): OpeningDeviation | null {
  const { deviation } = findFirstDeviation(sanHistory, userColor, maxPly);
  return deviation?.isUserMove ? deviation : null;
}

export function buildOpeningReport(
  sanHistory: string[],
  userColor: PlayerColor,
  maxPly = DEFAULT_MAX_PLY,
): OpeningReport {
  const walk = findFirstDeviation(sanHistory, userColor, maxPly);
  // A thin book (a single recorded continuation) is not enough evidence to
  // tell the user their opponent left theory. Treat that as the end of the
  // line instead of raising a low-confidence warning on move two.
  const deviation =
    walk.deviation && !walk.deviation.isUserMove && walk.deviation.confidence === 'low'
      ? null
      : walk.deviation;
  const bookPlies = deviation ? deviation.bookPlies : walk.depth;
  const prefix = sanHistory.slice(0, bookPlies);
  const family = lookupOpeningFamily(prefix);
  const recognized =
    (family && family.matchedPlies >= 2 ? family : null) ??
    lookupOpeningByMoves(prefix) ??
    (deviation && bookPlies >= 2
      ? { matchedPlies: bookPlies, eco: deviation.openingEco, name: deviation.openingName }
      : null);

  return {
    recognized,
    openingName: recognized?.name ?? deviation?.openingName ?? null,
    openingEco: recognized?.eco ?? deviation?.openingEco ?? '',
    bookPlies,
    totalPlies: sanHistory.length,
    firstDeviation: deviation,
    userDeviation: deviation?.isUserMove ? deviation : null,
    opponentDeviation: deviation && !deviation.isUserMove ? deviation : null,
    followedBook: !deviation && bookPlies > 0,
  };
}

export function isBookPly(plyIndex: number, sanPrefix: string[], lichessOpeningPly?: number, winLoss = 0): boolean {
  if (plyIndex >= 16 || winLoss > 8) return false;
  if (sanPrefix.length > 0 && walkBook(sanPrefix).depth === sanPrefix.length) return true;
  if (lichessOpeningPly && plyIndex < Math.min(lichessOpeningPly, 14) && winLoss <= 6) return true;
  return false;
}
