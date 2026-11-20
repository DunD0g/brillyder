# BrillyDer v2.0 — Product & Engineering Master Blueprint

## 0. Context & Architectural Constraints
BrillyDer is a local-first, mobile-friendly chess training, evaluation, and analysis web app (PWA) powered by on-device Stockfish WASM, syncing games from Lichess and Chess.com.
- **Core Philosophy:** Maximum chess improvement per minute spent. Zero fluff, zero server dependency where client-side works, 100% personalized to the user's actual games and rating band.
- **Data Storage:** Persist all user data (games, analysis, FSRS scheduling states, repertoires, frozen Woodpecker cycles, stats) in **IndexedDB** (with JSON export/import backup).
- **External APIs (Free, Client-Side):**
  - Lichess Games API & Chess.com Published-Data API (existing).
  - Lichess Opening Explorer API (`https://explorer.lichess.ovh/lichess`) filtered by `ratings` (matching user's rating band) and `speeds` (matching user's time control), with graceful local ECO fallback.
  - Lichess Endgame Tablebase API (`https://tablebase.lichess.ovh/standard`) for exact 7-piece Syzygy endgame evaluations.
- **Key Libraries to Add:**
  - `ts-fsrs` (TypeScript FSRS spaced repetition scheduler; use v6 on Node >= 24 or v5 on Node 20/22).
  - `idb` or `dexie` (IndexedDB wrapper).
  - Optional Sprint 4: `onnxruntime-web` + quantized Maia ONNX models (`public/models/maia-*.onnx`) for realistic human-like sparring.

---

## 1. Flagship Upgrade: Full Opening Prep, Courses & Repertoire Engine
Create a dedicated **Openings** tab (consolidating bottom navigation cleanly into: `Games | Analyze | Openings | Train | Insights`, moving `Vault` into the existing top-right Diamond counter pill modal).

### 1.1 Repertoire Builder & "Coverage Score"
- **Side-specific Repertoires:** Separate trees for **White** and **Black**, organized into named courses/repertoires (e.g., *London System*, *Modern Defense*, *Anti-London & Zukertort*, *Jobava London*).
- **PGN / Lichess Study Importer + Built-in Starter Courses:**
  - Import any PGN or Lichess Study URL into a repertoire tree.
  - Hydrate bundled starter courses from `src/data/starterCourses.json` via `chess.js`.
- **Real-World Coverage Score:**
  - Query Lichess Explorer API filtered to the user's rating bracket & time control.
  - Calculate **Expected Coverage %**: What percentage of real opponent replies at the user's rating are covered by the repertoire down to a configurable probability threshold (default: cover opponent moves played >= 5% down to cumulative line probability >= 2%).
  - **"Patch Gap" Button:** Highlight the #1 most common uncovered opponent reply at the user's rating, show Stockfish's top 3 candidate replies + human win-rate stats from Lichess Explorer, and allow 1-click addition to the repertoire.

### 1.2 Interactive Lesson Mode ("Learn" before "Drill")
1. **Concept Card (Mothership Formation):** Show the target setup, key pawn structure, ideal piece squares (highlighted via colored SVG arrows/squares on the board), and 3 bullet-point middlegame plans.
2. **Guided Walkthrough:** Step through the mainline explaining *why* each move is played (using course annotations or auto-generated rule-based explanations from Stockfish MultiPV).
3. **Trap & Punishment Spotlight:** Show common mistakes/blunders and animate refutations.
4. **Unlock Drill:** Completing the walkthrough activates those move-nodes in the user's **FSRS Review Queue**.

### 1.3 FSRS Spaced Repetition Drill Engine (`ts-fsrs`)
- **Card Unit:** Each user-move decision point `(position_fen, expected_uci)` is an FSRS card.
- **Smart Auto-Grading:**
  - Wrong move -> `Again` (show visual arrow + `wrongMoveTraps` punishment animation if matched, then require immediate retry).
  - Correct on 1st try, slow (>10s) or hint used -> `Hard`.
  - Correct on 1st try, normal (3–10s) -> `Good`.
  - Correct on 1st try, instant (<3s) -> `Easy`.
- **Training Modes:**
  1. **Due Reviews (FSRS):** Daily due cards, interleaved across lines.
  2. **Weakest Lines First:** Sort by lowest First-Try Accuracy or highest real-game eval loss.
  3. **Opening Sparring (Play-Out Mode):** Bot plays opponent moves weighted by real Lichess rating-band frequencies; once out of book, continue 5–10 middlegame moves against a rating-matched bot.

### 1.4 Automatic Game-to-Repertoire Deviation Detector ("Leak Patcher")
- Whenever a game is analyzed in `Games` / `Analyze`:
  - Compare the first 12 moves against the user's active repertoire tree.
  - *User Deviation:* Flag exact move & eval drop -> 1-click **"Boost to Today's FSRS Queue"** (sets card `due = now`).
  - *Opponent Novelty / Gap:* Flag uncovered opponent move -> 1-click **"Patch Gap in Repertoire"**.
