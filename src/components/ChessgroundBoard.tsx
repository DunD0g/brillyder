import React, { useEffect, useMemo, useRef } from 'react';
import { Chessground } from '@lichess-org/chessground';
import type { Api } from '@lichess-org/chessground/api';
import type { DrawShape } from '@lichess-org/chessground/draw';
import type { Key } from '@lichess-org/chessground/types';
import { Chess, type Square } from 'chess.js';
import { BOARD_THEMES } from '../chess/boardThemes';
import { CLASSIFICATION_META, type BoardThemeId, type MoveClassification, type PlayerColor } from '../types/chess';
import type { BoardArrow, SquareHighlight } from '../types/openings';
import { uciToSquares } from '../utils/chessMath';

interface Props {
  fen: string;
  orientation: PlayerColor;
  lastMove?: [string, string];
  interactive: boolean;
  turnColor?: PlayerColor;
  bestMoveUci?: string;
  playedMoveUci?: string;
  threatMoveUci?: string;
  showBestArrow?: boolean;
  showPlayedArrow?: boolean;
  showThreatArrow?: boolean;
  customArrows?: BoardArrow[];
  squareHighlights?: SquareHighlight[];
  badgeSquare?: string;
  badgeClassification?: MoveClassification;
  theme?: BoardThemeId;
  coordinates?: boolean;
  mini?: boolean;
  onUserMove?: (orig: Square, dest: Square) => void;
  onSquareClick?: (square: Square) => void;
  onSwipePrev?: () => void;
  onSwipeNext?: () => void;
}

function squareToGrid(sq: string, orientation: PlayerColor): { col: number; row: number } | null {
  if (!sq || sq.length < 2) return null;
  const file = sq.charCodeAt(0) - 97;
  const rank = parseInt(sq[1], 10) - 1;
  if (file < 0 || file > 7 || rank < 0 || rank > 7) return null;
  const col = orientation === 'w' ? file : 7 - file;
  const row = orientation === 'w' ? 7 - rank : rank;
  return { col, row };
}

function squareToPct(sq: string, orientation: PlayerColor): { left: string; top: string } | null {
  const g = squareToGrid(sq, orientation);
  if (!g) return null;
  return { left: `${(g.col + 0.5) * 12.5}%`, top: `${g.row * 12.5}%` };
}

const ARROW_COLOR_VAR: Record<BoardArrow['color'], string> = {
  plan: 'var(--arrow-plan, rgba(45, 212, 191, 0.80))',
  best: 'var(--arrow-best, rgba(52, 211, 153, 0.85))',
  threat: 'var(--arrow-threat, rgba(251, 113, 133, 0.85))',
  outpost: 'var(--arrow-outpost, rgba(168, 85, 247, 0.78))',
};

const HIGHLIGHT_STYLES: Record<SquareHighlight['color'], { bg: string; ring: string }> = {
  plan: { bg: 'rgba(45, 212, 191, 0.24)', ring: 'rgba(45, 212, 191, 0.78)' },
  threat: { bg: 'rgba(251, 113, 133, 0.26)', ring: 'rgba(251, 113, 133, 0.85)' },
  outpost: { bg: 'rgba(168, 85, 247, 0.26)', ring: 'rgba(168, 85, 247, 0.82)' },
};

