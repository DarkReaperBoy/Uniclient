#!/usr/bin/env bash
# Flutter debug interaction script — sends gesture and query commands to the running app.
# Uses the /tmp/uniclient_debug_cmd.json polling interface.
#
# GESTURES:
#   ./scripts/flutter_interact.sh tap 500 300              # left-click at (500, 300)
#   ./scripts/flutter_interact.sh rightclick 500 300       # right-click at (500, 300)
#   ./scripts/flutter_interact.sh longpress 500 300        # long-press at (500, 300)
#   ./scripts/flutter_interact.sh doubleclick 500 300      # double-click at (500, 300)
#   ./scripts/flutter_interact.sh scroll 500 300 0 -200    # scroll down at (500, 300)
#   ./scripts/flutter_interact.sh scroll 500 300 0 200     # scroll up at (500, 300)
#   ./scripts/flutter_interact.sh drag 100 300 200 300     # drag from (100,300) to (200,300)
#   ./scripts/flutter_interact.sh hover 500 300            # hover at (500, 300)
#   ./scripts/flutter_interact.sh type "hello world"       # type into focused field
#   ./scripts/flutter_interact.sh key enter                # send Enter key
#   ./scripts/flutter_interact.sh key escape               # dismiss popup/dialog
#   ./scripts/flutter_interact.sh dismiss                  # dismiss popup (tap corner)
#
# QUERIES (output to stdout):
#   ./scripts/flutter_interact.sh findtext "Pinned"        # find text on screen → coordinates
#   ./scripts/flutter_interact.sh alltext                  # dump ALL visible text + positions
#   ./scripts/flutter_interact.sh hittest 500 300          # what widget is at (500, 300)?
#   ./scripts/flutter_interact.sh windowsize               # get window width/height
#   ./scripts/flutter_interact.sh waitfor "Send" 5         # wait up to 5s for text to appear
#
# STATE:
#   ./scripts/flutter_interact.sh open 5                   # open chat at index 5
#   ./scripts/flutter_interact.sh open -id "chatId123"     # open chat by ID
#   ./scripts/flutter_interact.sh send "hello"             # send message in active chat
#   ./scripts/flutter_interact.sh chats                    # list chats
#   ./scripts/flutter_interact.sh messages                 # list messages
#   ./scripts/flutter_interact.sh state                    # get app state
#   ./scripts/flutter_interact.sh accounts                 # list accounts
#
# COMBO (high-level):
#   ./scripts/flutter_interact.sh taptext "Forward"        # find text "Forward" and tap its center
#
# WINDOW:
#   ./scripts/flutter_interact.sh resize mobile            # resize to 400x720 (narrow/oneColumn)
#   ./scripts/flutter_interact.sh resize desktop           # resize to 1024x768 (wide/twoColumn+)
#   ./scripts/flutter_interact.sh resize 800 600           # resize to custom WxH

set -euo pipefail

CMD_FILE="/tmp/uniclient_debug_cmd.json"
OUT_FILE="/tmp/uniclient_debug_out.json"

send_cmd() {
  echo "$1" > "$CMD_FILE"
}

wait_output() {
  local timeout="${1:-3}"
  local start=$SECONDS
  while [[ $((SECONDS - start)) -lt $timeout ]]; do
    if [[ -f "$OUT_FILE" ]]; then
      cat "$OUT_FILE"
      rm -f "$OUT_FILE"
      return 0
    fi
    sleep 0.2
  done
  echo "ERROR: No output within ${timeout}s" >&2
  return 1
}

ACTION="${1:-help}"
shift || true

