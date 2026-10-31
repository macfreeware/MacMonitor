#!/bin/bash
# MacMonitor kurulum paketini (.pkg) üretir.  Kullanım: scripts/build_pkg.sh
#   SKIP_APP_BUILD=1     MacMonitor.app zaten hazırsa yeniden derlemez
#   PKG_SIGN_IDENTITY=…  ("Developer ID Installer: …") verilirse paket imzalanır; yoksa imzasız üretilir
# Çıktı: build/release/MacMonitor-<sürüm>.pkg ve .sha256
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${SKIP_APP_BUILD:-0}" != "1" ]]; then
  ./build.sh
fi
APP="build/MacMonitor.app"
[[ -d "$APP" ]] || { echo "HATA: $APP yok"; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
mkdir -p build/release
OUT="build/release/MacMonitor-$VERSION.pkg"

echo "▸ Paket içeriği hazırlanıyor ($VERSION)…"
STAGE="build/pkg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE/payload" "$STAGE/resources"
ditto --norsrc --noextattr --noqtn "$APP" "$STAGE/payload/MacMonitor.app"
find "$STAGE/payload" -name .DS_Store -delete

# Uygulama başka bir yerdeki (örn. geliştirme klasöründeki) kopyaya "taşınmasın": her zaman /Applications.
pkgbuild --analyze --root "$STAGE/payload" "$STAGE/component.plist" >/dev/null
/usr/bin/plutil -replace 0.BundleIsRelocatable -bool NO "$STAGE/component.plist"
/usr/bin/plutil -replace 0.BundleHasStrictIdentifier -bool NO "$STAGE/component.plist"
# Aynı/eski sürümün üzerine de her zaman yazılsın (sürüm denetimiyle sessizce atlanmasın).
/usr/bin/plutil -replace 0.BundleIsVersionChecked -bool NO "$STAGE/component.plist"

echo "▸ Bileşen paketi…"
pkgbuild --root "$STAGE/payload" \
         --component-plist "$STAGE/component.plist" \
         --identifier com.rafetsapanci.MacMonitor.pkg --version "$VERSION" \
         --install-location /Applications \
         --scripts scripts/pkg/scripts \
         "$STAGE/MacMonitor-component.pkg" >/dev/null 2> >(grep -v '^write: Permission denied$' >&2)

echo "▸ Kurulum paketi…"
# Karşılama/bitiş sayfaları iki dili alt alta içerir; Installer sistemin diline uyan klasörü seçer, o dil üstte durur.
for lang in tr en; do
  mkdir -p "$STAGE/resources/$lang.lproj"
  for page in scripts/pkg/resources/*.html; do
    python3 -I - "$page" "$lang" "$VERSION" "$STAGE/resources/$lang.lproj/$(basename "$page")" <<'PY'
import re, sys
src, lang, version, out = sys.argv[1:5]
text = open(src, encoding="utf-8").read()
page, rest = text.split("</body></html>", 1)
blocks = {k: re.search(rf"<!--{k}-->\n(.*?)<!--/{k}-->", rest, re.S).group(1) for k in ("TR", "EN")}
first, second = ("TR", "EN") if lang == "tr" else ("EN", "TR")
body = (blocks[first] + "<hr>\n" + blocks[second]).replace("@VERSION@", version)
open(out, "w", encoding="utf-8").write(page.replace("@LANG@", lang).replace("@BODY@", body.strip()) + "</body></html>\n")
PY
  done
done
sed "s/@VERSION@/$VERSION/g" scripts/pkg/distribution.xml > "$STAGE/distribution.xml"
SIGN_ARGS=()
if [[ -n "${PKG_SIGN_IDENTITY:-}" ]]; then SIGN_ARGS=(--sign "$PKG_SIGN_IDENTITY"); fi
rm -f "$OUT" "$OUT.sha256"
productbuild --distribution "$STAGE/distribution.xml" --resources "$STAGE/resources" \
             --package-path "$STAGE" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$OUT" >/dev/null

# Hazırlık klasöründeki kopya sistemde "ikinci bir MacMonitor" olarak kalmasın: kaydını sil, klasörü kaldır.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$PWD/$STAGE/payload/MacMonitor.app" >/dev/null 2>&1 || true
rm -rf "${STAGE:?}"

( cd build/release && shasum -a 256 "MacMonitor-$VERSION.pkg" > "MacMonitor-$VERSION.pkg.sha256" )
echo "✔ Hazır: $OUT ($(du -h "$OUT" | cut -f1))"
echo "  SHA-256: $(cut -d' ' -f1 "$OUT.sha256")"
