APP_NAME = MacMonitor
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR = $(APP_BUNDLE)/Contents/MacOS
RESOURCES_DIR = $(APP_BUNDLE)/Contents/Resources
SWIFT_FILES = $(shell find Sources -name "*.swift")
CACHE_DIR = /tmp/swift-cache

.PHONY: all build run install clean

all: build

build:
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR) $(CACHE_DIR)
	@echo "🔨 MacMonitor derleniyor..."
	swiftc -O \
		-parse-as-library \
		-module-cache-path $(CACHE_DIR) \
		-target arm64-apple-macos13.0 \
		-framework AppKit \
		-framework SwiftUI \
		-framework ServiceManagement \
		$(SWIFT_FILES) \
		-o $(MACOS_DIR)/$(APP_NAME)
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(RESOURCES_DIR)/; fi
	@codesign --force --deep --sign - $(APP_BUNDLE) 2>/dev/null || true
	@echo "✅ Derleme tamamlandı: $(APP_BUNDLE)"

run: build
	@echo "🚀 MacMonitor başlatılıyor..."
	@open $(APP_BUNDLE)

install: build
	@echo "📦 Uygulama yükleniyor..."
	@killall MacMonitor 2>/dev/null || true
	@cp -R $(APP_BUNDLE) /Applications/ 2>/dev/null || cp -R $(APP_BUNDLE) ~/Applications/
	@echo "✅ Yüklendi! Başlatılıyor..."
	@open /Applications/$(APP_NAME).app 2>/dev/null || open ~/Applications/$(APP_NAME).app

clean:
	@rm -rf $(BUILD_DIR)
	@echo "🧹 Temizlendi."
