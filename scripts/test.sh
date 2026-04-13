#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GO_DIR="$PROJECT_DIR/go"

cd "$GO_DIR"

echo "=== Unit Tests (no credentials needed) ==="
go test ./utils/... -v -timeout 120s
go test ./cores/... -run "TestTelegramCore" -v -timeout 30s

echo ""
echo "=== Integration Tests ==="
if [ -z "${TG_BOT_TOKEN:-}" ]; then
    echo "Skipping Telegram integration tests."
    echo "To run them, set these environment variables:"
    echo "  TG_BOT_TOKEN     - Bot token from @BotFather"
    echo "  TG_API_ID        - API ID from my.telegram.org"
    echo "  TG_API_HASH      - API hash from my.telegram.org"
    echo "  TG_TEST_CHAT_ID  - Chat ID to send test messages to"
    echo ""
    echo "Example:"
    echo "  TG_BOT_TOKEN=123:ABC TG_API_ID=2040 TG_API_HASH=abc TG_TEST_CHAT_ID=12345 bash scripts/test.sh"
else
    echo "Running Telegram bot integration tests..."
    go test ./cores/... -run "TestIntegration_TelegramBot" -v -timeout 60s
fi

if [ -z "${BALE_BOT_TOKEN:-}" ]; then
    echo "Skipping Bale integration tests (set BALE_BOT_TOKEN, BALE_TEST_CHAT_ID)."
else
    echo "Running Bale integration tests..."
    go test ./cores/... -run "TestIntegration_Bale" -v -timeout 60s
fi

if [ -z "${RUBIKA_BOT_TOKEN:-}" ]; then
    echo "Skipping Rubika integration tests (set RUBIKA_BOT_TOKEN, RUBIKA_TEST_CHAT_ID)."
else
    echo "Running Rubika integration tests..."
    go test ./cores/... -run "TestIntegration_Rubika" -v -timeout 60s
fi

echo ""
echo "Done."
