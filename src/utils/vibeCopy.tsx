import React, { createContext, useContext } from 'react';
import type { MoveClassification } from '../types/chess';

export type VibeMode = 'cosmic' | 'classic';

export interface VibeCopy {
  mode: VibeMode;
  appSubtitle: string;
  brilliantLabel: string;
  blunderLabel: string;
  inaccuracyLabel: string;
  mistakeLabel: string;
  greatLabel: string;
  openingDeviation: string;
  advantageConversion: string;
  advantageConversionShort: string;
  woodpeckerRest: string;
  tiltGuardWarning: string;
  recallProbability: (pct: number) => string;
  gravityCheckTitle: string;
  gravityCheckCleared: string;
  vaultTitle: string;
  vaultSubtitle: string;
  mothershipBadge: string;
  radarPingLabel: string;
}

const COSMIC_COPY: VibeCopy = {
  mode: 'cosmic',
  appSubtitle: 'Cosmic Stockfish probe & opening coach',
  brilliantLabel: 'Galaxy-Brain Signal',
  blunderLabel: 'Hull Breach',
  inaccuracyLabel: 'Minor Orbit Drift',
  mistakeLabel: 'Course Slip',
  greatLabel: 'Precision Lock',
  openingDeviation: 'Uncharted Sector',
  advantageConversion: 'Tractor Beam: Lock in the Win',
  advantageConversionShort: 'Tractor Beam',
  woodpeckerRest: 'Neural Syncing (Let patterns consolidate)',
  tiltGuardWarning: 'Shields at 15% — Cool down in orbit before queuing',
  recallProbability: (pct: number) => `Signal Strength: ${Math.round(pct)}%`,
  gravityCheckTitle: 'Gravity Check',
  gravityCheckCleared: 'Systems Nominal — Cleared for Launch',
  vaultTitle: 'Certified galaxy-brain archive',
  vaultSubtitle: 'Your brightest signals, clutch saves, punished traps, and clean sweeps.',
  mothershipBadge: 'Mothership Formation',
  radarPingLabel: 'Radar Ping',
};

const CLASSIC_COPY: VibeCopy = {
  mode: 'classic',
  appSubtitle: 'On-device Stockfish chess coach',
  brilliantLabel: 'Brilliant Move',
  blunderLabel: 'Blunder',
  inaccuracyLabel: 'Inaccuracy',
  mistakeLabel: 'Mistake',
  greatLabel: 'Great Move',
  openingDeviation: 'Opening Deviation',
  advantageConversion: 'Advantage Conversion',
  advantageConversionShort: 'Conversion',
  woodpeckerRest: '24–48h Consolidation Rest',
  tiltGuardWarning: 'Tilt Alert (2+ losses) — Take a short break before queuing',
  recallProbability: (pct: number) => `Recall Probability: ${Math.round(pct)}%`,
  gravityCheckTitle: '60s Pre-Game Warmup',
  gravityCheckCleared: 'Warmup Complete — Ready to Play',
  vaultTitle: 'Chess highlights archive',
  vaultSubtitle: 'Your brilliant moves, clutch saves, punished traps, and clean wins.',
  mothershipBadge: 'Target Formation',
  radarPingLabel: 'Threat Check',
};

export function getVibeCopy(vibe: VibeMode): VibeCopy {
  return vibe === 'classic' ? CLASSIC_COPY : COSMIC_COPY;
}

export function getClassificationLabel(classification: MoveClassification, vibe: VibeMode): string {
  const copy = getVibeCopy(vibe);
  switch (classification) {
    case 'brilliant': return copy.brilliantLabel;
    case 'blunder': return copy.blunderLabel;
    case 'inaccuracy': return copy.inaccuracyLabel;
    case 'mistake': return copy.mistakeLabel;
    case 'great': return copy.greatLabel;
    case 'best': return 'Best';
    case 'excellent': return 'Good';
    case 'book': return 'Book';
  }
}

interface VibeContextValue {
  vibe: VibeMode;
  copy: VibeCopy;
  setVibe: (next: VibeMode) => void;
}

const VibeContext = createContext<VibeContextValue>({
  vibe: 'cosmic',
  copy: COSMIC_COPY,
  setVibe: () => undefined,
});

export const VibeProvider: React.FC<{
  vibe: VibeMode;
  setVibe: (next: VibeMode) => void;
  children: React.ReactNode;
}> = ({ vibe, setVibe, children }) => {
  const copy = getVibeCopy(vibe);
  return <VibeContext.Provider value={{ vibe, copy, setVibe }}>{children}</VibeContext.Provider>;
};

export function useVibe(): VibeContextValue {
  return useContext(VibeContext);
}
