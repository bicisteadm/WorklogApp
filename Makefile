# WorklogApp + SkodaAtlassianBridge — Build & Install
# Usage:
#   make              — WorklogApp Release build + install to /Applications
#   make build        — WorklogApp Release build only
#   make install      — Copy built WorklogApp.app to /Applications
#   make debug        — WorklogApp Debug build only (produces WorklogApp-Dev.app)
#   make dev-run      — Build Debug and launch a new instance (orange "DEV" badge,
#                       separate DB at WorklogApp-Dev.sqlite, bundle id .dev)
#   make dev-install  — Copy WorklogApp-Dev.app to /Applications
#   make run          — Build WorklogApp Release and launch
#   make icon         — Regenerate WorklogApp icon
#   make test         — Run WorklogApp unit tests
#   make clean        — Remove DerivedData build artifacts
#
#   make bridge       — SkodaAtlassianBridge Release build + install to /Applications
#   make bridge-build — Build the bridge app only
#   make bridge-run   — Build and launch the bridge app

PROJECT    := WorklogApp.xcodeproj
SCHEME     := WorklogApp
DEST       := platform=macOS
SIGN_FLAGS := CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
INSTALL_DIR := /Applications

# Resolve DerivedData build dir
BUILD_DIR = $(shell xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	-destination '$(DEST)' -configuration Release $(SIGN_FLAGS) \
	-showBuildSettings 2>/dev/null | grep '^\s*BUILT_PRODUCTS_DIR' | head -1 | awk '{print $$NF}')

DEBUG_BUILD_DIR = $(shell xcodebuild build -project $(PROJECT) -scheme $(SCHEME) \
	-destination '$(DEST)' -configuration Debug $(SIGN_FLAGS) \
	-showBuildSettings 2>/dev/null | grep '^\s*BUILT_PRODUCTS_DIR' | head -1 | awk '{print $$NF}')

APP_NAME     := WorklogApp.app
DEV_APP_NAME := WorklogApp-Dev.app

# Bridge paths
BRIDGE_PROJECT := SkodaAtlassianBridge/SkodaAtlassianBridge.xcodeproj
BRIDGE_SCHEME  := SkodaAtlassianBridge
BRIDGE_APP     := SkodaAtlassianBridge.app
BRIDGE_BUILD_DIR = $(shell xcodebuild build -project $(BRIDGE_PROJECT) -scheme $(BRIDGE_SCHEME) \
	-destination '$(DEST)' -configuration Release $(SIGN_FLAGS) \
	-showBuildSettings 2>/dev/null | grep '^\s*BUILT_PRODUCTS_DIR' | head -1 | awk '{print $$NF}')

.PHONY: all build install debug dev-run dev-install run icon test clean bridge bridge-build bridge-run

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
	@echo "✅ Debug build succeeded ($(DEV_APP_NAME))"

dev-run: debug
	@echo "🚀 Launching $(DEV_APP_NAME)…"
	@open -n "$(DEBUG_BUILD_DIR)/$(DEV_APP_NAME)"

dev-install: debug
	@echo "📦 Installing $(DEV_APP_NAME) to $(INSTALL_DIR)…"
	@rm -rf "$(INSTALL_DIR)/$(DEV_APP_NAME)"
	@cp -R "$(DEBUG_BUILD_DIR)/$(DEV_APP_NAME)" "$(INSTALL_DIR)/"
	@echo "✅ Installed to $(INSTALL_DIR)/$(DEV_APP_NAME)"

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
	@xcodebuild clean \
		-project $(BRIDGE_PROJECT) \
		-scheme $(BRIDGE_SCHEME) \
		2>/dev/null
	@echo "✅ Clean complete"

# ---- SkodaAtlassianBridge ----

bridge: bridge-build
	@echo "📦 Installing $(BRIDGE_APP) to $(INSTALL_DIR)…"
	@rm -rf "$(INSTALL_DIR)/$(BRIDGE_APP)"
	@cp -R "$(BRIDGE_BUILD_DIR)/$(BRIDGE_APP)" "$(INSTALL_DIR)/"
	@echo "✅ Installed to $(INSTALL_DIR)/$(BRIDGE_APP)"

bridge-build:
	@echo "🔨 Building $(BRIDGE_APP) (Release)…"
	@xcodebuild build \
		-project $(BRIDGE_PROJECT) \
		-scheme $(BRIDGE_SCHEME) \
		-destination '$(DEST)' \
		-configuration Release \
		$(SIGN_FLAGS) \
		2>&1 | tail -5
	@echo "✅ Bridge Release build succeeded"

bridge-run: bridge-build
	@echo "🚀 Launching $(BRIDGE_APP)…"
	@open "$(BRIDGE_BUILD_DIR)/$(BRIDGE_APP)"
