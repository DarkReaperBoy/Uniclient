package tests

import (
	"fmt"
	"testing"

	"uniclient/ui/appport"
)

func TestPortMessagesBeforePagesOlderHistory(t *testing.T) {
	e := newTestEngine(t)
	for i := 1; i <= 120; i++ {
		seedMessage(t, e, fmt.Sprintf("%d", i), int64(i)*1000)
	}
	port := appport.For(e.Engine)
	newest, ok := port.Messages("a1", "c1", 50)
	if !ok || len(newest) != 50 {
		t.Fatalf("newest page = (%d, %v), want 50", len(newest), ok)
	}
	if newest[0].ID != "71" || newest[49].ID != "120" {
		t.Fatalf("newest page must be chronological ids 71..120, got %s..%s", newest[0].ID, newest[49].ID)
	}
	oldest := newest[0].TimestampMs
	older, ok := port.MessagesBefore("a1", "c1", oldest+1, 50)
	if !ok || len(older) != 50 {
		t.Fatalf("older page = (%d, %v), want 50", len(older), ok)
	}
	if older[0].ID != "22" || older[49].ID != "71" {
		t.Fatalf("older page must be chronological ids 22..71, got %s..%s", older[0].ID, older[49].ID)
	}
	if older[49].TimestampMs != oldest {
		t.Fatalf("the boundary message must ride the older page (same-ms inclusivity), got ts %d want %d",
			older[49].TimestampMs, oldest)
	}
	last, ok := port.MessagesBefore("a1", "c1", older[0].TimestampMs+1, 50)
	if !ok || len(last) != 22 {
		t.Fatalf("final page = (%d, %v), want the remaining 22 (boundary inclusive)", len(last), ok)
	}
	if last[0].ID != "1" || last[21].ID != "22" {
		t.Fatalf("final page must be ids 1..22, got %s..%s", last[0].ID, last[21].ID)
	}
	strict, ok := port.MessagesBefore("a1", "c1", last[0].TimestampMs, 50)
	if !ok || len(strict) != 0 {
		t.Fatalf("strict cursor below the oldest message must be empty, got (%d, %v)", len(strict), ok)
	}
	if _, ok := port.MessagesBefore("a1", "never-seen", 100, 50); !ok {
		t.Fatal("unknown chat must be ok-empty, not an error")
	}
}

func TestPortMessagesBeforeIsChronological(t *testing.T) {
	e := newTestEngine(t)
	for i := 1; i <= 30; i++ {
		seedMessage(t, e, fmt.Sprintf("%d", i), int64(i)*1000)
	}
	port := appport.For(e.Engine)
	msgs, ok := port.Messages("a1", "c1", 10)
	if !ok || len(msgs) != 10 {
		t.Fatalf("newest page = (%d, %v), want 10", len(msgs), ok)
	}
	older, ok := port.MessagesBefore("a1", "c1", msgs[0].TimestampMs+1, 10)
	if !ok || len(older) != 10 {
		t.Fatalf("older page = (%d, %v), want 10", len(older), ok)
	}
	prev := int64(0)
	for _, wm := range older {
		if wm.TimestampMs < prev {
			t.Fatalf("older page must be chronological, %d after %d", wm.TimestampMs, prev)
		}
		prev = wm.TimestampMs
	}
	if older[9].ID != msgs[0].ID {
		t.Fatalf("inclusive boundary must include the newest-page head id %s, got %s", msgs[0].ID, older[9].ID)
	}
}
