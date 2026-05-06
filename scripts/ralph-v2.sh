#!/usr/bin/env bash
#
# ralph-v2.sh — Fully autonomous implement→verify→audit loop
#
# Designed by a 12-agent tribunal debate (7 rounds, 100k+ words).
# Incorporates: three-layer audit, circuit breakers, partial-failure
# semantics, proportional severity (Weber's Law), SSIM regression,
# conflict-aware regression gating, model routing, divergence detection.
#
# Two modes that alternate:
#   MODE 1 (IMPLEMENT+VERIFY): Two-stage ralph loop — pick checklist item,
#     implement (Opus), verify (Opus), push. Until gui.md empty.
#   MODE 2 (AUDIT): Three-layer audit of codebase vs spec:
#     Layer 1: Parallel Sonnet sessions extract constraint violations ($0.087/session)
#     Layer 2: Journey-based visual audit with SSIM regression ($0.13/session)
#     Layer 3: Generate new gui.md from findings, return to MODE 1
#     Convergence: zero critical+major findings for 2 consecutive cycles → done.
#
# No human gate. Fully autonomous. No artificial cost ceiling.
# Safety: circuit breakers, divergence rollback, partial failure, max 5 audit cycles.
#
# Usage: nix develop --command bash -c "scripts/ralph-v2.sh"
# Kill:  Ctrl+C or kill $(pgrep -f ralph-v2.sh)

set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"
SCRIPTS="$PROJECT_ROOT/scripts"
SPEC_FILE="$PROJECT_ROOT/research/telegram_desktop_ui.md"

# ─── Startup checks ─────────────────────────────────────────────
for cmd in claude jq magick git; do
  command -v "$cmd" &>/dev/null || { echo "FATAL: '$cmd' not found in PATH. Run inside nix develop."; exit 1; }
done

# ─── Configuration ───────────────────────────────────────────────
RATE_LIMIT_WAIT="${RALPH_RATE_WAIT:-300}"
BACKOFF_BASE=30
BACKOFF_MAX=300
MAX_IMPL_ATTEMPTS=3
MAX_AUDIT_CYCLES=5
CONVERGE_THRESHOLD=2
CIRCUIT_BREAKER_THRESHOLD=3
CIRCUIT_BREAKER_COOLDOWN=300
SESSION_TIMEOUT=600

# ─── Logging ─────────────────────────────────────────────────────
LOG_DIR="$PROJECT_ROOT/logs/ralph"
mkdir -p "$LOG_DIR"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$LOG_DIR/run_${RUN_ID}.log"
ITER_LOG_DIR="$LOG_DIR/iterations_${RUN_ID}"
mkdir -p "$ITER_LOG_DIR"

FEEDBACK_FILE="/tmp/ralph_feedback.txt"
COST_LOG="$LOG_DIR/cost_${RUN_ID}.log"
PROGRESS_FILE="/tmp/ralph_audit_progress.json"
AUDIT_DATA="$PROJECT_ROOT/audit"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
notify() {
  log "NOTIFY: $*"
  command -v notify-send &>/dev/null && notify-send -u critical "Ralph v2" "$*" 2>/dev/null || true
}
update_progress() {
  local phase="$1" step="$2" detail="${3:-}"
  echo "{\"phase\":\"$phase\",\"step\":\"$step\",\"detail\":\"$detail\",\"time\":\"$(date -Iseconds)\"}" > "$PROGRESS_FILE"
}

# ─── Gitignore ───────────────────────────────────────────────────
for pat in "logs/" ".ralph.lock" "audit/"; do
  grep -q "^${pat}$" "$PROJECT_ROOT/.gitignore" 2>/dev/null || echo "$pat" >> "$PROJECT_ROOT/.gitignore"
done

# ─── Lockfile ────────────────────────────────────────────────────
LOCKFILE="$PROJECT_ROOT/.ralph.lock"
if [[ -f "$LOCKFILE" ]] && kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
  echo "Another ralph instance running (PID $(cat "$LOCKFILE")). Exiting."
  exit 1
fi
echo $$ > "$LOCKFILE"

# ─── Cleanup ─────────────────────────────────────────────────────
cleanup() {
  log "Shutting down..."
  # Kill all child processes (prevents orphan Claude sessions burning API credits)
  kill -- -$$ 2>/dev/null || true
  pkill -x uniclient 2>/dev/null || true
  rm -f "$LOCKFILE" "$FEEDBACK_FILE"
  rm -f /tmp/uniclient_debug_cmd.json /tmp/uniclient_debug_out.json
  notify "Ralph v2 stopped. Impl: ${IMPL_ITERATION:-0}. Audit: ${AUDIT_CYCLE:-0}. Commits: ${TOTAL_COMMITS:-0}."
  log "=== FINAL: ${IMPL_ITERATION:-0} impl, ${AUDIT_CYCLE:-0} audit, ${TOTAL_COMMITS:-0} commits ==="
}
trap cleanup EXIT

