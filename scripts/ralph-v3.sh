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
#     SSIM regression between cycles for visual change detection
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
AYUGRAM_DIR="/home/nako/Documents/AyuGramDesktop"
AYUGRAM_UI="$AYUGRAM_DIR/Telegram/SourceFiles"

# ─── Startup checks ─────────────────────────────────────────────
for cmd in claude jq magick git; do
  command -v "$cmd" &>/dev/null || { echo "FATAL: '$cmd' not found in PATH. Run inside nix develop."; exit 1; }
done
if [[ ! -d "$AYUGRAM_DIR" ]]; then
  echo "FATAL: AyuGram Desktop not found at $AYUGRAM_DIR"
  echo "Clone it: git clone --depth 1 https://github.com/AyuGram/AyuGramDesktop.git $AYUGRAM_DIR"
  exit 1
fi

# ─── Configuration ───────────────────────────────────────────────
RATE_LIMIT_WAIT="${RALPH_RATE_WAIT:-300}"
BACKOFF_BASE=30
BACKOFF_MAX=300
MAX_IMPL_ATTEMPTS=3
MAX_AUDIT_CYCLES=5
CONVERGE_THRESHOLD=2
CIRCUIT_BREAKER_THRESHOLD=3
CIRCUIT_BREAKER_COOLDOWN=300
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
          linenum=$(grep -n "$dart_key" "$dart_palette" 2>/dev/null | head -1 | cut -d: -f1)
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
      grep -E "^[a-zA-Z].*: [0-9]+px|^[a-zA-Z].*: margins\(|^[a-zA-Z].*: font\(|^[a-zA-Z].*: #[0-9a-fA-F]" "$style_file" 2>/dev/null | head -80
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
      grep -E "^class |void |bool |int |QString |QRect |QSize |static |virtual " "$h_file" 2>/dev/null | head -30
      context+=$'\n'
    done
  done

  echo "$context"
}

# ─── Tier routing: complexity-based skip/haiku/sonnet ─────────────
get_file_tier() {
  local dart_file="$1"
  local lines callbacks switch_cases state_fields score
  lines=$(wc -l < "$dart_file" 2>/dev/null || echo 0)

  callbacks=$(grep -c "onTap:\|onPressed:\|onLongPress:\|bridge\.\|engine\.\|_engine\.\|\.call(" "$dart_file" 2>/dev/null || true)
  callbacks="${callbacks//[^0-9]/}"; [[ -z "$callbacks" ]] && callbacks=0

  switch_cases=$(grep -c "case '\|case \"" "$dart_file" 2>/dev/null || true)
  switch_cases="${switch_cases//[^0-9]/}"; [[ -z "$switch_cases" ]] && switch_cases=0

  state_fields=$(grep -c "bool _\|int _\|String _\|List<.*> _\|Map<.*> _\|late " "$dart_file" 2>/dev/null || true)
  state_fields="${state_fields//[^0-9]/}"; [[ -z "$state_fields" ]] && state_fields=0

  # Complexity score: weighted sum
  score=$(( callbacks * 3 + switch_cases * 2 + state_fields + lines / 200 ))

  if [[ $score -lt 3 ]]; then
    echo "skip"
  elif [[ $score -lt 12 ]]; then
    echo "haiku"
  else
    echo "sonnet"
  fi
}

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

# ─── Rate limit detection & waiting ──────────────────────────────
RATE_LIMITED=false

