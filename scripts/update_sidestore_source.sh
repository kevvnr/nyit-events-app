#!/usr/bin/env bash
set -euo pipefail

SOURCE_FILE="public/apps.json"
VERSION=""
VERSION_DATE="$(date +%F)"
VERSION_DESCRIPTION=""
DOWNLOAD_URL=""
IPA_PATH=""
SIZE_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/update_sidestore_source.sh \
    --version 1.5.1 \
    --description "• Item one\n• Item two" \
    --download-url "https://github.com/.../releases/download/.../CampusApp.ipa" \
    [--ipa build/ios/ipa/CampusApp.ipa | --size 12345678] \
    [--date YYYY-MM-DD] \
    [--file public/apps.json | --file sidestore/apps.json]

What it updates (first app in apps.json):
  - version
  - versionDate
  - versionDescription
  - downloadURL
  - size
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --date)
      VERSION_DATE="$2"
      shift 2
      ;;
    --description)
      VERSION_DESCRIPTION="$2"
      shift 2
      ;;
    --download-url)
      DOWNLOAD_URL="$2"
      shift 2
      ;;
    --ipa)
      IPA_PATH="$2"
      shift 2
      ;;
    --size)
      SIZE_OVERRIDE="$2"
      shift 2
      ;;
    --file)
      SOURCE_FILE="$2"
      shift 2
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

if [[ -z "$VERSION" || -z "$VERSION_DESCRIPTION" || -z "$DOWNLOAD_URL" ]]; then
  echo "Error: --version, --description, and --download-url are required." >&2
  usage
  exit 1
fi

dl_lower="$(printf '%s' "$DOWNLOAD_URL" | tr '[:upper:]' '[:lower:]')"
if [[ "$dl_lower" == *paste_* ]] || [[ "$dl_lower" == *your_* ]] || [[ "$dl_lower" == *example.com* ]] || [[ "$DOWNLOAD_URL" != http* ]]; then
  echo "Error: --download-url looks like a placeholder. Use the real GitHub Release asset URL (right-click the IPA on the release page → Copy link)." >&2
  exit 1
fi

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "Error: source file not found: $SOURCE_FILE" >&2
  exit 1
fi

SIZE_VALUE=""
if [[ -n "$SIZE_OVERRIDE" ]]; then
  SIZE_VALUE="$SIZE_OVERRIDE"
elif [[ -n "$IPA_PATH" ]]; then
  if [[ ! -f "$IPA_PATH" ]]; then
    echo "Error: IPA file not found: $IPA_PATH" >&2
    exit 1
  fi
  # macOS/BSD stat
  SIZE_VALUE="$(stat -f%z "$IPA_PATH")"
else
  echo "Error: provide --ipa or --size so apps.json gets a real size." >&2
  exit 1
fi

python3 - "$SOURCE_FILE" "$VERSION" "$VERSION_DATE" "$VERSION_DESCRIPTION" "$DOWNLOAD_URL" "$SIZE_VALUE" <<'PY'
import json
import sys

source_file = sys.argv[1]
version = sys.argv[2]
version_date = sys.argv[3]
version_description = sys.argv[4]
download_url = sys.argv[5]
size_value = int(sys.argv[6])

with open(source_file, "r", encoding="utf-8") as f:
    data = json.load(f)

apps = data.get("apps", [])
if not apps:
    raise SystemExit("apps.json has no apps[] entries")

app = apps[0]
vers = app.get("versions")
if isinstance(vers, list) and len(vers) > 0 and isinstance(vers[0], dict):
    entry = vers[0]
    entry["version"] = version
    entry["date"] = version_date
    entry["localizedDescription"] = version_description
    entry["downloadURL"] = download_url
    entry["size"] = size_value
elif isinstance(vers, list) and len(vers) == 0:
    app["versions"] = [
        {
            "version": version,
            "date": version_date,
            "localizedDescription": version_description,
            "downloadURL": download_url,
            "size": size_value,
        }
    ]
else:
    app["version"] = version
    app["versionDate"] = version_date
    app["versionDescription"] = version_description
    app["downloadURL"] = download_url
    app["size"] = size_value

with open(source_file, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

echo "Updated $SOURCE_FILE"
echo "  version: $VERSION"
echo "  date: $VERSION_DATE"
echo "  downloadURL: $DOWNLOAD_URL"
echo "  size: $SIZE_VALUE"