# ═════════════════════════════════════════════════════════════════
# SHARED INFRASTRUCTURE
# ═════════════════════════════════════════════════════════════════

# ─── Circuit breaker state ───────────────────────────────────────
CB_FAILURES=0
CB_OPEN=false
CB_OPEN_UNTIL=0

circuit_breaker_check() {
  if $CB_OPEN; then
    if [[ $(date +%s) -ge $CB_OPEN_UNTIL ]]; then
      log "Circuit breaker: HALF-OPEN, testing..."
      CB_OPEN=false
      CB_FAILURES=0
    else
      local remaining=$(( CB_OPEN_UNTIL - $(date +%s) ))
      log "Circuit breaker: OPEN (${remaining}s remaining). Skipping."
      return 1
    fi
  fi
  return 0
}

circuit_breaker_record() {
  local success="$1"
  if [[ "$success" == "true" ]]; then
    CB_FAILURES=0
  else
    CB_FAILURES=$((CB_FAILURES + 1))
    if [[ $CB_FAILURES -ge $CIRCUIT_BREAKER_THRESHOLD ]]; then
      CB_OPEN=true
      CB_OPEN_UNTIL=$(( $(date +%s) + CIRCUIT_BREAKER_COOLDOWN ))
      log "Circuit breaker: OPEN after $CB_FAILURES failures. Cooldown ${CIRCUIT_BREAKER_COOLDOWN}s."
    fi
  fi
}

