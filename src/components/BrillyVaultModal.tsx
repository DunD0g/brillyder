import React, { useEffect } from 'react';
import { Gem, X } from 'lucide-react';
import type {
  BoardThemeId,
  BrillyVaultEntry,
  BrillyVaultStats,
  SavedPositionBookmark,
} from '../types/chess';
import { BrillyVaultView } from './BrillyVaultView';

interface Props {
  open: boolean;
  onClose: () => void;
  entries: BrillyVaultEntry[];
  stats: BrillyVaultStats;
  username: string;
  boardTheme: BoardThemeId;
  savedPositions?: SavedPositionBookmark[];
  onOpenEntry: (entry: BrillyVaultEntry) => void;
  onOpenBookmark?: (bookmark: SavedPositionBookmark) => void;
  onRemoveBookmark?: (bookmarkId: string) => void;
  onOpenGames: () => void;
}

export const BrillyVaultModal: React.FC<Props> = ({
  open,
  onClose,
  entries,
  stats,
  username,
  boardTheme,
  savedPositions = [],
  onOpenEntry,
  onOpenBookmark,
  onRemoveBookmark,
  onOpenGames,
}) => {
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        onClose();
      }
    };
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    window.addEventListener('keydown', onKey);
    return () => {
      document.body.style.overflow = prevOverflow;
      window.removeEventListener('keydown', onKey);
    };
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-[85] flex items-end justify-center bg-[#04070e]/80 backdrop-blur-md sm:items-center sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-label="Brilly Vault"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="glass-card glass-card-strong anim-pop flex max-h-[92dvh] w-full max-w-4xl flex-col overflow-hidden rounded-b-none rounded-t-3xl border-b-0 sm:max-h-[88dvh] sm:rounded-2xl sm:border-b">
        <div className="flex items-center justify-between gap-2 border-b border-slate-800/80 bg-[#070B14]/80 px-4 py-3">
          <div className="flex items-center gap-2">
            <span className="inline-flex h-7 w-7 items-center justify-center rounded-xl border border-teal-400/35 bg-teal-400/10 text-teal-300">
              <Gem className="h-4 w-4" />
            </span>
            <div>
              <div className="text-xs font-black uppercase tracking-[0.16em] text-teal-300">Brilly Vault</div>
              <div className="text-[10px] text-slate-400">
                {stats.userMoves} !! brilliant · {stats.clutchSaves} clutch · {stats.trapsPunished} traps · {stats.cleanSweeps} sweeps
              </div>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="inline-flex h-8 w-8 items-center justify-center rounded-xl border border-slate-700/80 bg-slate-900/80 text-slate-300 transition hover:border-teal-400/50 hover:text-white"
            aria-label="Close Brilly Vault"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-3.5 sm:p-4 nice-scroll pb-[max(1.25rem,env(safe-area-inset-bottom))]">
          <BrillyVaultView
            entries={entries}
            stats={stats}
            username={username}
            boardTheme={boardTheme}
            inModal
            savedPositions={savedPositions}
            onOpenEntry={(entry) => {
              onClose();
              onOpenEntry(entry);
            }}
            onOpenBookmark={
              onOpenBookmark
                ? (bm) => {
                    onClose();
                    onOpenBookmark(bm);
                  }
                : undefined
            }
            onRemoveBookmark={onRemoveBookmark}
            onOpenGames={() => {
              onClose();
              onOpenGames();
            }}
          />
        </div>
      </div>
    </div>
  );
};
