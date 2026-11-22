import React, { useEffect, useMemo, useState } from 'react';
import {
  BarChart2,
  BookOpen,
  BookPlus,
  Check,
  Compass,
  Download,
  GitBranch,
  Layers,
  Orbit,
  Pencil,
  Play,
  Plus,
  RotateCcw,
  ShieldAlert,
  Trash2,
} from 'lucide-react';
import type { AnalyzedGame, BoardThemeId } from '../types/chess';
import type { FsrsOpeningCard, OpeningCourse, OpeningLine, Side } from '../types/openings';
import { hydrateCourseCards, hydrateLineCards, isCardDue } from '../lib/fsrsOpening';
import { addPatchedLineToCourse, type RepertoireGap } from '../services/repertoireCoverage';
import { removeLineFromCourse, upsertLineInCourse } from '../services/repertoireLines';
import { exportCourseToPgn } from '../services/repertoireTree';
import { useVibe } from '../utils/vibeCopy';
import type { UserHandleSpec } from '../utils/player';
import type { ExplorerPrefSettings } from './SettingsMenu';
import { MothershipCard } from './openings/MothershipCard';
import { GuidedWalkthrough } from './openings/GuidedWalkthrough';
import { RepertoireTreeView } from './openings/RepertoireTreeView';
import { LineEditorPanel } from './openings/LineEditorPanel';
import { OpeningDrillView } from './openings/OpeningDrillView';
import { CoverageGapPanel } from './openings/CoverageGapPanel';
import { ImportCourseModal } from './openings/ImportCourseModal';
import { MultiGameOpeningReport } from './openings/MultiGameOpeningReport';

type OpeningsSubTab = 'formation' | 'walkthrough' | 'drill' | 'coverage' | 'report';

interface Props {
  courses: OpeningCourse[];
  modifiedStarterIds?: Set<string>;
  fsrsCards: FsrsOpeningCard[];
  analyzedGames: AnalyzedGame[];
  username: UserHandleSpec;
  boardTheme: BoardThemeId;
  explorerPrefs: ExplorerPrefSettings;
  onSaveCourse: (course: OpeningCourse, newCards?: FsrsOpeningCard[], replacedLineId?: string) => Promise<void>;
  onDeleteCourse: (courseId: string) => Promise<void>;
  onDeleteLine?: (course: OpeningCourse, lineId: string) => Promise<void>;
  onUnlockCards: (cards: FsrsOpeningCard[]) => Promise<void>;
  onCardReviewed: (updated: FsrsOpeningCard) => Promise<void>;
  onOpenGame: (gameId: string, ply: number) => void;
}

