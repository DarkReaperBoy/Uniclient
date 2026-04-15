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

3. **Comprehensive widget tests** (`dart/test/widget_comprehensive_test.dart`)
   - 83 tests covering models, widget rendering, data/logic, events, themes, state, and reactions
   - No FFI dependency — uses mocked state, runs without `libcores.so`
   - Categories:
     - **Model tests (30)**: CachedMessage, ChatInfo, media fields, copyWith, JSON round-trip, convenience getters (isImage, isVideo, mediaSizeLabel, etc.)
     - **Widget render tests (8)**: PlatformRail, Sidebar, ChatView, EmojiPanel, Settings, AuthScreen — verify rendering with mock Provider state
     - **Data/logic tests (22)**: chat sorting, search filtering, unread computation, message ordering, platform filtering, date formatting
     - **Event model tests (8)**: auth events, connection events, message events, typing events — parse and verify fields
     - **Theme tests (4)**: dark/light ThemeData creation, AppColors constants, accent color consistency
     - **State tests (3)**: AppState, ChatState, AuthState ChangeNotifier behavior
   - Run: `cd dart && flutter test test/widget_comprehensive_test.dart`

4. **Telegram auth flow** (`dart/test/telegram_auth_test.dart`)
   - Full automated Telegram phone auth: add account → phone → OTP → 2FA → connected
   - Uses a pre-seeded session (reader account) to read OTP codes automatically
   - Reader account auto-auths from `auth/telegram_user_session.json`, reads OTP from user 777000
   - Requires: `libcores.so`, valid session file at `auth/telegram_user_session.json`
   - Env vars: `TG_PHONE` (default: +96877354040), `TG_2FA_PASSWORD` (default: nako123)
   - Run: `cd dart && flutter test test/telegram_auth_test.dart`

5. **Telegram send test** (`dart/test/telegram_send_test.dart`)
   - Auth + send message + verify in chat history
   - Requires: `libcores.so`, valid credentials
   - Run: `cd dart && flutter test test/telegram_send_test.dart`

6. **Platform GUI tests** (`dart/test/platform_gui_test.dart`)
   - Tests all 10 platforms through the engine FFI bridge: add account → auth → connect → get chats
   - Each platform: independent auth flow, auto-connects via `finalizeAuth` on reaching `ready` state
   - Platforms tested: IRC, GitHub, XMPP, Telegram, Bale, DeltaChat, Matrix, Rubika, Mumble, TeamSpeak
   - Results (2026-04-15):
     - **7/10 PASS**: IRC (Libera.Chat), GitHub (token), XMPP (yax.im), DeltaChat (IMAP), Matrix (local Dendrite), Mumble (local Docker), TeamSpeak (local Docker)
     - **2/10 SKIP**: Telegram (session expired, needs OTP), Rubika (geo-restricted, needs Iranian IP)
     - **1/10 FAIL**: Bale (bot token API returns 404, geo-restricted from Oman)
   - Docker containers needed: dendrite-test (Matrix), mumble-test (Mumble), ts3-test (TeamSpeak)
   - Bug fixed during testing: IRC auth config used `Extra["nickname"]` but core expected `Extra["nick"]`
   - Run: `cd dart && flutter test test/platform_gui_test.dart`
   - Run single platform: `cd dart && flutter test test/platform_gui_test.dart --name "IRC"`

### Running All Tests

```bash
# Inside nix develop:
cd dart && flutter test

# Or via alias:
test-dart
```

### Adding New Tests

- Bridge/engine tests go in `dart/test/bridge_test.dart`
- Widget/UI tests go in `dart/test/widget_test.dart` or `dart/test/widget_comprehensive_test.dart`
- Integration tests (if needed) go in `dart/integration_test/`

## What Can't Be Tested Automatically

- Visual appearance (icons, colors, layout aesthetics)
- Platform-specific rendering (GTK/Wayland behavior)
- Hot reload workflow

For these, ask the user to run `./uniclient` and report what they see.

## Architecture Notes

- **Async bridge**: Network-hitting FFI calls (`startAuth`, `submitAuthInput`, `connectAccount`, `sendMessage`, `editMessage`, `deleteMessage`, `requestDownload`) run on a background isolate via `Isolate.run`. Local ops (`listAccounts`, `getConfig`, `getCacheSize`, etc.) stay synchronous.
- **NativeCallable.listener**: Go event callbacks use `NativeCallable.listener` instead of `Pointer.fromFunction` so goroutines can push events safely from any thread.
- **Event testing caveat**: `NativeCallable.listener` events may not dispatch reliably in the `flutter_test` harness (runs in a restricted isolate). The event test is currently skipped.
- **Media metadata pipeline**: Go's `populateMediaMetadata()` joins the `media` table after scanning messages, exposing 10 media fields (type, name, mime, size, thumb base64, local path, dimensions, duration, download state) through proto tags 18-27 on `EngineCachedMessage`.
