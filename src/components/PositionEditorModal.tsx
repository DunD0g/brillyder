import React, { useEffect, useMemo, useState } from 'react';
import { Chess, type Square } from 'chess.js';
import { CheckCircle2, Eraser, FlipVertical2, RotateCcw, Sparkles, Trash2, X } from 'lucide-react';
import { BOARD_THEME_LIST, BOARD_THEMES } from '../chess/boardThemes';
import type { BoardThemeId, LichessGameRecord, PlayerColor } from '../types/chess';
import { parseFenToBoardMatrix } from '../utils/shareCard';
import { createCustomFenGame } from '../utils/customFen';

interface Props {
  open: boolean;
  boardTheme: BoardThemeId;
  onClose: () => void;
  onAnalyzeFen: (game: LichessGameRecord) => void;
}

const START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const KINGS_ONLY_FEN = '4k3/8/8/8/8/8/8/4K3 w - - 0 1';
const FILES = 'abcdefgh';

const WHITE_PIECES = ['K', 'Q', 'R', 'B', 'N', 'P'] as const;
const BLACK_PIECES = ['k', 'q', 'r', 'b', 'n', 'p'] as const;
const PIECE_GLYPH: Record<string, string> = {
  K: '♔',
  Q: '♕',
  R: '♖',
  B: '♗',
  N: '♘',
  P: '♙',
  k: '♚',
  q: '♛',
  r: '♜',
  b: '♝',
  n: '♞',
  p: '♟\uFE0E',
};
const PIECE_NAMES: Record<string, string> = {
  K: 'White King',
  Q: 'White Queen',
  R: 'White Rook',
  B: 'White Bishop',
  N: 'White Knight',
  P: 'White Pawn',
  k: 'Black King',
  q: 'Black Queen',
  r: 'Black Rook',
  b: 'Black Bishop',
  n: 'Black Knight',
  p: 'Black Pawn',
};

function matrixToPlacement(matrix: Array<Array<string | null>>): string {
  return matrix
    .map((row) => {
      let out = '';
      let empty = 0;
      for (const cell of row) {
        if (!cell) {
          empty++;
        } else {
          if (empty > 0) {
            out += String(empty);
            empty = 0;
          }
          out += cell;
        }
      }
      if (empty > 0) out += String(empty);
      return out || '8';
    })
    .join('/');
}

function pruneCastlingForMatrix(
  matrix: Array<Array<string | null>>,
  castling: { K: boolean; Q: boolean; k: boolean; q: boolean }
): { K: boolean; Q: boolean; k: boolean; q: boolean } {
  const wkHome = matrix[7]?.[4] === 'K';
  const bkHome = matrix[0]?.[4] === 'k';
  return {
    K: castling.K && wkHome && matrix[7]?.[7] === 'R',
    Q: castling.Q && wkHome && matrix[7]?.[0] === 'R',
    k: castling.k && bkHome && matrix[0]?.[7] === 'r',
    q: castling.q && bkHome && matrix[0]?.[0] === 'r',
  };
}

function buildFen(
  matrix: Array<Array<string | null>>,
  turn: PlayerColor,
  castling: { K: boolean; Q: boolean; k: boolean; q: boolean },
  tail: { ep: string; halfmove: string; fullmove: string }
): string {
  const placement = matrixToPlacement(matrix);
  const pruned = pruneCastlingForMatrix(matrix, castling);
  const castleStr =
    `${pruned.K ? 'K' : ''}${pruned.Q ? 'Q' : ''}${pruned.k ? 'k' : ''}${pruned.q ? 'q' : ''}` || '-';
  return `${placement} ${turn} ${castleStr} ${tail.ep || '-'} ${tail.halfmove || '0'} ${tail.fullmove || '1'}`;
}

