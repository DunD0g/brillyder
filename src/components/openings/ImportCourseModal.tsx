import React, { useState } from 'react';
import { BookPlus, Link2, Loader2, Upload, X } from 'lucide-react';
import type { OpeningCourse, Side } from '../../types/openings';
import {
  extractLichessStudyIds,
  fetchLichessStudyPgn,
  importPgnToCourse,
} from '../../services/repertoireImporter';

interface Props {
  open: boolean;
  defaultSide: Side;
  onClose: () => void;
  onImported: (course: OpeningCourse) => Promise<void>;
}

export const ImportCourseModal: React.FC<Props> = ({
  open,
  defaultSide,
  onClose,
  onImported,
}) => {
  const [name, setName] = useState('');
  const [side, setSide] = useState<Side>(defaultSide);
  const [studyUrl, setStudyUrl] = useState('');
  const [pgn, setPgn] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  React.useEffect(() => {
    setSide(defaultSide);
    if (open) setError(null);
  }, [defaultSide, open]);

  React.useEffect(() => {
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

  if (!open) return null;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);
    try {
      let rawPgn = pgn.trim();
      let source: 'pgn' | 'lichess-study' = 'pgn';

      if (!rawPgn && studyUrl.trim()) {
        rawPgn = await fetchLichessStudyPgn(studyUrl.trim());
        source = 'lichess-study';
      } else if (extractLichessStudyIds(rawPgn)) {
        rawPgn = await fetchLichessStudyPgn(rawPgn);
        source = 'lichess-study';
      }

      if (!rawPgn) {
        throw new Error('Paste a PGN or enter a public Lichess Study URL.');
      }

      const course = importPgnToCourse({
        name: name.trim() || (source === 'lichess-study' ? 'Lichess Study Course' : 'Custom PGN Course'),
        side,
        pgn: rawPgn,
        source,
      });

      await onImported(course);
      setName('');
      setStudyUrl('');
      setPgn('');
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Import failed.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-[85] flex items-end justify-center bg-[#04070e]/80 backdrop-blur-md sm:items-center sm:p-4"
      role="dialog"
      aria-modal="true"
      aria-label="Import PGN or Lichess Study"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="glass-card glass-card-strong anim-pop max-h-[92dvh] w-full max-w-lg overflow-y-auto rounded-b-none rounded-t-3xl p-4 pb-[max(1.25rem,env(safe-area-inset-bottom))] nice-scroll sm:rounded-2xl sm:pb-4">
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2 text-xs font-black uppercase tracking-[0.16em] text-brilly">
            <BookPlus className="h-4 w-4" /> Import PGN / Lichess Study
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg p-1 text-slate-400 hover:text-white"
            aria-label="Close importer"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <form onSubmit={(e) => void handleSubmit(e)} className="mt-3 space-y-3">
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-[1fr_auto]">
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Course name (e.g. Caro-Kann Fantasy)"
              className="rounded-xl border border-slate-700/80 bg-void px-3 py-2 text-xs text-slate-100 placeholder-slate-500 focus:border-teal-400 focus:outline-none"
            />
            <div className="inline-flex rounded-xl border border-slate-800 bg-void p-0.5">
              {(['white', 'black'] as Side[]).map((s) => (
                <button
                  key={s}
                  type="button"
                  onClick={() => setSide(s)}
                  className={`rounded-lg px-3 py-1.5 text-[11px] font-black capitalize ${
                    side === s ? 'bg-teal-400/20 text-teal-200' : 'text-slate-400'
                  }`}
                >
                  {s}
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="flex items-center gap-1 text-[10px] font-bold uppercase tracking-wider text-slate-400">
              <Link2 className="h-3 w-3 text-brilly" /> Lichess Study URL (Public)
            </label>
            <input
              type="text"
              value={studyUrl}
              onChange={(e) => setStudyUrl(e.target.value)}
              placeholder="https://lichess.org/study/XXXXXXXX"
              className="mt-1 w-full rounded-xl border border-slate-700/80 bg-void px-3 py-2 text-xs text-slate-100 placeholder-slate-500 focus:border-teal-400 focus:outline-none"
            />
          </div>

          <div>
            <label className="text-[10px] font-bold uppercase tracking-wider text-slate-400">
              Or Paste Raw PGN (Variations Supported)
            </label>
            <textarea
              rows={5}
              value={pgn}
              onChange={(e) => setPgn(e.target.value)}
              placeholder="1. d4 d5 2. Bf4 Nf6 (2... c5 3. e3 Nc6) 3. e3 e6 *"
              className="mt-1 w-full rounded-xl border border-slate-700/80 bg-void p-2.5 font-mono text-[11px] text-slate-100 placeholder-slate-500 focus:border-teal-400 focus:outline-none"
            />
          </div>

          {error && (
            <div className="rounded-xl border border-rose-500/35 bg-rose-500/10 px-3 py-2 text-xs text-rose-200">
              {error}
            </div>
          )}

          <div className="flex items-center justify-end gap-2 pt-1">
            <button
              type="button"
              onClick={onClose}
              className="rounded-xl border border-slate-700 bg-hull px-3 py-2 text-xs font-bold text-slate-300"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={loading}
              className="inline-flex items-center gap-1.5 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-4 py-2 text-xs font-extrabold text-slate-950 disabled:opacity-50"
            >
              {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Upload className="h-3.5 w-3.5" />}
              {loading ? 'Importing…' : 'Import Course'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
