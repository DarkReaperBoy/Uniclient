#!/usr/bin/env bash
# Flutter debug interaction script — sends gesture commands to the running app.
# Uses the /tmp/uniclient_debug_cmd.json polling interface.
#
# Usage:
#   ./scripts/flutter_interact.sh tap 500 300           # left-click at (500, 300)
#   ./scripts/flutter_interact.sh rightclick 500 300    # right-click at (500, 300)
#   ./scripts/flutter_interact.sh longpress 500 300     # long-press at (500, 300)
#   ./scripts/flutter_interact.sh scroll 500 300 0 -200 # scroll down at (500, 300)
#   ./scripts/flutter_interact.sh scroll 500 300 0 200  # scroll up at (500, 300)
#   ./scripts/flutter_interact.sh type "hello world"    # type into focused field
#   ./scripts/flutter_interact.sh key enter             # send Enter key
#   ./scripts/flutter_interact.sh open 5                # open chat at index 5
#   ./scripts/flutter_interact.sh open -id "chatId123"  # open chat by ID
#   ./scripts/flutter_interact.sh send "hello"          # send message in active chat
#   ./scripts/flutter_interact.sh chats                 # list chats
#   ./scripts/flutter_interact.sh messages              # list messages
#   ./scripts/flutter_interact.sh state                 # get app state
#   ./scripts/flutter_interact.sh wait                  # wait for output and print it

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
  tap)
    send_cmd "{\"action\":\"tap\",\"x\":$1,\"y\":$2}"
    ;;
  rightclick|right-click|rc)
    send_cmd "{\"action\":\"rightClick\",\"x\":$1,\"y\":$2}"
    ;;
  longpress|long-press|lp)
    send_cmd "{\"action\":\"longPress\",\"x\":$1,\"y\":$2}"
    ;;
  scroll|sc)
    local x="${1:-640}" y="${2:-400}" dx="${3:-0}" dy="${4:--200}"
    send_cmd "{\"action\":\"scroll\",\"x\":$x,\"y\":$y,\"dx\":$dx,\"dy\":$dy}"
    ;;
  type)
    local text="${1:-}"
    send_cmd "{\"action\":\"type\",\"text\":$(echo "$text" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}"
    ;;
  key)
    send_cmd "{\"action\":\"key\",\"key\":\"${1:-enter}\"}"
    ;;
  open)
    if [[ "${1:-}" == "-id" ]]; then
      send_cmd "{\"action\":\"openChat\",\"chatId\":\"$2\"}"
    else
      send_cmd "{\"action\":\"openChat\",\"index\":$1}"
    fi
    ;;
  send)
    send_cmd "{\"action\":\"sendMessage\",\"text\":$(echo "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')}"
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
  wait)
    wait_output "${1:-5}"
    ;;
  help|*)
    echo "Usage: $0 <action> [args...]"
    echo ""
    echo "Gestures:"
    echo "  tap <x> <y>                    Left-click at coordinates"
    echo "  rightclick <x> <y>             Right-click at coordinates"
    echo "  longpress <x> <y>              Long-press at coordinates"
    echo "  scroll <x> <y> <dx> <dy>       Scroll (negative dy = scroll down)"
    echo "  type <text>                    Type text into focused field"
    echo "  key <keyname>                  Send key (enter, backspace)"
    echo ""
    echo "State:"
    echo "  open <index>                   Open chat by index"
    echo "  open -id <chatId>              Open chat by ID"
    echo "  send <text>                    Send message in active chat"
    echo "  chats                          List chats (outputs JSON)"
    echo "  messages                       List current messages"
    echo "  state                          Get current app state"
    echo "  accounts                       List accounts"
    ;;
esac
