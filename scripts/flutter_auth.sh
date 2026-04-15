#!/usr/bin/env bash
# Flutter Auth CLI — automate auth flow in a running uniclient app.
#
# The app polls /tmp/uniclient_auth_cmd.json every second when auth needs input.
# This script writes commands to that file and monitors progress via app logs.
#
# Usage:
#   ./scripts/flutter_auth.sh status              — show current auth state from logs
#   ./scripts/flutter_auth.sh choose <method>      — pick auth method (phone, bot_token, qr)
#   ./scripts/flutter_auth.sh submit <value>       — enter phone/OTP/password/token
#   ./scripts/flutter_auth.sh cancel               — cancel auth flow
#   ./scripts/flutter_auth.sh otp-wait             — wait for OTP file (auth/otp_code.txt) and submit
#   ./scripts/flutter_auth.sh auto <method> [phone] — full auto: choose method, enter phone, wait for OTP
#
# Examples:
#   ./scripts/flutter_auth.sh choose phone         — start phone auth
#   ./scripts/flutter_auth.sh submit "+1234567890" — enter phone number
#   ./scripts/flutter_auth.sh otp-wait             — polls auth/otp_code.txt, submits when found
#   ./scripts/flutter_auth.sh submit "my2fapass"   — enter 2FA password

set -euo pipefail

CMD_FILE="/tmp/uniclient_auth_cmd.json"
APP_CMD_FILE="/tmp/uniclient_cmd.json"
OTP_FILE="${OTP_FILE:-auth/otp_code.txt}"
LOG_FILE="${UNICLIENT_LOG:-/tmp/uniclient_log.txt}"

send_cmd() {
  local action="$1"
  local value="${2:-}"
  if [[ -n "$value" ]]; then
    printf '{"action":"%s","value":"%s"}\n' "$action" "$value" > "$CMD_FILE"
  else
    printf '{"action":"%s"}\n' "$action" > "$CMD_FILE"
  fi
  echo "[auth-cli] Sent: action=$action value=${value:-(none)}"
}

wait_for_state() {
  local target="$1"
  local timeout="${2:-30}"
  local start=$SECONDS
  while (( SECONDS - start < timeout )); do
    if [[ -f "$LOG_FILE" ]]; then
      local last_state=$(grep "AUTH:.*state=" "$LOG_FILE" | tail -1 | grep -oP "state=\K\w+" || true)
      if [[ "$last_state" == "$target" ]]; then
        echo "[auth-cli] Reached state: $target"
        return 0
      fi
    fi
    sleep 1
  done
  echo "[auth-cli] Timeout waiting for state: $target" >&2
  return 1
}

