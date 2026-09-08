package engine

import (
	"testing"
)

// SearchMessagesEx kind filters (slice 57): links keep URL-bearing
// messages, files keep media-bearing messages, "" keeps everything.
func TestSearchMessagesExKindFilters(t *testing.T) {
	e := newTestEngine(t)
	seed := func(id, text, raw string, hasMedia int) {
		_, err := e.db.Exec(
			`INSERT INTO messages (account_id, chat_id, msg_id, content_text, content_raw, has_media, timestamp)
			 VALUES ('a1', 'c1', ?, ?, ?, ?, 1000)`, id, text, raw, hasMedia)
		if err != nil {
			t.Fatal(err)
		}
	}
	seed("m1", "plain cat text", "", 0)
	seed("m2", "see cat at http://cat.example", "", 0)
	seed("m3", "cat with entity", `{"entities":[{"type":"url","offset":0,"length":3}]}`, 0)
	seed("m4", "cat file", "", 1)

	all, err := e.SearchMessagesEx("cat*", "a1", 30, "", "", "", "")
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 4 {
		t.Fatalf("all = %d hits, want 4", len(all))
	}

	links, err := e.SearchMessagesEx("cat*", "a1", 30, "", "", "", SearchFilterLinks)
	if err != nil {
		t.Fatal(err)
	}
	if len(links) != 2 {
		t.Fatalf("links = %d hits, want 2 (m2, m3): %+v", len(links), links)
	}
	for _, r := range links {
		if r.MsgID != "m2" && r.MsgID != "m3" {
			t.Errorf("links hit = %s", r.MsgID)
		}
	}

	files, err := e.SearchMessagesEx("cat*", "a1", 30, "", "", "", SearchFilterFiles)
	if err != nil {
		t.Fatal(err)
	}
	if len(files) != 1 || files[0].MsgID != "m4" {
		t.Fatalf("files = %+v, want m4", files)
	}

	// Back-compat wrapper: same as "" kind.
	wrapped, err := e.SearchMessages("cat*", "a1", 30, "", "", "")
	if err != nil || len(wrapped) != 4 {
		t.Fatalf("wrapper = %d %v", len(wrapped), err)
	}
}
