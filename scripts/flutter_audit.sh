#!/usr/bin/env bash
# flutter_audit.sh — Unified debugging/verification toolkit for ralph.
# Merges diagnose, verify, recover, and find into one script.
#
# Usage:
#   ./scripts/flutter_audit.sh diagnose [quick]
#   ./scripts/flutter_audit.sh verify ["description"]
#   ./scripts/flutter_audit.sh recover [full|relaunch|kill]
#   ./scripts/flutter_audit.sh find text <query> [--tap]
#   ./scripts/flutter_audit.sh find widget <WidgetName>
#   ./scripts/flutter_audit.sh find near <x> <y> [radius]
#   ./scripts/flutter_audit.sh find focused
#   ./scripts/flutter_audit.sh find clickable
#   ./scripts/flutter_audit.sh find screen

set -euo pipefail

SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(dirname "$SCRIPTS")"
LOG_FILE="${UNICLIENT_LOG:-/tmp/uniclient_log.txt}"
CMD_FILE="/tmp/uniclient_debug_cmd.json"
OUT_FILE="/tmp/uniclient_debug_out.json"
BUNDLE="$PROJECT/dart/build/linux/x64/debug/bundle"

COMMAND="${1:-help}"
shift || true

# ═══════════════════════════════════════════════════════════════════
# Shared helpers
# ════════════════════════════════════════════════════���══════════════

ipc_send_and_wait() {
  local payload="$1"
  local timeout="${2:-4}"
  rm -f "$OUT_FILE"
  echo "$payload" > "$CMD_FILE"
  local start=$SECONDS
  while [[ $((SECONDS - start)) -lt $timeout ]]; do
    if [[ -f "$OUT_FILE" ]]; then
      cat "$OUT_FILE"
      rm -f "$OUT_FILE"
      return 0
    fi
    sleep 0.2
  done
  echo "ERROR: app not responding" >&2
  return 2
}

get_vm_url() {
  grep -a "Dart VM service is listening on" "$LOG_FILE" 2>/dev/null \
    | tail -1 | grep -oP 'http://[^ /]+/[^ /]+/' || true
}