export const PositionEditorModal: React.FC<Props> = ({
  open,
  boardTheme,
  onClose,
  onAnalyzeFen,
}) => {
  const palette = BOARD_THEMES[boardTheme] ?? BOARD_THEME_LIST[0];
  const [matrix, setMatrix] = useState<Array<Array<string | null>>>(() =>
    parseFenToBoardMatrix(START_FEN)
  );
  const [turn, setTurn] = useState<PlayerColor>('w');
  const [castling, setCastling] = useState({ K: true, Q: true, k: true, q: true });
  const [fenTail, setFenTail] = useState({ ep: '-', halfmove: '0', fullmove: '1' });
  const [selectedBrush, setSelectedBrush] = useState<string | 'erase'>('Q');
  const [orientation, setOrientation] = useState<PlayerColor>('w');
  const [fenInput, setFenInput] = useState(START_FEN);
  const [label, setLabel] = useState('');

  useEffect(() => {
    if (!open) return;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onClose();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => {
      document.body.style.overflow = prevOverflow;
      window.removeEventListener('keydown', onKey);
    };
  }, [open, onClose]);

  const applyFenToBoard = (raw: string) => {
    setFenInput(raw);
    const trimmed = raw.trim();
    const parts = trimmed.split(/\s+/);
    if (parts.length >= 1 && parts[0].split('/').length === 8) {
      const nextMatrix = parseFenToBoardMatrix(trimmed);
      setMatrix(nextMatrix);
      if (parts[1] === 'w' || parts[1] === 'b') setTurn(parts[1]);
      const cStr = parts[2] ?? '-';
      setCastling(
        pruneCastlingForMatrix(nextMatrix, {
          K: cStr.includes('K'),
          Q: cStr.includes('Q'),
          k: cStr.includes('k'),
          q: cStr.includes('q'),
        })
      );
      setFenTail({
        ep: parts[3] && /^([a-h][36]|-)$/.test(parts[3]) ? parts[3] : '-',
        halfmove: parts[4] && /^\d+$/.test(parts[4]) ? parts[4] : '0',
        fullmove: parts[5] && /^[1-9]\d*$/.test(parts[5]) ? parts[5] : '1',
      });
    }
  };

  const syncFromParts = (
    nextMatrix: Array<Array<string | null>>,
    nextTurn: PlayerColor,
    nextCastling: { K: boolean; Q: boolean; k: boolean; q: boolean },
    nextTail = fenTail
  ) => {
    const pruned = pruneCastlingForMatrix(nextMatrix, nextCastling);
    setMatrix(nextMatrix);
    setTurn(nextTurn);
    setCastling(pruned);
    setFenTail(nextTail);
    setFenInput(buildFen(nextMatrix, nextTurn, pruned, nextTail));
  };

  const validation = useMemo(() => {
    const trimmed = fenInput.trim();
    const parts = trimmed.split(/\s+/);
    const boardStr = parts[0] ?? '';
    const rows = boardStr.split('/');
    if (rows.length !== 8) {
      return { ok: false, error: 'FEN must describe all 8 ranks.' };
    }
    if (/[Pp]/.test(rows[0]) || /[Pp]/.test(rows[7])) {
      return { ok: false, error: 'Pawns cannot sit on the 1st or 8th rank.' };
    }
    const wkCount = (boardStr.match(/K/g) ?? []).length;
    const bkCount = (boardStr.match(/k/g) ?? []).length;
    if (wkCount !== 1 || bkCount !== 1) {
      return { ok: false, error: 'Position needs exactly one White king and one Black king.' };
    }
    try {
      const mat = parseFenToBoardMatrix(trimmed);
      const rawCastling = parts[2] ?? '-';
      const pruned = pruneCastlingForMatrix(mat, {
        K: rawCastling.includes('K'),
        Q: rawCastling.includes('Q'),
        k: rawCastling.includes('k'),
        q: rawCastling.includes('q'),
      });
      const safeCastle =
        `${pruned.K ? 'K' : ''}${pruned.Q ? 'Q' : ''}${pruned.k ? 'k' : ''}${pruned.q ? 'q' : ''}` || '-';
      const sanitizedFen = [
        parts[0],
        parts[1] === 'b' ? 'b' : 'w',
        safeCastle,
        parts[3] ?? '-',
        parts[4] ?? '0',
        parts[5] ?? '1',
      ].join(' ');

      const c = new Chess(sanitizedFen);
      const board = c.board();
      let wkSq: Square | null = null;
      let bkSq: Square | null = null;
      let wkPos: [number, number] | null = null;
      let bkPos: [number, number] | null = null;
      for (let r = 0; r < 8; r++) {
        for (let col = 0; col < 8; col++) {
          const cell = board[r][col];
          if (cell?.type === 'k') {
            if (cell.color === 'w') {
              wkSq = cell.square;
              wkPos = [r, col];
            } else {
              bkSq = cell.square;
              bkPos = [r, col];
            }
          }
        }
      }
      if (!wkSq || !bkSq || !wkPos || !bkPos) {
        return { ok: false, error: 'Both kings must be on the board.' };
      }
      if (Math.max(Math.abs(wkPos[0] - bkPos[0]), Math.abs(wkPos[1] - bkPos[1])) <= 1) {
        return { ok: false, error: 'Kings cannot stand on adjacent squares.' };
      }
      const sideToMove = c.turn();
      const oppKingSq = sideToMove === 'w' ? bkSq : wkSq;
      if (c.isAttacked(oppKingSq, sideToMove)) {
        return {
          ok: false,
          error: `${sideToMove === 'w' ? 'Black' : 'White'}'s king is already in check on ${sideToMove === 'w' ? 'White' : 'Black'}'s turn.`,
        };
      }
      return { ok: true, normalizedFen: c.fen(), error: null };
    } catch (err) {
      return {
        ok: false,
        error: err instanceof Error ? err.message : 'Invalid FEN position.',
      };
    }
  }, [fenInput]);

  if (!open) return null;

  const handleCellClick = (displayRow: number, displayCol: number) => {
    const srcRow = orientation === 'w' ? displayRow : 7 - displayRow;
    const srcCol = orientation === 'w' ? displayCol : 7 - displayCol;
    // Prevent placing pawns on rank 8 (srcRow 0) or rank 1 (srcRow 7)
    if ((selectedBrush === 'P' || selectedBrush === 'p') && (srcRow === 0 || srcRow === 7)) {
      return;
    }
    const next = matrix.map((r) => [...r]);
    if (selectedBrush === 'erase') {
      next[srcRow][srcCol] = null;
    } else if (next[srcRow][srcCol] === selectedBrush) {
      next[srcRow][srcCol] = null;
    } else {
      if (selectedBrush === 'K' || selectedBrush === 'k') {
        for (let r = 0; r < 8; r++) {
          for (let c = 0; c < 8; c++) {
            if (next[r][c] === selectedBrush) next[r][c] = null;
          }
        }
      }
      next[srcRow][srcCol] = selectedBrush;
    }
    syncFromParts(next, turn, castling, { ...fenTail, ep: '-' });
  };

  const handleLaunch = () => {
    if (!validation.ok || !validation.normalizedFen) return;
    const record = createCustomFenGame(validation.normalizedFen, label.trim() || undefined);
    onAnalyzeFen(record);
    onClose();
  };

  return (
    <div
      className="fixed inset-0 z-[85] flex items-end justify-center bg-[#04070e]/85 pt-[env(safe-area-inset-top)] backdrop-blur-md sm:items-center sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-label="Position & FEN Editor"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="glass-card glass-card-strong anim-pop flex max-h-[92dvh] w-full max-w-2xl flex-col overflow-hidden rounded-b-none rounded-t-3xl border-b-0 bg-[#0B1220] sm:max-h-[90dvh] sm:rounded-2xl sm:border-b">
        <div className="flex items-center justify-between gap-2 border-b border-slate-800/80 bg-[#070B14]/85 px-4 py-3">
          <div>
            <div className="text-xs font-black uppercase tracking-[0.16em] text-brilly">
              Board Editor &amp; FEN Analyzer
            </div>
            <div className="text-[10px] text-slate-400">
              Set up any OTB, book, or puzzle position to inspect with Stockfish &amp; Syzygy.
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close board editor"
            className="inline-flex h-9 w-9 items-center justify-center rounded-xl border border-slate-700/80 bg-slate-900/80 text-slate-300 hover:border-teal-400/50 hover:text-white"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto overscroll-contain p-3.5 nice-scroll pb-[max(1.5rem,env(safe-area-inset-bottom))]">
          <div className="grid grid-cols-1 gap-3 md:grid-cols-[minmax(0,300px)_minmax(0,1fr)]">
            {/* Interactive 8x8 setup board */}
            <div className="min-w-0 space-y-2">
              <div className="mx-auto grid aspect-square w-full max-w-[300px] grid-cols-8 grid-rows-8 overflow-hidden rounded-xl border border-slate-700 shadow-lg">
                {Array.from({ length: 64 }).map((_, idx) => {
                  const row = Math.floor(idx / 8);
                  const col = idx % 8;
                  const srcRow = orientation === 'w' ? row : 7 - row;
                  const srcCol = orientation === 'w' ? col : 7 - col;
                  const sqName = `${FILES[srcCol]}${8 - srcRow}`;
                  const piece = matrix[srcRow]?.[srcCol];
                  const isLight = (row + col) % 2 === 0;
                  const isWhitePiece = piece ? piece === piece.toUpperCase() : false;
                  return (
                    <button
                      key={idx}
                      type="button"
                      aria-label={`${sqName}${piece ? ` (${PIECE_NAMES[piece]})` : ' (empty)'}`}
                      onClick={() => handleCellClick(row, col)}
                      style={{ backgroundColor: isLight ? palette.lightSquare : palette.darkSquare }}
                      className="flex min-h-0 min-w-0 aspect-square items-center justify-center text-xl leading-none select-none transition hover:brightness-110 sm:text-2xl"
                    >
                      {piece && (
                        <span
                          style={{
                            color: isWhitePiece ? '#FFFFFF' : '#0B1120',
                            textShadow: isWhitePiece
                              ? '0 1px 2px rgba(0,0,0,0.9)'
                              : '0 0 2px rgba(255,255,255,0.65)',
                          }}
                        >
                          {PIECE_GLYPH[piece]}
                        </span>
                      )}
                    </button>
                  );
                })}
              </div>

              <div className="flex flex-wrap justify-center gap-1.5">
                <button
                  type="button"
                  onClick={() => applyFenToBoard(START_FEN)}
                  className="inline-flex min-h-[36px] items-center gap-1 rounded-lg border border-slate-700 bg-void/70 px-2.5 py-1.5 text-[11px] font-bold text-slate-300 hover:border-slate-500"
                >
                  <RotateCcw className="h-3.5 w-3.5" /> Start
                </button>
                <button
                  type="button"
                  onClick={() => applyFenToBoard(KINGS_ONLY_FEN)}
                  className="inline-flex min-h-[36px] items-center gap-1 rounded-lg border border-slate-700 bg-void/70 px-2.5 py-1.5 text-[11px] font-bold text-slate-300 hover:border-slate-500"
                >
                  <Trash2 className="h-3.5 w-3.5" /> Kings Only
                </button>
                <button
                  type="button"
                  onClick={() => setOrientation((o) => (o === 'w' ? 'b' : 'w'))}
                  className="inline-flex min-h-[36px] items-center gap-1 rounded-lg border border-slate-700 bg-void/70 px-2.5 py-1.5 text-[11px] font-bold text-slate-300 hover:border-slate-500"
                >
                  <FlipVertical2 className="h-3.5 w-3.5" /> Flip
                </button>
              </div>
            </div>

            {/* Piece Palette + FEN Controls */}
            <div className="min-w-0 space-y-3">
              <div>
                <div className="text-[10px] font-black uppercase tracking-[0.14em] text-slate-400">
                  Tap piece, then tap board squares
                </div>
                <div className="mt-1.5 space-y-1.5">
                  <div className="grid grid-cols-6 gap-1">
                    {WHITE_PIECES.map((p) => (
                      <button
                        key={p}
                        type="button"
                        aria-label={`Place ${PIECE_NAMES[p]}`}
                        aria-pressed={selectedBrush === p}
                        onClick={() => setSelectedBrush(p)}
                        className={`min-h-[38px] rounded-lg border py-1.5 text-lg leading-none transition ${
                          selectedBrush === p
                            ? 'border-teal-400 bg-teal-400/20 text-white'
                            : 'border-slate-800 bg-void/70 text-white hover:border-slate-600'
                        }`}
                      >
                        {PIECE_GLYPH[p]}
                      </button>
                    ))}
                  </div>
                  <div className="grid grid-cols-7 gap-1">
                    {BLACK_PIECES.map((p) => (
                      <button
                        key={p}
                        type="button"
                        aria-label={`Place ${PIECE_NAMES[p]}`}
                        aria-pressed={selectedBrush === p}
                        onClick={() => setSelectedBrush(p)}
                        className={`min-h-[38px] rounded-lg border py-1.5 text-lg leading-none transition ${
                          selectedBrush === p
                            ? 'border-purple-400 bg-purple-500/20 text-slate-100'
                            : 'border-slate-800 bg-void/70 text-slate-300 hover:border-slate-600'
                        }`}
                      >
                        {PIECE_GLYPH[p]}
                      </button>
                    ))}
                    <button
                      type="button"
                      aria-label="Erase piece"
                      aria-pressed={selectedBrush === 'erase'}
                      onClick={() => setSelectedBrush('erase')}
                      title="Erase piece"
                      className={`inline-flex min-h-[38px] items-center justify-center rounded-lg border py-1.5 transition ${
                        selectedBrush === 'erase'
                          ? 'border-rose-400 bg-rose-500/20 text-rose-200'
                          : 'border-slate-800 bg-void/70 text-slate-400 hover:border-slate-600'
                      }`}
                    >
                      <Eraser className="h-4 w-4" />
                    </button>
                  </div>
                </div>
              </div>

              {/* Turn & Castling */}
              <div className="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-slate-800 bg-void/60 p-2">
                <div className="inline-flex rounded-lg border border-slate-800 bg-hull p-0.5 text-[10px] font-bold">
                  {(['w', 'b'] as PlayerColor[]).map((side) => (
                    <button
                      key={side}
                      type="button"
                      onClick={() => syncFromParts(matrix, side, castling)}
                      className={`rounded px-2.5 py-1.5 ${
                        turn === side ? 'bg-teal-400/20 text-teal-200' : 'text-slate-400'
                      }`}
                    >
                      {side === 'w' ? 'White to move' : 'Black to move'}
                    </button>
                  ))}
                </div>
                <div className="flex items-center gap-1 font-mono text-[11px]">
                  {(['K', 'Q', 'k', 'q'] as const).map((flag) => (
                    <button
                      key={flag}
                      type="button"
                      aria-label={`Castling right ${flag}`}
                      aria-pressed={castling[flag]}
                      onClick={() => {
                        const nextC = { ...castling, [flag]: !castling[flag] };
                        syncFromParts(matrix, turn, nextC);
                      }}
                      className={`min-h-[32px] min-w-[30px] rounded border px-1.5 py-1 font-bold ${
                        castling[flag]
                          ? 'border-teal-400/50 bg-teal-400/15 text-teal-200'
                          : 'border-slate-800 text-slate-500'
                      }`}
                    >
                      {flag}
                    </button>
                  ))}
                </div>
              </div>

              {/* FEN Paste & Label */}
              <div className="space-y-1.5">
                <label
                  htmlFor="position-editor-fen"
                  className="block text-[10px] font-bold uppercase tracking-wider text-slate-400"
                >
                  FEN String (editable)
                </label>
                <input
                  id="position-editor-fen"
                  type="text"
                  value={fenInput}
                  onChange={(e) => applyFenToBoard(e.target.value)}
                  autoCapitalize="none"
                  autoCorrect="off"
                  spellCheck={false}
                  className="w-full rounded-xl border border-slate-700 bg-void px-2.5 py-2 font-mono text-xs text-slate-100 focus:border-teal-400 focus:outline-none"
                />
                <input
                  type="text"
                  value={label}
                  onChange={(e) => setLabel(e.target.value)}
                  aria-label="Custom position title"
                  placeholder="Optional title (e.g. OTB Club Endgame)"
                  className="w-full rounded-xl border border-slate-800 bg-void px-2.5 py-1.5 text-xs text-slate-200 placeholder:text-slate-500 focus:border-teal-400 focus:outline-none"
                />
                {validation.ok ? (
                  <div className="flex items-center gap-1 text-[10px] text-emerald-300">
                    <CheckCircle2 className="h-3 w-3" /> Valid chess position ready to analyze.
                  </div>
                ) : (
                  <div className="text-[10px] text-rose-300">{validation.error}</div>
                )}
              </div>

              <button
                type="button"
                disabled={!validation.ok}
                onClick={handleLaunch}
                className="inline-flex w-full items-center justify-center gap-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-cyan-300 px-4 py-2.5 text-xs font-black text-slate-950 transition hover:brightness-110 disabled:opacity-40"
              >
                <Sparkles className="h-4 w-4" /> Open in Analyze Board
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
