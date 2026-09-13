package gui

import (
	"encoding/json"
	"strings"
	"testing"
)

// Instant View reader (slice 176): pure-logic tests — core JSON → ivPage
// model, rich-text tree flattening, entry-point gating (known IV hosts,
// webpage-preview wp_has_iv flag), and the reader's history stack
// (related-article navigation). Layout is verified by compile + review.

func ivDoc(blocks ...map[string]interface{}) []byte {
	raw, _ := json.Marshal(map[string]interface{}{
		"url":       "https://telegra.ph/example-09-13",
		"title":     "An example article",
		"site_name": "Telegraph",
		"rtl":       false,
		"v2":        true,
		"blocks":    blocks,
	})
	return raw
}

func plainRT(s string) map[string]interface{} {
	return map[string]interface{}{"t": "plain", "v": s}
}

func boldRT(s string) map[string]interface{} {
	return map[string]interface{}{"t": "bold", "c": plainRT(s)}
}

func TestParseIVPageBasics(t *testing.T) {
	p := parseIVPage(ivDoc(
		map[string]interface{}{"type": "title", "text": plainRT("Hello")},
		map[string]interface{}{"type": "divider"},
	))
	if p == nil {
		t.Fatal("page not parsed")
	}
	if p.URL != "https://telegra.ph/example-09-13" || p.Title != "An example article" || p.SiteName != "Telegraph" {
		t.Fatalf("meta = %+v", p)
	}
	if p.RTL || !p.V2 {
		t.Fatalf("rtl/v2 = %v/%v", p.RTL, p.V2)
	}
	if len(p.Blocks) != 2 {
		t.Fatalf("blocks = %d", len(p.Blocks))
	}
	if p.Blocks[0].Type != "title" || p.Blocks[1].Type != "divider" {
		t.Fatalf("block types = %s, %s", p.Blocks[0].Type, p.Blocks[1].Type)
	}

	// Garbage JSON → nil, never panic.
	if parseIVPage([]byte("not json")) != nil {
		t.Fatal("garbage must not parse")
	}
	if parseIVPage([]byte(`{"url":"","blocks":[]}`)) != nil {
		t.Fatal("empty page must not parse")
	}
}