# ─── jq stream formatter ────────────────────────────────────────
JQ_FMT='
  try fromjson catch empty | . as $e |
  if $e.type == "assistant" then
    ($e.message.content // [])[] |
      if .type == "text" then "\n\(.text | split("\n") | map("│ \(.)") | join("\n"))\n"
      elif .type == "tool_use" then
        if .name == "Read" then "\n📖 \(.input.file_path | ltrimstr($root))"
        elif .name == "Edit" then "\n✏️  \(.input.file_path | ltrimstr($root))"
        elif .name == "Write" then "\n📝 \(.input.file_path | ltrimstr($root))"
        elif .name == "Bash" then "\n$ \(.input.command | gsub("\n"; " ; ") | .[:200])"
        else "\n🔧 \(.name)" end
      else empty end
  elif $e.type == "user" then
    ($e.message.content // [])[] |
      if .type == "tool_result" then
        (.content | tostring | split("\n")) as $lines |
        if ($lines | length) == 0 or ($lines[0] | length) == 0 then "  ✓"
        elif ($lines[0] | test("(?i)^(error|fail|exception|fatal)")) then "  ❌ \($lines[0][:200])"
        else "  ✓ \($lines[0][:160])" end
      else empty end
  elif $e.type == "system" and $e.subtype == "init" then "\n🚀 \($e.session_id // "")\n"
  elif $e.type == "result" then "\n✅ \($e.subtype // "done") — \(($e.duration_ms // 0) / 1000)s, $\($e.total_cost_usd // 0)\n"
  else empty end'

# ─── Claude invocation with circuit breaker + timeout ────────────
# $1=prompt $2=log_file $3=label $4=model(optional) $5=effort(optional)
invoke_claude() {
  local prompt="$1" iter_file="$2" label="$3" model="${4:-claude-opus-4-6}" effort="${5:-high}"

  circuit_breaker_check || return 1

  log "Invoking Claude ($label, $model)..."
  local code=0
  timeout "$SESSION_TIMEOUT" claude \
    --print \
    --dangerously-skip-permissions \
    --model "$model" \
    --effort "$effort" \
    --output-format stream-json \
    --verbose \
    -p "$prompt" \
    2>&1 \
    | tee "$iter_file.jsonl" \
    | jq -Rr --unbuffered --arg root "$PROJECT_ROOT/" "$JQ_FMT" \
    | tee -a "$iter_file" \
    || code=${PIPESTATUS[0]:-$?}

  # Log cost
  local cost
  cost=$(grep -o '"total_cost_usd":[0-9.]*' "$iter_file.jsonl" 2>/dev/null | tail -1 | grep -o '[0-9.]*' || echo "0")
  echo "$(date '+%H:%M:%S') $label $model \$$cost" >> "$COST_LOG" || true

  # Update circuit breaker
  if [[ $code -eq 0 ]]; then
    circuit_breaker_record true
  else
    circuit_breaker_record false
  fi

  return $code
}

# ─── SSIM comparison (ImageMagick) ───────────────────────────────
ssim_compare() {
  local img_a="$1" img_b="$2"
  if [[ ! -f "$img_a" || ! -f "$img_b" ]]; then
    echo "1.0"
    return
  fi
  local raw
  raw=$(magick compare -metric SSIM "$img_a" "$img_b" /dev/null 2>&1 || true)
  echo "$raw" | grep -oP '^[\d.]+' || echo "0"
}

# ─── App lifecycle ───────────────────────────────────────────────
launch_app() {
  pkill -x uniclient 2>/dev/null || true
  sleep 1
  rm -f /tmp/uniclient_debug_cmd.json /tmp/uniclient_debug_out.json
  local bundle="$PROJECT_ROOT/dart/build/linux/x64/debug/bundle"
  if [[ ! -x "$bundle/uniclient" ]]; then
    log "Binary not found. Building..."
    "$SCRIPTS/build_go.sh" linux 2>&1 | tail -3
    "$SCRIPTS/build_flutter.sh" linux debug 2>&1 | tail -5
  fi
  cd "$bundle" && nohup ./uniclient > /tmp/uniclient_log.txt 2>&1 &
  cd "$PROJECT_ROOT"
  sleep 4
  if ! pgrep -x uniclient &>/dev/null; then
    log "App failed to launch"
    return 1
  fi
  log "App launched (PID $(pgrep -x uniclient | head -1))"
}

# ═════════════════════════════════════════════════════════════════
# STAGE 1: IMPLEMENTATION PROMPT
# ═════════════════════════════════════════════════════════════════
build_impl_prompt() {
  local extra="${1:-}"
  cat <<'PROMPT_END'
You are running in unattended automation mode (ralph loop). No human is watching.
This is STAGE 1 (IMPLEMENTATION). Implement ONE checklist item. A separate
verification session tests your work afterwards.

MANDATORY FIRST STEPS:
1. Read CLAUDE.md (every rule is binding)
2. Read checklist/gui.md — find the FIRST "- [ ]" item top-to-bottom

THEN:
3. Read the spec section cited in the item (from research/telegram_desktop_ui.md)
4. Read existing source files BEFORE writing code
5. Implement completely — no stubs, no placeholders
6. Build and basic sanity check:
   a. ONLY rebuild Go if you changed files under go/: scripts/build_go.sh linux
      (Skip if you only changed dart/ files — saves 30-60 seconds)
   b. scripts/build_flutter.sh linux debug
   c. Launch: cd dart/build/linux/x64/debug/bundle && nohup ./uniclient > /tmp/uniclient_log.txt 2>&1 &
   d. Wait 3s, screenshot: scripts/flutter_inspect.sh screenshot /tmp/ss.png
   e. Verify no crash, feature roughly visible
   f. Kill: pkill uniclient
7. Commit: git add <files> && git commit -m "[unverified] <description>"
8. Do NOT push. Do NOT delete checklist item.

RULES:
- ONE item per session. Commit [unverified], exit.
- TELEGRAM ONLY for testing.
- Do NOT read SPEC.md, auth/auth.md, or research/ files except the cited spec section.
- Do NOT refactor unrelated code or fix unrelated bugs.
PROMPT_END
  [[ -n "$extra" ]] && echo -e "\n$extra"
}

# ═════════════════════════════════════════════════════════════════
# STAGE 2: VERIFICATION PROMPT
# ═════════════════════════════════════════════════════════════════
build_verify_prompt() {
  local item="$1"
  local diff_stat commit_msg
  diff_stat="$(git -C "$PROJECT_ROOT" diff HEAD~1 --stat 2>/dev/null || echo '(no diff)')"
  commit_msg="$(git -C "$PROJECT_ROOT" log -1 --format='%s' 2>/dev/null || echo '(no commit)')"

  cat <<PROMPT_END
You are running in unattended automation mode (ralph loop). No human is watching.
This is STAGE 2 (VERIFICATION). Test whether the implementation works.

ITEM: $item
COMMIT: $commit_msg
FILES: $diff_stat

STEPS:
1. Read CLAUDE.md
2. Read the spec section cited in the item
3. Build & launch the app (skip Go build if only dart/ files changed):
   scripts/build_flutter.sh linux debug
   cd dart/build/linux/x64/debug/bundle && nohup ./uniclient > /tmp/uniclient_log.txt 2>&1 &
4. Run: scripts/flutter_audit.sh verify "$(echo "$item" | head -c 80)"
5. Test BOTH modes:
   - Desktop (1024x768): screenshot + interactions
   - Mobile (400x720): screenshot + interactions
6. Check /tmp/uniclient_log.txt for crashes
7. Kill: pkill uniclient

SEVERITY GUIDE (proportional — Weber's Law):
- CRITICAL: >25% deviation on small elements (<20px), or element missing/broken
- MAJOR: >10% proportional deviation from spec value
- MINOR: 5-10% proportional deviation
- COSMETIC: <5% proportional deviation (do NOT fail for cosmetic issues)

IF PASS:
  a. Delete the item from checklist/gui.md (remove the "- [ ]" line)
  b. git add checklist/gui.md && git commit -m "Verify & close: <description>"
  c. git push origin main
  d. Exit.

IF FAIL:
  a. Write failure details to /tmp/ralph_feedback.txt
  b. Do NOT modify code, push, or delete checklist item.
  c. Exit.

Be HARSH on critical/major. Be lenient on cosmetic. A 2px error on a 300px panel is invisible.
PROMPT_END
}

# ═════════════════════════════════════════════════════════════════
# AUDIT: CONSTRAINT EXTRACTION PROMPT (Sonnet, per spec chunk)
# ═════════════════════════════════════════════════════════════════
build_extraction_prompt() {
  local start_line="$1" end_line="$2" section_name="$3" chunk_id="$4"
  cat <<PROMPT_END
You are an autonomous UI auditor comparing a Flutter app against a Telegram Desktop UI spec.
Read the spec section below, then read the corresponding Dart source files, and find EVERY discrepancy.

SPEC SECTION: $section_name (lines $start_line-$end_line of research/telegram_desktop_ui.md)

Read the spec lines. Then list ALL dart files under dart/lib/ and read the ones relevant to this section.

SEVERITY (proportional — Weber's Law):
- CRITICAL: >25% deviation on small elements, element missing entirely, interaction broken
- MAJOR: >10% proportional deviation, wrong element order, wrong visibility state
- MINOR: 5-10% proportional deviation
- COSMETIC: <5% deviation — DO NOT REPORT cosmetic issues

For each bug/deviation found, output ONE checklist line:
- [ ] [SEVERITY] spec §X "subsection": what's wrong (spec says Y, code does Z) — \`file.dart\`

RULES:
- Only report REAL issues where code deviates from spec or is broken
- Be specific with values: "spec says 46px but code uses 40px" not "wrong size"
- Only report CRITICAL and MAJOR issues. Skip MINOR and COSMETIC.
- Check: dimensions, colors, behavior, missing features, placeholders, TODO stubs, broken interactions
- One "- [ ]" line per issue

Write ALL findings to /home/nako/Documents/uniclient/checklist/audit_chunk_${chunk_id}.md
If no issues found, write a file containing only: # No issues found
PROMPT_END
}

# ═════════════════════════════════════════════════════════════════
# AUDIT: VISUAL JOURNEY REVIEW PROMPT (Sonnet, per journey)
# ═════════════════════════════════════════════════════════════════
build_journey_prompt() {
  local journey_name="$1" screenshots="$2" journey_id="$3"
  cat <<PROMPT_END
You are verifying a Flutter app's UI by testing a user journey. The app is running.

JOURNEY: $journey_name

STEPS:
1. Use scripts/flutter_interact.sh to navigate the journey:
$screenshots
2. At each step, take a screenshot: scripts/flutter_inspect.sh screenshot /tmp/journey_${journey_id}_stepN.png
3. Compare what you see against the spec (research/telegram_desktop_ui.md — read relevant sections)
4. Check BOTH desktop (1024x768) and mobile (400x720) modes

SEVERITY (proportional — Weber's Law):
- CRITICAL: layout collapsed, element missing, interaction broken, crash
- MAJOR: >10% proportional deviation, wrong order, wrong state
- Skip MINOR and COSMETIC

Report findings as checklist items:
- [ ] [SEVERITY] spec §X: description — \`file.dart\`

Write findings to /home/nako/Documents/uniclient/checklist/audit_journey_${journey_id}.md
If no issues: write "# No issues found"
PROMPT_END
}

# ═════════════════════════════════════════════════════════════════
# MAIN STATE
# ═════════════════════════════════════════════════════════════════
IMPL_ITERATION=0
AUDIT_CYCLE=0
TOTAL_COMMITS=0
CONSECUTIVE_FAILURES=0
ITEM_ATTEMPTS=0
CONVERGE_COUNT=0
DIVERGE_COUNT=0
LAST_COMMIT_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"
LAST_AUDIT_FINDINGS=999999

mkdir -p "$AUDIT_DATA"

log "=== Ralph v2 starting (tribunal design, fully autonomous) ==="
log "Kill with: Ctrl+C"

while true; do

  # ─── Check for checklist items ──────────────────────────────
  REMAINING=0
  if [[ -f "$PROJECT_ROOT/checklist/gui.md" ]]; then
    REMAINING=$(grep -c '^- \[ \]' "$PROJECT_ROOT/checklist/gui.md" 2>/dev/null || echo 0)
  fi

  if [[ "$REMAINING" -gt 0 ]]; then
    # ═══════════════════════════════════════════════════════════
    # MODE 1: IMPLEMENT + VERIFY
    # ═══════════════════════════════════════════════════════════
    IMPL_ITERATION=$((IMPL_ITERATION + 1))
    update_progress "implement" "iteration $IMPL_ITERATION" "$REMAINING items left"
    log "══ IMPLEMENT $IMPL_ITERATION ($REMAINING left, $TOTAL_COMMITS verified) ══"

    CURRENT_ITEM="$(grep -m1 '^- \[ \]' "$PROJECT_ROOT/checklist/gui.md" 2>/dev/null || echo "unknown")"
    log "Item: ${CURRENT_ITEM:0:100}"

    pkill -x uniclient 2>/dev/null || true
    rm -f /tmp/uniclient_debug_cmd.json /tmp/uniclient_debug_out.json

    # ── STAGE 1: IMPLEMENT ──────────────────────────────────
    IMPL_FILE="$ITER_LOG_DIR/iter_$(printf '%04d' $IMPL_ITERATION)_impl.log"

    IMPL_EXTRA=""
    if [[ -f "$FEEDBACK_FILE" ]]; then
      IMPL_EXTRA="PREVIOUS VERIFICATION FAILED. Feedback:
--- FEEDBACK START ---
$(cat "$FEEDBACK_FILE")
--- FEEDBACK END ---
Attempt $((ITEM_ATTEMPTS + 1)) of $MAX_IMPL_ATTEMPTS. Fix the issues above."
      rm -f "$FEEDBACK_FILE"
      log "Including feedback (attempt $((ITEM_ATTEMPTS + 1))/$MAX_IMPL_ATTEMPTS)"
    fi

    if [[ $ITEM_ATTEMPTS -ge $MAX_IMPL_ATTEMPTS ]]; then
      log "Item failed $MAX_IMPL_ATTEMPTS times. Skipping."
      IMPL_EXTRA="This item failed verification $MAX_IMPL_ATTEMPTS times.
SKIP IT — delete it from checklist/gui.md, commit, and exit.
Item: $CURRENT_ITEM"
      ITEM_ATTEMPTS=0
    fi

    IMPL_EXIT=0
    invoke_claude "$(build_impl_prompt "$IMPL_EXTRA")" "$IMPL_FILE" "IMPLEMENT" || IMPL_EXIT=$?

    if [[ $IMPL_EXIT -eq 2 ]]; then
      log "Rate limited. Waiting ${RATE_LIMIT_WAIT}s..."
      sleep "$RATE_LIMIT_WAIT"; continue
    elif [[ $IMPL_EXIT -ne 0 ]]; then
      CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
      BACKOFF=$(( BACKOFF_BASE * (2 ** (CONSECUTIVE_FAILURES - 1)) ))
      [[ $BACKOFF -gt $BACKOFF_MAX ]] && BACKOFF=$BACKOFF_MAX
      log "Impl failed (exit $IMPL_EXIT). Backoff ${BACKOFF}s..."
      sleep "$BACKOFF"; continue
    fi
    CONSECUTIVE_FAILURES=0

    IMPL_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"
    if [[ "$IMPL_HASH" == "$LAST_COMMIT_HASH" ]]; then
      log "No commit. Stall."
      ITEM_ATTEMPTS=$((ITEM_ATTEMPTS + 1)); continue
    fi
    log "Impl committed: $(git -C "$PROJECT_ROOT" log -1 --oneline)"

    # ── STAGE 2: VERIFY ─────────────────────────────────────
    pkill -x uniclient 2>/dev/null || true
    rm -f /tmp/uniclient_debug_cmd.json /tmp/uniclient_debug_out.json
    sleep 2

    VERIFY_FILE="$ITER_LOG_DIR/iter_$(printf '%04d' $IMPL_ITERATION)_verify.log"
    rm -f "$FEEDBACK_FILE"

    VERIFY_EXIT=0
    invoke_claude "$(build_verify_prompt "$CURRENT_ITEM")" "$VERIFY_FILE" "VERIFY" "claude-sonnet-4-6" || VERIFY_EXIT=$?

    if [[ $VERIFY_EXIT -eq 2 ]]; then
      log "Rate limited during verify. Waiting..."
      sleep "$RATE_LIMIT_WAIT"; continue
    elif [[ $VERIFY_EXIT -ne 0 ]]; then
      CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
      BACKOFF=$(( BACKOFF_BASE * (2 ** (CONSECUTIVE_FAILURES - 1)) ))
      [[ $BACKOFF -gt $BACKOFF_MAX ]] && BACKOFF=$BACKOFF_MAX
      log "Verify crashed (exit $VERIFY_EXIT). Backoff ${BACKOFF}s..."
      sleep "$BACKOFF"; continue
    fi
    CONSECUTIVE_FAILURES=0

    VERIFY_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"
    if [[ "$VERIFY_HASH" != "$IMPL_HASH" ]]; then
      NEW_COMMITS=$(git -C "$PROJECT_ROOT" log --oneline "$LAST_COMMIT_HASH".."$VERIFY_HASH" 2>/dev/null | wc -l)
      TOTAL_COMMITS=$((TOTAL_COMMITS + NEW_COMMITS))
      LAST_COMMIT_HASH="$VERIFY_HASH"
      ITEM_ATTEMPTS=0
      log "✅ VERIFIED ($NEW_COMMITS commits). Total: $TOTAL_COMMITS"
    elif [[ -f "$FEEDBACK_FILE" ]]; then
      ITEM_ATTEMPTS=$((ITEM_ATTEMPTS + 1))
      log "❌ VERIFY FAILED (attempt $ITEM_ATTEMPTS/$MAX_IMPL_ATTEMPTS)"
    else
      ITEM_ATTEMPTS=$((ITEM_ATTEMPTS + 1))
      log "⚠️  No push, no feedback. Attempt $ITEM_ATTEMPTS/$MAX_IMPL_ATTEMPTS"
    fi

    pkill -x uniclient 2>/dev/null || true

  else
    # ═══════════════════════════════════════════════════════════
    # MODE 2: AUDIT (checklist empty — re-audit codebase vs spec)
    # ═══════════════════════════════════════════════════════════
    AUDIT_CYCLE=$((AUDIT_CYCLE + 1))

    if [[ $AUDIT_CYCLE -gt $MAX_AUDIT_CYCLES ]]; then
      log "Max audit cycles ($MAX_AUDIT_CYCLES). Exiting."
      notify "Ralph v2: max audit cycles reached. $TOTAL_COMMITS commits."
      break
    fi

    log "══════════════════════════════════════════════════"
    log "══ AUDIT CYCLE $AUDIT_CYCLE / $MAX_AUDIT_CYCLES ══"
    log "══════════════════════════════════════════════════"
    update_progress "audit" "cycle $AUDIT_CYCLE" "starting"

    # Safety tag for rollback
    git -C "$PROJECT_ROOT" tag -f "audit-pre-cycle-${AUDIT_CYCLE}" HEAD 2>/dev/null || true

    # ── Take SSIM baseline (if previous cycle exists) ────────
    SSIM_DIR="$AUDIT_DATA/ssim_cycle_${AUDIT_CYCLE}"
    mkdir -p "$SSIM_DIR"
    PREV_SSIM_DIR="$AUDIT_DATA/ssim_cycle_$((AUDIT_CYCLE - 1))"

    if [[ $AUDIT_CYCLE -gt 1 ]] && launch_app; then
      "$SCRIPTS/flutter_inspect.sh" screenshot "$SSIM_DIR/desktop_pre.png" 2>/dev/null || true
      "$SCRIPTS/flutter_interact.sh" resize mobile 2>/dev/null || true
      sleep 1.5
      "$SCRIPTS/flutter_inspect.sh" screenshot "$SSIM_DIR/mobile_pre.png" 2>/dev/null || true
      "$SCRIPTS/flutter_interact.sh" resize desktop 2>/dev/null || true
      sleep 1

      # Compare against previous cycle
      if [[ -f "$PREV_SSIM_DIR/desktop_post.png" ]]; then
        SSIM_DESKTOP=$(ssim_compare "$PREV_SSIM_DIR/desktop_post.png" "$SSIM_DIR/desktop_pre.png")
        log "SSIM desktop (vs prev cycle): $SSIM_DESKTOP"
      fi
      if [[ -f "$PREV_SSIM_DIR/mobile_post.png" ]]; then
        SSIM_MOBILE=$(ssim_compare "$PREV_SSIM_DIR/mobile_post.png" "$SSIM_DIR/mobile_pre.png")
        log "SSIM mobile (vs prev cycle): $SSIM_MOBILE"
      fi

      pkill -x uniclient 2>/dev/null || true
    fi

    # ── LAYER 1: Constraint extraction (parallel Sonnet) ─────
    update_progress "audit" "cycle $AUDIT_CYCLE" "Layer 1: constraint extraction"
    log "Layer 1: Extracting constraints from spec..."

    if [[ ! -f "$SPEC_FILE" ]]; then
      log "FATAL: spec file not found at $SPEC_FILE"
      break
    fi

    # Get section boundaries
    mapfile -t SECTION_STARTS < <(grep -n '^## ' "$SPEC_FILE" | cut -d: -f1)
    TOTAL_LINES=$(wc -l < "$SPEC_FILE")
    NUM_SECTIONS=${#SECTION_STARTS[@]}

    rm -f "$PROJECT_ROOT/checklist/audit_chunk_"*.md "$PROJECT_ROOT/checklist/audit_journey_"*.md

    # Run extraction in parallel batches
    BATCH_SIZE=4
    PIDS=()
    CHUNK_ID=0
    SUCCESSFUL_CHUNKS=0
    FAILED_CHUNKS=0

    for ((i=0; i<NUM_SECTIONS; i++)); do
      START=${SECTION_STARTS[$i]}
      if [[ $((i + 1)) -lt $NUM_SECTIONS ]]; then
        END=$((SECTION_STARTS[$((i + 1))] - 1))
      else
        END=$TOTAL_LINES
      fi

      SECTION_NAME=$(sed -n "${START}p" "$SPEC_FILE" | sed 's/^## //')
      SECTION_SIZE=$((END - START))
      [[ $SECTION_SIZE -lt 20 ]] && continue

      CHUNK_FILE="$ITER_LOG_DIR/audit_c${AUDIT_CYCLE}_chunk_$(printf '%02d' $CHUNK_ID).log"
      PROMPT="$(build_extraction_prompt "$START" "$END" "$SECTION_NAME" "$CHUNK_ID")"

      log "  Chunk $CHUNK_ID: §$SECTION_NAME (lines $START-$END)"

      # Partial failure: each chunk is independent (bulkhead)
      (
        set +e
        invoke_claude "$PROMPT" "$CHUNK_FILE" "AUDIT-C${AUDIT_CYCLE}-${CHUNK_ID}" "claude-sonnet-4-6"
        exit $?
      ) &
      PIDS+=($!)
      CHUNK_ID=$((CHUNK_ID + 1))

      if [[ ${#PIDS[@]} -ge $BATCH_SIZE ]]; then
        for pid in "${PIDS[@]}"; do
          if wait "$pid" 2>/dev/null; then
            SUCCESSFUL_CHUNKS=$((SUCCESSFUL_CHUNKS + 1))
          else
            FAILED_CHUNKS=$((FAILED_CHUNKS + 1))
          fi
        done
        PIDS=()
      fi
    done

    # Wait for remaining
    for pid in "${PIDS[@]}"; do
      if wait "$pid" 2>/dev/null; then
        SUCCESSFUL_CHUNKS=$((SUCCESSFUL_CHUNKS + 1))
      else
        FAILED_CHUNKS=$((FAILED_CHUNKS + 1))
      fi
    done

    log "Layer 1: $SUCCESSFUL_CHUNKS/$CHUNK_ID chunks succeeded, $FAILED_CHUNKS failed (partial-failure OK)"

    # ── LAYER 2: Journey-based visual audit (if app builds) ──
    update_progress "audit" "cycle $AUDIT_CYCLE" "Layer 2: visual journey audit"
    JID=0

    if launch_app; then
      log "Layer 2: Running visual journey audit..."

      # Journey definitions: name + interaction steps
      JOURNEYS=(
        "chat_navigation|taptext 'All Chats';sleep 2;scroll 400 400 0 -300;sleep 1"
        "message_reading|open 0;sleep 2;scroll 600 400 0 -200;sleep 1"
        "search_flow|tap 200 35;sleep 1;type 'test';sleep 2"
        "settings|taptext 'Settings';sleep 2;scroll 400 400 0 -300;sleep 1"
        "responsive|resize desktop;sleep 2;resize mobile;sleep 2;resize desktop;sleep 1"
      )

      # Journeys run SEQUENTIALLY — they share the app via IPC files,
      # so parallel execution causes command interleaving and wrong responses.
      for journey_def in "${JOURNEYS[@]}"; do
        IFS='|' read -r JNAME JSTEPS <<< "$journey_def"
        JOURNEY_FILE="$ITER_LOG_DIR/audit_c${AUDIT_CYCLE}_journey_$(printf '%02d' $JID).log"

        JOURNEY_STEPS="Steps to execute via scripts/flutter_interact.sh:
$(echo "$JSTEPS" | tr ';' '\n' | sed 's/^/  - /')"

        PROMPT="$(build_journey_prompt "$JNAME" "$JOURNEY_STEPS" "$JID")"

        invoke_claude "$PROMPT" "$JOURNEY_FILE" "JOURNEY-C${AUDIT_CYCLE}-${JID}" "claude-sonnet-4-6" || true
        JID=$((JID + 1))

        # Reset app state between journeys for clean starting state
        pkill -x uniclient 2>/dev/null || true
        sleep 2
        launch_app || { log "App failed to relaunch between journeys"; break; }
      done

      log "Layer 2: $JID journey audits completed"

      # Take post-audit SSIM screenshots
      "$SCRIPTS/flutter_inspect.sh" screenshot "$SSIM_DIR/desktop_post.png" 2>/dev/null || true
      "$SCRIPTS/flutter_interact.sh" resize mobile 2>/dev/null || true
      sleep 1.5
      "$SCRIPTS/flutter_inspect.sh" screenshot "$SSIM_DIR/mobile_post.png" 2>/dev/null || true
      "$SCRIPTS/flutter_interact.sh" resize desktop 2>/dev/null || true

      pkill -x uniclient 2>/dev/null || true
    else
      log "Layer 2: SKIPPED (app failed to launch). Degrading to Layer 1 only."
    fi

    # ── MERGE: Combine all findings into gui.md ──────────────
    update_progress "audit" "cycle $AUDIT_CYCLE" "merging findings"
    {
      echo "# GUI Audit — Cycle $AUDIT_CYCLE ($(date '+%Y-%m-%d %H:%M'))"
      echo ""
      echo "## Constraint Violations (Layer 1)"
      echo ""
      for f in "$PROJECT_ROOT/checklist/audit_chunk_"*.md; do
        [[ -f "$f" ]] || continue
        if grep -qi "no issues found" "$f" && [[ $(wc -l < "$f") -le 2 ]]; then
          continue
        fi
        cat "$f"
        echo ""
      done
      echo "## Visual Journey Findings (Layer 2)"
      echo ""
      for f in "$PROJECT_ROOT/checklist/audit_journey_"*.md; do
        [[ -f "$f" ]] || continue
        if grep -qi "no issues found" "$f" && [[ $(wc -l < "$f") -le 2 ]]; then
          continue
        fi
        cat "$f"
        echo ""
      done
    } > "$PROJECT_ROOT/checklist/gui.md"

    rm -f "$PROJECT_ROOT/checklist/audit_chunk_"*.md "$PROJECT_ROOT/checklist/audit_journey_"*.md

    FINDINGS=$(grep -c '^- \[ \]' "$PROJECT_ROOT/checklist/gui.md" 2>/dev/null || echo 0)
    log "Audit cycle $AUDIT_CYCLE: $FINDINGS items found ($SUCCESSFUL_CHUNKS chunks, $FAILED_CHUNKS failed)"

    # ── Convergence check ────────────────────────────────────
    if [[ "$FINDINGS" -eq 0 ]]; then
      CONVERGE_COUNT=$((CONVERGE_COUNT + 1))
      log "Zero findings. Convergence: $CONVERGE_COUNT/$CONVERGE_THRESHOLD"
      if [[ $CONVERGE_COUNT -ge $CONVERGE_THRESHOLD ]]; then
        log "═══════════════════════════════════════════"
        log "══ CONVERGED after $AUDIT_CYCLE audit cycles ══"
        log "═══════════════════════════════════════════"
        notify "Ralph v2: CONVERGED! $TOTAL_COMMITS commits, $AUDIT_CYCLE audit cycles."
        break
      fi
      continue
    fi

    # ── Divergence detection ─────────────────────────────────
    if [[ "$FINDINGS" -gt "$LAST_AUDIT_FINDINGS" && $AUDIT_CYCLE -gt 1 ]]; then
      DIVERGE_COUNT=$((DIVERGE_COUNT + 1))
      log "⚠️  DIVERGENCE: findings $LAST_AUDIT_FINDINGS → $FINDINGS (count: $DIVERGE_COUNT)"
      if [[ $DIVERGE_COUNT -ge 2 ]]; then
        rollback_tag="audit-pre-cycle-$((AUDIT_CYCLE - 2))"
        if git -C "$PROJECT_ROOT" rev-parse "$rollback_tag" &>/dev/null; then
          log "DIVERGENCE confirmed. Resetting to $rollback_tag."
          git -C "$PROJECT_ROOT" reset --hard "$rollback_tag"
          git -C "$PROJECT_ROOT" push origin main --force-with-lease 2>/dev/null || true
        else
          log "DIVERGENCE confirmed but rollback tag $rollback_tag not found."
        fi
        notify "Ralph v2: DIVERGENCE. Rolled back."
        break
      fi
    else
      DIVERGE_COUNT=0
    fi
    LAST_AUDIT_FINDINGS=$FINDINGS
    CONVERGE_COUNT=0

    # ── Commit new checklist ─────────────────────────────────
    git -C "$PROJECT_ROOT" add checklist/gui.md 2>/dev/null || true
    git -C "$PROJECT_ROOT" commit -m "$(cat <<EOF
Audit cycle $AUDIT_CYCLE: $FINDINGS items found (L1: $SUCCESSFUL_CHUNKS chunks, L2: $JID journeys)

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)" 2>/dev/null || true
    if ! git -C "$PROJECT_ROOT" push origin main 2>/dev/null; then
      log "⚠️  git push failed — commits are local only. Will retry next cycle."
    fi
    LAST_COMMIT_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"

    log "New checklist ($FINDINGS items) committed. Returning to implement loop."
  fi
done

# ─── Final report ────────────────────────────────────────────────
log "═══════════════════════════════════════════════"
log "══ RALPH V2 COMPLETE"
log "══ Impl iterations: $IMPL_ITERATION"
log "══ Audit cycles: $AUDIT_CYCLE"
log "══ Verified commits: $TOTAL_COMMITS"
if [[ -f "$COST_LOG" ]]; then
  TOTAL_COST=$(awk '{gsub(/\$/,"",$4); sum+=$4} END{printf "%.2f", sum}' "$COST_LOG" 2>/dev/null || echo "?")
  log "══ Total cost: \$$TOTAL_COST"
fi
log "══ Known limitations:"
log "══   - Same-model blind spot (Claude auditing Claude)"
log "══   - Animation/timing not testable via screenshots"
log "══   - ~10-15% of spec surface requires human judgment"
log "═══════════════════════════════════════════════"
notify "Ralph v2 DONE. $IMPL_ITERATION impl, $AUDIT_CYCLE audit, $TOTAL_COMMITS commits."
