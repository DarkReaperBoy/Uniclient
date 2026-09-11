package gui

// Inline bot results tests (slice 128): composer query parsing (@bot at
// message start, terminated by a space), fetch-key guarding, and the
// thumb/model shaping the panel renders from.

import (
	"testing"

	"uniclient/cores"
)

func TestInlineBotQuery(t *testing.T) {
	cases := []struct {
		text  string
		bot   string
		query string
		ok    bool
	}{
		{"@gif cats", "gif", "cats", true},
		{"@gif ", "gif", "", true}, // terminated, empty query: tdesktop shows default results
		{"@pic_search nature", "pic_search", "nature", true},
		{"@gif", "", "", false},            // @token still being typed (not terminated)
		{"@gi cats", "", "", false},        // too short (Telegram usernames are 5+)
		{"hello @gif cats", "", "", false}, // @bot must start the message
		{"@", "", "", false},
		{"", "", "", false},
		{"@gif!cats", "", "", false}, // '!' is not a username char and not a separator
		{"@gif  two spaces", "gif", " two spaces", true},
	}
	for _, c := range cases {
		bot, query, ok := inlineBotQuery(c.text)
		if ok != c.ok || bot != c.bot || query != c.query {
			t.Errorf("inlineBotQuery(%q) = (%q, %q, %v), want (%q, %q, %v)",
				c.text, bot, query, ok, c.bot, c.query, c.ok)
		}
	}
}

func TestInlineFetchKey(t *testing.T) {
	a := inlineFetchKey("acct1", "gif", "cats")
	b := inlineFetchKey("acct1", "gif", "cats")
	if a != b {
		t.Error("same inputs → different keys")
	}
	if inlineFetchKey("acct1", "gif", "cats") == inlineFetchKey("acct1", "gif", "dogs") {
		t.Error("query not part of the key")
	}
	if inlineFetchKey("acct1", "gif", "cats") == inlineFetchKey("acct2", "gif", "cats") {
		t.Error("account not part of the key")
	}
}

func TestInlineResultThumb(t *testing.T) {
	if inlineResultThumb(cores.InlineBotResult{}) != "" {
		t.Error("result without thumb yielded a thumb")
	}
	if got := inlineResultThumb(cores.InlineBotResult{ThumbB64: "QUJD"}); got != "QUJD" {
		t.Errorf("b64 thumb = %q, want QUJD", got)
	}
	// HTTP-only thumbs (plain BotInlineResult) need a URL fetcher this build
	// does not have — the panel renders those rows text-only (honest §1.10).
	if got := inlineResultThumb(cores.InlineBotResult{ThumbURL: "https://x/t.png"}); got != "" {
		t.Errorf("url thumb leaked into the b64 path: %q", got)
	}
}

func TestInlineResultSubtitle(t *testing.T) {
	if s := inlineResultSubtitle(cores.InlineBotResult{Title: "T", Description: "D"}); s != "D" {
		t.Errorf("subtitle = %q, want D", s)
	}
	if s := inlineResultSubtitle(cores.InlineBotResult{Title: "T"}); s != "" {
		t.Errorf("missing description subtitle = %q", s)
	}
	if s := inlineResultSubtitle(cores.InlineBotResult{Title: "T", Description: "  "}); s != "" {
		t.Errorf("blank description subtitle = %q", s)
	}
}

func TestInlinePanelModel(t *testing.T) {
	// No results → no panel.
	if m := newInlinePanelModel(nil); m != nil {
		t.Error("nil results produced a panel")
	}
	if m := newInlinePanelModel(&cores.InlineBotResults{}); m != nil {
		t.Error("empty results produced a panel")
	}
	res := &cores.InlineBotResults{
		QueryID: 42,
		Gallery: true,
		Results: []cores.InlineBotResult{
			{ID: "1", Type: "photo", Title: "Sunset", ThumbB64: "QUJD"},
			{ID: "2", Type: "article", Title: "Read", Description: "An article"},
		},
		SwitchPM: "Open @gif",
	}
	m := newInlinePanelModel(res)
	if m == nil {
		t.Fatal("results produced no panel")
	}
	if m.QueryID != 42 || len(m.Results) != 2 || !m.Gallery {
		t.Errorf("model = %+v", m)
	}
	if m.SwitchPM != "Open @gif" {
		t.Errorf("switch_pm = %q", m.SwitchPM)
	}
	if m.Results[0].ThumbB64 != "QUJD" || m.Results[1].Description != "An article" {
		t.Errorf("results shaping = %+v", m.Results)
	}
}

func TestInlineMoreAvailable(t *testing.T) {
	if inlineMoreAvailable(&cores.InlineBotResults{NextOffset: "5"}) {
		t.Error("empty results: More must not show")
	}
	res := &cores.InlineBotResults{NextOffset: "5", Results: []cores.InlineBotResult{{ID: "1"}}}
	if !inlineMoreAvailable(res) {
		t.Error("next_offset with results: More must show")
	}
	res.NextOffset = ""
	if inlineMoreAvailable(res) {
		t.Error("no next_offset: More must not show")
	}
}