# ═══════════════════════════════════════════════════════════════════
# diagnose — single-command health check
# ═══════════════════════════════════════════════════════════════════
cmd_diagnose() {
  local MODE="${1:-full}"
  local REPORT=""
  local EXIT_CODE=0

  section() { REPORT+="=== $1 ===\n"; }
  line()    { REPORT+="$1\n"; }
  blank()   { REPORT+="\n"; }

  # 1. Process
  section "PROCESS"
  local APP_PID
  APP_PID=$(pgrep -x uniclient 2>/dev/null | head -1 || true)
  if [[ -n "$APP_PID" ]]; then
    local UPTIME RSS RSS_MB
    UPTIME=$(ps -o etimes= -p "$APP_PID" 2>/dev/null | tr -d ' ' || echo "?")
    RSS=$(ps -o rss= -p "$APP_PID" 2>/dev/null | tr -d ' ' || echo "?")
    RSS_MB=$((${RSS:-0} / 1024))
    line "STATUS: running (PID $APP_PID, uptime ${UPTIME}s, RSS ${RSS_MB}MB)"
  else
    line "STATUS: NOT RUNNING"
    EXIT_CODE=1
  fi
  blank

  # 2. VM Service
  section "VM SERVICE"
  if [[ -f "$LOG_FILE" ]]; then
    local VM_URL
    VM_URL=$(get_vm_url)
    if [[ -n "$VM_URL" ]]; then
      line "URL: $VM_URL"
      local VM_RESP
      VM_RESP=$(curl -s --connect-timeout 3 --max-time 5 "${VM_URL}getVM" 2>/dev/null || true)
      if [[ -n "$VM_RESP" ]] && echo "$VM_RESP" | jq . &>/dev/null; then
        local ISOLATE_COUNT
        ISOLATE_COUNT=$(echo "$VM_RESP" | jq '.result.isolates | length' 2>/dev/null || echo "?")
        line "REACHABLE: yes ($ISOLATE_COUNT isolates)"
      else
        line "REACHABLE: no (connection failed or invalid response)"
        [[ $EXIT_CODE -eq 0 ]] && EXIT_CODE=2
      fi
    else
      line "URL: not found in logs"
      [[ $EXIT_CODE -eq 0 ]] && EXIT_CODE=2
    fi
  else
    line "LOG FILE: not found at $LOG_FILE"
    [[ $EXIT_CODE -eq 0 ]] && EXIT_CODE=2
  fi
  blank

  # 3. IPC
  section "IPC"
  if [[ $EXIT_CODE -lt 2 ]]; then
    rm -f "$OUT_FILE"
    echo '{"action":"getState"}' > "$CMD_FILE"
    local IPC_START=$SECONDS IPC_OK=false IPC_RESULT=""
    while [[ $((SECONDS - IPC_START)) -lt 4 ]]; do
      if [[ -f "$OUT_FILE" ]]; then
        IPC_RESULT=$(cat "$OUT_FILE")
        rm -f "$OUT_FILE"
        IPC_OK=true
        break
      fi
      sleep 0.3
    done
    if $IPC_OK; then
      local ACTIVE_CHAT CHAT_COUNT ACCOUNT_COUNT
      ACTIVE_CHAT=$(echo "$IPC_RESULT" | jq -r '.activeChatId // "none"' 2>/dev/null || echo "parse-error")
      CHAT_COUNT=$(echo "$IPC_RESULT" | jq '.chats | length' 2>/dev/null || echo "?")
      ACCOUNT_COUNT=$(echo "$IPC_RESULT" | jq '.accounts | length' 2>/dev/null || echo "?")
      line "RESPONSIVE: yes"
      line "ACCOUNTS: $ACCOUNT_COUNT"
      line "CHATS: $CHAT_COUNT"
      line "ACTIVE CHAT: $ACTIVE_CHAT"
    else
      line "RESPONSIVE: no (command timed out after 4s)"
      [[ $EXIT_CODE -eq 0 ]] && EXIT_CODE=3
    fi
  else
    line "SKIPPED (VM service not available)"
  fi
  blank

  # 4. Recent logs
  section "RECENT LOGS (last 30 lines)"
  if [[ -f "$LOG_FILE" ]]; then
    while IFS= read -r logline; do
      line "  $logline"
    done < <(tail -30 "$LOG_FILE")
  else
    line "  (no log file)"
  fi
  blank

  # 5. Error indicators
  section "ERROR INDICATORS"
  if [[ -f "$LOG_FILE" ]]; then
    local LAST_200 FLUTTER_ERRORS DART_ERRORS SEGFAULTS ENGINE_ERRORS OOM
    LAST_200=$(tail -200 "$LOG_FILE")
    FLUTTER_ERRORS=$(echo "$LAST_200" | grep -ci "══╡ EXCEPTION CAUGHT" || true)
    DART_ERRORS=$(echo "$LAST_200" | grep -ci "Unhandled Exception\|ERROR:\|FATAL:" || true)
    SEGFAULTS=$(echo "$LAST_200" | grep -ci "segfault\|SIGSEGV\|Segmentation fault" || true)
    ENGINE_ERRORS=$(echo "$LAST_200" | grep -ci "ENGINE:.*error\|ENGINE:.*fail" || true)
    OOM=$(echo "$LAST_200" | grep -ci "out of memory\|OOM" || true)
    line "Flutter exceptions: $FLUTTER_ERRORS"
    line "Dart errors:        $DART_ERRORS"
    line "Segfaults:          $SEGFAULTS"
    line "Engine errors:      $ENGINE_ERRORS"
    line "OOM:                $OOM"
    if [[ $((FLUTTER_ERRORS + DART_ERRORS + SEGFAULTS + OOM)) -gt 0 ]]; then
      blank
      line "RECENT ERRORS:"
      while IFS= read -r errline; do
        line "  $errline"
      done < <(echo "$LAST_200" | grep -i "EXCEPTION CAUGHT\|Unhandled Exception\|ERROR:\|FATAL:\|segfault\|SIGSEGV\|out of memory" | tail -10)
    fi
  else
    line "(no log file)"
  fi
  blank

  # 6. Screenshot + tree (full mode only)
  if [[ "$MODE" == "full" && $EXIT_CODE -lt 2 ]]; then
    section "SCREENSHOT"
    local SS_FILE="/tmp/flutter_diagnose_screenshot.png"
    if "$SCRIPTS/flutter_inspect.sh" screenshot "$SS_FILE" 2>/dev/null; then
      local SS_SIZE
      SS_SIZE=$(stat -c%s "$SS_FILE" 2>/dev/null || echo 0)
      line "Saved: $SS_FILE ($(( SS_SIZE / 1024 ))KB)"
    else
      line "FAILED to capture screenshot"
    fi
    blank

    section "WIDGET TREE (top 3 levels)"
    local TREE
    TREE=$("$SCRIPTS/flutter_inspect.sh" tree 2>/dev/null | head -40 || true)
    if [[ -n "$TREE" ]]; then
      while IFS= read -r treeline; do
        line "  $treeline"
      done < <(echo "$TREE")
    else
      line "  (failed to get widget tree)"
    fi
    blank
  fi

  # 7. Stale files
  section "IPC FILES"
  for f in /tmp/uniclient_debug_cmd.json /tmp/uniclient_debug_out.json /tmp/uniclient_auth_cmd.json; do
    if [[ -f "$f" ]]; then
      local AGE SIZE
      AGE=$(( $(date +%s) - $(stat -c%Y "$f" 2>/dev/null || echo 0) ))
      SIZE=$(stat -c%s "$f" 2>/dev/null || echo 0)
      line "  $f — ${AGE}s old, ${SIZE}B"
      if [[ $AGE -gt 10 ]]; then
        line "  WARNING: stale file (>10s old, app may not be polling)"
      fi
    fi
  done
  blank

  # Summary
  section "SUMMARY"
  case $EXIT_CODE in
    0) line "VERDICT: APP HEALTHY — running and responsive" ;;
    1) line "VERDICT: APP NOT RUNNING — needs restart" ;;
    2) line "VERDICT: APP BROKEN — running but VM service unreachable" ;;
    3) line "VERDICT: APP STUCK — running but not responding to IPC" ;;
  esac
  blank

  echo -e "$REPORT"
  return $EXIT_CODE
}

