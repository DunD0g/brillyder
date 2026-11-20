# BrillyDer v2.0 — "Warp-Speed Learning", Cosmic UI & Data Schema

Use this document alongside `docs/BRILLYDER_V2_BLUEPRINT.md` and `src/data/starterCourses.json`.

---

## 1. Visual Identity & Subtle Witty Alien Theme ("Cosmic Minimalist")
Sleek dark glassmorphism—Linear/Raycast meets a cheeky space-probe AI. Never cartoonish; the chessboard stays crisp and high-contrast.

### 1.1 Color & Surface Tokens
```css
:root {
  --bg-void: #070B14;
  --bg-hull: #0F172A;
  --bg-cockpit: #162036;
  --border-glass: rgba(148, 163, 184, 0.14);
  --border-glow: rgba(45, 212, 191, 0.35);

  --accent-brilly: #2DD4BF;    /* Brilliant !!, mastered, active state */
  --accent-warp: #A855F7;      /* Streaks, FSRS warp, outposts */
  --accent-blunder: #FB7185;   /* Hull breach ??, threats, mistakes */
  --accent-alert: #FBBF24;     /* Inaccuracies, cooldowns, hints */
  --accent-clean: #34D399;     /* Best move, clean sweep */

  --arrow-plan: rgba(45, 212, 191, 0.80);
  --arrow-best: rgba(52, 211, 153, 0.85);
  --arrow-threat: rgba(251, 113, 133, 0.85);
  --arrow-outpost: rgba(168, 85, 247, 0.78);
}
```

### 1.2 Cosmic Copy Dictionary (with `Cosmic | Classic` Settings Toggle)
- `!!` Brilliant Move -> "Galaxy-Brain Signal"
- `??` Blunder -> "Hull Breach"
- `?!` Inaccuracy -> "Minor Orbit Drift"
- Opening Deviation -> "Uncharted Sector"
- Advantage Conversion -> "Tractor Beam: Lock in the Win"
- Woodpecker 24h Rest -> "Neural Syncing (Let patterns consolidate)"
- Tilt Guard (2+ losses) -> "Shields at 15% — Cool down in orbit before queuing"
- FSRS Recall Probability -> "Signal Strength: 93%"
- 60-Second Pre-Game Warmup -> "Gravity Check"

### 1.3 Micro-Interactions & Audio
- Glowing cyan-to-violet **Tractor Beam** progress bar across the 15-min Daily Session.
- Subtle radar sweep ring during Stockfish / Opponent Scout analysis.
- Toggleable Web Audio API synth cues (crystalline chord on `!!`/streak, low hull-thud on `??`, soft sonar ping on correct FSRS move).

---

## 2. Five "Warp-Speed" Learning Mechanics
1. **Tabiya-First "Mothership Formation" Lessons:** Display completed target shape + SVG arrows/highlights + 3 middlegame plans BEFORE drilling move 1.
2. **Contrastive Trap Feedback:** On wrong drill move, match `wrongMoveTraps[playedSan]`, animate the opponent's 1–2 move punishment with coral arrows, show the 1-sentence reason, and require immediate retry.
3. **"Radar Ping" Anti-Tunnel-Vision Mode:** Optional 2-second pre-step in Blunder Rewind & Woodpecker: *"Tap the piece/square the opponent just threatened"* to wire Checks-Captures-Threats (CCT).
4. **60-Second Pre-Game "Gravity Check":** 3 timed 8-second hanging-piece/tactic flashes + 2 due FSRS opening moves -> *"Systems Nominal — Cleared for Launch"*.
5. **Exact Endgame + Human-Probability Feedback:** Lichess Tablebase (`tablebase.lichess.ovh`) for <=7-piece WDL flips, plus Lichess Explorer / optional client-side Maia ONNX (`public/models/maia-*.onnx` via `onnxruntime-web`) for human-like sparring and move-popularity stats.

---

## 3. TypeScript Data Schema (`src/types/openings.ts`)
```ts
export type Side = 'white' | 'black';

export interface BoardArrow {
  from: string;
  to: string;
  color: 'plan' | 'best' | 'threat' | 'outpost';
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
  highlights?: { square: string; color: 'plan' | 'threat' | 'outpost' }[];
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
  mothershipSetup: {
    previewMoves: string[];
    arrows: BoardArrow[];
    highlights: { square: string; color: 'plan' | 'threat' | 'outpost' }[];
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
  expectedSan: string;
  expectedUci: string;
  fsrsState: Record<string, unknown>;
  attempts: number;
  firstTryHits: number;
  avgResponseMs: number;
  source: 'course' | 'game-deviation';
}
```
