.DEFAULT_GOAL := help
SHELL := /bin/bash

WORKSPACE ?= Supershot.xcworkspace
SCHEME ?= Supershot Dev
CONFIGURATION ?= Debug
BUILD_DESTINATION ?= generic/platform=iOS Simulator
TEST_DESTINATION ?= platform=iOS Simulator,name=iPhone 18 Pro,OS=latest
MAC_DESTINATION ?= platform=macOS
XCODEBUILD ?= xcodebuild
XCODEBUILD_ARGS ?=
XCBEAUTIFY ?= xcbeautify
SWIFTFORMAT ?= swiftformat

XCODEBUILD_COMMON = -workspace "$(WORKSPACE)" -scheme "$(SCHEME)" \
	-configuration "$(CONFIGURATION)" -onlyUsePackageVersionsFromResolvedFile
SWIFT_PATHS = Supershot SupershotShared SupershotTests SupershotWidgets \
	SupershotPackage/Package.swift SupershotPackage/Sources SupershotPackage/Tests

.PHONY: help build build-macos test format lint check-swiftformat check-xcbeautify

help:
	@printf '%s\n' \
		'make build         Build the iOS app for a generic simulator' \
		'make build-macos   Build the native macOS app without code signing' \
		'make test          Run app and package tests on an iPhone 18 Pro simulator' \
		'make format        Format Swift sources using .swiftformat' \
		'make lint				  Check Swift formatting without modifying files' \
		'' \
		'Override settings with make TARGET VARIABLE=value. Examples:' \
		'  make test TEST_DESTINATION="platform=iOS Simulator,id=<simulator-id>"' \
		'  make test XCODEBUILD_ARGS="-only-testing:ScoringFeatureTests"' \
		'  make build SCHEME=Supershot CONFIGURATION=Release'

build: check-xcbeautify
	set -o pipefail; $(XCODEBUILD) build $(XCODEBUILD_COMMON) \
		-destination "$(BUILD_DESTINATION)" CODE_SIGNING_ALLOWED=NO $(XCODEBUILD_ARGS) 2>&1 | "$(XCBEAUTIFY)"

build-macos: check-xcbeautify
	set -o pipefail; $(XCODEBUILD) build $(XCODEBUILD_COMMON) \
		-destination "$(MAC_DESTINATION)" CODE_SIGNING_ALLOWED=NO $(XCODEBUILD_ARGS) 2>&1 | "$(XCBEAUTIFY)"

test: check-xcbeautify
	set -o pipefail; $(XCODEBUILD) test $(XCODEBUILD_COMMON) \
		-destination "$(TEST_DESTINATION)" $(XCODEBUILD_ARGS) 2>&1 | "$(XCBEAUTIFY)"

check-xcbeautify:
	@command -v "$(XCBEAUTIFY)" >/dev/null 2>&1 || { \
		echo 'xcbeautify is required. Install it with: brew install xcbeautify' >&2; \
		exit 1; \
	}

check-swiftformat:
	@command -v "$(SWIFTFORMAT)" >/dev/null 2>&1 || { \
		echo 'SwiftFormat is required. Install it with: brew install swiftformat' >&2; \
		exit 1; \
	}

format: check-swiftformat
	$(SWIFTFORMAT) $(SWIFT_PATHS) --config .swiftformat --cache ignore

lint: check-swiftformat
	$(SWIFTFORMAT) $(SWIFT_PATHS) --config .swiftformat --cache ignore --lint
