package gui

// Bot keyboard tests (slice 127): inline-keyboard + reply-keyboard parsing
// from message Extra, action classification, reply-keyboard panel
// visibility over the loaded window, and renderable-button gating.

import (
	"testing"

	"uniclient/engine"
)

func inlineKbdRaw(rows string) []byte {
	return []byte(`{"extra":{"inline_keyboard":` + rows + `}}`)
}

func replyKbdRaw(rows, placeholder string, singleUse bool) []byte {
	su := "false"
	if singleUse {
		su = "true"
	}
	return []byte(`{"extra":{"reply_keyboard":{"rows":` + rows + `,"resize":true,"single_use":` + su + `,"persistent":false,"placeholder":"` + placeholder + `"}}}`)
}

func TestParseInlineKeyboard(t *testing.T) {
	m := &engine.CachedMessage{ContentRaw: inlineKbdRaw(`[
                [{"text":"Tap me","type":"callback","data":"payload-1"},
                 {"text":"Open site","type":"url","url":"https://example.com"}],
                [{"text":"Copy code","type":"copy","copy_text":"12345"},
                 {"text":"Forward","type":"switch_inline","query":"gif cats","same_peer":true}],
                [{"text":"Play","type":"game"},
                 {"text":"Login","type":"url_auth","url":"https://t.me","button_id":7},
                 {"text":"App","type":"web_view","url":"https://app.example.com"},
                 {"text":"Checkout","type":"buy"}]
        ]`)}
	kbd := parseInlineKeyboard(m)
	if kbd == nil {
		t.Fatal("parseInlineKeyboard = nil for a well-formed markup")
	}
	if len(kbd.Rows) != 3 {
		t.Fatalf("rows = %d, want 3", len(kbd.Rows))
	}
	want := [][]botKbdBtn{{
		{Text: "Tap me", Type: "callback", Data: "payload-1"},
		{Text: "Open site", Type: "url", URL: "https://example.com"},
	}, {
		{Text: "Copy code", Type: "copy", CopyText: "12345"},
		{Text: "Forward", Type: "switch_inline", Query: "gif cats", SamePeer: true},
	}, {
		{Text: "Play", Type: "game"},
		{Text: "Login", Type: "url_auth", URL: "https://t.me", ButtonID: 7},
		{Text: "App", Type: "web_view", URL: "https://app.example.com"},
		{Text: "Checkout", Type: "buy"},
	}}
	for r := range want {
		if len(kbd.Rows[r]) != len(want[r]) {
			t.Fatalf("row %d: %d buttons, want %d", r, len(kbd.Rows[r]), len(want[r]))
		}
		for c := range want[r] {
			got, exp := kbd.Rows[r][c], want[r][c]
			if got != exp {
				t.Errorf("row %d btn %d = %+v, want %+v", r, c, got, exp)
			}
		}
	}
}

func TestParseInlineKeyboardNone(t *testing.T) {
	if k := parseInlineKeyboard(nil); k != nil {
		t.Error("nil message parsed a keyboard")
	}
	if k := parseInlineKeyboard(&engine.CachedMessage{}); k != nil {
		t.Error("empty message parsed a keyboard")
	}
	if k := parseInlineKeyboard(&engine.CachedMessage{ContentRaw: []byte(`{"extra":{}}`)}); k != nil {
		t.Error("extra without inline_keyboard parsed a keyboard")
	}
	if k := parseInlineKeyboard(&engine.CachedMessage{ContentRaw: []byte(`{bad json`)}); k != nil {
		t.Error("malformed JSON parsed a keyboard")
	}
	if k := parseInlineKeyboard(&engine.CachedMessage{ContentRaw: inlineKbdRaw(`[]`)}); k != nil {
		t.Error("empty rows parsed a keyboard")
	}
	// A row of empty buttons is not a usable keyboard either.
	if k := parseInlineKeyboard(&engine.CachedMessage{ContentRaw: inlineKbdRaw(`[[]]`)}); k != nil {
		t.Error("row without buttons parsed a keyboard")
	}
}

func TestParseReplyKeyboard(t *testing.T) {
	m := &engine.CachedMessage{ContentRaw: replyKbdRaw(`[
                [{"text":"Yes","type":"text"},{"text":"No","type":"text"}],
                [{"text":"Share phone","type":"request_phone"},{"text":"Where am I","type":"request_location"}]
        ]`, "Choose…", true)}
	kbd, singleUse, placeholder := parseReplyKeyboard(m)
	if kbd == nil {
		t.Fatal("parseReplyKeyboard = nil for a well-formed markup")
	}
	if !singleUse {
		t.Error("single_use lost in parsing")
	}
	if placeholder != "Choose…" {
		t.Errorf("placeholder = %q, want %q", placeholder, "Choose…")
	}
	if len(kbd.Rows) != 2 || len(kbd.Rows[0]) != 2 || len(kbd.Rows[1]) != 2 {
		t.Fatalf("rows shape = %+v", kbd.Rows)
	}
	if kbd.Rows[0][0].Text != "Yes" || kbd.Rows[0][0].Type != "text" {
		t.Errorf("first button = %+v", kbd.Rows[0][0])
	}
	if kbd.Rows[1][0].Type != "request_phone" {
		t.Errorf("request_phone button type = %q", kbd.Rows[1][0].Type)
	}
}

