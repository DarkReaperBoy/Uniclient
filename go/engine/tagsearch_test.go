package engine

import (
	"testing"
)

func TestMatchHashtagToken(t *testing.T) {
	cases := []struct {
		text, body string
		want       bool
	}{
		{"check #news now", "news", true},
		{"#news", "news", true},
		{"#News today", "news", true},
		{"newsletter only", "news", false},
		{"#newsletter", "news", false},
		{"#news2 is different", "news", false},
		{"#news_2 is different", "news", false},
		{"a #news, b", "news", true},
		{"tag #news. end", "news", true},
		{"", "news", false},
		{"#news", "", false},
		{"no tags here", "news", false},
		{"##news", "news", true},
	}
	for _, tc := range cases {
		if got := matchHashtagToken(tc.text, tc.body); got != tc.want {
			t.Errorf("matchHashtagToken(%q, %q) = %v, want %v", tc.text, tc.body, got, tc.want)
		}
	}
}

func TestSearchMessagesByTag(t *testing.T) {
	e := newTestEngine(t)
	seed := func(id, text string) {
		_, err := e.db.Exec(
			`INSERT INTO messages (account_id, chat_id, msg_id, content_text, timestamp)
			 VALUES ('a1', 'c1', ?, ?, 1000)`, id, text)
		if err != nil {
			t.Fatal(err)
		}
	}
	seed("m1", "check #news now")
	seed("m2", "newsletter about cats")
	seed("m3", "#newsflash again")
	seed("m4", "see #NEWS here")
	seed("m5", "nothing relevant")

	hits, err := e.SearchMessagesByTag("a1", "c1", "#news", 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(hits) != 2 {
		t.Fatalf("hits = %d, want 2 (m1, m4): %+v", len(hits), hits)
	}
	for _, h := range hits {
		if h.MsgID != "m1" && h.MsgID != "m4" {
			t.Errorf("tag hit = %s", h.MsgID)
		}
	}

	for _, q := range []string{"", "#", "##", "# "} {
		hits, err := e.SearchMessagesByTag("a1", "c1", q, 50)
		if err != nil || len(hits) != 0 {
			t.Errorf("query %q: hits=%v err=%v, want none/nil", q, hits, err)
		}
	}
}
