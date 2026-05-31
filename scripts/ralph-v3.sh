#!/usr/bin/env bash
#
# ralph-v3.sh — Fully autonomous implement→verify→audit loop
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
#     Layer 1: Parallel Opus sessions extract constraint violations (all sessions use $RALPH_MODEL)
#     SSIM regression between cycles for visual change detection
#     Layer 3: Generate new gui.md from findings, return to MODE 1
#     Convergence: zero critical+major findings for 2 consecutive cycles → done.
#
# No human gate. Fully autonomous. No artificial cost ceiling.
# Safety: circuit breakers, divergence stop, partial failure, max 5 audit cycles.
#
# Usage: nix develop --command bash -c "scripts/ralph-v3.sh"
# Kill:  Ctrl+C or kill $(pgrep -f ralph-v3.sh)

set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"
SCRIPTS="$PROJECT_ROOT/scripts"
SPEC_FILE="$PROJECT_ROOT/research/telegram_desktop_ui.md"
AYUGRAM_DIR="/home/nako/Documents/AyuGramDesktop"
AYUGRAM_UI="$AYUGRAM_DIR/Telegram/SourceFiles"

# ─── Claude binary ──────────────────────────────────────────────
# Use the user-installed native CLI (newer than the NixOS-packaged one on
# PATH) by absolute path, so the loop works under cron / bare shells where
# ~/.local/bin isn't on PATH. Override with: CLAUDE_BIN=/path/to/claude
CLAUDE_BIN="${CLAUDE_BIN:-/home/nako/.local/bin/claude}"

# ─── Startup checks ─────────────────────────────────────────────
[[ -x "$CLAUDE_BIN" ]] || { echo "FATAL: claude CLI not executable at '$CLAUDE_BIN'. Set CLAUDE_BIN env var or install it."; exit 1; }
for cmd in jq magick git; do
  command -v "$cmd" &>/dev/null || { echo "FATAL: '$cmd' not found in PATH. Run inside nix develop."; exit 1; }
done
if [[ ! -d "$AYUGRAM_DIR" ]]; then
  echo "FATAL: AyuGram Desktop not found at $AYUGRAM_DIR"
  echo "Clone it: git clone --depth 1 https://github.com/AyuGram/AyuGramDesktop.git $AYUGRAM_DIR"
  exit 1
fi

# ─── Configuration ───────────────────────────────────────────────
BACKOFF_BASE=30
BACKOFF_MAX=300
MAX_IMPL_ATTEMPTS=3
MAX_AUDIT_CYCLES=5
CONVERGE_THRESHOLD=2
CIRCUIT_BREAKER_THRESHOLD=3
CIRCUIT_BREAKER_COOLDOWN=300
SKIP_UNCHANGED="${RALPH_SKIP_UNCHANGED:-0}"
# Single model for ALL sessions (implement, verify, audit, cleanup). Override
# with RALPH_MODEL=...  The [1m] suffix selects the 1M-context Opus variant.
RALPH_MODEL="${RALPH_MODEL:-claude-opus-4-8[1m]}"
# No session timeout — ralph runs until Claude finishes naturally

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
STAGE_FILE="/tmp/ralph_current_stage.txt"
INTERRUPT_FILE="/tmp/ralph_interrupted_${RUN_ID}"
AUDIT_DATA="$PROJECT_ROOT/audit"
# Durable resume state (gitignored under audit/): survives Ctrl+C so a re-run
# continues exactly where it left off instead of restarting the session.
STATE_FILE="$AUDIT_DATA/state.json"
RESUME_DIR="$AUDIT_DATA/resume"
DONE_DIR="$RESUME_DIR/done"
AUDIT_SESSION_FILE="$RESUME_DIR/session.json"
RESUMING_AUDIT=false
CURRENT_STAGE="STARTING"
CURRENT_STEP="initializing"
CURRENT_DETAIL=""
rm -f "$INTERRUPT_FILE"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
notify() {
  log "NOTIFY: $*"
  command -v notify-send &>/dev/null && notify-send -u critical "Ralph v3" "$*" 2>/dev/null || true
}
update_progress() {
  local stage="$1" step="$2" detail="${3:-}"
  local now
  now="$(date -Iseconds)"
  CURRENT_STAGE="$stage"
  CURRENT_STEP="$step"
  CURRENT_DETAIL="$detail"

  jq -n \
    --arg current_stage "$stage" \
    --arg phase "$stage" \
    --arg step "$step" \
    --arg detail "$detail" \
    --arg time "$now" \
    --arg run_id "$RUN_ID" \
    --arg impl_iteration "${IMPL_ITERATION:-0}" \
    --arg audit_cycle "${AUDIT_CYCLE:-0}" \
    --arg audit_phase "${AUDIT_PHASE:-none}" \
    --arg remaining "${REMAINING:-0}" \
    --arg item_count "${ITEM_COUNT:-0}" \
    --arg item_attempts "${ITEM_ATTEMPTS:-0}" \
    --arg total_commits "${TOTAL_COMMITS:-0}" \
    --arg skip_unchanged "$SKIP_UNCHANGED" \
    '{current_stage:$current_stage, phase:$phase, step:$step, detail:$detail, time:$time, run_id:$run_id, implementation_iteration:($impl_iteration|tonumber), audit_cycle:($audit_cycle|tonumber), audit_phase:$audit_phase, remaining_items:($remaining|tonumber), current_section_items:($item_count|tonumber), item_attempts:($item_attempts|tonumber), verified_commits:($total_commits|tonumber), skip_unchanged_audits:($skip_unchanged == "1")}' > "$PROGRESS_FILE"

  {
    printf 'Ralph v3 current stage: %s\n' "$stage"
    printf 'Step: %s\n' "$step"
    [[ -n "$detail" ]] && printf 'Detail: %s\n' "$detail"
    printf 'Updated: %s\n' "$now"
    printf 'Run ID: %s\n' "$RUN_ID"
    printf 'Implementation iteration: %s\n' "${IMPL_ITERATION:-0}"
    printf 'Audit cycle: %s\n' "${AUDIT_CYCLE:-0}"
    printf 'Audit phase: %s\n' "${AUDIT_PHASE:-none}"
    printf 'Remaining checklist items: %s\n' "${REMAINING:-0}"
    printf 'Current section items: %s\n' "${ITEM_COUNT:-0}"
    printf 'Item attempts: %s\n' "${ITEM_ATTEMPTS:-0}"
    printf 'Verified commits: %s\n' "${TOTAL_COMMITS:-0}"
    printf 'Skip unchanged audits: %s\n' "$SKIP_UNCHANGED"
    printf 'JSON progress: %s\n' "$PROGRESS_FILE"
    printf 'Log file: %s\n' "$LOG_FILE"
  } > "$STAGE_FILE"
  save_resume_state
}

set_current_stage() {
  local stage="$1" step="$2" detail="${3:-}"
  update_progress "$stage" "$step" "$detail"
  log ""
  log "▶ CURRENT RALPH STAGE: $stage"
  log "  Step: $step"
  [[ -n "$detail" ]] && log "  Detail: $detail"
  log "  Stage file: $STAGE_FILE"
}

# ─── Resume state: survive Ctrl+C and continue where we left off ──
# save_resume_state is called from update_progress, which only ever runs in the
# main process (never in the parallel audit subshells), so $STATE_FILE writes
# never race. Written atomically (tmp + mv). Every guard ends with `return 0`
# so a transient jq/fs hiccup can never trip `set -e`.
save_resume_state() {
  mkdir -p "$AUDIT_DATA" 2>/dev/null || true
  local tmp="$STATE_FILE.tmp.$$"
  if jq -n \
      --argjson cycle    "${AUDIT_CYCLE:-0}" \
      --arg     phase    "${AUDIT_PHASE:-ayugram}" \
      --argjson converge "${CONVERGE_COUNT:-0}" \
      --argjson div_a    "${DIVERGE_AYUGRAM_COUNT:-0}" \
      --argjson div_c    "${DIVERGE_CLEANUP_COUNT:-0}" \
      --argjson last_a   "${LAST_AYUGRAM_FINDINGS:-999999}" \
      --argjson last_c   "${LAST_CLEANUP_FINDINGS:-999999}" \
      --argjson commits  "${TOTAL_COMMITS:-0}" \
      --argjson impl     "${IMPL_ITERATION:-0}" \
      '{audit_cycle:$cycle, audit_phase:$phase, converge_count:$converge, diverge_ayugram:$div_a, diverge_cleanup:$div_c, last_ayugram_findings:$last_a, last_cleanup_findings:$last_c, total_commits:$commits, impl_iteration:$impl}' \
      > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$STATE_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
  return 0
}

load_resume_state() {
  [[ "${RALPH_FRESH:-0}" == "1" ]] && { log "  RALPH_FRESH=1 — ignoring saved state, starting a clean run."; rm -f "$STATE_FILE" 2>/dev/null || true; rm -rf "$RESUME_DIR" 2>/dev/null || true; return 0; }
  [[ -f "$STATE_FILE" ]] || return 0
  jq -e . "$STATE_FILE" >/dev/null 2>&1 || { log "  ⚠️  saved state unreadable — starting clean."; return 0; }
  AUDIT_CYCLE=$(jq -r '.audit_cycle // 0'                "$STATE_FILE" 2>/dev/null || echo 0)
  AUDIT_PHASE=$(jq -r '.audit_phase // "ayugram"'        "$STATE_FILE" 2>/dev/null || echo ayugram)
  CONVERGE_COUNT=$(jq -r '.converge_count // 0'          "$STATE_FILE" 2>/dev/null || echo 0)
  DIVERGE_AYUGRAM_COUNT=$(jq -r '.diverge_ayugram // 0'  "$STATE_FILE" 2>/dev/null || echo 0)
  DIVERGE_CLEANUP_COUNT=$(jq -r '.diverge_cleanup // 0'  "$STATE_FILE" 2>/dev/null || echo 0)
  LAST_AYUGRAM_FINDINGS=$(jq -r '.last_ayugram_findings // 999999' "$STATE_FILE" 2>/dev/null || echo 999999)
  LAST_CLEANUP_FINDINGS=$(jq -r '.last_cleanup_findings // 999999' "$STATE_FILE" 2>/dev/null || echo 999999)
  TOTAL_COMMITS=$(jq -r '.total_commits // 0'            "$STATE_FILE" 2>/dev/null || echo 0)
  IMPL_ITERATION=$(jq -r '.impl_iteration // 0'          "$STATE_FILE" 2>/dev/null || echo 0)
  log "  ↻ RESUMING from saved state: audit cycle $AUDIT_CYCLE, phase $AUDIT_PHASE, $TOTAL_COMMITS verified commits (convergence $CONVERGE_COUNT/$CONVERGE_THRESHOLD)."
  log "    (set RALPH_FRESH=1 to ignore saved state and start clean)"
  return 0
}

# Per-file audit resume. A leftover $AUDIT_SESSION_FILE + done-markers mean an
# audit pass was interrupted before its merge. begin_audit_session decides:
# resume that pass (keep finished chunks) or start the phase fresh (wipe stale
# chunks/markers). Completion is tracked by orchestrator-written done-markers,
# NOT by chunk-file existence — a chunk file can be half-written if Claude is
# killed mid-write, but a done-marker is only touched after the session exits 0.
begin_audit_session() {
  local cycle="$1" phase="$2" fhash match=false
  fhash=$(printf '%s\n' "${DART_FILES[@]}" | sha1sum 2>/dev/null | cut -d' ' -f1 || true)
  mkdir -p "$DONE_DIR" 2>/dev/null || true
  if [[ -f "$AUDIT_SESSION_FILE" ]] \
     && [[ "$(jq -r '.cycle // empty'      "$AUDIT_SESSION_FILE" 2>/dev/null || true)" == "$cycle" ]] \
     && [[ "$(jq -r '.phase // empty'      "$AUDIT_SESSION_FILE" 2>/dev/null || true)" == "$phase" ]] \
     && [[ "$(jq -r '.files_hash // empty' "$AUDIT_SESSION_FILE" 2>/dev/null || true)" == "$fhash" ]]; then
    match=true
  fi
  if $match; then
    local done_n
    done_n=$(find "$DONE_DIR" -name 'chunk_*.done' 2>/dev/null | wc -l | tr -d ' ' || echo 0)
    RESUMING_AUDIT=true
    log "  ↻ Resuming interrupted $phase audit (cycle $cycle): ${done_n:-0} file(s) already done — auditing only the remainder."
  else
    rm -rf "$DONE_DIR" 2>/dev/null || true
    mkdir -p "$DONE_DIR" 2>/dev/null || true
    rm -f "$PROJECT_ROOT/checklist/audit_chunk_"*.md 2>/dev/null || true
    jq -n --arg c "$cycle" --arg p "$phase" --arg f "$fhash" \
      '{cycle:$c, phase:$p, files_hash:$f}' > "$AUDIT_SESSION_FILE" 2>/dev/null || true
    RESUMING_AUDIT=false
  fi
  return 0
}

