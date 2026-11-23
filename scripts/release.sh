#!/usr/bin/env bash
#
# release.sh — build the release APK, generate version.json (auto-update) and
# upload to your hosting via FTP (uses curl, always available).
#
# Configuration: copy .deploy.env.example to .deploy.env and fill it in
# (UPDATE_URL, APK_URL, ARUBA_FTP_*). The password is passed at runtime.
#
# Usage:
#   ./scripts/release.sh                         # build + version.json in site/
#   ARUBA_FTP_PASS="..." ./scripts/release.sh --upload   # build + FTP upload
#
# Release notes: set them in UPDATE_NOTES (otherwise the ones already present in
# site/version.json are kept).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Load local configuration if present.
if [[ -f .deploy.env ]]; then
  # shellcheck disable=SC1091
  source .deploy.env
fi

UPDATE_URL="${UPDATE_URL:-}"
APK_URL="${APK_URL:-}"

echo "==> Building release APK"
if [[ -n "$UPDATE_URL" ]]; then
  echo "    auto-update: ON ($UPDATE_URL)"
  flutter build apk --release --dart-define=UPDATE_URL="$UPDATE_URL"
else
  echo "    auto-update: OFF (UPDATE_URL not set)"
  flutter build apk --release
fi

mkdir -p site
cp build/app/outputs/flutter-apk/app-release.apk site/reel-saver.apk
SIZE_MB=$(( $(stat -f%z site/reel-saver.apk 2>/dev/null || stat -c%s site/reel-saver.apk) / 1024 / 1024 ))
echo "    APK ready: site/reel-saver.apk (~${SIZE_MB} MB)"

if [[ -n "$APK_URL" ]]; then
  echo "==> Updating site/version.json from pubspec"
  APK_URL="$APK_URL" UPDATE_NOTES="${UPDATE_NOTES:-}" python3 - <<'PY'
import json, os, re
ver = None
for line in open('pubspec.yaml', encoding='utf-8'):
    m = re.match(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)', line.strip())
    if m:
        ver = (m.group(1), int(m.group(2)))
        break
if not ver:
    raise SystemExit('Version not found in pubspec.yaml (expected x.y.z+n)')
name, code = ver
notes = (os.environ.get('UPDATE_NOTES') or '').replace('\\n', '\n')
path = 'site/version.json'
if not notes and os.path.exists(path):
    try:
        notes = json.load(open(path, encoding='utf-8')).get('notes', '')
    except Exception:
        notes = ''
data = {'versionCode': code, 'versionName': name,
        'apkUrl': os.environ['APK_URL'], 'notes': notes}
json.dump(data, open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print(f'    version.json -> versionName={name} versionCode={code}')
PY
else
  echo "==> APK_URL not set: skipping version.json (auto-update not published)"
fi

if [[ "${1:-}" != "--upload" ]]; then
  echo "==> No upload (pass --upload to upload via FTP)."
  echo "    Upload the contents of site/ to your hosting manually."
  exit 0
fi

: "${ARUBA_FTP_HOST:?ARUBA_FTP_HOST is required (in .deploy.env)}"
: "${ARUBA_FTP_DIR:?ARUBA_FTP_DIR is required (in .deploy.env)}"
: "${ARUBA_FTP_USER:?ARUBA_FTP_USER is required (in .deploy.env)}"
: "${ARUBA_FTP_PASS:?ARUBA_FTP_PASS is required (pass it at runtime)}"

echo "==> Uploading to $ARUBA_FTP_HOST$ARUBA_FTP_DIR via FTP"
up() {
  [[ -f "site/$1" ]] || return 0
  curl -sS --ftp-create-dirs -u "$ARUBA_FTP_USER:$ARUBA_FTP_PASS" \
    -T "site/$1" "ftp://$ARUBA_FTP_HOST$ARUBA_FTP_DIR/$1"
  echo "    OK $1"
}
up index.html
up .htaccess
up icon.png
up version.json
up reel-saver.apk
echo "==> Done."
