package tests

import (
	"testing"
	"time"

	"gioui.org/io/key"

	. "uniclient/ui/app"
)

type submitPort struct {
	fail bool
	sent []string
}

func (p *submitPort) Messages(accountID, chatID string, limit int) ([]WireMessage, bool) {
	return nil, true
}

func (p *submitPort) Send(accountID, chatID, text string) bool {
	p.sent = append(p.sent, accountID+"|"+chatID+"|"+text)
	return !p.fail
}

func openComposedModel(t *testing.T, port ChatPort) Model {
	t.Helper()
	m := composeModel(t, 400, 600)
	m = m.WithPort(port)
	m.Open = ChatRef{Account: "a1", ID: "c1"}
	m.OpenValid = true
	return m
}

func TestChatComposeSubmittedSendsAndClears(t *testing.T) {
	port := &submitPort{}
	m := openComposedModel(t, port)
	m = typeString(t, m, "hello wire")
	if m.ChatCompose.Text != "hello wire" {
		t.Fatalf("setup: typed %q", m.ChatCompose.Text)
	}
	m, cmd := Update(m, ChatComposeSubmitted{Now: 2000})
	if m.ChatCompose.Text != "" || m.ChatCompose.Cursor != 0 || m.ChatCompose.Anchor != 0 {
		t.Fatalf("submit must clear the field: %q cursor %d anchor %d",
			m.ChatCompose.Text, m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	}
	if m.ChatCompose.PlaceholderShifted {
		t.Fatal("the placeholder must return after the submit clear")
	}
	if cmd == nil {
		t.Fatal("submit must return the send cmd")
	}
	res, ok := cmd().(ChatComposeSendRequested)
	if !ok {
		t.Fatalf("send cmd result = %T, want ChatComposeSendRequested", cmd())
	}
	if !res.OK || res.Text != "hello wire" {
		t.Fatalf("send result = %+v, want OK with the submitted text", res)
	}
	if len(port.sent) != 1 || port.sent[0] != "a1|c1|hello wire" {
		t.Fatalf("port sends = %v, want one a1|c1|hello wire", port.sent)
	}
	m, _ = Update(m, res)
	if m.ChatCompose.Text != "" {
		t.Fatalf("successful send must keep the field clear: %q", m.ChatCompose.Text)
	}
}

func TestChatComposeSubmitFailureRestoresField(t *testing.T) {
	port := &submitPort{fail: true}
	m := openComposedModel(t, port)
	m = typeString(t, m, "hello wire")
	m, cmd := Update(m, ChatComposeSubmitted{Now: 2000})
	if cmd == nil {
		t.Fatal("failed-destination send still starts as a cmd")
	}
	if m.ChatCompose.Text != "" {
		t.Fatalf("the field must clear optimistically: %q", m.ChatCompose.Text)
	}
	res := cmd().(ChatComposeSendRequested)
	if res.OK {
		t.Fatal("setup: port must report failure")
	}
	m, _ = Update(m, res)
	if m.ChatCompose.Text != "hello wire" || m.ChatCompose.Cursor != 10 || m.ChatCompose.Anchor != 10 {
		t.Fatalf("failed send must restore the field: %q cursor %d anchor %d",
			m.ChatCompose.Text, m.ChatCompose.Cursor, m.ChatCompose.Anchor)
	}
}

func TestChatComposeSubmittedGuards(t *testing.T) {
	port := &submitPort{}
	m := openComposedModel(t, port)
	m = typeString(t, m, "no chat")
	m.OpenValid = false
	m, cmd := Update(m, ChatComposeSubmitted{Now: 2000})
	if cmd != nil || m.ChatCompose.Text != "no chat" {
		t.Fatalf("no open chat: cmd %v text %q — no send, text preserved", cmd != nil, m.ChatCompose.Text)
	}

	m = openComposedModel(t, port)
	m = typeString(t, m, "blocked")
	m.ChatCompose.CanSend = false
	m, cmd = Update(m, ChatComposeSubmitted{Now: 2000})
	if cmd != nil || m.ChatCompose.Text != "blocked" {
		t.Fatalf("read-only chat: cmd %v text %q — no send, text preserved", cmd != nil, m.ChatCompose.Text)
	}

	m = openComposedModel(t, port)
	m = typeString(t, m, "no port")
	m = m.WithPort(nil)
	m, cmd = Update(m, ChatComposeSubmitted{Now: 2000})
	if cmd != nil || m.ChatCompose.Text != "no port" {
		t.Fatalf("portless: cmd %v text %q — no send, text preserved", cmd != nil, m.ChatCompose.Text)
	}

	m = openComposedModel(t, port)
	m, cmd = Update(m, ChatComposeSubmitted{Now: 2000})
	if cmd != nil {
		t.Fatal("empty field must not send")
	}
}

func TestChatOpenSetsCanSendFromRowType(t *testing.T) {
	nowMs := localMs(2026, time.November, 30, 15, 0)
	group := snapshotChats(nowMs, "20", "Group", "hi", 2, "bob", false, 0, 0, false)
	channel := snapshotChats(nowMs, "30", "Channel", "post", 3, "", false, 0, 0, false)
	for _, tc := range []struct {
		row  string
		want bool
	}{{group, true}, {channel, false}} {
		m := applyEngineEvent(t, feedsModel(t, 800, 600).WithPort(&submitPort{}), chatSnapshotWire("tele_02", tc.row, nowMs))
		if len(m.Dialogs.Rows) != 1 {
			t.Fatalf("rows = %d, want 1", len(m.Dialogs.Rows))
		}
		m, cmd := Update(m, DialogsPressed{X: 20, Y: 10, Now: 1})
		if cmd == nil {
			t.Fatal("open must start the load cmd")
		}
		loaded, ok := cmd().(ChatLoaded)
		if !ok {
			t.Fatalf("open cmd result = %T, want ChatLoaded", cmd())
		}
		m, _ = Update(m, loaded)
		if m.ChatCompose.CanSend != tc.want {
			t.Fatalf("CanSend = %v, want %v (channel rows are read-only)", m.ChatCompose.CanSend, tc.want)
		}
	}
}

func TestChatScrollKeysMoveHistory(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: preloadItems(6), MoreAbove: false})
	m, _ = Update(m, ChatMeasured{Heights: uniformHeights(6, 50)})
	m, _ = Update(m, ChatScrolled{DeltaY: 200})
	if m.ChatScroll.Top != 180 {
		t.Fatalf("setup: top = %d, want 180 (content 300 - viewport 120)", m.ChatScroll.Top)
	}
	m, _ = Update(m, ComposeKeyMsg(key.Event{Name: key.NameUpArrow, State: key.Press}, 1000))
	if m.ChatScroll.Top != 160 {
		t.Fatalf("up key = %d, want 160 (single step 20)", m.ChatScroll.Top)
	}
	m, _ = Update(m, ComposeKeyMsg(key.Event{Name: key.NamePageUp, State: key.Press}, 1001))
	if m.ChatScroll.Top != 0 {
		t.Fatalf("page up = %d, want 0 (200 clamped at the top)", m.ChatScroll.Top)
	}
	m, _ = Update(m, ComposeKeyMsg(key.Event{Name: key.NameUpArrow, State: key.Press}, 1002))
	if m.ChatScroll.Top != 0 {
		t.Fatalf("up at the top edge = %d, want clamp 0", m.ChatScroll.Top)
	}
	m, _ = Update(m, ComposeKeyMsg(key.Event{Name: key.NamePageDown, State: key.Press}, 1003))
	if m.ChatScroll.Top != 180 {
		t.Fatalf("page down = %d, want 180 (200 clamped at the bottom)", m.ChatScroll.Top)
	}
	m, _ = Update(m, ComposeKeyMsg(key.Event{Name: key.NameDownArrow, State: key.Press}, 1004))
	if m.ChatScroll.Top != 180 {
		t.Fatalf("down at the bottom edge = %d, want clamp 180", m.ChatScroll.Top)
	}
}
