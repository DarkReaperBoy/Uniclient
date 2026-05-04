#!/usr/bin/env bash
#
# ralph.sh — Two-stage unattended Claude Code automation for UniClient
#
# Usage:
#   nix develop --command bash -c "scripts/ralph.sh"
#
# Two-stage loop:
#   Stage 1 (IMPLEMENT): Fresh session picks next checklist item, implements it,
#     commits with [unverified] tag. Does NOT push, does NOT remove from checklist.
#   Stage 2 (VERIFY): Fresh session builds, launches, tests the implementation
#     thoroughly in both desktop+mobile modes using flutter_audit.sh.
#     - PASS → removes item from checklist, commits, pushes.
#     - FAIL → writes feedback, loops back to Stage 1 (fresh session with feedback).
#
# Failure recovery:
#   - Rate limit → wait 5 min, retry
#   - Network/crash → exponential backoff (30s→60s→120s→5min cap)
#   - Stuck item → after 3 impl+verify cycles, skip it
#   - NEVER stops on its own (except: checklist empty)
#
# Kill it: Ctrl+C or `kill $(pgrep -f ralph.sh)`

set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"

# ─── Configuration ───────────────────────────────────────────────
COOLDOWN_SECONDS="${RALPH_COOLDOWN:-0}"
RATE_LIMIT_WAIT="${RALPH_RATE_WAIT:-300}"
BACKOFF_BASE=30
BACKOFF_MAX=300
MAX_ATTEMPTS_PER_ITEM=3

# ─── Logging ─────────────────────────────────────────────────────
LOG_DIR="$PROJECT_ROOT/logs/ralph"
mkdir -p "$LOG_DIR"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/run_${RUN_ID}.log"
ITER_LOG_DIR="$LOG_DIR/iterations_${RUN_ID}"
mkdir -p "$ITER_LOG_DIR"

FEEDBACK_FILE="/tmp/ralph_feedback.txt"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
notify() {
  log "NOTIFY: $*"
  command -v notify-send &>/dev/null && notify-send -u critical "Ralph" "$*" 2>/dev/null || true
}

# ─── Gitignore logs ──────────────────────────────────────────────
for pat in "logs/" ".ralph.lock"; do
  grep -q "^${pat}$" "$PROJECT_ROOT/.gitignore" 2>/dev/null || echo "$pat" >> "$PROJECT_ROOT/.gitignore"
done

# ─── Lockfile ────────────────────────────────────────────────────
LOCKFILE="$PROJECT_ROOT/.ralph.lock"
if [[ -f "$LOCKFILE" ]] && kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
  echo "Another ralph instance is running (PID $(cat "$LOCKFILE")). Exiting."
  exit 1
fi
echo $$ > "$LOCKFILE"

# ─── Cleanup on exit ────────────────────────────────────────────
cleanup() {
  log "Shutting down..."
  pkill -x uniclient 2>/dev/null || true
  rm -f "$LOCKFILE" "$FEEDBACK_FILE"
  notify "Ralph stopped after $ITERATION iterations ($TOTAL_COMMITS verified commits)."
  log "=== Final stats: $ITERATION iterations, $TOTAL_COMMITS verified commits ==="
}
trap cleanup EXIT

