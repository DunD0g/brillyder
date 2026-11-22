import React, { useMemo, useState } from 'react';
import { Check, CheckCircle2, X, XCircle } from 'lucide-react';
import type { OpeningCourse, OpeningLine } from '../../types/openings';
import {
  createCustomCourseLine,
  parseAndValidateLineMoves,
} from '../../services/repertoireLines';

interface Props {
  course: OpeningCourse;
  editingLine?: OpeningLine | null;
  onSave: (line: OpeningLine, movesChanged: boolean) => Promise<void>;
  onCancel: () => void;
}

function movesToDisplayString(moves: string[]): string {
  const parts: string[] = [];
  for (let i = 0; i < moves.length; i += 2) {
    const moveNum = Math.floor(i / 2) + 1;
    parts.push(moves[i + 1] ? `${moveNum}. ${moves[i]} ${moves[i + 1]}` : `${moveNum}. ${moves[i]}`);
  }
  return parts.join(' ');
}

export const LineEditorPanel: React.FC<Props> = ({
  course,
  editingLine = null,
  onSave,
  onCancel,
}) => {
  const [title, setTitle] = useState(editingLine?.title ?? '');
  const [eco, setEco] = useState(editingLine?.eco ?? '');
  const [movesText, setMovesText] = useState(
    editingLine ? movesToDisplayString(editingLine.moves) : ''
  );
  const [planNote, setPlanNote] = useState(
    editingLine?.annotations[editingLine.annotations.length - 1]?.plan ??
      editingLine?.subtitle ??
      ''
  );
  const [saving, setSaving] = useState(false);

  const parsed = useMemo(() => parseAndValidateLineMoves(movesText), [movesText]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!parsed.ok || saving) return;
    setSaving(true);
    try {
      const movesChanged =
        !editingLine ||
        editingLine.moves.length !== parsed.moves.length ||
        editingLine.moves.some((m, idx) => m !== parsed.moves[idx]);

      let nextLine: OpeningLine;
      if (editingLine && !movesChanged) {
        const trimmedPlan = planNote.trim();
        const existingAnns = editingLine.annotations.slice();
        if (trimmedPlan) {
          if (existingAnns.length > 0) {
            existingAnns[existingAnns.length - 1] = {
              ...existingAnns[existingAnns.length - 1],
              plan: trimmedPlan,
            };
          } else {
            const parity = course.side === 'white' ? 0 : 1;
            let lastUserPly = -1;
            for (let i = editingLine.moves.length - 1; i >= 0; i--) {
              if (i % 2 === parity) {
                lastUserPly = i;
                break;
              }
            }
            if (lastUserPly >= 0) {
              existingAnns.push({ ply: lastUserPly, plan: trimmedPlan });
            }
          }
        }
        nextLine = {
          ...editingLine,
          title: title.trim() || editingLine.title,
          subtitle: trimmedPlan || editingLine.subtitle,
          eco: eco.trim().toUpperCase(),
          annotations: existingAnns,
        };
      } else {
        nextLine = createCustomCourseLine({
          course,
          title: title.trim() || `${course.name} Line`,
          eco,
          planNote,
          moves: parsed.moves,
          existingLineId: editingLine?.id,
        });
      }
      await onSave(nextLine, movesChanged);
    } finally {
      setSaving(false);
    }
  };

  return (
    <form
      onSubmit={(e) => void handleSubmit(e)}
      className="glass-card border-teal-400/40 p-3.5 space-y-2.5"
    >
      <div className="flex items-center justify-between gap-2">
        <span className="text-[11px] font-black uppercase tracking-[0.14em] text-brilly">
          {editingLine ? `Edit line · ${editingLine.title}` : `Add new line to ${course.name}`}
        </span>
        <button
          type="button"
          onClick={onCancel}
          className="inline-flex h-7 w-7 items-center justify-center rounded-lg border border-slate-700 bg-void/70 text-slate-400 hover:text-white"
          aria-label="Close line editor"
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </div>

      <div className="grid grid-cols-1 gap-2 sm:grid-cols-[1fr_92px]">
        <input
          type="text"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Line title (e.g., Anti-Nf6 Quick e5)"
          className="rounded-xl border border-slate-700 bg-void/75 px-3 py-1.5 text-xs text-slate-100 placeholder:text-slate-500 focus:border-teal-400/60 focus:outline-none"
          required
        />
        <input
          type="text"
          value={eco}
          onChange={(e) => setEco(e.target.value)}
          placeholder="ECO (C54)"
          maxLength={6}
          className="rounded-xl border border-slate-700 bg-void/75 px-2.5 py-1.5 font-mono text-xs uppercase text-slate-100 placeholder:text-slate-500 focus:border-teal-400/60 focus:outline-none"
        />
      </div>

      <div>
        <textarea
          value={movesText}
          onChange={(e) => setMovesText(e.target.value)}
          rows={2}
          placeholder="Moves in SAN (e.g., 1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 Nf6)"
          className="w-full rounded-xl border border-slate-700 bg-void/75 px-3 py-2 font-mono text-xs text-slate-100 placeholder:text-slate-500 focus:border-teal-400/60 focus:outline-none"
          required
        />
        <div className="mt-1 flex items-center gap-1.5 text-[10px]">
          {parsed.ok ? (
            <span className="inline-flex items-center gap-1 text-clean">
              <CheckCircle2 className="h-3 w-3 shrink-0" />
              Valid chess.js SAN ({parsed.moves.length} plies)
            </span>
          ) : (
            <span className="inline-flex items-center gap-1 text-amber-300">
              <XCircle className="h-3 w-3 shrink-0" />
              {parsed.error}
            </span>
          )}
        </div>
      </div>

      <input
        type="text"
        value={planNote}
        onChange={(e) => setPlanNote(e.target.value)}
        placeholder="Key middlegame plan or idea note (optional)"
        className="w-full rounded-xl border border-slate-700 bg-void/75 px-3 py-1.5 text-xs text-slate-100 placeholder:text-slate-500 focus:border-teal-400/60 focus:outline-none"
      />

      <div className="flex items-center justify-end gap-2 pt-0.5">
        <button
          type="button"
          onClick={onCancel}
          className="rounded-xl border border-slate-700 bg-hull px-3 py-1.5 text-[11px] font-bold text-slate-300"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={!parsed.ok || saving}
          className="inline-flex items-center gap-1 rounded-xl bg-gradient-to-r from-teal-400 to-emerald-400 px-3.5 py-1.5 text-[11px] font-extrabold text-slate-950 disabled:opacity-40"
        >
          <Check className="h-3.5 w-3.5" /> {editingLine ? 'Save changes' : 'Add line & unlock FSRS'}
        </button>
      </div>
    </form>
  );
};