# ═══════════════════════════════════════════════════════════════════
# verify — post-implementation check in both modes
# ═══════════════════════════════════════════════════════════════════
cmd_verify() {
  local DESCRIPTION="${1:-feature verification}"
  local VERIFY_DIR="/tmp/flutter_verify"
  local REPORT=""
  local PASS=true

  mkdir -p "$VERIFY_DIR"

  section() { REPORT+="=== $1 ===\n"; }
  line()    { REPORT+="$1\n"; }
  blank()   { REPORT+="\n"; }
  fail()    { line "FAIL: $1"; PASS=false; }

  # Step 0: ensure app running
  section "APP CHECK"
  if ! pgrep -x uniclient &>/dev/null; then
    line "App not running. Attempting recovery..."
    if cmd_recover relaunch 2>&1 | tail -5; then
      line "Recovery successful."
    else
      fail "Could not start app. Build and launch it manually."
      echo -e "$REPORT"
      return 1
    fi
  else
    line "App is running (PID $(pgrep -x uniclient | head -1))"
  fi

  local VM_URL
  VM_URL=$(get_vm_url)
  if [[ -z "$VM_URL" ]]; then
    fail "VM service URL not found in logs"
    echo -e "$REPORT"
    return 1
  fi
  line "VM service: $VM_URL"
  blank

  # Record log position
  local LOG_LINE_START
  LOG_LINE_START=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)

  # Desktop mode
  section "DESKTOP MODE (1024x768)"
  "$SCRIPTS/flutter_interact.sh" resize desktop 2>/dev/null || true
  sleep 1.5

  if "$SCRIPTS/flutter_inspect.sh" screenshot "$VERIFY_DIR/desktop.png" 2>/dev/null; then
    local SS_SIZE
    SS_SIZE=$(stat -c%s "$VERIFY_DIR/desktop.png" 2>/dev/null || echo 0)
    line "Screenshot: $VERIFY_DIR/desktop.png ($(( SS_SIZE / 1024 ))KB)"
  else
    fail "Desktop screenshot failed"
  fi

  rm -f "$OUT_FILE"
  echo '{"action":"getAllText"}' > "$CMD_FILE"
  local DT_START=$SECONDS
  while [[ $((SECONDS - DT_START)) -lt 4 ]]; do
    if [[ -f "$OUT_FILE" ]]; then
      cp "$OUT_FILE" "$VERIFY_DIR/desktop_text.json"
      rm -f "$OUT_FILE"
      local TEXT_COUNT
      TEXT_COUNT=$(jq 'length' "$VERIFY_DIR/desktop_text.json" 2>/dev/null || echo "?")
      line "Visible text elements: $TEXT_COUNT"
      break
    fi
    sleep 0.3
  done
  blank

  # Mobile mode
  section "MOBILE MODE (400x720)"
  "$SCRIPTS/flutter_interact.sh" resize mobile 2>/dev/null || true
  sleep 1.5

  if "$SCRIPTS/flutter_inspect.sh" screenshot "$VERIFY_DIR/mobile.png" 2>/dev/null; then
    SS_SIZE=$(stat -c%s "$VERIFY_DIR/mobile.png" 2>/dev/null || echo 0)
    line "Screenshot: $VERIFY_DIR/mobile.png ($(( SS_SIZE / 1024 ))KB)"
  else
    fail "Mobile screenshot failed"
  fi

  rm -f "$OUT_FILE"
  echo '{"action":"getAllText"}' > "$CMD_FILE"
  local MB_START=$SECONDS
  while [[ $((SECONDS - MB_START)) -lt 4 ]]; do
    if [[ -f "$OUT_FILE" ]]; then
      cp "$OUT_FILE" "$VERIFY_DIR/mobile_text.json"
      rm -f "$OUT_FILE"
      TEXT_COUNT=$(jq 'length' "$VERIFY_DIR/mobile_text.json" 2>/dev/null || echo "?")
      line "Visible text elements: $TEXT_COUNT"
      break
    fi
    sleep 0.3
  done
  blank

  # App state
  section "APP STATE"
  rm -f "$OUT_FILE"
  echo '{"action":"getState"}' > "$CMD_FILE"
  local STATE_OK=false STATE_JSON=""
  local ST_START=$SECONDS
  while [[ $((SECONDS - ST_START)) -lt 4 ]]; do
    if [[ -f "$OUT_FILE" ]]; then
      STATE_JSON=$(cat "$OUT_FILE")
      cp "$OUT_FILE" "$VERIFY_DIR/state.json"
      rm -f "$OUT_FILE"
      STATE_OK=true
      break
    fi
    sleep 0.3
  done
  if $STATE_OK; then
    line "Accounts: $(echo "$STATE_JSON" | jq '.accounts | length' 2>/dev/null || echo '?')"
    line "Chats loaded: $(echo "$STATE_JSON" | jq '.chats | length' 2>/dev/null || echo '?')"
    line "Active chat: $(echo "$STATE_JSON" | jq -r '.activeChatId // "none"' 2>/dev/null || echo '?')"
  else
    fail "App not responding to state query"
  fi
  blank

  # Error check
  section "ERROR CHECK"
  if [[ -f "$LOG_FILE" ]]; then
    local TOTAL_LINES NEW_LINES RECENT
    TOTAL_LINES=$(wc -l < "$LOG_FILE")
    NEW_LINES=$((TOTAL_LINES - LOG_LINE_START))
    if [[ $NEW_LINES -gt 0 ]]; then
      RECENT=$(tail -n "$NEW_LINES" "$LOG_FILE")
    else
      RECENT=$(tail -50 "$LOG_FILE")
    fi
    local FLUTTER_EX DART_ERR SEGFAULT
    FLUTTER_EX=$(echo "$RECENT" | grep -c "══╡ EXCEPTION CAUGHT" 2>/dev/null || true)
    DART_ERR=$(echo "$RECENT" | grep -c "Unhandled Exception" 2>/dev/null || true)
    SEGFAULT=$(echo "$RECENT" | grep -c "segfault\|SIGSEGV" 2>/dev/null || true)
    if [[ $FLUTTER_EX -gt 0 ]]; then
      fail "Flutter exception detected ($FLUTTER_EX occurrence(s))"
      while IFS= read -r eline; do
        line "  $eline"
      done < <(echo "$RECENT" | grep -A2 "══╡ EXCEPTION CAUGHT" | tail -10)
    fi
    if [[ $DART_ERR -gt 0 ]]; then
      fail "Unhandled Dart exception ($DART_ERR occurrence(s))"
    fi
    if [[ $SEGFAULT -gt 0 ]]; then
      fail "Segfault detected"
    fi
    if [[ $((FLUTTER_EX + DART_ERR + SEGFAULT)) -eq 0 ]]; then
      line "No crashes or errors detected."
    fi
  else
    line "No log file available."
  fi
  blank

  # Window size
  section "WINDOW SIZE"
  rm -f "$OUT_FILE"
  echo '{"action":"getWindowSize"}' > "$CMD_FILE"
  local WS_START=$SECONDS
  while [[ $((SECONDS - WS_START)) -lt 3 ]]; do
    if [[ -f "$OUT_FILE" ]]; then
      local WS_JSON
      WS_JSON=$(cat "$OUT_FILE")
      rm -f "$OUT_FILE"
      line "Current size: $(echo "$WS_JSON" | jq -r '"\(.width // "?")x\(.height // "?")"' 2>/dev/null || echo '?')"
      break
    fi
    sleep 0.3
  done
  blank

  # Verdict
  section "VERDICT"
  line "Feature: $DESCRIPTION"
  if $PASS; then
    line "RESULT: PASS"
    line "Artifacts saved to: $VERIFY_DIR/"
  else
    line "RESULT: FAIL"
    line "Review screenshots in $VERIFY_DIR/ and errors above."
  fi
  blank

  echo -e "$REPORT"
  $PASS && return 0 || return 1
}

