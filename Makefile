SHELL := /bin/bash
.DEFAULT_GOAL := help

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
EXAMPLE_DIR := $(ROOT_DIR)/example
PTY_PACKAGE_DIR := $(ROOT_DIR)/packages/ianvs_pty
TERMINAL_PACKAGE_DIR := $(ROOT_DIR)/packages/ianvs_terminal
BACKEND_DIR := $(ROOT_DIR)/backend

FLUTTER ?= flutter
DART ?= dart
GO ?= go

APP_NAME ?= Ianvs Terminal
RELEASE_DIR := $(EXAMPLE_DIR)/build/macos/Build/Products/Release
APP_BUNDLE := $(RELEASE_DIR)/$(APP_NAME).app
INSTALL_DIR ?= /Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_NAME).app

.PHONY: \
	help bootstrap format format-check analyze test test-profiles verify \
	run run-macos build build-macos sign-macos install install-macos \
	build-install-macos clean \
	backend-format backend-test backend-run backend-generate-key

help: ## Show the available commands.
	@printf '%s\n' \
		'Usage: make <target>' \
		'' \
		'Development:' \
		'  bootstrap           Resolve workspace dependencies' \
		'  format              Format workspace Dart sources' \
		'  format-check        Check Dart formatting without changes' \
		'  analyze             Analyze the PTY, terminal, and example packages' \
		'  test                Run workspace unit and widget tests' \
		'  test-profiles       Run only the Profile Editor test suite' \
		'  verify              Run the repository verification script' \
		'  backend-format       Format Go data API sources' \
		'  backend-test         Run Go data API tests' \
		'  backend-run          Run the local Go data API (requires BACKEND_CONFIG)' \
		'  backend-generate-key Generate a client-owned data key' \
		'' \
		'macOS:' \
		'  run                  Run the example app on macOS' \
		'  build                Build the macOS release app' \
		'  sign-macos           Build and prepare a locally runnable release app' \
		'  install              Build, sign, and install into /Applications' \
		'  build-install-macos  Alias for install-macos' \
		'' \
		'Maintenance:' \
		'  clean                Clean example Flutter build outputs' \
		'' \
		'Overrides: FLUTTER=<path> DART=<path> INSTALL_DIR=<directory>'

bootstrap: ## Resolve workspace dependencies.
	cd "$(ROOT_DIR)" && $(DART) pub get

format: ## Format workspace Dart sources.
	cd "$(ROOT_DIR)" && $(DART) format example/lib example/test example/integration_test packages test

format-check: ## Check Dart formatting without changing files.
	cd "$(ROOT_DIR)" && $(DART) format --output=none --set-exit-if-changed example/lib example/test example/integration_test packages test

analyze: ## Analyze all Dart and Flutter packages with fatal infos.
	cd "$(PTY_PACKAGE_DIR)" && $(DART) analyze --fatal-infos
	cd "$(TERMINAL_PACKAGE_DIR)" && $(FLUTTER) analyze --fatal-infos
	cd "$(EXAMPLE_DIR)" && $(FLUTTER) analyze --fatal-infos

test: ## Run workspace unit and widget tests.
	cd "$(ROOT_DIR)" && $(DART) test
	cd "$(PTY_PACKAGE_DIR)" && $(DART) test
	cd "$(TERMINAL_PACKAGE_DIR)" && $(FLUTTER) test
	cd "$(EXAMPLE_DIR)" && $(FLUTTER) test

test-profiles: ## Run only the Profile Editor tests.
	cd "$(EXAMPLE_DIR)" && $(FLUTTER) test test/profiles

verify: ## Run the repository's complete verification entrypoint.
	"$(ROOT_DIR)/tools/verify_flutter_terminal.sh"

backend-format: ## Format Go data API sources.
	cd "$(BACKEND_DIR)" && gofmt -w .

backend-test: ## Run Go data API tests.
	cd "$(BACKEND_DIR)" && $(GO) test ./...

backend-run: ## Run the local Go data API.
	@test -n "$(strip $(BACKEND_CONFIG))" || { printf '%s\n' \
		'BACKEND_CONFIG is required (for example: make backend-run BACKEND_CONFIG=/absolute/path/to/config.json)' >&2; exit 2; }
	cd "$(BACKEND_DIR)" && $(GO) run ./cmd/ianvs-api serve --config "$(BACKEND_CONFIG)"

backend-generate-key: ## Generate a client-owned data encryption key.
	cd "$(BACKEND_DIR)" && $(GO) run ./cmd/ianvs-api generate-key

run: run-macos

run-macos: ## Run the example app on macOS.
	cd "$(EXAMPLE_DIR)" && $(FLUTTER) run -d macos

build: build-macos

build-macos: ## Build the macOS release app.
	cd "$(EXAMPLE_DIR)" && $(FLUTTER) build macos --release
	@test -d "$(APP_BUNDLE)" || { printf 'Missing app bundle: %s\n' "$(APP_BUNDLE)" >&2; exit 1; }
	@printf 'Built: %s\n' "$(APP_BUNDLE)"

sign-macos: build-macos ## Build and prepare the release app for local launch.
	"$(ROOT_DIR)/tools/sign_local_macos_release.sh" "$(APP_BUNDLE)"

install: install-macos

install-macos: sign-macos ## Build, sign, and install the app into INSTALL_DIR.
	@test -d "$(INSTALL_DIR)" || { printf 'Missing install directory: %s\n' "$(INSTALL_DIR)" >&2; exit 1; }
	ditto --rsrc --extattr "$(APP_BUNDLE)" "$(INSTALLED_APP)"
	codesign --verify --deep --strict "$(INSTALLED_APP)"
	@printf 'Installed: %s\n' "$(INSTALLED_APP)"

build-install-macos: install-macos

clean: ## Clean example Flutter build outputs.
	cd "$(EXAMPLE_DIR)" && $(FLUTTER) clean
