package gui

import (
	"testing"

	"uniclient/engine"
)

// Selection-mode state machine (gui/select.go, slice 14).

func newSelApp() *App { return &App{} }

func TestSelectionToggle(t *testing.T) {
	a := newSelApp()
	a.startSelection("m1")
	if !a.selOn || !a.sel["m1"] || a.selectionCount() != 1 {
		t.Fatalf("start = on=%v sel=%v count=%d", a.selOn, a.sel, a.selectionCount())
	}
	// Toggle off/on.
	a.toggleMsgSel("m1")
	a.toggleMsgSel("m2")
	if a.sel["m1"] || !a.sel["m2"] || a.selectionCount() != 1 {
		t.Fatalf("after toggles: sel=%v", a.sel)
	}
	// Toggle while OFF is a no-op.
	a.cancelSelection()
	a.toggleMsgSel("m3")
	if a.selOn || a.sel != nil {
		t.Fatalf("toggle outside selection mode mutated state")
	}
}

func TestStartSelectionClosesMenu(t *testing.T) {
	a := newSelApp()
	a.menu = &menuTarget{}
	a.startSelection("m1")
	if a.menu != nil {
		t.Fatal("menu should close when selection starts")
	}
}

func TestSelectedMessages(t *testing.T) {
	a := newSelApp()
	k := chatKey{AccountID: "acct", ChatID: "chat"}
	a.msgFor = &k
	a.messages = []engine.CachedMessage{
		{MsgID: "a", AccountID: "acct", ChatID: "chat", ContentText: "one"},
		{MsgID: "b", AccountID: "acct", ChatID: "chat", ContentText: "two"},
		{MsgID: "c", AccountID: "acct", ChatID: "chat", ContentText: "three"},
	}
	a.startSelection("b")
	a.toggleMsgSel("c")
	msgs := a.selectedMessages()
	if len(msgs) != 2 || msgs[0].MsgID != "b" || msgs[1].MsgID != "c" {
		t.Fatalf("selectedMessages = %+v", msgs)
	}
}

func TestForwardSelectedBuildsBatch(t *testing.T) {
	a := newSelApp()
	k := chatKey{AccountID: "acct", ChatID: "chat"}
	a.msgFor = &k
	a.messages = []engine.CachedMessage{
		{MsgID: "a", AccountID: "acct", ChatID: "chat"},
		{MsgID: "b", AccountID: "acct", ChatID: "chat"},
	}
	a.startSelection("a")
	a.toggleMsgSel("b")
	a.forwardSelected()
	if len(a.fwd) != 2 || a.selOn || a.sel != nil {
		t.Fatalf("forwardSelected: fwd=%d selOn=%v", len(a.fwd), a.selOn)
	}
}

// ── slice 126: forward comment ────────────────────────────────────────────

func TestTrimForwardComment(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"", ""},
		{"   ", ""},
		{"\n\n", ""},
		{"  hi \n", "hi"},
		{"multi\nline\ncomment", "multi\nline\ncomment"},
	}
	for _, c := range cases {
		if got := trimForwardComment(c.in); got != c.want {
			t.Errorf("trimForwardComment(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestForwardCommentOrder(t *testing.T) {
	// The comment ships as its own message BEFORE the forwarded batch
	// (Telegram share-sheet semantics): the plan is comment-first per
	// recipient, then the forward.
	steps := forwardCommitSteps("note", []string{"m1", "m2"})
	if len(steps) != 2 || steps[0].kind != fwdStepComment || steps[0].text != "note" {
		t.Fatalf("steps = %+v, want comment first", steps)
	}
	if steps[1].kind != fwdStepForward || len(steps[1].ids) != 2 {
		t.Fatalf("forward step wrong: %+v", steps[1])
	}
	// No comment → only the forward step.
	steps = forwardCommitSteps("", []string{"m1"})
	if len(steps) != 1 || steps[0].kind != fwdStepForward {
		t.Fatalf("no-comment steps = %+v", steps)
	}
}
