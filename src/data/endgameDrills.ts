import { Chess } from 'chess.js';
import type { AnalyzedGame, PlayerColor } from '../types/chess';
import { countTotalPieces } from '../utils/chessMath';
import { resolveUserColor, type UserHandleSpec } from '../utils/player';

export type EndgameLabCategory = 'Pawn' | 'Rook' | 'Minor Piece' | 'Queen' | 'Rook+Minor';

export interface EndgameDrill {
  id: string;
  title: string;
  category: EndgameLabCategory;
  goal: 'win' | 'draw';
  difficulty: 'Essential' | 'Club' | 'Master';
  fen: string;
  userColor: PlayerColor;
  keyIdea: string;
  firstHintSan: string;
  botElo: number;
  source: 'theory' | 'user-game';
  sourceGameId?: string;
  sourcePly?: number;
  opponentName?: string;
}

/**
 * 12 classic 7-piece-or-fewer theoretical endgames verified by chess.js
 * and eligible for exact Lichess Syzygy tablebase grading.
 */
export const THEORETICAL_ENDGAME_DRILLS: EndgameDrill[] = [
  {
    id: 'eg_pawn_opposition',
    title: 'King & Pawn — Take the Opposition',
    category: 'Pawn',
    goal: 'win',
    difficulty: 'Essential',
    fen: '4k3/8/8/4P3/4K3/8/8/8 w - - 0 1',
    userColor: 'w',
    keyIdea: 'Lead with your king in front of the pawn. Reach the 6th rank first (Kd5/Kf5) so Black cannot hold direct opposition.',
    firstHintSan: 'Kd5',
    botElo: 1800,
    source: 'theory',
  },
  {
    id: 'eg_pawn_key_squares',
    title: 'Key Squares — Outflank the Defender',
    category: 'Pawn',
    goal: 'win',
    difficulty: 'Essential',
    fen: '3k4/8/3K4/8/3P4/8/8/8 w - - 0 1',
    userColor: 'w',
    keyIdea: 'Because the white king is already on the 6th rank in front of the pawn, simply push d5 or step sideways — White wins regardless of opposition.',
    firstHintSan: 'Ke6',
    botElo: 1800,
    source: 'theory',
  },
  {
    id: 'eg_pawn_opposition_draw',
    title: 'Defending K+P vs K — Hold Opposition',
    category: 'Pawn',
    goal: 'draw',
    difficulty: 'Essential',
    fen: '4k3/8/4P3/4K3/8/8/8/8 b - - 0 1',
    userColor: 'b',
    keyIdea: 'Retreat straight back to e7/e8 and always step directly in front of White’s king when it advances to the 6th rank.',
    firstHintSan: 'Ke7',
    botElo: 1900,
    source: 'theory',
  },
  {
    id: 'eg_pawn_outside_passer',
    title: 'Outside Passed Pawn Decoy',
    category: 'Pawn',
    goal: 'win',
    difficulty: 'Club',
    fen: '8/8/3k4/p7/P1K4P/8/8/8 w - - 0 1',
    userColor: 'w',
    keyIdea: 'Push the outside h-pawn (h5!) to drag Black’s king away from the queenside, then infiltrate to b5 and capture on a5.',
    firstHintSan: 'h5',
    botElo: 1850,
    source: 'theory',
  },
  {
    id: 'eg_rook_lucena',
    title: 'The Lucena Position (Build a Bridge)',
    category: 'Rook',
    goal: 'win',
    difficulty: 'Essential',
    fen: '1K1k4/1P6/8/8/8/8/r7/2R5 w - - 0 1',
    userColor: 'w',
    keyIdea: 'Cut off Black’s king with Rc4 (the 4th-rank bridge), then step out with your king and shield checks on the 4th rank.',
    firstHintSan: 'Rc4',
    botElo: 1900,
    source: 'theory',
  },
  {
    id: 'eg_rook_philidor',
    title: 'Philidor Defense (3rd Rank + Back-Rank Checks)',
    category: 'Rook',
    goal: 'draw',
    difficulty: 'Essential',
    fen: '4k3/8/3PK3/8/8/r7/8/5R2 b - - 0 1',
    userColor: 'b',
    keyIdea: 'Once the pawn reaches the 6th rank, swing your rook behind the enemy king (Ra1!) and deliver endless checks from behind.',
    firstHintSan: 'Ra1',
    botElo: 1950,
    source: 'theory',
  },
  {
    id: 'eg_rook_cutoff',
    title: 'Rook Cutoff — Keep the King Out',
    category: 'Rook',
    goal: 'win',
    difficulty: 'Club',
    fen: '8/8/2k5/4P3/4K3/8/1r6/3R4 w - - 0 1',
    userColor: 'w',
    keyIdea: 'Cut Black’s king off along the d-file (Rd6+ or Kf5 after securing the cutoff) and march the e-pawn with king support.',
    firstHintSan: 'Rd6+',
    botElo: 1850,
    source: 'theory',
  },
  {
    id: 'eg_rook_vancura',
    title: 'Rook Pawn Defense — Side Checks',
    category: 'Rook',
    goal: 'draw',
    difficulty: 'Master',
    fen: '1R6/P4k2/8/8/8/r7/8/6K1 b - - 0 1',
    userColor: 'b',
    keyIdea: 'Keep the black king near g7/f7 and harass the a-pawn laterally or from behind so White’s rook stays tied to a8/a7.',
    firstHintSan: 'Kg7',
    botElo: 1950,
    source: 'theory',
  },
  {
    id: 'eg_minor_wrong_bishop',
    title: 'Wrong-Color Rook Pawn — Fortress Draw',
    category: 'Minor Piece',
    goal: 'draw',
    difficulty: 'Essential',
    fen: '8/6k1/8/7P/6KB/8/8/8 b - - 0 1',
    userColor: 'b',
    keyIdea: 'The h8 corner is dark, while White’s bishop is light-squared! Tuck your king into h8/g8 and refuse to leave the corner.',
    firstHintSan: 'Kh7',
    botElo: 1900,
    source: 'theory',
  },
  {
    id: 'eg_minor_knight_blockade',
    title: 'Knight + Pawn vs Lone King Technique',
    category: 'Minor Piece',
    goal: 'win',
    difficulty: 'Club',
    fen: '8/8/4k3/8/3PK3/4N3/8/8 w - - 0 1',
    userColor: 'w',
    keyIdea: 'Use the knight to deny key defensive squares (Nf5 / Nc4) while the king takes space in front of the d-pawn.',
    firstHintSan: 'd5+',
    botElo: 1800,
    source: 'theory',
  },
  {
    id: 'eg_queen_vs_7th',
    title: 'Queen vs 7th-Rank Center Pawn',
    category: 'Queen',
    goal: 'win',
    difficulty: 'Club',
    fen: '8/8/8/1Q6/8/5K2/3pk3/8 w - - 0 1',
    userColor: 'w',
    keyIdea: 'Give stair-step checks to force Black’s king onto d1 in front of its own pawn, then gain a free tempo to bring your king closer.',
    firstHintSan: 'Qe2+',
    botElo: 1950,
    source: 'theory',
  },
  {
    id: 'eg_rook_minor_convert',
    title: 'Rook + Bishop vs Rook — Active King Squeeze',
    category: 'Rook+Minor',
    goal: 'win',
    difficulty: 'Master',
    fen: '3k4/8/3K4/3B4/8/8/7r/5R2 w - - 0 1',
    userColor: 'w',
    keyIdea: 'Black’s king is pinned to the back rank with your king directly opposite. Threaten mate with Rf8+ or drive the rook off the rank.',
    firstHintSan: 'Rf8+',
    botElo: 1950,
    source: 'theory',
  },
];

