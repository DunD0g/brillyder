import React, { useEffect, useMemo, useRef } from 'react';
import { Chessground } from '@lichess-org/chessground';
import type { Api } from '@lichess-org/chessground/api';
import type { DrawShape } from '@lichess-org/chessground/draw';
import type { Key } from '@lichess-org/chessground/types';
import { Chess, type Square } from 'chess.js';
import { CLASSIFICATION_META, type MoveClassification, type PlayerColor } from '../types/chess';
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
  return { left: `${(col + 1) * 12.5}%`, top: `${row * 12.5}%` };
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
  onUserMove,
  onSwipePrev,
  onSwipeNext,
}) => {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const cgRef = useRef<Api | null>(null);
  const onUserMoveRef = useRef(onUserMove);
  const touchStartRef = useRef<{ x: number; y: number } | null>(null);
  onUserMoveRef.current = onUserMove;

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
      coordinates: true,
      animation: { enabled: true, duration: 165 },
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
  }, []);

  useEffect(() => {
    if (!cgRef.current) return;
    cgRef.current.set({
      fen,
      orientation: orientation === 'w' ? 'white' : 'black',
      viewOnly: !interactive,
      turnColor: turnColor ? (turnColor === 'w' ? 'white' : 'black') : undefined,
      check: checkColor,
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
  }, [fen, orientation, interactive, turnColor, checkColor, lastMove, shapes, legalDests]);

  const badgeCoords = badgeSquare && badgeClassification ? squareToPct(badgeSquare, orientation) : null;
  const badgeMeta = badgeClassification ? CLASSIFICATION_META[badgeClassification] : null;

  return (
    <div
      className={`relative w-full aspect-square rounded-xl overflow-hidden shadow-2xl border border-slate-700/80 ${interactive ? 'touch-none' : 'touch-pan-y'}`}
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
      {badgeCoords && badgeMeta && (
        <div
          className="pointer-events-none absolute z-30 -translate-x-[82%] translate-y-[6%] flex items-center justify-center rounded-full shadow-lg border border-slate-950 font-extrabold text-[10px] sm:text-[11px] text-white w-5 h-5 sm:w-6 sm:h-6"
          style={{ left: badgeCoords.left, top: badgeCoords.top, backgroundColor: badgeMeta.badgeBg }}
        >
          {badgeMeta.symbol}
        </div>
      )}
    </div>
  );
};