# ─── jq stream formatter (shared) ───────────────────────────────
JQ_FORMATTER='
  try fromjson catch empty | . as $e |
  if $e.type == "assistant" then
    ($e.message.content // [])[] |
      if .type == "text" then
        "\n\(.text | split("\n") | map("│ \(.)") | join("\n"))\n"
      elif .type == "tool_use" then
        if .name == "Read" then       "\n📖 Read \(.input.file_path | ltrimstr($root))"
        elif .name == "Edit" then     "\n✏️  Edit \(.input.file_path | ltrimstr($root))"
        elif .name == "Write" then    "\n📝 Write \(.input.file_path | ltrimstr($root))"
        elif .name == "Bash" then     "\n$ \(.input.command | gsub("\n"; " ; ") | .[:200])"
        elif .name == "Grep" then     "\n🔍 Grep \"\(.input.pattern // "")\" in \(.input.path // "." | ltrimstr($root))"
        elif .name == "Glob" then     "\n🔍 Glob \(.input.pattern // "")"
        elif .name == "Agent" then    "\n🤖 Agent: \(.input.description // "")"
        else                          "\n🔧 \(.name)"
        end
      else empty end
  elif $e.type == "user" then
    ($e.message.content // [])[] |
      if .type == "tool_result" then
        (.content | tostring | split("\n")) as $lines |
        if ($lines | length) == 0 or ($lines[0] | length) == 0 then "  ✓"
        elif ($lines[0] | test("(?i)^(error|fail|exception|fatal)")) then "  ❌ \($lines[0][:200])"
        else "  ✓ \($lines[0][:160])"
        end
      else empty end
  elif $e.type == "system" and $e.subtype == "init" then "\n🚀 Session \($e.session_id // "")\n"
  elif $e.type == "result" then "\n✅ \($e.subtype // "done") — \(($e.duration_ms // 0) / 1000)s, $\($e.total_cost_usd // 0)\n"
  else empty end'

# ─── Invoke Claude (shared helper) ──────────────────────────────
# $1 = prompt, $2 = log file path, $3 = stage label
invoke_claude() {
  local prompt="$1"
  local iter_file="$2"
  local label="$3"

  log "Invoking Claude Code ($label)..."
  set +e
  claude \
    --print \
    --dangerously-skip-permissions \
    --model claude-opus-4-6 \
    --effort max \
    --output-format stream-json \
    --verbose \
    -p "$prompt" \
    2>&1 \
    | tee "$iter_file.jsonl" \
    | jq -Rr --unbuffered --arg root "$PROJECT_ROOT/" "$JQ_FORMATTER" \
    | tee -a "$iter_file"
  local code=${PIPESTATUS[0]}
  set -e
  return $code
}

# ═════════════════════════════════════════════════════════════════
# STAGE 1 PROMPT — Implementation
# ═════════════════════════════════════════════════════════════════
# $1 = extra context (feedback from verification, skip instructions, etc.)
build_impl_prompt() {
  local extra="${1:-}"
  cat <<'PROMPT_END'
You are running in unattended automation mode (ralph loop). No human is watching.
This is STAGE 1 (IMPLEMENTATION). Your job: implement ONE checklist item. A separate
verification session will test your work afterwards — you do NOT need to be perfect,
but you must produce a buildable, runnable implementation.

MANDATORY FIRST STEPS — do these in order:
1. Read CLAUDE.md (the entire file — every rule is binding)
2. Read checklist/gui.md and find the FIRST unchecked "- [ ]" item
   - Each "- [ ]" entry is one checklist item; scan top-to-bottom
   - If an entire section is done, move to the next section

THEN:
3. Read the relevant spec section cited in the checklist entry (e.g. §4.2 → read that section of research/telegram_desktop_ui.md)
4. Read existing source files BEFORE writing code
5. Implement the feature completely — no stubs, no placeholders
6. Build and do a basic sanity check:
   a. Build Go: scripts/build_go.sh linux
   b. Build Flutter: scripts/build_flutter.sh linux debug
   c. Launch app: cd dart/build/linux/x64/debug/bundle && nohup ./uniclient > /tmp/uniclient_log.txt 2>&1 &
   d. Wait 3 seconds, screenshot with scripts/flutter_inspect.sh screenshot /tmp/ss.png
   e. Verify it didn't crash and the feature is roughly visible
   f. Kill app: pkill uniclient
7. Commit your changes with "[unverified]" prefix in the commit message:
   git add <changed files>
   git commit -m "[unverified] <description of what you implemented>"
8. Do NOT push. Do NOT delete the checklist item. The verification stage handles that.

RULES:
- ONE item per session. Implement it, basic sanity check, commit [unverified].
- Do NOT push to remote — verification stage pushes after confirming.
- Do NOT delete the checklist item — verification stage does that.
- Do NOT do exhaustive testing — just confirm it builds and doesn't crash.
- Exit cleanly when done. A fresh verification session runs next.

TELEGRAM ONLY:
- The app has multiple accounts (Telegram, Rubika, etc.). ONLY use the TELEGRAM account for testing.
- Do NOT open, interact with, or screenshot Rubika/Bale/Matrix/other platform chats.
- If the app opens to a non-Telegram chat, switch to the Telegram account first.
- All GUI work targets Telegram Desktop UI replication. Other platforms are irrelevant.

STAY ON TASK — do NOT:
- Read SPEC.md, auth/auth.md, or any research/ file EXCEPT the spec section cited in your checklist item.
- Refactor, clean up, or "improve" code that isn't part of your checklist item.
- Fix unrelated bugs you discover — log them in checklist/gui.md under "## Bugs" instead.
- Add comments, docstrings, or type annotations to code you didn't change.
- Read files beyond what's needed for the current item. Stay narrow.
PROMPT_END

  if [[ -n "$extra" ]]; then
    echo ""
    echo "$extra"
  fi
}

# ═════════════════════════════════════════════════════════════════
# STAGE 2 PROMPT — Verification
# ═════════════════════════════════════════════════════════════════
# $1 = the checklist item text being verified
build_verify_prompt() {
  local item="${1:-unknown item}"
  local latest_diff
  latest_diff="$(git -C "$PROJECT_ROOT" diff HEAD~1 --stat 2>/dev/null || echo '(no diff available)')"
  local latest_msg
  latest_msg="$(git -C "$PROJECT_ROOT" log -1 --format='%s' 2>/dev/null || echo '(no commit)')"

  cat <<PROMPT_END
You are running in unattended automation mode (ralph loop). No human is watching.
This is STAGE 2 (VERIFICATION). A separate implementation session just committed code.
Your ONLY job: test whether the implementation actually works. You do NOT write code
(unless a trivial 1-line fix is needed). You are the quality gate.

THE ITEM BEING VERIFIED:
$item

LATEST COMMIT: $latest_msg
FILES CHANGED:
$latest_diff

MANDATORY STEPS:
1. Read CLAUDE.md (the entire file — every rule is binding)
2. Read the checklist item above and understand what it claims to implement
3. Read the spec section cited in the item (from research/telegram_desktop_ui.md)
4. Build and launch the app:
   a. Build Go: scripts/build_go.sh linux
   b. Build Flutter: scripts/build_flutter.sh linux debug
   c. Launch: cd dart/build/linux/x64/debug/bundle && nohup ./uniclient > /tmp/uniclient_log.txt 2>&1 &
   d. Wait 3 seconds for startup
5. Run the full verification suite:
   scripts/flutter_audit.sh verify "$(echo "$item" | head -c 80)"
6. Test BOTH display modes thoroughly:
   a. Desktop (1024x768): scripts/flutter_interact.sh resize desktop
      - Screenshot: scripts/flutter_inspect.sh screenshot /tmp/verify_desktop.png
      - Test all interactions related to the feature (tap, scroll, type, etc.)
      - Verify visual correctness against the spec
   b. Mobile (400x720): scripts/flutter_interact.sh resize mobile
      - Screenshot: scripts/flutter_inspect.sh screenshot /tmp/verify_mobile.png
      - Same interaction tests
7. Check for regressions:
   - Does the app crash? Check /tmp/uniclient_log.txt for exceptions
   - Do other features still work? Quick scroll through chat list, open a chat
8. Kill app: pkill uniclient

THEN DECIDE:

IF PASS (feature works correctly in both modes, no crashes, matches spec):
  a. Delete the verified item from checklist/gui.md (remove the entire "- [ ]" line)
  b. Commit: git add checklist/gui.md && git commit -m "Verify & close: <short description>"
  c. Push everything: git push origin main
  d. Exit cleanly.

IF FAIL (feature broken, doesn't match spec, crashes, only works in one mode):
  a. Write a detailed failure report to /tmp/ralph_feedback.txt explaining:
     - What EXACTLY is broken (be specific — "button at 500,300 does nothing" not "doesn't work")
     - What the spec says it SHOULD do
     - Any error messages from logs
     - Which mode(s) it fails in (desktop/mobile/both)
  b. Do NOT modify any code (unless it's a trivial 1-line typo fix — then fix, rebuild, re-verify)
  c. Do NOT push. Do NOT delete the checklist item.
  d. Exit cleanly. A fresh implementation session will retry with your feedback.

RULES:
- You are a TESTER, not a developer. Your job is to break things, not fix them.
- Be harsh. If something is off by a few pixels from spec, that's a fail.
- If you can't verify it visually (screenshot fails, app won't launch), that's a fail.
- The /tmp/ralph_feedback.txt file is critical — the next implementation session reads it.
  Be specific enough that someone with no context can fix the issue.
- Do NOT refactor, clean up, or change anything unrelated.
- Do NOT read SPEC.md, auth/auth.md, or research/ files beyond the cited spec section.
PROMPT_END
}

# ─── Main Loop ───────────────────────────────────────────────────
ITERATION=0
TOTAL_COMMITS=0
CONSECUTIVE_FAILURES=0
ITEM_ATTEMPTS=0
LAST_COMMIT_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"

log "=== Ralph two-stage loop starting ==="
log "Logs: $LOG_FILE"
log "Kill with: Ctrl+C"

while true; do
  ITERATION=$((ITERATION + 1))

  log "══ Iteration $ITERATION (verified commits: $TOTAL_COMMITS) ══"

  # ─── Check checklist exists and has unchecked items ──────────
  if [[ ! -f "$PROJECT_ROOT/checklist/gui.md" ]]; then
    log "checklist/gui.md not found. Nothing to do."
    notify "Ralph: checklist/gui.md not found"
    sleep 60
    continue
  fi

  REMAINING=$(grep -c '^- \[ \]' "$PROJECT_ROOT/checklist/gui.md" 2>/dev/null || echo 0)
  if [[ "$REMAINING" -eq 0 ]]; then
    log "All checklist items completed! ($TOTAL_COMMITS verified commits)"
    notify "Ralph: ALL DONE! $TOTAL_COMMITS verified commits across $ITERATION iterations."
    break
  fi
  log "Remaining checklist items: $REMAINING"

  # ─── Get current item ──────────────────────────────────────────
  CURRENT_ITEM="$(grep -m1 '^- \[ \]' "$PROJECT_ROOT/checklist/gui.md" 2>/dev/null || echo "unknown")"
  log "Current item: $CURRENT_ITEM"

  # ─── Kill leftover app ────────────────────────────────────────
  pkill -x uniclient 2>/dev/null || true
  rm -f /tmp/uniclient_debug_cmd.json /tmp/uniclient_debug_out.json

  # ═══════════════════════════════════════════════════════════════
  # STAGE 1: IMPLEMENTATION (fresh session)
  # ═══════════════════════════════════════════════════════════════
  IMPL_FILE="$ITER_LOG_DIR/iter_$(printf '%04d' $ITERATION)_impl.log"

  IMPL_EXTRA=""
  # Include feedback from failed verification if present
  if [[ -f "$FEEDBACK_FILE" ]]; then
    FEEDBACK_CONTENT="$(cat "$FEEDBACK_FILE")"
    IMPL_EXTRA="IMPORTANT — PREVIOUS VERIFICATION FAILED. Here is the feedback from the verifier:
--- FEEDBACK START ---
$FEEDBACK_CONTENT
--- FEEDBACK END ---
This is attempt $((ITEM_ATTEMPTS + 1)) of $MAX_ATTEMPTS_PER_ITEM for this item.
Fix the issues described above. The verifier will test again after you commit."
    rm -f "$FEEDBACK_FILE"
    log "Including verification feedback (attempt $((ITEM_ATTEMPTS + 1))/$MAX_ATTEMPTS_PER_ITEM)"
  fi

  # Skip logic
  if [[ $ITEM_ATTEMPTS -ge $MAX_ATTEMPTS_PER_ITEM ]]; then
    log "Item failed $MAX_ATTEMPTS_PER_ITEM times. Skipping."
    notify "Ralph: skipping item after $MAX_ATTEMPTS_PER_ITEM failed attempts"
    IMPL_EXTRA="WARNING: This item has failed verification $MAX_ATTEMPTS_PER_ITEM times.
SKIP IT — delete it from checklist/gui.md, commit that deletion, and exit.
The item was: $CURRENT_ITEM"
    ITEM_ATTEMPTS=0
  fi

  IMPL_PROMPT="$(build_impl_prompt "$IMPL_EXTRA")"

  invoke_claude "$IMPL_PROMPT" "$IMPL_FILE" "STAGE 1: IMPLEMENT"
  IMPL_EXIT=$?

  # Handle rate limit / crash
  if [[ $IMPL_EXIT -eq 2 ]]; then
    log "Rate limited during implementation. Waiting ${RATE_LIMIT_WAIT}s..."
    notify "Ralph: rate limited, waiting $(( RATE_LIMIT_WAIT / 60 ))min"
    sleep "$RATE_LIMIT_WAIT"
    continue
  elif [[ $IMPL_EXIT -ne 0 ]]; then
    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    BACKOFF=$(( BACKOFF_BASE * (2 ** (CONSECUTIVE_FAILURES - 1)) ))
    [[ $BACKOFF -gt $BACKOFF_MAX ]] && BACKOFF=$BACKOFF_MAX
    log "Implementation failed (exit $IMPL_EXIT). Backing off ${BACKOFF}s..."
    sleep "$BACKOFF"
    continue
  fi
  CONSECUTIVE_FAILURES=0

  # Check if implementation committed anything
  IMPL_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"
  if [[ "$IMPL_HASH" == "$LAST_COMMIT_HASH" ]]; then
    log "Implementation produced no commit. Counting as stall."
    ITEM_ATTEMPTS=$((ITEM_ATTEMPTS + 1))
    sleep "$COOLDOWN_SECONDS"
    continue
  fi

  log "Implementation committed: $(git -C "$PROJECT_ROOT" log -1 --oneline)"

  # ─── Kill leftover app between stages ─────────────────────────
  pkill -x uniclient 2>/dev/null || true
  rm -f /tmp/uniclient_debug_cmd.json /tmp/uniclient_debug_out.json
  sleep 2

  # ═══════════════════════════════════════════════════════════════
  # STAGE 2: VERIFICATION (fresh session)
  # ═══════════════════════════════════════════════════════════════
  VERIFY_FILE="$ITER_LOG_DIR/iter_$(printf '%04d' $ITERATION)_verify.log"
  rm -f "$FEEDBACK_FILE"

  VERIFY_PROMPT="$(build_verify_prompt "$CURRENT_ITEM")"

  invoke_claude "$VERIFY_PROMPT" "$VERIFY_FILE" "STAGE 2: VERIFY"
  VERIFY_EXIT=$?

  # Handle rate limit / crash for verification
  if [[ $VERIFY_EXIT -eq 2 ]]; then
    log "Rate limited during verification. Waiting ${RATE_LIMIT_WAIT}s..."
    sleep "$RATE_LIMIT_WAIT"
    continue
  elif [[ $VERIFY_EXIT -ne 0 ]]; then
    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    BACKOFF=$(( BACKOFF_BASE * (2 ** (CONSECUTIVE_FAILURES - 1)) ))
    [[ $BACKOFF -gt $BACKOFF_MAX ]] && BACKOFF=$BACKOFF_MAX
    log "Verification crashed (exit $VERIFY_EXIT). Backing off ${BACKOFF}s..."
    sleep "$BACKOFF"
    continue
  fi
  CONSECUTIVE_FAILURES=0

  # ─── Check verification result ────────────────────────────────
  VERIFY_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"

  if [[ "$VERIFY_HASH" != "$IMPL_HASH" ]]; then
    # Verification made new commits (pushed + removed checklist item) → PASS
    NEW_COMMITS=$(git -C "$PROJECT_ROOT" log --oneline "$LAST_COMMIT_HASH".."$VERIFY_HASH" 2>/dev/null | wc -l)
    TOTAL_COMMITS=$((TOTAL_COMMITS + NEW_COMMITS))
    LAST_COMMIT_HASH="$VERIFY_HASH"
    ITEM_ATTEMPTS=0
    log "✅ VERIFIED & PUSHED! $NEW_COMMITS commit(s). Total verified: $TOTAL_COMMITS"
    log "Latest: $(git -C "$PROJECT_ROOT" log --oneline -1)"
    notify "Ralph: verified commit #$TOTAL_COMMITS — $(git -C "$PROJECT_ROOT" log -1 --format='%s')"
  elif [[ -f "$FEEDBACK_FILE" ]]; then
    # Feedback file exists → FAIL, retry with feedback
    ITEM_ATTEMPTS=$((ITEM_ATTEMPTS + 1))
    log "❌ VERIFICATION FAILED (attempt $ITEM_ATTEMPTS/$MAX_ATTEMPTS_PER_ITEM)"
    log "Feedback: $(head -3 "$FEEDBACK_FILE")"
    # Don't update LAST_COMMIT_HASH — the [unverified] commit stays
    # Next iteration will be a fresh implementation session with the feedback
  else
    # No new commits, no feedback file — ambiguous, treat as stall
    ITEM_ATTEMPTS=$((ITEM_ATTEMPTS + 1))
    log "⚠️  Verification produced no result (no push, no feedback). Attempt $ITEM_ATTEMPTS/$MAX_ATTEMPTS_PER_ITEM"
  fi

  # Kill app between iterations
  pkill -x uniclient 2>/dev/null || true

  sleep "$COOLDOWN_SECONDS"
done
