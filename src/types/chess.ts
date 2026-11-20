export type PlayerColor = 'w' | 'b';

export type MoveClassification =
  | 'brilliant'
  | 'great'
  | 'best'
  | 'excellent'
  | 'inaccuracy'
  | 'mistake'
  | 'blunder'
  | 'book';

export interface ClassificationMeta {
  key: MoveClassification;
  label: string;
  symbol: string;
  color: string;
  bgClass: string;
  textClass: string;
  borderClass: string;
  badgeBg: string;
}

export const CLASSIFICATION_META: Record<MoveClassification, ClassificationMeta> = {
  brilliant: { key: 'brilliant', label: 'Brilliant', symbol: '!!', color: '#06b6d4', bgClass: 'bg-cyan-500/15', textClass: 'text-cyan-300', borderClass: 'border-cyan-500/40', badgeBg: '#06b6d4' },
  great: { key: 'great', label: 'Great Move', symbol: '!', color: '#3b82f6', bgClass: 'bg-blue-500/15', textClass: 'text-blue-300', borderClass: 'border-blue-500/40', badgeBg: '#3b82f6' },
  best: { key: 'best', label: 'Best', symbol: '★', color: '#22c55e', bgClass: 'bg-emerald-500/15', textClass: 'text-emerald-300', borderClass: 'border-emerald-500/40', badgeBg: '#22c55e' },
  excellent: { key: 'excellent', label: 'Good', symbol: '✓', color: '#84cc16', bgClass: 'bg-lime-500/15', textClass: 'text-lime-300', borderClass: 'border-lime-500/40', badgeBg: '#84cc16' },
  inaccuracy: { key: 'inaccuracy', label: 'Inaccuracy', symbol: '?!', color: '#eab308', bgClass: 'bg-yellow-500/15', textClass: 'text-yellow-300', borderClass: 'border-yellow-500/40', badgeBg: '#eab308' },
  mistake: { key: 'mistake', label: 'Mistake', symbol: '?', color: '#f97316', bgClass: 'bg-orange-500/15', textClass: 'text-orange-300', borderClass: 'border-orange-500/40', badgeBg: '#f97316' },
  blunder: { key: 'blunder', label: 'Blunder', symbol: '??', color: '#ef4444', bgClass: 'bg-red-500/15', textClass: 'text-red-300', borderClass: 'border-red-500/40', badgeBg: '#ef4444' },
  book: { key: 'book', label: 'Book', symbol: '📖', color: '#a16207', bgClass: 'bg-amber-700/20', textClass: 'text-amber-300', borderClass: 'border-amber-600/40', badgeBg: '#92400e' },
};

export interface LichessPlayerInfo {
  name: string;
  rating?: number;
  ratingDiff?: number;
}

export interface LichessGameRecord {
  id: string;
  source: 'lichess' | 'chesscom' | 'pgn' | 'sample';
  rated: boolean;
  variant: string;
  speed: string;
  perf: string;
  createdAt: number;
  status: string;
  winner?: 'white' | 'black';
  resultString: '1-0' | '0-1' | '1/2-1/2' | '*';
  timeControlLabel: string;
  pgn: string;
  openingName: string;
  openingEco: string;
  openingPly?: number;
  white: LichessPlayerInfo;
  black: LichessPlayerInfo;
  userColor?: PlayerColor;
  url?: string;
}

export interface EngineScore {
  cpWhite: number;
  mateWhite: number | null;
  isCheckmate?: boolean;
  winPercentWhite: number;
  display: string;
}

export interface MultiPvLine {
  multipv: number;
  bestMoveUci: string;
  pv: string[];
  score: EngineScore;
}

export interface EngineEval {
  fen: string;
  depth: number;
  bestMoveUci: string;
  pv: string[];
  score: EngineScore;
  lines: MultiPvLine[];
}

export interface CoachingExplanation {
  headline: string;
  detail: string;
  tacticalTag: string;
}