export const ChessgroundBoard: React.FC<Props> = ({
  fen,
  orientation,
  lastMove,
  interactive,
  turnColor,
  bestMoveUci,
  playedMoveUci,
  threatMoveUci,
  showBestArrow = true,
  showPlayedArrow = true,
  showThreatArrow = false,
  customArrows,
  squareHighlights,
  badgeSquare,
  badgeClassification,
  theme = 'slate',
  coordinates = true,
  mini = false,
  onUserMove,
  onSquareClick,
  onSwipePrev,
  onSwipeNext,
}) => {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const cgRef = useRef<Api | null>(null);
  const onUserMoveRef = useRef(onUserMove);
  const onSquareClickRef = useRef(onSquareClick);
  const touchStartRef = useRef<{ x: number; y: number } | null>(null);
  onUserMoveRef.current = onUserMove;
  onSquareClickRef.current = onSquareClick;

  const boardTheme = BOARD_THEMES[theme];

  const fenTurn = useMemo<PlayerColor>(() => (fen.split(' ')[1] === 'b' ? 'b' : 'w'), [fen]);
  const effectiveTurn = turnColor ?? fenTurn;
  const movableColor = interactive ? (effectiveTurn === 'w' ? ('white' as const) : ('black' as const)) : undefined;

  const legalDests = useMemo(() => {
    const map = new Map<Key, Key[]>();
    if (!interactive) return map;
    try {
      const c = new Chess(fen);
      for (const mv of c.moves({ verbose: true })) {
        const from = mv.from as Key;
        const list = map.get(from) ?? [];
        list.push(mv.to as Key);
        map.set(from, list);
      }
    } catch { /* ignore */ }
    return map;
  }, [fen, interactive]);

  const checkColor = useMemo(() => {
    try {
      const c = new Chess(fen);
      if (c.inCheck()) return c.turn() === 'w' ? ('white' as const) : ('black' as const);
    } catch { /* ignore */ }
    return false as const;
  }, [fen]);

  const shapes = useMemo<DrawShape[]>(() => {
    const out: DrawShape[] = [];
    if (showPlayedArrow && playedMoveUci) {
      const p = uciToSquares(playedMoveUci);
      if (p && (!showBestArrow || playedMoveUci !== bestMoveUci)) {
        out.push({ orig: p.from as Key, dest: p.to as Key, brush: 'blue' });
      }
    }
    if (showBestArrow && bestMoveUci) {
      const b = uciToSquares(bestMoveUci);
      if (b) out.push({ orig: b.from as Key, dest: b.to as Key, brush: 'green' });
    }
    if (showThreatArrow && threatMoveUci) {
      const t = uciToSquares(threatMoveUci);
      if (t) out.push({ orig: t.from as Key, dest: t.to as Key, brush: 'red' });
    }
    return out;
  }, [showPlayedArrow, playedMoveUci, showBestArrow, bestMoveUci, showThreatArrow, threatMoveUci]);

  useEffect(() => {
    if (!containerRef.current) return;
    const api = Chessground(containerRef.current, {
      fen,
      orientation: orientation === 'w' ? 'white' : 'black',
      viewOnly: !interactive,
      disableContextMenu: true,
      coordinates: false,
      animation: { enabled: !mini, duration: 165 },
      highlight: { lastMove: true, check: true },
      drawable: { enabled: true, visible: true, autoShapes: shapes },
      movable: {
        free: false,
        color: movableColor,
        dests: legalDests,
        showDests: true,
        events: { after: (orig, dest) => onUserMoveRef.current?.(orig as Square, dest as Square) },
      },
      draggable: { enabled: interactive, showGhost: true },
      selectable: { enabled: interactive },
      premovable: { enabled: false },
      predroppable: { enabled: false },
    });
    cgRef.current = api;
    const ro = new ResizeObserver(() => api.redrawAll());
    ro.observe(containerRef.current);
    return () => { ro.disconnect(); api.destroy(); cgRef.current = null; };
    // Chessground binds input listeners once at construction, so the board must
    // be rebuilt whenever interactivity turns on (e.g. entering a sandbox).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [interactive]);

  useEffect(() => {
    if (!cgRef.current) return;
    cgRef.current.set({
      fen,
      orientation: orientation === 'w' ? 'white' : 'black',
      viewOnly: !interactive,
      turnColor: effectiveTurn === 'w' ? 'white' : 'black',
      check: checkColor,
      coordinates: false,
      lastMove: lastMove ? ([lastMove[0] as Key, lastMove[1] as Key] as [Key, Key]) : undefined,
      drawable: { enabled: true, visible: true, autoShapes: shapes },
      movable: {
        free: false,
        color: movableColor,
        dests: legalDests,
        showDests: true,
      },
      draggable: { enabled: interactive, showGhost: true },
      selectable: { enabled: interactive },
      premovable: { enabled: false },
      predroppable: { enabled: false },
    });
  }, [fen, orientation, interactive, effectiveTurn, checkColor, lastMove, shapes, legalDests, coordinates, movableColor]);

  const badgeCoords = badgeSquare && badgeClassification ? squareToPct(badgeSquare, orientation) : null;
  const badgeMeta = badgeClassification ? CLASSIFICATION_META[badgeClassification] : null;
  const rankLabels = Array.from({ length: 8 }, (_, row) => ({
    label: String(orientation === 'w' ? 8 - row : row + 1),
    top: `${(row + 0.5) * 12.5}%`,
  }));
  const fileLabels = Array.from({ length: 8 }, (_, col) => ({
    label: String.fromCharCode(97 + (orientation === 'w' ? col : 7 - col)),
    left: `${(col + 0.5) * 12.5}%`,
  }));
  const cssVars = {
    '--bd-lastmove': boardTheme.lastMove,
    '--bd-selected': boardTheme.selected,
    '--bd-dest': boardTheme.moveDest,
    '--bd-check': boardTheme.check,
    '--bd-coord': boardTheme.coordColor,
    '--bd-light': boardTheme.lightSquare,
    '--bd-dark': boardTheme.darkSquare,
    '--bd-piece-filter': boardTheme.pieceFilter ?? 'none',
    '--bd-shadow': boardTheme.shadow,
  } as React.CSSProperties;

  const handleOverlayClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!onSquareClickRef.current || !containerRef.current) return;
    const rect = containerRef.current.getBoundingClientRect();
    const relX = (e.clientX - rect.left) / rect.width;
    const relY = (e.clientY - rect.top) / rect.height;
    const col = Math.floor(relX * 8);
    const row = Math.floor(relY * 8);
    if (col < 0 || col > 7 || row < 0 || row > 7) return;
    const file = orientation === 'w' ? col : 7 - col;
    const rank = orientation === 'w' ? 7 - row : row;
    const sq = `${String.fromCharCode(97 + file)}${rank + 1}` as Square;
    onSquareClickRef.current(sq);
  };

  return (
    <div
      className={`relative w-full aspect-square overflow-hidden border border-white/10 brillyder-board theme-${theme} ${interactive || onSquareClick ? 'touch-none' : 'touch-pan-y'} ${mini ? 'rounded-lg is-mini' : 'rounded-xl sm:rounded-2xl'} ${onSquareClick ? 'cursor-crosshair' : ''}`}
      style={{ ...cssVars, boxShadow: boardTheme.shadow }}
      onContextMenu={(e) => e.preventDefault()}
      onClick={onSquareClick ? handleOverlayClick : undefined}
      onTouchStart={(e) => { if (!interactive) touchStartRef.current = { x: e.touches[0].clientX, y: e.touches[0].clientY }; }}
      onTouchEnd={(e) => {
        if (interactive || !touchStartRef.current) return;
        const dx = e.changedTouches[0].clientX - touchStartRef.current.x;
        const dy = e.changedTouches[0].clientY - touchStartRef.current.y;
        touchStartRef.current = null;
        if (Math.abs(dx) > 42 && Math.abs(dx) > Math.abs(dy) * 1.35) {
          if (dx < 0) onSwipeNext?.(); else onSwipePrev?.();
        }
      }}
    >
      <div ref={containerRef} className="w-full h-full brillyder-board" />
      {squareHighlights && squareHighlights.length > 0 && (
        <div className="pointer-events-none absolute inset-0 z-[15]" aria-hidden="true">
          {squareHighlights.map((hl, idx) => {
            const g = squareToGrid(hl.square, orientation);
            if (!g) return null;
            const style = HIGHLIGHT_STYLES[hl.color];
            return (
              <div
                key={`${hl.square}-${hl.color}-${idx}`}
                className="absolute"
                style={{
                  left: `${g.col * 12.5}%`,
                  top: `${g.row * 12.5}%`,
                  width: '12.5%',
                  height: '12.5%',
                  backgroundColor: style.bg,
                  boxShadow: `inset 0 0 0 2px ${style.ring}`,
                }}
              />
            );
          })}
        </div>
      )}
      {customArrows && customArrows.length > 0 && (
        <svg
          viewBox="0 0 800 800"
          className="pointer-events-none absolute inset-0 z-[18] h-full w-full"
          aria-hidden="true"
        >
          {customArrows.map((arrow, idx) => {
            const fromG = squareToGrid(arrow.from, orientation);
            const toG = squareToGrid(arrow.to, orientation);
            if (!fromG || !toG) return null;
            const x1 = (fromG.col + 0.5) * 100;
            const y1 = (fromG.row + 0.5) * 100;
            const x2 = (toG.col + 0.5) * 100;
            const y2 = (toG.row + 0.5) * 100;
            const dx = x2 - x1;
            const dy = y2 - y1;
            const len = Math.hypot(dx, dy);
            if (len < 1) return null;
            const ux = dx / len;
            const uy = dy / len;
            const headLen = 30;
            const headHalf = 19;
            const startX = x1 + ux * 16;
            const startY = y1 + uy * 16;
            const tipX = x2 - ux * 10;
            const tipY = y2 - uy * 10;
            const baseX = tipX - ux * headLen;
            const baseY = tipY - uy * headLen;
            const perpX = -uy;
            const perpY = ux;
            const p1x = baseX + perpX * headHalf;
            const p1y = baseY + perpY * headHalf;
            const p2x = baseX - perpX * headHalf;
            const p2y = baseY - perpY * headHalf;
            const stroke = ARROW_COLOR_VAR[arrow.color];
            return (
              <g key={`${arrow.from}-${arrow.to}-${arrow.color}-${idx}`}>
                <line
                  x1={startX}
                  y1={startY}
                  x2={baseX}
                  y2={baseY}
                  stroke={stroke}
                  strokeWidth="15"
                  strokeLinecap="round"
                />
                <polygon
                  points={`${tipX},${tipY} ${p1x},${p1y} ${p2x},${p2y}`}
                  fill={stroke}
                />
              </g>
            );
          })}
        </svg>
      )}
      {coordinates && (
        <div className="pointer-events-none absolute inset-0 z-20" aria-hidden="true">
          {rankLabels.map(({ label, top }) => (
            <span key={`rank-${label}`} className="board-coord-chip" style={{ left: 2, top, transform: 'translateY(-50%)' }}>{label}</span>
          ))}
          {fileLabels.map(({ label, left }) => (
            <span key={`file-${label}`} className="board-coord-chip" style={{ left, bottom: 2, transform: 'translateX(-50%)' }}>{label}</span>
          ))}
        </div>
      )}
      {badgeCoords && badgeMeta && (
        <div
          className={`pointer-events-none absolute z-30 flex items-center justify-center rounded-full shadow-lg border border-slate-950 font-extrabold text-white ${mini ? 'text-[8px] w-4 h-4' : 'text-[10px] sm:text-[11px] w-5 h-5 sm:w-6 sm:h-6'}`}
          style={{ left: badgeCoords.left, top: badgeCoords.top, transform: 'translate(-50%, -50%)', backgroundColor: badgeMeta.badgeBg }}
        >
          {badgeMeta.symbol}
        </div>
      )}
    </div>
  );
};
