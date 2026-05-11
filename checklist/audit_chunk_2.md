# bridge_stub — Platform Fallback (Not a Feature)

## Classification
This file is **NOT a UI feature** or **user-facing component**. It's a platform abstraction fallback — a safety net that should never be reached at runtime.

## Design Analysis

**What it is:**
- Stub implementation for the bridge layer (`dart:ffi` for native, `dart:web` for web)
- Conditional imports in `bridge.dart` select the correct implementation (`bridge_ffi.dart` or `bridge_web.dart`)
- This stub is loaded only if both platform-specific imports fail — an error condition

**What it does (correctly):**
1. `events` returns `Stream.empty()` — no events are generated (correct for a stub)
2. `isInitialized` returns `false` — correctly signals that the bridge isn't ready
3. `init()`, `call()`, `callAsync()` throw `UnsupportedError` — correctly fail fast instead of silently doing nothing
4. `dispose()` is a no-op — correct, nothing to clean up

## Assessment

**No issues found.** This is intentionally minimal and correct. It's a fallback that signals platform incompatibility, not a feature implementation. Any feature wiring issues would be in:
- `dart/lib/bridge/bridge_ffi.dart` (desktop/Android native)
- `dart/lib/bridge/bridge_web.dart` (web)

These are the files to audit for backend connectivity and feature wiring.

---

**Recommendation:** Audit `bridge_ffi.dart` and `bridge_web.dart` instead. This stub is correctly designed.
