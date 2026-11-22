import { Chess } from 'chess.js';
import type { LichessGameRecord } from '../types/chess';

export function createCustomFenGame(fen: string, label?: string): LichessGameRecord {
  const cleanFen = fen.trim();
  const chess = new Chess(cleanFen);
  const normalized = chess.fen();
  const id = `fen_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 6)}`;
  const pgn = `[Event "${label || 'Custom Position Analysis'}"]\n[Site "BrillyDer Board Editor"]\n[White "White"]\n[Black "Black"]\n[Result "*"]\n[SetUp "1"]\n[FEN "${normalized}"]\n\n*`;
  return {
    id,
    source: 'pgn',
    rated: false,
    variant: 'standard',
    speed: 'classical',
    perf: 'custom',
    createdAt: Date.now(),
    status: 'started',
    resultString: '*',
    timeControlLabel: 'Custom FEN',
    pgn,
    openingName: label || 'Custom Position',
    openingEco: '',
    white: { name: 'White' },
    black: { name: 'Black' },
    userColor: chess.turn(),
  };
}