export interface AnalyzedPly {
  ply: number;
  moveNumber: number;
  color: PlayerColor;
  san: string;
  uci: string;
  from: string;
  to: string;
  promotion?: string;
  captured?: string;
  beforeFen: string;
  afterFen: string;
  clockText?: string;
  clockSeconds?: number;
  timeSpentSeconds?: number;
  clockTag?: 'impulse' | 'time-trouble';
  bestMoveUci: string;
  bestMoveSan: string;
  bestPvSan: string[];
  topLines?: Array<{ san: string; evalDisplay: string; pvSan: string[] }>;
  threatMoveUci?: string;
  threatMoveSan?: string;
  evalBefore: EngineScore;
  evalAfter: EngineScore;
  secondBestGapWin: number;
  secondBestGapPawns?: number;
  isCriticalMoment?: boolean;
  isClutchSave?: boolean;
  deepened?: boolean;
  winLoss: number;
  accuracy: number;
  classification: MoveClassification;
  phase: 'opening' | 'middlegame' | 'endgame';
  coaching: CoachingExplanation;
}

export interface PlayerAnalysisSummary {
  accuracy: number;
  estimatedElo: number;
  counts: Record<MoveClassification, number>;
  avgWinLoss: number;
}

export interface AnalyzedGame {
  id: string;
  analyzedAt: number;
  depth: number;
  classificationVersion?: number;
  game: LichessGameRecord;
  initialEval: EngineScore;
  plies: AnalyzedPly[];
  whiteSummary: PlayerAnalysisSummary;
  blackSummary: PlayerAnalysisSummary;
  openingLineDetected?: string;
}

export type AnalysisDepthPreset = 14 | 18;

export interface PlayBotConfig {
  active: boolean;
  elo: number;
  userColor: PlayerColor;
  startFen: string;
}

export interface BotSession extends PlayBotConfig {
  fen: string;
  lastMove?: [string, string];
  thinking: boolean;
  historyFens: string[];
  statusText: string;
}

export interface RetrySession {
  active: boolean;
  fen: string;
  status: 'prompt' | 'evaluating' | 'solved' | 'try_again' | 'revealed';
  feedback: string;
}

export interface SkillProfile {
  openings: number;
  tactics: number;
  endgames: number;
  conversion: number;
  resilience: number;
  timeManagement: number;
}

export interface OpeningStat {
  name: string;
  eco: string;
  games: number;
  wins: number;
  draws: number;
  losses: number;
  winRate: number;
  avgAccuracy: number;
}

export interface PhaseBlunderStats {
  phase: 'Opening' | 'Middlegame' | 'Endgame';
  moves: number;
  inaccuracies: number;
  mistakes: number;
  blunders: number;
  blunderRatePer10Moves: number;
  accuracy: number;
}

export interface ClockBucketStats {
  label: string;
  clockLimit: number;
  moves: number;
  mistakes: number;
  blunders: number;
  errorsPer10Moves: number;
  accuracy: number;
}

export interface AccuracyTrendPoint {
  date: number;
  accuracy: number;
  result: 'W' | 'D' | 'L';
  opening: string;
  opponent: string;
}

export interface GameHighlight {
  gameId: string;
  opponent: string;
  opponentRating: number;
  userRating: number;
  userColor: PlayerColor;
  result: 'W' | 'D' | 'L';
  accuracy: number;
  opening: string;
  playedAt: number;
  brilliants: number;
  blunders: number;
  score: number;
  highlightPly: number;
  reason: string;
}

export interface ColourSplit {
  games: number;
  wins: number;
  draws: number;
  losses: number;
  winRate: number;
  accuracy: number;
}

export type EndgameCategory = 'Rook' | 'Pawn' | 'Minor Piece' | 'Queen' | 'Rook+Minor';

export interface ClockLeakSummary {
  impulseBlunders: number;
  timeTroubleBlunders: number;
  avgTimeSpentSec: number;
  impulsePerGame: number;
}

export interface TiltStreakBucket {
  label: string;
  priorLosses: number;
  games: number;
  wins: number;
  draws: number;
  losses: number;
  winRate: number;
}

export interface TiltGuardStats {
  buckets: TiltStreakBucket[];
  activeWarning: boolean;
  consecutiveLosses: number;
}

