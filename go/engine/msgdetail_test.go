package engine

import (
	"encoding/json"
	"testing"

	"uniclient/cores"
)

func TestMediaDCRoundTrip(t *testing.T) {
	e := newTestEngine(t)
	e.cacheMediaRef("a1", "c1", "m1", 0, cores.FileRef{
		ID:       "55",
		Name:     "song.mp3",
		MimeType: "audio/mpeg",
		Size:     10,
		DC:       4,
	})
	var dc int
	err := e.db.QueryRow(
		`SELECT dc_id FROM media WHERE account_id = 'a1' AND chat_id = 'c1' AND msg_id = 'm1' AND seq = 0`).
		Scan(&dc)
	if err != nil {
		t.Fatal(err)
	}
	if dc != 4 {
		t.Fatalf("stored dc_id = %d, want 4", dc)
	}
}

func TestStickerPackAuthorID(t *testing.T) {
	cases := []struct {
		packID int64
		want   int64
	}{
		{packID: 0x0000000200000001, want: 2},
		{packID: 0x0000000500000007, want: 5},
		{packID: 0x0000000A003F0001, want: 0x8000000A},
		{packID: 0x0000000A01000001, want: 0x10000000A},
		{packID: 0, want: 0},
		{packID: 0x0000000000FFFFFF, want: 0},
	}
	for _, c := range cases {
		if got := StickerPackAuthorID(c.packID); got != c.want {
			t.Errorf("StickerPackAuthorID(0x%X) = %d (0x%X), want %d (0x%X)", c.packID, got, got, c.want, c.want)
		}
	}
}

func TestStickerSetIDFromMessage(t *testing.T) {
	raw, _ := json.Marshal(map[string]interface{}{
		"extra": map[string]interface{}{
			"sticker_set_id": "12345678901234",
		},
	})
	var m CachedMessage
	m.ContentRaw = raw
	if id := m.StickerSetID(); id != 12345678901234 {
		t.Errorf("StickerSetID = %d, want 12345678901234", id)
	}
	var m2 CachedMessage
	m2.ContentRaw = []byte(`{"extra":{}}`)
	if id := m2.StickerSetID(); id != 0 {
		t.Errorf("absent sticker_set_id must be 0, got %d", id)
	}
	var m3 CachedMessage
	m3.ContentRaw = []byte(`{"extra":{"sticker_set_id":"not-a-number"}}`)
	if id := m3.StickerSetID(); id != 0 {
		t.Errorf("malformed sticker_set_id must be 0, got %d", id)
	}
}
