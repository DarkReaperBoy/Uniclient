package gui

// Ayu message filters GUI (slice 90, matrix row 238): settings-row
// summaries, the escTarget registration, and the content-pane dialog
// priority contract (incl. the c1fca15c ordering regression pin).

import (
	"regexp"
	"strings"
	"testing"

	"uniclient/engine"
)

func TestFilterCountLabel(t *testing.T) {
	cases := []struct {
		name string
		fs   []engine.AyuFilter
		want string
	}{
		{"none", nil, "Off"},
		{"empty", []engine.AyuFilter{}, "Off"},
		{"one on", []engine.AyuFilter{{ID: 1, Enabled: true}}, "1/1 active"},
		{"mixed", []engine.AyuFilter{{ID: 1, Enabled: true}, {ID: 2, Enabled: false}}, "1/2 active"},
		{"all off", []engine.AyuFilter{{ID: 1, Enabled: false}, {ID: 2, Enabled: false}}, "2 filters · all off"},
	}
	for _, tc := range cases {
		if got := filterCountLabel(tc.fs); got != tc.want {
			t.Errorf("%s: filterCountLabel = %q, want %q", tc.name, got, tc.want)
		}
	}
}

func TestFilterCountText(t *testing.T) {
	cases := []struct {
		loaded bool
		n      int
		want   string
	}{
		{false, 0, "…"},
		{false, 3, "…"},
		{true, 0, "Off"},
		{true, 1, "1"},
		{true, 7, "7"},
	}
	for _, tc := range cases {
		if got := filterCountText(tc.loaded, tc.n); got != tc.want {
			t.Errorf("filterCountText(%v, %d) = %q, want %q", tc.loaded, tc.n, got, tc.want)
		}
	}
}

func TestContentPaneDialogSurface(t *testing.T) {
	// Nothing open → no dialog.
	if got := contentDialogSurface(frame{}); got != "" {
		t.Fatalf("empty frame = %q, want \"\"", got)
	}

	// Each dialog alone wins.
	solo := map[string]frame{
		"newChat":       {newDlg: &newChatDlg{}},
		"contacts":      {contactsOpen: true},
		"folder":        {folderDlg: &folderDlgState{}},
		"folderInvites": {folderInvites: &folderInvitesState{}},
		"attach":        {attachDlg: &attachDlgState{}},
		"addMember":     {addMemDlg: &addMemDlgState{}},
		"ttl":           {ttlDlg: &ttlDlgState{}},
		"privacy":       {privacyDlg: &privacyDlgState{accountID: "a", key: "calls"}},
		"lock":          {lockDlg: &lockDlgState{}},
		"autoDownload":  {autoDlDlg: &autodlDlgState{}},
		"chatTheme":     {themeDlg: &chatThemeDlgState{}},
		"cloudTheme":    {cloudDlg: &cloudThemeDlgState{}},
		"ayuFilters":    {ayuFilterDlg: &ayuFilterDlgState{}},
	}
	for want, f := range solo {
		if got := contentDialogSurface(f); got != want {
			t.Errorf("solo %s: = %q, want %q", want, got, want)
		}
	}

	// REGRESSION PIN (c1fca15c): dialogs opened from settings must beat
	// the settings page, and the passcode LOCK must beat everything.
	reg := frame{
		settingsOpen: true,
		selected:     &chatKey{AccountID: "a", ChatID: "c"},
	}
	if got := contentDialogSurface(reg); got != "" {
		t.Errorf("settings + chat, no dialog: = %q, want \"\" (settings renders)", got)
	}
	reg.autoDlDlg = &autodlDlgState{}
	if got := contentDialogSurface(reg); got != "autoDownload" {
		t.Errorf("autoDl + settings + chat: = %q, want autoDownload (was hidden by c1fca15c)", got)
	}
	reg.ayuFilterDlg = &ayuFilterDlgState{}
	if got := contentDialogSurface(reg); got != "autoDownload" {
		t.Errorf("autoDl wins over ayuFilters (order): = %q, want autoDownload", got)
	}
	reg.lockDlg = &lockDlgState{}
	if got := contentDialogSurface(reg); got != "lock" {
		t.Errorf("lock + everything: = %q, want lock (security gate)", got)
	}
}

func TestEscTargetAyuFilterDlgSelfHandled(t *testing.T) {
	f := frame{ayuFilterDlg: &ayuFilterDlgState{}, menu: &menuTarget{}}
	if got := escTarget(f); got != "" {
		t.Errorf("ayuFilterDlg + menu: escTarget = %q, want empty (dialog consumes Esc)", got)
	}
}

func TestQuickFilterPattern(t *testing.T) {
	cases := []struct {
		name, in, want string
	}{
		{"empty", "   ", ""},
		{"first line only", "Buy now\nsecond line", `Buy now`},
		{"collapse spaces", "a\t b   c", `a b c`},
		{"regex metachars quoted", "50% off (really)!", `50% off \(really\)!`},
	}
	for _, tc := range cases {
		if got := quickFilterPattern(tc.in); got != tc.want {
			t.Errorf("%s: quickFilterPattern = %q, want %q", tc.name, got, tc.want)
		}
	}
	// Long text capped at 64 runes.
	long := strings.Repeat("x", 100)
	if got := quickFilterPattern(long); len([]rune(got)) != 64 {
		t.Errorf("cap: len = %d runes, want 64", len([]rune(got)))
	}
	// The quoted suggestion must actually match the source text.
	src := "Special (50%) offer — act now!"
	if !regexp.MustCompile(quickFilterPattern(src)).MatchString(src) {
		t.Error("quoted pattern must match its source text")
	}
}

func TestActionsForFilterGate(t *testing.T) {
	// Filter follows Copy: only messages with text.
	txt := engine.CachedMessage{MsgID: "m1", ContentText: "promo spam"}
	if acts := actionsFor(&txt, nil); !acts.Filter {
		t.Error("text message: Filter must be offered")
	}
	blank := engine.CachedMessage{MsgID: "m2"}
	if acts := actionsFor(&blank, nil); acts.Filter {
		t.Error("textless message: Filter must not be offered")
	}
	svc := engine.CachedMessage{MsgID: "m3", ContentText: "joined", IsService: true}
	if acts := actionsFor(&svc, nil); acts.Filter {
		t.Error("service message: Filter must not be offered")
	}
}
