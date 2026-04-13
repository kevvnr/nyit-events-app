#!/usr/bin/env bash
# Unsigned release build (no Apple codesign). SideStore / AltStore can sign on install.
# Output: build/ios/ipa/CampusApp_unsigned.ipa
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IPA_DIR="$ROOT/build/ios/ipa"
DEFAULT_OUT="$IPA_DIR/CampusApp_unsigned.ipa"
OUTPUT_IPA="${OUTPUT_IPA:-$DEFAULT_OUT}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-edu.nyit.campusevents}"
SKIP_CLEAN="${SKIP_CLEAN:-0}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build_ipa_campusapp_unsigned.sh [--output path/CampusApp_unsigned.ipa] [--bundle-id edu.nyit.campusevents] [--skip-clean]

Environment:
  OUTPUT_IPA=path/to/file.ipa   (default: build/ios/ipa/CampusApp_unsigned.ipa)
  EXPECTED_BUNDLE_ID=…
  SKIP_CLEAN=1

Steps:
  flutter clean (optional) → pub get → pod install → flutter build ios --release --no-codesign → zip Payload/Runner.app
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_IPA="$2"
      shift 2
      ;;
    --bundle-id)
      EXPECTED_BUNDLE_ID="$2"
      shift 2
      ;;
    --skip-clean)
      SKIP_CLEAN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

mkdir -p "$(dirname "$OUTPUT_IPA")"

echo "==> Building unsigned iOS app (no codesign)"
if [[ "$SKIP_CLEAN" != "1" ]]; then
  flutter clean
fi
flutter pub get

if [[ -f "$ROOT/ios/Podfile" ]]; then
  echo "==> pod install (ios)"
  (cd "$ROOT/ios" && pod install)
fi

flutter build ios --release --no-codesign

echo "==> Packaging IPA → $OUTPUT_IPA"
rm -rf Payload .tmp_ipa_unsigned
mkdir Payload
cp -R build/ios/iphoneos/Runner.app Payload/
zip -qr "$OUTPUT_IPA" Payload
rm -rf Payload

echo "==> Verifying IPA metadata"
mkdir .tmp_ipa_unsigned
unzip -q "$OUTPUT_IPA" -d .tmp_ipa_unsigned
INFO_PLIST=".tmp_ipa_unsigned/Payload/Runner.app/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
VERSION_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
IPA_SIZE="$(stat -f%z "$OUTPUT_IPA")"

echo "Bundle ID: $BUNDLE_ID"
echo "Version:   $VERSION_NAME"
echo "Build:     $BUILD_NUMBER"
echo "Size:      $IPA_SIZE bytes"

if [[ "$BUNDLE_ID" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "ERROR: Bundle ID mismatch. Expected '$EXPECTED_BUNDLE_ID' but got '$BUNDLE_ID'." >&2
  rm -rf .tmp_ipa_unsigned
  exit 2
fi

rm -rf .tmp_ipa_unsigned
echo ""
echo "✅ Unsigned IPA: $OUTPUT_IPA"
