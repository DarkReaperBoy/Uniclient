package tests

import (
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/dialogs/render"
	chatrender "uniclient/ui/history/render"
	"uniclient/ui/material"
)

const accountListWire = `{"type":"account_list","timestamp_ms":1731014400000,"data":[` +
	`{"id":"xm_01","platform":"xmpp","display_name":"Pals","phone":"","username":"pals","avatar_path":"","sort_order":0,"conn_state":0,"is_verified":false,"is_premium":false},` +
	`{"id":"tele_02","platform":"telegram","display_name":"Work","phone":"","username":"work","avatar_path":"","sort_order":1,"conn_state":1,"is_verified":false,"is_premium":false}]}`

const accountListEmptyWire = `{"type":"account_list","timestamp_ms":1731014400000,"data":[]}`

const accountListBadDataWire = `{"type":"account_list","timestamp_ms":1731014400000,"data":"not-an-array"}`

const unknownEventWire = `{"type":"msg_received","account_id":"tele_02","timestamp_ms":1731014400000,"data":{"chat_id":"10"}}`

func bridgeModel(t *testing.T, w, h int) Model {
	t.Helper()
	m, _ := Update(InitialModel(), Resized{Width: w, Height: h})
	return m
}

func applyEngineEvent(t *testing.T, m Model, wire string) Model {
	t.Helper()
	next, cmd := Update(m, EngineEventMsg{Data: []byte(wire)})
	if cmd != nil {
		t.Fatalf("EngineEventMsg produced a cmd, want nil")
	}
	return next
}

func TestEngineEventAccountListDecodes(t *testing.T) {
	m := applyEngineEvent(t, bridgeModel(t, 1440, 900), accountListWire)
	if len(m.Accounts) != 2 {
		t.Fatalf("Accounts len = %d, want 2", len(m.Accounts))
	}
	first, second := m.Accounts[0], m.Accounts[1]
	if first.ID != "xm_01" || second.ID != "tele_02" {
		t.Fatalf("Accounts not sorted by sort_order: %s then %s", first.ID, second.ID)
	}
	if second.Platform != "telegram" || second.DisplayName != "Work" || second.ConnState != 1 {
		t.Fatalf("second account decoded wrong: %+v", second)
	}
}

func TestEngineEventAccountListEmpty(t *testing.T) {
	m := applyEngineEvent(t, bridgeModel(t, 1440, 900), accountListEmptyWire)
	if len(m.Accounts) != 0 {
		t.Fatalf("Accounts len = %d, want 0", len(m.Accounts))
	}
}

func TestEngineEventUnknownTypeIgnored(t *testing.T) {
	m := applyEngineEvent(t, bridgeModel(t, 1440, 900), accountListWire)
	m = applyEngineEvent(t, m, unknownEventWire)
	if len(m.Accounts) != 2 {
		t.Fatalf("unknown event type mutated Accounts: len = %d", len(m.Accounts))
	}
}

func TestEngineEventMalformedIgnored(t *testing.T) {
	m := applyEngineEvent(t, bridgeModel(t, 1440, 900), accountListWire)
	next := applyEngineEvent(t, m, "{not json")
	if len(next.Accounts) != len(m.Accounts) {
		t.Fatalf("malformed event mutated Accounts")
	}
}

func TestEngineEventAccountListBadDataIgnored(t *testing.T) {
	m := applyEngineEvent(t, bridgeModel(t, 1440, 900), accountListWire)
	next := applyEngineEvent(t, m, accountListBadDataWire)
	if len(next.Accounts) != len(m.Accounts) {
		t.Fatalf("bad account_list data mutated Accounts")
	}
}

func TestZeroAccountChatEmptyPrompt(t *testing.T) {
	scene := View(bridgeModel(t, 1440, 900))
	if scene.Chat.EmptyText != AddAccountPrompt {
		t.Fatalf("two-pane zero-account Chat.EmptyText = %q, want %q", scene.Chat.EmptyText, AddAccountPrompt)
	}
	if scene.Dialogs.EmptyText != "" {
		t.Fatalf("two-pane zero-account Dialogs.EmptyText = %q, want empty", scene.Dialogs.EmptyText)
	}
}

func TestZeroAccountSinglePanePromptInDialogs(t *testing.T) {
	scene := View(bridgeModel(t, 390, 844))
	if scene.Dialogs.EmptyText != AddAccountPrompt {
		t.Fatalf("single-pane zero-account Dialogs.EmptyText = %q, want %q", scene.Dialogs.EmptyText, AddAccountPrompt)
	}
	if scene.Chat.EmptyText != "" {
		t.Fatalf("single-pane zero-account Chat.EmptyText = %q, want empty", scene.Chat.EmptyText)
	}
}

func TestAccountPresentNoEmptyPrompt(t *testing.T) {
	m := applyEngineEvent(t, bridgeModel(t, 1440, 900), accountListWire)
	scene := View(m)
	if scene.Chat.EmptyText != "" || scene.Dialogs.EmptyText != "" {
		t.Fatalf("accounts present but prompt shown: chat %q dialogs %q", scene.Chat.EmptyText, scene.Dialogs.EmptyText)
	}
}

func TestInitialModelAccountsUnknown(t *testing.T) {
	if InitialModel().Accounts != nil {
		t.Fatalf("InitialModel Accounts = %v, want nil until the pump delivers", InitialModel().Accounts)
	}
}

func TestPaintEmptyPromptWithoutPanic(t *testing.T) {
	p := render.NewPainter()
	cp := chatrender.NewChatPainter()
	gtx := renderContext()
	sch := material.SchemeFor(material.Light)

	double := View(bridgeModel(t, 1440, 900))
	p.PaintPane(gtx, double.Dialogs, sch)
	cp.PaintChatPane(gtx, double.Chat, sch)

	single := View(bridgeModel(t, 390, 844))
	p.PaintPane(gtx, single.Dialogs, sch)
	cp.PaintChatPane(gtx, single.Chat, sch)

	filled := View(applyEngineEvent(t, bridgeModel(t, 1440, 900), accountListWire))
	p.PaintPane(gtx, filled.Dialogs, sch)
	cp.PaintChatPane(gtx, filled.Chat, sch)
}

func TestZeroAccountSceneKeepsHeader(t *testing.T) {
	scene := View(bridgeModel(t, 1440, 900))
	if scene.Dialogs.Header.Field.W <= 0 {
		t.Fatalf("zero-account scene lost the header chrome")
	}
	if len(scene.Dialogs.Rows) != 0 {
		t.Fatalf("zero-account scene grew rows")
	}
}