- **Opening Report Card:** Group analyzed games by ECO/Opening with Games Played, W/D/L %, Avg Eval at Move 10, and Most Costly Recurring Position.

---

## 2. Upgrade the "Train" Tab: The 15-Minute High-ROI Daily Coach Loop

### 2.1 Daily Workout Generator (Configurable: 10 / 15 / 25 mins)
Compose a 4-stage daily session with a glowing Tractor Beam progress bar:
1. **Stage 1: Opening Due Cards** (5–10 FSRS opening positions + recent game deviations).
2. **Stage 2: Blunder Rewind ("Worst First")** (3–5 costliest mistakes from the last 14 days, with optional Radar Ping pre-step).
3. **Stage 3: Frozen Woodpecker Cycle** (10–15 puzzles from the active frozen cycle).
4. **Stage 4: Targeted Weakness Drill** (Rotates between **Advantage Conversion**, **Weakest Endgame**, and **Missed Motif Drill**).

### 2.2 Fix the Woodpecker Deck (True Cycle Architecture)
- **Create Frozen Cycle:** User selects a fixed batch size (**30, 50, or 100 puzzles**) drawn from their own mistakes (filtered to solvable difficulty: eval swing >= 1.5, excluding obscure deep engine-only lines).
- **Cycle Tracking:** Track **Cycle # (1 to 7)**, **Total Time**, **Accuracy %**, and **First-Try Rate** (0 wrong moves & 0 hints).
- **Mandatory Consolidation Cooldown:** Recommend a 24–48h rest between cycles (countdown badge, overridable).
- **Speed-Up Chart:** Visualize time & accuracy improvements across cycles.

### 2.3 Advantage Conversion ("Tractor Beam") & Endgame Trainer
- **Blown-Lead Replay:** Extract positions from user games where eval hit >= +2.5 (or <= -2.5 as Black) and later drew/lost. Replay against a rating-capped Stockfish (or Maia) bot until mate / +8.0 without dropping below +1.5.
- **Endgame Weakness Tracker:** Classify endgames (`Rook`, `Pawn`, `Minor Piece`, `Queen`, `Rook+Minor`), compute accuracy per category, and integrate `tablebase.lichess.ovh` for exact <=7-piece WDL feedback.

### 2.4 Tactical Motif Classifier (Pattern Drills)
- Tag missed tactics from user games via board-state heuristics + Stockfish PV: `Hanging Piece`, `Fork`, `Pin/Skewer`, `Back-Rank Mate`, `Discovered Attack`, `Deflection`, `Mate in 1–3`, `Only Move Save`.
- Display a **"Patterns You Miss Most"** breakdown with 1-click Motif Drills.

---

## 3. Upgrade the "Analyze" Tab: Plain-English Coach & Deeper Signals
- **Rule-Based Plain-English Move Explanations:** Combine MultiPV (top 3 lines) + tactical detector to generate concise human explanations (e.g., *"Allows a knight fork on c2"*, *"Leaves e6 undefended"*, *"Only move to stop Qxh7+"*).
- **Forced vs. Critical Move Distinction:** Use MultiPV gap (`eval(best) - eval(second_best)`). Gap >= 2.0 flags a **Critical Moment**; finding it under pressure earns a **Clutch Save** badge.
- **Time-Management Overlay (Clock Leaks):** Parse `[%clk ...]` tags from PGNs to plot Time Spent vs. Eval Swing, flagging **Impulse Blunders** (<5s spent with >3m left) vs **Time-Trouble Blunders** (<60s left).

---

## 4. Upgrade "Insights" & "Brilly Vault"
- **Actionable Insights:** Every metric card gets a 1-click **"Train This"** CTA (e.g., Blown Leads -> Advantage Conversion; 6L Streak -> Tilt Guard win-rate curve by consecutive losses + stop-loss rule).
- **20-Game Checkpoints:** Compare the last 20 rated games against the previous 20 on key focus metrics (Avg Eval at Move 10, Impulse Blunders/Game, Blown Lead %).
- **Expanded Brilly Vault (Top-Right Diamond Modal):** Tabs for `!! Brilliant`, `Clutch Saves`, `Traps Punished`, and `Clean Sweeps`.

---

## 5. Technical Polish & Optimization
- **Two-Pass Stockfish Worker:** Fast pass (`D12`–`D14`, MultiPV=2) for batch analysis, automatically deepening (`D18`, MultiPV=3) *only* on turning points (eval swing >= 1.0) to save battery and cut analysis time.
- **Offline-First & Full Backup:** JSON Export/Import of the entire IndexedDB store in Settings.
