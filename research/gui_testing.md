# GUI Testing Strategy

## Automated Testing (Claude runs these independently)

All GUI tests run headlessly via `flutter test` — no user interaction, no display needed.

### Test Suites

1. **Bridge tests** (`dart/test/bridge_test.dart`)
   - Tests the full FFI bridge: Dart → Go shared library → Engine
   - Exercises: engine init, account CRUD, config, cache, auth flows (multi-step)
   - Uses a temp directory for each run — fully isolated
   - Requires `libcores.so` built (`scripts/build_go.sh linux`)
   - Run: `cd dart && flutter test test/bridge_test.dart`

2. **Widget tests** (`dart/test/widget_test.dart`)
   - Tests widget rendering without the Go backend
   - Exercises: loading state, layout at various window sizes
   - No FFI dependency — can run without `libcores.so`
   - Run: `cd dart && flutter test test/widget_test.dart`

### Running All Tests

```bash
# Inside nix develop:
cd dart && flutter test

# Or via alias:
test-dart
```

### Adding New Tests

- Bridge/engine tests go in `dart/test/bridge_test.dart`
- Widget/UI tests go in `dart/test/widget_test.dart`
- Integration tests (if needed) go in `dart/integration_test/`

## What Can't Be Tested Automatically

- Visual appearance (icons, colors, layout aesthetics)
- User interaction flows that require real network auth (Telegram OTP, etc.)
- Platform-specific rendering (GTK/Wayland behavior)
- Hot reload workflow

For these, ask the user to run `./uniclient` and report what they see.

## Architecture Notes

- **Async bridge**: Network-hitting FFI calls (`startAuth`, `submitAuthInput`, `connectAccount`, `sendMessage`, `editMessage`, `deleteMessage`, `requestDownload`) run on a background isolate via `Isolate.run`. Local ops (`listAccounts`, `getConfig`, `getCacheSize`, etc.) stay synchronous.
- **NativeCallable.listener**: Go event callbacks use `NativeCallable.listener` instead of `Pointer.fromFunction` so goroutines can push events safely from any thread.
- **Event testing caveat**: `NativeCallable.listener` events may not dispatch reliably in the `flutter_test` harness (runs in a restricted isolate). The event test is currently skipped.
