#!/bin/bash
# Sürüm dosyalarını hazırlar: evrensel uygulama, MacMonitor.zip + .sha256 (uygulamanın kendini
# güncellemesi bu iki sabit adı arar, bkz. Sources/Models/UpdateChecker.swift) ve kurulum paketi.
#
#   scripts/make_release.sh                       # yalnızca dosyaları hazırlar ve denetler
#   scripts/make_release.sh --publish notlar.md   # ayrıca GitLab'da v<sürüm> sürümünü oluşturur (glab ile);
#                                                 # notlardaki @PKG_SHA@ ve @ZIP_SHA@ doldurulur
#
# Sürüm numarası build.sh'teki VERSION'dan gelir; önce onu yükseltip commit'leyin.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' build.sh)
OUT="build/release"

rm -rf "$OUT"
./build.sh --zip
SKIP_APP_BUILD=1 scripts/build_pkg.sh

# Denetim: zip'ten çıkan uygulama, güncelleyicinin aradığı yerde, imzalı ve doğru sürümde mi?
CHECK=$(mktemp -d)
ditto -x -k "$OUT/MacMonitor.zip" "$CHECK"
codesign --verify --deep --strict "$CHECK/MacMonitor/MacMonitor.app"
[[ "$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$CHECK/MacMonitor/MacMonitor.app/Contents/Info.plist")" == "$VERSION" ]]
[[ "$(lipo -archs "$CHECK/MacMonitor/MacMonitor.app/Contents/MacOS/MacMonitor")" == "x86_64 arm64" ]]
rm -rf "$CHECK"

# Deneme ayarları (yalnızca DEBUG) yayımlanan ikilide olmamalı.
if strings build/MacMonitor.app/Contents/MacOS/MacMonitor | grep -q "MACMONITOR_UPDATE_"; then
  echo "✘ Yayım ikilisinde deneme ayarı var" >&2
  exit 1
fi

echo "✔ $OUT ($VERSION)"
cat "$OUT/MacMonitor.zip.sha256" "$OUT/MacMonitor-$VERSION.pkg.sha256"

if [[ "${1:-}" == "--publish" ]]; then
  NOTES_SRC="${2:?Notlar dosyası gerekli: scripts/make_release.sh --publish notlar.md}"
  # Özetler bu derlemeye ait olmalı: notlardaki @PKG_SHA@ ve @ZIP_SHA@ burada doldurulur.
  NOTES="$OUT/notes.md"
  sed -e "s/@PKG_SHA@/$(cut -d' ' -f1 "$OUT/MacMonitor-$VERSION.pkg.sha256")/g" \
      -e "s/@ZIP_SHA@/$(cut -d' ' -f1 "$OUT/MacMonitor.zip.sha256")/g" "$NOTES_SRC" > "$NOTES"
  glab release create "v$VERSION" \
    "$OUT/MacMonitor.zip#MacMonitor.zip" \
    "$OUT/MacMonitor.zip.sha256#MacMonitor.zip.sha256" \
    "$OUT/MacMonitor-$VERSION.pkg#MacMonitor-$VERSION.pkg" \
    "$OUT/MacMonitor-$VERSION.pkg.sha256#MacMonitor-$VERSION.pkg.sha256" \
    --ref main --name "MacMonitor $VERSION" --notes-file "$NOTES"
  # README'deki indirme düğmesi sürümsüz adresi kullanır: .../permalink/latest/downloads/MacMonitor.pkg
  ID=$(glab api "projects/freeware2%2Fmacmonitor/releases/v$VERSION/assets/links" |
       python3 -I -c 'import sys,json; print(next(l["id"] for l in json.load(sys.stdin) if l["name"].endswith(".pkg")))')
  printf '{"name":"MacMonitor-%s.pkg","direct_asset_path":"/MacMonitor.pkg"}' "$VERSION" |
    glab api --method PUT -H "Content-Type: application/json" --input - \
      "projects/freeware2%2Fmacmonitor/releases/v$VERSION/assets/links/$ID" >/dev/null
fi
