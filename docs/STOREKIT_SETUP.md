# BrillyDer StoreKit 2 & Dual-Edition Setup Guide

BrillyDer ships **two synchronized iOS targets** from the exact same `main` branch (`BrillyDerCore` + `BrillyDerUI`), so every feature and bug fix updates both apps automatically with zero branch drift:

| Edition | Xcode Scheme | Bundle Identifier | Pro Access | Distribution |
|---|---|---|---|---|
| **BrillyDer (App Store)** | `BrillyDer` | `com.brillyder.app` | Pure **StoreKit 2** (`Product.purchase()`, `Transaction.currentEntitlements`, `AppStore.sync()`) | App Store / TestFlight (`./scripts/build-ipa.sh --app-store --team-id <TEAM>`) |
| **BrillyDer Admin (Founder)** | `BrillyDerAdmin` | `com.brillyder.admin` | Permanently unlocked (`BRILLY_ADMIN_EDITION`), plus optional *Simulate Free Tier* toggle in Settings | Personal sideload via AltStore / SideStore / Xcode (`BrillyDer-Admin-iOS-unsigned.ipa`) — installs side-by-side next to the App Store app! |

---

## 1. Free vs. Pro Boundaries (`BrillyDer` App Store Target)

| Feature | Free | Brilly/Der Pro |
|---|---|---|
| Lichess & Chess.com Sync | Unlimited | Unlimited |
| Re-opening Already-Analyzed Games | Unlimited | Unlimited |
| New On-Device Game Analyses | 5 per day | Unlimited + Batch Analyze (5 / 10 / All) |
| Daily Orbit Coach & Warmup | 10m Coach + 60s Gravity Check + Mistake Deck | 10m, 15m & 25m Orbit Coach + Woodpecker Cycles + Advantage Conversion |
| Opening Courses | 2 Starter Courses (*London System* + *Modern Defense*) | All 8 Starter Courses + Unlimited Custom PGN Imports |
| Endgame & Vision Labs | — | 12 Syzygy Endgames, Board Vision & Puzzle Rush |
| Retina Chess Piece Sets | Classic (`cburnett`) | All 4 Sets (`cburnett`, `chessnut`, `spatial`, `kiwen-suwi`) |

---

## 2. App Store Connect Product Registration Checklist

Create these exact 3 products in **App Store Connect → BrillyDer (`com.brillyder.app`)**:

### A. Subscription Group: `BrillyDer Pro`
1. **Annual (`com.brillyder.pro.annual`)** — Level 1 (Highest)
   - Duration: `1 Year`
   - Price: `£24.99` (or your preferred base territory price — StoreKit 2 auto-localizes display prices worldwide)
   - **Introductory Offer:** `Free Trial`, Duration: `1 Week` (`7 days`), All Territories
2. **Monthly (`com.brillyder.pro.monthly`)** — Level 2
   - Duration: `1 Month`
   - Price: `£3.99`

### B. Non-Consumable In-App Purchase
3. **Lifetime (`com.brillyder.pro.lifetime`)**
   - Type: `Non-Consumable`
   - Price: `£39.99`
   - Family Sharing: Enabled (optional)

### C. Required App Store Connect URLs (already hosted via GitHub Pages)
- **Privacy Policy URL:** `https://dund0g.github.io/brillyder/privacy.html`
- **Support URL:** `https://dund0g.github.io/brillyder/support.html`
- **Terms of Use URL (for App Description / Metadata):** `https://dund0g.github.io/brillyder/terms.html`

> **Important for First Submission:** Attach all 3 IAP products directly to your first App Store version submission inside App Store Connect (under *In-App Purchases and Subscriptions*) so Apple Review approves them alongside the binary.

---

## 3. Testing Locally Before App Store Connect Approval

1. Generate the Xcode project:
   ```bash
   cd ios && xcodegen generate && open BrillyDer.xcodeproj
   ```
2. Select scheme **`BrillyDer`** — it is already linked to `ios/BrillyDer.storekit` (pre-configured with Monthly, Annual + 7-day trial, and Lifetime).
3. Run on Simulator or your iPhone (`⌘R`) and test:
   - Free tier quota (5 analyses/day, 10m Coach, 2 openings, `cburnett` piece set)
   - Tapping any locked feature -> opens live StoreKit 2 paywall
   - Purchasing Annual (7-day trial), Monthly, or Lifetime via Xcode's local StoreKit sheet
   - Tapping **Restore Purchases** and inspecting Xcode's **Debug → StoreKit → Manage Transactions** to test renewals & refunds!
4. Select scheme **`BrillyDerAdmin`** (or download `BrillyDer-Admin-iOS-unsigned.ipa` from GitHub Actions) to run your personal permanently-unlocked **BrillyDer Admin** app side-by-side on your iPhone!
