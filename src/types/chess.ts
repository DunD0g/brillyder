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
  source: 'lichess' | 'pgn' | 'sample';
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
  bestMoveUci: string;
  bestMoveSan: string;
  bestPvSan: string[];
  threatMoveUci?: string;
  threatMoveSan?: string;
  evalBefore: EngineScore;
  evalAfter: EngineScore;
  secondBestGapWin: number;
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

export interface SkillProfile {
  openings: number;
  tactics: number;
  endgames: number;
  conversion: number;
  resilience: number;
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

export interface MultiGameInsights {
  gamesCount: number;
  avgAccuracy: number;
  avgEstimatedElo: number;
  record: { wins: number; draws: number; losses: number };
  skillProfile: SkillProfile;
  openings: OpeningStat[];
  phaseStats: PhaseBlunderStats[];
  recommendation: string;
}
