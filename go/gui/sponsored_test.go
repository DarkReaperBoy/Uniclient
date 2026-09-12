package gui

// Sponsored messages (slice 163): pure derivations locked here — the
// eligible placements (broadcast channel + bot chat), the channel
// row-model extension (caption + 1-based ad rows appended after all
// message rows), and the view-report ledger semantics.

import (
	"testing"

	"uniclient/cores"
	"uniclient/engine"
)

func TestSponsoredEligible(t *testing.T) {
	cases := []struct {
		name string
		chat *engine.ChatInfo
		want bool
	}{
		{"nil", nil, false},
		{"channel", &engine.ChatInfo{Type: engine.ChatTypeChanVal}, true},
		{"bot DM", &engine.ChatInfo{Type: engine.ChatTypeDMVal, IsBot: true}, true},
		{"plain DM", &engine.ChatInfo{Type: engine.ChatTypeDMVal}, false},
		{"group", &engine.ChatInfo{Type: engine.ChatTypeGroupVal}, false},
		{"forum channel", &engine.ChatInfo{Type: engine.ChatTypeChanVal, IsForum: true}, true},
	}
	for _, c := range cases {
		if got := sponsoredEligible(c.chat); got != c.want {
			t.Errorf("%s: eligible = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestAppendSponsoredRows(t *testing.T) {
	chan1 := &engine.ChatInfo{Type: engine.ChatTypeChanVal}
	base := []chatRow{
		{day: "2 Jan 2006", msgIdx: -1},
		{msgIdx: 0},
		{msgIdx: 1},
	}
	ads := []cores.SponsoredMessageInfo{
		{RandomID: "aa", Title: "A"},
		{RandomID: "bb", Title: "B"},
	}

	// Channel with ads: caption + one row per ad, after the messages.
	got := appendSponsoredRows(append([]chatRow{}, base...), chan1, "", ads)
	if len(got) != len(base)+3 {
		t.Fatalf("rows = %d, want %d+3", len(got), len(base))
	}
	head := got[len(base)]
	if !head.spHead || head.msgIdx != -1 || head.spIdx != 0 {
		t.Fatalf("caption row = %+v", head)
	}
	for i := 1; i <= 2; i++ {
		r := got[len(base)+i]
		if r.spIdx != i || r.msgIdx != -1 {
			t.Fatalf("ad row %d = %+v", i, r)
		}
	}
	// Message rows untouched (compare the comparable fields).
	for i := range base {
		if got[i].day != base[i].day || got[i].msgIdx != base[i].msgIdx ||
			got[i].unread != base[i].unread || got[i].album != nil {
			t.Fatalf("message row %d mutated: %+v", i, got[i])
		}
	}

	// No ads → unchanged.
	if got := appendSponsoredRows(append([]chatRow{}, base...), chan1, "", nil); len(got) != len(base) {
		t.Fatalf("no-ads rows = %d, want %d", len(got), len(base))
	}
	// Non-channel → unchanged (bots use the top bar).
	bot := &engine.ChatInfo{Type: engine.ChatTypeDMVal, IsBot: true}
	if got := appendSponsoredRows(append([]chatRow{}, base...), bot, "", ads); len(got) != len(base) {
		t.Fatalf("bot rows = %d, want %d (top bar placement)", len(got), len(base))
	}
	// Topic view inside a channel → unchanged.
	if got := appendSponsoredRows(append([]chatRow{}, base...), chan1, "12", ads); len(got) != len(base) {
		t.Fatalf("topic-view rows = %d, want %d", len(got), len(base))
	}
	// nil chat → unchanged.
	if got := appendSponsoredRows(append([]chatRow{}, base...), nil, "", ads); len(got) != len(base) {
		t.Fatalf("nil-chat rows = %d, want %d", len(got), len(base))
	}
}

func TestSponsoredViewOnce(t *testing.T) {
	a := &App{}
	if !a.sponsoredViewOnce("aa") {
		t.Fatal("first view report must fire")
	}
	if a.sponsoredViewOnce("aa") {
		t.Fatal("second view report in the same window must be suppressed")
	}
	if !a.sponsoredViewOnce("bb") {
		t.Fatal("a different ad must still report")
	}
}

func TestAppendSimilarRow(t *testing.T) {
	// Slice 167: the similar-channels block appends after the sponsored
	// block for broadcast channels only.
	chan1 := &engine.ChatInfo{Type: engine.ChatTypeChanVal}
	base := []chatRow{{msgIdx: 0}}
	if got := appendSimilarRow(append([]chatRow{}, base...), chan1, "", 3); len(got) != len(base)+1 || !got[len(got)-1].simBlock {
		t.Fatalf("channel with similar rows = %v", got)
	}
	if got := appendSimilarRow(append([]chatRow{}, base...), chan1, "", 0); len(got) != len(base) {
		t.Fatal("no recommendations must not append")
	}
	bot := &engine.ChatInfo{Type: engine.ChatTypeDMVal, IsBot: true}
	if got := appendSimilarRow(append([]chatRow{}, base...), bot, "", 3); len(got) != len(base) {
		t.Fatal("non-channel must not append")
	}
	if got := appendSimilarRow(append([]chatRow{}, base...), chan1, "12", 3); len(got) != len(base) {
		t.Fatal("topic view must not append")
	}
}
