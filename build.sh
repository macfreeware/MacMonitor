#!/bin/bash
set -e

echo "🔨 MacMonitor derleniyor..."

APP_NAME="MacMonitor"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
CACHE_DIR="/tmp/swift-cache"

mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"
mkdir -p "${CACHE_DIR}"

# Find all Swift source files
SWIFT_FILES=$(find Sources -name "*.swift")

echo "📦 Kaynak dosyalar derleniyor (Release modunda)..."
swiftc -O \
    -parse-as-library \
    -module-cache-path "${CACHE_DIR}" \
    -target arm64-apple-macos13.0 \
    -framework AppKit \
    -framework SwiftUI \
    -framework ServiceManagement \
    ${SWIFT_FILES} \
    -o "${MACOS_DIR}/${APP_NAME}"

echo "📋 Info.plist kopyalanıyor..."
cp Resources/Info.plist "${CONTENTS_DIR}/Info.plist"

# Generate or copy Icon if available
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "${RESOURCES_DIR}/"
fi

# Ad-hoc code signing for local macOS execution
echo "✍️  Uygulama imzalanıyor (ad-hoc)..."
codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true

echo "✅ Derleme tamamlandı: ${APP_BUNDLE}"
echo "🚀 Başlatmak için: open ${APP_BUNDLE}"
