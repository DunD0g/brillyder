#!/usr/bin/env bash
set -euo pipefail

# Build a local BrillyDer iOS .ipa using Xcode 26.
# Usage:
#   ./scripts/build-ipa.sh --unsigned
#   ./scripts/build-ipa.sh --app-store --team-id YOUR_TEAM_ID

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$IOS_DIR"

MODE="unsigned"
TEAM_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --unsigned) MODE="unsigned"; shift ;;
    --app-store) MODE="app-store"; shift ;;
    --team-id) TEAM_ID="${2:-}"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing xcodegen via Homebrew..."
  brew install xcodegen
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

  rm -rf build/Payload build/BrillyDer-iOS-unsigned.ipa
  mkdir -p build/Payload
  cp -R build/DerivedData/Build/Products/Release-iphoneos/BrillyDer.app build/Payload/
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

  xcodebuild -exportArchive \
    -archivePath build/BrillyDer.xcarchive \
    -exportPath build/export \
    -exportOptionsPlist ExportOptions.plist \
    -allowProvisioningUpdates

  echo "Exported signed .ipa to: $IOS_DIR/build/export/"
fi
