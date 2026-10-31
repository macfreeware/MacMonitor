#!/bin/bash
# MacMonitor.app'i derler (Apple Silicon + Intel, universal).
#   --zip  ayrıca build/release/MacMonitor-<sürüm>.zip ve SHA-256 değerini üretir
set -e
cd "$(dirname "$0")"

APP_NAME="MacMonitor"
VERSION="1.0.4"
BUILD_NUMBER="4"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
CACHE_DIR="/tmp/macmonitor-module-cache"

echo "🔨 ${APP_NAME} ${VERSION} derleniyor..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${CACHE_DIR}"

SWIFT_FILES=$(find Sources -name "*.swift")

echo "📦 Kaynak dosyalar derleniyor (arm64 + x86_64)..."
for ARCH in arm64 x86_64; do
    swiftc -O \
        -parse-as-library \
        -module-cache-path "${CACHE_DIR}" \
        -target ${ARCH}-apple-macos13.0 \
        -framework AppKit \
        -framework SwiftUI \
        -framework ServiceManagement \
        ${SWIFT_FILES} \
        -o "${BUILD_DIR}/${APP_NAME}-${ARCH}"
done
lipo -create "${BUILD_DIR}/${APP_NAME}-arm64" "${BUILD_DIR}/${APP_NAME}-x86_64" -output "${MACOS_DIR}/${APP_NAME}"
rm -f "${BUILD_DIR}/${APP_NAME}-arm64" "${BUILD_DIR}/${APP_NAME}-x86_64"

# Sürüm yalnızca burada tanımlanır; Hakkında ve Ayarlar onu Info.plist'ten okur.
cp Resources/Info.plist "${CONTENTS_DIR}/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${CONTENTS_DIR}/Info.plist"
cp Resources/AppIcon.icns "${RESOURCES_DIR}/"

echo "✍️  Uygulama imzalanıyor (ad-hoc)..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "✅ Derleme tamamlandı: ${APP_BUNDLE}"

if [[ "${1:-}" == "--zip" ]]; then
    # Zip, uygulamayı ve GPL lisans metnini içeren bir klasör taşır.
    mkdir -p "${BUILD_DIR}/release"
    ZIP="${BUILD_DIR}/release/${APP_NAME}-${VERSION}.zip"
    STAGE="${BUILD_DIR}/release/${APP_NAME}-${VERSION}"
    rm -rf "${ZIP}" "${ZIP}.sha256" "${STAGE}"
    mkdir -p "${STAGE}"
    cp -R "${APP_BUNDLE}" "${STAGE}/"
    cp LICENSE "${STAGE}/LICENSE.txt"
    ditto -c -k --norsrc --keepParent "${STAGE}" "${ZIP}"
    rm -rf "${STAGE}"
    (cd "${BUILD_DIR}/release" && shasum -a 256 "$(basename "${ZIP}")" > "$(basename "${ZIP}").sha256")
    echo "📦 Paket: ${ZIP}"
fi
