# Uniclient — Go engine + FFI bridge build system
#
# Build requirements:
#   - Go 1.27+ (https://go.dev/dl)
#   - A C compiler (gcc/clang/mingw) for the c-shared targets
#   - Node.js (>= 18) only for `make smoke-wasm`
#
# All library/engine builds use `-tags goolm`:
#   mautrix's default Olm implementation (crypto/libolm) is cgo; the goolm
#   build tag selects the pure-Go implementation so the engine stays
#   CGO-free. The ONLY cgo in the repo is the c-shared FFI export shim
#   (go/cmd/bridge/main.go) required by -buildmode=c-shared.
#
# Low-RAM note: gotd/td's generated tg package needs ~2GB+ RAM to compile.
# The GOFLAGS/GOENV below enable the documented low-memory recipe
# automatically (harmless on big machines).

GO      ?= go
GOROOT  ?= $(shell $(GO) env GOROOT 2>/dev/null)
NODE    ?= node
DIST    ?= dist
GO_DIR  := go
SMOKE   := scripts/smoke

# Low-memory compile recipe (verified): harmless on big machines, keeps
# 4GB CI boxes alive through the gotd tg package.
export GOMEMLIMIT ?= 900MiB
export GOGC       ?= 30

GOFLAGS_BUILD := -p 1 -tags goolm

.PHONY: all build test vet lint clean dist c-shared wasm cli \
	smoke-c smoke-wasm smoke \
	ci-native ci-wasm ci-smoke help

all: build test vet

## build: compile all packages (native, CGO_ENABLED=0 where possible)
build:
	cd $(GO_DIR) && CGO_ENABLED=0 $(GO) build $(GOFLAGS_BUILD) ./...

## test: run the full test suite
test:
	cd $(GO_DIR) && CGO_ENABLED=0 $(GO) test $(GOFLAGS_BUILD) ./...

## test-race: run tests with the race detector (needs ~4GB+ free RAM;
## the gotd tg package under -race needs more than small CI boxes have)
test-race:
	cd $(GO_DIR) && CGO_ENABLED=0 $(GO) test $(GOFLAGS_BUILD) -race ./utils/ ./cores/ ./bridge/

## vet: go vet across the module
vet:
	cd $(GO_DIR) && CGO_ENABLED=0 $(GO) vet $(GOFLAGS_BUILD) ./...

## lint: vet + verify gofmt clean
lint: vet
	@cd $(GO_DIR) && test -z "$$(gofmt -l .)" || (echo "gofmt needed on:"; gofmt -l .; exit 1)

## fmt: format everything
fmt:
	cd $(GO_DIR) && $(GO) fmt ./...

## c-shared: build the FFI shared library for the CURRENT platform into dist/
c-shared:
	cd $(GO_DIR) && CGO_ENABLED=1 $(GO) build $(GOFLAGS_BUILD) -buildmode=c-shared \
		-o ../$(DIST)/libuniclient.so ./cmd/bridge
	@echo "-> $(DIST)/libuniclient.so + libuniclient.h"

## cli: build a native CLI binary that links the bridge in-process
cli:
	cd $(GO_DIR) && CGO_ENABLED=0 $(GO) build $(GOFLAGS_BUILD) -o ../$(DIST)/uniclient-cli ./cmd/cli

## wasm: build the js/wasm module into dist/
wasm:
	cd $(GO_DIR) && GOOS=js GOARCH=wasm CGO_ENABLED=0 $(GO) build $(GOFLAGS_BUILD) \
		-o ../$(DIST)/uniclient.wasm ./cmd/bridge
	@echo "-> $(DIST)/uniclient.wasm"

## smoke-c: build c-shared + run the C FFI smoke test (needs cc + the .so)
smoke-c: c-shared
	$(CC) $(SMOKE)/smoke_c.c -o $(SMOKE)/smoke_c \
		-L$(realpath $(DIST)) -luniclient -Wl,-rpath,'$(realpath $(DIST))'
	@rm -rf /tmp/uniclient-smoke-c && mkdir -p /tmp/uniclient-smoke-c
	$(SMOKE)/smoke_c /tmp/uniclient-smoke-c

## smoke-wasm: build wasm + run the Node smoke test (needs node)
smoke-wasm: wasm
	cd $(SMOKE) && GOROOT='$(GOROOT)' $(NODE) --stack-size=8192 run_wasm.mjs

## smoke: both smoke suites
smoke: smoke-c smoke-wasm

## ci-native: the native CI gate
ci-native: build test vet

## ci-wasm: the wasm CI gate
ci-wasm: wasm

## ci-smoke: the artifact smoke CI gate
ci-smoke: smoke

## clean: remove build artifacts
clean:
	rm -rf $(DIST) $(SMOKE)/smoke_c

help:
	@echo "Uniclient build targets:"
	@echo "  make build      — compile all packages (CGO_ENABLED=0)"
	@echo "  make test       — run the test suite"
	@echo "  make test-race  — tests + race detector (heavy)"
	@echo "  make vet        — go vet"
	@echo "  make lint       — vet + gofmt check"
	@echo "  make c-shared   — dist/libuniclient.so (FFI library for hosts)"
	@echo "  make cli        — dist/uniclient-cli"
	@echo "  make wasm       — dist/uniclient.wasm (web bridge module)"
	@echo "  make smoke-c    — build + run C FFI smoke test"
	@echo "  make smoke-wasm — build + run Node wasm smoke test"
	@echo "  make smoke      — both smoke suites"
	@echo "  make clean      — remove artifacts"
