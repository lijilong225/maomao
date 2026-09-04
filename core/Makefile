SHELL := /bin/bash

ANDROID_SDK ?= $(HOME)/Library/Android/sdk
NDK_VERSION ?= 28.2.13676358
ANDROID_NDK_HOME ?= $(ANDROID_SDK)/ndk/$(NDK_VERSION)
ANDROID_API ?= 24

GOMOBILE ?= $(shell go env GOPATH)/bin/gomobile
# The no_* tags stub out tailscale/zerotier outbounds and hysteria v1's faketcp obfs, saving ~12 MB per ABI.
BUILD_TAGS ?= with_gvisor cmfa no_tailscale no_zerotier no_fake_tcp
AAR_OUT ?= ../app/android/app/libs/maomao-core.aar

# gomobile locates gobind through PATH.
export PATH := $(shell go env GOPATH)/bin:$(PATH)

# constant.Version defaults to a stale placeholder, so inject the real one.
MIHOMO_VERSION ?= $(shell go list -m -f '{{.Version}}' github.com/metacubex/mihomo)
LDFLAGS ?= -s -w -X github.com/metacubex/mihomo/constant.Version=$(MIHOMO_VERSION)

# arm64 first: it is the only ABI required for Play Store 16KB page-size compliance.
ANDROID_TARGETS ?= android/arm64,android/arm,android/amd64

# Windows runs the core as a sidecar process, so the cmfa carve-outs (no
# process-name matching, relaxed path checks) are not wanted there.
WINDOWS_TAGS ?= with_gvisor
WINDOWS_ARCH ?= amd64
WINDOWS_OUT ?= ../app/windows/libs/maomao-core.exe

# macOS ships as a sidecar too, and only Apple Silicon is supported.
MACOS_TAGS ?= with_gvisor
MACOS_ARCH ?= arm64
MACOS_OUT ?= ../app/macos/libs/maomao-core

.PHONY: android android-check windows windows-check macos macos-check clean

android-check:
	GOOS=android GOARCH=arm64 CGO_ENABLED=1 \
	CC=$(ANDROID_NDK_HOME)/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android$(ANDROID_API)-clang \
	go build -tags "$(BUILD_TAGS)" ./...

android:
	mkdir -p $(dir $(AAR_OUT))
	ANDROID_HOME=$(ANDROID_SDK) ANDROID_NDK_HOME=$(ANDROID_NDK_HOME) \
	$(GOMOBILE) bind \
		-target=$(ANDROID_TARGETS) \
		-androidapi $(ANDROID_API) \
		-javapkg com.maomao.proxy \
		-tags "$(BUILD_TAGS)" \
		-trimpath \
		-ldflags "$(LDFLAGS)" \
		-o $(AAR_OUT) \
		./bridge

windows-check:
	GOOS=windows GOARCH=$(WINDOWS_ARCH) CGO_ENABLED=0 \
	go build -tags "$(WINDOWS_TAGS)" ./...

windows:
	mkdir -p $(dir $(WINDOWS_OUT))
	GOOS=windows GOARCH=$(WINDOWS_ARCH) CGO_ENABLED=0 \
	go build \
		-tags "$(WINDOWS_TAGS)" \
		-trimpath \
		-ldflags "$(LDFLAGS)" \
		-o $(WINDOWS_OUT) \
		./cmd/maomao-core

macos-check:
	GOOS=darwin GOARCH=$(MACOS_ARCH) CGO_ENABLED=0 \
	go build -tags "$(MACOS_TAGS)" ./...

macos:
	mkdir -p $(dir $(MACOS_OUT))
	GOOS=darwin GOARCH=$(MACOS_ARCH) CGO_ENABLED=0 \
	go build \
		-tags "$(MACOS_TAGS)" \
		-trimpath \
		-ldflags "$(LDFLAGS)" \
		-o $(MACOS_OUT) \
		./cmd/maomao-core

clean:
	rm -f $(AAR_OUT) $(basename $(AAR_OUT))-sources.jar $(WINDOWS_OUT) $(MACOS_OUT)