export const OpeningsView: React.FC<Props> = ({
  courses,
  modifiedStarterIds,
  fsrsCards,
  analyzedGames,
  username,
  boardTheme,
  explorerPrefs,
  onSaveCourse,
  onDeleteCourse,
  onDeleteLine,
  onUnlockCards,
  onCardReviewed,
  onOpenGame,
}) => {
  const { vibe } = useVibe();
  const [side, setSide] = useState<Side>('white');
  const [subTab, setSubTab] = useState<OpeningsSubTab>('formation');
  const [selectedCourseId, setSelectedCourseId] = useState<string>('');
  const [selectedLineId, setSelectedLineId] = useState<string>('');
  const [drillFocusLineId, setDrillFocusLineId] = useState<string | null>(null);
  const [importOpen, setImportOpen] = useState(false);
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null);
  const [lineEditorMode, setLineEditorMode] = useState<'closed' | 'add' | 'edit'>('closed');
  const [confirmDeleteLineId, setConfirmDeleteLineId] = useState<string | null>(null);
  const [walkthroughMode, setWalkthroughMode] = useState<'steps' | 'tree'>('steps');
  const [exportedPgn, setExportedPgn] = useState(false);

  const sideCourses = useMemo(
    () => courses.filter((c) => c.side === side),
    [courses, side]
  );

  const selectedCourse = useMemo(
    () => sideCourses.find((c) => c.id === selectedCourseId) ?? sideCourses[0] ?? null,
    [sideCourses, selectedCourseId]
  );

  useEffect(() => {
    if (selectedCourse && selectedCourse.id !== selectedCourseId) {
      setSelectedCourseId(selectedCourse.id);
    }
  }, [selectedCourse, selectedCourseId]);

  const selectedLine = useMemo(
    () => selectedCourse?.lines.find((l) => l.id === selectedLineId) ?? selectedCourse?.lines[0] ?? null,
    [selectedCourse, selectedLineId]
  );

  useEffect(() => {
    if (selectedLine && selectedLine.id !== selectedLineId) {
      setSelectedLineId(selectedLine.id);
    }
  }, [selectedLine, selectedLineId]);

  const cardMap = useMemo(() => {
    const map = new Map<string, FsrsOpeningCard>();
    for (const c of fsrsCards) map.set(c.cardId, c);
    return map;
  }, [fsrsCards]);

  const dueCountSide = useMemo(
    () => fsrsCards.filter((c) => c.side === side && isCardDue(c)).length,
    [fsrsCards, side]
  );

  const isLineUnlocked = (course: OpeningCourse, line: OpeningLine): boolean => {
    const lineCards = hydrateLineCards(course.id, course.side, line, cardMap);
    return lineCards.length > 0 && lineCards.every((c) => c.unlocked);
  };

  const handleUnlockLine = async (line: OpeningLine) => {
    if (!selectedCourse) return;
    const cards = hydrateLineCards(selectedCourse.id, selectedCourse.side, line, cardMap, { unlocked: true });
    const unlocked = cards.map((c) => ({ ...c, unlocked: true }));
    await onUnlockCards(unlocked);
  };

  const handleUnlockAllSideStarter = async () => {
    const batch: FsrsOpeningCard[] = [];
    for (const course of sideCourses) {
      for (const card of hydrateCourseCards(course, cardMap, { unlocked: true })) {
        batch.push({ ...card, unlocked: true });
      }
    }
    await onUnlockCards(batch);
  };

  const handlePatchGap = async (
    course: OpeningCourse,
    gap: RepertoireGap,
    replySan: string,
    note: string
  ) => {
    const { updatedCourse, newCards } = addPatchedLineToCourse(course, gap.moveSequence, replySan, {
      planNote: note,
    });
    await onSaveCourse(updatedCourse, newCards);
  };

  const handleImportedCourse = async (course: OpeningCourse) => {
    const cards = hydrateCourseCards(course, undefined, { unlocked: true });
    await onSaveCourse(course, cards);
    setSide(course.side);
    setSelectedCourseId(course.id);
    setSubTab('walkthrough');
  };

  const handleSaveEditedLine = async (line: OpeningLine, movesChanged: boolean) => {
    if (!selectedCourse) return;
    const updatedCourse = upsertLineInCourse(selectedCourse, line);
    const cards = movesChanged
      ? hydrateLineCards(updatedCourse.id, updatedCourse.side, line, undefined, { unlocked: true }).map((c) => ({
          ...c,
          unlocked: true,
        }))
      : undefined;
    await onSaveCourse(updatedCourse, cards, movesChanged ? line.id : undefined);
    setSelectedLineId(line.id);
    setLineEditorMode('closed');
  };

  const handleConfirmDeleteLine = async (lineId: string) => {
    if (!selectedCourse || selectedCourse.lines.length <= 1) return;
    setConfirmDeleteLineId(null);
    setLineEditorMode('closed');
    if (onDeleteLine) {
      await onDeleteLine(selectedCourse, lineId);
    } else {
      const updated = removeLineFromCourse(selectedCourse, lineId);
      await onSaveCourse(updated);
    }
  };

  const handleExportCoursePgn = () => {
    if (!selectedCourse) return;
    const pgn = exportCourseToPgn(selectedCourse);
    const blob = new Blob([pgn], { type: 'application/x-chess-pgn;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${selectedCourse.id}.pgn`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    setExportedPgn(true);
    window.setTimeout(() => setExportedPgn(false), 1800);
  };

  return (
    <div className="space-y-3 pb-24">
      {/* Studio Header */}
      <section className="glass-card glass-card-strong p-3.5 sm:p-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <div className="flex items-center gap-1.5 text-[10px] font-black uppercase tracking-[0.18em] text-brilly">
              <BookOpen className="h-4 w-4" /> Opening Repertoire Studio
            </div>
            <h1 className="mt-0.5 text-lg font-extrabold text-white">
              {vibe === 'cosmic' ? 'Mothership Formations & FSRS Warp' : 'Courses, FSRS Drills & Coverage'}
            </h1>
          </div>

          <div className="flex flex-wrap items-center gap-1.5">
            <div className="inline-flex rounded-xl border border-slate-800 bg-void/70 p-0.5">
              {(['white', 'black'] as Side[]).map((s) => (
                <button
                  key={s}
                  type="button"
                  onClick={() => { setSide(s); setDrillFocusLineId(null); }}
                  className={`inline-flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[11px] font-black capitalize transition ${
                    side === s ? 'bg-teal-400/20 text-teal-200' : 'text-slate-400 hover:text-slate-200'
                  }`}
                >
                  <span
                    className={`h-2.5 w-2.5 rounded-full border ${
                      s === 'white' ? 'border-slate-300 bg-white' : 'border-slate-500 bg-slate-950'
                    }`}
                  />
                  {s}
                </button>
              ))}
            </div>

            <button
              type="button"
              onClick={() => setImportOpen(true)}
              className="inline-flex items-center gap-1.5 rounded-xl border border-teal-400/35 bg-teal-400/10 px-3 py-1.5 text-[11px] font-bold text-teal-200 transition hover:bg-teal-400/20"
            >
              <BookPlus className="h-3.5 w-3.5" /> Import
            </button>

            {selectedCourse && (
              <button
                type="button"
                onClick={handleExportCoursePgn}
                title={`Export ${selectedCourse.name} as multi-chapter PGN`}
                className="inline-flex items-center gap-1 rounded-xl border border-slate-800 bg-void/70 px-2.5 py-1.5 text-[11px] font-bold text-slate-300 transition hover:border-slate-600 hover:text-white"
              >
                {exportedPgn ? <Check className="h-3.5 w-3.5 text-emerald-400" /> : <Download className="h-3.5 w-3.5 text-slate-400" />}
                <span className="hidden sm:inline">{exportedPgn ? 'Exported' : 'PGN'}</span>
              </button>
            )}
          </div>
        </div>

        {/* Course Selector Strip */}
        <div className="mt-3 grid grid-cols-2 gap-2 lg:grid-cols-4">
          {sideCourses.map((course) => {
            const active = selectedCourse?.id === course.id;
            const courseCards = hydrateCourseCards(course, cardMap);
            const unlockedCount = courseCards.filter((c) => c.unlocked).length;
            const dueCount = courseCards.filter((c) => isCardDue(c)).length;
            const isCustom = course.source === 'pgn' || course.source === 'lichess-study';
            const isModifiedStarter = !isCustom && Boolean(modifiedStarterIds?.has(course.id));
            return (
              <div
                key={course.id}
                role="button"
                tabIndex={0}
                onClick={() => { setSelectedCourseId(course.id); setDrillFocusLineId(null); setLineEditorMode('closed'); setConfirmDeleteLineId(null); }}
                onKeyDown={(e) => {
                  if (e.target !== e.currentTarget) return;
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    setSelectedCourseId(course.id);
                    setDrillFocusLineId(null);
                    setLineEditorMode('closed');
                    setConfirmDeleteLineId(null);
                  }
                }}
                className={`group relative min-w-0 cursor-pointer rounded-xl border p-2.5 text-left transition active:scale-[0.98] ${
                  active
                    ? 'border-teal-400/60 bg-teal-400/12 shadow-lg shadow-teal-500/10'
                    : 'border-slate-800 bg-void/55 hover:border-slate-600'
                }`}
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="flex items-center gap-1.5 text-[9px] font-black uppercase tracking-wider text-purple-300">
                      <span>{vibe === 'cosmic' ? course.codename : course.difficulty}</span>
                      {isModifiedStarter && (
                        <span className="rounded bg-teal-400/15 px-1 py-0.5 text-[8px] font-bold text-teal-200">
                          edited
                        </span>
                      )}
                    </div>
                    <div className="truncate text-xs font-extrabold text-white">{course.name}</div>
                  </div>
                  <div className="flex items-center gap-1">
                    {dueCount > 0 && (
                      <span className="rounded-full bg-purple-500/25 px-1.5 py-0.5 font-mono text-[9px] font-bold text-purple-200">
                        {dueCount} due
                      </span>
                    )}
                    {(isCustom || isModifiedStarter) && (
                      confirmDeleteId === course.id ? (
                        <div className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
                          <button
                            type="button"
                            onClick={() => {
                              setConfirmDeleteId(null);
                              void onDeleteCourse(course.id);
                            }}
                            className="rounded-md border border-rose-500/50 bg-rose-500/20 px-1.5 py-0.5 text-[9px] font-extrabold text-rose-200 hover:bg-rose-500/30"
                          >
                            {isCustom ? 'Delete' : 'Reset'}
                          </button>
                          <button
                            type="button"
                            onClick={() => setConfirmDeleteId(null)}
                            className="rounded-md border border-slate-700 bg-slate-800 px-1.5 py-0.5 text-[9px] font-bold text-slate-300"
                          >
                            Cancel
                          </button>
                        </div>
                      ) : (
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            setConfirmDeleteId(course.id);
                          }}
                          aria-label={isCustom ? `Delete ${course.name}` : `Reset ${course.name} to default`}
                          title={isCustom ? 'Delete custom course' : 'Reset starter course to default'}
                          className="rounded-lg p-1.5 text-slate-500 transition hover:bg-rose-500/15 hover:text-rose-300"
                        >
                          {isCustom ? <Trash2 className="h-3.5 w-3.5" /> : <RotateCcw className="h-3.5 w-3.5" />}
                        </button>
                      )
                    )}
                  </div>
                </div>
                <div className="mt-1.5 flex items-center gap-2 text-[10px] text-slate-400">
                  <span className="inline-flex items-center gap-1">
                    <Layers className="h-3 w-3 text-slate-500" /> {course.lines.length} lines
                  </span>
                  <span>·</span>
                  <span>{unlockedCount}/{courseCards.length} FSRS</span>
                </div>
              </div>
            );
          })}
        </div>

        {/* Sub-Navigation */}
        <div className="mt-3 flex flex-wrap gap-1.5 border-t border-slate-800/80 pt-3">
          {([
            ['formation', vibe === 'cosmic' ? 'Mothership' : 'Formation', Compass],
            ['walkthrough', 'Walkthrough', Play],
            ['drill', `FSRS Drill${dueCountSide > 0 ? ` (${dueCountSide})` : ''}`, Orbit],
            ['coverage', 'Coverage & Gaps', ShieldAlert],
            ['report', 'Report Card', BarChart2],
          ] as Array<[OpeningsSubTab, string, typeof Compass]>).map(([id, label, Icon]) => (
            <button
              key={id}
              type="button"
              onClick={() => {
                setSubTab(id);
                if (id !== 'drill') setDrillFocusLineId(null);
              }}
              className={`inline-flex items-center gap-1.5 rounded-xl border px-3 py-1.5 text-[11px] font-bold transition ${
                subTab === id
                  ? 'border-teal-400/50 bg-teal-400/15 text-teal-200'
                  : 'border-slate-800 bg-void/60 text-slate-400 hover:border-slate-600 hover:text-slate-200'
              }`}
            >
              <Icon className="h-3.5 w-3.5" />
              {label}
            </button>
          ))}
        </div>
      </section>

      {/* Active Sub-View */}
      {selectedCourse && subTab === 'formation' && (
        <MothershipCard
          course={selectedCourse}
          boardTheme={boardTheme}
          onStartWalkthrough={() => setSubTab('walkthrough')}
          onStartDrill={() => { setDrillFocusLineId(null); setSubTab('drill'); }}
        />
      )}

      {selectedCourse && subTab === 'walkthrough' && (
        <div className="space-y-3">
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex min-w-0 items-center gap-1.5 overflow-x-auto pb-1 nice-scroll sm:flex-wrap sm:overflow-visible sm:pb-0">
              {selectedCourse.lines.map((line) => {
                const active = selectedLine?.id === line.id;
                const unlocked = isLineUnlocked(selectedCourse, line);
                return (
                  <button
                    key={line.id}
                    type="button"
                    onClick={() => {
                      setSelectedLineId(line.id);
                      setLineEditorMode('closed');
                      setConfirmDeleteLineId(null);
                    }}
                    className={`inline-flex shrink-0 items-center gap-1.5 rounded-xl border px-2.5 py-1.5 text-[11px] font-bold transition active:scale-[0.98] ${
                      active
                        ? 'border-teal-400/55 bg-teal-400/15 text-teal-100'
                        : 'border-slate-800 bg-hull/70 text-slate-400 hover:border-slate-600 hover:text-slate-200'
                    }`}
                  >
                    {line.eco && <span className="font-mono text-[9px] text-slate-500">{line.eco}</span>}
                    <span>{line.title}</span>
                    {unlocked && <span className="h-1.5 w-1.5 rounded-full bg-clean" />}
                  </button>
                );
              })}
            </div>

            <div className="flex shrink-0 items-center gap-1.5 self-end sm:self-auto">
              <div className="inline-flex rounded-xl border border-slate-800 bg-void/70 p-0.5 text-[10px] font-bold">
                <button
                  type="button"
                  onClick={() => setWalkthroughMode('steps')}
                  className={`rounded-lg px-2 py-1 transition ${
                    walkthroughMode === 'steps' ? 'bg-teal-400/20 text-teal-200' : 'text-slate-400 hover:text-slate-200'
                  }`}
                >
                  Line
                </button>
                <button
                  type="button"
                  onClick={() => setWalkthroughMode('tree')}
                  className={`inline-flex items-center gap-1 rounded-lg px-2 py-1 transition ${
                    walkthroughMode === 'tree' ? 'bg-teal-400/20 text-teal-200' : 'text-slate-400 hover:text-slate-200'
                  }`}
                >
                  <GitBranch className="h-3 w-3" /> Tree
                </button>
              </div>
              <button
                type="button"
                onClick={() => {
                  setConfirmDeleteLineId(null);
                  setLineEditorMode((m) => (m === 'add' ? 'closed' : 'add'));
                }}
                className="inline-flex items-center gap-1 rounded-xl border border-teal-400/35 bg-teal-400/10 px-2.5 py-1.5 text-[10px] font-extrabold text-teal-200 transition hover:bg-teal-400/20"
              >
                <Plus className="h-3 w-3" /> Add line
              </button>
              {selectedLine && (
                <button
                  type="button"
                  onClick={() => {
                    setConfirmDeleteLineId(null);
                    setLineEditorMode((m) => (m === 'edit' ? 'closed' : 'edit'));
                  }}
                  className="inline-flex items-center gap-1 rounded-xl border border-slate-700 bg-hull px-2.5 py-1.5 text-[10px] font-bold text-slate-200 transition hover:border-slate-500"
                >
                  <Pencil className="h-3 w-3" /> Edit
                </button>
              )}
              {selectedLine && selectedCourse.lines.length > 1 && (
                confirmDeleteLineId === selectedLine.id ? (
                  <div className="inline-flex items-center gap-1">
                    <button
                      type="button"
                      onClick={() => void handleConfirmDeleteLine(selectedLine.id)}
                      className="rounded-lg border border-rose-500/50 bg-rose-500/20 px-2 py-1 text-[10px] font-extrabold text-rose-200 hover:bg-rose-500/30"
                    >
                      Remove
                    </button>
                    <button
                      type="button"
                      onClick={() => setConfirmDeleteLineId(null)}
                      className="rounded-lg border border-slate-700 bg-slate-800 px-2 py-1 text-[10px] font-bold text-slate-300"
                    >
                      Cancel
                    </button>
                  </div>
                ) : (
                  <button
                    type="button"
                    onClick={() => setConfirmDeleteLineId(selectedLine.id)}
                    aria-label={`Remove line ${selectedLine.title}`}
                    className="inline-flex items-center gap-1 rounded-xl border border-rose-500/25 bg-rose-500/10 px-2 py-1.5 text-[10px] font-bold text-rose-200 transition hover:bg-rose-500/20"
                  >
                    <Trash2 className="h-3 w-3" />
                  </button>
                )
              )}
            </div>
          </div>

          {lineEditorMode !== 'closed' && (
            <LineEditorPanel
              key={`${selectedCourse.id}-${lineEditorMode}-${lineEditorMode === 'edit' ? selectedLine?.id : 'new'}`}
              course={selectedCourse}
              editingLine={lineEditorMode === 'edit' ? selectedLine : null}
              onSave={handleSaveEditedLine}
              onCancel={() => setLineEditorMode('closed')}
            />
          )}

          {walkthroughMode === 'tree' ? (
            <RepertoireTreeView
              course={selectedCourse}
              cards={fsrsCards}
              boardTheme={boardTheme}
              onOpenLineWalkthrough={(lineId) => {
                setSelectedLineId(lineId);
                setWalkthroughMode('steps');
              }}
              onDrillLine={(lineId) => {
                setSelectedLineId(lineId);
                setDrillFocusLineId(lineId);
                setSubTab('drill');
              }}
            />
          ) : (
            selectedLine && (
              <GuidedWalkthrough
                course={selectedCourse}
                line={selectedLine}
                boardTheme={boardTheme}
                unlocked={isLineUnlocked(selectedCourse, selectedLine)}
                onUnlockLine={(l) => void handleUnlockLine(l)}
                onStartDrillForLine={(l) => {
                  setDrillFocusLineId(l.id);
                  setSubTab('drill');
                }}
              />
            )
          )}
        </div>
      )}

      {subTab === 'drill' && (
        <OpeningDrillView
          courses={courses}
          side={side}
          cards={fsrsCards}
          boardTheme={boardTheme}
          explorerPrefs={explorerPrefs}
          focusCourseId={drillFocusLineId ? selectedCourse?.id : null}
          focusLineId={drillFocusLineId}
          onCardReviewed={onCardReviewed}
          onUnlockStarterLines={handleUnlockAllSideStarter}
        />
      )}

      {selectedCourse && subTab === 'coverage' && (
        <CoverageGapPanel
          course={selectedCourse}
          boardTheme={boardTheme}
          explorerPrefs={explorerPrefs}
          onPatchGap={handlePatchGap}
        />
      )}

      {subTab === 'report' && (
        <MultiGameOpeningReport
          analyzedGames={analyzedGames}
          username={username}
          courses={courses}
          onOpenGame={onOpenGame}
        />
      )}

      <ImportCourseModal
        open={importOpen}
        defaultSide={side}
        onClose={() => setImportOpen(false)}
        onImported={handleImportedCourse}
      />
    </div>
  );
};
