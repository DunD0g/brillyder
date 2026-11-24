# BrillyDer v2.0 — Sprint Tracker

## Phase 1 — Cosmic Shell, Navigation, IndexedDB & FSRS Core
**Status:** Completed & Verified

### Built
- **Cosmic Minimalist Theme & Audio Cues:**
  - Applied exact CSS custom properties (`--bg-void`, `--bg-hull`, `--bg-cockpit`, `--border-glass`, `--border-glow`, `--accent-brilly`, `--accent-warp`, `--accent-blunder`, `--accent-alert`, `--accent-clean`, `--arrow-plan`, `--arrow-best`, `--arrow-threat`, `--arrow-outpost`) in `src/index.css` and `tailwind.config.js`, plus `.tractor-beam-track/.tractor-beam-fill` and `.radar-sweep` utilities.
  - Added crystalline chord (`playBrilliantChord`), low hull-thud (`playHullThud`), and soft sonar ping (`playSonarPing`) Web Audio cues in `src/utils/sound.ts`.
- **`Vibe: Cosmic | Classic` Copy System & Settings:**
  - Created `src/utils/vibeCopy.tsx` with the complete Cosmic/Classic dictionary and `VibeProvider`/`useVibe` context, wired into `App.tsx`, `ClassificationBadge.tsx`, `AlienCelebration.tsx`, `BrillyVaultView.tsx`, and `OpeningsView.tsx`.
  - Built `src/components/SettingsMenu.tsx` with Vibe toggle, Board & Pieces themes, Alien Celebrations toggle, Lichess Explorer target rating/speed pool, and full IndexedDB JSON Export/Import backup (`merge` / `replace`).
- **Consolidated 5-Tab Nav & Brilly Vault Modal/Drawer:**
  - Consolidated desktop and mobile bottom nav to `Games | Analyze | Openings | Train | Insights` in `src/App.tsx`.
  - Moved `Brilly Vault` into responsive `src/components/BrillyVaultModal.tsx` triggered by the top-right Diamond counter pill (and `AnalysisView` Vault CTA).
  - Created initial `src/components/OpeningsView.tsx` shell hydrating all 4 starter courses from `src/data/starterCourses.json`.
- **IndexedDB (`idb`) Persistence Migration:**
  - Upgraded `brillyder_db` from v1 -> v2 via `idb` in `src/storage/brillyDb.ts` (preserving `analyzed_games`, adding `prefs`, `repertoires`, `fsrs_cards`, `woodpecker_cycles`, `training_logs`, one-time idempotent migration from `localStorage`, and full validated JSON Export/Import).
  - Delegated `src/storage/gameDb.ts` cleanly to `brillyDb.ts` with zero breakage to existing callers.
- **FSRS-6 Opening Scheduler (`ts-fsrs` v6) & Validation Suite:**
  - Installed `idb@^8.0.4`, `ts-fsrs@^6.0.0` (Node `v24.12.0`), and `vitest@^2`; updated `.github/workflows/deploy.yml` to Node `24` with `npm test`.
  - Created `src/types/openings.ts` and `src/lib/fsrsOpening.ts` with response-time auto-grading (`Again / Hard / Good / Easy`), course hydration, recall probability (`Signal Strength: XX%`), due checks, and due-now deviation boosting.
  - Added `src/data/starterCourses.test.ts`, `src/lib/fsrsOpening.test.ts`, and `src/storage/backupSchema.test.ts`.

