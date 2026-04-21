#!/usr/bin/env bash
#
# ralph.sh — Unattended infinite Claude Code automation for UniClient
#
# Usage:
#   nix develop --command bash -c "scripts/ralph.sh"
#
# What it does:
#   Loops FOREVER. Each iteration: fresh context, picks next checklist item,
#   implements, tests with GUI toolkit, commits, pushes. Handles every
#   failure gracefully — never stops unless you kill it or checklist is empty.
#
# Failure recovery:
#   - Rate limit → wait 5 min, retry
#   - Network/crash → exponential backoff (30s→60s→120s→5min cap), retry forever
#   - Stuck task → after 3 attempts on same position, tells Claude to skip it
#   - Stall (no commits) → notifies you, keeps going
#   - NEVER stops on its own (except: checklist fully checked)
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

# ─── Logging ─────────────────────────────────────────────────────
LOG_DIR="$PROJECT_ROOT/logs/ralph"
mkdir -p "$LOG_DIR"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/run_${RUN_ID}.log"
ITER_LOG_DIR="$LOG_DIR/iterations_${RUN_ID}"
mkdir -p "$ITER_LOG_DIR"

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
  pkill uniclient 2>/dev/null || true
  rm -f "$LOCKFILE"
  notify "Ralph stopped after $ITERATION iterations ($TOTAL_COMMITS commits)."
  log "=== Final stats: $ITERATION iterations, $TOTAL_COMMITS commits ==="
}
trap cleanup EXIT

# ─── Build the prompt ────────────────────────────────────────────
# $1 = extra context (optional, for skip instructions etc.)
build_prompt() {
  local extra="${1:-}"
  cat <<'PROMPT_END'
You are running in unattended automation mode (ralph loop). No human is watching.

MANDATORY FIRST STEPS — do these in order:
1. Read CLAUDE.md (the entire file — every rule is binding)
2. Read checklist/gui.md and find the FIRST unchecked "- [ ]" item
   - Each "- [ ]" entry is one checklist item; scan top-to-bottom
   - If an entire section is done, move to the next section

THEN:
3. Read the relevant spec section cited in the checklist entry (e.g. §4.2 → read that section of research/telegram_desktop_ui.md)
4. Read existing source files BEFORE writing code
5. Implement the feature completely — no stubs, no placeholders
6. Build and verify — do NOT skip any step:
   a. Build Go: scripts/build_go.sh linux
   b. Build Flutter: scripts/build_flutter.sh linux debug
   c. Launch app: cd dart/build/linux/x64/debug/bundle && nohup ./uniclient > /tmp/uniclient_log.txt 2>&1 &
   d. Wait 3 seconds for startup
   e. Test BOTH modes — the app opens narrow by default, so desktop mode WILL be missed if you skip this:
      - Desktop first: scripts/flutter_interact.sh resize desktop
        Screenshot, verify, test interactions
      - Then mobile: scripts/flutter_interact.sh resize mobile
        Screenshot, verify, test interactions
      Your feature must work in BOTH modes or it's not done.
   f. Kill app: pkill uniclient
7. If it works: DELETE the completed item from checklist/gui.md, git add changed files, commit, push
8. If build/test fails: fix and retry (up to 3 attempts in this session)
   - If still broken after 3 attempts: commit partial progress with "WIP:" prefix, push, exit
9. Update checklist/ docs if relevant

RULES:
- ONE item per session. Implement it, test it to perfection, push it. The loop gives you fresh context next round.
- ALWAYS delete completed items from checklist/gui.md — never mark [x], just remove the line. Git log is the record of done work.
- ALWAYS commit something — working code or WIP progress.
- ALWAYS push after commit: git push origin main
- Do NOT declare something working until you have visually verified it via screenshot and tested every interaction.
- Exit cleanly when done. The loop restarts you with fresh context.

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

  # Append extra context if provided
  if [[ -n "$extra" ]]; then
    echo ""
    echo "$extra"
  fi
}

# ─── Main Loop ───────────────────────────────────────────────────
ITERATION=0
TOTAL_COMMITS=0
CONSECUTIVE_FAILURES=0
STALL_ITERATIONS=0
LAST_COMMIT_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"

log "=== Ralph loop starting ==="
log "All output streams here. Logs also saved to: $LOG_FILE"
log "Kill with: Ctrl+C"