func TestParseIVPageBlockVariety(t *testing.T) {
	p := parseIVPage(ivDoc(
		map[string]interface{}{"type": "author_date", "author": plainRT("Jane Doe"), "date": float64(1726000000)},
		map[string]interface{}{"type": "paragraph", "text": map[string]interface{}{
			"t": "concat", "c": []interface{}{plainRT("plain "), boldRT("bold"), map[string]interface{}{
				"t": "url", "c": plainRT("link"), "href": "https://x.org",
			},
			}}},
		map[string]interface{}{"type": "preformatted", "text": plainRT("x := 1"), "lang": "go"},
		map[string]interface{}{"type": "list", "items": []interface{}{
			map[string]interface{}{"text": plainRT("one")},
			map[string]interface{}{"blocks": []interface{}{map[string]interface{}{"type": "paragraph", "text": plainRT("two")}}},
		}},
		map[string]interface{}{"type": "ordered_list", "items": []interface{}{
			map[string]interface{}{"num": float64(3), "text": plainRT("third")},
		}},
		map[string]interface{}{"type": "blockquote", "text": plainRT("quoted"), "caption": plainRT("source")},
		map[string]interface{}{"type": "photo", "photo_id": float64(9001), "thumb": "aGk=", "extra": "9001:OQ==", "w": float64(800), "h": float64(600), "caption": plainRT("a caption"), "url": "https://telegra.ph/file/x.jpg"},
		map[string]interface{}{"type": "video", "video_id": float64(7001), "mime": "video/mp4", "size": float64(42000), "duration": float64(12), "w": float64(640), "h": float64(360), "caption": plainRT("clip")},
		map[string]interface{}{"type": "related", "title": plainRT("See also"), "articles": []interface{}{
			map[string]interface{}{"url": "https://telegra.ph/other", "title": "Other", "desc": "More", "author": "Jane"},
		}},
		map[string]interface{}{"type": "details", "title": plainRT("More"), "blocks": []interface{}{map[string]interface{}{"type": "paragraph", "text": plainRT("hidden")}}, "open": false},
		map[string]interface{}{"type": "table", "title": plainRT("t"), "rows": []interface{}{
			[]interface{}{map[string]interface{}{"text": plainRT("H1"), "header": true, "colspan": float64(2)}},
			[]interface{}{map[string]interface{}{"text": plainRT("a"), "align_center": true}},
		}, "bordered": true, "striped": true},
		map[string]interface{}{"type": "channel", "title": "Some Channel", "username": "somechannel", "id": float64(12345)},
		map[string]interface{}{"type": "embed", "w": float64(640), "h": float64(360), "url": "https://youtube.com/watch?v=x", "caption": plainRT("video embed")},
		map[string]interface{}{"type": "kicker", "text": plainRT("TECH")},
		map[string]interface{}{"type": "pullquote", "text": plainRT("big quote"), "caption": plainRT("attr")},
	))
	if p == nil {
		t.Fatal("page not parsed")
	}
	byType := map[string]*ivBlock{}
	for i := range p.Blocks {
		byType[p.Blocks[i].Type] = &p.Blocks[i]
	}
	for _, k := range []string{"author_date", "paragraph", "preformatted", "list", "ordered_list", "blockquote", "photo", "video", "related", "details", "table", "channel", "embed", "kicker", "pullquote"} {
		if byType[k] == nil {
			t.Fatalf("missing block %q", k)
		}
	}
	if byType["photo"].PhotoID != 9001 || byType["photo"].ThumbB64 != "aGk=" || byType["photo"].Extra != "9001:OQ==" || byType["photo"].W != 800 || byType["photo"].H != 600 {
		t.Fatalf("photo block = %+v", *byType["photo"])
	}
	if byType["video"].Mime != "video/mp4" || byType["video"].Size != 42000 || byType["video"].Duration != 12 {
		t.Fatalf("video block = %+v", *byType["video"])
	}
	if len(byType["related"].Articles) != 1 || byType["related"].Articles[0].URL != "https://telegra.ph/other" || byType["related"].Articles[0].Title != "Other" {
		t.Fatalf("related = %+v", byType["related"].Articles)
	}
	if len(byType["table"].Rows) != 2 || byType["table"].Rows[0][0].Header != true || byType["table"].Rows[0][0].Colspan != 2 || byType["table"].Rows[1][0].AlignCenter != true {
		t.Fatalf("table = %+v", byType["table"].Rows)
	}
	if byType["channel"].ChannelTitle != "Some Channel" || byType["channel"].Username != "somechannel" || byType["channel"].ChannelID != 12345 {
		t.Fatalf("channel = %+v", *byType["channel"])
	}
	if byType["embed"].URL != "https://youtube.com/watch?v=x" || byType["embed"].W != 640 {
		t.Fatalf("embed = %+v", *byType["embed"])
	}
	if byType["author_date"].Date != 1726000000 {
		t.Fatalf("author_date = %+v", *byType["author_date"])
	}
	if byType["preformatted"].Lang != "go" {
		t.Fatalf("preformatted lang = %q", byType["preformatted"].Lang)
	}
	if byType["details"].Open {
		t.Fatal("details default must be closed when open=false")
	}
}

func TestIVRichSpans(t *testing.T) {
	// Build a rich-text tree: concat(plain("a "), bold(concat(italic("b"), url("c")))) + underline(" d")
	root := ivRich{Kind: "concat", Children: []ivRich{
		{Kind: "plain", Text: "a "},
		{Kind: "bold", Children: []ivRich{
			{Kind: "italic", Children: []ivRich{{Kind: "plain", Text: "b"}}},
			{Kind: "url", Href: "https://x.org", Children: []ivRich{{Kind: "plain", Text: "c"}}},
		}},
		{Kind: "underline", Children: []ivRich{{Kind: "plain", Text: " d"}}},
	}}
	spans := ivRichSpans(root)
	var sb strings.Builder
	for _, s := range spans {
		sb.WriteString(s.Text)
	}
	if got := sb.String(); got != "a bc d" {
		t.Fatalf("flattened text = %q", got)
	}
	// "b" = bold+italic, no href; "c" = bold + href; " d" = underline.
	var bFound, cFound, dFound bool
	for _, s := range spans {
		switch s.Text {
		case "b":
			bFound = s.Bold && s.Italic && s.Href == ""
		case "c":
			cFound = s.Bold && !s.Italic && s.Href == "https://x.org"
		case " d":
			dFound = s.Underline && !s.Bold
		}
	}
	if !bFound || !cFound || !dFound {
		t.Fatalf("span styles = %+v", spans)
	}

	// Email + fixed + strike propagation.
	root2 := ivRich{Kind: "email", Email: "a@b.c", Children: []ivRich{
		{Kind: "fixed", Children: []ivRich{{Kind: "strike", Children: []ivRich{{Kind: "plain", Text: "x"}}}}},
	}}
	spans2 := ivRichSpans(root2)
	if len(spans2) != 1 || !spans2[0].Fixed || !spans2[0].Strike || spans2[0].Email != "a@b.c" {
		t.Fatalf("email/fixed/strike = %+v", spans2)
	}

	// Plain node alone.
	spans3 := ivRichSpans(ivRich{Kind: "plain", Text: "solo"})
	if len(spans3) != 1 || spans3[0].Text != "solo" {
		t.Fatalf("solo = %+v", spans3)
	}
}