# ═══════════════════════════════════════════════════════════════════
# recover — kill/clean/rebuild/relaunch
# ═══════════════════════════════════════════════════════════════════
cmd_recover() {
  local MODE="${1:-full}"
  local VM_WAIT_TIMEOUT=30
  local LAUNCH_SETTLE_TIME=3

  log() { echo "[recover] $*"; }

  # Kill
  log "Killing any running uniclient processes..."
  pkill -x uniclient 2>/dev/null || true
  for i in $(seq 1 5); do
    pgrep -x uniclient &>/dev/null || break
    sleep 0.5
  done
  if pgrep -x uniclient &>/dev/null; then
    log "Force killing uniclient..."
    pkill -9 -x uniclient 2>/dev/null || true
    sleep 1
  fi

  # Clean IPC
  log "Cleaning IPC files..."
  rm -f /tmp/uniclient_debug_cmd.json \
        /tmp/uniclient_debug_out.json \
        /tmp/uniclient_auth_cmd.json \
        /tmp/uniclient_cmd.json

  if [[ "$MODE" == "kill" ]]; then
    log "Kill complete. App is stopped."
    return 0
  fi

  # Rebuild
  if [[ "$MODE" == "full" ]]; then
    log "Building Go shared library..."
    if ! "$SCRIPTS/build_go.sh" linux 2>&1 | tail -3; then
      log "ERROR: Go build failed"
      return 1
    fi
    log "Building Flutter app..."
    if ! "$SCRIPTS/build_flutter.sh" linux debug 2>&1 | tail -5; then
      log "ERROR: Flutter build failed"
      return 1
    fi
  fi

  # Verify binary
  if [[ ! -x "$BUNDLE/uniclient" ]]; then
    log "ERROR: Binary not found at $BUNDLE/uniclient"
    return 1
  fi

  # Launch
  log "Launching app..."
  > "$LOG_FILE"
  cd "$BUNDLE" && nohup ./uniclient > "$LOG_FILE" 2>&1 &
  local APP_PID=$!
  log "Launched with PID $APP_PID"

  log "Waiting ${LAUNCH_SETTLE_TIME}s for initial startup..."
  sleep "$LAUNCH_SETTLE_TIME"

  if ! kill -0 "$APP_PID" 2>/dev/null; then
    log "ERROR: App crashed immediately after launch."
    tail -20 "$LOG_FILE" 2>/dev/null || true
    return 2
  fi

  # Wait for VM service
  log "Waiting for VM service (up to ${VM_WAIT_TIMEOUT}s)..."
  local START=$SECONDS VM_URL=""
  while [[ $((SECONDS - START)) -lt $VM_WAIT_TIMEOUT ]]; do
    VM_URL=$(get_vm_url)
    [[ -n "$VM_URL" ]] && break
    if ! kill -0 "$APP_PID" 2>/dev/null; then
      log "ERROR: App died during startup."
      tail -20 "$LOG_FILE" 2>/dev/null || true
      return 2
    fi
    sleep 1
  done

  if [[ -z "$VM_URL" ]]; then
    log "ERROR: VM service URL not found after ${VM_WAIT_TIMEOUT}s"
    tail -20 "$LOG_FILE" 2>/dev/null || true
    return 2
  fi

  # Verify VM service responds
  log "VM service found at: $VM_URL"
  local VM_OK=false
  for i in $(seq 1 5); do
    local RESP
    RESP=$(curl -s --connect-timeout 2 --max-time 3 "${VM_URL}getVM" 2>/dev/null || true)
    if [[ -n "$RESP" ]] && echo "$RESP" | jq . &>/dev/null; then
      VM_OK=true
      break
    fi
    sleep 1
  done
  if ! $VM_OK; then
    log "ERROR: VM service at $VM_URL not responding"
    return 2
  fi

  # Wait for IPC handler
  log "Waiting for IPC handler..."
  rm -f "$OUT_FILE"
  echo '{"action":"getState"}' > "$CMD_FILE"
  local IPC_OK=false IPC_START=$SECONDS
  while [[ $((SECONDS - IPC_START)) -lt 8 ]]; do
    if [[ -f "$OUT_FILE" ]]; then
      rm -f "$OUT_FILE"
      IPC_OK=true
      break
    fi
    sleep 0.5
  done
  $IPC_OK && log "IPC handler active." || log "WARNING: IPC handler not responding (app may still be loading)"

  log "App recovered and ready. PID: $APP_PID  VM: $VM_URL"
  return 0
}