while true; do
  ITERATION=$((ITERATION + 1))
  ITER_FILE="$ITER_LOG_DIR/iter_$(printf '%04d' $ITERATION).log"

  log "── Iteration $ITERATION (commits so far: $TOTAL_COMMITS) ──"

  # ─── Check checklist exists and has unchecked items ──────────
  if [[ ! -f "$PROJECT_ROOT/checklist/gui.md" ]]; then
    log "checklist/gui.md not found. Nothing to do."
    notify "Ralph: checklist/gui.md not found"
    sleep 60
    continue
  fi
  REMAINING=$(grep -c '^- \[ \]' "$PROJECT_ROOT/checklist/gui.md" 2>/dev/null || echo 0)
  if [[ "$REMAINING" -eq 0 ]]; then
    log "All checklist items completed! ($TOTAL_COMMITS total commits)"
    notify "Ralph: ALL DONE! $TOTAL_COMMITS commits across $ITERATION iterations."
    break
  fi
  log "Remaining checklist items: $REMAINING"

  # ─── Kill leftover app ──────────────────────────────────────
  pkill uniclient 2>/dev/null || true

  # ─── Build prompt with context ──────────────────────────────
  EXTRA=""
  if [[ $STALL_ITERATIONS -ge 3 ]]; then
    STUCK_ITEM="$(grep -m1 '^- \[ \]' "$PROJECT_ROOT/checklist/gui.md" 2>/dev/null || echo "unknown")"
    EXTRA="WARNING: The last $STALL_ITERATIONS iterations produced no commits. You are likely stuck on this item:
  $STUCK_ITEM
SKIP IT — delete it from checklist/gui.md and try the NEXT item instead.
If all remaining items seem blocked, commit a note explaining why and exit."
    log "Injecting skip instruction (stalled $STALL_ITERATIONS iterations on: $STUCK_ITEM)"
  fi

  PROMPT="$(build_prompt "$EXTRA")"

# ─── Invoke Claude ──────────────────────────────────────────
  log "Invoking Claude Code..."
  set +e
  claude \
    --print \
    --dangerously-skip-permissions \
    --model claude-opus-4-6 \
    --effort max \
--output-format stream-json \
    --verbose \
    -p "$PROMPT" \
    2>&1 \
    | tee "$ITER_FILE.jsonl" \
    | jq -Rr --unbuffered --arg root "$PROJECT_ROOT/" '
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
        else empty end' \
    | tee -a "$ITER_FILE"
  EXIT_CODE=${PIPESTATUS[0]}
  set -e

  # ─── Check for new commits ─────────────────────────────────
  CURRENT_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"
  if [[ "$CURRENT_HASH" != "$LAST_COMMIT_HASH" ]]; then
    NEW_COMMITS=$(git -C "$PROJECT_ROOT" log --oneline "$LAST_COMMIT_HASH".."$CURRENT_HASH" 2>/dev/null | wc -l)
    TOTAL_COMMITS=$((TOTAL_COMMITS + NEW_COMMITS))
    LAST_COMMIT_HASH="$CURRENT_HASH"
    STALL_ITERATIONS=0
    CONSECUTIVE_FAILURES=0
    log "Progress! $NEW_COMMITS new commit(s). Total: $TOTAL_COMMITS"
    log "Latest: $(git -C "$PROJECT_ROOT" log --oneline -1)"
    # Kill uniclient after successful push
    pkill uniclient 2>/dev/null || true
    log "Killed uniclient after push"
  else
    STALL_ITERATIONS=$((STALL_ITERATIONS + 1))
    log "No new commits. Stall count: $STALL_ITERATIONS"
    if [[ $((STALL_ITERATIONS % 5)) -eq 0 ]]; then
      notify "Ralph: $STALL_ITERATIONS iterations without a commit (total commits: $TOTAL_COMMITS)"
    fi
  fi

  # ─── Handle exit codes ─────────────────────────────────────
  if [[ $EXIT_CODE -eq 0 ]]; then
    CONSECUTIVE_FAILURES=0
    sleep "$COOLDOWN_SECONDS"

  elif [[ $EXIT_CODE -eq 2 ]]; then
    # Rate limited
    log "Rate limited. Waiting ${RATE_LIMIT_WAIT}s..."
    notify "Ralph: rate limited, waiting $(( RATE_LIMIT_WAIT / 60 ))min"
    sleep "$RATE_LIMIT_WAIT"
    CONSECUTIVE_FAILURES=0

  else
    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    # Exponential backoff: 30, 60, 120, 240, 300, 300, 300...
    BACKOFF=$(( BACKOFF_BASE * (2 ** (CONSECUTIVE_FAILURES - 1)) ))
    [[ $BACKOFF -gt $BACKOFF_MAX ]] && BACKOFF=$BACKOFF_MAX
    log "Failure #$CONSECUTIVE_FAILURES. Backing off ${BACKOFF}s..."

    if [[ $((CONSECUTIVE_FAILURES % 5)) -eq 0 ]]; then
      notify "Ralph: $CONSECUTIVE_FAILURES consecutive failures, still retrying"
    fi

    sleep "$BACKOFF"
  fi
done