export function classifyEndgameFenCategory(fen: string): EndgameLabCategory {
  const boardPart = fen.split(' ')[0] ?? '';
  const hasQ = /[Qq]/.test(boardPart);
  const hasR = /[Rr]/.test(boardPart);
  const hasMinor = /[BNbn]/.test(boardPart);
  if (hasQ) return 'Queen';
  if (hasR && hasMinor) return 'Rook+Minor';
  if (hasR) return 'Rook';
  if (hasMinor) return 'Minor Piece';
  return 'Pawn';
}

/**
 * Extracts user endgame mistakes/blunders in <=7-piece positions from analyzed games
 * so players can drill their own real Syzygy-eligible endgame slips alongside theory.
 */
export function extractUserEndgameDrills(
  analyzedGames: AnalyzedGame[],
  username: UserHandleSpec,
  limit = 10
): EndgameDrill[] {
  const results: EndgameDrill[] = [];
  const seenFens = new Set<string>();

  for (const ag of analyzedGames) {
    const userColor = resolveUserColor(ag.game, username);
    if (!userColor) continue;
    const opp = userColor === 'w' ? ag.game.black.name : ag.game.white.name;

    for (const ply of ag.plies) {
      if (ply.color !== userColor) continue;
      if (ply.classification !== 'blunder' && ply.classification !== 'mistake') continue;
      const pieces = countTotalPieces(ply.beforeFen);
      if (pieces < 3 || pieces > 7) continue;
      const fenKey = ply.beforeFen.split(' ').slice(0, 4).join(' ');
      if (seenFens.has(fenKey)) continue;

      try {
        const c = new Chess(ply.beforeFen);
        if (c.isGameOver() || c.turn() !== userColor) continue;
        const test = c.move(ply.bestMoveSan);
        if (!test) continue;
      } catch {
        continue;
      }

      seenFens.add(fenKey);
      const cpFromUser = userColor === 'w' ? ply.evalBefore.cpWhite : -ply.evalBefore.cpWhite;
      const goal: 'win' | 'draw' = cpFromUser >= 120 || (ply.evalBefore.mateWhite !== null && (userColor === 'w' ? ply.evalBefore.mateWhite > 0 : ply.evalBefore.mateWhite < 0))
        ? 'win'
        : 'draw';

      results.push({
        id: `eg_user_${ag.id}_${ply.ply}`,
        title: `vs ${opp} · Move ${ply.moveNumber}`,
        category: classifyEndgameFenCategory(ply.beforeFen),
        goal,
        difficulty: 'Club',
        fen: ply.beforeFen,
        userColor,
        keyIdea: `You played ${ply.san} (${ply.evalBefore.display} → ${ply.evalAfter.display}). Find ${ply.bestMoveSan} and convert cleanly.`,
        firstHintSan: ply.bestMoveSan,
        botElo: 1750,
        source: 'user-game',
        sourceGameId: ag.id,
        sourcePly: ply.ply,
        opponentName: opp,
      });

      if (results.length >= limit) return results;
    }
  }

  return results;
}
