# Flutter GUI Automation — VM Service Protocol

Discovered session 18 (2026-04-15). Allows Claude Code to interact with the running Flutter app without OS-level GUI tools.

## Problem
- User is on KDE Wayland — `xdotool` doesn't work
- `ydotool` coordinate mapping is broken with display scaling (1.25x)
- Need to take screenshots, read widget text, and control auth flow programmatically

## Solution: Flutter VM Service Protocol

Flutter debug builds expose a Dart VM Service over HTTP/WebSocket. The URL is printed at startup:
```
The Dart VM service is listening on http://127.0.0.1:PORT/TOKEN=/
```

### Key extension methods (via WebSocket JSON-RPC)

**Screenshot** — renders the Flutter widget tree to PNG server-side:
```json
{"method": "ext.flutter.inspector.screenshot",
 "params": {"isolateId": "isolates/XXX", "id": "inspector-8",
            "width": 1280, "height": 800, "margin": 0,
            "maxPixelRatio": 2.0, "debugPaint": false}}
```
Response: `{"result": {"result": "<base64 PNG>"}}`

**Widget tree**:
```json
{"method": "ext.flutter.inspector.getRootWidgetSummaryTree",
 "params": {"isolateId": "isolates/XXX", "objectGroup": "inspect"}}
```
Returns full tree with `valueId` (e.g. `inspector-8`), `description`, `children`, `createdByLocalProject`.

**Widget details**:
```json
{"method": "ext.flutter.inspector.getDetailsSubtree",
 "params": {"isolateId": "isolates/XXX", "arg": "inspector-116", "subtreeDepth": 10}}
```
Returns properties including text content (`data`, `text` fields).

### Isolate discovery
```bash
curl -s "http://127.0.0.1:PORT/TOKEN=/getVM" | jq '.result.isolates[] | select(.isSystemIsolate == false) | .id'
```

### WebSocket connection
```bash
echo '{"jsonrpc":"2.0","id":"1","method":"...","params":{...}}' | websocat -n1 "ws://127.0.0.1:PORT/TOKEN=/ws"
```

### Gotchas
- `websocat` default buffer is 64KB — large widget trees get truncated. The `screenshot` response is usually within this limit.
- Inspector IDs (`inspector-N`) change between app restarts. Use the tree to find the right one, or fall back to `inspector-8` (typically the app root).
- `evaluate` (Dart expression evaluation) doesn't work in custom builds — the JIT compilation service isn't available when using `frontend_server` directly.
- HTTP GET works for some methods (`getVM`, `getIsolate`) but extension methods require WebSocket.

## Auth Flow Automation

Instead of fighting with `evaluate`, we built file-based IPC:

- `AuthState` polls `/tmp/uniclient_auth_cmd.json` every 1s when auth needs input
- CLI writes: `{"action":"choose","value":"phone"}` or `{"action":"submit","value":"12345"}`
- App reads, deletes file, processes command
- Same OTP-file pattern as Go integration tests (`auth/otp_code.txt`)

This avoids all the complexity of runtime Dart evaluation and works on every platform with a filesystem.

## Tools
- `scripts/flutter_inspect.sh` — screenshot, tree, find, details, text
- `scripts/flutter_auth.sh` — status, choose, submit, otp-wait, auto, cancel
