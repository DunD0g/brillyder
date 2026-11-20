export const PASS1_TWO_PASS_WEIGHT = 0.72;
export const PASS2_TWO_PASS_WEIGHT = 1 - PASS1_TWO_PASS_WEIGHT;

/**
 * Computes a monotonic 0..1 progress fraction within a single game analysis,
 * weighting Pass 1 (fast scan) and Pass 2 (turning-point deepening) so the
 * progress bar never snaps back to 0% when Pass 2 begins.
 */
export function computeGameProgressFraction(
  done: number,
  total: number,
  pass: 1 | 2,
  twoPass: boolean,
  prevFraction = 0
): number {
  const safePrev = clamp01(prevFraction);
  const ratio = total > 0 ? clamp01(done / total) : pass === 2 ? 1 : 0;

  let raw: number;
  if (!twoPass) {
    raw = ratio;
  } else if (pass === 1) {
    raw = ratio * PASS1_TWO_PASS_WEIGHT;
  } else {
    raw = PASS1_TWO_PASS_WEIGHT + ratio * PASS2_TWO_PASS_WEIGHT;
  }

  return Math.max(safePrev, clamp01(raw));
}

/**
 * Computes an integer 0..100 monotonic percentage for a single-game review bar.
 */
export function computeSingleGamePercent(
  gameFraction: number,
  prevPercent = 0,
  active = true
): number {
  const clamped = clamp01(gameFraction);
  if (clamped >= 1) return 100;
  const raw = Math.round(clamped * 100);
  const floored = active ? Math.max(2, raw) : raw;
  return Math.min(99, Math.max(clampPercent(prevPercent), floored));
}

/**
 * Computes an integer 0..100 monotonic percentage across a multi-game batch
 * (e.g., Batch Analyze or Opponent Scout), smoothly advancing on every ply.
 */
export function computeBatchProgressPercent(
  completedGames: number,
  totalGames: number,
  currentGameFraction: number,
  prevPercent = 0,
  active = true
): number {
  if (totalGames <= 0) return 0;
  const safeCompleted = Math.min(totalGames, Math.max(0, completedGames));
  if (safeCompleted >= totalGames) return 100;

  const safeFrac = clamp01(currentGameFraction);
  const overallFraction = clamp01((safeCompleted + safeFrac) / totalGames);
  const raw = Math.round(overallFraction * 100);
  const floored = active ? Math.max(2, raw) : raw;
  return Math.min(99, Math.max(clampPercent(prevPercent), floored));
}

function clamp01(v: number): number {
  if (!Number.isFinite(v)) return 0;
  return Math.min(1, Math.max(0, v));
}

function clampPercent(v: number): number {
  if (!Number.isFinite(v)) return 0;
  return Math.min(100, Math.max(0, Math.round(v)));
}
