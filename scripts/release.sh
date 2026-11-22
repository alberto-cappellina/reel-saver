#!/usr/bin/env bash
#
# release.sh — build dell'APK release, generazione di version.json (auto-update)
# e caricamento sul tuo hosting via FTP (usa curl, sempre disponibile).
#
# Configurazione: copia .deploy.env.example in .deploy.env e compilalo
# (UPDATE_URL, APK_URL, ARUBA_FTP_*). La password si passa a runtime.
#
# Uso:
#   ./scripts/release.sh                         # build + version.json in site/
#   ARUBA_FTP_PASS="..." ./scripts/release.sh --upload   # build + upload FTP
#
# Note di rilascio: impostale in UPDATE_NOTES (altrimenti si mantengono quelle
# già presenti in site/version.json).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Carica la configurazione locale se presente.
if [[ -f .deploy.env ]]; then
  # shellcheck disable=SC1091
  source .deploy.env
fi

UPDATE_URL="${UPDATE_URL:-}"
APK_URL="${APK_URL:-}"

echo "==> Build APK release"
if [[ -n "$UPDATE_URL" ]]; then
  echo "    auto-update: ON ($UPDATE_URL)"
  flutter build apk --release --dart-define=UPDATE_URL="$UPDATE_URL"
else
  echo "    auto-update: OFF (UPDATE_URL non impostato)"
  flutter build apk --release
fi

mkdir -p site
cp build/app/outputs/flutter-apk/app-release.apk site/reel-saver.apk
SIZE_MB=$(( $(stat -f%z site/reel-saver.apk 2>/dev/null || stat -c%s site/reel-saver.apk) / 1024 / 1024 ))
echo "    APK pronto: site/reel-saver.apk (~${SIZE_MB} MB)"

if [[ -n "$APK_URL" ]]; then
  echo "==> Aggiorno site/version.json dal pubspec"
  APK_URL="$APK_URL" UPDATE_NOTES="${UPDATE_NOTES:-}" python3 - <<'PY'
import json, os, re
ver = None
for line in open('pubspec.yaml', encoding='utf-8'):
    m = re.match(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)', line.strip())
    if m:
        ver = (m.group(1), int(m.group(2)))
        break
if not ver:
    raise SystemExit('Versione non trovata in pubspec.yaml (atteso x.y.z+n)')
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
  echo "==> APK_URL non impostato: salto version.json (auto-update non pubblicato)"
fi

if [[ "${1:-}" != "--upload" ]]; then
  echo "==> Nessun upload (passa --upload per caricare via FTP)."
  echo "    Carica manualmente il contenuto di site/ sul tuo hosting."
  exit 0
fi

: "${ARUBA_FTP_HOST:?Serve ARUBA_FTP_HOST (in .deploy.env)}"
: "${ARUBA_FTP_DIR:?Serve ARUBA_FTP_DIR (in .deploy.env)}"
: "${ARUBA_FTP_USER:?Serve ARUBA_FTP_USER (in .deploy.env)}"
: "${ARUBA_FTP_PASS:?Serve ARUBA_FTP_PASS (passala a runtime)}"

echo "==> Upload su $ARUBA_FTP_HOST$ARUBA_FTP_DIR via FTP"
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
echo "==> Fatto."
