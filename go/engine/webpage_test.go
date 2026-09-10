package engine

import (
	"database/sql"
	"encoding/json"
	"testing"
)

// Webpage-preview send wiring (slice 117): the composer's preview-off toggle
// must survive the pending-queue round trip (payload JSON → executePending
// extra) so the core can call messages.sendMessage with no_webpage=true.
// GUI-side parsing/layout is pinned in gui/webpage_test.go.

func TestSendMessageNoWebpagePayload(t *testing.T) {
	e := newTestEngine(t)
	e.accounts = map[string]*Account{"tg": {ID: "tg", Core: plainStub{}}}

	if _, err := e.SendMessage("tg", "10", "see https://example.com", "", nil, false, 0, "", "", false, false, false, false, true); err != nil {
		t.Fatalf("send: %v", err)
	}

	var payload string
	var action string
	err := e.db.QueryRow(
		`SELECT action, payload FROM pending WHERE account_id = ? AND chat_id = ? ORDER BY created_at DESC LIMIT 1`,
		"tg", "10").Scan(&action, &payload)
	if err == sql.ErrNoRows {
		t.Fatal("no pending row written")
	}
	if err != nil {
		t.Fatal(err)
	}
	if action != ActionSend {
		t.Errorf("action = %q, want %q", action, ActionSend)
	}
	var p sendPayload
	if err := json.Unmarshal([]byte(payload), &p); err != nil {
		t.Fatalf("payload decode: %v", err)
	}
	if !p.NoWebpage {
		t.Error("NoWebpage lost in the pending payload")
	}

	// And the executePending extra construction preserves it.
	if extra := sendExtras(p); extra["no_webpage"] != true {
		t.Errorf("extra no_webpage = %v, want true", extra["no_webpage"])
	}
}

func TestSendMessageWebPageExtras(t *testing.T) {
	// The preview-on path (webPageUrl + force flags) still carries its
	// extras; nothing regressed.
	p := sendPayload{
		WebPageUrl:      "https://example.com",
		ForceLargeMedia: true,
		Silent:          true,
	}
	extra := sendExtras(p)
	if extra["web_page_url"] != "https://example.com" {
		t.Errorf("web_page_url = %v", extra["web_page_url"])
	}
	if extra["force_large_media"] != true {
		t.Errorf("force_large_media = %v", extra["force_large_media"])
	}
	if extra["silent"] != true {
		t.Errorf("silent = %v", extra["silent"])
	}

	// Default (preview on, no custom flags): no no_webpage extra.
	if _, has := sendExtras(sendPayload{})["no_webpage"]; has {
		t.Error("no_webpage extra must be absent by default")
	}
}
