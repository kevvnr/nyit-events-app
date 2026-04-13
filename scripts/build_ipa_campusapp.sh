#!/usr/bin/env bash
# Signed development IPA (Personal Team) → always leaves build/ios/ipa/CampusApp.ipa
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EXPORT_PLIST="${EXPORT_PLIST:-ios/ExportOptions-development.plist}"
IPA_DIR="$ROOT/build/ios/ipa"
OUT_NAME="CampusApp.ipa"
OUT_PATH="$IPA_DIR/$OUT_NAME"

echo "==> flutter pub get"
flutter pub get

if [[ -f "$ROOT/ios/Podfile" ]]; then
  echo "==> pod install (ios)"
  (cd "$ROOT/ios" && pod install)
fi

echo "==> flutter build ipa (signed, export: $EXPORT_PLIST)"
flutter build ipa --export-options-plist="$EXPORT_PLIST"

mkdir -p "$IPA_DIR"
shopt -s nullglob
candidates=("$IPA_DIR"/*.ipa)
newest=""
for f in "${candidates[@]}"; do
  if [[ -z "$newest" ]] || [[ "$f" -nt "$newest" ]]; then
    newest="$f"
  fi
done

if [[ -z "$newest" ]]; then
  echo "ERROR: No .ipa found in $IPA_DIR after build." >&2
  exit 1
fi

if [[ "$(basename "$newest")" == "$OUT_NAME" ]]; then
  echo ""
  echo "✅ Release IPA: $OUT_PATH"
  exit 0
fi

mv -f "$newest" "$OUT_PATH"
echo ""
echo "✅ Release IPA: $OUT_PATH"
