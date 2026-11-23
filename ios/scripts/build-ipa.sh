#!/usr/bin/env bash
set -euo pipefail

# Build a local BrillyDer iOS .ipa using Xcode 26.
# Usage:
#   ./scripts/build-ipa.sh --unsigned [--skip-tests]
#   ./scripts/build-ipa.sh --app-store --team-id YOUR_TEAM_ID [--skip-tests]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_DIR/.." && pwd)"
cd "$IOS_DIR"

MODE="unsigned"
TEAM_ID=""
SKIP_TESTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --unsigned) MODE="unsigned"; shift ;;
    --app-store) MODE="app-store"; shift ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    --team-id)
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "Error: --team-id requires a non-empty value."
        exit 1
      fi
      TEAM_ID="$2"
      shift 2
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -f "$REPO_ROOT/src/data/starterCourses.json" ]]; then
  echo "Verifying starterCourses.json parity with Web PWA..."
  diff -u "$REPO_ROOT/src/data/starterCourses.json" "$IOS_DIR/Sources/BrillyDerCore/Resources/starterCourses.json"
fi

if [[ "$SKIP_TESTS" -eq 0 ]]; then
  echo "Running BrillyDerCore Swift unit tests..."
  swift test
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing xcodegen via Homebrew..."
  HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
fi

echo "Generating BrillyDer.xcodeproj..."
xcodegen generate

if [[ "$MODE" == "unsigned" ]]; then
  echo "Building unsigned Release .ipa for generic/platform=iOS..."
  xcodebuild build \
    -project BrillyDer.xcodeproj \
    -scheme BrillyDer \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath build/DerivedData \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    AD_HOC_CODE_SIGNING_ALLOWED=NO

  APP_PATH="build/DerivedData/Build/Products/Release-iphoneos/BrillyDer.app"
  /usr/libexec/PlistBuddy -c "Print :UILaunchScreen" "$APP_PATH/Info.plist" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :NSPhotoLibraryAddUsageDescription" "$APP_PATH/Info.plist" >/dev/null
  find "$APP_PATH" -name "cburnett_wK.png" | grep -q "cburnett_wK.png"

  rm -rf build/Payload build/BrillyDer-iOS-unsigned.ipa
  mkdir -p build/Payload
  cp -R "$APP_PATH" build/Payload/
  (cd build && zip -r -y BrillyDer-iOS-unsigned.ipa Payload >/dev/null)
  echo "Created: $IOS_DIR/build/BrillyDer-iOS-unsigned.ipa"
else
  if [[ -z "$TEAM_ID" ]]; then
    echo "Error: --app-store requires --team-id <APPLE_TEAM_ID>"
    exit 1
  fi
  echo "Archiving signed App Store / TestFlight .ipa..."
  rm -rf build/BrillyDer.xcarchive build/export
  xcodebuild archive \
    -project BrillyDer.xcodeproj \
    -scheme BrillyDer \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath build/BrillyDer.xcarchive \
    DEVELOPMENT_TEAM="$TEAM_ID"

  TEMP_EXPORT_PLIST="$(mktemp -t brillyder-export.XXXXXX.plist)"
  trap 'rm -f "$TEMP_EXPORT_PLIST"' EXIT
  cp ExportOptions.plist "$TEMP_EXPORT_PLIST"
  /usr/libexec/PlistBuddy -c "Delete :teamID" "$TEMP_EXPORT_PLIST" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$TEMP_EXPORT_PLIST"

  xcodebuild -exportArchive \
    -archivePath build/BrillyDer.xcarchive \
    -exportPath build/export \
    -exportOptionsPlist "$TEMP_EXPORT_PLIST" \
    -allowProvisioningUpdates

  echo "Exported signed .ipa to: $IOS_DIR/build/export/"
fi
