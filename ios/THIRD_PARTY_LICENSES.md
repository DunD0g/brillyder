# BrillyDer iOS — Third-Party Software & Asset Licenses

BrillyDer's native iOS app has **zero GPL/AGPL dependencies**. All bundled engines and chess piece graphics are sourced under permissive App-Store-compatible licenses:

## Chess Engine & Algorithms

1. **Renegade Chess Engine (v1.3.1 + Self-Play NNUE `renegade-net-36.bin`)**
   - **Author:** Copyright © 2022–2026 Krisztián Peőcz (`pkrisz99/Renegade`)
   - **License:** MIT License (full text bundled at `ios/Sources/CRenegadeEngine/LICENSE`)
   - **Source:** https://github.com/pkrisz99/Renegade

2. **FSRS-6 Spaced Repetition & PeSTO Evaluation Reference**
   - **Algorithm Credits:** FSRS-6 (Free Spaced Repetition Scheduler, MIT) and PeSTO tapered piece-square evaluation reference for the pure-Swift interactive fallback engine.

## Bundled Chess Piece Artwork

1. **Classic (`cburnett`)**
   - **Author:** Colin M.L. Burnett (Wikimedia Commons `File:Chess_*t45.svg`)
   - **License:** BSD-3-Clause (multi-licensed under BSD / GFDL / GPL on Wikimedia Commons; used here under the BSD license)
   - **Source:** https://commons.wikimedia.org/wiki/Category:SVG_chess_pieces

2. **Chessnut (`chessnut`)**
   - **Author:** Alexis Luengas (`LexLuengas/chessnut-pieces`)
   - **License:** Apache License 2.0 (https://www.apache.org/licenses/LICENSE-2.0)
   - **Source:** https://github.com/LexLuengas/chessnut-pieces

3. **Spatial (`spatial`)**
   - **Author:** Maurizio Monge (`maurimo/chess-art`)
   - **License:** MIT License
   - **Source:** https://github.com/maurimo/chess-art

4. **Minimal (`kiwen-suwi`)**
   - **Author:** neverRare
   - **License:** Creative Commons Attribution 4.0 International (CC BY 4.0 — https://creativecommons.org/licenses/by/4.0/)
   - **Source:** https://github.com/lichess-org/lila/tree/master/public/piece/kiwen-suwi

## Optional Public Third-Party APIs & Trademark Notice

BrillyDer optionally queries public HTTPS endpoints from Lichess (`lichess.org`, `lichess.org/api/cloud-eval`, `tablebase.lichess.ovh`) and Chess.com (`api.chess.com`). BrillyDer is an independent application and is not affiliated with, endorsed by, or sponsored by Lichess, Chess.com, or the Stockfish project.
