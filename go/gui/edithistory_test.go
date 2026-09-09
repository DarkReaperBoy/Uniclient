package gui

// Edits-history viewer (slice 96, matrix row 164): pure helpers — revision
// row naming, ordering, the context-menu gate (which messages offer the
// action and when the async lookup has resolved), and escTarget
// self-handling.

import (
	"testing"

	"uniclient/engine"
)

func TestEditHistRowTitle(t *testing.T) {
	cases := []struct {
		rev  engine.EditRevision
		want string
	}{
		{engine.EditRevision{SenderName: "Alice"}, "Alice"},
		{engine.EditRevision{SenderName: "", SenderID: "u42"}, "user u42"},
		{engine.EditRevision{}, "someone"},
	}
	for _, tc := range cases {
		if got := editHistRowTitle(tc.rev); got != tc.want {
			t.Errorf("editHistRowTitle(%+v) = %q, want %q", tc.rev, got, tc.want)
		}
	}
}

func TestEditHistRowPreview(t *testing.T) {
	cases := []struct {
		name, text, want string
	}{
		{"plain", "hello world", "hello world"},
		{"trims", "  padded  ", "padded"},
		{"newline first line", "line one\nline two", "line one"},
		{"empty", "   ", "(no text)"},
	}
	for _, tc := range cases {
		if got := editHistRowPreview(tc.text); got != tc.want {
			t.Errorf("%s: editHistRowPreview(%q) = %q, want %q", tc.name, tc.text, got, tc.want)
		}
	}
}

func TestEditsMenuGate(t *testing.T) {
	cases := []struct {
		name  string
		m     engine.CachedMessage
		known bool
		has   bool
		want  bool
	}{
		{"edited message, resolved true", engine.CachedMessage{MsgID: "m1", EditedAt: 1}, true, true, true},
		{"edited message, resolved false", engine.CachedMessage{MsgID: "m2", EditedAt: 1}, true, false, false},
		{"lookup pending hides item", engine.CachedMessage{MsgID: "m3", EditedAt: 1}, false, true, false},
		{"never edited hides item", engine.CachedMessage{MsgID: "m4"}, true, true, false},
		{"service row hides item", engine.CachedMessage{MsgID: "m5", IsService: true, EditedAt: 1}, true, true, false},
	}
	for _, tc := range cases {
		if got := editsMenuGate(tc.m, tc.known, tc.has); got != tc.want {
			t.Errorf("%s: editsMenuGate = %v, want %v", tc.name, got, tc.want)
		}
	}
}

func TestEscTargetEditHistDlgSelfHandled(t *testing.T) {
	f := frame{editHistDlg: &editHistState{}, menu: &menuTarget{}}
	if got := escTarget(f); got != "" {
		t.Errorf("editHistDlg + menu: escTarget = %q, want empty (dialog consumes Esc)", got)
	}
}

func TestMenuActionsEditsItem(t *testing.T) {
	// menuActionsFor includes "Edits history" when the menu target carries
	// a resolved revisions lookup (pure item construction — the closures
	// only run on click).
	m := engine.CachedMessage{
		AccountID: "a", ChatID: "c", MsgID: "m1", SenderID: "u1", EditedAt: 1,
	}
	a := &App{}
	f := frame{menu: &menuTarget{msg: m, hasEdits: boolPtr(true)}}
	found := false
	for _, it := range a.menuActionsFor(f, m) {
		if it.label == "Edits history" {
			found = true
		}
	}
	if !found {
		t.Errorf("menuActionsFor: \"Edits history\" missing (items: %v)", menuLabels(a.menuActionsFor(f, m)))
	}
	// Lookup pending → no item.
	f2 := frame{menu: &menuTarget{msg: m}}
	for _, it := range a.menuActionsFor(f2, m) {
		if it.label == "Edits history" {
			t.Error("\"Edits history\" present while the revisions lookup is pending")
		}
	}
}

func boolPtr(b bool) *bool { return &b }
