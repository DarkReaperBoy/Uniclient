package gui

// Message details (AyuGram parity slice 105): the message context menu
// gains Ayu's "Message details" — a dialog of key/value rows derived from
// what the engine actually caches (dates, sender, delivery, media
// metadata, forward origin, flags). Rows the engine does not have (DC,
// views for non-channel messages) are simply absent — honest, never
// fabricated (§1.10). Pure derivation locked here.

import (
	"testing"
	"time"

	"uniclient/engine"
	"uniclient/utils"
)

func detailValues(rows []detailRow) map[string]string {
	m := map[string]string{}
	for _, r := range rows {
		m[r.label] = r.value
	}
	return m
}

func TestMsgDetailRowsPlain(t *testing.T) {
	now := time.Unix(1700000000, 0)
	m := engine.CachedMessage{
		MsgID:      "555",
		SenderID:   "42",
		SenderName: "Alice",
		Timestamp:  now.Add(-2 * time.Hour).Unix(),
		Status:     engine.MsgStatusSent,
	}
	rows := msgDetailRows(m, now, "")
	v := detailValues(rows)
	if v["Message ID"] != "555" {
		t.Fatalf("id = %q", v["Message ID"])
	}
	if v["Sender"] != "Alice (42)" {
		t.Fatalf("sender = %q", v["Sender"])
	}
	if v["Sent"] == "" {
		t.Fatal("sent date must exist")
	}
	if _, ok := v["Edited"]; ok {
		t.Fatal("unedited message must not have an Edited row")
	}
	if _, ok := v["File"]; ok {
		t.Fatal("non-media message must not have media rows")
	}
}

func TestMsgDetailRowsSenderFallback(t *testing.T) {
	now := time.Unix(1, 0)
	m := engine.CachedMessage{MsgID: "1", SenderID: "42", Timestamp: now.Unix()}
	v := detailValues(msgDetailRows(m, now, ""))
	if v["Sender"] != "user 42" {
		t.Fatalf("id-only sender = %q", v["Sender"])
	}
	// Service messages have no sender row at all.
	m.IsService = true
	v = detailValues(msgDetailRows(m, now, ""))
	if _, ok := v["Sender"]; ok {
		t.Fatalf("service message sender row must be absent: %q", v["Sender"])
	}
}

func TestMsgDetailRowsEdited(t *testing.T) {
	now := time.Unix(1700000000, 0)
	m := engine.CachedMessage{MsgID: "1", Timestamp: now.Add(-time.Hour).Unix(), EditedAt: now.Add(-30 * time.Minute).Unix()}
	v := detailValues(msgDetailRows(m, now, ""))
	if v["Edited"] == "" {
		t.Fatal("edited row must exist")
	}
}

func TestMsgDetailRowsMedia(t *testing.T) {
	now := time.Unix(1, 0)
	m := engine.CachedMessage{
		MsgID:          "1",
		Timestamp:      now.Unix(),
		HasMedia:       true,
		MediaFileName:  "cat.jpg",
		MediaMimeType:  "image/jpeg",
		MediaFileSize:  2048,
		MediaWidth:     640,
		MediaHeight:    480,
		MediaDuration:  0,
		MediaLocalPath: "/data/cat.jpg",
	}
	v := detailValues(msgDetailRows(m, now, ""))
	if v["File"] != "cat.jpg" {
		t.Fatalf("file = %q", v["File"])
	}
	if v["Type"] != "image/jpeg" {
		t.Fatalf("type = %q", v["Type"])
	}
	if v["Size"] != "2 KB" {
		t.Fatalf("size = %q, want 2 KB", v["Size"])
	}
	if v["Dimensions"] != "640 × 480" {
		t.Fatalf("dims = %q", v["Dimensions"])
	}
	if v["Saved at"] != "/data/cat.jpg" {
		t.Fatalf("path = %q", v["Saved at"])
	}
	if _, ok := v["Duration"]; ok {
		t.Fatal("zero duration must be omitted")
	}
	// Voice message: duration row appears.
	m.MediaDuration = 95
	m.MediaMimeType = "audio/ogg"
	v = detailValues(msgDetailRows(m, now, ""))
	if v["Duration"] != "1:35" {
		t.Fatalf("duration = %q, want 1:35", v["Duration"])
	}
}

