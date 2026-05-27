# bridge_stub.dart — No issues found

## Context
This file is a **backend FFI bridge stub**, not a UI component. It uses Dart's conditional import pattern (bridge.dart:9-11):

```dart
import 'bridge_stub.dart'
    if (dart.library.ffi) 'bridge_ffi.dart'
    if (dart.library.js_interop) 'bridge_web.dart' as impl;
```

At runtime:
- **Native platforms** (desktop/mobile): `bridge_ffi.dart` is loaded → `bridge_stub.dart` is never reached
- **Web**: `bridge_web.dart` is loaded → `bridge_stub.dart` is never reached
- **Other platforms**: `bridge_stub.dart` is loaded as fallback → intentional `UnsupportedError` is thrown

## Design
The stub's error-throwing behavior is **correct and intentional**. It serves as:
1. A fallback for unsupported platforms (safe fail)
2. A compile-time check that all code paths are covered
3. Runtime detection of missing platform-specific implementations

## Verdict
✅ No audit issues — this is not a UI file and the stub pattern is correctly implemented.
