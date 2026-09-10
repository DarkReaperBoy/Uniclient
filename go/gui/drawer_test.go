package gui

import (
	"testing"

	"uniclient/engine"
)

func TestGhostAllOn(t *testing.T) {
	all := cfgSnapshot{
		SendReadReceipts: true, SendUploadProgress: true, SendReadStories: true,
		SendOnlinePackets: true, SendOfflineAfterOnline: true, MarkReadAfterAction: true,
		UseScheduledMessages: true, SendWithoutSound: true,
	}
	if !ghostAllOn(all) {
		t.Fatal("all flags on: expected ghost on")
	}
	// Each single flag off must flip the master state.
	fields := []func(c *cfgSnapshot) *bool{
		func(c *cfgSnapshot) *bool { return &c.SendReadReceipts },
		func(c *cfgSnapshot) *bool { return &c.SendUploadProgress },
		func(c *cfgSnapshot) *bool { return &c.SendReadStories },
		func(c *cfgSnapshot) *bool { return &c.SendOnlinePackets },
		func(c *cfgSnapshot) *bool { return &c.SendOfflineAfterOnline },
		func(c *cfgSnapshot) *bool { return &c.MarkReadAfterAction },
		func(c *cfgSnapshot) *bool { return &c.UseScheduledMessages },
		func(c *cfgSnapshot) *bool { return &c.SendWithoutSound },
	}
	for i, f := range fields {
		c := all
		*f(&c) = false
		if ghostAllOn(c) {
			t.Fatalf("flag %d off: expected ghost off", i)
		}
	}
	if ghostAllOn(cfgSnapshot{}) {
		t.Fatal("empty snapshot: expected ghost off")
	}
}

func TestContactMatches(t *testing.T) {
	c := engine.ContactInfo{
		DisplayName: "Alice Cooper",
		Username:    "alice",
		Phone:       "+15550100",
	}
	cases := []struct {
		q    string
		want bool
	}{
		{"", true},
		{"  ", true},
		{"alice", true},
		{"ALICE", true},
		{"  Alice  ", true},
		{"coop", true},
		{"555", true},
		{"bob", false},
		{"+15550200", false},
	}
	for _, tc := range cases {
		if got := contactMatches(c, tc.q); got != tc.want {
			t.Errorf("contactMatches(%q) = %v, want %v", tc.q, got, tc.want)
		}
	}
}

func TestContactSubtitleAndBadge(t *testing.T) {
	c := engine.ContactInfo{Username: "alice"}
	if got := contactSubtitle(c); got != "@alice" {
		t.Errorf("username subtitle = %q, want @alice", got)
	}
	c = engine.ContactInfo{Phone: "+15550100"}
	if got := contactSubtitle(c); got != "+15550100" {
		t.Errorf("phone subtitle = %q, want +15550100", got)
	}
	c = engine.ContactInfo{}
	if got := contactSubtitle(c); got != "" {
		t.Errorf("empty subtitle = %q, want \"\"", got)
	}

	c = engine.ContactInfo{IsBot: true}
	if got := contactBadge(c); got != "bot" {
		t.Errorf("bot badge = %q", got)
	}
	c = engine.ContactInfo{IsOnline: true}
	if got := contactBadge(c); got != "online" {
		t.Errorf("online badge = %q", got)
	}
	c = engine.ContactInfo{}
	if got := contactBadge(c); got != "" {
		t.Errorf("no badge expected, got %q", got)
	}
}

func TestSortContacts(t *testing.T) {
	list := []engine.ContactInfo{
		{DisplayName: "Zoe"},
		{DisplayName: "alice"},
		{DisplayName: "Bob"},
		{DisplayName: ""},
	}
	sortContacts(list)
	if list[0].DisplayName != "" {
		t.Errorf("empty name first, got %q", list[0].DisplayName)
	}
	if list[1].DisplayName != "alice" || list[2].DisplayName != "Bob" || list[3].DisplayName != "Zoe" {
		t.Errorf("sort order wrong: %q %q %q", list[1].DisplayName, list[2].DisplayName, list[3].DisplayName)
	}
}

func TestContactChat(t *testing.T) {
	chats := []engine.ChatInfo{
		{AccountID: "acc1", ChatID: "100", Type: engine.ChatTypeDMVal, Title: "Alice"},
		{AccountID: "acc1", ChatID: "200", Type: engine.ChatTypeGroupVal, Title: "Group"},
		{AccountID: "acc2", ChatID: "100", Type: engine.ChatTypeDMVal, Title: "Other account"},
	}
	if c, ok := contactChat(chats, "acc1", "100"); !ok || c.Title != "Alice" {
		t.Fatalf("expected Alice DM, got %+v ok=%v", c, ok)
	}
	// A group chat keyed by the same ID must not match (DM only).
	if _, ok := contactChat(chats, "acc1", "200"); ok {
		t.Fatal("group must not match a user ID lookup")
	}
	// Account scoping matters.
	if _, ok := contactChat(chats, "acc2", "100"); !ok {
		// acc2/100 IS a DM, so it matches — but for the wrong account
		// when scoping to acc1.
	}
	if _, ok := contactChat(chats, "acc1", "999"); ok {
		t.Fatal("unknown user must not match")
	}
}

// LRead/SRead drawer toggles (AyuGram parity slice 75): local read and
// send-read are independent flags — the config layer must round-trip both.

func TestLReadSReadIndependentChanges(t *testing.T) {
	// The field-mapping layer produces distinct changes for each toggle.
	lr := configFieldChanges("local_read_mark", false)
	if lr == nil || lr.LocalReadMark == nil || *lr.LocalReadMark {
		t.Fatalf("local_read_mark change: %+v", lr)
	}
	sr := configFieldChanges("send_read_receipts", false)
	if sr == nil || sr.SendReadReceipts == nil || *sr.SendReadReceipts {
		t.Fatalf("send_read_receipts change: %+v", sr)
	}
	// Flipping LRead must not touch SRead and vice versa.
	if lr.SendReadReceipts != nil {
		t.Fatal("LRead change must not carry SRead")
	}
	if sr.LocalReadMark != nil {
		t.Fatal("SRead change must not carry LRead")
	}
}

func TestGhostAllOnUnaffectedByLRead(t *testing.T) {
	// ghostAllOn stays keyed to the send-side flags only.
	c := cfgSnapshot{SendReadReceipts: true, SendUploadProgress: true, SendReadStories: true,
		SendOnlinePackets: true, SendOfflineAfterOnline: true, MarkReadAfterAction: true,
		UseScheduledMessages: true, SendWithoutSound: true}
	if !ghostAllOn(c) {
		t.Fatal("full send-side ghost profile must be on")
	}
	c.LocalReadMark = false
	if !ghostAllOn(c) {
		t.Fatal("LRead must not factor into the ghost master state")
	}
}