check_and_wait_rate_limit() {
  local output_file="$1"
  [[ -f "$output_file" ]] || return 1

  # Check for rate limit message (may be JSON-wrapped or plain text)
  if ! grep -q "hit your limit\|rate.limit\|Rate limit\|429\|Too Many Requests" "$output_file" 2>/dev/null; then
    RATE_LIMITED=false
    return 1
  fi

  RATE_LIMITED=true
  log ""
  log "  ⏰ RATE LIMITED detected."

  # Try to extract reset time like "resets 9:30pm (Asia/Muscat)"
  # The text may be JSON-wrapped: {"type":"text","text":"...resets 9:30pm..."}
  local reset_str
  reset_str=$(grep -oP 'resets?\s+\K[0-9]{1,2}:[0-9]{2}\s*(am|pm|AM|PM)' "$output_file" 2>/dev/null | head -1 || true)
  # If not found, try extracting from JSON string values
  if [[ -z "$reset_str" ]]; then
    reset_str=$(jq -r 'select(.type=="result" or .type=="system" or .type=="assistant") | .. | strings' "$output_file" 2>/dev/null \
      | grep -oP 'resets?\s+\K[0-9]{1,2}:[0-9]{2}\s*(am|pm|AM|PM)' 2>/dev/null | head -1 || true)
  fi
  # Last resort: brute-force search for time pattern near "reset"
  if [[ -z "$reset_str" ]]; then
    reset_str=$(cat "$output_file" | tr '\\' '\n' | grep -oP 'resets?\s+\K[0-9]{1,2}:[0-9]{2}\s*(am|pm|AM|PM)' 2>/dev/null | head -1 || true)
  fi

  if [[ -n "$reset_str" ]]; then
    # Parse the time and compute seconds to wait
    local reset_epoch
    reset_epoch=$(date -d "$reset_str" +%s 2>/dev/null || true)
    local now_epoch
    now_epoch=$(date +%s)

    if [[ -n "$reset_epoch" && "$reset_epoch" -gt "$now_epoch" ]]; then
      local wait_secs=$(( reset_epoch - now_epoch + 60 ))  # +60s buffer
      local wait_mins=$(( wait_secs / 60 ))
      log "  ⏰ Rate limit resets at $reset_str. Waiting ${wait_mins} minutes (${wait_secs}s)..."
      log "     Sleeping until $(date -d "+${wait_secs} seconds" '+%H:%M:%S')..."

      # Sleep in chunks so Ctrl+C works and we can show progress
      local slept=0
      while [[ $slept -lt $wait_secs ]]; do
        sleep 30
        slept=$((slept + 30))
        local remaining=$(( wait_secs - slept ))
        if [[ $((slept % 300)) -eq 0 && $remaining -gt 0 ]]; then
          log "     Still waiting... ${remaining}s left ($(date '+%H:%M:%S'))"
        fi
      done
    else
      # Reset time in the past or unparseable — default 30 min wait
      log "  ⏰ Could not parse reset time '$reset_str'. Waiting 30 minutes..."
      sleep 1800
    fi
  else
    # No reset time found — default 30 min wait
    log "  ⏰ No reset time found in output. Waiting 30 minutes..."
    sleep 1800
  fi

  # Reset circuit breaker after rate limit wait (the API should be available now)
  CB_FAILURES=0
  CB_OPEN=false
  CB_OPEN_UNTIL=0
  RATE_LIMITED=false
  log "  ✅ Rate limit wait complete. Circuit breaker reset. Resuming."
  log ""
  return 0
}

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
  if $e.type == "assistant" then
    ($e.message.content // [])[] |
      if .type == "text" then
        "\n\(.text | split("\n") | map("  │ \(.)") | join("\n"))\n"
      elif .type == "tool_use" then
        if .name == "Read" then       "\n  📖 Read \(.input.file_path | ltrimstr($root))"
        elif .name == "Edit" then     "\n  ✏️  Edit \(.input.file_path | ltrimstr($root))"
        elif .name == "Write" then    "\n  📝 Write \(.input.file_path | ltrimstr($root))"
        elif .name == "Bash" then     "\n  $ \(.input.command | gsub("\n"; " ; ") | .[:200])"
        elif .name == "Grep" then     "\n  🔍 Grep \"\(.input.pattern // "")\" in \(.input.path // "." | ltrimstr($root))"
        elif .name == "Glob" then     "\n  🔍 Glob \(.input.pattern // "")"
        elif .name == "Agent" then    "\n  🤖 Agent: \(.input.description // "")"
        else                          "\n  🔧 \(.name)"
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
  elif $e.type == "system" and $e.subtype == "init" then
    "\n  ┌─────────────────────────────────────────┐\n  │ 🚀 Session \($e.session_id // "")  │\n  └─────────────────────────────────────────┘\n"
  elif $e.type == "result" then
    "\n  ┌─────────────────────────────────────────┐\n  │ ✅ \($e.subtype // "done") — \(($e.duration_ms // 0) / 1000)s, $\($e.total_cost_usd // 0)  │\n  └─────────────────────────────────────────┘\n"
  else empty end'

# ─── Claude invocation with circuit breaker + timeout ────────────
# $1=prompt $2=log_file $3=label $4=model(optional) $5=effort(optional)
invoke_claude() {
  local prompt="$1" iter_file="$2" label="$3" model="${4:-claude-opus-4-6}" effort="${5:-max}"

  circuit_breaker_check || return 1
  wait_for_internet

  echo ""
  log "┌──────────────────────────────────────────────────────────"
  log "│ 🧠 Claude session: $label"
  log "│ 📦 Model: $model | Effort: $effort"
  log "│ 📄 Log: $iter_file"
  log "└──────────────────────────────────────────────────────────"

  local code=0
  claude \
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

  # Log cost from stream
  local cost duration
  cost=$(grep -o '"total_cost_usd":[0-9.]*' "$iter_file.jsonl" 2>/dev/null | tail -1 | grep -o '[0-9.]*' || echo "0")
  duration=$(grep -o '"duration_ms":[0-9]*' "$iter_file.jsonl" 2>/dev/null | tail -1 | grep -o '[0-9]*' || echo "0")
  local duration_s=$(( ${duration:-0} / 1000 ))
  echo "$(date '+%H:%M:%S') $label $model \$$cost ${duration_s}s" >> "$COST_LOG" || true

  # Check for rate limit ONLY on failure
  if [[ $code -ne 0 ]] && check_and_wait_rate_limit "$iter_file.jsonl"; then
    # Was rate limited, waited, now retry the same call
    log "  🔄 Retrying $label after rate limit wait..."
    code=0
    claude \
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
    # Re-extract cost
    cost=$(grep -o '"total_cost_usd":[0-9.]*' "$iter_file.jsonl" 2>/dev/null | tail -1 | grep -o '[0-9.]*' || echo "0")
    duration=$(grep -o '"duration_ms":[0-9]*' "$iter_file.jsonl" 2>/dev/null | tail -1 | grep -o '[0-9]*' || echo "0")
    duration_s=$(( ${duration:-0} / 1000 ))
    echo "$(date '+%H:%M:%S') $label-RETRY $model \$$cost ${duration_s}s" >> "$COST_LOG" || true
  fi

  echo ""
  if [[ $code -eq 0 ]]; then
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
  b. git add checklist/gui.md && git commit -m "Verify & close: <section name>"
  c. git push origin main
  d. Exit.

IF SOME ITEMS FAIL:
  a. Delete ONLY the items that PASSED from checklist/gui.md
  b. Write failure details for failed items to /tmp/ralph_feedback.txt
  c. git add checklist/gui.md && git commit -m "Verify & close: <section> (partial)"
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
# AUDIT: PER-FILE COMPARISON PROMPT (Sonnet, per dart file)
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
LAST_AYUGRAM_FINDINGS=999999
LAST_CLEANUP_FINDINGS=999999
# Two-phase audit: "ayugram" (compare vs source) then "cleanup" (stubs/perf)
AUDIT_PHASE="ayugram"

mkdir -p "$AUDIT_DATA"

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
log "  Kill: Ctrl+C"
log ""

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
    update_progress "implement" "iteration $IMPL_ITERATION" "$REMAINING items left"
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
      log "  ⚠️  gui.md has items but no ## section headers. Clearing and re-auditing."
      echo "" > "$PROJECT_ROOT/checklist/gui.md"
      continue
    fi

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
Item: $CURRENT_ITEMS"
      ITEM_ATTEMPTS=0
    fi

    IMPL_EXIT=0
    invoke_claude "$(build_impl_prompt "$IMPL_EXTRA")" "$IMPL_FILE" "IMPLEMENT" || IMPL_EXIT=$?

    if [[ $IMPL_EXIT -ne 0 ]]; then
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
    log ""
    log "  ⏳ Cooling down before verification (2s)..."
    pkill -x uniclient 2>/dev/null || true
    rm -f /tmp/uniclient_debug_cmd.json /tmp/uniclient_debug_out.json
    sleep 2

    VERIFY_FILE="$ITER_LOG_DIR/iter_$(printf '%04d' $IMPL_ITERATION)_verify.log"
    rm -f "$FEEDBACK_FILE"

    VERIFY_EXIT=0
    invoke_claude "$(build_verify_prompt "$CURRENT_ITEMS")" "$VERIFY_FILE" "VERIFY" "claude-sonnet-4-6" || VERIFY_EXIT=$?

    if [[ $VERIFY_EXIT -ne 0 ]]; then
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
      log ""
      log "  ╔════════════════════════════════════════════╗"
      log "  ║  ✅ VERIFIED & PUSHED                      ║"
      log "  ║  $NEW_COMMITS commit(s) | Total: $TOTAL_COMMITS verified  ║"
      log "  ╚════════════════════════════════════════════╝"
    elif [[ -f "$FEEDBACK_FILE" ]]; then
      ITEM_ATTEMPTS=$((ITEM_ATTEMPTS + 1))
      log ""
      log "  ╔════════════════════════════════════════════╗"
      log "  ║  ❌ VERIFICATION FAILED                    ║"
      log "  ║  Attempt $ITEM_ATTEMPTS / $MAX_IMPL_ATTEMPTS — feedback saved    ║"
      log "  ╚════════════════════════════════════════════╝"
      log "  Feedback: $(head -2 "$FEEDBACK_FILE" 2>/dev/null || echo 'none')"
    else
      ITEM_ATTEMPTS=$((ITEM_ATTEMPTS + 1))
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
      AUDIT_CYCLE=$((AUDIT_CYCLE + 1))

      if [[ $AUDIT_CYCLE -gt $MAX_AUDIT_CYCLES ]]; then
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
      update_progress "audit" "cycle $AUDIT_CYCLE phase A" "ayugram comparison"

    # Safety tag for rollback
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
    update_progress "audit" "cycle $AUDIT_CYCLE" "Layer 0: mechanical scans"
    run_static_scan
    run_palette_diff

    # ── LAYER 1: Per-file audit (Dart vs AyuGram, parallel Sonnet) ─
    update_progress "audit" "cycle $AUDIT_CYCLE" "Layer 1: per-file code comparison"
    log "  Layer 1: Comparing Dart files against AyuGram source (skeleton mode)..."

    # Get all auditable dart files
    mapfile -t ALL_DART_FILES < <(find "$PROJECT_ROOT/dart/lib" -name "*.dart" -type f 2>/dev/null | grep -v '/proto/' | sort)

    # Filter by fingerprint on cycle 2+ (skip unchanged files)
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
      log "  📂 Auditing $NUM_FILES files ($SKIPPED_UNCHANGED unchanged, skipped)"
    else
      log "  📂 Auditing ALL $NUM_FILES files (cycle $AUDIT_CYCLE — full scan)"
    fi

    rm -f "$PROJECT_ROOT/checklist/audit_chunk_"*.md

    BATCH_SIZE=8
    PIDS=()
    CHUNK_ID=0
    SUCCESSFUL_CHUNKS=0
    FAILED_CHUNKS=0
    BATCH_RATE_LIMITED=false
    unset CHUNK_ID_MAP 2>/dev/null || true
    declare -A CHUNK_ID_MAP

    for dart_file in "${DART_FILES[@]}"; do
      # If rate limited, wait before launching more
      if $BATCH_RATE_LIMITED; then
        log "  ⏰ Rate limit detected in previous batch. Checking before continuing..."
        # Find any rate-limited output from the last batch
        for rl_check in "$ITER_LOG_DIR"/audit_c${AUDIT_CYCLE}_*.log.jsonl; do
          if [[ -f "$rl_check" ]] && check_and_wait_rate_limit "$rl_check"; then
            break
          fi
        done
        BATCH_RATE_LIMITED=false
      fi

      dart_basename=$(basename "$dart_file" .dart)
      CHUNK_FILE="$ITER_LOG_DIR/audit_c${AUDIT_CYCLE}_${dart_basename}.log"

      # Tier routing: skip tiny files, use haiku for simple, sonnet for complex
      tier=$(get_file_tier "$dart_file")
      if [[ "$tier" == "skip" ]]; then
        log "    [$((CHUNK_ID + 1))/$NUM_FILES] $dart_basename.dart — SKIP (tiny/no callbacks)"
        CHUNK_ID=$((CHUNK_ID + 1))
        SUCCESSFUL_CHUNKS=$((SUCCESSFUL_CHUNKS + 1))
        continue
      fi

      model="claude-sonnet-4-6"
      [[ "$tier" == "haiku" ]] && model="claude-haiku-4-5-20251001"

      CHUNK_ID_MAP["$dart_basename"]=$CHUNK_ID
      PROMPT="$(build_audit_prompt "$dart_file" "$CHUNK_ID")"
      log "    [$((CHUNK_ID + 1))/$NUM_FILES] $dart_basename.dart ($(wc -l < "$dart_file") lines, tier=$tier)"

      (
        set +e
        invoke_claude "$PROMPT" "$CHUNK_FILE" "AUDIT-${dart_basename}" "$model"
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

        # Check if any session in this batch was rate limited
        if [[ $FAILED_CHUNKS -gt 0 ]]; then
          for rl_check in "$ITER_LOG_DIR"/audit_c${AUDIT_CYCLE}_*.log.jsonl; do
            if [[ -f "$rl_check" ]] && grep -q "hit your limit\|rate.limit\|Rate limit" "$rl_check" 2>/dev/null; then
              BATCH_RATE_LIMITED=true
              log "  ⚠️  Rate limit detected in batch. Will wait before next batch."
              break
            fi
          done
        fi
      fi
    done

    for pid in "${PIDS[@]}"; do
      if wait "$pid" 2>/dev/null; then
        SUCCESSFUL_CHUNKS=$((SUCCESSFUL_CHUNKS + 1))
      else
        FAILED_CHUNKS=$((FAILED_CHUNKS + 1))
      fi
    done

    # Only update fingerprints for files whose audit SUCCEEDED (not rate-limited/failed)
    for dart_file in "${DART_FILES[@]}"; do
      db=$(basename "$dart_file" .dart)
      chunk_out="$PROJECT_ROOT/checklist/audit_chunk_${CHUNK_ID_MAP[$db]:-999}.md"
      chunk_jsonl="$ITER_LOG_DIR/audit_c${AUDIT_CYCLE}_${db}.log.jsonl"
      # Only fingerprint if output exists AND was not rate-limited
      if [[ -f "$chunk_out" ]] && ! grep -q "hit your limit\|rate.limit\|Rate limit" "$chunk_jsonl" 2>/dev/null; then
        update_fingerprint "$dart_file"
      fi
    done

    log ""
    log "  📊 Layer 1: $SUCCESSFUL_CHUNKS/$NUM_FILES audited, $FAILED_CHUNKS failed"
    [[ $SKIPPED_UNCHANGED -gt 0 ]] && log "  ⏭️  $SKIPPED_UNCHANGED files skipped (unchanged since last audit)"
    [[ $FAILED_CHUNKS -gt 0 ]] && log "  ⚠️  $FAILED_CHUNKS files failed (partial-failure — continuing)"

    else
      # ── Phase B: CLEANUP SWEEP (placeholders, stubs, perf) ──
      echo ""
      log "╔══════════════════════════════════════════════════════════════╗"
      log "║  🧹 AUDIT CYCLE $AUDIT_CYCLE / $MAX_AUDIT_CYCLES — Phase B: Cleanup Sweep       "
      log "║  📊 Hunting placeholders, broken wiring, performance issues  "
      log "║  🏷️  Git tag: audit-pre-cycle-${AUDIT_CYCLE}b                          "
      log "╚══════════════════════════════════════════════════════════════╝"
      update_progress "audit" "cycle $AUDIT_CYCLE phase B" "cleanup sweep"

      git -C "$PROJECT_ROOT" tag -f "audit-pre-cycle-${AUDIT_CYCLE}b" HEAD 2>/dev/null || true

      mapfile -t DART_FILES < <(find "$PROJECT_ROOT/dart/lib" -name "*.dart" -type f 2>/dev/null | grep -v '/proto/' | sort)
      NUM_FILES=${#DART_FILES[@]}
      log "  📂 Sweeping ALL $NUM_FILES files for placeholders & perf issues"

      rm -f "$PROJECT_ROOT/checklist/audit_chunk_"*.md

      BATCH_SIZE=8
      PIDS=()
      CHUNK_ID=0
      SUCCESSFUL_CHUNKS=0
      FAILED_CHUNKS=0
      BATCH_RATE_LIMITED=false

      for dart_file in "${DART_FILES[@]}"; do
        if $BATCH_RATE_LIMITED; then
          log "  ⏰ Rate limit detected. Checking before continuing..."
          for rl_check in "$ITER_LOG_DIR"/cleanup_c${AUDIT_CYCLE}_*.log.jsonl; do
            if [[ -f "$rl_check" ]] && check_and_wait_rate_limit "$rl_check"; then
              break
            fi
          done
          BATCH_RATE_LIMITED=false
        fi

        dart_basename=$(basename "$dart_file" .dart)
        CHUNK_FILE="$ITER_LOG_DIR/cleanup_c${AUDIT_CYCLE}_${dart_basename}.log"

        tier=$(get_file_tier "$dart_file")
        if [[ "$tier" == "skip" ]]; then
          log "    [$((CHUNK_ID + 1))/$NUM_FILES] $dart_basename.dart — SKIP (tiny)"
          CHUNK_ID=$((CHUNK_ID + 1))
          SUCCESSFUL_CHUNKS=$((SUCCESSFUL_CHUNKS + 1))
          continue
        fi
        model="claude-sonnet-4-6"
        [[ "$tier" == "haiku" ]] && model="claude-haiku-4-5-20251001"

        PROMPT="$(build_cleanup_prompt "$dart_file" "$CHUNK_ID")"
        log "    [$((CHUNK_ID + 1))/$NUM_FILES] $dart_basename.dart (tier=$tier)"

        (
          set +e
          invoke_claude "$PROMPT" "$CHUNK_FILE" "CLEANUP-${dart_basename}" "$model"
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
          if [[ $FAILED_CHUNKS -gt 0 ]]; then
            for rl_check in "$ITER_LOG_DIR"/cleanup_c${AUDIT_CYCLE}_*.log.jsonl; do
              if [[ -f "$rl_check" ]] && grep -q "hit your limit\|rate.limit\|Rate limit" "$rl_check" 2>/dev/null; then
                BATCH_RATE_LIMITED=true
                log "  ⚠️  Rate limit detected in batch. Will wait before next batch."
                break
              fi
            done
          fi
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
    update_progress "audit" "cycle $AUDIT_CYCLE" "merging findings"
    phase_title="Code Comparison (Dart vs AyuGram)"
    [[ "$AUDIT_PHASE" == "cleanup" ]] && phase_title="Cleanup Sweep (placeholders, stubs, perf)"
    {
      echo "# GUI Audit — Cycle $AUDIT_CYCLE Phase ${AUDIT_PHASE^} ($(date '+%Y-%m-%d %H:%M'))"
      echo ""
      echo "## $phase_title"
      echo ""
      for f in "$PROJECT_ROOT/checklist/audit_chunk_"*.md; do
        [[ -f "$f" ]] || continue
        if grep -qi "no issues found" "$f" && [[ $(wc -l < "$f") -le 2 ]]; then
          continue
        fi
        cat "$f"
        echo ""
      done
    } > "$PROJECT_ROOT/checklist/gui.md"

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

    # ── Handle findings ────────────────────────────────────────
    if [[ "$FINDINGS" -eq 0 ]]; then
      if [[ "$AUDIT_PHASE" == "ayugram" ]]; then
        # AyuGram audit found nothing → move to cleanup sweep
        log "  AyuGram audit clean. Moving to Phase B: cleanup sweep..."
        AUDIT_PHASE="cleanup"
        continue
      else
        # Cleanup sweep also found nothing → check convergence
        CONVERGE_COUNT=$((CONVERGE_COUNT + 1))
        log "  Both phases clean. Convergence: $CONVERGE_COUNT/$CONVERGE_THRESHOLD"
        if [[ $CONVERGE_COUNT -ge $CONVERGE_THRESHOLD ]]; then
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
        continue
      fi
    fi

    # ── Divergence detection (per-phase comparison) ─────────
    if [[ "$AUDIT_PHASE" == "ayugram" ]]; then
      LAST_PHASE_FINDINGS=$LAST_AYUGRAM_FINDINGS
    else
      LAST_PHASE_FINDINGS=$LAST_CLEANUP_FINDINGS
    fi
    if [[ "$FINDINGS" -gt "$LAST_PHASE_FINDINGS" && $AUDIT_CYCLE -gt 1 ]]; then
      DIVERGE_COUNT=$((DIVERGE_COUNT + 1))
      log "  ⚠️  DIVERGENCE: findings $LAST_PHASE_FINDINGS → $FINDINGS (count: $DIVERGE_COUNT)"
      if [[ $DIVERGE_COUNT -ge 2 ]]; then
        rollback_tag="audit-pre-cycle-$((AUDIT_CYCLE - 2))a"
        if git -C "$PROJECT_ROOT" rev-parse "$rollback_tag" &>/dev/null; then
          log "  DIVERGENCE confirmed. Resetting to $rollback_tag."
          git -C "$PROJECT_ROOT" reset --hard "$rollback_tag"
          wait_for_internet
          git -C "$PROJECT_ROOT" push origin main --force-with-lease 2>/dev/null || true
        else
          log "  DIVERGENCE confirmed but rollback tag $rollback_tag not found."
        fi
        notify "Ralph v3: DIVERGENCE. Rolled back."
        break
      fi
    else
      DIVERGE_COUNT=0
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

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)" 2>/dev/null || true
    wait_for_internet
    if ! git -C "$PROJECT_ROOT" push origin main 2>/dev/null; then
      log "  ⚠️  git push failed — commits are local only."
    fi
    LAST_COMMIT_HASH="$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo "none")"

    # After fixing this phase's items, move to next phase
    if [[ "$AUDIT_PHASE" == "ayugram" ]]; then
      log "  AyuGram checklist ($FINDINGS items) committed. Fixing, then cleanup sweep."
      AUDIT_PHASE="cleanup"
    else
      log "  Cleanup checklist ($FINDINGS items) committed. Fixing, then next AyuGram cycle."
      AUDIT_PHASE="ayugram"
    fi
  fi
done

# ─── Final report ────────────────────────────────────────────────
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
