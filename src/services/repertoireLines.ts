import { Chess } from 'chess.js';
import type { OpeningCourse, OpeningLine } from '../types/openings';

export interface ParsedLineMovesResult {
  ok: true;
  moves: string[];
}

export interface ParsedLineMovesError {
  ok: false;
  error: string;
}

/**
 * Parses and validates a raw SAN move list (e.g. "1. d4 Nf6 2. Bf4 d5 3. e3 c5"
 * or "d4 Nf6 Bf4 d5") via chess.js, guaranteeing 100% legal canonical SAN output.
 */
export function parseAndValidateLineMoves(
  rawMoves: string
): ParsedLineMovesResult | ParsedLineMovesError {
  const cleaned = rawMoves
    .replace(/\{[^}]*\}/g, ' ')
    .replace(/\([^)]*\)/g, ' ')
    .replace(/\b\d+\.+/g, ' ')
    .replace(/\b(1-0|0-1|1\/2-1\/2|\*)\b/g, ' ')
    .trim();

  if (!cleaned) {
    return { ok: false, error: 'Enter at least 2 legal moves (e.g., 1. e4 e5 2. Nf3 Nc6).' };
  }

  const tokens = cleaned.split(/\s+/).filter(Boolean);
  if (tokens.length < 2) {
    return { ok: false, error: 'Enter at least 2 legal moves so the drill has a response.' };
  }

  const chess = new Chess();
  const canonical: string[] = [];
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i].replace(/[?!]+$/g, '');
    try {
      const mv = chess.move(token);
      if (!mv) {
        return { ok: false, error: `Illegal move "${tokens[i]}" at ply ${i + 1}.` };
      }
      canonical.push(mv.san);
    } catch {
      return { ok: false, error: `Illegal move "${tokens[i]}" at ply ${i + 1}.` };
    }
  }

  return { ok: true, moves: canonical };
}

/**
 * Builds a clean new OpeningLine with an annotation anchored on the user's last move
 * (so it always passes the side-color annotation invariant).
 */
export function createCustomCourseLine(params: {
  course: OpeningCourse;
  title: string;
  eco?: string;
  planNote?: string;
  moves: string[];
  existingLineId?: string;
}): OpeningLine {
  const { course, title, eco, planNote, moves, existingLineId } = params;
  const userTurnParity = course.side === 'white' ? 0 : 1;
  let notePly = -1;
  for (let i = moves.length - 1; i >= 0; i--) {
    if (i % 2 === userTurnParity) {
      notePly = i;
      break;
    }
  }
  const trimmedNote = planNote?.trim() ?? '';
  const slug = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 32) || 'line';

  return {
    id: existingLineId ?? `custom-${slug}-${Date.now().toString(36)}`,
    title: title.trim() || 'Custom Variation',
    subtitle: trimmedNote || 'Custom repertoire line',
    eco: eco?.trim().toUpperCase() ?? '',
    frequencyNote: 'Custom repertoire line',
    moves,
    annotations:
      trimmedNote && notePly >= 0
        ? [{ ply: notePly, plan: trimmedNote }]
        : [],
  };
}

export function upsertLineInCourse(course: OpeningCourse, line: OpeningLine): OpeningCourse {
  const idx = course.lines.findIndex((l) => l.id === line.id);
  const nextLines =
    idx === -1
      ? [...course.lines, line]
      : course.lines.map((l, i) => (i === idx ? line : l));
  return {
    ...course,
    lines: nextLines,
  };
}

export function removeLineFromCourse(course: OpeningCourse, lineId: string): OpeningCourse {
  if (course.lines.length <= 1) return course;
  return {
    ...course,
    lines: course.lines.filter((l) => l.id !== lineId),
  };
}
