import React, { useEffect, useMemo, useState } from 'react';
import {
  BarChart2,
  BookOpen,
  BookPlus,
  Compass,
  Layers,
  Orbit,
  Play,
  ShieldAlert,
  Trash2,
} from 'lucide-react';
import type { AnalyzedGame, BoardThemeId } from '../types/chess';
import type { FsrsOpeningCard, OpeningCourse, OpeningLine, Side } from '../types/openings';
import { hydrateCourseCards, hydrateLineCards, isCardDue } from '../lib/fsrsOpening';
import { addPatchedLineToCourse, type RepertoireGap } from '../services/repertoireCoverage';
import { useVibe } from '../utils/vibeCopy';
import type { UserHandleSpec } from '../utils/player';
import type { ExplorerPrefSettings } from './SettingsMenu';
import { MothershipCard } from './openings/MothershipCard';
import { GuidedWalkthrough } from './openings/GuidedWalkthrough';
import { OpeningDrillView } from './openings/OpeningDrillView';
import { CoverageGapPanel } from './openings/CoverageGapPanel';
import { ImportCourseModal } from './openings/ImportCourseModal';
import { MultiGameOpeningReport } from './openings/MultiGameOpeningReport';

type OpeningsSubTab = 'formation' | 'walkthrough' | 'drill' | 'coverage' | 'report';

interface Props {
  courses: OpeningCourse[];
  fsrsCards: FsrsOpeningCard[];
  analyzedGames: AnalyzedGame[];
  username: UserHandleSpec;
  boardTheme: BoardThemeId;
  explorerPrefs: ExplorerPrefSettings;
  onSaveCourse: (course: OpeningCourse, newCards?: FsrsOpeningCard[]) => Promise<void>;
  onDeleteCourse: (courseId: string) => Promise<void>;
  onUnlockCards: (cards: FsrsOpeningCard[]) => Promise<void>;
  onCardReviewed: (updated: FsrsOpeningCard) => Promise<void>;
  onOpenGame: (gameId: string, ply: number) => void;
}

export const OpeningsView: React.FC<Props> = ({
  courses,
  fsrsCards,
  analyzedGames,
  username,
  boardTheme,
  explorerPrefs,
  onSaveCourse,
  onDeleteCourse,
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
              <BookPlus className="h-3.5 w-3.5" /> Import PGN / Study
            </button>
          </div>
        </div>

        {/* Course Selector Strip */}
        <div className="mt-3 grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          {sideCourses.map((course) => {
            const active = selectedCourse?.id === course.id;
            const courseCards = hydrateCourseCards(course, cardMap);
            const unlockedCount = courseCards.filter((c) => c.unlocked).length;
            const dueCount = courseCards.filter((c) => isCardDue(c)).length;
            const isCustom = course.source === 'pgn' || course.source === 'lichess-study';
            return (
              <div
                key={course.id}
                role="button"
                tabIndex={0}
                onClick={() => { setSelectedCourseId(course.id); setDrillFocusLineId(null); }}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    setSelectedCourseId(course.id);
                    setDrillFocusLineId(null);
                  }
                }}
                className={`group relative cursor-pointer rounded-xl border p-2.5 text-left transition ${
                  active
                    ? 'border-teal-400/60 bg-teal-400/12 shadow-lg shadow-teal-500/10'
                    : 'border-slate-800 bg-void/55 hover:border-slate-600'
                }`}
              >
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <div className="text-[9px] font-black uppercase tracking-wider text-purple-300">
                      {vibe === 'cosmic' ? course.codename : course.difficulty}
                    </div>
                    <div className="truncate text-xs font-extrabold text-white">{course.name}</div>
                  </div>
                  <div className="flex items-center gap-1">
                    {dueCount > 0 && (
                      <span className="rounded-full bg-purple-500/25 px-1.5 py-0.5 font-mono text-[9px] font-bold text-purple-200">
                        {dueCount} due
                      </span>
                    )}
                    {isCustom && (
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
                            Delete
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
                          aria-label={`Delete ${course.name}`}
                          className="rounded-lg p-1.5 text-slate-500 transition hover:bg-rose-500/15 hover:text-rose-300"
                        >
                          <Trash2 className="h-3.5 w-3.5" />
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
          <div className="flex flex-wrap gap-1.5">
            {selectedCourse.lines.map((line) => {
              const active = selectedLine?.id === line.id;
              const unlocked = isLineUnlocked(selectedCourse, line);
              return (
                <button
                  key={line.id}
                  type="button"
                  onClick={() => setSelectedLineId(line.id)}
                  className={`inline-flex items-center gap-1.5 rounded-xl border px-2.5 py-1.5 text-[11px] font-bold transition ${
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

          {selectedLine && (
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