func TestParseReplyKeyboardNone(t *testing.T) {
	if k, _, _ := parseReplyKeyboard(nil); k != nil {
		t.Error("nil message parsed a reply keyboard")
	}
	if k, _, _ := parseReplyKeyboard(&engine.CachedMessage{ContentRaw: []byte(`{"extra":{}}`)}); k != nil {
		t.Error("extra without reply_keyboard parsed a keyboard")
	}
	if k, _, _ := parseReplyKeyboard(&engine.CachedMessage{ContentRaw: replyKbdRaw(`[]`, "", false)}); k != nil {
		t.Error("empty rows parsed a reply keyboard")
	}
}

func TestReplyKbdActive(t *testing.T) {
	if k := replyKbdActive(nil); k != nil {
		t.Error("no messages → keyboard")
	}
	msgs := []engine.CachedMessage{
		{MsgID: "1", ContentRaw: replyKbdRaw(`[[{"text":"A","type":"text"}]]`, "", false)},
		{MsgID: "2", ContentRaw: nil}, // plain message: keyboard persists
	}
	if k := replyKbdActive(msgs); k == nil || len(k.Rows) != 1 || k.Rows[0][0].Text != "A" {
		t.Fatalf("latest keyboard lost: %+v", k)
	}
	// A keyboard_hide message AFTER the keyboard clears it (tdesktop: bots
	// send reply_keyboard_hide to dismiss the panel).
	msgs = append(msgs, engine.CachedMessage{MsgID: "3", ContentRaw: []byte(`{"extra":{"keyboard_hide":true}}`)})
	if k := replyKbdActive(msgs); k != nil {
		t.Fatalf("keyboard_hide after a keyboard did not clear it: %+v", k)
	}
	// A newer keyboard after the hide wins again.
	msgs = append(msgs, engine.CachedMessage{MsgID: "4", ContentRaw: replyKbdRaw(`[[{"text":"B","type":"text"}]]`, "", false)})
	if k := replyKbdActive(msgs); k == nil || k.Rows[0][0].Text != "B" {
		t.Fatalf("newer keyboard after hide not active: %+v", k)
	}
}

func TestBotKbdActionFor(t *testing.T) {
	cases := []struct {
		btn  botKbdBtn
		kind string
	}{
		{botKbdBtn{Type: "callback", Data: "d1"}, "callback"},
		{botKbdBtn{Type: "game"}, "game"},
		{botKbdBtn{Type: "url", URL: "https://x"}, "url"},
		{botKbdBtn{Type: "url_auth", URL: "https://x"}, "url"},
		{botKbdBtn{Type: "web_view", URL: "https://x"}, "url"},
		{botKbdBtn{Type: "simple_web_view", URL: "https://x"}, "url"},
		{botKbdBtn{Type: "copy", CopyText: "abc"}, "copy"},
		{botKbdBtn{Type: "switch_inline", Query: "q", SamePeer: true}, "insert"},
		{botKbdBtn{Type: "switch_inline", Query: "q"}, "clipboard"},
		{botKbdBtn{Type: "buy"}, "unsupported"},
		{botKbdBtn{Type: ""}, "callback"}, // core maps unknown → callback
	}
	for _, c := range cases {
		if got := botKbdActionFor(c.btn).Kind; got != c.kind {
			t.Errorf("botKbdActionFor(%+v).Kind = %q, want %q", c.btn, got, c.kind)
		}
	}
	// Payload pass-through.
	if p := botKbdActionFor(botKbdBtn{Type: "copy", CopyText: "42"}); p.Kind != "copy" || p.Payload != "42" {
		t.Errorf("copy action = %+v", p)
	}
	if p := botKbdActionFor(botKbdBtn{Type: "callback", Data: "d"}); p.Kind != "callback" || p.Data != "d" {
		t.Errorf("callback action = %+v", p)
	}
	if p := botKbdActionFor(botKbdBtn{Type: "switch_inline", Query: "gif cats", SamePeer: true}); p.Kind != "insert" || p.Payload != "gif cats" {
		t.Errorf("insert action = %+v", p)
	}
}

func TestReplyKbdRenderable(t *testing.T) {
	for _, ty := range []string{"text", "web_view", "simple_web_view"} {
		if !replyKbdRenderable(botKbdBtn{Type: ty, Text: "Go"}) {
			t.Errorf("replyKbdRenderable(%q) = false, want true", ty)
		}
	}
	for _, ty := range []string{"request_phone", "request_location", "request_poll", "request_peer", "", "callback"} {
		if replyKbdRenderable(botKbdBtn{Type: ty, Text: "Go"}) {
			t.Errorf("replyKbdRenderable(%q) = true, want false", ty)
		}
	}
	// A button without a label cannot render at all.
	if replyKbdRenderable(botKbdBtn{Type: "text"}) {
		t.Error("label-less text button rendered")
	}
}

func TestBotKbdHint(t *testing.T) {
	if h := botKbdHint("", "Write a message…"); h != "Write a message…" {
		t.Errorf("empty placeholder hint = %q", h)
	}
	if h := botKbdHint("Choose…", "Write a message…"); h != "Choose…" {
		t.Errorf("placeholder hint = %q, want %q", h, "Choose…")
	}
}
