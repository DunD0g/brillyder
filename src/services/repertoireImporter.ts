import { Chess } from 'chess.js';
import type { MoveAnnotation, OpeningCourse, OpeningLine, Side } from '../types/openings';
import { lookupOpeningByMoves } from '../chess/openingBook';

export interface ImportCourseInput {
  name: string;
  side: Side;
  pgn: string;
  source?: 'pgn' | 'lichess-study';
  difficulty?: OpeningCourse['difficulty'];
}

interface ParsedBranch {
  title: string;
  eco: string;
  moves: string[];
  annotations: MoveAnnotation[];
}

const LICHESS_STUDY_RE = /lichess\.org\/study\/([A-Za-z0-9]{8})(?:\/([A-Za-z0-9]{8}))?/;

export function extractLichessStudyIds(input: string): { studyId: string; chapterId?: string } | null {
  const m = input.trim().match(LICHESS_STUDY_RE);
  if (!m) return null;
  return { studyId: m[1], chapterId: m[2] };
}

export async function fetchLichessStudyPgn(urlOrId: string): Promise<string> {
  const ids = extractLichessStudyIds(urlOrId);
  const studyId = ids?.studyId ?? (/^[A-Za-z0-9]{8}$/.test(urlOrId.trim()) ? urlOrId.trim() : null);
  if (!studyId) {
    throw new Error('Paste a valid Lichess Study URL (e.g. https://lichess.org/study/XXXXXXXX).');
  }
  const endpoint = ids?.chapterId
    ? `https://lichess.org/api/study/${studyId}/${ids.chapterId}.pgn?comments=true&variations=true&clocks=false`
    : `https://lichess.org/api/study/${studyId}.pgn?comments=true&variations=true&clocks=false`;

  const res = await fetch(endpoint, { headers: { Accept: 'application/x-chess-pgn, text/plain' } });
  if (!res.ok) {
    throw new Error(
      res.status === 404
        ? 'Lichess study not found or is set to Private/Unlisted.'
        : `Could not fetch Lichess study (HTTP ${res.status}).`
    );
  }
  const text = await res.text();
  if (!text.trim()) throw new Error('Lichess study returned an empty PGN.');
  return text;
}

function splitMultiPgn(raw: string): string[] {
  const normalized = raw.replace(/\r\n/g, '\n').trim();
  if (!normalized) return [];
  const chunks: string[] = [];
  let current: string[] = [];
  let sawMoveText = false;

  for (const line of normalized.split('\n')) {
    const trimmed = line.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      if (sawMoveText && current.length > 0) {
        chunks.push(current.join('\n').trim());
        current = [];
        sawMoveText = false;
      }
      current.push(line);
    } else {
      if (trimmed.length > 0) sawMoveText = true;
      current.push(line);
    }
  }
  if (current.length > 0) chunks.push(current.join('\n').trim());
  return chunks.filter(Boolean);
}

function parseHeaders(pgnChunk: string): Record<string, string> {
  const headers: Record<string, string> = {};
  const re = /^\[([A-Za-z0-9_]+)\s+"([^"]*)"\]$/gm;
  let match: RegExpExecArray | null;
  while ((match = re.exec(pgnChunk)) !== null) {
    headers[match[1]] = match[2];
  }
  return headers;
}

function stripHeaders(pgnChunk: string): string {
  return pgnChunk
    .split('\n')
    .filter((l) => !/^\s*\[[^\]]+\]\s*$/.test(l))
    .join(' ')
    .trim();
}

type Token =
  | { type: 'lparen' }
  | { type: 'rparen' }
  | { type: 'comment'; text: string }
  | { type: 'word'; text: string };

