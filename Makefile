APP_BUNDLE = build/MacMonitor.app

.PHONY: all build run install zip pkg clean

all: build

build:
	@./build.sh

zip:
	@./build.sh --zip

pkg:
	@./scripts/build_pkg.sh

run: build
	@open $(APP_BUNDLE)

install:
	@./install.sh

clean:
	@rm -rf build
	@echo "🧹 Temizlendi."
