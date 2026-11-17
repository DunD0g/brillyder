import React, { useEffect, useMemo, useRef } from 'react';
import { Chessground } from '@lichess-org/chessground';
import type { Api } from '@lichess-org/chessground/api';
import type { DrawShape } from '@lichess-org/chessground/draw';
import type { Key } from '@lichess-org/chessground/types';
import { Chess, type Square } from 'chess.js';
import { BOARD_THEMES } from '../chess/boardThemes';
import { CLASSIFICATION_META, type BoardThemeId, type MoveClassification, type PlayerColor } from '../types/chess';
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
  badgeSquare?: string;
  badgeClassification?: MoveClassification;
  theme?: BoardThemeId;
  coordinates?: boolean;
  mini?: boolean;
  onUserMove?: (orig: Square, dest: Square) => void;
  onSwipePrev?: () => void;
  onSwipeNext?: () => void;
}

function squareToPct(sq: string, orientation: PlayerColor): { left: string; top: string } | null {
  if (!sq || sq.length < 2) return null;
  const file = sq.charCodeAt(0) - 97;
  const rank = parseInt(sq[1], 10) - 1;
  if (file < 0 || file > 7 || rank < 0 || rank > 7) return null;
  const col = orientation === 'w' ? file : 7 - file;
  const row = orientation === 'w' ? 7 - rank : rank;
  return { left: `${(col + 0.5) * 12.5}%`, top: `${row * 12.5}%` };
}

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
  badgeSquare,
  badgeClassification,
  theme = 'slate',
  coordinates = true,
  mini = false,
  onUserMove,
  onSwipePrev,
  onSwipeNext,
}) => {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const cgRef = useRef<Api | null>(null);
  const onUserMoveRef = useRef(onUserMove);
  const touchStartRef = useRef<{ x: number; y: number } | null>(null);
  onUserMoveRef.current = onUserMove;

  const boardTheme = BOARD_THEMES[theme];

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
      coordinates: false,
      animation: { enabled: !mini, duration: 165 },
      highlight: { lastMove: true, check: true },
      drawable: { enabled: true, visible: true, autoShapes: shapes },
      movable: {
        free: false,
        color: interactive && turnColor ? (turnColor === 'w' ? 'white' : 'black') : undefined,
        dests: legalDests,
        showDests: true,
        events: { after: (orig, dest) => onUserMoveRef.current?.(orig as Square, dest as Square) },
      },
      draggable: { enabled: interactive, showGhost: true },
    });
    cgRef.current = api;
    const ro = new ResizeObserver(() => api.redrawAll());
    ro.observe(containerRef.current);
    return () => { ro.disconnect(); api.destroy(); cgRef.current = null; };
    // Intentionally init once: live prop updates are handled by the effect below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!cgRef.current) return;
    cgRef.current.set({
      fen,
      orientation: orientation === 'w' ? 'white' : 'black',
      viewOnly: !interactive,
      turnColor: turnColor ? (turnColor === 'w' ? 'white' : 'black') : undefined,
      check: checkColor,
      coordinates: false,
      lastMove: lastMove ? ([lastMove[0] as Key, lastMove[1] as Key] as [Key, Key]) : undefined,
      drawable: { enabled: true, visible: true, autoShapes: shapes },
      movable: {
        free: false,
        color: interactive && turnColor ? (turnColor === 'w' ? 'white' : 'black') : undefined,
        dests: legalDests,
        showDests: true,
      },
      draggable: { enabled: interactive, showGhost: true },
    });
  }, [fen, orientation, interactive, turnColor, checkColor, lastMove, shapes, legalDests, coordinates]);

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

  return (
    <div
      className={`relative w-full aspect-square overflow-hidden border border-white/10 brillyder-board theme-${theme} ${interactive ? 'touch-none' : 'touch-pan-y'} ${mini ? 'rounded-lg is-mini' : 'rounded-xl sm:rounded-2xl'}`}
      style={{ ...cssVars, boxShadow: boardTheme.shadow }}
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
