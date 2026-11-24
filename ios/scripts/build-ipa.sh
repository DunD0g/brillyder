#!/usr/bin/env bash
set -euo pipefail

# Build local BrillyDer iOS .ipa package(s) using Xcode 26.
# Usage:
#   ./scripts/build-ipa.sh --unsigned [--edition both|store|admin] [--skip-tests]
#   ./scripts/build-ipa.sh --app-store --team-id YOUR_TEAM_ID [--skip-tests]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_DIR/.." && pwd)"
cd "$IOS_DIR"

MODE="unsigned"
EDITION="both"
TEAM_ID=""
SKIP_TESTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --unsigned) MODE="unsigned"; shift ;;
    --app-store) MODE="app-store"; shift ;;
    --skip-tests) SKIP_TESTS=1; shift ;;
    --edition)
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == --* ]]; then
        echo "Error: --edition requires one of: both, store, admin."
        exit 1
      fi
      EDITION="$2"
      shift 2
      ;;
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

verify_app_bundle() {
  local app_path="$1"
  local expected_bundle_id="$2"
  echo "Verifying bundle requirements in $app_path ($expected_bundle_id)..."
  local actual_bundle_id
  actual_bundle_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Info.plist")"
  if [[ "$actual_bundle_id" != "$expected_bundle_id" ]]; then
    echo "Error: Expected CFBundleIdentifier=$expected_bundle_id but got $actual_bundle_id"
    exit 1
  fi
  /usr/libexec/PlistBuddy -c "Print :UILaunchScreen" "$app_path/Info.plist" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :NSPhotoLibraryAddUsageDescription" "$app_path/Info.plist" >/dev/null
  /usr/libexec/PlistBuddy -c "Print :ITSAppUsesNonExemptEncryption" "$app_path/Info.plist" >/dev/null
  [[ -f "$app_path/PrivacyInfo.xcprivacy" ]] || { echo "Error: PrivacyInfo.xcprivacy missing in bundle"; exit 1; }
  plutil -lint "$app_path/PrivacyInfo.xcprivacy" >/dev/null
  find "$app_path" -name "starterCourses.json" | grep -q "starterCourses.json"
  find "$app_path" -name "cburnett_wK.png" | grep -q "cburnett_wK.png"
  if [[ -f "$IOS_DIR/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" ]]; then
    sips -g hasAlpha "$IOS_DIR/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" | grep -q "hasAlpha: no"
  fi
  echo "Bundle verification passed for $expected_bundle_id!"
}

build_unsigned_scheme() {
  local scheme="$1"
  local app_name="$2"
  local expected_bundle_id="$3"
  local ipa_name="$4"

  echo "Building unsigned Release $ipa_name ($scheme) for generic/platform=iOS..."
  xcodebuild build \
    -project BrillyDer.xcodeproj \
    -scheme "$scheme" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath build/DerivedData \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    AD_HOC_CODE_SIGNING_ALLOWED=NO

  local app_path="build/DerivedData/Build/Products/Release-iphoneos/${app_name}.app"
  verify_app_bundle "$app_path" "$expected_bundle_id"

  rm -rf build/Payload "build/${ipa_name}"
  mkdir -p build/Payload
  cp -R "$app_path" build/Payload/
  (cd build && zip -r -y "$ipa_name" Payload >/dev/null)
  echo "Created: $IOS_DIR/build/${ipa_name}"
}

if [[ "$MODE" == "unsigned" ]]; then
  case "$EDITION" in
    store)
      build_unsigned_scheme "BrillyDer" "BrillyDer" "com.brillyder.app" "BrillyDer-iOS-unsigned.ipa"
      ;;
    admin)
      build_unsigned_scheme "BrillyDerAdmin" "BrillyDerAdmin" "com.brillyder.admin" "BrillyDer-Admin-iOS-unsigned.ipa"
      ;;
    both)
      build_unsigned_scheme "BrillyDer" "BrillyDer" "com.brillyder.app" "BrillyDer-iOS-unsigned.ipa"
      build_unsigned_scheme "BrillyDerAdmin" "BrillyDerAdmin" "com.brillyder.admin" "BrillyDer-Admin-iOS-unsigned.ipa"
      ;;
    *)
      echo "Error: --edition must be one of: both, store, admin."
      exit 1
      ;;
  esac
else
  if [[ -z "$TEAM_ID" ]]; then
    echo "Error: --app-store requires --team-id <APPLE_TEAM_ID>"
    exit 1
  fi
  echo "Archiving signed App Store / TestFlight .ipa (com.brillyder.app)..."
  rm -rf build/BrillyDer.xcarchive build/export
  xcodebuild archive \
    -project BrillyDer.xcodeproj \
    -scheme BrillyDer \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath build/BrillyDer.xcarchive \
    DEVELOPMENT_TEAM="$TEAM_ID"

  verify_app_bundle "build/BrillyDer.xcarchive/Products/Applications/BrillyDer.app" "com.brillyder.app"

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