function tokenizeMoveText(text: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (/\s/.test(ch)) { i++; continue; }
    if (ch === '{') {
      const end = text.indexOf('}', i + 1);
      const raw = end === -1 ? text.slice(i + 1) : text.slice(i + 1, end);
      const clean = raw.replace(/\[%[a-zA-Z]+\s+[^\]]*\]/g, '').replace(/\s+/g, ' ').trim();
      if (clean) tokens.push({ type: 'comment', text: clean });
      i = end === -1 ? text.length : end + 1;
      continue;
    }
    if (ch === ';') {
      const end = text.indexOf('\n', i + 1);
      i = end === -1 ? text.length : end + 1;
      continue;
    }
    if (ch === '(') { tokens.push({ type: 'lparen' }); i++; continue; }
    if (ch === ')') { tokens.push({ type: 'rparen' }); i++; continue; }
    let j = i;
    while (j < text.length && !/[\s(){};]/.test(text[j])) j++;
    tokens.push({ type: 'word', text: text.slice(i, j) });
    i = j;
  }
  return tokens;
}

function isMoveNoise(word: string): boolean {
  if (/^\d+\.+$/.test(word)) return true;
  if (/^\$\d+$/.test(word)) return true;
  if (word === '1-0' || word === '0-1' || word === '1/2-1/2' || word === '*') return true;
  return false;
}

/**
 * Expands a single PGN chunk (including nested RAV variations in parentheses)
 * into clean, chess.js-validated OpeningLine branches.
 */
function extractBranchesFromChunk(pgnChunk: string, baseTitle: string, side: Side): ParsedBranch[] {
  const headers = parseHeaders(pgnChunk);
  const body = stripHeaders(pgnChunk);
  const tokens = tokenizeMoveText(body);
  const targetColor = side === 'white' ? 'w' : 'b';

  const rawBranches: Array<{ moves: string[]; comments: Map<number, string> }> = [];
  const MAX_BRANCHES = 24;
  const MAX_PLIES = 24;

  function walk(
    idx: number,
    fen: string,
    moves: string[],
    comments: Map<number, string>,
    prevFen: string | null,
    prevMoves: string[],
    prevComments: Map<number, string>
  ): number {
    let curFen = fen;
    let curMoves = [...moves];
    let curComments = new Map(comments);
    let lastFen = prevFen;
    let lastMoves = [...prevMoves];
    let lastComments = new Map(prevComments);
    let branched = false;

    while (idx < tokens.length) {
      const tok = tokens[idx];
      if (tok.type === 'rparen') {
        idx++;
        break;
      }
      if (tok.type === 'lparen') {
        idx++;
        if (rawBranches.length < MAX_BRANCHES && lastFen) {
          idx = walk(idx, lastFen, lastMoves, lastComments, null, [], new Map());
        } else {
          // Skip extra variation cleanly
          let depth = 1;
          while (idx < tokens.length && depth > 0) {
            if (tokens[idx].type === 'lparen') depth++;
            else if (tokens[idx].type === 'rparen') depth--;
            idx++;
          }
        }
        continue;
      }
      if (tok.type === 'comment') {
        if (curMoves.length > 0 && !curComments.has(curMoves.length - 1)) {
          curComments.set(curMoves.length - 1, tok.text);
        }
        idx++;
        continue;
      }

      const rawWord = tok.text.replace(/^\d+\.+/, '').replace(/[!?]+$/, '');
      idx++;
      if (!rawWord || isMoveNoise(tok.text) || isMoveNoise(rawWord)) continue;
      if (curMoves.length >= MAX_PLIES) continue;

      const board = new Chess(curFen);
      try {
        const mv = board.move(rawWord);
        lastFen = curFen;
        lastMoves = [...curMoves];
        lastComments = new Map(curComments);
        curFen = board.fen();
        curMoves.push(mv.san);
        branched = true;
      } catch {
        // Ignore unrecognized token
      }
    }

    if (curMoves.length > 0 && (branched || rawBranches.length === 0) && rawBranches.length < MAX_BRANCHES) {
      rawBranches.push({ moves: curMoves, comments: curComments });
    }
    return idx;
  }

  walk(0, new Chess().fen(), [], new Map(), null, [], new Map());

  // Fallback to chess.js direct PGN load if custom parser found nothing
  if (rawBranches.length === 0) {
    try {
      const c = new Chess();
      c.loadPgn(pgnChunk);
      const hist = c.history();
      if (hist.length > 0) {
        rawBranches.push({ moves: hist.slice(0, MAX_PLIES), comments: new Map() });
      }
    } catch {
      return [];
    }
  }

  // Deduplicate identical move lines
  const seen = new Set<string>();
  const out: ParsedBranch[] = [];
  const chapterName = headers.Event || headers.ChapterName || headers.Opening || baseTitle;

  rawBranches.forEach((b, i) => {
    const key = b.moves.join(' ');
    if (seen.has(key) || b.moves.length === 0) return;
    seen.add(key);

    // Verify legality and attach side-aligned annotations
    const verify = new Chess();
    const annotations: MoveAnnotation[] = [];
    for (let ply = 0; ply < b.moves.length; ply++) {
      const turn = verify.turn();
      const mv = verify.move(b.moves[ply]);
      const comment = b.comments.get(ply);
      if (comment && turn === targetColor) {
        annotations.push({
          ply,
          plan: comment,
          arrows: [{ from: mv.from, to: mv.to, color: 'best' }],
        });
      }
    }

    const ecoLookup = lookupOpeningByMoves(b.moves);
    const title = i === 0
      ? (headers.Opening || chapterName || `${baseTitle} — Mainline`)
      : `${chapterName} — Sideline ${i}`;

    out.push({
      title,
      eco: headers.ECO || ecoLookup?.eco || '',
      moves: b.moves,
      annotations,
    });
  });

  return out;
}

