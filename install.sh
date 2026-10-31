#!/bin/bash
set -e

echo "🚀 MacMonitor Yükleme ve Başlatma Sihirbazı"
echo "-----------------------------------------"

# 1. Derleme yap
./build.sh

# 2. Çalışan eski örnek varsa durdur
echo "🛑 Eski çalışan örnekler kontrol ediliyor..."
killall MacMonitor 2>/dev/null || true
sleep 0.5

# 3. Yükleme hedefi (Öncelikle /Applications, izin yoksa ~/Applications)
TARGET_DIR="/Applications"
if [ ! -w "$TARGET_DIR" ]; then
    TARGET_DIR="$HOME/Applications"
    mkdir -p "$TARGET_DIR"
fi

echo "📂 Uygulama taşınıyor: $TARGET_DIR/MacMonitor.app"
rm -rf "$TARGET_DIR/MacMonitor.app"
cp -R "build/MacMonitor.app" "$TARGET_DIR/"

echo "✨ MacMonitor başarıyla yüklendi!"
echo "▶️  Uygulama menü çubuğunda başlatılıyor..."
open "$TARGET_DIR/MacMonitor.app"

echo "🎉 Hazır! Menü çubuğunun (sağ üst) üst köşesine bakın."
