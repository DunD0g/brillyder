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