case "${1:-help}" in
  add)
    platform="${2:?Usage: $0 add <platform>}"
    printf '{"action":"add","platform":"%s"}\n' "$platform" > "$APP_CMD_FILE"
    echo "[auth-cli] Sent add-account: platform=$platform (auth dialog will open)"
    sleep 2
    ;;

  status)
    if [[ -f "$LOG_FILE" ]]; then
      echo "=== Recent auth log entries ==="
      grep "AUTH:" "$LOG_FILE" | tail -20
    else
      echo "No log file found at $LOG_FILE"
    fi
    ;;

  choose)
    send_cmd "choose" "${2:?Usage: $0 choose <method>}"
    ;;

  submit)
    send_cmd "submit" "${2:?Usage: $0 submit <value>}"
    ;;

  cancel)
    send_cmd "cancel"
    ;;

  otp-wait)
    echo "[auth-cli] Waiting for OTP in $OTP_FILE ..."
    rm -f "$OTP_FILE"
    timeout="${2:-120}"
    start=$SECONDS
    while (( SECONDS - start < timeout )); do
      if [[ -f "$OTP_FILE" ]]; then
        otp=$(cat "$OTP_FILE" | tr -d '[:space:]')
        if [[ -n "$otp" ]]; then
          echo "[auth-cli] Got OTP: $otp"
          rm -f "$OTP_FILE"
          send_cmd "submit" "$otp"
          exit 0
        fi
      fi
      sleep 1
    done
    echo "[auth-cli] Timeout waiting for OTP ($timeout seconds)" >&2
    exit 1
    ;;

  auto)
    method="${2:-phone}"
    phone="${3:-}"

    echo "[auth-cli] === Auto auth: method=$method ==="

    # Step 1: Wait for choose state
    echo "[auth-cli] Waiting for auth choose state..."
    wait_for_state "choose" 15

    # Step 2: Choose method
    send_cmd "choose" "$method"
    sleep 2

    # Step 3: If phone method, submit phone number
    if [[ "$method" == "phone" && -n "$phone" ]]; then
      echo "[auth-cli] Waiting for input state..."
      wait_for_state "input" 10 || wait_for_state "otp" 5
      # Check if we went straight to OTP (session reuse) or need phone
      last_state=$(grep "AUTH:.*state=" "$LOG_FILE" | tail -1 | grep -oP "state=\K\w+" || true)
      if [[ "$last_state" == "input" ]]; then
        send_cmd "submit" "$phone"
        sleep 2
      fi
    fi

    # Step 4: Wait for OTP if phone auth
    if [[ "$method" == "phone" ]]; then
      last_state=$(grep "AUTH:.*state=" "$LOG_FILE" | tail -1 | grep -oP "state=\K\w+" || true)
      if [[ "$last_state" == "otp" ]]; then
        echo "[auth-cli] OTP required. Waiting for $OTP_FILE ..."
        rm -f "$OTP_FILE"
        start=$SECONDS
        while (( SECONDS - start < 120 )); do
          if [[ -f "$OTP_FILE" ]]; then
            otp=$(cat "$OTP_FILE" | tr -d '[:space:]')
            if [[ -n "$otp" ]]; then
              echo "[auth-cli] Got OTP: $otp"
              rm -f "$OTP_FILE"
              send_cmd "submit" "$otp"
              break
            fi
          fi
          sleep 1
        done
      fi

      # Step 5: Check for 2FA
      sleep 2
      last_state=$(grep "AUTH:.*state=" "$LOG_FILE" | tail -1 | grep -oP "state=\K\w+" || true)
      if [[ "$last_state" == "2fa" ]]; then
        echo "[auth-cli] 2FA required. Waiting for password in $OTP_FILE ..."
        rm -f "$OTP_FILE"
        start=$SECONDS
        while (( SECONDS - start < 120 )); do
          if [[ -f "$OTP_FILE" ]]; then
            pass=$(cat "$OTP_FILE" | tr -d '\n')
            if [[ -n "$pass" ]]; then
              echo "[auth-cli] Got 2FA password"
              rm -f "$OTP_FILE"
              send_cmd "submit" "$pass"
              break
            fi
          fi
          sleep 1
        done
      fi
    fi

    # Step 6: Wait for ready
    sleep 2
    last_state=$(grep "AUTH:.*state=" "$LOG_FILE" | tail -1 | grep -oP "state=\K\w+" || true)
    if [[ "$last_state" == "ready" ]]; then
      echo "[auth-cli] === Auth complete! ==="
      # Auto-close the dialog by submitting empty (the ready state has a Close button)
      sleep 1
    else
      echo "[auth-cli] Final state: $last_state (expected: ready)"
    fi
    ;;

  *)
    echo "Usage: $0 {status|choose|submit|cancel|otp-wait|auto} [args...]"
    echo ""
    echo "Commands:"
    echo "  status              — show auth state from logs"
    echo "  choose <method>     — pick auth method (phone, bot_token, qr)"
    echo "  submit <value>      — enter phone/OTP/password/token"
    echo "  cancel              — cancel auth flow"
    echo "  otp-wait            — wait for OTP file and auto-submit"
    echo "  auto <method> [phone] — full automatic auth flow"
    echo ""
    echo "Environment:"
    echo "  UNICLIENT_LOG  — app log file (default: /tmp/uniclient_log.txt)"
    echo "  OTP_FILE       — OTP input file (default: auth/otp_code.txt)"
    exit 1
    ;;
esac