# ═══════════════════════════════════════════════════════════════════
# find — smart widget finding with coordinates
# ═══════════════════════════════════════════════════════════════════
cmd_find() {
  local ACTION="${1:-help}"
  shift || true

  case "$ACTION" in
    text|t)
      local QUERY="${1:?Usage: flutter_audit.sh find text <query> [--tap]}"
      local TAP=false
      [[ "${2:-}" == "--tap" || "${2:-}" == "-t" ]] && TAP=true

      local RESULT
      RESULT=$(ipc_send_and_wait "{\"action\":\"findText\",\"text\":$(jq -n --arg q "$QUERY" '$q')}" 4)
      if [[ $? -eq 2 ]]; then return 2; fi

      local COUNT
      COUNT=$(echo "$RESULT" | jq 'length' 2>/dev/null || echo 0)
      if [[ "$COUNT" -eq 0 ]]; then
        echo "NOT FOUND: \"$QUERY\"" >&2
        return 1
      fi

      echo "$RESULT" | jq -r '.[] | "[\(.text // "?")] at (\(.cx // 0), \(.cy // 0)) size \(.w // 0)x\(.h // 0)"' 2>/dev/null
      echo "---JSON---"
      echo "$RESULT" | jq . 2>/dev/null

      if $TAP; then
        local CX CY
        CX=$(echo "$RESULT" | jq '.[0].cx' 2>/dev/null)
        CY=$(echo "$RESULT" | jq '.[0].cy' 2>/dev/null)
        echo "Tapping at ($CX, $CY)..."
        echo "{\"action\":\"tap\",\"x\":$CX,\"y\":$CY}" > "$CMD_FILE"
      fi
      ;;

    widget|w)
      local QUERY="${1:?Usage: flutter_audit.sh find widget <WidgetName>}"
      local MATCHES
      MATCHES=$("$SCRIPTS/flutter_inspect.sh" find "$QUERY" 2>/dev/null || true)
      if [[ -z "$MATCHES" ]]; then
        echo "NOT FOUND: widget type \"$QUERY\"" >&2
        return 1
      fi
      echo "$MATCHES"
      ;;

    near|n)
      local X="${1:?Usage: flutter_audit.sh find near <x> <y> [radius]}"
      local Y="${2:?}"
      local RADIUS="${3:-50}"
      local RESULT
      RESULT=$(ipc_send_and_wait '{"action":"getAllText"}' 4)
      if [[ $? -eq 2 ]]; then return 2; fi

      echo "$RESULT" | jq -r --argjson x "$X" --argjson y "$Y" --argjson r "$RADIUS" '
        [.[] | . + {dist: (((.cx - $x) * (.cx - $x) + (.cy - $y) * (.cy - $y)) | sqrt)}
        | select(.dist <= $r)]
        | sort_by(.dist)
        | .[] | "  \(.dist | floor)px: \"\((.text // "?")[0:60])\" at (\(.cx), \(.cy))"
      ' 2>/dev/null || echo "No text elements within ${RADIUS}px of ($X, $Y)"
      ;;

    focused|f)
      local RESULT
      RESULT=$(ipc_send_and_wait '{"action":"getAllText"}' 4)
      if [[ $? -eq 2 ]]; then return 2; fi
      echo "$RESULT" | jq -r '.[] | select(.isEditable == true or .isFocused == true) | "Focused: \"\(.text)\" at (\(.cx), \(.cy))"' 2>/dev/null
      echo "TIP: Use hittest to check specific coordinates"
      ;;

    clickable|c)
      local RESULT
      RESULT=$(ipc_send_and_wait '{"action":"getAllText"}' 4)
      if [[ $? -eq 2 ]]; then return 2; fi
      echo "$RESULT" | jq -r '
        [.[] | select(.text != null and (.text | length) > 0 and (.text | length) < 80)]
        | group_by((.cy / 20 | floor) * 20)
        | .[] | "  y~\(.[0].cy | . / 20 | floor | . * 20): \([.[] | "\"\(.text[0:40])\"@(\(.cx),\(.cy))"] | join("  |  "))"
      ' 2>/dev/null
      ;;

    screen|s)
      echo "--- Window ---"
      local WS
      WS=$(ipc_send_and_wait '{"action":"getWindowSize"}' 3) || true
      if [[ -n "$WS" ]]; then
        echo "  Size: $(echo "$WS" | jq -r '"\(.width // "?")x\(.height // "?") @ \(.pixelRatio // "?")x"' 2>/dev/null)"
      fi
      echo "--- Visible Text (grouped by region) ---"
      local RESULT
      RESULT=$(ipc_send_and_wait '{"action":"getAllText"}' 4) || true
      if [[ -n "$RESULT" ]]; then
        echo "$RESULT" | jq -r '
          .[] | select(.text != null and (.text | length) > 0)
          | "  [\(if .cy < 80 then "TOP" elif .cy > 700 then "BOT" else "MID" end)-\(if .cx < 350 then "L" else "R" end)] (\(.cx | tostring | " " * (4 - length) + .)  ,\(.cy | tostring | " " * (4 - length) + .)) \"\(.text[0:50])\(if (.text | length) > 50 then "..." else "" end)\""
        ' 2>/dev/null
      fi
      ;;

    help|*)
      cat <<'EOF'