# Per-file pass + merge finished — clear this phase's resume markers so the next
# phase/cycle starts fresh.
end_audit_session() {
  rm -rf "$DONE_DIR" 2>/dev/null || true
  rm -f "$AUDIT_SESSION_FILE" 2>/dev/null || true
  return 0
}

# Drop a stored Implement/Verify session id if the current work-unit differs
# from the one it belonged to — so we never --resume an unrelated conversation.
# $1=key (implement|verify)  $2=signature (e.g. section name) of the current unit
resume_guard() {
  local key="$1" sig="$2" prev=""
  local sig_file="$RESUME_DIR/session_${key}.sig"   # separate stmt: ${key} must be set first (set -u)
  mkdir -p "$RESUME_DIR" 2>/dev/null || true
  [[ -f "$sig_file" ]] && prev=$(cat "$sig_file" 2>/dev/null || true)
  [[ "$prev" != "$sig" ]] && rm -f "$RESUME_DIR/session_${key}.id" 2>/dev/null || true
  printf '%s' "$sig" > "$sig_file" 2>/dev/null || true
  return 0
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
kill_descendants() {
  local parent="$1" child
  while IFS= read -r child; do
    [[ -n "$child" ]] || continue
    kill_descendants "$child"
    kill "$child" 2>/dev/null || true
  done < <(pgrep -P "$parent" 2>/dev/null || true)
}

cleanup() {
  trap - EXIT
  log "Shutting down..."
  case "${CURRENT_STAGE:-}" in
    COMPLETE*|STOPPED*) ;;
    *) update_progress "STOPPED" "cleanup" "Ralph exited or was interrupted" ;;
  esac
  # Kill descendant Claude/subshell pipelines without signalling this script.
  kill_descendants "$$"
  pkill -x uniclient 2>/dev/null || true
  rm -f "$LOCKFILE"
  [[ "${CURRENT_STAGE:-}" == "STOPPED / INTERRUPTED"* ]] || rm -f "$FEEDBACK_FILE"
  rm -f /tmp/uniclient_debug_cmd.json /tmp/uniclient_debug_out.json
  notify "Ralph v3 stopped. Impl: ${IMPL_ITERATION:-0}. Audit: ${AUDIT_CYCLE:-0}. Commits: ${TOTAL_COMMITS:-0}."
  log "=== FINAL: ${IMPL_ITERATION:-0} impl, ${AUDIT_CYCLE:-0} audit, ${TOTAL_COMMITS:-0} commits ==="
}

handle_interrupt() {
  trap - INT TERM
  touch "$INTERRUPT_FILE" 2>/dev/null || true
  update_progress "STOPPED / INTERRUPTED" "Ctrl+C" "Stopped by user; current work will be retried on the next ralph run" || true
  log "Interrupt received. Stopping without marking current work complete."
  exit 130
}

trap handle_interrupt INT TERM
trap cleanup EXIT

# ═════════════════════════════════════════════════════════════════
# SHARED INFRASTRUCTURE
# ═════════════════════════════════════════════════════════════════

# ─── Internet connectivity check ─────────────────────────────────
wait_for_internet() {
  if ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
    return 0
  fi
  log ""
  log "  ⚡ Internet connection lost. Waiting for reconnection..."
  log "     Pinging 1.1.1.1 every 5 seconds..."
  local waited=0
  while ! ping -c 1 -W 2 1.1.1.1 &>/dev/null; do
    sleep 5
    waited=$((waited + 5))
    # Print a dot every 30 seconds so the terminal doesn't look dead
    if [[ $((waited % 30)) -eq 0 ]]; then
      log "     Still waiting... (${waited}s offline)"
    fi
  done
  log "  ✅ Internet restored after ${waited}s. Resuming."
  log ""
  sleep 2
}

# ─── Static scan: catch obvious bugs with ZERO tokens ────────────
run_static_scan() {
  local scan_dir="$PROJECT_ROOT/dart/lib"
  local out_file="$PROJECT_ROOT/checklist/audit_chunk_static.md"
  log "  🔍 Static scan: grepping for placeholders, stubs, perf issues..."

  {
    echo "## static_scan — Mechanical pattern detection (zero AI cost)"
    echo ""

    # Empty callbacks
    while IFS=: read -r file line content; do
      [[ -n "$file" ]] && echo "- [ ] [CRITICAL] Empty callback — \`$(basename "$file"):$line\` — \`$content\`"
    done < <(grep -rn "onTap: () {}\|onPressed: () {}\|onLongPress: () {}" "$scan_dir/ui/" 2>/dev/null || true)

    # TODO/FIXME/HACK stubs
    while IFS=: read -r file line content; do
      [[ -n "$file" ]] && echo "- [ ] [CRITICAL] TODO/stub marker — \`$(basename "$file"):$line\` — \`${content:0:120}\`"
    done < <(grep -rn "TODO\|FIXME\|HACK\|XXX" "$scan_dir/ui/" "$scan_dir/state/" 2>/dev/null | grep -v "node_modules\|.dart.js" || true)

    # "coming soon" / "not implemented" fake features
    while IFS=: read -r file line content; do
      [[ -n "$file" ]] && echo "- [ ] [CRITICAL] Fake feature — \`$(basename "$file"):$line\` — \`${content:0:120}\`"
    done < <(grep -rn "coming soon\|not yet supported\|not implemented\|not.supported" "$scan_dir/ui/" 2>/dev/null | grep -iv "ErrNotSupported\|// not" || true)

    # debugPrint used as stub implementation
    while IFS=: read -r file line content; do
      [[ -n "$file" ]] && echo "- [ ] [MAJOR] debugPrint stub (should be real implementation) — \`$(basename "$file"):$line\`"
    done < <(grep -rn "debugPrint" "$scan_dir/ui/" 2>/dev/null || true)

    # Non-builder ListViews (perf issue)
    while IFS=: read -r file line content; do
      [[ -n "$file" ]] && echo "- [ ] [MAJOR] Non-lazy ListView (use ListView.builder) — \`$(basename "$file"):$line\`"
    done < <(grep -rn "ListView(" "$scan_dir/ui/" 2>/dev/null | grep -v "ListView.builder\|ListView.separated\|ListView.custom" || true)

    # Empty catch blocks (silent error swallowing)
    while IFS=: read -r file line content; do
      [[ -n "$file" ]] && echo "- [ ] [MAJOR] Empty catch block (silently swallows errors) — \`$(basename "$file"):$line\`"
    done < <(grep -rn "catch.*{}" "$scan_dir/" 2>/dev/null || true)

    # Resource leak detection: addListener without removeListener per file
    for f in "$scan_dir/ui/"*.dart "$scan_dir/state/"*.dart; do
      [[ -f "$f" ]] || continue
      local adds removes fname
      fname=$(basename "$f")
      adds=$(grep -c "addListener\|\.listen(" "$f" 2>/dev/null || true)
      adds="${adds//[^0-9]/}"; [[ -z "$adds" ]] && adds=0
      removes=$(grep -c "removeListener\|\.cancel()" "$f" 2>/dev/null || true)
      removes="${removes//[^0-9]/}"; [[ -z "$removes" ]] && removes=0
      if [[ $adds -gt 0 && $removes -lt $adds ]]; then
        echo "- [ ] [MAJOR] Potential resource leak: $adds listeners/subscriptions added but only $removes removed — \`$fname\`"
      fi
    done

    # Timer leak detection
    for f in "$scan_dir/ui/"*.dart "$scan_dir/state/"*.dart; do
      [[ -f "$f" ]] || continue
      local timers cancels fname
      fname=$(basename "$f")
      timers=$(grep -c "Timer(\|Timer.periodic(" "$f" 2>/dev/null || true)
      timers="${timers//[^0-9]/}"; [[ -z "$timers" ]] && timers=0
      cancels=$(grep -c "\.cancel()" "$f" 2>/dev/null || true)
      cancels="${cancels//[^0-9]/}"; [[ -z "$cancels" ]] && cancels=0
      if [[ $timers -gt 0 && $cancels -lt $timers ]]; then
        echo "- [ ] [MAJOR] Potential timer leak: $timers timers created but only $cancels cancel() calls — \`$fname\`"
      fi
    done

    # setState after await without mounted check
    while IFS= read -r match; do
      [[ -n "$match" ]] && echo "- [ ] [MAJOR] setState after await without mounted check — $match"
    done < <(
      for f in "$scan_dir/ui/"*.dart; do
        [[ -f "$f" ]] || continue
        awk '
          /await / { awaiting=NR; file=FILENAME }
          /setState/ && awaiting && (NR - awaiting) <= 5 {
            # Check if mounted appears between await and setState
            found_mounted=0
            for (i=awaiting; i<=NR; i++) {
              if (lines[i] ~ /mounted/) found_mounted=1
            }
            if (!found_mounted) print "`" FILENAME ":" NR "` — setState " (NR-awaiting) " lines after await"
            awaiting=0
          }
          { lines[NR]=$0 }
          /[;}]/ && !/await/ && !/setState/ { if (NR - awaiting > 5) awaiting=0 }
        ' "$f" 2>/dev/null
      done || true
    )

    # context.read inside build() methods (should be context.watch for reactivity)
    while IFS=: read -r file line content; do
      [[ -n "$file" ]] && echo "- [ ] [CRITICAL] context.read inside build (should be context.watch for reactivity) — \`$(basename "$file"):$line\`"
    done < <(
      for f in "$scan_dir/ui/"*.dart; do
        [[ -f "$f" ]] || continue
        awk '
          /Widget build\(/ { in_build=1 }
          in_build && /context\.read</ { print FILENAME ":" NR ":" $0 }
          in_build && /^[[:space:]]*\}/ && !/if|else|for|while|switch|try|catch/ { in_build=0 }
        ' "$f" 2>/dev/null
      done || true
    )

  } > "$out_file"

  local count
  count=$(grep -c '^- \[ \]' "$out_file" 2>/dev/null || true)
  count="${count//[^0-9]/}"
  [[ -z "$count" ]] && count=0
  log "  📊 Static scan: $count issues found (cost: \$0)"
}