case "$ACTION" in
  # ── Gestures ──
  tap)
    send_cmd "{\"action\":\"tap\",\"x\":$1,\"y\":$2}"
    ;;
  rightclick|right-click|rc)
    send_cmd "{\"action\":\"rightClick\",\"x\":$1,\"y\":$2}"
    ;;
  longpress|long-press|lp)
    send_cmd "{\"action\":\"longPress\",\"x\":$1,\"y\":$2}"
    ;;
  doubleclick|double-click|dc)
    send_cmd "{\"action\":\"doubleClick\",\"x\":$1,\"y\":$2}"
    ;;
  scroll|sc)
    send_cmd "{\"action\":\"scroll\",\"x\":${1:-640},\"y\":${2:-400},\"dx\":${3:-0},\"dy\":${4:--200}}"
    ;;
  drag)
    send_cmd "{\"action\":\"drag\",\"x1\":$1,\"y1\":$2,\"x2\":$3,\"y2\":$4,\"steps\":${5:-10}}"
    ;;
  hover)
    send_cmd "{\"action\":\"hover\",\"x\":$1,\"y\":$2}"
    ;;
  type)
    send_cmd "{\"action\":\"type\",\"text\":$(python3 -c "import json; print(json.dumps('''$1'''))")}"
    ;;
  settext|set-text|st)
    send_cmd "{\"action\":\"setText\",\"text\":$(python3 -c "import json; print(json.dumps('''$1'''))")}"
    ;;
  key)
    send_cmd "{\"action\":\"key\",\"key\":\"${1:-enter}\"}"
    ;;
  dismiss)
    send_cmd '{"action":"dismissPopup"}'
    ;;

  # ── Queries ──
  findtext|find-text|ft)
    rm -f "$OUT_FILE"
    send_cmd "{\"action\":\"findText\",\"text\":$(python3 -c "import json; print(json.dumps('''$1'''))")}"
    wait_output 3
    ;;
  alltext|all-text|at)
    rm -f "$OUT_FILE"
    send_cmd '{"action":"getAllText"}'
    wait_output 3
    ;;
  hittest|hit-test|ht)
    rm -f "$OUT_FILE"
    send_cmd "{\"action\":\"hitTest\",\"x\":$1,\"y\":$2}"
    wait_output 3
    ;;
  windowsize|window-size|ws)
    rm -f "$OUT_FILE"
    send_cmd '{"action":"getWindowSize"}'
    wait_output 3
    ;;
  waitfor|wait-for|wf)
    rm -f "$OUT_FILE"
    send_cmd "{\"action\":\"waitForText\",\"text\":$(python3 -c "import json; print(json.dumps('''$1'''))"),\"timeout\":${2:-5}}"
    wait_output "${2:-5}"
    ;;

  # ── Combos ──
  taptext|tap-text|tt)
    # Find text, then tap its center.
    rm -f "$OUT_FILE"
    send_cmd "{\"action\":\"findText\",\"text\":$(python3 -c "import json; print(json.dumps('''$1'''))")}"
    TT_RESULT=$(wait_output 3) || { echo "Text '$1' not found"; exit 1; }
    TT_CX=$(echo "$TT_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['cx'])" 2>/dev/null) || { echo "Text '$1' not found on screen"; exit 1; }
    TT_CY=$(echo "$TT_RESULT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['cy'])" 2>/dev/null)
    echo "Tapping '$1' at ($TT_CX, $TT_CY)"
    send_cmd "{\"action\":\"tap\",\"x\":$TT_CX,\"y\":$TT_CY}"
    ;;

  # ── State ──
  open)
    if [[ "${1:-}" == "-id" ]]; then
      send_cmd "{\"action\":\"openChat\",\"chatId\":\"$2\"}"
    else
      send_cmd "{\"action\":\"openChat\",\"index\":$1}"
    fi
    ;;
  send)
    send_cmd "{\"action\":\"sendMessage\",\"text\":$(python3 -c "import json; print(json.dumps('''$1'''))")}"
    ;;
  chats)
    rm -f "$OUT_FILE"
    send_cmd '{"action":"listChats"}'
    wait_output 3
    ;;
  messages|msgs)
    rm -f "$OUT_FILE"
    send_cmd '{"action":"getMessages"}'
    wait_output 3
    ;;
  state)
    rm -f "$OUT_FILE"
    send_cmd '{"action":"getState"}'
    wait_output 3
    ;;
  accounts)
    rm -f "$OUT_FILE"
    send_cmd '{"action":"listAccounts"}'
    wait_output 3
    ;;

  resize)
    # Resize the uniclient window via debug command (in-app, no external tools).
    MODE="${1:-}"
    case "$MODE" in
      mobile)  W=400; H=720 ;;
      desktop) W=1024; H=768 ;;
      *)       W="${1:-1024}"; H="${2:-768}" ;;
    esac
    send_cmd "{\"action\":\"resize\",\"width\":$W,\"height\":$H}"
    echo "Resized to ${W}x${H}"
    ;;

  help|*)
    cat <<'HELPEOF'
Usage: flutter_interact.sh <action> [args...]

GESTURES:
  tap <x> <y>                     Left-click at coordinates
  rightclick <x> <y>              Right-click (opens context menu)
  longpress <x> <y>               Long-press (enters selection mode)
  doubleclick <x> <y>             Double-click (text selection)
  scroll <x> <y> <dx> <dy>        Scroll (negative dy = down, positive = up)
  drag <x1> <y1> <x2> <y2> [steps]  Drag from point to point
  hover <x> <y>                   Hover at coordinates (triggers tooltips)
  type <text>                     Type text into focused TextField
  key <name>                      Send key: enter, escape
  dismiss                         Dismiss any open popup/dialog

QUERIES (output JSON to stdout):
  findtext <query>                Find text on screen → [{text, x, y, w, h, cx, cy}]
  alltext                         Dump ALL visible text with positions
  hittest <x> <y>                 What widget is at these coordinates?
  windowsize                      Get window width, height, pixelRatio
  waitfor <text> [timeout_sec]    Wait for text to appear (polls every 200ms)

COMBOS:
  taptext <query>                 Find text on screen and tap its center

STATE:
  open <index>                    Open chat by index
  open -id <chatId>               Open chat by ID
  send <text>                     Send message in active chat
  chats                           List chats (JSON)
  messages                        List current messages
  state                           Get current app state
  accounts                        List accounts

WINDOW:
  resize mobile                   Resize to 400x720 (narrow/oneColumn)
  resize desktop                  Resize to 1024x768 (wide/twoColumn+)
  resize <W> <H>                  Resize to custom dimensions
HELPEOF
    ;;
esac