### Verified
- `npm test`: **3 test files, 22 tests passed** — 100% legal SAN verified via `chess.js` across all 4 courses (`previewMoves`, every line's `moves`, every `annotation` ply/side, every `wrongMoveTraps.playedSan` + `punishmentLine`), FSRS auto-grading & JSON round-trip, and backup schema validation.
- `npm run build`: `prepare-assets.mjs` (`stockfish-19-lite-single.js` + `.wasm`) + `tsc --noEmit` + `vite build` passed cleanly.

### Remaining / Next Up
- **Phase 2:** Extend `ChessgroundBoard` with custom SVG arrows & square highlights; build full `Openings` studio (Mothership Formation card, Guided Walkthrough, FSRS Active Recall Drills with animated `wrongMoveTraps` punishments, PGN/Lichess Study importer); integrate rating/speed-filtered Lichess Opening Explorer for Real-World Coverage % & 1-click Patch Gap; wire Automatic Game Deviation Detection ("Leak Patcher") into `Analyze`.

---

## Phase 2 — Full Openings Tab, Courses, FSRS Drills & Leak Patcher
**Status:** Completed & Verified

### Built
- **Board Visual Overlays (`ChessgroundBoard` Extension):**
  - Extended `src/components/ChessgroundBoard.tsx` with custom SVG `customArrows` (`plan`, `best`, `threat`, `outpost` mapped to Cosmic CSS tokens), translucent glowing `squareHighlights`, and `onSquareClick` coordinate picking (ready for Phase 3 Radar Ping).
- **Full `Openings` Tab Studio (`src/components/OpeningsView.tsx` + `src/components/openings/*`):**
  - Hydrates all 4 courses from `src/data/starterCourses.json` split into White & Black repertoires, merged seamlessly with user-imported and patched courses in IndexedDB `repertoires`.
  - **Mothership Formation (`MothershipCard.tsx`):** Target setup board (`previewMoves`) with SVG arrows/highlights, step-through controls, 3 middlegame plans, and golden rules.
  - **Guided Walkthrough (`GuidedWalkthrough.tsx`):** Interactive move-by-move walkthrough with plan notes, Vibe-aware `cosmicCue`, animated `wrongMoveTraps` Trap Spotlight, and 1-click **Unlock Drill** into FSRS.
  - **FSRS Active Recall Drill (`OpeningDrillView.tsx`):** Supports Due Reviews (FSRS with live Signal Strength / Recall Probability), Weakest Lines First, and Opening Sparring (Lichess rating-band weighted opponent replies + middlegame play-out against rating-capped Stockfish), with response-time auto-grading (`Again / Hard / Good / Easy`), sonar ping cue, and animated `wrongMoveTraps` punishments with coral arrows + immediate retry.
  - **PGN / Lichess Study Importer (`repertoireImporter.ts` & `ImportCourseModal.tsx`):** Parses single/multi-game PGN including nested RAV variations and comments, plus public Lichess Study URLs, validated 100% by `chess.js`.
- **Rating/Speed-Filtered Lichess Explorer, Real-World Coverage & 1-Click Patch Gap:**
  - Upgraded `src/services/openingExplorer.ts` to filter `explorer.lichess.ovh/lichess` by user rating bracket & speeds (with graceful offline ECO book fallback).
  - Built `src/services/repertoireCoverage.ts` & `CoverageGapPanel.tsx` calculating Expected Coverage % (opponent replies `>= 5%` down to `>= 2%` line probability), ranking uncovered gaps, showing Stockfish MultiPV=3 candidates + Lichess human win rates, and providing 1-click **Patch Gap** persistence into IndexedDB + FSRS.
- **Automatic Game-to-Repertoire Deviation Detector ("Leak Patcher") & Multi-Game Opening Report Card:**
  - Built `src/services/deviationDetector.ts` comparing moves 1–12 against active repertoires (transposition-aware via normalized FEN) to flag User Deviations (1-click **Boost to Today's FSRS Queue**) and Opponent Novelties (1-click **Patch Gap in Repertoire**) inside `OpeningReportCard.tsx` in `Analyze`.
  - Added `MultiGameOpeningReport.tsx` grouping analyzed games by ECO/Opening with Games Played, W/D/L %, Avg Eval at Move 10, and clickable Most Costly Opening Position.

### Verified
- `npm test`: **6 test files, 29 tests passed** (added `repertoireImporter.test.ts`, `repertoireCoverage.test.ts`, `deviationDetector.test.ts` alongside all starter-course SAN, FSRS, and backup tests).
- `npm run build`: `prepare-assets.mjs` + `tsc --noEmit` + `vite build` passed cleanly.

### Remaining / Next Up
- **Phase 3:** 15-min 4-stage Daily Coach Loop with Tractor Beam progress bar, Radar Ping threat-tap pre-step, 60-second Gravity Check warmup modal, Frozen Woodpecker Cycles (30/50/100, Cycles 1–7, First-Try Rate, 24–48h cooldown badge, Speed-Up chart), and Tractor Beam Advantage Conversion arena.

---

## Phase 3 — 15-Min Daily Coach Loop, True Woodpecker Cycles & Advantage Conversion
**Status:** Completed & Verified

### Built
- **15-Minute 4-Stage Daily Coach Loop (`src/services/dailyCoach.ts`, `src/components/train/DailyCoachSession.tsx`):**
  - Configurable `10 / 15 / 25 min` session generator with glowing cyan-to-violet **Tractor Beam** progress bar across 4 stages:
    1. **Due Opening FSRS** (prioritizing boosted `game-deviation` cards)
    2. **Blunder Rewind ("Worst First")** from last 14 days with toggleable 2-second **"Radar Ping"** threat-tap pre-step (`findRadarPingTargets` + `ChessgroundBoard.onSquareClick`)
    3. **Frozen Woodpecker Cycle** (drawing from active frozen cycle / solvable mistakes)
    4. **Targeted Weakness Drill** (rotating Advantage Conversion, Weakest Endgame, and Missed Motif Drill)
  - Logs daily session completions into IndexedDB `training_logs`.
- **60-Second "Gravity Check" Pre-Game Warmup Modal (`src/components/train/GravityCheckModal.tsx`):**
  - 3 timed 8-second hanging-piece/tactic flashes (from user deck + `chess.js`-verified built-in fallback flashes) + 2 due FSRS opening moves (with starter course fallback), ending with *"Systems Nominal — Cleared for Launch"* (Cosmic) / *"Warmup Complete — Ready to Play"* (Classic).
- **True Frozen Woodpecker Cycles (`src/services/woodpeckerCycles.ts`, `src/components/train/WoodpeckerCycleView.tsx`):**
  - Freezes fixed 30 / 50 / 100-puzzle batches filtered to solvable difficulty (eval swing `>= 1.5` pawns, excluding obscure borderline quiet moves).
  - Tracks Cycles `#1–7`, live elapsed stopwatch, Accuracy %, First-Try Rate (`0` wrong moves & `0` hints), toggleable Radar Ping pre-step, overridable 24–48h consolidation cooldown badge (Vibe-aware), and responsive SVG **Cycle Speed-Up & First-Try Chart**, persisted in IndexedDB `woodpecker_cycles`.
- **"Tractor Beam" Advantage Conversion (`src/services/advantageConversion.ts`, `src/components/train/AdvantageConversionView.tsx`):**
  - Extracts positions from user games where eval hit `>= +2.5` (or `<= -2.5` as Black) and later slipped; replays against a rating-capped Stockfish bot with live eval checks (`>= +8.0` or checkmate locks the win; `< +1.5` warns and enables 1-click turn rewind), logging conversions to IndexedDB `training_logs`.
- **Unified Train Hub (`MistakeTrainerView.tsx` & `App.tsx`):**
  - Reorganized `Train` into `15m Daily Coach | Woodpecker | Conversion | Mistake Deck` (+ Puzzle Rush & Motif Filter support + 60s Gravity Check launcher).

### Verified
- `npm test`: **9 test files, 36 tests passed** (added `woodpeckerCycles.test.ts`, `advantageConversion.test.ts`, `dailyCoach.test.ts` including `chess.js` legality checks on all fallback Gravity Check flashes).
- `npm run build`: `prepare-assets.mjs` + `tsc --noEmit` + `vite build` passed cleanly.

### Remaining / Next Up
- **Phase 4:** MultiPV plain-English coach & full Tactical Motif tagging + Critical/Clutch Save distinction; two-pass Stockfish optimization (`D12–D14` fast pass -> `D18` MultiPV=3 turning points `>= 1.0` eval swing); `[%clk]` Impulse vs Time-Trouble Blunders + Tilt Guard + 20-Game Checkpoints + 1-click "Train This" CTAs on every Insights card; expanded 4-tab `Brilly Vault`; Lichess 7-piece Syzygy Tablebase & Endgame Weakness Tracker; optional `onnxruntime-web` Maia Web Worker with seamless Stockfish fallback.

---

## Phase 4 — Plain-English Coach, Clock/Tilt Guard, Tablebase & Optional Maia
**Status:** Completed & Verified

### Built
- **MultiPV Plain-English Coach & Tactical Motif Classifier (`src/chess/tacticalMotifs.ts`, `src/chess/moveCoach.ts`, `src/chess/classification.ts`, `src/components/CoachCard.tsx`):**
  - Full board-state + Stockfish MultiPV detector tagging `Hanging Piece`, `Fork`, `Pin/Skewer`, `Back-Rank Mate`, `Discovered Attack`, `Deflection`, `Mate in 1–3`, and `Only Move Save`, with concise human explanations and MultiPV Top-3 display in `CoachCard`.
  - Forced vs. Critical Move distinction (`secondBestGapPawns >= 2.0` -> Critical Moment badge; finding it under pressure -> `Clutch Save` badge).
- **Two-Pass Stockfish Optimization (`src/services/analysisRunner.ts`, `src/components/AnalysisView.tsx`):**
  - Fast Pass (`D12–D14`, MultiPV=2) across every position, automatically deepening ONLY turning points (`>= 1.0` pawn eval swing or mate change) to `D18`, MultiPV=3, with live pass status + `.radar-sweep` animation.
- **Clock Leaks (`[%clk]`), Tilt Guard, 20-Game Checkpoints & Actionable Insights (`src/utils/chessMath.ts`, `src/services/insightsAggregator.ts`, `src/components/EvalGraph.tsx`, `src/components/TimeTroubleCard.tsx`, `src/components/InsightsView.tsx`):**
  - Parses `[TimeControl]` increments and `[%clk]` timestamps to compute per-move `timeSpentSeconds`, flagging **Impulse Blunders** (`<5s` spent with `>3m` left) vs **Time-Trouble Blunders** (`<60s` left), with a toggleable **Time Spent vs. Eval Swing** overlay in `EvalGraph`.
  - Added **Tilt Guard** (win-rate curve by consecutive prior losses `0L / 1L / 2L / 3L+` + Vibe-aware stop-loss alert banner when on 2+ loss streak), **20-Game Checkpoints** (Avg Eval at Move 10, Impulse Blunders/Game, Blown Lead %), **Patterns You Miss Most** (1-click Motif Drills), **Endgame Weakness Tracker** (`Rook`, `Pawn`, `Minor Piece`, `Queen`, `Rook+Minor`), and 1-click **"Train This"** CTAs across every `Insights` card.
- **Expanded 4-Tab Brilly Vault (`src/services/vault.ts`, `src/components/BrillyVaultView.tsx`):**
  - Upgraded the top-right Diamond Modal Vault with 4 tabs: `!! Brilliant`, `Clutch Saves`, `Traps Punished`, and `Clean Sweeps`.
- **Lichess 7-Piece Syzygy Tablebase (`src/services/tablebaseApi.ts`):**
  - Queries `https://tablebase.lichess.ovh/standard` for exact `<=7`-piece WDL/DTZ feedback and clickable best moves in `AnalysisView` and `AdvantageConversionView`.
- **Optional Client-Side Maia ONNX Bot (`src/engine/maia.worker.ts`, `src/engine/MaiaService.ts`, `src/components/SettingsMenu.tsx`):**
  - Opt-in Web Worker loader using `onnxruntime-web` that probes `public/models/maia-*.onnx` and runs local human-like policy inference for Play Bot, Opening Sparring, and Advantage Conversion, falling back cleanly to rating-capped Stockfish whenever absent or disabled.
- **PWA Cache Bump:** Bumped `public/sw.js` cache to `brillyder-v8`.

### Verified
- `npm test`: **11 test files, 44 tests passed** (added `tacticalMotifs.test.ts` and `phase4Insights.test.ts` alongside all Phase 1–3 tests).
- `npm run build`: `prepare-assets.mjs` + `tsc --noEmit` + `vite build` passed cleanly.

### Release
- All 4 phases of BrillyDer v2.0 are complete, verified, and deployed on GitHub Pages (`main`).

---

## v2.0.1 — Full Codebase Audit, Mobile UX & Pedagogy Hardening
**Status:** Completed & Verified

### Built
- **Pass 1 — Brilliant Engine, Classification, Tactical Motifs & Stockfish/Maia (`3bd158d`):**
  - Hardened `StockfishService.ts` (`EngineCancelledError`, clean `dispose()` queue unwind, `AbortSignal`, MultiPV aspiration bound safety, `Skill Level 20` restoration for `targetElo >= 1320`).
  - Upgraded `MaiaService.ts` with genuine 1858-move LC0 policy map, plane 109 (`rule50`), `worker.onerror` recovery, and parallel model probing.
  - Fixed `classification.ts` false-positive promotion sacrifices (`bxa8=Q Kxa8`), passive en-prise sacrifices, missed short mate penalties, stricter `isClutchSave`, safe RAV comment/header parsing in `loadPgnSafely`, bumped `CLASSIFICATION_VERSION = 3`, Move-1 book detection in `openingBook.ts`, legal SEE & pin-aware hanging piece detection in `tacticalMotifs.ts`, paired `(i, i+1)` Pass-2 deepening + custom-FEN starts in `analysisRunner.ts`, and decimal/multi-stage PGN clock parsing in `chessMath.ts`.
- **Pass 2 — Stats, Vault, Sync, Explorer/Tablebase, Daily Coach & IndexedDB (`0421264`):**
  - Fixed inverted Lichess Syzygy Tablebase move labels (`invertTablebaseMoveCategory`) and removed negative poison caching in `tablebaseApi.ts` & `openingExplorer.ts`.
  - Prioritized explicit `username` matching in `resolveUserColor`, excluded unfinished `'*'` games from W/D/L and insights, fixed DST-safe drill streaks, fixed Clean Sweep spotlight ply & deduplicated `vault.stats.totalHighlights`, and tightened Advantage Conversion extraction to `[+2.5, +7.5]` peaks before slips.
  - Fixed Gravity Check FSRS history preservation and implemented cross-stage deduplication in `dailyCoach.ts` (preserving the Frozen Woodpecker Cycle across days and honoring its 24–48h consolidation cooldown while avoiding within-sitting duplicates across Stages 2–4).
  - Hardened Lichess/Chess.com sync (aborted game filtering, reserved path rejection, timeouts, deterministic PGN IDs, multi-month archive walking) and IndexedDB backup/restore atomicity (`brillyDb.ts`, `sound.ts`).
- **Pass 3 — Gravity Check Mobile Layout, Modals, Drills & Mode Interactions (`9237ece`):**
  - Fixed `GravityCheckModal` mobile cut-off (centered viewport layout with safe-area padding and height-capped square board) plus modal reset-loop and timer races.
  - Pinned active items in `OpeningDrillView` and `WoodpeckerCycleView` so solved/revealed feedback stays visible; added rollback guards in `OpeningDrillView` Sparring, `AdvantageConversionView`, and `AnalysisView` Bot/Retry modes.
  - Added boot hydration guard (`hydratedRef`), generation-guarded game sync, scouted-game review jumping, `MistakeTrainerView` motif-aware auto-selection + `EvalBar` orientation fix + `storageRevision` reload, and modal-aware keyboard guards across views.
- **Pass 4 — Mobile Safe-Areas, Vibe (`Cosmic | Classic`) Polish & Dead-Code Cleanup:**
  - Fixed `SettingsMenu` mobile viewport inset positioning + larger close target, `AlienCelebration` Classic vibe mode + Face ID safe-area clearance + auto-dismiss callback, mobile `TransportControls` Retry pill, 5-char `EvalBar` legibility, 2-tap delete confirmation in `OpeningsView`, `InsightsView` Scout-mode CTA gating, `MultiGameOpeningReport` deviation badges, `BrillyVaultView` highlight counters, accessibility pinch-zoom in `index.html`, removed unused `BoardThemePicker.tsx`, and bumped `public/sw.js` to `brillyder-v11`.

### Verified
- `npm test`: **15 test files, 71 tests passed** (including `classification.test.ts` and `auditPass2.test.ts`).
- `npm run build`: `prepare-assets.mjs` + `tsc --noEmit` + `vite build` passed cleanly.

---

## v2.1 — Multi-Move Tactics, Expanded Repertoires, Puzzle Rush Modes & Code-Splitting
**Status:** Completed & Verified

### Built
- **Dual-Platform Handle Resolution & Brilly Vault `!!` Count (`017b127`, `739fb70`):**
  - Kept the Brilly Vault headline count strictly to user `!!` Brilliant moves while retaining Clutch Saves, Traps Punished, and Clean Sweeps in their own stat tiles and tabs.
  - Extended `resolveUserColor` (`UserHandleSpec`) so Lichess and Chess.com games automatically match each platform's saved handle across Vault, Insights, Mistake Deck, Conversion, and Opening Reports.
- **Puzzle Rush Modes (`739fb70`):**
  - Added **3-Min Blitz** and **3-Strikes Survival** modes in `PuzzleRush.tsx` with separate persisted personal bests (`loadRushBest`/`saveRushBest`), strike indicators, best-move arrow feedback on survival misses, and a pawn promotion picker.
- **Multi-Move Tactical Puzzles (`01dd338`):**
  - Added `src/utils/puzzleSequence.ts` (+ tests) extracting legal 2–3 move forcing tactical & forced-mate sequences directly from stored Stockfish `bestPvSan` lines, wired into `MistakeTrainerView`, `WoodpeckerCycleView`, and `DailyCoachSession` with animated opponent replies, `Move X/Y` step badges, step-aware hints, and Stockfish alternative acceptance.
- **Repertoire Line Manager & 4 Extra Starter Courses (`1c89d86`):**
  - Added `LineEditorPanel.tsx`, `src/services/repertoireLines.ts` (+ tests), and `deleteFsrsCardsByLine` in `brillyDb.ts` to add, edit, or delete individual lines inside any course (with live `chess.js` SAN validation and 2-tap starter course Reset).
  - Added 4 new `chess.js`-verified starter courses to `src/data/starterCourses.json`: **Italian Game**, **Queen's Gambit**, **Accelerated Dragon Sicilian**, and **French Defense** (8 starter courses total: 4 White, 4 Black).
- **Bundle Code-Splitting & Faster Mobile Startup:**
  - Converted heavy tabs (`AnalysisView`, `OpeningsView`, `MistakeTrainerView`, `InsightsView`) and modals (`BrillyVaultModal`, `GravityCheckModal`) to `React.lazy` + `<Suspense>` in `App.tsx`, and configured vendor/data `manualChunks` in `vite.config.ts`.
- **Mobile Layout Audit & UI Polish (`5605f24` + UI pass):**
  - Fixed the Walkthrough mobile board blowout/zoom bug (caused by CSS Grid `auto` track + `truncate` (`white-space: nowrap`) inside `GuidedWalkthrough.tsx` expanding the column past viewport width whenever a trap card mounted) and audited every CSS grid across the app to use explicit `grid-cols-1` + `min-w-0`.
  - Added global iOS Safari zoom & overflow protections in `src/index.css` (`overflow-x: clip`, `touch-action: manipulation` on buttons/links, `16px` mobile input font-size floor).
  - Polished mobile UX: inline live plan/trap callout beneath Walkthrough step buttons, height-capped mobile boards, compact 2-column course cards in `OpeningsView`, Games search & quick filter bar + result edge accents in `GameListView`, 1-tap Copy FEN/PGN in `AnalysisView`, `PlayerBar` active turn glow, and active mobile nav indicator.
  - Bumped `public/sw.js` to `brillyder-v18`.

### Verified
- `npm test`: **17 test files, 96 tests passed** (including all 33 `starterCourses.test.ts` chess.js legality checks, `puzzleSequence.test.ts`, and `repertoireLines.test.ts`).
- `npm run build`: `prepare-assets.mjs` + `tsc --noEmit` + `vite build` passed cleanly with zero oversized chunk warnings.

---

## v2.2 — Daily-First Power Suite: Endgame Lab, Move Tree, Board Editor, Share Cards & PWA Polish
**Status:** Completed & Verified

### Information Architecture ("Daily Core Front & Center")
- Kept **15m Daily Coach**, **Woodpecker**, **Advantage Conversion**, and **Mistake Deck** front-and-center as the primary daily improvement flow, while tucking specialty tools cleanly one tap away so they never clutter daily training:
  - **Train → `Labs`** pill houses **Syzygy Endgame Lab**, **60s Board Vision**, and **Puzzle Rush**.
  - **Openings → Walkthrough** keeps a clean `Line | Tree` toggle for the **Repertoire Move Tree**, plus a compact `PGN` export button beside `Import`.
  - **Games** tucks **Board / FEN Editor** neatly next to `Paste PGN`.
  - **Analyze** adds single-tap `Save` (Bookmark) and `Card` (PNG Share) pills beside `FEN` / `PGN`; saved positions live cleanly in **Brilly Vault → Saved** (preserving the 5-tab nav and keeping the Vault headline count strictly user `!!` moves).
  - **Insights** renders **Scout Gameplan ("How to Beat `<opponent>`")** strictly when Scout Mode is active.
  - **Settings** houses **Engine Depth Presets (`Fast D12 | Balanced D14→18 | Deep D18→20`)** and the **Local Maia `.onnx` Model Uploader**.

### Built
- **Phase A (`2b96a20`) — PWA Polish, Depth Presets & Local Maia ONNX:**
  - Non-intrusive PWA `"New BrillyDer update ready · Reload"` banner (`SKIP_WAITING` + `controllerchange`) and header `Offline` badge (`public/sw.js`, `src/main.tsx`, `src/App.tsx`).
  - Added `D12` Fast single-pass preset alongside `D14 → D18` Balanced and `D18 → D20` Deep (`analysisRunner.ts`, `AnalysisView.tsx`, `SettingsMenu.tsx`).
  - Added Cache Storage (`brillyder-maia-models-v1`, preserved across SW cache bumps) local `.onnx` upload/remove + `ArrayBuffer` worker inference in `MaiaService.ts`, `maia.worker.ts`, and `SettingsMenu.tsx`.
- **Phase B (`0ae0e3f`) — Syzygy Endgame Lab & 60s Board Vision:**
  - Built `src/data/endgameDrills.ts` (+ `chess.js` & `<=7`-piece Syzygy eligibility test `endgameDrills.test.ts`) with 12 classic theoretical endgames across all 5 categories (`Pawn`, `Rook`, `Minor Piece`, `Queen`, `Rook+Minor`) plus automatic extraction of user's own `<=7`-piece game slips.
  - Built `EndgameLabView.tsx` (Syzygy live WDL/DTZ grading, promotion picker, Stockfish fallback, persisted mastery) and `BoardVisionView.tsx` (60s Coordinate Sniper with White/Black/Flip modes, Hide Coordinates toggle, personal bests), wired under `Train → Labs` and linked directly from Insights' Endgame Weakness Tracker.
- **Phase C (`9108893`) — Walkthrough Auto-Play, Visual Move Tree & PGN Export:**
  - Added `Play / Pause` auto-stepping to `GuidedWalkthrough.tsx`.
  - Built `src/services/repertoireTree.ts` (+ round-trip test `repertoireTree.test.ts` verifying all 8 starter courses export canonical PGN and re-import identically) and `RepertoireTreeView.tsx` showing branching lines with per-node FSRS Signal Strength dots.
- **Phase D — Position/FEN Editor, Bookmarks, Shareable PNG Cards & Scout Gameplan:**
  - Built lazy-loaded `PositionEditorModal.tsx` + `src/utils/customFen.ts` (piece palette, presets, castling/turn toggles, live `chess.js` validation, instant Analyze launch with custom-FEN support fixed in `AnalysisView.tsx`).
  - Built `src/services/bookmarks.ts` persisted inside IndexedDB prefs + JSON backups, wired into `AnalysisView.tsx` and `BrillyVaultView.tsx` (`Saved` tab).
  - Built pure client-side `<canvas>` PNG card renderer `src/utils/shareCard.ts` (+ `shareCard.test.ts`) with native iOS Web Share API + desktop download fallback, wired into `AnalysisView.tsx` and every card in `BrillyVaultView.tsx`.
  - Built `src/services/scoutReport.ts` (+ `scoutReport.test.ts`) and `ScoutGameplanCard.tsx` surfacing opponent favorite openings, softest ECO targets, and clock/tilt exploits exclusively in Scout Mode.
  - Bumped `public/sw.js` to `brillyder-v20`.

### Verified
- `npm test`: **21 test files, 102 tests passed** (including all 33 starter course SAN tests, 12 Syzygy endgame drills, 8-course PGN round-trip tests, share card tests, and scout gameplan tests).
- `npm run build`: `prepare-assets.mjs` + `tsc --noEmit` + `vite build` passed cleanly with lazy chunks preserved.

---

## v2.2.1 — Final Pre-iOS 4-Agent Swarm Audit & Hardening
**Status:** Completed & Verified

### Built
- **Pass 1 — Chess Engine, Endgame Drills, Syzygy, Maia, Board Editor & Share Card (`8423956`):**
  - Replaced 6 broken/illegal/mate-in-1 theoretical endgame FENs in `src/data/endgameDrills.ts` and added strict non-adjacent-king, non-mover-in-check, wrong-bishop-color, and non-mate-in-1 unit assertions in `endgameDrills.test.ts`; filtered already-lost user slips (`<-1.0`) out of `extractUserEndgameDrills`.
  - Fixed `EndgameLabView` warning-state piece desync (`turnColor` + `interactive`), soft-lock rollback on engine failure, Undo mastery exploit, stale Syzygy hint leakage, and Escape/backdrop/Cancel promotion picker.
  - Hardened `PositionEditorModal` to reject adjacent kings, opponent-in-check, and rank 1/8 pawns, auto-prune phantom castling flags, preserve EP/clocks, lock body scroll, and escape PGN headers in `customFen.ts`.
  - Switched `maia.worker.ts` to `onnxruntime-web/wasm` (cutting worker JS 419 kB → 78 kB and WASM 29.5 MB → 14.8 MB!), serialized worker requests, cached `loadedModelKey` to eliminate 20 MB/move re-transfers, added `AbortSignal` & `dispose()` rejection cleanup; added explicit Stockfish `#wasmUrl` + distinct `EngineTimeoutError`.
  - Fixed SEE promotion capture sort (`=Q` before `=N` in `tacticalMotifs.ts`), 5-field Syzygy cache key (`tablebaseApi.ts`), `401` backoff (`openingExplorer.ts`), `try/catch` move guards (`repertoireTree.ts`), strict opponent matching (`scoutReport.ts`), iOS WebKit `'interrupted'` audio recovery (`sound.ts`), and Share Card filled monochrome `♟\uFE0E` glyphs + measured text truncation (`shareCard.ts`).
- **Pass 2 — State, Smart Backup Merge, Offline Hydration, Custom FEN Isolation & PWA Safety (`05801a7`):**
  - Serialized `setPrefSync` writes with `flushPrefWrites()` before `exportFullBackup`, added smart `merge` semantics for bookmarks/mastered endgames/mistake progress/streaks/PBs/conversion IDs in `brillyDb.ts`, and closed DB handle cleanly on `blocking()`.
  - Hydrated `gamesByPlatform` from cached `analyzed_games` on boot/restore so Games works fully offline; excluded Custom FEN 0-ply records from Batch Analysis, Insights, Opening Reports, and IDB `analyzed_games`.
  - Fixed `sw.js` (only fall back to `index.html` for `request.mode === 'navigate'`, skip caching `ort-wasm`, `brillyder-v22`), suppressed involuntary first-install reload & native Capacitor SW/tip registration, added `LazyViewErrorBoundary`, fixed `runBatchAnalysis`/`runScout`/`handlePlatformChange` races, preserved Sandbox FENs on bookmark reopen, fixed `BoardVisionView` PB overwrite + added Stop button, and wired `mistakeProgress` into `DailyCoachSession`.
- **Pass 3 — Mobile UI, Clipping, Promotion Pickers, Accessibility & Vibe Polish:**
  - Enforced `font-size: 16px !important` on mobile `<input>/<textarea>/<select>` and added `-webkit-touch-callout: none` on board/buttons while removing `background-attachment: fixed` jank in `src/index.css`.
  - Repositioned `ChessgroundBoard` move badges inside the upper-right square corner so rank-8 badges are never sliced by `overflow-hidden`; added `max(260px, ...)` floor to all height-capped mobile boards.
  - Made all 4 promotion pickers dismissible (Escape, backdrop click, Cancel) with side-appropriate glyphs; fixed `SettingsMenu` effect split, `TransportControls` desktop padding, `BrillyVaultView` empty filter state & keyboard target guards, `RepertoireTreeView` Vibe label, `GuidedWalkthrough` timer purity, `PlayerBar` `♟\uFE0E`, and deferred `URL.revokeObjectURL`.

### Verified
- `npm test`: **21 test files, 102 tests passed**.
- `npm run build`: clean TypeScript check & Vite chunked production build (`maia.worker` 78.4 kB, `ort-wasm` 14.8 MB, `index` 178 kB).

---

## v2.3 (iOS Phase 1 — Daily Core MVP) — Native SwiftUI + iOS 26 Liquid Glass App
**Status:** Completed & Verified

### Built
- **App-Store-Compliant Pure Swift 6 Core (`ios/Sources/BrillyDerCore/`):**
  - Zero GPL dependencies: original FIDE-legal `ChessBoard` (Perft-verified, FEN/SAN/UCI, Zobrist hashing), `PGNParser` (`[%clk]` clock extraction & variations), `ChessMath` (exact win%, accuracy, Elo & SEE promotion-ordered capture gain), and BrillyDer v3 `MoveClassifier`.
  - Original pure-Swift `BrillyNativeEngine` (Alpha-Beta + PVS + Quiescence + Transposition Table + Killer heuristics + PeSTO tapered PST + MultiPV) behind pluggable `ChessEngine` protocol (ready for optional MIT C++ NNUE engine like Caissa in Phase 1.5).
  - Full `FSRS6Scheduler` (response-time auto-grading `<3s Easy / 3–10s Good / >10s or hint Hard / wrong Again`), `CourseRepository` bundling all 8 starter courses directly from `src/data/starterCourses.json`, `LichessClient`, `ChessComClient`, `GameAnalyzer`, `DailyCoachPlanner` (`10m / 15m / 25m` 4-stage workouts + 60s Gravity Check), and `LocalVaultStore` with 100% Web PWA ↔ iOS `brillyder` `schemaVersion: 2` JSON backup merge/export.
- **Native SwiftUI + iOS 26 Liquid Glass UI (`ios/Sources/BrillyDerUI/`):**
  - Authentic iOS 26 `.glassEffect(_:in:)` & `GlassEffectContainer` surfaces with automatic Reduce Transparency & iOS 18 fallback, plus live **`UI Surface Style: Liquid Glass | Cosmic Minimalist`** and **`Vibe: Cosmic | Classic`** toggles in `CockpitSettingsSheet`.
  - Zero-GPL custom 120Hz `InteractiveChessBoardView` (tap + drag, legal dots, coaching arrows, square highlights, rank-8 safe classification badges, dismissible promotion overlay, 4 board themes, native haptics).
  - All 5 Daily-First Core tabs (`Train`, `Games`, `Analyze`, `Openings`, `Insights`) + `CockpitSettingsSheet` (with native `fileExporter`/`fileImporter` Web ↔ iOS JSON backup).
- **App Store Compliance Assets (`ios/App/` & `ios/project.yml`):**
  - Generated full-bleed opaque 1024×1024 RGB `AppIcon-1024.png` (`hasAlpha: no`, passes `ITMS-90717`).
  - Added `PrivacyInfo.xcprivacy` (zero tracking, local-only data), `Info.plist` (`ITSAppUsesNonExemptEncryption = false`), `AVAudioSession` (`.ambient` + `.mixWithOthers`), and XcodeGen `project.yml` + `ios/README.md`.

### Verified
- `cd ios && swift build`: clean zero-error, zero-warning Swift 6.3 / SDK 26.4 compilation across both `BrillyDerCore` and `BrillyDerUI` (type-checking real iOS/macOS 26 `.glassEffect()` & `GlassEffectContainer` APIs).
- `cd ios && swift test`: **4 suites, 18 tests passed** (Perft depth 1–3 on starting & Kiwipete positions, 100% legal SAN validation across all 8 starter courses & traps, native engine Mate-in-1/Mate-in-2/hanging Queen/full game analysis, FSRS-6 scheduling, Daily Coach quotas, and Web ↔ iOS JSON backup round-trip).
- `npm test && npm run build`: **21 test files, 102 tests passed** with zero regressions to the web PWA.

### Remaining / Next Up (iOS Phase 2 & 3)
- **Xcode 26 Device Run & TestFlight:** Install Xcode 26 from the Mac App Store, generate `BrillyDer.xcodeproj` via `xcodegen generate`, sign & run on iPhone Simulator / physical device.
- **iOS Phase 2:** Plug in MIT C++ NNUE engine (e.g. Caissa) behind `ChessEngine` for 3500+ Elo deep analysis, Syzygy Endgame Lab, Advantage Conversion, Brilly Vault modal, Shareable PNG Cards, and WidgetKit Home/Lock Screen daily streak widgets.
- **iOS Phase 3:** Visual Repertoire Move Tree, Scout Mode Gameplan, Frozen Woodpecker Cycles, 60s Board Vision, and optional CoreML Maia.

---

## v2.4 (iOS Phase 2 — Full Web-Parity Power Suite & Full-Screen Fix)
**Status:** Completed & Verified

### Built
- **Full-Screen Edge-to-Edge Fix & iOS 26 Liquid Glass Polish:**
  - Moved `UILaunchScreen`, `UIApplicationSceneManifest`, `ITSAppUsesNonExemptEncryption`, and orientations directly into `ios/project.yml` `info.properties` so `xcodegen generate` always preserves full-screen display metadata (verified via `PlistBuddy` in both local builds and GitHub Actions CI).
  - Cleaned up top-right iOS 26 toolbar buttons to render native single-layer Liquid Glass platters, added bottom scroll clearance across all 5 tabs above the floating tab bar, and prevented Daily Coach chip truncation.
- **Games Tab (`GamesTabView.swift`, `PositionEditorSheet.swift`):**
  - Added **Batch Analyze** (`Analyze 5 / 10 / All Unanalyzed`) with live progress HUD & Stop control, result/unanalyzed filters, **Scout Opponent** sheet, and full interactive **Board / FEN Position Editor** (with legality guards for adjacent kings, rank 1/8 pawns, and opponent-in-check).
- **Analyze Tab (`AnalyzeTabView.swift`, `EvalGraphView.swift`, `ShareCardRenderer.swift`):**
  - Added interactive tappable/draggable **Eval Graph**, **Opening Deviation ("Leak Patcher")** card with 1-tap FSRS Queue Boost, live **7-Piece Syzygy Tablebase** readout (`SyzygyClient.swift`), **Play vs Bot** from any position, **Custom FEN Sandbox** live MultiPV mode, Copy FEN/PGN, and native `ImageRenderer` **Shareable PNG Position Cards**.
- **Brilly Vault Modal (`BrillyVaultSheet.swift`, `VaultService.swift`):**
  - Added top-right `💎 N` toolbar button strictly counting user `!!` Brilliant moves, opening a 5-tab modal (`!! Brilliant`, `Clutch`, `Traps`, `Sweeps`, `Saved`) with jump-to-ply & PNG Share Card.
- **Train Power Suite (`TrainTabView.swift`, `TrainPowerModesView.swift`, `TrainLabsView.swift`):**
  - Preserved the **15m Daily Coach** hero front-and-center while adding segmented access to **Woodpecker Cycles** (`30/50/100`, Cycles `#1–7`, First-Try %, 24h cooldown, speed-up log), **Advantage Conversion ("Tractor Beam")**, **Mistake Deck** (motif-filtered), and **Labs** (**Syzygy Endgame Lab** with all 12 verified theoretical drills + user slips, and **60s Board Vision** coordinate sniper).
- **Openings & Insights Suites (`OpeningsTabView.swift`, `InsightsTabView.swift`, `RepertoireTreeService.swift`, `AdvancedInsightsService.swift`):**
  - Added **Repertoire Move Tree (`Line | Move Tree`)** with FSRS recall dots, **Import Custom PGN Course**, **Export Canonical PGN**, and **Wrong-Move Trap Spotlight** in Openings.
  - Added **Clock Leaks (Impulse vs Time Trouble)**, **Tilt Guard (`0L / 1L / 2L / 3L+` + stop-loss alert)**, **Patterns You Miss Most** (1-tap Train), **Endgame Weakness Tracker** (1-tap Lab), and **Scout Gameplan** in Insights.

### Verified
- `cd ios && swift test`: **5 suites, 23 tests passed** (including all 12 theoretical Syzygy endgames, 8-course PGN round-trip, DeviationDetector, strict Vault count, Perft 1–3, and all 8 starter courses).
- `cd ios && ./scripts/build-ipa.sh --unsigned`: Local Xcode `Release-iphoneos` `arm64` `** BUILD SUCCEEDED **`, generated `ios/build/BrillyDer-iOS-unsigned.ipa` with verified `UILaunchScreen` in `BrillyDer.app/Info.plist`.

### Remaining / Next Up (iOS Phase 3)
- **Native MIT C++ NNUE Engine Upgrade:** Bind a 3500+ Elo MIT-licensed C++ NNUE engine (e.g. Caissa) behind `ChessEngineProtocol` for ultra-deep instant analysis.
- **WidgetKit & CoreML:** Home/Lock Screen daily streak & due-cards widgets + optional local CoreML Maia bot.

---

## v2.5 (iOS Polish & 100% Parity — Vector Staunton Pieces, Faceted Gem Logo, Audio/Celebrations, Puzzle Rush & Resilient Web Migration)
**Status:** Completed & Verified

### Built
- **Custom Zero-GPL Vector Neo-Staunton Chess Pieces (`ChessPieceGlyph.swift`):** Replaced Unicode font glyphs with original sculpted SwiftUI Canvas vector silhouettes filling ~86% of each square with high-contrast gradients, outlines, and inner detail lines.
- **Custom Faceted Brilliant Gem Icon (`BrillyGemIcon.swift`) & Vector Move Badges:** Replaced flat SF rhombus with a custom faceted crystal gem across the top-right `💎` pill, Brilly Vault header, and celebrations; replaced emoji Book/Star board badges with crisp SF Symbols inside `InteractiveChessBoardView.swift`.
- **Resilient Web PWA → iOS Backup Migration (`LocalVaultStore.swift`, `CockpitSettingsSheet.swift`):** Hardened JSON decoding against float `cpWhite` and legacy FSRS card fields, added full restoration of bookmarks (`brillyder_saved_positions_v1`), mastered endgames (`brillyder_endgame_mastered_v1`), streaks (`brillyder_mistake_streak`), conversion IDs (`training_logs`), and Board Vision / Puzzle Rush personal bests, plus both **Import File (.json)** and **Import From Clipboard** in Settings.
- **Full Feature Parity Additions:** Added procedural `AVAudioEngine` sound cues (`SoundEffects.swift`), non-blocking Cosmic UFO / Classic celebrations (`AlienCelebrationOverlay.swift`), **Puzzle Rush** (`3-Min Blitz` & `Survival 3-Strikes`) in `TrainLabsView.swift`, **Lichess Game URL Import** (`LichessClient.fetchSingleGame`), **20-Game Checkpoints & Accuracy Trend Chart** in `InsightsTabView.swift`, and custom course deletion in `OpeningsTabView.swift`.

### Verified
- `cd ios && swift test`: **5 suites, 24 tests passed** (including real Web PWA JSON backup migration test).
- `cd ios && ./scripts/build-ipa.sh --unsigned`: `Release-iphoneos` `arm64` `** BUILD SUCCEEDED **` (`v2.5.1`, build `4`).
- **v2.5.1 Hotfixes:** Moved single & batch analysis off `@MainActor` via `Task.detached` with ply-by-ply live `batchProgress`, upgraded Analysis & Batch HUDs to glowing `TractorBeamProgressBar` + radar ring, and froze `DailySessionSheet` steps on appear with `board.turn` orientation so grading FSRS cards never shifts the list or flips the board mid-move.

---

## v2.6 (Full 4-Agent Native iOS Swarm Audit & Production Hardening)
**Status:** Completed & Verified

### Built
- **Pass 1 — Chess Rules, Engine, Classification & Syzygy Integrity (`BrillyDerCore`):**
  - Hardened `ChessBoard.init(fen:)` (rejects rank 1/8 pawns, opponent-already-in-check, invalid EP squares; strips impossible castling flags) and normalized phantom en passant squares in `positionKey` & `zobristHash` so transpositions/repetitions hash identically.
  - Hardened `BrillyNativeEngine` (only caches root TT on `pvIdx == 1` to stop MultiPV TT poisoning, disables deadline at depth 1 & requires `completedAnyMove` to prevent fake `-M1`, full in-check evasions & checkmate detection in `quiescence`, in-search `pathHashes` repetition detection, skips TT cutoffs on PV nodes, preserves deeper PV1 if PV2 times out).
  - Fixed `SyzygyClient` candidate move perspective (`invertOpponentCategory` converts Lichess opponent-perspective moves to mover perspective), filtered `"unknown"`, excluded castling & K-vs-K, added 3-min 429/5xx backoff and 160-entry LRU cache.
  - Fixed `PGNParser` wrapped clock comments & `"e.p."`, `ChessMath` POSIX locale formatting, `MoveClassifier` prefix-matched book plies & passive promotion sacrifice, `FSRS6Scheduler` forget-stability clamp, `DeviationDetector` dual-handle matching & ply-24 scan, `RepertoireTreeService` branch-keyed recall (`beforePosKey::san`), and dual-handle ownership across `GameAnalyzer`, `VaultService`, `AdvancedInsightsService`, `EndgameDrills`, `DailyCoachPlanner`, and `WoodpeckerAndConversion`.
- **Pass 2 — Crash-Proof Web ↔ iOS Backup Migration, Persistence & Dual-Engine Concurrency (`LocalVaultStore`, `BrillyAppStore`, Sync Clients):**
  - Eliminated launch-loop `fatalError` on Web backups containing edited starter courses (`allCourses` overrides starters by ID, all `Dictionary(uniqueKeysWithValues:)` replaced with `uniquingKeysWith:`, unmatched/`game-deviation` FSRS cards preserved).
  - Closed all 5 Web PWA ↔ iOS backup schema gaps: bidirectional `brillyder_username_lichess` & `brillyder_username_chesscom`, `training_logs.data.ids` + `woodpecker_cycles` (`activeAttemptedIds` + `gameId_ply` normalization), `lastSolvedAt` + `brillyder_daily_done` streak sync, FSRS `unlocked ||` + `last_review` merge, lossy per-element `VaultSnapshot` decoding + `.corrupt` backup preservation.
  - Added `isHydrated` save guard, coalesced serial vault persistence + `.background` flush, dedicated `interactiveEngine` actor so Batch Analyze never stalls Play Bot/Sandbox/Endgames, monotonic generation guards across analysis/batch/sync/scout tasks, strict `LichessClient` & `ChessComClient` validation/dedup, and memoized store snapshots.
- **Pass 3 — 120Hz Board, Sculpted Vector Pieces, Audio Recovery, Lazy Share Cards & App Store Readiness:**
  - Added missing `NSPhotoLibraryAddUsageDescription` to `ios/project.yml` (`v2.6.0`, build `5`) to prevent TCC `SIGABRT` on Photo Library saves; wired `scenePhase` lifecycle in `BrillyDerApp.swift`; hardened `build-ipa.sh` & `.github/workflows/ios-ipa.yml` (PR trigger, `PlistBuddy` checks, `--team-id` injection).
  - Rewrote `BrillySoundEngine` (`SoundEffects.swift`) with pre-cached PCM buffers and automatic recovery across `AVAudioEngineConfigurationChange`, phone-call interruptions, and media-services resets.
  - Replaced synchronous `ImageRenderer` in `body` with lazy `BrillyShareCardItem: Transferable` (`ShareCardRenderer.swift`) and cached `OpeningDeviationReport` in `AnalyzeTabView`.
  - Upgraded `InteractiveChessBoardView` (`@GestureState` cancel-proof dragging, 1× per-frame legal move calculation instead of 64×, `.none` gesture gating on non-interactive boards, En Passant capture ring, unified single-path arrows, Neon coordinate contrast, lifted drop hit-testing) and `ChessPieceGlyph` (single `drawLayer` shadow, crisp Black-piece halo contrast on Neon/Walnut, responsive mini-board detail culling, seamless 12-pt King cross, Bishop slash, Staunton Pawn proportions).
- **Pass 4 — Full SwiftUI Screen & Drill Polish:**
  - Fixed `DailySessionSheet` (added Stage 4 drills, fixed double FSRS grading via `hadMistakeOnCurrent`, dynamic duration title, `ScrollView`), `GravityCheckSheet` (real 60s countdown, real per-item `responseMs`, rose/teal feedback, no `0/1` flash), `AnalyzeTabView` (Coach Card positioned above floating glass tab bar, full game-switch reset, cancellable Bot/Eval tasks, kept solved Retry move visible), `WoodpeckerCyclePanel` (missing-puzzle recovery, 2-step Reveal, deduped Freeze buttons), `ConversionPlaySheet` & `EndgameDrillPlaySheet` (cancellable bot tasks, post-bot outcome checks, `"cursed-win"` Syzygy draw check), `BoardVisionPanel`, `PuzzleRushPanel`, `OpeningsTabView` (live FSRS recall, delete confirmation, full move tree), `InsightsTabView` (20-game checkpoints scoped strictly to recent 20 games), `BrillyVaultSheet` (bookmark delete), `PositionEditorSheet` (castling toggles, FEN error feedback, 6-wide SE palette), `CockpitSettingsSheet`, and safe-area-aware global Batch Scan floating pill in `BrillyDerRootView`.

### Verified
- `cd ios && swift test`: **5 suites, 28 tests passed** (added regressions for Syzygy perspective inversion, phantom EP transposition equality, strict FEN validation, MultiPV root TT non-poisoning, unresolved Vault ownership, and full Web PWA backup migration with patched starter course & Woodpecker cycles).
- `cd ios && ./scripts/build-ipa.sh --unsigned`: `Release-iphoneos` `arm64` `** BUILD SUCCEEDED **` (`v2.6.0`, build `5`, `UILaunchScreen` & `NSPhotoLibraryAddUsageDescription` verified via `PlistBuddy`), packaged `ios/build/BrillyDer-iOS-unsigned.ipa`.
- `npm test`: **21 test files, 102 tests passed** with zero Web PWA regressions.

---

## v2.6.1 (iOS Pro Piece Sets & Launch-Stability Hotfixes)
**Status:** Completed & Verified

### Built
- **4 Tournament-Grade Permissively Licensed Retina Piece Sets (`ChessPieceGlyph.swift`, `BrillyTheme.swift`, `BrillyDerUI/Resources/Pieces/`):**
  - Replaced hand-coded Bézier silhouettes with 48 pre-rendered 256×256 `@3x` transparent Retina PNGs across 4 App-Store-safe (zero GPL, zero NC) piece sets (~796 KB total, documented in `ios/THIRD_PARTY_LICENSES.md`):
    - **Classic (`cburnett`)** — BSD-3-Clause (Colin M.L. Burnett / Wikimedia Commons, default matching BrillyDer Web)
    - **Chessnut (`chessnut`)** — Apache 2.0 (Alexis Luengas)
    - **Spatial (`spatial`)** — MIT (Maurizio Monge)
    - **Minimal (`kiwen-suwi`)** — CC BY 4.0 (neverRare)
  - Added `@MainActor` `PieceSpriteCache` (`NSCache`), `@Environment(\.brillyPieceSet)` live propagation across every board, editor, modal, and Share Card (`BrillyShareCardItem`), plus a 2×2 **Chess Piece Style** picker with live two-square board previews inside `CockpitSettingsSheet.swift`.
- **iOS Launch-Stability Fixes (`BrillyDerApp.swift`, `SoundEffects.swift`, `LocalVaultStore.swift`, `BrillyDerRootView.swift`):**
  - Moved `AVAudioSession` activation off the main thread (`Task.detached(priority: .utility)`) to eliminate iOS `AVAudioSession Hang Risk` faults on launch.
  - Made `BrillySoundEngine` 100% lazy (never constructs or starts `AVAudioEngine` at launch), added `hwFormat.sampleRate > 0 && hwFormat.channelCount > 0` guard to prevent real-device ObjC `NSException` (`SIGABRT`) crashes, and stopped mutating the audio graph inside `AVAudioEngineConfigurationChange`.
  - Fixed a potential infinite-loop hazard in `LossyDecodableArray` when encountering malformed non-object JSON elements (`JSONValue.self` + strict `currentIndex` advance guard).
  - Replaced `.safeAreaInset(edge: .top)` around `TabView` with non-intrusive `.overlay(alignment: .top)`.

### Verified
- `cd ios && ./scripts/build-ipa.sh --unsigned`: `starterCourses.json` diff clean, `swift test` **5 suites, 28 tests passed**, Release `arm64` `** BUILD SUCCEEDED **` (`v2.6.1`, build `6`), verified `UILaunchScreen`, `NSPhotoLibraryAddUsageDescription`, and all 48 PNGs inside `Payload/BrillyDer.app/BrillyDer_BrillyDerUI.bundle`.

---

## v2.6.2 (iOS Cosmic Alien Share Cards & Interactive Share Card Studio)
**Status:** Completed & Verified

### Built
- **Native Alien UFO Mascot & Expressive Mood System (`BrillyAlienUFOView.swift`, `AlienCelebrationOverlay.swift`):**
  - Built a bespoke SwiftUI vector Alien UFO mascot (`BrillyAlienUFOView`) with glowing tractor beam, translucent cockpit dome, porthole rim lights, sparkles, and 6 move-reactive moods (`brilliant` starry-eyed galaxy-brain alien, `great` cyan-visored striker, `best` approving alien, `book` scholar-glasses alien, `mistake` surprised alien, and `blunder` tilted dizzy `× ×`-eyed facepalming alien with sweat drop), plus curated Cosmic & Classic quip pools (`BrillyShareQuips`).
  - Upgraded `AlienCelebrationBanner` to render `BrillyAlienUFOView` during live Brilliant/Blunder moments in Cosmic mode (cleanly falling back to `BrillyGemIcon` / warning triangle in Classic mode).
- **Show-Stopping Move Highlight Share Card & Interactive Studio (`ShareCardRenderer.swift`, `VaultService.swift`, `AnalyzeTabView.swift`, `BrillyVaultSheet.swift`):**
  - Enriched `VaultHighlight` with `fromSquare`, `toSquare`, `classification`, `evalScore`, `whiteName`, `blackName`, `userAccuracy`, `userEstimatedElo`, and `openingName` so **Brilly Vault** share cards (and vault thumbnails) display the exact move played.
  - Redesigned `BrillyShareCardView` (rendered at `3x` Retina `1200px` wide) with deep starfield & classification-colored nebula backdrop, **BRILLY**`DER` header + signal badge, bold hero move banner (`23. Qxe8 !! BRILLIANT`), Alien UFO reaction quote, `e2 → e8` trajectory & accuracy chips, **dashed origin launch ring + luminous gradient move arrow + destination square glow border + gleaming on-board `!!` badge**, integrated horizontal Eval Bar, full player matchup & unwrapped 2-line coaching insight.
  - Added **`BrillyShareCardSheet`** interactive Share Card Studio on tapping **Card** / **Share Card** in both `AnalyzeTabView` and `BrillyVaultSheet`, featuring live full-fidelity preview, **Alien Cosmic / Classic** toggle, **New Quip** shuffler, **Arrow** toggle, one-tap **Share Card**, and one-tap **Save Photo** directly to the Camera Roll.

### Verified
- Rendered & visually inspected real `ImageRenderer` PNG previews for both `23. Qxe8!!` Brilliant (Classic pieces, Slate board) and `4. Qf3??` Blunder (Chessnut pieces, Emerald board).
- `cd ios && ./scripts/build-ipa.sh --unsigned`: `starterCourses.json` diff clean, `swift test` **5 suites, 28 tests passed** (including `VaultHighlight` move-square & metadata assertions), Release `arm64` `** BUILD SUCCEEDED **` (`v2.6.2`, build `7`), packaged `ios/build/BrillyDer-iOS-unsigned.ipa`.

---

## v2.6.3 (iOS Brilly/Der Brand Lift, Top-Left Crown Logo & BRILLY!! / BLUN-DER!! Shouts)
**Status:** Completed & Verified

### Built
- **Official Split-Crown Logo & `Brilly / Der` Dual-Tone Wordmark (`BrillyBrandViews.swift`, `BrillyDerRootView.swift`, `TrainTabView.swift`, `ShareCardRenderer.swift`):**
  - Built native vector `BrillyLogoMark` (matching Web `icon.svg` / iOS AppIcon: cyan/rose split chess crown, `!!`/`??` accents, split arcs) and mounted it in the top-left circular glass toolbar slot (`.topBarLeading`, tapping navigates home to Train) and in the Share Card header.
  - Built dual-tone `BrillyWordmarkView` (`Brilly / Der` with luminous teal gradient, frosted tilted `/`, and blunder-rose gradient) and replaced the plain white navigation title on `TrainTabView` with the hero `Brilly / Der` brand bar + `!! / ??` badge.
- **`BRILLY!!` & `BLUN-DER!!` Shout System + Settings Preview (`BrillyTheme.swift`, `BrillyAppStore.swift`, `BrillyAlienUFOView.swift`, `AlienCelebrationOverlay.swift`, `AnalyzeTabView.swift`, `CockpitSettingsSheet.swift`):**
  - Added persisted `CalloutStyle` (`Brilly/Der` default, `Alien Probe`, `Standard`; `Vibe == .classic` always cleanly enforces standard chess labels).
  - Upgraded `AlienCelebrationBanner` with bold dual-tone shout headlines (`BRILLY!! MOVE!`, `PURE BRILLY!!`, `BLUN-DER!!`, `OH DERRR!!`), glowing `!!` / `??` pill tags, subtle watermark shimmer, and expressive `BrillyAlienUFOView` alongside witty Brilly/Der quips.
  - Wired Brilly/Der labels into `AnalyzeTabView` coach pills (`Brilly!!`, `Blun-DER`, `Mini-Der`), `BrillyShareCardView` (`PURE BRILLY!!`, `!! BRILLY`, `?? BLUN-DER`), and `BrillyShareCardSheet` style cycler (`Brilly/Der → Alien Probe → Classic`).
  - Added `Move Callouts` picker + live inline **`Preview Brilly!!`** and **`Preview Blun-DER`** test buttons right inside `CockpitSettingsSheet`.

### Verified
- Visually inspected rendered `ImageRenderer` previews ([preview_brand_shouts.png] and [preview_brillyder_card.png]) verifying the top-left split-crown logo, `Brilly / Der` wordmark, `PURE BRILLY!!` / `OH DERRR!!` Alien UFO banners, and updated `BRILLY / DER` Share Card.
- `cd ios && ./scripts/build-ipa.sh --unsigned`: `starterCourses.json` diff clean, `swift test` **5 suites, 28 tests passed**, Release `arm64` `** BUILD SUCCEEDED **` (`v2.6.3`, build `8`), packaged `ios/build/BrillyDer-iOS-unsigned.ipa`.

---

## v2.6.4 (iOS Daily Coach & Opening Drill Overhaul — Exact Move Numbers, Zero Phantom Arrows & Context)
**Status:** Completed & Verified

### Built
- **Authoritative Move Numbers & Strict Legal-Move Arrow Validation (`DailyCoachPlanner.swift`, `ChessTypes.swift`, `TrainTabView.swift`, `OpeningsTabView.swift`):**
  - Replaced stale `ply / 2 + 1` move numbering with `ChessBoard(fen:).fullmoveNumber` across `DailySessionSheet`, `GravityCheckSheet`, `DailyCoachPlanner.buildGravityCheckFlashes`, and `OpeningsTabView` drills so Move 7–10 positions never misreport as Move 2/3.
  - Added `DailyCoachPlanner.legalMove(uci:on:)` validation before filtering cards in `buildPlan` / `buildGravityCheckFlashes` and before drawing ANY hint highlight or vector arrow, eliminating phantom arrows from empty or stale squares (`b8 → c6`).
  - Added `DailyCoachPlanner.precedingMove(for:)` and source-game previous-ply lookup so every Daily Coach & Opening Drill card highlights the opponent's last move (`After 7. O-O`) instead of cold-dropping onto an unlabeled static board.
- **Polished Daily Coach UX & 2-Step Progressive Hints (`TrainTabView.swift`, `OpeningsTabView.swift`):**
  - Switched `DailySessionSheet` and `GravityCheckSheet` to compact `.inline` navigation headers, added a crisp context bar (`Course · Line Title`, exact `Move N` + side dot, and `Played <blunder>` pill on Rewind drills), and surfaced real `MoveAnnotation.plan` coaching insights on solve and `WrongMoveTrap` explanations on trap misses.
  - Upgraded Hints to a clean 2-step flow (**Tap 1:** highlights the origin piece square + piece name nudge; **Tap 2:** draws the validated legal arrow), resetting cleanly on solve with a `★` solved badge on the board.

### Verified
- `cd ios && ./scripts/build-ipa.sh --unsigned`: `starterCourses.json` diff clean, `swift test` **5 suites, 29 tests passed** (added `dailyCoachLegalityAndContext` regression test), Release `arm64` `** BUILD SUCCEEDED **` (`v2.6.4`, build `9`), packaged `ios/build/BrillyDer-iOS-unsigned.ipa`.

---

## v2.7.0 (Auto-Play Restore, Daily FSRS Opening Selector, Anti-Bleed Nav Polish & Founder Pro Suite)
**Status:** Completed & Verified

### Built
- **Restored Analyze Auto-Play & Speed Toggle (`AnalyzeTabView.swift`):**
  - Added glowing `▶ AUTO` / `⏸ PAUSE` and `1x` / `2x` speed toggle buttons right inside the Analyze transport bar (with automatic rewind from end, pause on manual step/retry/bot/game switch, and celebratory pause on `!!`/`??` moves at `1x`).
- **Daily FSRS Opening Selector — Two Effortless Ways (`BrillyAppStore.swift`, `OpeningsTabView.swift`, `TrainTabView.swift`, `CockpitSettingsSheet.swift`):**
  - Added persisted `dailyOpeningCourseIds` filtering across `dueOpeningCount`, `dailyWorkoutPlan`, and `GravityCheckSheet` (smart default includes only practiced/imported openings rather than random unpracticed openings).
  - **Way 1 (Openings Tab):** Press & hold (`contextMenu`) OR tap the direct `Daily ✓` / `Add Daily` pill on any opening card to include/exclude it from Daily FSRS.
  - **Way 2 (Train Tab & Settings):** Tap `1. Openings · Edit` (or the `due` pill) on the Daily Flight Plan card — or Settings → **Choose Daily Openings** — to open `DailyOpeningsPickerSheet` with White/Black toggles and `Practiced Only` / `All` / `Clear` presets.
- **Anti-Bleed Bottom Tab Chrome, Safe-Area Padding & Clean Empty States (iOS + Web):**
  - Added frosted solid dark tab-bar chrome (`#0E121A` at 92% opacity + subtle bottom fade scrim on iOS `BrillyDerRootView.swift`; `.brilly-bottom-nav` `rgba(14,18,26,0.92)` + `blur(20px)` on Web `src/index.css` / `src/App.tsx`) and bumped bottom scroll clearance across all 5 tabs (`padding(.bottom, 120)` on iOS; `pb-[calc(7rem+env(safe-area-inset-bottom))]` on Web).
  - Replaced `0 Bookmarks` on the Train summary row with a dynamic `🔥 Daily Streak` tile when bookmarks are empty (switching to `Bookmarks` once `>= 1` saved).
  - Replaced `0% recall` on unstarted openings in `OpeningsTabView` with an inviting teal-tinted progress bar and `Start Drill →` pill.
- **Viral Share Card Footer, Tap-Scale Polish & Brilly/Der Pro Modal (Founder Pro Unlocked):**
  - Added both players' accuracy comparison (`Lukedunwell 94.9% vs Opponent 88.5%`) and a crisp `Analyzed with Brilly/Der` viral footer pill to `ShareCardRenderer.swift` & `src/utils/shareCard.ts`.
  - Added `BrillyPressScaleStyle` (`scaleEffect(0.975)`), Web `active:scale-[0.98]` + `user-select: none`, and `BrillyProPaywallSheet.swift` + `src/components/BrillyProModal.tsx` featuring Monthly (`£3.99/mo`), Annual (`£24.99/yr`, **Best Value · 7-Day Free Trial**), and Lifetime (`£39.99 one-time`) — with **Founder Pro Active (`hasProAccess = true`) unlocked by default** for the owner plus an optional `Simulate Free Tier Locks` preview toggle in Settings.

### Verified
- `npm test && npm run build`: Web PWA tests & production Vite build passed cleanly.
- `cd ios && ./scripts/build-ipa.sh --unsigned`: `starterCourses.json` parity clean, `swift test` **5 suites, 29 tests passed**, Release `arm64` `** BUILD SUCCEEDED **` (`v2.7.0`, build `10`), packaged `ios/build/BrillyDer-iOS-unsigned.ipa`.

---

## v2.8.0 (Final 4-Agent App Store Readiness Swarm Audit, Analyze AUTO Bar Fix & Streak Repair)
**Status:** Completed & Verified

### Built
- **Analyze Un-Squished `AUTO` Bar & Top Header Controls (`AnalyzeTabView.swift`):**
  - Replaced the large `Analyze` system title with a compact inline header holding `|<` (First), `>|` (Last), `⇅` (Flip), and a native `⋯` Game Menu (Bookmark, Share Move Card, Copy FEN/PGN, Play Bot), leaving 4 spacious 44pt+ controls (`<`, single-line `▶ AUTO / ⏸ PAUSE`, `>`, `1x/2x`) below the board.
  - Added `ScrollViewReader` auto-scrolling on the horizontal move strip + high-contrast dark ink on selected move numbers.
- **App Store Review & Legal Compliance (`CockpitSettingsSheet.swift`, `BrillyAppStore.swift`, `BrillyProPaywallSheet.swift`, `TrainTabView.swift`, `BrillyAlienUFOView.swift`, `public/privacy.html`, `public/support.html`, `ios/scripts/build-ipa.sh`):**
  - Gated non-StoreKit paywall preview & `"Simulate Free Tier Locks"` debug toggle strictly behind `#if DEBUG` (keeping full access unconditionally unlocked in Release — zero Guideline 3.1.1 / 2.1 / 2.2 risk).
  - Replaced misleading iOS `"Stockfish"` references with accurate `BrillyNative` on-device engine copy.
  - Added in-app **About, Privacy Policy & Third-Party Licenses** sheets (fulfilling Guideline 5.1.1(i) and BSD-3-Clause / Apache-2.0 / MIT / CC BY 4.0 binary attributions) + static `public/privacy.html` & `public/support.html` for App Store Connect + native `PasteButton` clipboard import.
  - Hardened `ios/scripts/build-ipa.sh` with `verify_app_bundle()` checking `PrivacyInfo.xcprivacy` (`plutil -lint`), `ITSAppUsesNonExemptEncryption`, `UILaunchScreen`, `NSPhotoLibraryAddUsageDescription`, `starterCourses.json`, `cburnett_wK.png`, and `AppIcon-1024.png` opaque alpha check across both `--unsigned` and `--app-store` modes.
- **Daily Streak System Repair (`BrillyAppStore.swift`, `BrillyDerRootView.swift`, `TrainTabView.swift`):**
  - Fixed iOS hiding the toolbar streak count (switched `Label` to explicit `HStack` so `🔥 4d` renders cleanly), switched yesterday calculation to DST-safe `Calendar.current.date(byAdding: .day, value: -1, to:)`, and wired automatic `recordTrainingActivity()` across all training flows (Opening FSRS drills, Daily Coach, Gravity Check, Woodpecker, Endgame Lab, Advantage Conversion, Board Vision, and Puzzle Rush).
- **UI, iPad Universal, WCAG Contrast & Stability Hardening (`BrillyDerRootView.swift`, `LiquidGlassModifiers.swift`, `InteractiveChessBoardView.swift`, `EvalBarView.swift`, `PositionEditorSheet.swift`, `TrainLabsView.swift`, `ShareCardRenderer.swift`, `SoundEffects.swift`, `BrillyDerCore`):**
  - Removed root bottom blackout scrim and adopted native `.brillySoftScrollEdge()` + `.brillyTabBarChrome()` + clean `36pt` bottom padding; capped iPad chessboards at `520pt` on regular width; upgraded WCAG AA+ badge ink & `warpPurpleText`; added VoiceOver labels to `PositionEditorSheet` & `PuzzleRushPanel` hearts and stacked Castling pills cleanly for 375pt iPhone SE.
  - Replaced Swift 6 `@MainActor @objc` `PhotoLibrarySaver` with async `Photos` (`PHPhotoLibrary.requestAuthorization(for: .addOnly)` + `PHAssetCreationRequest`) with clear permission-denied feedback.
  - Eliminated P0 Core crash/logic bugs: Unicode `parseSAN` force-unwrap crash, `FSRS6Scheduler` `Int64` overflow (`36,500`-day cap + `max(0, attempts)`), `BrillyNativeEngine` horizon stalemate `standPat` bug & MultiPV timeout ordering, 3-fold repetition draw blunder classification, `ChessComClient` `"+"`/`inf` bounds + `https://api.chess.com` host validation, `PGNParser` BOM/multi-game/NaN safety, `SyzygyClient` offline 45s backoff & 3.5s timeout, `VaultService` lazy `posKey` + dedup, `DeviationDetector` Black move-1 guard, `LocalVaultStore` date-based FSRS merge, `BrillyAppStore` `dailyOpeningCourseIds` pruning + `beginBackgroundTask` flush, and `SoundEffects` `[.interrupts]`.

### Verified
- `npm test && npm run build`: **21 test files, 102 tests passed** + Vite production build clean (including `public/privacy.html` & `public/support.html`).
- `cd ios && ./scripts/build-ipa.sh --unsigned`: `starterCourses.json` parity clean, `swift test` **6 suites, 35 tests passed** (added `AppStoreReadinessTests.swift`), Release `arm64` `** BUILD SUCCEEDED **` (`v2.8.0`, build `11`), all App Store bundle checks (`PrivacyInfo.xcprivacy`, `Info.plist`, opaque `AppIcon`, pieces & courses) passed.

---

## v2.9.0 (Production StoreKit 2 Monetization + Side-by-Side Founder Admin Edition)
**Status:** Completed & Verified

### Built
- **Real StoreKit 2 Engine & Entitlement Policy (`BrillyEntitlementPolicy.swift`, `BrillyStoreKitManager.swift`, `ios/BrillyDer.storekit`, `docs/STOREKIT_SETUP.md`):**
  - Implemented `BrillyStoreKitManager` (`@MainActor @Observable`) with live `Product.products(for:)` discovery (`com.brillyder.pro.monthly`, `com.brillyder.pro.annual`, `com.brillyder.pro.lifetime`), dynamic 7-day introductory trial eligibility (`subscription.isEligibleForIntroOffer`), `Product.purchase()`, background `Transaction.updates` listener, offline JWS-verified `Transaction.currentEntitlements`, `AppStore.sync()` Restore Purchases, and `AppStore.showManageSubscriptions`.
  - Added local Xcode `ios/BrillyDer.storekit` configuration linked to the `BrillyDer` run scheme + `docs/STOREKIT_SETUP.md` App Store Connect checklist + hosted `public/terms.html` & in-app `BrillyTermsSheet`.
- **Production Paywall & Clear Free-vs-Pro Boundaries (`BrillyProPaywallSheet.swift`, `BrillyAppStore.swift`, `TrainTabView.swift`, `GamesTabView.swift`, `OpeningsTabView.swift`, `CockpitSettingsSheet.swift`):**
  - Replaced debug-only preview with full App Store Guideline 3.1.2-compliant StoreKit 2 paywall (localized Apple prices, trial-eligibility-gated 7-day badge, auto-renewal disclosure, Restore Purchases, Privacy Policy & Terms links).
  - Enforced clean Free vs. Pro boundaries on the App Store target: Free = unlimited Lichess/Chess.com sync, 5 new game analyses/day (cached games always free), 10m Orbit Coach + 60s Gravity Check + Mistake Deck, 2 starter openings (*London System* + *Modern Defense*), and `cburnett` piece set; Pro = unlimited game & batch analysis, 15m/25m Orbit Coach, Woodpecker Cycles, Advantage Conversion, Endgame/Vision Labs, all 8 openings + Custom PGN imports, and all 4 Retina piece sets.
- **Synchronized Dual Targets — App Store (`BrillyDer`) + Founder Admin (`BrillyDerAdmin`) (`ios/project.yml`, `ios/App/BrillyDerApp.swift`, `ios/scripts/build-ipa.sh`, `.github/workflows/ios-ipa.yml`):**
  - Added a second `BrillyDerAdmin` target (`com.brillyder.admin`, display name `BrillyDer Admin`, compile flag `BRILLY_ADMIN_EDITION`) sharing 100% of `BrillyDerCore` & `BrillyDerUI` so every future commit updates BOTH editions automatically with zero branch drift and installs side-by-side on the same iPhone.
  - Updated `build-ipa.sh` (`--edition both|store|admin`, enforcing `com.brillyder.app` on `--app-store`) and GitHub Actions `ios-ipa.yml` to build, verify, and upload both `BrillyDer-iOS-unsigned.ipa` and `BrillyDer-Admin-iOS-unsigned.ipa`.

### Verified
- `npm test && npm run build`: Web PWA tests & Vite production build clean (including `public/terms.html`).
- `cd ios && ./scripts/build-ipa.sh --unsigned --edition both`: `starterCourses.json` parity clean, `swift test` **6 suites, 36 tests passed**, BOTH `BrillyDer` (`com.brillyder.app`) and `BrillyDerAdmin` (`com.brillyder.admin`) Release `arm64` builds succeeded + passed `verify_app_bundle()`.

---

## v2.10.0 (Ghibli-Style Thumbs-Up Default Theme, Decoupled Mascots & First-Install Welcome Guide)
**Status:** Completed & Verified

### Built
- **Studio Ghibli-Style Thumbs-Up & Blun-DER Mascots (`BrillyGhibliBuddyView.swift`, `Resources/Mascots/brilly_buddy_thumbsup.png`, `brilly_buddy_blunder.png`):**
  - Bundled custom 320x320 Retina hand-painted Ghibli-style chess-buddy sticker portraits (cheerful thumbs-up buddy with golden knight pin for positive moves; comical facepalm buddy for blunders) with glowing themed rim and instant static image caching.
- **Approachable Default Theme & Decoupled Mascot Picker (`BrillyTheme.swift`, `AlienCelebrationOverlay.swift`, `BrillyAlienUFOView.swift`, `ShareCardRenderer.swift`, `BrillyAppStore.swift`, `CockpitSettingsSheet.swift`):**
  - Switched fresh-install defaults away from the Alien space theme to **`Classic` Coach Copy** + **`Brilly/Der` Ghibli Thumbs-Up Buddy** (*"Very nice, Brilly!!"* / *"Blun-DER!!"*).
  - Decoupled `calloutStyle` from `vibeMode` so users can freely mix **`Brilly/Der` (Ghibli Thumbs-Up)**, **`Standard` (Glowing Diamond)**, and **`Alien UFO` (Cosmic Probe)** in Settings, live celebrations, and Share Cards.
- **First-Install Welcome Guide & Interactive Theme Picker (`BrillyWelcomeGuideSheet.swift`, `BrillyDerRootView.swift`, `CockpitSettingsSheet.swift`):**
  - Added a 3-step first-launch sheet (1. Quick App Guide, 2. Live Mascot / Vibe / Board Theme Picker with Settings pointer tip, 3. Optional Lichess/Chess.com quick connect with 1-tap Skip), persisted via `brilly_has_completed_onboarding` and re-openable anytime from **Settings → Quick Start & Theme Guide**.

### Verified
- `cd ios && ./scripts/build-ipa.sh --unsigned --edition both`: `starterCourses.json` parity clean, `swift test` **6 suites, 36 tests passed**, BOTH `BrillyDer` (`com.brillyder.app`) and `BrillyDerAdmin` (`com.brillyder.admin`) Release `arm64` builds succeeded and verified `brilly_buddy_thumbsup.png` & `brilly_buddy_blunder.png` bundled.

---

## v2.11.0 (Hold-to-Turbo Scrubbing, Press-and-Hold Power Shortcuts & Emoji-Style 👍/🤦 Badges)
**Status:** Completed & Verified

### Built
- **Native Emoji-Style `👍` / `🤦` Reaction Medallions (`BrillyGhibliBuddyView.swift`):** Replaced AI-generated portraits with crisp native Apple emoji badges (`👍` + glowing sparkles for positive moves; `🤦` + comic shock lines & sweat drop for blunders) and removed ~300KB of unused PNG assets.
- **Hold-to-Turbo Move Scrubbing (`BrillyTurboStepButton` in `LiquidGlassModifiers.swift` & `AnalyzeTabView.swift`):**
  - Tap `<` / `>` for single ply; **press & hold (`>= 260ms`)** to engage progressive turbo scrubbing (`110ms` -> `65ms` -> `40ms` per ply) with glowing double-chevron feedback (`chevron.left.2` / `chevron.right.2`), subtle tactile ticks every 3rd ply, and suppressed celebration spam while scrubbing.
- **Additional Tactile Press-and-Hold Shortcuts (`AnalyzeTabView.swift`, `GamesTabView.swift`):**
  - **Hold `|<` / `>|`** in Analyze header to jump straight to the **Previous / Next Key Moment** (`!!` Brilliant, `?` Mistake, or `??` Blunder).
  - **Tap `1x / 2x / 3x`** for Turbo Auto-Play (`280ms/ply`), or **hold** to snap back to `1x`.
  - **Tap White/Black accuracy pills** to flip the board to that player's side; **hold** to copy their username.
  - **Press & hold any game row** in `Games` for a native iOS context menu (`Analyze / Open`, `Scout Opponent`, `Copy PGN`).

### Verified
- `cd ios && ./scripts/build-ipa.sh --unsigned --edition both`: `starterCourses.json` parity clean, `swift test` **6 suites, 36 tests passed**, BOTH `BrillyDer` (`com.brillyder.app`) and `BrillyDerAdmin` (`com.brillyder.admin`) Release `arm64` builds succeeded + passed `verify_app_bundle()`.

---

## v2.11.3 (Final Pre-App-Store Polish: Official Support Email, Native `requestReview`, Paywall Copy & Solo-Dev Credit)
**Status:** Completed & Verified

### Built
- **Official Support Email (`brillyder@gmail.com`):** Added clickable `mailto:brillyder@gmail.com` links across `public/support.html`, `public/privacy.html`, `public/terms.html`, `CockpitSettingsSheet` (About section), and `BrillyPrivacySheet`.
- **Native StoreKit In-App Review Prompt (`BrillyAppStore.swift`, `BrillyDerRootView.swift`, `ShareCardRenderer.swift`, `CockpitSettingsSheet.swift`):** Added respectful once-per-version `requestReview()` prompting on `BrillyDer` (skipped on `BrillyDerAdmin` and deferred until no sheet is active) after positive milestones (2nd completed Daily Coach session, 3-day streak, saving a `!!` Brilliant bookmark, or exporting a Share Card), plus a **"Rate BrillyDer"** button in Settings → About.
- **Paywall Benefits & Solo-Dev Credit (`BrillyProPaywallSheet.swift`, `CockpitSettingsSheet.swift`):** Added **Pro Emoji Packs (`🔥/💀`, `👍/🤡`, `👑/🫠`) & Custom Share Card Captions** to the Pro paywall benefits card and added `"Crafted independently by Luke Dunwell"` in Settings → About.

### Verified
- `npm test && npm run build`: **21 test files, 102 tests passed** + Vite production build clean (including updated `public/support.html`, `privacy.html`, `terms.html`).
- `cd ios && ./scripts/build-ipa.sh --unsigned --edition both`: `starterCourses.json` parity clean, `swift test` **6 suites, 36 tests passed**, BOTH `BrillyDer` (`com.brillyder.app`) and `BrillyDerAdmin` (`com.brillyder.admin`) Release `arm64` builds (`v2.11.3`, build `15`) succeeded + passed `verify_app_bundle()`.