# ─── AyuGram palette diff: catch color mismatches for $0 ────────
run_palette_diff() {
  local palette_file="$AYUGRAM_DIR/Telegram/lib_ui/ui/colors.palette"
  local dart_palette="$PROJECT_ROOT/dart/lib/theme/telegram_palette.dart"
  local out_file="$PROJECT_ROOT/checklist/audit_chunk_palette.md"

  if [[ ! -f "$palette_file" || ! -f "$dart_palette" ]]; then
    log "  ⏭️  Palette diff: skipped (files not found)"
    return
  fi

  log "  🎨 Palette diff: comparing AyuGram colors.palette vs telegram_palette.dart..."

  {
    echo "## palette_diff — Color comparison (zero AI cost)"
    echo ""

    # Extract hex colors from AyuGram palette (resolve simple aliases)
    # Format: "windowBg: #ffffff;" → windowBg=#ffffff
    declare -A ayugram_colors
    while IFS= read -r pline; do
      pline=$(echo "$pline" | sed 's/\/\/.*//;s/^[[:space:]]*//' | tr -d ';')
      [[ -z "$pline" || "$pline" == //* ]] && continue
      local key val
      key=$(echo "$pline" | cut -d: -f1 | tr -d ' ')
      val=$(echo "$pline" | cut -d: -f2- | tr -d ' ')
      [[ -n "$key" && -n "$val" ]] && ayugram_colors["$key"]="$val"
    done < "$palette_file"

    # Extract Color(0xFFRRGGBB) from Dart palette
    while IFS= read -r dline; do
      local dart_key dart_hex
      dart_key=$(echo "$dline" | grep -oP "static\s+const\s+Color\s+\K\w+" || true)
      dart_hex=$(echo "$dline" | grep -oP "Color\(0x\K[0-9A-Fa-f]{8}" || true)
      [[ -z "$dart_key" || -z "$dart_hex" ]] && continue
      # Convert 0xAARRGGBB to #rrggbb (drop alpha)
      local dart_rgb="#${dart_hex:2:6}"
      dart_rgb=$(echo "$dart_rgb" | tr '[:upper:]' '[:lower:]')
      # Check if this key exists in AyuGram
      local ayu_val="${ayugram_colors[$dart_key]:-}"
      if [[ -z "$ayu_val" ]]; then
        continue  # Dart-only color, not necessarily a bug
      fi
      # Resolve simple alias: if ayu_val doesn't start with #, follow one level
      if [[ "$ayu_val" != \#* ]]; then
        ayu_val="${ayugram_colors[$ayu_val]:-$ayu_val}"
      fi
      if [[ "$ayu_val" == \#* ]]; then
        local ayu_rgb
        ayu_rgb=$(echo "$ayu_val" | tr '[:upper:]' '[:lower:]')
        if [[ "$dart_rgb" != "$ayu_rgb" ]]; then
          local linenum
          linenum=$(grep -n "$dart_key" "$dart_palette" 2>/dev/null | head -1 | cut -d: -f1 || true)
          echo "- [ ] [MAJOR] Color mismatch '$dart_key': AyuGram=$ayu_rgb, Dart=$dart_rgb — \`telegram_palette.dart:${linenum:-?}\` ← \`colors.palette\`"
        fi
      fi
    done < "$dart_palette"

    # Check for AyuGram colors missing from Dart
    for ayu_key in "${!ayugram_colors[@]}"; do
      if ! grep -q "$ayu_key" "$dart_palette" 2>/dev/null; then
        local ayu_val="${ayugram_colors[$ayu_key]}"
        [[ "$ayu_val" == \#* ]] && echo "- [ ] [MAJOR] Missing palette entry '$ayu_key' (AyuGram=$ayu_val) — \`telegram_palette.dart\` ← \`colors.palette\`"
      fi
    done

  } > "$out_file"

  local count
  count=$(grep -c '^- \[ \]' "$out_file" 2>/dev/null || true)
  count="${count//[^0-9]/}"
  [[ -z "$count" ]] && count=0
  log "  📊 Palette diff: $count color mismatches found (cost: \$0)"
}

# ─── AyuGram style extraction: pre-build context for sessions ───
extract_ayugram_context() {
  local dart_file="$1"
  local dart_basename
  dart_basename=$(basename "$dart_file" .dart)
  local context=""

  # Map Dart files to likely AyuGram directories by name/purpose
  local ayu_dirs=()
  case "$dart_basename" in
    # Layout & Navigation
    shell|titlebar)                     ayu_dirs=("window") ;;
    hamburger_drawer)                   ayu_dirs=("window") ;;
    filter_column)                      ayu_dirs=("dialogs") ;;
    chat_list*)                         ayu_dirs=("dialogs" "dialogs/ui") ;;
    chat_switch_overlay)                ayu_dirs=("dialogs") ;;
    # Messages & Chat
    message_bubble)                     ayu_dirs=("history/view" "history/view/media") ;;
    chat_view)                          ayu_dirs=("history" "history/view") ;;
    send_files_box)                     ayu_dirs=("boxes") ;;
    # Panels
    info_panel)                         ayu_dirs=("info" "info/profile") ;;
    peer_short_info)                    ayu_dirs=("info") ;;
    my_profile_page)                    ayu_dirs=("info" "settings") ;;
    # Settings
    settings*|chat_settings*|privacy*|notifications*|advanced*|folders*|active_sessions*|shortcuts*)
                                        ayu_dirs=("settings" "settings/sections") ;;
    # Calls
    call_*|calls_*)                     ayu_dirs=("calls") ;;
    # Emoji & Stickers
    emoji_panel|custom_emoji*)          ayu_dirs=("chat_helpers") ;;
    sticker*|emoji_status*)             ayu_dirs=("chat_helpers") ;;
    # Auth
    auth_screen|auth_state)             ayu_dirs=("intro") ;;
    # Media
    media_viewer)                       ayu_dirs=("media/view") ;;
    photo_crop_editor)                  ayu_dirs=("editor") ;;
    story_editor)                       ayu_dirs=("media/stories") ;;
    # Boxes & Dialogs
    admin_tools)                        ayu_dirs=("boxes/peers") ;;
    create_group*|create_channel*)      ayu_dirs=("boxes/peers") ;;
    contacts_screen)                    ayu_dirs=("boxes") ;;
    confirm_box|input_dialogs)          ayu_dirs=("boxes") ;;
    choose_datetime_box)                ayu_dirs=("boxes") ;;
    color_picker_box)                   ayu_dirs=("boxes") ;;
    edit_forum_topic_box|forum_topic*)  ayu_dirs=("boxes/peers") ;;
    language_box)                       ayu_dirs=("boxes") ;;
    chat_export)                        ayu_dirs=("export") ;;
    payment_panel)                      ayu_dirs=("payments") ;;
    # Context menus & popups
    popup_menu)                         ayu_dirs=("ui" "history/view" "dialogs/ui") ;;
    reactions_detail)                   ayu_dirs=("history/view") ;;
    # Theme & Appearance
    *theme*|*wallpaper*|telegram_palette) ayu_dirs=("boxes" "window") ;;
    # Notifications
    notification_popup|notification_*)  ayu_dirs=("window") ;;
    # Keyboard & Input
    keyboard_shortcuts)                 ayu_dirs=("core") ;;
    spoiler_animation)                  ayu_dirs=("ui/effects") ;;
    instant_view)                       ayu_dirs=("iv") ;;
    web_app_panel)                      ayu_dirs=("calls") ;;
    # AyuGram-specific
    ghost_*|ayu_*)                      ayu_dirs=("ayu" "ayu/ui") ;;
    # State & Bridge
    app_state|chat_state|engine_service) ayu_dirs=("data" "core") ;;
    ayu_forward)                        ayu_dirs=("ayu") ;;
    # Stats
    stats_chart)                        ayu_dirs=("data") ;;
    # Misc UI
    telegram_toast|telegram_tooltip)    ayu_dirs=("ui/toast" "ui") ;;
    # Fallback: search broadly
    *)                                  ayu_dirs=("ui" "boxes") ;;
  esac

  if [[ ${#ayu_dirs[@]} -eq 0 ]]; then
    echo "(no pre-mapped AyuGram context for $dart_basename)"
    return
  fi

  # Extract relevant .style values
  context+="=== AYUGRAM STYLE VALUES ==="$'\n'
  for dir in "${ayu_dirs[@]}"; do
    for style_file in "$AYUGRAM_UI/$dir"/*.style "$AYUGRAM_UI/ui/$dir"/*.style; do
      [[ -f "$style_file" ]] || continue
      context+="--- $(basename "$style_file") ---"$'\n'
      # Extract pixel values and key definitions (skip comments, includes)
      context+="$(grep -E "^[a-zA-Z].*: [0-9]+px|^[a-zA-Z].*: margins\(|^[a-zA-Z].*: font\(|^[a-zA-Z].*: #[0-9a-fA-F]" "$style_file" 2>/dev/null | head -80 || true)"$'\n'
      context+=$'\n'
    done
  done

  # Extract key function signatures from .h files
  context+="=== AYUGRAM HEADER SIGNATURES ==="$'\n'
  for dir in "${ayu_dirs[@]}"; do
    for h_file in "$AYUGRAM_UI/$dir"/*.h "$AYUGRAM_UI/ui/$dir"/*.h; do
      [[ -f "$h_file" ]] || continue
      context+="--- $(basename "$h_file") ---"$'\n'
      # Extract class declarations and public method signatures
      context+="$(grep -E "^class |void |bool |int |QString |QRect |QSize |static |virtual " "$h_file" 2>/dev/null | head -30 || true)"$'\n'
      context+=$'\n'
    done
  done

  echo "$context"
}

# (tier routing removed — every session uses the single Opus model $RALPH_MODEL)

# ─── Skeleton extraction: reduce tokens by 80% ──────────────────
extract_skeleton() {
  local dart_file="$1"
  local skeleton=""

  # Extract only the interesting parts: callbacks, constants, bridge calls, switch cases
  skeleton+="=== FILE: $(basename "$dart_file") ==="$'\n'
  skeleton+="--- Class/Widget declarations ---"$'\n'
  skeleton+="$(grep -n "^class \|^abstract class \|^mixin " "$dart_file" 2>/dev/null || true)"$'\n'
  skeleton+="--- Callbacks (onTap, onPressed, etc.) with context ---"$'\n'
  skeleton+="$(grep -n -B1 -A3 "onTap:\|onPressed:\|onLongPress:\|onChanged:\|onSubmitted:" "$dart_file" 2>/dev/null || true)"$'\n'
  skeleton+="--- Numeric constants and dimensions ---"$'\n'
  skeleton+="$(grep -n "height:\|width:\|fontSize:\|EdgeInsets\|SizedBox\|BorderRadius\|= [0-9]" "$dart_file" 2>/dev/null | head -60 || true)"$'\n'
  skeleton+="--- Bridge/Engine calls ---"$'\n'
  skeleton+="$(grep -n "bridge\.\|engine\.\|_engine\.\|EngineService\.\|\.call(" "$dart_file" 2>/dev/null || true)"$'\n'
  skeleton+="--- Switch/case blocks (stub detection) ---"$'\n'
  skeleton+="$(grep -n -A2 "case '\|case \"" "$dart_file" 2>/dev/null | head -80 || true)"$'\n'
  skeleton+="--- Color values ---"$'\n'
  skeleton+="$(grep -n "Color(\|0xFF\|0xff\|AppColors\.\|TelegramPalette\." "$dart_file" 2>/dev/null | head -40 || true)"$'\n'
  skeleton+="--- State fields ---"$'\n'
  skeleton+="$(grep -n "bool _\|int _\|String _\|List<\|Map<\|final _\|late " "$dart_file" 2>/dev/null | head -40 || true)"$'\n'
  skeleton+="--- Lifecycle methods (initState, dispose, didChangeDependencies) ---"$'\n'
  skeleton+="$(grep -n -A5 "void initState\|void dispose\|void didChangeDependencies\|void didUpdateWidget" "$dart_file" 2>/dev/null | head -60 || true)"$'\n'
  skeleton+="--- Error handling (try/catch) ---"$'\n'
  skeleton+="$(grep -n -B1 -A2 "} catch\|catch (" "$dart_file" 2>/dev/null | head -40 || true)"$'\n'
  skeleton+="--- Animation constants (Duration, Curves, controllers) ---"$'\n'
  skeleton+="$(grep -n "Duration(\|Curves\.\|AnimationController\|Tween\|AnimatedBuilder\|vsync" "$dart_file" 2>/dev/null | head -30 || true)"$'\n'

  echo "$skeleton"
}

# ─── Fingerprint cache for skip-unchanged ────────────────────────
FINGERPRINT_FILE="$PROJECT_ROOT/audit/fingerprints.json"

should_audit_file() {
  local dart_file="$1" cycle="$2"
  # Default to full audits. Fingerprint skipping can hide work after interrupted
  # runs or stale false-negatives; only enable it explicitly with
  # RALPH_SKIP_UNCHANGED=1.
  [[ "$SKIP_UNCHANGED" == "1" ]] || return 0
  [[ -f "$INTERRUPT_FILE" ]] && return 0
  # Always audit on cycle 1
  [[ "$cycle" -le 1 ]] && return 0
  # Check if file hash changed since last audit
  local current_hash
  current_hash=$(sha256sum "$dart_file" 2>/dev/null | cut -d' ' -f1)
  local stored_hash
  stored_hash=$(jq -r --arg f "$dart_file" '.[$f] // ""' "$FINGERPRINT_FILE" 2>/dev/null || true)
  if [[ "$current_hash" == "$stored_hash" ]]; then
    return 1  # unchanged, skip
  fi
  return 0  # changed or new, audit
}

update_fingerprint() {
  local dart_file="$1"
  [[ "$SKIP_UNCHANGED" == "1" ]] || return 0
  [[ -f "$INTERRUPT_FILE" ]] && return 0
  local current_hash
  current_hash=$(sha256sum "$dart_file" 2>/dev/null | cut -d' ' -f1)
  # Create or update the fingerprint file
  if [[ ! -f "$FINGERPRINT_FILE" ]]; then
    echo '{}' > "$FINGERPRINT_FILE"
  fi
  local tmp
  tmp=$(jq --arg f "$dart_file" --arg h "$current_hash" '. + {($f): $h}' "$FINGERPRINT_FILE" 2>/dev/null)
  [[ -n "$tmp" ]] && echo "$tmp" > "$FINGERPRINT_FILE"
}

# Retry/backoff on transient failures handled by invoke_claude() + circuit breaker.
# No output-parsing rate limit detection (too fragile, causes false positives).

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

# ─── Stream formatter for pretty terminal output ────────────────
JQ_FMT='
  try fromjson catch empty | . as $e |
  (now|localtime|strftime("%H:%M:%S")) as $ts |
  if $e.type == "assistant" then
    ($e.message.content // [])[] |
      if .type == "text" then
        "\n  [\($ts)]\n\(.text | split("\n") | map("  │ \(.)") | join("\n"))\n"
      elif .type == "tool_use" then
        if .name == "Read" then       "\n  [\($ts)] 📖 Read \(.input.file_path | ltrimstr($root))"
        elif .name == "Edit" then     "\n  [\($ts)] ✏️  Edit \(.input.file_path | ltrimstr($root))"
        elif .name == "Write" then    "\n  [\($ts)] 📝 Write \(.input.file_path | ltrimstr($root))"
        elif .name == "Bash" then     "\n  [\($ts)] $ \(.input.command | gsub("\n"; " ; ") | .[:200])"
        elif .name == "Grep" then     "\n  [\($ts)] 🔍 Grep \"\(.input.pattern // "")\" in \(.input.path // "." | ltrimstr($root))"
        elif .name == "Glob" then     "\n  [\($ts)] 🔍 Glob \(.input.pattern // "")"
        elif .name == "Agent" then    "\n  [\($ts)] 🤖 Agent: \(.input.description // "")"
        else                          "\n  [\($ts)] 🔧 \(.name)"
        end
      else empty end
  elif $e.type == "user" then
    ($e.message.content // [])[] |
      if .type == "tool_result" then
        (.content | tostring | split("\n")) as $lines |
        if ($lines | length) == 0 or ($lines[0] | length) == 0 then "  [\($ts)] ✓"
        elif ($lines[0] | test("(?i)^(error|fail|exception|fatal)")) then "  [\($ts)] ❌ \($lines[0][:200])"
        else "  [\($ts)] ✓ \($lines[0][:160])"
        end
      else empty end
  elif $e.type == "system" and $e.subtype == "init" then
    "\n  ┌─────────────────────────────────────────┐\n  │ 🚀 [\(now|localtime|strftime("%H:%M:%S"))] Session \($e.session_id // "")  │\n  └─────────────────────────────────────────┘\n"
  elif $e.type == "result" then
    ($e.subtype // "unknown") as $subtype |
    (if $subtype == "success" then "✅" else "❌" end) as $icon |
    "\n  ┌─────────────────────────────────────────┐\n  │ \($icon) [\(now|localtime|strftime("%Y-%m-%d %H:%M:%S"))] \($subtype) — \(($e.duration_ms // 0) / 1000)s, $\($e.total_cost_usd // 0)  │\n  └─────────────────────────────────────────┘\n"
  else empty end'

claude_result_subtype() {
  local jsonl_file="$1"
  jq -Rr 'try (fromjson | select(.type == "result") | .subtype // "unknown") catch empty' "$jsonl_file" 2>/dev/null | tail -1 || true
}

normalize_claude_exit() {
  local current_code="$1" jsonl_file="$2" subtype
  if [[ -f "$INTERRUPT_FILE" ]]; then
    echo 130
    return
  fi
  subtype=$(claude_result_subtype "$jsonl_file")
  if [[ -n "$subtype" && "$subtype" != "success" ]]; then
    echo 1
  else
    echo "$current_code"
  fi
}

# ─── Claude invocation with circuit breaker + timeout ────────────
# $1=prompt $2=log_file $3=label $4=model(optional) $5=effort(optional)
# $6=resume_key(optional): assign a known session id so a Ctrl+C'd session can be
#    continued mid-task on the next run instead of restarting from scratch.
invoke_claude() {
  local prompt="$1" iter_file="$2" label="$3" model="${4:-$RALPH_MODEL}" effort="${5:-max}"
  local resume_key="${6:-}"

  circuit_breaker_check || return 1
  wait_for_internet

  echo ""
  log "┌──────────────────────────────────────────────────────────"
  log "│ 🧠 Claude session: $label"
  log "│ 📦 Model: $model | Effort: $effort"
  log "│ 📄 Log: $iter_file"
  log "└──────────────────────────────────────────────────────────"

  # ── Mid-session resume (Implement/Verify only) ──────────────────
  # A leftover session-id file means this exact unit was interrupted last run;
  # --resume continues that conversation (Claude reloads what it read/edited/
  # decided). Otherwise assign a fresh known id we can resume later. The retry
  # path below always --resumes, since the session exists after the first call.
  local -a session_args=() retry_session_args=()
  local sid_file="" sid="" effective_prompt="$prompt" retry_prompt="$prompt"
  local resume_nudge="You were interrupted (Ctrl+C) partway through a task in THIS conversation. Do NOT restart from scratch. Re-read what you already did above, check the on-disk state of any files you were editing, and continue from exactly where you left off until the original task — described earlier in this conversation — is fully complete."
  if [[ -n "$resume_key" ]]; then
    mkdir -p "$RESUME_DIR" 2>/dev/null || true
    sid_file="$RESUME_DIR/session_${resume_key}.id"
    [[ -s "$sid_file" ]] && sid=$(cat "$sid_file" 2>/dev/null || true)
    if [[ -n "$sid" ]]; then
      session_args=(--resume "$sid")
      effective_prompt="$resume_nudge"
      log "  ↻ Resuming interrupted $label session ($sid) — continuing mid-task, not restarting."
    else
      sid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)
      if [[ -n "$sid" ]]; then
        printf '%s' "$sid" > "$sid_file" 2>/dev/null || true
        session_args=(--session-id "$sid")
      fi
    fi
    [[ -n "$sid" ]] && { retry_session_args=(--resume "$sid"); retry_prompt="$resume_nudge"; }
  fi

  # Run claude to a file in the background, then pretty-print live by tailing it
  # with --pid. Tailing the PID (instead of piping claude straight into jq) makes
  # the formatter stop the instant the REAL claude process exits — even if the
  # session left a background child (e.g. the launched app) holding an fd. Piping
  # directly would block forever waiting for EOF on that still-open fd: the
  # "✅ success box, then nothing" hang.
  local code=0 claude_pid
  : > "$iter_file.jsonl"
  "$CLAUDE_BIN" \
    --print \
    "${session_args[@]}" \
    --dangerously-skip-permissions \
    --permission-mode bypassPermissions \
    --model "$model" \
    --effort "$effort" \
    --output-format stream-json \
    --verbose \
    -p "$effective_prompt" \
    > "$iter_file.jsonl" 2>&1 &
  claude_pid=$!
  tail -n +1 -f --pid="$claude_pid" "$iter_file.jsonl" 2>/dev/null \
    | jq -Rr --unbuffered --arg root "$PROJECT_ROOT/" "$JQ_FMT" \
    | tee -a "$iter_file" || true
  if wait "$claude_pid"; then code=0; else code=$?; fi

  # Log cost from stream
  local cost duration
  cost=$(grep -o '"total_cost_usd":[0-9.]*' "$iter_file.jsonl" 2>/dev/null | tail -1 | grep -o '[0-9.]*' || echo "0")
  duration=$(grep -o '"duration_ms":[0-9]*' "$iter_file.jsonl" 2>/dev/null | tail -1 | grep -o '[0-9]*' || echo "0")
  local duration_s=$(( ${duration:-0} / 1000 ))
  echo "$(date '+%H:%M:%S') $label $model \$$cost ${duration_s}s" >> "$COST_LOG" || true

  code=$(normalize_claude_exit "$code" "$iter_file.jsonl")

  # On failure: check internet, backoff, retry once. Ctrl+C is an intentional
  # stop, so do not retry inside this exiting process; the next ralph run will
  # retry because no checklist/fingerprint state is advanced.
  if [[ $code -ne 0 && $code -ne 130 ]]; then
    wait_for_internet
    local backoff=$(( 30 + RANDOM % 30 ))  # 30-60s jitter
    log "  ⏳ Failed (exit $code). Retrying in ${backoff}s..."
    sleep "$backoff"
    code=0
    : > "$iter_file.jsonl"
    "$CLAUDE_BIN" \
      --print \
      "${retry_session_args[@]}" \
      --dangerously-skip-permissions \
      --permission-mode bypassPermissions \
      --model "$model" \
      --effort "$effort" \
      --output-format stream-json \
      --verbose \
      -p "$retry_prompt" \
      > "$iter_file.jsonl" 2>&1 &
    claude_pid=$!
    tail -n +1 -f --pid="$claude_pid" "$iter_file.jsonl" 2>/dev/null \
      | jq -Rr --unbuffered --arg root "$PROJECT_ROOT/" "$JQ_FMT" \
      | tee -a "$iter_file" || true
    if wait "$claude_pid"; then code=0; else code=$?; fi
    code=$(normalize_claude_exit "$code" "$iter_file.jsonl")
    # Re-extract cost
    cost=$(grep -o '"total_cost_usd":[0-9.]*' "$iter_file.jsonl" 2>/dev/null | tail -1 | grep -o '[0-9.]*' || echo "0")
    duration=$(grep -o '"duration_ms":[0-9]*' "$iter_file.jsonl" 2>/dev/null | tail -1 | grep -o '[0-9]*' || echo "0")
    duration_s=$(( ${duration:-0} / 1000 ))
    echo "$(date '+%H:%M:%S') $label-RETRY $model \$$cost ${duration_s}s" >> "$COST_LOG" || true
  fi

  echo ""
  if [[ $code -eq 130 ]]; then
    log "┌──────────────────────────────────────────────────────────"
    log "│ 🛑 $label INTERRUPTED — current work will retry next run"
    log "└──────────────────────────────────────────────────────────"
    circuit_breaker_record true
  elif [[ $code -eq 0 ]]; then
    log "┌──────────────────────────────────────────────────────────"
    log "│ ✅ $label COMPLETE — \$$cost, ${duration_s}s"
    log "└──────────────────────────────────────────────────────────"
    circuit_breaker_record true
  else
    log "┌──────────────────────────────────────────────────────────"
    log "│ ❌ $label FAILED (exit $code) — \$$cost, ${duration_s}s"
    log "└──────────────────────────────────────────────────────────"
    circuit_breaker_record false
  fi

  # Keep the session id ONLY on interrupt, so the next run resumes it; on success
  # or a genuine failure, clear it so the next run starts a fresh session.
  if [[ -n "$sid_file" && $code -ne 130 ]]; then
    rm -f "$sid_file" 2>/dev/null || true
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
    if ! "$SCRIPTS/build_go.sh" linux 2>&1 | tail -3; then
      log "Go build failed"
      return 1
    fi
    if ! "$SCRIPTS/build_flutter.sh" linux debug 2>&1 | tail -5; then
      log "Flutter build failed"
      return 1
    fi
  fi
  (cd "$bundle" && nohup ./uniclient > /tmp/uniclient_log.txt 2>&1 &)
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
  cat <<PROMPT_END
You are running in unattended automation mode (ralph loop). No human is watching.
This is STAGE 1 (IMPLEMENTATION). Implement ALL items in the first section that
has unchecked items. A separate verification session tests your work afterwards.

REFERENCE SOURCE CODE: The AyuGram Desktop (Telegram Desktop fork) source is at:
  $AYUGRAM_UI/
Use it as the PRIMARY reference for exact pixel values, colors, dimensions, and behavior.
Key directories:
  - $AYUGRAM_UI/dialogs/ — chat list, rows, filters
  - $AYUGRAM_UI/history/ — message list, bubbles, compose
  - $AYUGRAM_UI/info/ — info panel, members, shared media
  - $AYUGRAM_UI/settings/ — settings screens
  - $AYUGRAM_UI/calls/ — call UI
  - $AYUGRAM_UI/boxes/ — dialogs, popups
  - $AYUGRAM_UI/window/ — layout, columns, titlebar
Look for .style files (pixel constants), .cpp files (behavior), and .h files (structure).

MANDATORY FIRST STEPS:
1. Read CLAUDE.md (every rule is binding)
2. Read checklist/gui.md — find the FIRST section (## heading) that contains "- [ ]" items
3. Read ALL "- [ ]" items in that section

THEN:
4. Find and read the corresponding AyuGram source files for the UI area being fixed
   (search $AYUGRAM_UI/ for relevant .style, .cpp, .h files)
5. Read existing Dart source files BEFORE writing code
6. Implement ALL items matching the AyuGram reference — no stubs, no placeholders
7. Build and basic sanity check:
   a. ONLY rebuild Go if you changed files under go/: scripts/build_go.sh linux
      (Skip if you only changed dart/ files — saves 30-60 seconds)
   b. scripts/build_flutter.sh linux debug
   c. Launch: cd dart/build/linux/x64/debug/bundle && nohup ./uniclient > /tmp/uniclient_log.txt 2>&1 &
   d. Wait 3s, screenshot: scripts/flutter_inspect.sh screenshot /tmp/ss.png
   e. Verify no crash, features roughly visible
   f. Kill: pkill uniclient
8. Commit: git add <files> && git commit -m "[unverified] <section name>: N items"
9. Do NOT push. Do NOT delete checklist items.

RULES:
- ONE SECTION per session. All items in it, one commit, then exit.
- TELEGRAM ONLY for testing.
- Do NOT refactor unrelated code or fix unrelated bugs.
- The AyuGram source is GROUND TRUTH — match it exactly.
- For placeholder/stub items: do NOT remove the UI element. Make it FUNCTIONAL — wire it
  to the engine, implement real behavior, test on both desktop and mobile.
PROMPT_END
  [[ -n "$extra" ]] && printf '\n%s\n' "$extra"
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
This is STAGE 2 (VERIFICATION). Test whether the section implementation works.

SECTION BEING VERIFIED (all items below):
$item

COMMIT: $commit_msg
FILES: $diff_stat

REFERENCE SOURCE CODE: AyuGram Desktop source is at $AYUGRAM_UI/
Use it to verify exact values. Search for .style files for pixel constants,
.cpp files for behavior. The AyuGram source is GROUND TRUTH.

STEPS:
1. Read CLAUDE.md
2. For each item, find the corresponding AyuGram source files to know the correct values
3. Build & launch the app (skip Go build if only dart/ files changed):
   scripts/build_flutter.sh linux debug
   cd dart/build/linux/x64/debug/bundle && nohup ./uniclient > /tmp/uniclient_log.txt 2>&1 &
4. Run: scripts/flutter_audit.sh verify "section verification"
5. Go through EVERY "- [ ]" item listed above ONE BY ONE:
   For EACH item:
   a. Read what the item claims (e.g. "spec says 46px, code uses 40")
   b. Navigate to the relevant screen/widget in the app
   c. Screenshot in DESKTOP mode (1024x768): scripts/flutter_inspect.sh screenshot /tmp/verify_desktop.png
   d. Verify the specific claim against what you see
   e. Screenshot in MOBILE mode (400x720): scripts/flutter_interact.sh resize mobile + screenshot
   f. Verify it works in mobile too
   g. Mark the item as PASS or FAIL with a specific reason
   h. Resize back to desktop: scripts/flutter_interact.sh resize desktop
   Do NOT skip any item. Do NOT batch-pass items without checking each one individually.
6. Check /tmp/uniclient_log.txt for crashes
7. Kill: pkill uniclient

SEVERITY GUIDE (proportional — Weber's Law):
- CRITICAL: >25% deviation on small elements (<20px), or element missing/broken
- MAJOR: >10% proportional deviation from spec value
- MINOR: 5-10% proportional deviation
- COSMETIC: <5% proportional deviation (do NOT fail for cosmetic issues)

IF ALL ITEMS PASS:
  a. Delete ALL verified items from checklist/gui.md (remove their "- [ ]" lines)
  b. git add checklist/gui.md && git commit -m "Verify & close: <section name>" -- checklist/gui.md
  c. git push origin main
  d. Exit.

IF SOME ITEMS FAIL:
  a. Delete ONLY the items that PASSED from checklist/gui.md
  b. Write failure details for failed items to /tmp/ralph_feedback.txt
  c. git add checklist/gui.md && git commit -m "Verify & close: <section> (partial)" -- checklist/gui.md
  d. git push origin main
  e. Exit.

IF ALL ITEMS FAIL:
  a. Write failure details to /tmp/ralph_feedback.txt
  b. Do NOT modify checklist, do NOT push.
  c. Exit.

Be HARSH on critical/major. Be lenient on cosmetic.
PROMPT_END
}

# ═════════════════════════════════════════════════════════════════
# AUDIT: PER-FILE COMPARISON PROMPT (Opus, per dart file)
# ═════════════════════════════════════════════════════════════════
build_audit_prompt() {
  local dart_file="$1" chunk_id="$2"
  local dart_basename
  dart_basename=$(basename "$dart_file" .dart)
  local skeleton
  skeleton=$(extract_skeleton "$dart_file")
  local ayugram_context
  ayugram_context=$(extract_ayugram_context "$dart_file")
  cat <<PROMPT_END
You are an autonomous auditor. Compare ONE Dart file against AyuGram Desktop C++ source.

DART FILE: $dart_file

--- DART SKELETON (pre-extracted interesting parts) ---
$skeleton
--- END DART SKELETON ---

--- AYUGRAM REFERENCE (pre-extracted style values + headers) ---
$ayugram_context
--- END AYUGRAM REFERENCE ---

The AyuGram context above is pre-extracted. Use it for dimensional/color/style comparisons.
For BEHAVIORAL comparisons, search the AyuGram source: find $AYUGRAM_UI/ -name "*.cpp" | xargs grep -l "keyword"
For suspicious patterns in the skeleton, read the full Dart file sections (Read with offset/limit).

AYUGRAM SOURCE (GROUND TRUTH): $AYUGRAM_UI/
Steps:
1. Read the Dart file completely
2. Figure out what it implements
3. Find matching AyuGram source:
   - find $AYUGRAM_UI/ -name "*.style" -o -name "*.cpp" -o -name "*.h" | xargs grep -l "keyword"
4. Compare line by line

CHECK ALL OF THESE — not just visuals:

**PLACEHOLDERS & STUBS (most important):**
- onTap: () {} — empty callback that does nothing
- TODO/FIXME/HACK comments
- Hardcoded fake data (mock messages, dummy users, static lists)
- SnackBar("coming soon") or similar fake feedback
- Functions that return early or throw "not implemented"
- Features that LOOK functional but aren't wired to the engine/bridge

**BACKEND WIRING:**
- Does the UI actually call the engine (bridge.call) for the feature it displays?
- Are API responses actually used, or is the UI showing cached/stale/fake data?
- Do state changes from the engine (events) actually update the UI?
- Group chats: do sender names come from real user data or are they missing/hardcoded?
- Media: are images actually downloaded and displayed, or just showing placeholders?
- Calls: is the call UI wired to real call engine methods, or is it purely cosmetic?

**VISUAL ACCURACY (compare to AyuGram .style files):**
- Dimensions, colors, fonts, padding, margins
- Layout structure and nesting
- Responsive behavior at different widths

**BEHAVIORAL ACCURACY (compare to AyuGram .cpp files):**
- User interactions: tap, long-press, swipe, scroll, drag
- State transitions: what happens when you tap X?
- Context menus: which items appear and what do they do?
- Error/empty/loading states

**PERFORMANCE & OPTIMIZATION:**
- Unnecessary rebuilds: widgets rebuilding on every frame or every setState when they shouldn't
- Missing const constructors on stateless widgets
- Large lists not using ListView.builder (building all children at once instead of lazy)
- Images not using cacheWidth/cacheHeight or ResizeImage (decoding at full resolution)
- Heavy work on the UI thread (JSON parsing, sorting, filtering in build methods)
- Missing RepaintBoundary on animated/frequently-changing widgets
- Unbounded list growth (lists that grow forever without pagination or eviction)
- Redundant network calls (fetching data already in cache, no deduplication)
- Missing Isolate.run for expensive operations (large list transforms, image processing)

OUTPUT FORMAT — EVERY item cites BOTH files:

## $dart_basename — [short description]

- [ ] [CRITICAL] description — \`$(basename "$dart_file"):lineN\` ← \`AyuGram/path/to/source.style:lineN\`
- [ ] [MAJOR] description — \`$(basename "$dart_file"):lineN\` ← \`AyuGram/path/to/file.cpp:lineN\`

SEVERITY:
- CRITICAL: placeholder/stub, feature not wired to backend, element missing, >25% deviation
- MAJOR: wrong behavior, data not flowing, >10% deviation, wrong state
- Skip MINOR and COSMETIC

RULES:
- AyuGram C++ source is the ONLY authority
- EVERY item MUST cite BOTH files with line numbers
- Placeholders and broken wiring are ALWAYS CRITICAL — a button that does nothing is worse than a button that's 2px off
- If a UI element exists but isn't connected to the engine, that's CRITICAL
- If data should come from the backend but is hardcoded/faked, that's CRITICAL

Write findings to /home/nako/Documents/uniclient/checklist/audit_chunk_${chunk_id}.md
If no issues: write "# ${dart_basename} — No issues found"
PROMPT_END
}


# ═════════════════════════════════════════════════════════════════
# CLEANUP SWEEP PROMPT (placeholders, stubs, optimization — no AyuGram)
# ═════════════════════════════════════════════════════════════════
build_cleanup_prompt() {
  local dart_file="$1" chunk_id="$2"
  local dart_basename
  dart_basename=$(basename "$dart_file" .dart)
  local skeleton
  skeleton=$(extract_skeleton "$dart_file")
  cat <<PROMPT_END
You are a code quality auditor. Find placeholders, stubs, broken wiring, and perf issues.
NOTE: Obvious patterns (empty callbacks, TODOs, debugPrint stubs) were already caught by
a static scan. Focus on things that REQUIRE reading the code to understand.

DART FILE: $dart_file

--- SKELETON (pre-extracted interesting parts) ---
$skeleton
--- END SKELETON ---

For suspicious patterns, read the full context from the Dart file (use Read with offset/limit).

Also read any state/bridge files it imports to verify the wiring is real.

HUNT FOR THESE — be ruthless:

**PLACEHOLDERS & STUBS:**
- onTap: () {} or onPressed: () {} — empty callbacks
- TODO, FIXME, HACK, XXX comments
- Hardcoded strings that should come from the engine ("User", "Chat", "Message")
- Hardcoded fake data (dummy lists, mock objects, static content)
- SnackBar("coming soon") or similar deferred features
- Functions that return null/empty/early without doing real work
- "not implemented" or "not supported" error throws
- Features behind if(false) or commented-out code

**BROKEN WIRING:**
- UI shows data but never calls bridge/engine to fetch it
- State objects with fields that are never updated from engine events
- Buttons/actions that don't call any engine method
- Event listeners registered but handler does nothing
- Auth/session checks that are always true/false

**PERFORMANCE:**
- Unnecessary rebuilds (setState in places it shouldn't be)
- Missing const constructors
- Lists not using ListView.builder
- Images not using cacheWidth/cacheHeight
- Heavy computation in build() methods
- Unbounded list growth
- Missing RepaintBoundary on animated widgets
- Redundant API calls (no caching/dedup)

OUTPUT FORMAT:

## $dart_basename — cleanup

- [ ] [CRITICAL] empty onTap callback at line N — button does nothing — \`$(basename "$dart_file"):N\`
- [ ] [CRITICAL] hardcoded "User" string at line N — should come from engine — \`$(basename "$dart_file"):N\`
- [ ] [MAJOR] ListView builds all children at once (line N) — use ListView.builder — \`$(basename "$dart_file"):N\`

SEVERITY:
- CRITICAL: placeholder, stub, fake feature, broken wiring — these must be made FUNCTIONAL
  (do NOT remove the UI element — implement the real behavior behind it, wired to the engine,
   working on both desktop and mobile)
- MAJOR: performance issue, missing optimization
- Skip anything that actually works correctly

Write findings to /home/nako/Documents/uniclient/checklist/audit_chunk_${chunk_id}.md
If no issues: write "# ${dart_basename} — clean"
PROMPT_END
}

# Remove a repeatedly failing section from gui.md without spending another
# implementation+verification cycle on a prompt that is only allowed to skip it.
skip_current_items() {
  local section_name="$1" current_items="$2"
  local checklist="$PROJECT_ROOT/checklist/gui.md"
  local items_file tmp

  items_file=$(mktemp)
  tmp=$(mktemp)
  printf '%s\n' "$current_items" > "$items_file"

  awk '
    NR == FNR { drop[$0]++; next }
    drop[$0] > 0 { drop[$0]--; next }
    { print }
  ' "$items_file" "$checklist" > "$tmp"
  rm -f "$items_file"
  mv "$tmp" "$checklist"

  git -C "$PROJECT_ROOT" add checklist/gui.md
  git -C "$PROJECT_ROOT" commit -m "Skip GUI items after repeated failures: $section_name" -- checklist/gui.md || return 1
  wait_for_internet
  if ! git -C "$PROJECT_ROOT" push origin main 2>/dev/null; then
    log "  ⚠️  git push failed — skip commit is local only."
  fi
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
DIVERGE_AYUGRAM_COUNT=0
DIVERGE_CLEANUP_COUNT=0
LAST_COMMIT_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"
LAST_AYUGRAM_FINDINGS=999999
LAST_CLEANUP_FINDINGS=999999
# Two-phase audit: "ayugram" (compare vs source) then "cleanup" (stubs/perf)
AUDIT_PHASE="ayugram"

mkdir -p "$AUDIT_DATA"
# Override the defaults above from persisted state if a prior run was interrupted.
load_resume_state

echo ""
log "╔══════════════════════════════════════════════════════════════╗"
log "║           🤖 RALPH v3 — Fully Autonomous Loop               ║"
log "║   AyuGram audit → fix → cleanup sweep → fix → next cycle    ║"
log "╚══════════════════════════════════════════════════════════════╝"
log ""
log "  Mode 1: Implement → Verify (per section)"
log "  Mode 2a: AyuGram source comparison audit"
log "  Mode 2b: Placeholder/optimization cleanup sweep"
log "  Convergence: both phases find zero issues for 2 cycles"
log "  Current stage: $STAGE_FILE"
log "  Progress JSON:  $PROGRESS_FILE"
log "  Kill: Ctrl+C"
log ""
set_current_stage "STARTING" "main loop" "checking checklist/gui.md"

while true; do

  # ─── Check for checklist items ──────────────────────────────
  REMAINING=0
  if [[ -f "$PROJECT_ROOT/checklist/gui.md" ]]; then
    REMAINING=$(grep -c '^- \[ \]' "$PROJECT_ROOT/checklist/gui.md" 2>/dev/null || true)
    REMAINING="${REMAINING:-0}"
    REMAINING="${REMAINING//[^0-9]/}"
    [[ -z "$REMAINING" ]] && REMAINING=0
  fi

  if [[ "$REMAINING" -gt 0 ]]; then
    # ═══════════════════════════════════════════════════════════
    # MODE 1: IMPLEMENT + VERIFY
    # ═══════════════════════════════════════════════════════════
    IMPL_ITERATION=$((IMPL_ITERATION + 1))
    set_current_stage "MODE 1 / SELECT SECTION" "implementation iteration $IMPL_ITERATION" "$REMAINING unchecked checklist items"
    echo ""
    log "╔══════════════════════════════════════════════════════════════╗"
    log "║  🔨 IMPLEMENT #$IMPL_ITERATION                                      "
    log "║  📋 $REMAINING items remaining | ✅ $TOTAL_COMMITS verified commits  "
    log "╚══════════════════════════════════════════════════════════════╝"

    # Extract the first section (## heading) that contains unchecked items
    CURRENT_SECTION=""
    CURRENT_ITEMS=""
    SECTION_NAME=""
    while IFS= read -r line; do
      if [[ "$line" =~ ^##\  ]]; then
        if [[ -n "$CURRENT_ITEMS" ]]; then
          break
        fi
        CURRENT_SECTION="$line"
        SECTION_NAME="${line#\#\# }"
      elif [[ "$line" =~ ^-\ \[\ \] ]] && [[ -n "$CURRENT_SECTION" ]]; then
        CURRENT_ITEMS+="$line"$'\n'
      fi
    done < "$PROJECT_ROOT/checklist/gui.md"
    CURRENT_ITEMS="${CURRENT_ITEMS%$'\n'}"
    ITEM_COUNT=$(echo "$CURRENT_ITEMS" | grep -c '^- \[ \]' || true)
    ITEM_COUNT="${ITEM_COUNT//[^0-9]/}"
    [[ -z "$ITEM_COUNT" ]] && ITEM_COUNT=0
    log ""
    log "  📂 Section: $SECTION_NAME"
    log "  📝 Items: $ITEM_COUNT"
    echo "$CURRENT_ITEMS" | head -5 | while IFS= read -r item_line; do
      log "     $item_line"
    done
    [[ $ITEM_COUNT -gt 5 ]] && log "     ... and $((ITEM_COUNT - 5)) more"
    log ""

    # Guard: if no section found (items exist but no ## headers), treat as audit needed
    if [[ -z "$CURRENT_SECTION" || $ITEM_COUNT -eq 0 ]]; then
      log "  ⚠️  gui.md has unchecked items outside a ## section. Adding a wrapper section instead of deleting them."
      tmp_gui=$(mktemp)
      awk '
        /^- \[ \]/ && !inserted { print "## Unsectioned Items"; inserted=1 }
        { print }
      ' "$PROJECT_ROOT/checklist/gui.md" > "$tmp_gui"
      mv "$tmp_gui" "$PROJECT_ROOT/checklist/gui.md"
      continue
    fi

    pkill -x uniclient 2>/dev/null || true
    rm -f /tmp/uniclient_debug_cmd.json /tmp/uniclient_debug_out.json

    HEAD_SUBJECT="$(git -C "$PROJECT_ROOT" log -1 --format='%s' 2>/dev/null || true)"
    RETRY_VERIFY_ONLY=false
    if [[ "$HEAD_SUBJECT" == \[unverified\]* ]]; then
      RETRY_VERIFY_ONLY=true
      IMPL_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"
      log "Detected existing unverified implementation commit. Retrying verification before implementation."
      # Implement already produced a commit — drop any interrupted-implement
      # session so a later implement never resumes this finished conversation.
      rm -f "$RESUME_DIR/session_implement.id" "$RESUME_DIR/session_implement.sig" 2>/dev/null || true
    fi

    # ── STAGE 1: IMPLEMENT ──────────────────────────────────
    IMPL_FILE="$ITER_LOG_DIR/iter_$(printf '%04d' $IMPL_ITERATION)_impl.log"

    if ! $RETRY_VERIFY_ONLY && [[ $ITEM_ATTEMPTS -ge $MAX_IMPL_ATTEMPTS ]]; then
      set_current_stage "MODE 1 / SKIP FAILED SECTION" "section: $SECTION_NAME" "failed $MAX_IMPL_ATTEMPTS attempts; removing checklist items"
      log "Section failed $MAX_IMPL_ATTEMPTS times. Removing it to avoid an infinite loop."
      if skip_current_items "$SECTION_NAME" "$CURRENT_ITEMS"; then
        SKIP_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"
        if [[ "$SKIP_HASH" != "$LAST_COMMIT_HASH" ]]; then
          LAST_COMMIT_HASH="$SKIP_HASH"
        fi
        ITEM_ATTEMPTS=0
        rm -f "$FEEDBACK_FILE"
        continue
      fi
      log "Failed to skip repeated section; backing off before retry."
      set_current_stage "MODE 1 / BACKOFF" "skip failed" "retrying in ${BACKOFF_BASE}s"
      sleep "$BACKOFF_BASE"
      continue
    fi

    if ! $RETRY_VERIFY_ONLY; then
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

      IMPL_EXIT=0
      set_current_stage "MODE 1 / STAGE 1: IMPLEMENT" "section: $SECTION_NAME" "$ITEM_COUNT item(s); attempt $((ITEM_ATTEMPTS + 1))/$MAX_IMPL_ATTEMPTS"
      resume_guard implement "$SECTION_NAME"
      invoke_claude "$(build_impl_prompt "$IMPL_EXTRA")" "$IMPL_FILE" "IMPLEMENT" "$RALPH_MODEL" "max" "implement" || IMPL_EXIT=$?

      if [[ $IMPL_EXIT -ne 0 ]]; then
        CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
        BACKOFF=$(( BACKOFF_BASE * (2 ** (CONSECUTIVE_FAILURES - 1)) ))
        [[ $BACKOFF -gt $BACKOFF_MAX ]] && BACKOFF=$BACKOFF_MAX
        log "Impl failed (exit $IMPL_EXIT). Backoff ${BACKOFF}s..."
        set_current_stage "MODE 1 / IMPLEMENT BACKOFF" "exit $IMPL_EXIT" "retrying in ${BACKOFF}s"
        sleep "$BACKOFF"; continue
      fi
      CONSECUTIVE_FAILURES=0

      IMPL_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"
      if [[ "$IMPL_HASH" == "$LAST_COMMIT_HASH" ]]; then
        log "No commit. Stall."
        ITEM_ATTEMPTS=$((ITEM_ATTEMPTS + 1)); continue
      fi
      log "Impl committed: $(git -C "$PROJECT_ROOT" log -1 --oneline)"
    fi

    # ── STAGE 2: VERIFY ─────────────────────────────────────
    log ""
    log "  ⏳ Cooling down before verification (2s)..."
    pkill -x uniclient 2>/dev/null || true
    rm -f /tmp/uniclient_debug_cmd.json /tmp/uniclient_debug_out.json
    sleep 2

    VERIFY_FILE="$ITER_LOG_DIR/iter_$(printf '%04d' $IMPL_ITERATION)_verify.log"
    rm -f "$FEEDBACK_FILE"

    VERIFY_EXIT=0
    set_current_stage "MODE 1 / STAGE 2: VERIFY" "section: $SECTION_NAME" "$ITEM_COUNT item(s); implementation commit ${IMPL_HASH:0:12}"
    resume_guard verify "$SECTION_NAME"
    invoke_claude "$(build_verify_prompt "$CURRENT_ITEMS")" "$VERIFY_FILE" "VERIFY" "$RALPH_MODEL" "max" "verify" || VERIFY_EXIT=$?

    if [[ $VERIFY_EXIT -ne 0 ]]; then
      CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
      BACKOFF=$(( BACKOFF_BASE * (2 ** (CONSECUTIVE_FAILURES - 1)) ))
      [[ $BACKOFF -gt $BACKOFF_MAX ]] && BACKOFF=$BACKOFF_MAX
      log "Verify crashed (exit $VERIFY_EXIT). Backoff ${BACKOFF}s..."
      set_current_stage "MODE 1 / VERIFY BACKOFF" "exit $VERIFY_EXIT" "retrying in ${BACKOFF}s"
      sleep "$BACKOFF"; continue
    fi
    CONSECUTIVE_FAILURES=0

    VERIFY_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"
    if [[ "$VERIFY_HASH" != "$IMPL_HASH" ]]; then
      NEW_COMMITS=$(git -C "$PROJECT_ROOT" log --oneline "$LAST_COMMIT_HASH".."$VERIFY_HASH" 2>/dev/null | wc -l)
      TOTAL_COMMITS=$((TOTAL_COMMITS + NEW_COMMITS))
      LAST_COMMIT_HASH="$VERIFY_HASH"
      if [[ -f "$FEEDBACK_FILE" ]]; then
        ITEM_ATTEMPTS=$((ITEM_ATTEMPTS + 1))
        set_current_stage "MODE 1 / PARTIAL VERIFY" "section: $SECTION_NAME" "some items passed; attempt $ITEM_ATTEMPTS/$MAX_IMPL_ATTEMPTS"
        log ""
        log "  ╔════════════════════════════════════════════╗"
        log "  ║  ⚠️  PARTIALLY VERIFIED                    ║"
        log "  ║  $NEW_COMMITS commit(s) | Attempt $ITEM_ATTEMPTS / $MAX_IMPL_ATTEMPTS  ║"
        log "  ╚════════════════════════════════════════════╝"
        log "  Feedback: $(head -2 "$FEEDBACK_FILE" 2>/dev/null || echo 'none')"
      else
        ITEM_ATTEMPTS=0
        set_current_stage "MODE 1 / VERIFIED" "section: $SECTION_NAME" "all items passed; $NEW_COMMITS commit(s)"
        log ""
        log "  ╔════════════════════════════════════════════╗"
        log "  ║  ✅ VERIFIED & PUSHED                      ║"
        log "  ║  $NEW_COMMITS commit(s) | Total: $TOTAL_COMMITS verified  ║"
        log "  ╚════════════════════════════════════════════╝"
      fi
    elif [[ -f "$FEEDBACK_FILE" ]]; then
      ITEM_ATTEMPTS=$((ITEM_ATTEMPTS + 1))
      set_current_stage "MODE 1 / VERIFY FAILED" "section: $SECTION_NAME" "attempt $ITEM_ATTEMPTS/$MAX_IMPL_ATTEMPTS; feedback saved"
      log ""
      log "  ╔════════════════════════════════════════════╗"
      log "  ║  ❌ VERIFICATION FAILED                    ║"
      log "  ║  Attempt $ITEM_ATTEMPTS / $MAX_IMPL_ATTEMPTS — feedback saved    ║"
      log "  ╚════════════════════════════════════════════╝"
      log "  Feedback: $(head -2 "$FEEDBACK_FILE" 2>/dev/null || echo 'none')"
    else
      ITEM_ATTEMPTS=$((ITEM_ATTEMPTS + 1))
      set_current_stage "MODE 1 / VERIFY UNKNOWN" "section: $SECTION_NAME" "no checklist commit and no feedback; attempt $ITEM_ATTEMPTS/$MAX_IMPL_ATTEMPTS"
      log ""
      log "  ⚠️  No push, no feedback. Attempt $ITEM_ATTEMPTS/$MAX_IMPL_ATTEMPTS"
    fi

    pkill -x uniclient 2>/dev/null || true

  else
    # ═══════════════════════════════════════════════════════════
    # MODE 2: AUDIT (two phases: ayugram comparison → cleanup sweep)
    # ═══════════════════════════════════════════════════════════

    if [[ "$AUDIT_PHASE" == "ayugram" ]]; then
      # ── Phase A: AyuGram source comparison ──
      # Only start a NEW cycle when not resuming: a leftover ayugram session
      # file means the previous per-file pass was interrupted before its merge,
      # so we continue that same cycle rather than skipping ahead.
      if [[ -f "$AUDIT_SESSION_FILE" ]] \
         && [[ "$(jq -r '.phase // empty' "$AUDIT_SESSION_FILE" 2>/dev/null || true)" == "ayugram" ]]; then
        log "  ↻ Resuming interrupted AyuGram audit — continuing cycle $AUDIT_CYCLE (not incrementing)."
      else
        AUDIT_CYCLE=$((AUDIT_CYCLE + 1))
      fi

      if [[ $AUDIT_CYCLE -gt $MAX_AUDIT_CYCLES ]]; then
        set_current_stage "STOPPED / MAX AUDIT CYCLES" "cycle $AUDIT_CYCLE" "limit is $MAX_AUDIT_CYCLES"
        log "Max audit cycles ($MAX_AUDIT_CYCLES). Exiting."
        notify "Ralph v3: max audit cycles reached. $TOTAL_COMMITS commits."
        break
      fi

      echo ""
      log "╔══════════════════════════════════════════════════════════════╗"
      log "║  🔍 AUDIT CYCLE $AUDIT_CYCLE / $MAX_AUDIT_CYCLES — Phase A: AyuGram Comparison  "
      log "║  📊 Comparing Dart code against AyuGram Desktop C++ source   "
      log "║  🏷️  Git tag: audit-pre-cycle-${AUDIT_CYCLE}a                          "
      log "╚══════════════════════════════════════════════════════════════╝"
      set_current_stage "MODE 2 / PHASE A: AYUGRAM AUDIT" "cycle $AUDIT_CYCLE/$MAX_AUDIT_CYCLES" "Dart UI vs AyuGram source"

    # Safety tag for manual divergence review
    git -C "$PROJECT_ROOT" tag -f "audit-pre-cycle-${AUDIT_CYCLE}a" HEAD 2>/dev/null || true

    # ── Take SSIM screenshot and compare vs previous cycle ───
    SSIM_DIR="$AUDIT_DATA/ssim_cycle_${AUDIT_CYCLE}"
    mkdir -p "$SSIM_DIR"
    PREV_SSIM_DIR="$AUDIT_DATA/ssim_cycle_$((AUDIT_CYCLE - 1))"

    if launch_app; then
      "$SCRIPTS/flutter_inspect.sh" screenshot "$SSIM_DIR/desktop.png" 2>/dev/null || true
      "$SCRIPTS/flutter_interact.sh" resize mobile 2>/dev/null || true
      sleep 1.5
      "$SCRIPTS/flutter_inspect.sh" screenshot "$SSIM_DIR/mobile.png" 2>/dev/null || true
      "$SCRIPTS/flutter_interact.sh" resize desktop 2>/dev/null || true

      # Compare against previous cycle's screenshots
      if [[ -f "$PREV_SSIM_DIR/desktop.png" ]]; then
        SSIM_DESKTOP=$(ssim_compare "$PREV_SSIM_DIR/desktop.png" "$SSIM_DIR/desktop.png")
        log "  📸 SSIM desktop (vs prev cycle): $SSIM_DESKTOP"
      fi
      if [[ -f "$PREV_SSIM_DIR/mobile.png" ]]; then
        SSIM_MOBILE=$(ssim_compare "$PREV_SSIM_DIR/mobile.png" "$SSIM_DIR/mobile.png")
        log "  📸 SSIM mobile (vs prev cycle): $SSIM_MOBILE"
      fi

      pkill -x uniclient 2>/dev/null || true
    fi

    # ── LAYER 0: Mechanical scans (ZERO tokens) ────────────────
    set_current_stage "MODE 2 / PHASE A: MECHANICAL SCANS" "cycle $AUDIT_CYCLE/$MAX_AUDIT_CYCLES" "static scan and palette diff"
    run_static_scan
    run_palette_diff

    # ── LAYER 1: Per-file audit (Dart vs AyuGram, parallel Opus) ─
    set_current_stage "MODE 2 / PHASE A: PER-FILE AUDIT" "cycle $AUDIT_CYCLE/$MAX_AUDIT_CYCLES" "parallel Dart file comparison"
    log "  Layer 1: Comparing Dart files against AyuGram source (skeleton mode)..."

    # Get all auditable dart files
    mapfile -t ALL_DART_FILES < <((find "$PROJECT_ROOT/dart/lib" -name "*.dart" -type f 2>/dev/null | grep -v '/proto/' || true) | sort)

    # Full audit by default. Fingerprint filtering only activates when
    # RALPH_SKIP_UNCHANGED=1 is explicitly set.
    DART_FILES=()
    SKIPPED_UNCHANGED=0
    for dart_file in "${ALL_DART_FILES[@]}"; do
      if should_audit_file "$dart_file" "$AUDIT_CYCLE"; then
        DART_FILES+=("$dart_file")
      else
        SKIPPED_UNCHANGED=$((SKIPPED_UNCHANGED + 1))
      fi
    done
    NUM_FILES=${#DART_FILES[@]}
    if [[ $SKIPPED_UNCHANGED -gt 0 ]]; then
      log "  📂 Auditing $NUM_FILES files ($SKIPPED_UNCHANGED omitted by explicit RALPH_SKIP_UNCHANGED=1)"
    else
      log "  📂 Auditing ALL $NUM_FILES files (cycle $AUDIT_CYCLE — full scan)"
    fi

    # Resume-aware: keep finished chunks if this continues an interrupted audit;
    # otherwise clear stale chunks/markers and start the phase fresh.
    begin_audit_session "$AUDIT_CYCLE" "ayugram"

    BATCH_SIZE=8
    PIDS=()
    CHUNK_ID=0
    SUCCESSFUL_CHUNKS=0
    FAILED_CHUNKS=0
    unset CHUNK_ID_MAP 2>/dev/null || true
    declare -A CHUNK_ID_MAP

    for dart_file in "${DART_FILES[@]}"; do

      dart_basename=$(basename "$dart_file" .dart)
      dart_rel="${dart_file#$PROJECT_ROOT/dart/lib/}"
      chunk_label="${dart_rel%.dart}"
      chunk_label="${chunk_label//\//_}"
      CHUNK_FILE="$ITER_LOG_DIR/audit_c${AUDIT_CYCLE}_${chunk_label}.log"
      CHUNK_ID_MAP["$dart_file"]=$CHUNK_ID

      # Resume: if this file's audit already finished in an interrupted run
      # (orchestrator-written done-marker present), skip re-auditing it.
      if [[ -f "$DONE_DIR/chunk_${CHUNK_ID}.done" ]]; then
        log "    [$((CHUNK_ID + 1))/$NUM_FILES] $dart_basename.dart — already audited (resume skip)"
        SUCCESSFUL_CHUNKS=$((SUCCESSFUL_CHUNKS + 1))
        CHUNK_ID=$((CHUNK_ID + 1))
        continue
      fi

      model="$RALPH_MODEL"

      PROMPT="$(build_audit_prompt "$dart_file" "$CHUNK_ID")"
      log "    [$((CHUNK_ID + 1))/$NUM_FILES] $dart_basename.dart ($(wc -l < "$dart_file") lines)"

      this_chunk=$CHUNK_ID
      (
        trap - EXIT INT TERM
        set +e
        invoke_claude "$PROMPT" "$CHUNK_FILE" "AUDIT-${chunk_label}" "$model"
        rc=$?
        # Mark done only on clean exit, so an interrupted/failed chunk is retried.
        [[ $rc -eq 0 ]] && touch "$DONE_DIR/chunk_${this_chunk}.done" 2>/dev/null
        exit $rc
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

    for pid in "${PIDS[@]}"; do
      if wait "$pid" 2>/dev/null; then
        SUCCESSFUL_CHUNKS=$((SUCCESSFUL_CHUNKS + 1))
      else
        FAILED_CHUNKS=$((FAILED_CHUNKS + 1))
      fi
    done

    # Update fingerprints for files whose audit produced output
    for dart_file in "${DART_FILES[@]}"; do
      chunk_out="$PROJECT_ROOT/checklist/audit_chunk_${CHUNK_ID_MAP[$dart_file]:-999}.md"
      if [[ -f "$chunk_out" ]]; then
        update_fingerprint "$dart_file"
      fi
    done

    log ""
    log "  📊 Layer 1: $SUCCESSFUL_CHUNKS/$NUM_FILES audited, $FAILED_CHUNKS failed"
    [[ $SKIPPED_UNCHANGED -gt 0 ]] && log "  ⏭️  $SKIPPED_UNCHANGED files omitted only because RALPH_SKIP_UNCHANGED=1"
    [[ $FAILED_CHUNKS -gt 0 ]] && log "  ⚠️  $FAILED_CHUNKS files failed (partial-failure — continuing)"

    else
      # ── Phase B: CLEANUP SWEEP (placeholders, stubs, perf) ──
      echo ""
      log "╔══════════════════════════════════════════════════════════════╗"
      log "║  🧹 AUDIT CYCLE $AUDIT_CYCLE / $MAX_AUDIT_CYCLES — Phase B: Cleanup Sweep       "
      log "║  📊 Hunting placeholders, broken wiring, performance issues  "
      log "║  🏷️  Git tag: audit-pre-cycle-${AUDIT_CYCLE}b                          "
      log "╚══════════════════════════════════════════════════════════════╝"
      set_current_stage "MODE 2 / PHASE B: CLEANUP AUDIT" "cycle $AUDIT_CYCLE/$MAX_AUDIT_CYCLES" "placeholders, broken wiring, performance"

      git -C "$PROJECT_ROOT" tag -f "audit-pre-cycle-${AUDIT_CYCLE}b" HEAD 2>/dev/null || true

      mapfile -t DART_FILES < <((find "$PROJECT_ROOT/dart/lib" -name "*.dart" -type f 2>/dev/null | grep -v '/proto/' || true) | sort)
      NUM_FILES=${#DART_FILES[@]}
      log "  📂 Sweeping ALL $NUM_FILES files for placeholders & perf issues"

      # Resume-aware (see Phase A): keep finished chunks on a continuation.
      begin_audit_session "$AUDIT_CYCLE" "cleanup"

      BATCH_SIZE=8
      PIDS=()
      CHUNK_ID=0
      SUCCESSFUL_CHUNKS=0
      FAILED_CHUNKS=0

      for dart_file in "${DART_FILES[@]}"; do

        dart_basename=$(basename "$dart_file" .dart)
        dart_rel="${dart_file#$PROJECT_ROOT/dart/lib/}"
        chunk_label="${dart_rel%.dart}"
        chunk_label="${chunk_label//\//_}"
        CHUNK_FILE="$ITER_LOG_DIR/cleanup_c${AUDIT_CYCLE}_${chunk_label}.log"

        # Resume: skip files already swept in an interrupted run.
        if [[ -f "$DONE_DIR/chunk_${CHUNK_ID}.done" ]]; then
          log "    [$((CHUNK_ID + 1))/$NUM_FILES] $dart_basename.dart — already swept (resume skip)"
          SUCCESSFUL_CHUNKS=$((SUCCESSFUL_CHUNKS + 1))
          CHUNK_ID=$((CHUNK_ID + 1))
          continue
        fi

        model="$RALPH_MODEL"

        PROMPT="$(build_cleanup_prompt "$dart_file" "$CHUNK_ID")"
        log "    [$((CHUNK_ID + 1))/$NUM_FILES] $dart_basename.dart"

        this_chunk=$CHUNK_ID
        (
          trap - EXIT INT TERM
          set +e
          invoke_claude "$PROMPT" "$CHUNK_FILE" "CLEANUP-${chunk_label}" "$model"
          rc=$?
          [[ $rc -eq 0 ]] && touch "$DONE_DIR/chunk_${this_chunk}.done" 2>/dev/null
          exit $rc
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

      for pid in "${PIDS[@]}"; do
        if wait "$pid" 2>/dev/null; then
          SUCCESSFUL_CHUNKS=$((SUCCESSFUL_CHUNKS + 1))
        else
          FAILED_CHUNKS=$((FAILED_CHUNKS + 1))
        fi
      done

      log ""
      log "  📊 Cleanup: $SUCCESSFUL_CHUNKS/$NUM_FILES swept, $FAILED_CHUNKS failed"
    fi  # end ayugram/cleanup phase

    # ── MERGE: Combine all findings into gui.md ──────────────
    set_current_stage "MODE 2 / MERGE AUDIT FINDINGS" "cycle $AUDIT_CYCLE/$MAX_AUDIT_CYCLES" "writing checklist/gui.md"
    phase_title="Code Comparison (Dart vs AyuGram)"
    [[ "$AUDIT_PHASE" == "cleanup" ]] && phase_title="Cleanup Sweep (placeholders, stubs, perf)"
    {
      echo "# GUI Audit — Cycle $AUDIT_CYCLE Phase ${AUDIT_PHASE^} ($(date '+%Y-%m-%d %H:%M'))"
      echo ""
      echo "## $phase_title"
      echo ""
      for f in "$PROJECT_ROOT/checklist/audit_chunk_"*.md; do
        [[ -f "$f" ]] || continue
        if ! grep -q '^- \[ \]' "$f"; then
          continue
        fi
        cat "$f"
        echo ""
      done
    } > "$PROJECT_ROOT/checklist/gui.md"

    # gui.md is now written from the chunks. Clear this phase's resume markers
    # FIRST (so an interrupt during the chunk cleanup below still leaves no stale
    # session that could re-generate an already-merged checklist), THEN remove
    # the now-merged chunk files.
    end_audit_session
    rm -f "$PROJECT_ROOT/checklist/audit_chunk_"*.md

    FINDINGS=$(grep -c '^- \[ \]' "$PROJECT_ROOT/checklist/gui.md" 2>/dev/null || true)
    FINDINGS="${FINDINGS//[^0-9]/}"
    [[ -z "$FINDINGS" ]] && FINDINGS=0
    echo ""
    log "  ┌──────────────────────────────────────────────────"
    log "  │ 📋 Audit cycle $AUDIT_CYCLE results"
    log "  │ 🔢 Findings: $FINDINGS items"
    log "  │ 📦 Files: $SUCCESSFUL_CHUNKS ok, $FAILED_CHUNKS failed"
    log "  └──────────────────────────────────────────────────"

    if [[ $FAILED_CHUNKS -gt 0 && "$FINDINGS" -eq 0 ]]; then
      CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
      if [[ $CONSECUTIVE_FAILURES -ge $MAX_IMPL_ATTEMPTS ]]; then
        set_current_stage "STOPPED / AUDIT CHUNKS FAILED" "cycle $AUDIT_CYCLE/$MAX_AUDIT_CYCLES" "$FAILED_CHUNKS chunks failed with zero findings $CONSECUTIVE_FAILURES times"
        log "  ❌ Audit phase produced only failed chunks $CONSECUTIVE_FAILURES times. Stopping for manual review."
        notify "Ralph v3: audit chunks keep failing; stopped for manual review."
        break
      fi
      BACKOFF=$(( BACKOFF_BASE * (2 ** (CONSECUTIVE_FAILURES - 1)) ))
      [[ $BACKOFF -gt $BACKOFF_MAX ]] && BACKOFF=$BACKOFF_MAX
      log "  ⚠️  $FAILED_CHUNKS audit chunks failed and no findings were produced. Retrying same phase after ${BACKOFF}s instead of treating it as clean."
      sleep "$BACKOFF"
      continue
    fi
    if [[ "$FINDINGS" -gt 0 || $FAILED_CHUNKS -eq 0 ]]; then
      CONSECUTIVE_FAILURES=0
    fi

    # ── Handle findings ────────────────────────────────────────
    if [[ "$FINDINGS" -eq 0 ]]; then
      if [[ "$AUDIT_PHASE" == "ayugram" ]]; then
        # AyuGram audit found nothing → move to cleanup sweep
        LAST_AYUGRAM_FINDINGS=0
        DIVERGE_AYUGRAM_COUNT=0
        log "  AyuGram audit clean. Moving to Phase B: cleanup sweep..."
        AUDIT_PHASE="cleanup"
        set_current_stage "MODE 2 / PHASE TRANSITION" "AyuGram audit clean" "next stage: Phase B cleanup audit"
        continue
      else
        # Cleanup sweep also found nothing → check convergence
        LAST_CLEANUP_FINDINGS=0
        DIVERGE_CLEANUP_COUNT=0
        CONVERGE_COUNT=$((CONVERGE_COUNT + 1))
        log "  Both phases clean. Convergence: $CONVERGE_COUNT/$CONVERGE_THRESHOLD"
        if [[ $CONVERGE_COUNT -ge $CONVERGE_THRESHOLD ]]; then
          set_current_stage "COMPLETE / CONVERGED" "both audit phases clean" "$CONVERGE_COUNT/$CONVERGE_THRESHOLD clean cycles"
          echo ""
          log "╔══════════════════════════════════════════════════════════════╗"
          log "║  🎉 CONVERGED — both phases zero findings for $CONVERGE_THRESHOLD cycles  ║"
          log "║  🔄 Audit cycles: $AUDIT_CYCLE                                       ║"
          log "║  ✅ Verified commits: $TOTAL_COMMITS                                  ║"
          log "╚══════════════════════════════════════════════════════════════╝"
          notify "Ralph v3: CONVERGED! $TOTAL_COMMITS commits, $AUDIT_CYCLE audit cycles."
          break
        fi
        # Reset to ayugram for next full cycle
        AUDIT_PHASE="ayugram"
        set_current_stage "MODE 2 / NEXT AUDIT CYCLE" "cleanup audit clean" "next stage: Phase A AyuGram audit"
        continue
      fi
    fi

    # ── Divergence detection (per-phase comparison) ─────────
    if [[ "$AUDIT_PHASE" == "ayugram" ]]; then
      LAST_PHASE_FINDINGS=$LAST_AYUGRAM_FINDINGS
      DIVERGE_PHASE_COUNT=$DIVERGE_AYUGRAM_COUNT
      PHASE_TAG_SUFFIX="a"
    else
      LAST_PHASE_FINDINGS=$LAST_CLEANUP_FINDINGS
      DIVERGE_PHASE_COUNT=$DIVERGE_CLEANUP_COUNT
      PHASE_TAG_SUFFIX="b"
    fi
    if [[ "$FINDINGS" -gt "$LAST_PHASE_FINDINGS" && $AUDIT_CYCLE -gt 1 ]]; then
      DIVERGE_PHASE_COUNT=$((DIVERGE_PHASE_COUNT + 1))
      log "  ⚠️  DIVERGENCE: findings $LAST_PHASE_FINDINGS → $FINDINGS (phase count: $DIVERGE_PHASE_COUNT)"
      if [[ "$AUDIT_PHASE" == "ayugram" ]]; then
        DIVERGE_AYUGRAM_COUNT=$DIVERGE_PHASE_COUNT
      else
        DIVERGE_CLEANUP_COUNT=$DIVERGE_PHASE_COUNT
      fi
      if [[ $DIVERGE_PHASE_COUNT -ge 2 ]]; then
        review_tag="audit-pre-cycle-${AUDIT_CYCLE}${PHASE_TAG_SUFFIX}"
        set_current_stage "STOPPED / DIVERGENCE" "cycle $AUDIT_CYCLE phase $PHASE_TAG_SUFFIX" "findings increased from $LAST_PHASE_FINDINGS to $FINDINGS twice"
        if git -C "$PROJECT_ROOT" rev-parse "$review_tag" &>/dev/null; then
          log "  DIVERGENCE confirmed at $review_tag. Stopping for manual review; not resetting or force-pushing."
        else
          log "  DIVERGENCE confirmed but phase tag $review_tag not found."
        fi
        notify "Ralph v3: DIVERGENCE. Stopped for manual review."
        break
      fi
    else
      if [[ "$AUDIT_PHASE" == "ayugram" ]]; then
        DIVERGE_AYUGRAM_COUNT=0
      else
        DIVERGE_CLEANUP_COUNT=0
      fi
    fi
    if [[ "$AUDIT_PHASE" == "ayugram" ]]; then
      LAST_AYUGRAM_FINDINGS=$FINDINGS
    else
      LAST_CLEANUP_FINDINGS=$FINDINGS
    fi
    CONVERGE_COUNT=0

    # ── Commit new checklist ─────────────────────────────────
    phase_label="AyuGram comparison"
    [[ "$AUDIT_PHASE" == "cleanup" ]] && phase_label="cleanup sweep"

    git -C "$PROJECT_ROOT" add checklist/gui.md 2>/dev/null || true
    git -C "$PROJECT_ROOT" commit -m "$(cat <<EOF
Audit cycle $AUDIT_CYCLE ($phase_label): $FINDINGS items found

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)" -- checklist/gui.md 2>/dev/null || true
    wait_for_internet
    if ! git -C "$PROJECT_ROOT" push origin main 2>/dev/null; then
      log "  ⚠️  git push failed — commits are local only."
    fi
    LAST_COMMIT_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"

    # Keep the same phase active until its generated checklist is fixed and
    # verifies clean. Otherwise the next empty-checklist transition would skip
    # the implementation pass for the current phase's findings.
    if [[ "$AUDIT_PHASE" == "ayugram" ]]; then
      log "  AyuGram checklist ($FINDINGS items) committed. Fixing before cleanup sweep."
    else
      log "  Cleanup checklist ($FINDINGS items) committed. Fixing before next AyuGram cycle."
    fi
  fi
done

# ─── Final report ────────────────────────────────────────────────
case "${CURRENT_STAGE:-}" in
  COMPLETE*|STOPPED*) ;;
  *) set_current_stage "COMPLETE / LOOP EXIT" "final report" "main loop exited" ;;
esac

TOTAL_COST="?"
if [[ -f "$COST_LOG" ]]; then
  TOTAL_COST=$(awk '{gsub(/\$/,"",$4); sum+=$4} END{printf "%.2f", sum}' "$COST_LOG" 2>/dev/null || echo "?")
fi

echo ""
log "╔══════════════════════════════════════════════════════════════╗"
log "║                    🏁 RALPH V3 COMPLETE                      ║"
log "╠══════════════════════════════════════════════════════════════╣"
log "║  🔨 Implementation iterations: $IMPL_ITERATION"
log "║  🔍 Audit cycles:              $AUDIT_CYCLE"
log "║  ✅ Verified commits:          $TOTAL_COMMITS"
log "║  💰 Total cost:                \$$TOTAL_COST"
log "╠══════════════════════════════════════════════════════════════╣"
log "║  ⚠️  Known limitations:                                      ║"
log "║    - Same-model blind spot (Claude auditing Claude)          ║"
log "║    - Animation/timing not testable via screenshots           ║"
log "║    - ~10-15% of spec surface requires human judgment         ║"
log "╚══════════════════════════════════════════════════════════════╝"
notify "Ralph v3 DONE. $IMPL_ITERATION impl, $AUDIT_CYCLE audit, $TOTAL_COMMITS commits. \$$TOTAL_COST"
