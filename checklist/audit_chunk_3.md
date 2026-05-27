# bridge_web — Web WASM Bridge Implementation Audit

## CRITICAL ISSUES

- [ ] **[CRITICAL] Function name mismatch: Dart imports `bridgeCall` but Go exports `BridgeCallWithLen`** — `bridge_web.dart:14-15` ← `go/cmd/bridge/main.go:27` + `scripts/build_go.sh:57`
  - Go exports: `BridgeCallWithLen` (FFI-style with pointer/length params)
  - JavaScript names via `wasm_exec.js`: `bridgeCallWithLen` (lowercase camelCase)
  - Dart imports: `bridgeCall` (wrong name, will be undefined at runtime)
  - Result: When Dart calls `_jsBridgeCall()`, JavaScript will throw "bridgeCall is not defined"

- [ ] **[CRITICAL] Function signature incompatibility: FFI pointer/length API not compatible with JavaScript/WASM** — `bridge_web.dart:36-44` ← `go/cmd/bridge/main.go:28-37`
  - Go function expects: `BridgeCallWithLen(data *C.uint8_t, dataLen C.int32_t, outLen *C.int32_t) *C.uint8_t`
  - Dart calls it with: `_jsBridgeCall(JSUint8Array data)` (single parameter)
  - WASM has no raw pointers—this calling convention doesn't work in JavaScript
  - Even with correct name, this would fail or return garbage data
  - **Fix needed**: Either (1) create WASM-friendly wrapper functions in Go that handle memory marshaling, or (2) create a JavaScript wrapper in `index.html` that bridges between the JavaScript API and Go's FFI API

- [ ] **[CRITICAL] Event callback parameter mismatch** — `bridge_web.dart:32` ← `go/cmd/bridge/main.go:53`
  - Go `BridgeSetEventCallback` expects: `cb C.event_callback_t` (C callback function pointer)
  - Dart passes: `_onEventFromGo.toJS` (converted to JSFunction)
  - The Go side will receive this and try to invoke it as a C function pointer (via `C.invoke_event_callback`)
  - This is **not a valid C callback** in the WASM context—the parameter types are incompatible

## Status

**The web bridge is non-functional.** The WASM module loads but all calls will fail because:
1. Function names don't match (bridgeCall ≠ bridgeCallWithLen)
2. Function signatures are incompatible with JavaScript semantics
3. Memory marshaling between JS and WASM is not implemented

**Root cause:** The bridge was designed for native FFI (Linux/Windows/macOS using C pointers) but the same code is being used for WASM without adaptation. WASM requires different APIs.

## Required Fixes

1. **Create WASM-compatible Go exports** — Add wrapper functions in `go/cmd/bridge/` that:
   - Export `bridgeCall(data []byte) []byte` or similar (not pointer-based)
   - Handle all memory marshaling internally
   - Make these available to JavaScript with the correct names

2. **Or create a JavaScript wrapper** — In `dart/web/index.html` or a separate `.js` file:
   - Define `window.bridgeCall` and `window.bridgeSetEventCallback`
   - These wrap the Go `bridgeCallWithLen` with proper pointer/memory handling
   - Convert between JavaScript Uint8Array and WASM linear memory

3. **Test the web build** — Build `go build -o cores.wasm` and verify:
   - `bridgeCall` and `bridgeSetEventCallback` are callable from JavaScript console
   - They return the expected types
   - Memory marshaling works correctly

