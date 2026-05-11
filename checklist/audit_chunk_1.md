# bridge_ffi.dart — FFI Bridge Infrastructure Audit

## Summary
The FFI bridge implementation is structurally sound and has proper memory management. However, there are 3 issues affecting release-mode safety and resource cleanup.

---

## Issues Found

- [ ] **[CRITICAL]** Release-mode safety: `assert()` statements on lines 70 & 76 are stripped in release builds. If the bridge is called without `init()` in production, no validation occurs. → `bridge_ffi.dart:70` & `bridge_ffi.dart:76`
  - **Fix**: Replace `assert(_initialized, ...)` with explicit `if (!_initialized) throw StateError(...)`
  - **Impact**: Silent failures in release mode if init() is skipped

- [ ] **[MAJOR]** Resource leak: `_globalEventController` (line 146) is never closed. On app shutdown, the StreamController remains open. → `bridge_ffi.dart:146`
  - **Fix**: Call `_globalEventController.close()` in `dispose()` or add cleanup handler
  - **Impact**: Potential memory/resource leak on app termination

- [ ] **[MAJOR]** Fragile library path resolution on Linux (line 90-92): Relative path `lib/libcores.so` assumes a specific directory structure. If the app is installed elsewhere or run from a different working directory, the path resolution falls back to bare `libcores.so`, which requires the library in system PATH. → `bridge_ffi.dart:87-98`
  - **Fix**: Use `Platform.resolvedExecutable` to derive absolute path more robustly, or document the expected deployment structure
  - **Impact**: Library loading failures in non-standard deployment scenarios

---

## What's Working Correctly

✓ Memory management in `_doCall()` (lines 102-131): Proper allocation, usage, and freeing of pointers  
✓ Event callback marshaling via `NativeCallable.listener()` (line 162): Correct async handling from Go goroutines  
✓ Isolate-based async calls (lines 75-79, 135-143): Background FFI calls prevent UI blocking  
✓ Null pointer checks (line 117): Handles empty/error responses from backend  

---

## Cross-Check Notes

- This is infrastructure code (FFI wrapper) with no direct AyuGram C++ equivalent to compare against
- No stubs, TODOs, or placeholder implementations found
- No hardcoded mock data or fake callbacks
- Backend wiring is complete: `init()` → load library → set event callback → calls go through `_callWithLen`
