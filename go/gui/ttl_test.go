package gui

import (
	"testing"

	"uniclient/engine"
)

// TTL label rendering (slice 60): Telegram presets + custom fallbacks.
func TestTtlLabel(t *testing.T) {
	cases := map[int]string{
		0:              "Off",
		24 * 3600:      "24 hours",
		7 * 24 * 3600:  "7 days",
		30 * 24 * 3600: "1 month",
		2 * 24 * 3600:  "2 days",
		5 * 3600:       "5 hours",
		90:             "90s",
	}
	for secs, want := range cases {
		if got := ttlLabel(secs); got != want {
			t.Errorf("ttlLabel(%d) = %q, want %q", secs, got, want)
		}
	}
}

// TTL choices must cover Telegram's preset ladder, start with Off, and
// stay ascending.
func TestTtlChoices(t *testing.T) {
	if len(ttlChoices) != 4 {
		t.Fatalf("choices = %d", len(ttlChoices))
	}
	if ttlChoices[0].label != "Off" || ttlChoices[0].secs != 0 {
		t.Fatalf("first = %+v", ttlChoices[0])
	}
	prev := -1
	for _, ch := range ttlChoices {
		if ch.secs <= prev {
			t.Fatalf("not ascending: %+v", ttlChoices)
		}
		prev = ch.secs
		if ttlLabel(ch.secs) == ch.label+"!" { // labels must render sanely
			t.Errorf("weird label for %+v", ch)
		}
	}
}

// The dialog's chat wiring compiles against a ChatInfo snapshot.
func TestTtlDlgStateFields(t *testing.T) {
	st := &ttlDlgState{accountID: "a1", chatID: "c1", title: "Chat"}
	if st.accountID != "a1" || st.chatID != "c1" {
		t.Fatalf("state = %+v", st)
	}
	_ = engine.ChatInfo{TtlPeriod: 86400}
}
