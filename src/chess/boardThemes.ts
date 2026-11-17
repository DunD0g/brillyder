import type { BoardThemeId } from '../types/chess';
import { getPref, setPref } from '../storage/gameDb';

export interface BoardTheme {
  id: BoardThemeId;
  name: string;
  shortName: string;
  lightSquare: string;
  darkSquare: string;
  lastMove: string;
  selected: string;
  moveDest: string;
  check: string;
  coordColor: string;
  accent: string;
  accentSoft: string;
  pieceFilter?: string;
  shadow: string;
}

export const BOARD_THEMES: Record<BoardThemeId, BoardTheme> = {
  slate: {
    id: 'slate',
    name: 'BrillyDer Slate',
    shortName: 'Slate',
    lightSquare: '#9cb0c7',
    darkSquare: '#4c647d',
    lastMove: 'rgba(34, 211, 238, 0.36)',
    selected: 'rgba(16, 185, 129, 0.48)',
    moveDest: 'rgba(34, 211, 238, 0.55)',
    check: 'rgba(244, 63, 94, 0.92)',
    coordColor: '#cbd5e1',
    accent: '#22d3ee',
    accentSoft: 'rgba(34, 211, 238, 0.16)',
    shadow: '0 20px 50px rgba(0, 0, 0, 0.45)',
  },
  emerald: {
    id: 'emerald',
    name: 'Emerald Tournament',
    shortName: 'Emerald',
    lightSquare: '#e7efdc',
    darkSquare: '#527d58',
    lastMove: 'rgba(250, 204, 21, 0.48)',
    selected: 'rgba(16, 185, 129, 0.5)',
    moveDest: 'rgba(250, 204, 21, 0.62)',
    check: 'rgba(239, 68, 68, 0.92)',
    coordColor: '#dbe7d2',
    accent: '#34d399',
    accentSoft: 'rgba(52, 211, 153, 0.16)',
    shadow: '0 20px 50px rgba(2, 44, 34, 0.45)',
    pieceFilter: 'drop-shadow(0 1px 1px rgba(0,0,0,0.35)) saturate(1.03)',
  },
  walnut: {
    id: 'walnut',
    name: 'Walnut Classic',
    shortName: 'Walnut',
    lightSquare: '#ecd7b6',
    darkSquare: '#8b5d3d',
    lastMove: 'rgba(251, 146, 60, 0.5)',
    selected: 'rgba(180, 83, 9, 0.55)',
    moveDest: 'rgba(245, 158, 11, 0.62)',
    check: 'rgba(220, 38, 38, 0.94)',
    coordColor: '#f5e7d2',
    accent: '#f59e0b',
    accentSoft: 'rgba(245, 158, 11, 0.16)',
    shadow: '0 20px 50px rgba(54, 28, 10, 0.5)',
    pieceFilter: 'sepia(0.12) saturate(1.05) drop-shadow(0 1px 1px rgba(0,0,0,0.4))',
  },
  neon: {
    id: 'neon',
    name: 'Midnight Neon',
    shortName: 'Neon',
    lightSquare: '#2b3550',
    darkSquare: '#111827',
    lastMove: 'rgba(168, 85, 247, 0.55)',
    selected: 'rgba(34, 211, 238, 0.45)',
    moveDest: 'rgba(232, 121, 249, 0.7)',
    check: 'rgba(244, 63, 94, 0.95)',
    coordColor: '#a5b4fc',
    accent: '#e879f9',
    accentSoft: 'rgba(232, 121, 249, 0.16)',
    shadow: '0 24px 60px rgba(76, 29, 149, 0.45)',
    pieceFilter: 'drop-shadow(0 0 3px rgba(34,211,238,0.55)) saturate(1.08)',
  },
};

export const BOARD_THEME_LIST: BoardTheme[] = [BOARD_THEMES.slate, BOARD_THEMES.emerald, BOARD_THEMES.walnut, BOARD_THEMES.neon];

const THEME_PREF_KEY = 'brillyder_board_theme';

export function getStoredBoardTheme(): BoardThemeId {
  const stored = getPref<string>(THEME_PREF_KEY, 'slate');
  return stored in BOARD_THEMES ? (stored as BoardThemeId) : 'slate';
}

export function storeBoardTheme(id: BoardThemeId): void {
  setPref(THEME_PREF_KEY, id);
}
