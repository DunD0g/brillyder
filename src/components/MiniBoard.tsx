import React from 'react';
import type { BoardThemeId, MoveClassification, PlayerColor } from '../types/chess';
import { ChessgroundBoard } from './ChessgroundBoard';

interface Props {
  fen: string;
  orientation: PlayerColor;
  theme: BoardThemeId;
  lastMove?: [string, string];
  badgeSquare?: string;
  badgeClassification?: MoveClassification;
  className?: string;
}

/** Tiny, non-interactive chessground used on Vault cards and drill lists. */
export const MiniBoard: React.FC<Props> = ({ fen, orientation, theme, lastMove, badgeSquare, badgeClassification, className = '' }) => (
  <div className={`w-full ${className}`}>
    <ChessgroundBoard
      fen={fen}
      orientation={orientation}
      lastMove={lastMove}
      interactive={false}
      theme={theme}
      coordinates={false}
      mini
      badgeSquare={badgeSquare}
      badgeClassification={badgeClassification}
      showBestArrow={false}
      showPlayedArrow={false}
    />
  </div>
);