Usage: flutter_audit.sh find <action> [args...]

  text <query> [--tap]    Find text on screen, return coords. --tap to click.
  widget <WidgetName>     Find widget type in inspector tree.
  near <x> <y> [radius]  List text elements within radius (default 50px).
  focused                 Find currently focused text field.
  clickable               List all visible text grouped by row.
  screen                  Full layout dump (window size + all text).
EOF
      ;;
  esac
}

# ══════════════════════════════════════════════════════════��════════
# Main dispatch
# ══════════════════════════════════════════════════���════════════════
case "$COMMAND" in
  diagnose|d) cmd_diagnose "$@" ;;
  verify|v)   cmd_verify "$@" ;;
  recover|r)  cmd_recover "$@" ;;
  find|f)     cmd_find "$@" ;;
  help|*)
    cat <<'EOF'
flutter_audit.sh — Unified debugging/verification toolkit

COMMANDS:
  diagnose [quick]                Health check (process, VM, IPC, errors, screenshot)
  verify ["description"]          Test both desktop+mobile modes, check for crashes
  recover [full|relaunch|kill]    Kill/clean/rebuild/relaunch the app
  find text <query> [--tap]       Find text on screen, optionally tap it
  find widget <WidgetName>        Find widget in inspector tree
  find near <x> <y> [radius]     List text near a point
  find focused                    Find focused text field
  find clickable                  List all clickable text by row
  find screen                     Full screen layout dump

ALIASES: d=diagnose, v=verify, r=recover, f=find

EXIT CODES:
  diagnose: 0=healthy, 1=not running, 2=VM unreachable, 3=IPC stuck
  verify:   0=pass, 1=fail
  recover:  0=ready, 1=build failed, 2=app won't start
  find:     0=found, 1=not found, 2=app unresponsive
EOF
    ;;
esac