func TestIVKnownHost(t *testing.T) {
	for _, u := range []string{
		"https://telegra.ph/Example-09-13",
		"https://example.telegra.ph/Author-09-13",
		"http://graph.org/some-post",
		"https://en.graph.org/post",
	} {
		if !ivKnownHost(u) {
			t.Fatalf("expected IV host: %s", u)
		}
	}
	for _, u := range []string{
		"https://telegra.ph.evil.com/x", // suffix trick
		"https://evil.com/telegra.ph",   // path segment
		"https://telegram.org",          // not an IV host
		"not a url",
		"",
	} {
		if ivKnownHost(u) {
			t.Fatalf("must not be IV host: %q", u)
		}
	}
}

func TestWebPageHasIV(t *testing.T) {
	m := wpMessage(map[string]interface{}{
		"wp_url":       "https://telegra.ph/post",
		"wp_site_name": "Telegraph",
		"wp_has_iv":    true,
	})
	wp := parseWebPage(m)
	if wp == nil || !wp.HasIV {
		t.Fatalf("has_iv not parsed: %+v", wp)
	}
	m2 := wpMessage(map[string]interface{}{"wp_url": "https://x.org"})
	wp2 := parseWebPage(m2)
	if wp2 == nil || wp2.HasIV {
		t.Fatalf("absent has_iv must default false: %+v", wp2)
	}
}

func TestIVHistoryPushBack(t *testing.T) {
	st := &ivState{}
	page1 := &ivPage{URL: "https://telegra.ph/one", Title: "One"}
	page2 := &ivPage{URL: "https://telegra.ph/two", Title: "Two"}
	st.page = page1
	st.pushHistory(page2)
	if st.page != page2 || len(st.hist) != 1 || st.hist[0] != page1 {
		t.Fatalf("push: page=%v hist=%v", st.page, st.hist)
	}
	// Back pops: returns to page1, history empties.
	if st.back() != true || st.page != page1 || len(st.hist) != 0 {
		t.Fatalf("back: page=%v hist=%v", st.page, st.hist)
	}
	// Back on empty history returns false (overlay closes instead).
	if st.back() {
		t.Fatal("back on empty history must report false")
	}
	// Deep stack cap: pushes beyond ivHistMax drop the oldest.
	for i := 0; i < ivHistMax+5; i++ {
		st.pushHistory(&ivPage{URL: "u", Title: "t"})
	}
	if len(st.hist) > ivHistMax {
		t.Fatalf("history exceeds cap: %d > %d", len(st.hist), ivHistMax)
	}
}

func TestIVDetailsOpenDefault(t *testing.T) {
	p := parseIVPage(ivDoc(
		map[string]interface{}{"type": "details", "title": plainRT("A"), "blocks": []interface{}{}, "open": true},
		map[string]interface{}{"type": "details", "title": plainRT("B"), "blocks": []interface{}{}, "open": false},
	))
	if p == nil {
		t.Fatal("page not parsed")
	}
	st := &ivState{}
	if !st.detailsOpenAt(0, p.Blocks[0].Open) {
		t.Fatal("open=true default must be open")
	}
	if st.detailsOpenAt(1, p.Blocks[1].Open) {
		t.Fatal("open=false default must be closed")
	}
	st.setDetailsOpen(1, true)
	if !st.detailsOpenAt(1, false) {
		t.Fatal("override must win over the default")
	}
}