export interface CheckpointMetrics {
  games: number;
  avgEvalMove10: number | null;
  impulseBlundersPerGame: number;
  blownLeadPct: number | null;
}

export interface TwentyGameCheckpoints {
  windowSize: number;
  recent: CheckpointMetrics;
  previous: CheckpointMetrics;
}

export interface MotifWeaknessStat {
  motif: string;
  count: number;
  avgWinLoss: number;
}

export interface EndgameCategoryStat {
  category: EndgameCategory;
  moves: number;
  accuracy: number;
  blunders: number;
}

export interface MultiGameInsights {
  gamesCount: number;
  avgAccuracy: number;
  avgEstimatedElo: number;
  record: { wins: number; draws: number; losses: number };
  skillProfile: SkillProfile;
  openings: OpeningStat[];
  phaseStats: PhaseBlunderStats[];
  timeTrouble: ClockBucketStats[];
  clockLeaks: ClockLeakSummary;
  tiltGuard: TiltGuardStats;
  checkpoints: TwentyGameCheckpoints | null;
  missedMotifs: MotifWeaknessStat[];
  endgameCategories: EndgameCategoryStat[];
  trend: AccuracyTrendPoint[];
  ratingBand: string;
  brilliantCount: number;
  recommendation: string;
  bestGames: GameHighlight[];
  worstGame: GameHighlight | null;
  bestAccuracy: number;
  avgOpponentRating: number;
  giantSlayer: { wins: number; games: number; best: GameHighlight | null };
  comebacks: number;
  blownWins: number;
  blunderFreeGames: number;
  scoreByColour: { white: ColourSplit; black: ColourSplit };
  currentStreak: { kind: 'W' | 'D' | 'L' | 'none'; count: number };
  openingBest: OpeningStat | null;
  openingWorst: OpeningStat | null;
}

export type GamePlatform = 'lichess' | 'chesscom';

export interface ScoutState {
  username: string;
  platform: GamePlatform;
  status: 'loading' | 'ready' | 'error';
  games: AnalyzedGame[];
  progress: { done: number; total: number; percent?: number; plyDone?: number; plyTotal?: number } | null;
  error: string | null;
}

export type BoardThemeId = 'slate' | 'emerald' | 'walnut' | 'neon';

export type VaultCategory = 'brilliant' | 'clutch' | 'traps' | 'clean';

export interface BrillyVaultEntry {
  id: string;
  category: VaultCategory;
  gameId: string;
  ply: number;
  moveNumber: number;
  san: string;
  uci: string;
  from: string;
  to: string;
  beforeFen: string;
  afterFen: string;
  color: PlayerColor;
  playerName: string;
  opponentName: string;
  isUserMove: boolean;
  openingName: string;
  openingEco: string;
  playedAt: number;
  analyzedAt: number;
  captured?: string;
  badgeText?: string;
  reason?: string;
}

export interface BrillyVaultStats {
  total: number;
  totalHighlights: number;
  userMoves: number;
  opponentMoves: number;
  clutchSaves: number;
  trapsPunished: number;
  cleanSweeps: number;
  thisMonth: number;
  topOpenings: Array<{ name: string; count: number }>;
  topMonths: Array<{ key: string; label: string; count: number }>;
  topUserOpening: { name: string; count: number } | null;
}

export type MistakeClassification = 'inaccuracy' | 'mistake' | 'blunder';

export interface MistakePuzzle {
  id: string;
  gameId: string;
  ply: number;
  moveNumber: number;
  color: PlayerColor;
  beforeFen: string;
  afterFen: string;
  san: string;
  bestMoveSan: string;
  bestMoveUci: string;
  threatMoveUci?: string;
  classification: MistakeClassification;
  phase: 'opening' | 'middlegame' | 'endgame';
  tacticalTag: string;
  headline: string;
  openingName: string;
  openingEco: string;
  playerName: string;
  opponentName: string;
  playedAt: number;
  evalBefore: EngineScore;
  evalAfter: EngineScore;
  winLoss: number;
}

export interface MistakeProgressRecord {
  solved: boolean;
  attempts: number;
  lastAt: number;
}

export interface DrillStreak {
  current: number;
  best: number;
  lastSolvedAt: number;
}
