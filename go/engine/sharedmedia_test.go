package engine

import "testing"

// Shared-media tab filters (engine/cache_msgs.go GetSharedMedia) and link
// extraction (profile Links tab) — pure helpers, tested before wiring.

func TestSharedMediaTypeFilter(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"image", "AND m.media_type IN (1, 7, 6)"},
		{"video", "AND m.media_type IN (2, 5)"},
		{"audio", "AND m.media_type IN (3, 4)"},
		{"gif", "AND m.media_type = 7"},
		{"voice", "AND m.media_type = 4"},
		{"file", "AND m.media_type = 8"},
		{"", ""},
		{"bogus", ""},
	}
	for _, c := range cases {
		if got := sharedMediaTypeFilter(c.in); got != c.want {
			t.Errorf("sharedMediaTypeFilter(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestExtractFirstURL(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"", ""},
		{"no links here", ""},
		{"look https://example.com/a?b=1 now", "https://example.com/a?b=1"},
		{"http://plain.org/x and https://other.io", "http://plain.org/x"},
		{"tg://join?invite=abc", "tg://join?invite=abc"},
		{"wrap (https://p.org),", "https://p.org"},
		{"www.noscheme.com", ""},
	}
	for _, c := range cases {
		if got := ExtractFirstURL(c.in); got != c.want {
			t.Errorf("ExtractFirstURL(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// GetSharedLinks + the gif/voice sub-tabs: DB-backed, seeded like the
// hide/poll tests (in-memory sqlite, migrateDB).

func seedSharedMsg(t *testing.T, e *Engine, msgID, text, sender string, ts int64) {
	t.Helper()
	_, err := e.db.Exec(
		`INSERT INTO messages (account_id, chat_id, msg_id, content_text, sender_name, timestamp)
                 VALUES ('a1', 'c1', ?, ?, ?, ?)`, msgID, text, sender, ts)
	if err != nil {
		t.Fatal(err)
	}
}

func seedSharedMedia(t *testing.T, e *Engine, msgID string, mediaType int) {
	t.Helper()
	_, err := e.db.Exec(
		`INSERT INTO media (account_id, chat_id, msg_id, seq, media_type, file_name, file_size, duration_ms)
                 VALUES ('a1', 'c1', ?, 0, ?, ?, ?, ?)`, msgID, mediaType, "f.bin", 1024, 3000)
	if err != nil {
		t.Fatal(err)
	}
}

func TestGetSharedLinks(t *testing.T) {
	e := newTestEngine(t)
	seedSharedMsg(t, e, "m1", "see https://example.com/a", "alice", 1000)
	seedSharedMsg(t, e, "m2", "no link here", "bob", 2000)
	seedSharedMsg(t, e, "m3", "docs at http://plain.org/x end", "carol", 3000)
	seedSharedMsg(t, e, "m4", "invite tg://join?invite=zz", "dave", 4000)

	items, err := e.GetSharedLinks("a1", "c1", 50, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 3 {
		t.Fatalf("links = %d items, want 3", len(items))
	}
	// Newest first.
	if items[0].MsgID != "m4" || items[0].URL != "tg://join?invite=zz" {
		t.Errorf("newest link = %+v, want m4 tg://join?invite=zz", items[0])
	}
	if items[1].URL != "http://plain.org/x" || items[1].SenderName != "carol" {
		t.Errorf("second link = %+v, want carol http://plain.org/x", items[1])
	}
	if items[2].URL != "https://example.com/a" || items[2].Timestamp != 1000 {
		t.Errorf("third link = %+v, want m1 https://example.com/a", items[2])
	}
}

func TestGetSharedMediaSubTabs(t *testing.T) {
	e := newTestEngine(t)
	// One message per distinct media kind; the gif/voice tabs must isolate
	// their kinds from the umbrella image/audio tabs.
	seedSharedMsg(t, e, "g1", "gif", "", 1000)
	seedSharedMedia(t, e, "g1", MediaGIF)
	seedSharedMsg(t, e, "i1", "img", "", 2000)
	seedSharedMedia(t, e, "i1", MediaImage)
	seedSharedMsg(t, e, "v1", "voice", "", 3000)
	seedSharedMedia(t, e, "v1", MediaVoice)
	seedSharedMsg(t, e, "a1m", "audio", "", 4000)
	seedSharedMedia(t, e, "a1m", MediaAudio)

	gifs, err := e.GetSharedMedia("a1", "c1", "gif", 50, 0, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(gifs) != 1 || gifs[0].MsgID != "g1" {
		t.Fatalf("gif tab = %+v, want only g1", gifs)
	}
	if gifs[0].Duration != 3 {
		t.Errorf("gif duration = %d, want 3 (duration_ms/1000)", gifs[0].Duration)
	}

	voices, err := e.GetSharedMedia("a1", "c1", "voice", 50, 0, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(voices) != 1 || voices[0].MsgID != "v1" {
		t.Fatalf("voice tab = %+v, want only v1", voices)
	}

	images, err := e.GetSharedMedia("a1", "c1", "image", 50, 0, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(images) != 2 {
		t.Fatalf("image tab = %d items, want 2 (image+gif)", len(images))
	}

	audio, err := e.GetSharedMedia("a1", "c1", "audio", 50, 0, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(audio) != 2 {
		t.Fatalf("audio tab = %d items, want 2 (voice+audio)", len(audio))
	}
}
