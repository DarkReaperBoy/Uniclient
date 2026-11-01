package gui

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
		{"@gif ", "gif", "", true},
		{"@pic_search nature", "pic_search", "nature", true},
		{"@gif", "", "", false},
		{"@gi cats", "", "", false},
		{"hello @gif cats", "", "", false},
		{"@", "", "", false},
		{"", "", "", false},
		{"@gif!cats", "", "", false},
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
	if src, _ := inlineThumbSource(cores.InlineBotResult{}); src != thumbSrcNone {
		t.Errorf("result without thumb yielded a route: %v", src)
	}
	if src, _ := inlineThumbSource(cores.InlineBotResult{ThumbB64: "QUJD"}); src != thumbSrcB64 {
		t.Errorf("b64 thumb not routed to the b64 path: %v", src)
	}
	if src, url := inlineThumbSource(cores.InlineBotResult{ThumbURL: "https://x/t.png"}); src != thumbSrcURL || url != "https://x/t.png" {
		t.Errorf("url thumb not routed to the fetcher: %v %q", src, url)
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
