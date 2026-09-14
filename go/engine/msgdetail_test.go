package engine

import (
	"encoding/json"
	"testing"

	"uniclient/cores"
)

// Message details completion (slice 207): the media DC rides the media
// row (migrateV56) into CachedMessage.MediaDC, and the sticker-set
// author ID derives from the cached pack ID with the TDesktop-x64
// bit formula AyuGram uses (getUserIdFromPackId).

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
	// The TDesktop-x64 formula (AyuGram getUserIdFromPackId):
	//   ownerId = id >> 32
	//   if (id >> 16 & 0xff) == 0x3f  → ownerId |= 0x80000000
	//   if id >> 24 & 0xff             → ownerId += 0x100000000
	cases := []struct {
		packID int64
		want   int64
	}{
		{packID: 0x0000000200000001, want: 2},           // plain: user 2
		{packID: 0x0000000500000007, want: 5},           // plain: user 5
		{packID: 0x0000000A003F0001, want: 0x8000000A},  // 0x3f byte at >>16
		{packID: 0x0000000A01000001, want: 0x10000000A}, // non-zero byte at >>24
		{packID: 0, want: 0},                            // no pack
		{packID: 0x0000000000FFFFFF, want: 0},           // pack-only bits, no author
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
	// Absent → 0.
	var m2 CachedMessage
	m2.ContentRaw = []byte(`{"extra":{}}`)
	if id := m2.StickerSetID(); id != 0 {
		t.Errorf("absent sticker_set_id must be 0, got %d", id)
	}
	// Malformed → 0, never a panic.
	var m3 CachedMessage
	m3.ContentRaw = []byte(`{"extra":{"sticker_set_id":"not-a-number"}}`)
	if id := m3.StickerSetID(); id != 0 {
		t.Errorf("malformed sticker_set_id must be 0, got %d", id)
	}
}
