export type Side = 'white' | 'black';

export interface BoardArrow {
  from: string;
  to: string;
  color: 'plan' | 'best' | 'threat' | 'outpost';
}

export interface SquareHighlight {
  square: string;
  color: 'plan' | 'threat' | 'outpost';
}

export interface WrongMoveTrap {
  playedSan: string;
  punishmentLine: string[];
  reason: string;
  arrows?: BoardArrow[];
}

export interface MoveAnnotation {
  ply: number;
  plan: string;
  cosmicCue?: string;
  arrows?: BoardArrow[];
  highlights?: SquareHighlight[];
  wrongMoveTraps?: WrongMoveTrap[];
  isCritical?: boolean;
}

export interface OpeningLine {
  id: string;
  title: string;
  subtitle: string;
  eco: string;
  frequencyNote: string;
  moves: string[];
  annotations: MoveAnnotation[];
}

export interface OpeningCourse {
  id: string;
  name: string;
  codename: string;
  side: Side;
  difficulty: 'Beginner' | 'Intermediate' | 'Club';
  tagline: string;
  source?: 'starter' | 'pgn' | 'lichess-study';
  mothershipSetup: {
    previewMoves: string[];
    arrows: BoardArrow[];
    highlights: SquareHighlight[];
    corePlans: string[];
    goldenRules: string[];
  };
  lines: OpeningLine[];
}

export interface FsrsOpeningCard {
  cardId: string;
  courseId: string;
  lineId: string;
  side: Side;
  fen: string;
  ply: number;
  moveSequence: string[];
  expectedSan: string;
  expectedUci: string;
  fsrsState: Record<string, unknown>;
  dueAt: number;
  attempts: number;
  firstTryHits: number;
  avgResponseMs: number;
  source: 'course' | 'game-deviation';
  unlocked: boolean;
}

export interface WoodpeckerCycleRecord {
  id: string;
  createdAt: number;
  batchSize: 30 | 50 | 100;
  puzzleIds: string[];
  currentCycle: number;
  activeIndex: number;
  activeStartedAt: number | null;
  activeAttemptedIds: Record<string, { firstTry: boolean; wrongMoves: number; hintsUsed: number; solved: boolean }>;
  completedCycles: Array<{
    cycleNumber: number;
    completedAt: number;
    elapsedSeconds: number;
    accuracyPct: number;
    firstTryPct: number;
    solvedCount: number;
    totalCount: number;
  }>;
  cooldownUntil: number | null;
}

export interface TrainingLogRecord {
  id: string;
  kind: 'mistake-progress' | 'drill-streak' | 'daily-session' | 'gravity-check' | 'conversion' | 'meta';
  updatedAt: number;
  data: Record<string, unknown>;
}
