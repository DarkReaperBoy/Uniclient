# Uniclient — messenger build system (pure-Go engine + cores; the Gio GUI
# rebuild rides along — its Linux shims need libxkbcommon-dev + libwayland-dev)
#
# Requirements: Go 1.27+. Pure Go: no cgo, no system dev headers needed.
# NixOS users: `nix run` — no local toolchain needed.

GO      ?= go
DIST    ?= dist
GO_DIR  := go

# Low-memory compile recipe: keeps small machines alive through gotd's tg
# package (~2GB+ to compile). Harmless on big machines.
export GOMEMLIMIT ?= 900MiB
export GOGC       ?= 30

TAGS := goolm
STRIP := -trimpath -ldflags "-s -w"

.PHONY: all build run test vet lint fmt clean windows compress help

all: build test vet

## build: compile the native binary for the CURRENT platform (pure Go)
build:
	cd $(GO_DIR) && CGO_ENABLED=1 $(GO) build -p 1 -tags $(TAGS) $(STRIP) -o ../$(DIST)/uniclient ./cmd/uniclient

## run: build + run the headless engine host
run: build
	UNICLIENT_HOME ?= $(DIST)/home
	$(DIST)/uniclient

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

## windows: cross-build windows (pure Go, no toolchain needed)
windows:
	cd $(GO_DIR) && GOOS=windows GOARCH=amd64 CGO_ENABLED=0 $(GO) build -p 1 -tags $(TAGS) \
		$(STRIP) -o ../$(DIST)/uniclient-windows-amd64.exe ./cmd/uniclient

## compress: UPX the native binaries (if upx is installed)
compress:
	@if command -v upx >/dev/null 2>&1; then \
		upx --best --lzma $(DIST)/uniclient $(DIST)/uniclient-windows-amd64.exe 2>/dev/null || true; \
	else echo "upx not found (release CI compresses binaries)"; fi

## clean: remove build artifacts
clean:
	rm -rf $(DIST)

help:
	@echo "Uniclient build targets:"
	@echo "  make build    — native binary for this platform (dist/uniclient)"
	@echo "  make run      — build + run the headless engine host"
	@echo "  make test     — test suite (engine end-to-end included)"
	@echo "  make lint     — vet + gofmt gate"
	@echo "  make windows  — Windows cross-build"
	@echo "  make compress — UPX native binaries"
	@echo "  make clean    — remove dist/"
