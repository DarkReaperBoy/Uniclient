# bridge — CRITICAL: CGo violation in Go bridge

## Findings

### CRITICAL Issues

- [ ] **[CRITICAL] Bridge uses CGo despite explicit CLAUDE.md zero-CGo rule** — `go/cmd/bridge/main.go:13` uses `import "C"` and builds with `CGO_ENABLED=1`, violating CLAUDE.md's non-negotiable rule: "**HARD RULE: Pure Go + Flutter ONLY — ZERO CGo, ZERO C/C++ dependencies.** No CGo anywhere — not in cores, not in utils, not in bridge, not in tests, not anywhere."
  - Affected files:
    - `go/cmd/bridge/main.go:2` — comment explicitly says `CGO_ENABLED=1`
    - `go/cmd/bridge/main.go:13` — `import "C"` statement
    - `scripts/build_go.sh:21,27,33,49` — all targets built with `CGO_ENABLED=1`
  - Impact: Requires C compiler toolchain (mingw32-gcc for Windows, NDK for Android). Can be done 100% in pure Go.
  - Fix: Rewrite FFI entry point using native Go types (uint8, int32, pointers) without `import "C"`. The only reason CGo was used is for C.malloc/C.free and C type definitions — both unnecessary. Go's `buildmode=c-shared` works fine with pure Go.

## Details

**Current architecture (WRONG):**
- main.go imports C to get C.uint8_t, C.int32_t, C.malloc, C.free, C.CBytes
- Builds with CGO_ENABLED=1 on all native platforms

**Correct architecture:**
- Use Go's native types: byte arrays, int32, unsafe.Pointer
- Memory: use Go's unsafe package for C interop; Go's GC handles Dart-managed allocations
- Build with CGO_ENABLED=0 (the default)
- Type signatures:
  - `func BridgeCallWithLen(data *byte, dataLen int32, outLen *int32) *byte`
  - `func BridgeFree(ptr *byte)` — or eliminate and let Dart use Go pointers directly
  - `func BridgeSetEventCallback(cb uintptr)` — callback handle instead of C function pointer

This is a hard rule violation and must be fixed before any feature work proceeds.
