# WorklogApp — Build & Install
# Usage:
#   make              — Release build + install to /Applications
#   make build        — Release build only
#   make install      — Copy built .app to /Applications
#   make debug        — Debug build only
#   make run          — Build Release and launch
#   make icon         — Regenerate app icon
#   make test         — Run unit tests
#   make clean        — Remove DerivedData build artifacts

PROJECT    := WorklogApp.xcodeproj
SCHEME     := WorklogApp
DEST       := platform=macOS
SIGN_FLAGS := CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
INSTALL_DIR := /Applications

# Resolve DerivedData build dir
BUILD_DIR = $(shell xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	-destination '$(DEST)' -configuration Release $(SIGN_FLAGS) \
	-showBuildSettings 2>/dev/null | grep '^\s*BUILT_PRODUCTS_DIR' | head -1 | awk '{print $$NF}')

APP_NAME   := WorklogApp.app

.PHONY: all build install debug run icon test clean

all: build install

build:
	@echo "🔨 Building Release…"
	@xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DEST)' \
		-configuration Release \
		$(SIGN_FLAGS) \
		2>&1 | tail -5
	@echo "✅ Release build succeeded"

debug:
	@echo "🔨 Building Debug…"
	@xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DEST)' \
		-configuration Debug \
		$(SIGN_FLAGS) \
		2>&1 | tail -5

install: build
	@echo "📦 Installing to $(INSTALL_DIR)…"
	@rm -rf "$(INSTALL_DIR)/$(APP_NAME)"
	@cp -R "$(BUILD_DIR)/$(APP_NAME)" "$(INSTALL_DIR)/"
	@echo "✅ Installed to $(INSTALL_DIR)/$(APP_NAME)"

run: build
	@echo "🚀 Launching $(APP_NAME)…"
	@open "$(BUILD_DIR)/$(APP_NAME)"

icon:
	@echo "🎨 Generating app icon…"
	@swift scripts/generate_icon.swift
	@echo "✅ Icon generated — rebuild needed to apply"

test:
	@echo "🧪 Running unit tests…"
	@xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DEST)' \
		-only-testing:WorklogAppTests \
		$(SIGN_FLAGS) \
		2>&1 | grep -E "Test case|passed|failed|error:|BUILD" | tail -30
	@echo "✅ Tests complete"

clean:
	@echo "🧹 Cleaning…"
	@xcodebuild clean \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		2>/dev/null
	@echo "✅ Clean complete"
