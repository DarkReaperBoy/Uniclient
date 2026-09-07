# Uniclient — single-binary Gio messenger build system
#
# Requirements: Go 1.27+. On Linux additionally the X11/Wayland/EGL
# development headers. Android needs the Android SDK + NDK (see flake.nix
# or CI). NixOS users: `nix run` — no local toolchain needed.

GO      ?= go
DIST    ?= dist
GO_DIR  := go

# Low-memory compile recipe: keeps small machines alive through gotd's tg
# package (~2GB+ to compile). Harmless on big machines.
export GOMEMLIMIT ?= 900MiB
export GOGC       ?= 30

TAGS := goolm
STRIP := -trimpath -ldflags "-s -w"

.PHONY: all build run test vet lint fmt clean wasm apk web serve help

all: build test vet

## build: compile the native binary for the CURRENT platform
build:
	cd $(GO_DIR) && CGO_ENABLED=1 $(GO) build -p 1 -tags $(TAGS) $(STRIP) -o ../$(DIST)/uniclient ./cmd/uniclient

## run: build + run the app (with the demo backend for a quick look)
run: build
	UNICLIENT_HOME ?= $(DIST)/home
	$(DIST)/uniclient -demo

## test: run the full test suite
test:
	cd $(GO_DIR) && CGO_ENABLED=1 $(GO) test -p 1 -tags $(TAGS) -count=1 ./...

## vet: go vet
vet:
	cd $(GO_DIR) && CGO_ENABLED=1 $(GO) vet -tags $(TAGS) ./...

## lint: vet + gofmt clean
lint: vet
	@cd $(GO_DIR) && test -z "$$(gofmt -l .)" || (echo "gofmt needed on:"; gofmt -l .; exit 1)

## fmt: format everything
fmt:
	cd $(GO_DIR) && $(GO) fmt ./...

## wasm: web build (pure Go)
wasm:
	cd $(GO_DIR) && GOOS=js GOARCH=wasm CGO_ENABLED=0 $(GO) build -p 1 -tags $(TAGS) \
		$(STRIP) -o ../$(DIST)/uniclient.wasm ./cmd/uniclient

## apk: Android APK (arm64; needs ANDROID_HOME + ANDROID_NDK_HOME)
apk:
	cd $(GO_DIR) && gogio -target android -arch arm64 -minsdk 24 -tags $(TAGS) \
		-o ../$(DIST)/uniclient.apk ./cmd/uniclient

## windows: cross-build windows (pure Go, no toolchain needed)
windows:
	cd $(GO_DIR) && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 $(GO) build -p 1 -tags $(TAGS) \
		$(STRIP) -o ../$(DIST)/uniclient-windows-amd64.exe ./cmd/uniclient

## compress: UPX the native binaries (if upx is installed)
compress:
	@if command -v upx >/dev/null 2>&1; then \
		upx --best --lzma $(DIST)/uniclient $(DIST)/uniclient-windows-amd64.exe 2>/dev/null || true; \
	else echo "upx not found (release CI compresses binaries)"; fi

## serve: serve the wasm build locally on :8080 (after make wasm)
serve:
	./scripts/web.sh

## clean: remove build artifacts
clean:
	rm -rf $(DIST)

help:
	@echo "Uniclient build targets:"
	@echo "  make build    — native binary for this platform (dist/uniclient)"
	@echo "  make run      — build + run with the demo backend"
	@echo "  make test     — test suite (includes the demo end-to-end test)"
	@echo "  make lint     — vet + gofmt gate"
	@echo "  make wasm     — web build (dist/uniclient.wasm)"
	@echo "  make apk      — Android APK (needs ANDROID_HOME/NDK)"
	@echo "  make windows  — Windows cross-build"
	@echo "  make compress — UPX native binaries"
	@echo "  make serve    — serve the wasm build on :8080"
	@echo "  make clean    — remove dist/"
