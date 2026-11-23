# BrillyDer Native iOS App (SwiftUI + iOS 26 Liquid Glass)

100% native, local-first Swift 6 / SwiftUI iOS app for **BrillyDer** — engineered for **iOS 26 Liquid Glass** (with a live **Liquid Glass | Cosmic Minimalist** appearance toggle) and **App Store compliance from day 1**.

## Architecture
- **`Sources/BrillyDerCore`** — Pure Swift 6 library (zero GPL dependencies, 100% locally testable via `swift test`):
  - `ChessBoard` (Perft-verified FIDE legal move generator, FEN/SAN/UCI, Zobrist hashing) & `PGNParser`.
  - `BrillyNativeEngine` behind pluggable `ChessEngine` protocol (MIT/original pure-Swift Alpha-Beta + PVS + Quiescence + Transposition Table + PeSTO tapered eval + MultiPV — ready to plug in a permissive MIT C++ NNUE engine like Caissa in Phase 1.5 without touching UI code).
  - `MoveClassifier` (BrillyDer v3 Brilliant/Great/Best/Good/Inaccuracy/Mistake/Blunder/Book + SEE sacrifice checks).
  - `FSRS6Scheduler` + `CourseRepository` (bundles `starterCourses.json` directly from the web repo — zero drift).
  - `LichessClient`, `ChessComClient`, `GameAnalyzer`, `DailyCoachPlanner`, and `LocalVaultStore` (100% cross-compatible with BrillyDer Web PWA `brillyder` `schemaVersion: 2` JSON backups).
- **`Sources/BrillyDerUI`** — Pure SwiftUI interface:
  - Authentic **iOS 26 Liquid Glass** (`glassEffect(_:in:)`, `GlassEffectContainer`, native floating tab bar) with graceful iOS 18 & Reduce Transparency fallback and live **Liquid Glass | Cosmic Minimalist** switcher.
  - Custom 120Hz `InteractiveChessBoardView` (tap + drag, legal dots, coaching arrows, rank-8 safe move badges, dismissible promotion sheet, native haptics — zero `chessground` GPL dependency).
  - All 5 Daily-First Core tabs (`Train`, `Games`, `Analyze`, `Openings`, `Insights`) + `CockpitSettingsSheet`.
- **`App/`** — iOS app entry point & App Store assets:
  - Opaque 1024×1024 RGB `AppIcon-1024.png` (zero alpha channel — passes `ITMS-90717`).
  - `PrivacyInfo.xcprivacy` (declares zero tracking, local-only data).
  - `AVAudioSession` configured as `.ambient` + `.mixWithOthers` (obeys hardware mute switch & never pauses Spotify/podcasts).

## Cloud `.ipa` Build via GitHub Actions (No Local Xcode Required)
Every push affecting `ios/` (or manual **Actions → Build BrillyDer iOS (.ipa) → Run workflow**) compiles the native iOS 26 arm64 binary on GitHub's `macos-26` runner, runs `swift test`, verifies `PrivacyInfo.xcprivacy` + `starterCourses.json`, and uploads **`BrillyDer-iOS-unsigned-ipa`** as a downloadable artifact:
1. Open the repo's **Actions** tab → click the latest **Build BrillyDer iOS (.ipa)** run.
2. Download the **`BrillyDer-iOS-unsigned-ipa`** artifact and unzip it to get `BrillyDer-iOS-unsigned.ipa`.
3. Sideload onto your iPhone with **AltStore**, **SideStore**, or **Sideloadly** (free Apple ID), or sign with your Apple Developer account.

## Running on iPhone / Simulator Locally (Xcode 26)
1. Install **Xcode 26** from the Mac App Store and select it:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```
2. Generate `BrillyDer.xcodeproj` (via [XcodeGen](https://github.com/yonaskolb/XcodeGen)) or run the 1-command `.ipa` builder:
   ```bash
   brew install xcodegen
   cd ios && xcodegen generate
   open BrillyDer.xcodeproj
   ```
   Or build an `.ipa` directly from Terminal:
   ```bash
   cd ios
   ./scripts/build-ipa.sh --unsigned
   # Or signed for TestFlight / App Store Connect:
   ./scripts/build-ipa.sh --app-store --team-id YOUR_TEAM_ID
   ```
3. In Xcode → Signing & Capabilities, choose your Apple Developer Team, pick an iOS 26 Simulator or your plugged-in iPhone, and press **⌘R**!

## Running Swift Unit Tests Locally
```bash
cd ios && swift test
```
(If running with macOS Command Line Tools before installing Xcode, pass `-Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib`.)