func TestMsgDetailRowsForwardReplyFlags(t *testing.T) {
	now := time.Unix(1, 0)
	m := engine.CachedMessage{
		MsgID:       "1",
		Timestamp:   now.Unix(),
		ForwardFrom: "Bob",
		ReplyToID:   "77",
		IsPinned:    true,
		IsSilent:    true,
	}
	v := detailValues(msgDetailRows(m, now, ""))
	if v["Forwarded from"] != "Bob" {
		t.Fatalf("fwd = %q", v["Forwarded from"])
	}
	if v["Reply to"] != "77" {
		t.Fatalf("reply = %q", v["Reply to"])
	}
	if v["Pinned"] != "yes" {
		t.Fatalf("pinned = %q", v["Pinned"])
	}
	if v["Silent"] != "yes" {
		t.Fatalf("silent = %q", v["Silent"])
	}
}

func TestMsgDetailRowsDeleted(t *testing.T) {
	now := time.Unix(1700000000, 0)
	m := engine.CachedMessage{MsgID: "1", Timestamp: now.Add(-time.Hour).Unix(), IsDeleted: true, DeletedAt: now.Add(-5 * time.Minute).Unix()}
	v := detailValues(msgDetailRows(m, now, ""))
	if v["Deleted"] == "" {
		t.Fatal("anti-recall deleted row must exist")
	}
}

func TestMsgDetailMenuGate(t *testing.T) {
	// Service messages have no details; everything real does.
	if msgDetailMenuGate(engine.CachedMessage{IsService: true}) {
		t.Fatal("service messages get no details item")
	}
	if !msgDetailMenuGate(engine.CachedMessage{MsgID: "5"}) {
		t.Fatal("real messages get the details item")
	}
}

var _ = utils.AppConfig{}

func TestDCNameLabel(t *testing.T) {
	cases := []struct {
		dc   int
		want string
	}{
		{1, "DC1, Miami FL, USA"},
		{3, "DC3, Miami FL, USA"},
		{2, "DC2, Amsterdam, NL"},
		{4, "DC4, Amsterdam, NL"},
		{5, "DC5, Singapore, SG"},
		{9, "DC9, UNKNOWN"},
		{0, ""},
		{-1, ""},
	}
	for _, c := range cases {
		if got := dcNameLabel(c.dc); got != c.want {
			t.Errorf("dcNameLabel(%d) = %q, want %q", c.dc, got, c.want)
		}
	}
}

func TestMsgDetailRowsDatacenter(t *testing.T) {
	now := time.Unix(1700000000, 0)
	m := engine.CachedMessage{MsgID: "1", Timestamp: now.Unix(), HasMedia: true, MediaDC: 4}
	v := detailValues(msgDetailRows(m, now, ""))
	if v["Datacenter"] != "DC4, Amsterdam, NL" {
		t.Fatalf("datacenter = %q, want DC4, Amsterdam, NL", v["Datacenter"])
	}
	// No DC (0 / non-Telegram platforms) → no row (§1.10).
	m2 := engine.CachedMessage{MsgID: "2", Timestamp: now.Unix(), HasMedia: true}
	if v2 := detailValues(msgDetailRows(m2, now, "")); v2["Datacenter"] != "" {
		t.Fatalf("absent DC must hide the row, got %q", v2["Datacenter"])
	}
}

func TestMsgDetailRowsStickerAuthor(t *testing.T) {
	now := time.Unix(1700000000, 0)
	// A sticker message: pack 0x0000000A00000021 → author user 10.
	raw := `{"extra":{"sticker_set_id":"42949673233"}}` // 0xA00000021
	m := engine.CachedMessage{MsgID: "9", Timestamp: now.Unix(), ContentRaw: []byte(raw)}
	if authorID := engine.StickerPackAuthorID(m.StickerSetID()); authorID != 10 {
		t.Fatalf("pack author = %d, want 10", authorID)
	}
	rows := msgDetailRows(m, now, "")
	var found bool
	for _, r := range rows {
		if r.label == "Sticker author" {
			found = true
			if r.action != "author" {
				t.Errorf("author row action = %q, want author", r.action)
			}
			if r.value != "user 10" {
				t.Errorf("unresolved author value = %q, want \"user 10\"", r.value)
			}
		}
	}
	if !found {
		t.Fatal("sticker author row missing")
	}
	// Resolved name replaces the fallback.
	rows = msgDetailRows(m, now, "Jane Packmaker")
	for _, r := range rows {
		if r.label == "Sticker author" && r.value != "Jane Packmaker" {
			t.Errorf("resolved author value = %q, want Jane Packmaker", r.value)
		}
	}
	// Non-sticker messages get no author row.
	plain := engine.CachedMessage{MsgID: "10", Timestamp: now.Unix()}
	for _, r := range msgDetailRows(plain, now, "") {
		if r.label == "Sticker author" {
			t.Fatal("non-sticker message must not carry an author row")
		}
	}
}
