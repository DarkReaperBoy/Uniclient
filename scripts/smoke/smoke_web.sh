#!/usr/bin/env bash
# Web-host smoke test: boots the real uniclient-web server headlessly and
# drives it through the API surface a browser would use, including one REAL
# network round-trip (a bogus GitHub token must produce an auth error state).
#
# Run from the repo root:   scripts/smoke/smoke_web.sh
set -euo pipefail

PORT="${UNICLIENT_WEB_PORT:-8199}"
BASE="http://127.0.0.1:$PORT"
cd "$(dirname "$0")/../../go"

echo "== building uniclient-web =="
CGO_ENABLED=0 go build -tags goolm -o /tmp/uniclient-web-smoke ./cmd/web

export UNICLIENT_HOME
UNICLIENT_HOME="$(mktemp -d)"
echo "== launching server (home: $UNICLIENT_HOME) =="
/tmp/uniclient-web-smoke -no-browser -port "$PORT" &
SRV=$!
trap 'kill $SRV 2>/dev/null || true; rm -rf "$UNICLIENT_HOME"' EXIT

for _ in $(seq 1 30); do
  curl -sf "$BASE/api/health" >/dev/null 2>&1 && break
  sleep 1
done

echo "== health =="
curl -sf "$BASE/api/health" | grep -q '"ok":true' && echo "ok: health JSON"

echo "== static UI =="
curl -sf "$BASE/" | grep -q '<title>Uniclient</title>' && echo "ok: index.html"
curl -sf "$BASE/app.js"  >/dev/null && echo "ok: app.js"
curl -sf "$BASE/style.css" >/dev/null && echo "ok: style.css"

echo "== QR rendering =="
curl -s --max-time 10 -X POST "$BASE/api/qr" -d '{"text":"tg://login?token=smoke"}' -o /tmp/uc-qr.png
head -c 4 /tmp/uc-qr.png | od -An -tx1 | grep -qi '89 50 4e 47' && echo "ok: QR PNG magic bytes"

echo "== account + auth flow =="
AID="$(curl -sf -X POST "$BASE/api/accounts" -d '{"platform":"github"}' \
  | grep -o '"account_id":"[^"]*"' | cut -d'"' -f4)"
[ -n "$AID" ] && echo "ok: account created ($AID)"

STATE="$(curl -sf -X POST "$BASE/api/accounts/$AID/auth/start")"
echo "$STATE" | grep -q '"state":"input"' && echo "ok: auth flow starts at input state"
echo "$STATE" | grep -q 'Personal Access Token' && echo "ok: GitHub asks for the token"

echo "== real network round-trip: bogus token must yield an error state =="
RESP="$(curl -s --max-time 60 -X POST "$BASE/api/accounts/$AID/auth/input" \
  -d '{"input":"ghp_this_token_is_invalid_by_design"}')"
echo "$RESP" | grep -q '"state":"error"' && echo "ok: invalid token rejected by the real GitHub API"

echo "== WebSocket =="
node -e '
const ws = new WebSocket("ws://127.0.0.1:'"$PORT"'/ws");
ws.onopen = () => { console.log("ok: WebSocket connected"); process.exit(0); };
ws.onerror = () => { console.error("WS failed"); process.exit(1); };
setTimeout(() => { console.error("WS timeout"); process.exit(1); }, 10000);
'

echo "== second launch dedupe =="
if timeout 10 /tmp/uniclient-web-smoke -no-browser -port "$PORT" 2>&1 | grep -q "already running"; then
  echo "ok: second instance defers to the running one"
else
  echo "FAIL: second instance did not detect the running server" >&2
  exit 1
fi

echo "== clean shutdown =="
kill -INT $SRV
wait $SRV 2>/dev/null || true
trap - EXIT
echo "SMOKE PASSED"
