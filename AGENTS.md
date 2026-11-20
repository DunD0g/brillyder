# BrillyDer — Agent Rules & Engineering Constraints

## Product Architecture
- **Local-First PWA:** Never introduce paid APIs, backend servers, or mandatory auth. All persistence lives in IndexedDB with JSON export/import backup.
- **Engine Integrity:** Do not break the existing client-side Stockfish WASM worker or Lichess/Chess.com sync pipeline.
- **Zero Illegal Chess Moves:** Any opening course or puzzle data added to `src/data/starterCourses.json` MUST be validated by a `chess.js` unit test (`npm test`) that replays every `moves`, `previewMoves`, and `punishmentLine` sequence to guarantee 100% legal SAN.

## UI & Theme Standards ("Cosmic Minimalist")
- Preserve the dark glassmorphic palette (`--bg-void: #070B14`, `--bg-hull: #0F172A`, `--accent-brilly: #2DD4BF`, `--accent-warp: #A855F7`, `--accent-blunder: #FB7185`).
- Keep the chessboard high-contrast, uncluttered, and thumb-friendly on mobile (iOS Safari / PWA safe areas).
- Maintain a `Vibe: Cosmic | Classic` toggle in Settings so witty space-probe copy cleanly falls back to standard chess labels.

## Execution Rules
- Before editing code, inspect existing components and types so you extend rather than duplicate state stores or board components.
- Execute systematically phase-by-phase, running typechecks/tests after each phase before moving to the next.
- Update `docs/SPRINT_TRACKER.md` as each sprint completes with what was built, verified, and any remaining follow-ups.