export function importPgnToCourse(input: ImportCourseInput): OpeningCourse {
  const chunks = splitMultiPgn(input.pgn);
  if (chunks.length === 0) {
    throw new Error('Paste valid PGN moves or a Lichess Study URL to import.');
  }

  const courseName = input.name.trim() || 'Custom Repertoire';
  const slug = courseName
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 32) || 'custom';
  const courseId = `custom-${slug}-${Date.now().toString(36)}`;

  const lines: OpeningLine[] = [];
  const seenMoves = new Set<string>();

  chunks.forEach((chunk, cIdx) => {
    const branches = extractBranchesFromChunk(chunk, `${courseName} #${cIdx + 1}`, input.side);
    branches.forEach((branch, bIdx) => {
      const key = branch.moves.join(' ');
      if (seenMoves.has(key)) return;
      seenMoves.add(key);
      lines.push({
        id: `${courseId}-line-${cIdx + 1}-${bIdx + 1}`,
        title: branch.title,
        subtitle: `${branch.moves.length} plies imported for ${input.side === 'white' ? 'White' : 'Black'}`,
        eco: branch.eco,
        frequencyNote: input.source === 'lichess-study' ? 'Imported from Lichess Study' : 'Imported from PGN',
        moves: branch.moves,
        annotations: branch.annotations,
      });
    });
  });

  if (lines.length === 0) {
    throw new Error('No legal chess moves could be parsed from the provided PGN.');
  }

  const previewLine = lines[0];
  const previewMoves = previewLine.moves.slice(0, Math.min(12, previewLine.moves.length));

  return {
    id: courseId,
    name: courseName,
    codename: input.source === 'lichess-study' ? 'Imported Beacon' : 'Custom Blueprint',
    side: input.side,
    difficulty: input.difficulty ?? 'Intermediate',
    tagline: `${lines.length} imported line${lines.length === 1 ? '' : 's'} for ${input.side === 'white' ? 'White' : 'Black'}.`,
    source: input.source ?? 'pgn',
    mothershipSetup: {
      previewMoves,
      arrows: [],
      highlights: [],
      corePlans: [
        'Walk through each imported branch to lock in key piece placements before drilling.',
        'Use Real-World Coverage to spot common opponent replies missing from this PGN.',
        'Unlock all lines to schedule them automatically in your daily FSRS queue.',
      ],
      goldenRules: [
        'Always check opponent threats before committing to automatic opening moves.',
        'Patch new opponent sidelines directly from your analyzed games via Leak Patcher.',
      ],
    },
    lines,
  };
}
