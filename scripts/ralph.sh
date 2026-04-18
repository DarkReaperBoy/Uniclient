#!/usr/bin/env bash
#
# ralph.sh — Unattended infinite Claude Code automation for UniClient
#
# Usage:
#   nix develop --command bash -c "scripts/ralph.sh"
#
# What it does:
#   Loops FOREVER. Each iteration: fresh context, picks next todolist item,
#   implements, tests with GUI toolkit, commits, pushes. Handles every
#   failure gracefully — never stops unless you kill it or todolist is empty.
#
# Failure recovery:
#   - Rate limit → wait 5 min, retry
#   - Network/crash → exponential backoff (30s→60s→120s→5min cap), retry forever
#   - Stuck task → after 3 attempts on same position, tells Claude to skip it
#   - Stall (no commits) → notifies you, keeps going
#   - NEVER stops on its own (except: todolist.md deleted)
#
# Kill it: Ctrl+C or `kill $(pgrep -f ralph.sh)`

set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"

# ─── Configuration ───────────────────────────────────────────────
COOLDOWN_SECONDS="${RALPH_COOLDOWN:-10}"
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
if ! grep -q "^logs/" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
  echo "logs/" >> "$PROJECT_ROOT/.gitignore"
fi

# ─── Cleanup on exit ────────────────────────────────────────────
cleanup() {
  log "Shutting down..."
  pkill -f "bundle/uniclient" 2>/dev/null || true
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
2. Read todolist.md
3. Check git log --oneline -20 to see what was already done recently
4. Pick the FIRST uncompleted sub-item from todolist.md that wasn't already done
   - If a section has bullet points (- items), each bullet is ONE iteration
   - Skip bullets that already have matching commits in git log
   - If the entire section is done, move to the next section

THEN:
5. Read the relevant spec sections and source files BEFORE writing code
6. Implement the feature completely — no stubs, no placeholders
7. Build and verify:
   a. Build Go: scripts/build_go.sh linux
   b. Build Flutter: scripts/build_flutter.sh linux debug
   c. Launch app: cd dart/build/linux/x64/debug/bundle && nohup ./uniclient > /tmp/uniclient_log.txt 2>&1 &
   d. Wait 3 seconds for startup
   e. Screenshot: scripts/flutter_inspect.sh screenshot /tmp/ralph_ss.png
   f. Read screenshot to verify visually
   g. Test interaction with scripts/flutter_interact.sh if applicable
   h. Kill app: pkill -f "bundle/uniclient"
8. If it works: remove the completed bullet from todolist.md, git add changed files, commit, push
9. If build/test fails: fix and retry (up to 3 attempts in this session)
   - If still broken after 3 attempts: commit partial progress with "WIP:" prefix, push, exit
10. Update checklist/ if relevant

RULES:
- ONE bullet point per session. Small, focused, atomic.
- ALWAYS commit something — working code or WIP progress.
- ALWAYS push after commit: git push origin main
- ALWAYS remove completed items from todolist.md before committing.
- Exit cleanly when done. The loop restarts you with fresh context.
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

log "=== Ralph loop starting (infinite, subscription mode) ==="
log "Kill with: Ctrl+C or kill \$\$"
log "Monitor with: tail -f $LOG_FILE"

while true; do
  ITERATION=$((ITERATION + 1))
  ITER_FILE="$ITER_LOG_DIR/iter_$(printf '%04d' $ITERATION).log"
  ITER_START="$(date +%s)"

  log "── Iteration $ITERATION (commits so far: $TOTAL_COMMITS) ──"

  # ─── Check todolist exists ───────────────────────────────────
  if [[ ! -f "$PROJECT_ROOT/todolist.md" ]]; then
    log "todolist.md gone. All done?"
    notify "Ralph: todolist.md not found — all done?"
    sleep 60  # wait in case it's a transient git issue
    continue  # don't stop — it might reappear after a git operation
  fi

  # ─── Kill leftover app ──────────────────────────────────────
  pkill -f "bundle/uniclient" 2>/dev/null || true

  # ─── Build prompt with context ──────────────────────────────
  EXTRA=""
  if [[ $STALL_ITERATIONS -ge 3 ]]; then
    EXTRA="WARNING: The last $STALL_ITERATIONS iterations produced no commits. You may be stuck on a task.
Try a DIFFERENT todolist item — skip the one you've been attempting. Look further down the list.
If all remaining items seem blocked, commit a note explaining why and exit."
    log "Injecting skip instruction (stalled $STALL_ITERATIONS iterations)"
  fi

  PROMPT="$(build_prompt "$EXTRA")"

# ─── Invoke Claude ──────────────────────────────────────────
  log "Invoking Claude Code..."
  set +e
  claude \
    --print \
    --dangerously-skip-permissions \
    --model claude-opus-4-7 \
    --effort max \
    --output-format stream-json \
    --verbose \
    -p "$PROMPT" \
    2>&1 \
    | tee "$ITER_FILE.jsonl" \
    | jq -Rr --unbuffered '
        try fromjson catch empty | . as $e |
        if $e.type == "assistant" then
          ($e.message.content // [])[] |
            if .type == "text" then "💬 \(.text | split("\n")[0])"
            elif .type == "tool_use" then "🔧 \(.name): \(.input | tostring | .[:140])"
            else empty end
        elif $e.type == "user" then
          ($e.message.content // [])[] |
            if .type == "tool_result" then
              "  ↳ \((.content | tostring | split("\n") | .[0])[:140])"
            else empty end
        elif $e.type == "system" and $e.subtype == "init" then "🚀 session \($e.session_id // "")"
        elif $e.type == "result" then "✅ \($e.subtype // "done") (\(($e.duration_ms // 0) / 1000)s, $\($e.total_cost_usd // 0))"
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
