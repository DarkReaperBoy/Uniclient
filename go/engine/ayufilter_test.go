package engine

// Ayu regex message filters (slice 90, matrix row 238): CRUD round-trips,
// invalid-regex rejection, and the load-path filtering.

import (
	"regexp"
	"testing"
)

func TestAyuFilterCRUD(t *testing.T) {
	e := newTestEngine(t)

	if got := e.ListAyuFilters(); len(got) != 0 {
		t.Fatalf("fresh engine has %d filters, want 0", len(got))
	}

	f1, err := e.AddAyuFilter(`(?i)promo`)
	if err != nil {
		t.Fatal(err)
	}
	if !f1.Enabled || f1.Pattern != `(?i)promo` {
		t.Fatalf("f1 = %+v", f1)
	}
	f2, err := e.AddAyuFilter(`spam\d+`)
	if err != nil {
		t.Fatal(err)
	}
	if f2.ID == f1.ID {
		t.Fatalf("ids must differ: %d", f1.ID)
	}

	got := e.ListAyuFilters()
	if len(got) != 2 {
		t.Fatalf("listed %d filters, want 2", len(got))
	}
	// Newest first.
	if got[0].ID != f2.ID || got[1].ID != f1.ID {
		t.Fatalf("order = %+v %+v, want newest first", got[0], got[1])
	}

	// Toggle → reflected in the list.
	if err := e.SetAyuFilterEnabled(f1.ID, false); err != nil {
		t.Fatal(err)
	}
	got = e.ListAyuFilters()
	for _, f := range got {
		if f.ID == f1.ID && f.Enabled {
			t.Fatal("disabled filter still enabled")
		}
	}

	// Remove → gone.
	if err := e.RemoveAyuFilter(f2.ID); err != nil {
		t.Fatal(err)
	}
	if got := e.ListAyuFilters(); len(got) != 1 || got[0].ID != f1.ID {
		t.Fatalf("after remove: %+v", got)
	}
}

func TestAyuFilterInvalidRegexRejected(t *testing.T) {
	e := newTestEngine(t)
	for _, bad := range []string{"", "   ", "([unclosed", "*star"} {
		if _, err := e.AddAyuFilter(bad); err == nil {
			t.Errorf("AddAyuFilter(%q) accepted an invalid pattern", bad)
		}
	}
	if got := e.ListAyuFilters(); len(got) != 0 {
		t.Fatalf("rejected filters must not be stored: %+v", got)
	}
}

func TestFilterMessagesByRegexes(t *testing.T) {
	msgs := []CachedMessage{
		{MsgID: "m1", ContentText: "Buy PROMO now"},
		{MsgID: "m2", ContentText: "hello world"},
		{MsgID: "m3", ContentText: "spam123 offer"},
		{MsgID: "m4", ContentText: ""},
	}
	promo := regexp.MustCompile(`(?i)promo`)
	spam := regexp.MustCompile(`spam\d+`)

	out := filterMessagesByRegexes(msgs, nil)
	if len(out) != 4 {
		t.Fatalf("no regexes = passthrough, got %d", len(out))
	}
	out = filterMessagesByRegexes(msgs, []*regexp.Regexp{})
	if len(out) != 4 {
		t.Fatalf("empty set = passthrough, got %d", len(out))
	}

	out = filterMessagesByRegexes(msgs, []*regexp.Regexp{promo, spam})
	if len(out) != 2 {
		t.Fatalf("filtered = %d, want m2+m4", len(out))
	}
	for _, m := range out {
		if m.MsgID == "m1" || m.MsgID == "m3" {
			t.Errorf("matching message %s survived", m.MsgID)
		}
	}

	// Empty text never matches (media bubbles survive text filters).
	out = filterMessagesByRegexes([]CachedMessage{{MsgID: "m4"}}, []*regexp.Regexp{regexp.MustCompile(`.*`)})
	if len(out) != 1 {
		t.Fatal("empty-content message must survive")
	}
}

func TestGetMessagesAppliesAyuFilters(t *testing.T) {
	e := newTestEngine(t)
	seedMessage(t, e, "m1", 1000)
	seedMessage(t, e, "m2", 2000)
	seedMessage(t, e, "m3", 3000)
	// seedMessage writes content_text = msgID, so "m2" matches ^m2$.

	if _, err := e.AddAyuFilter(`^m2$`); err != nil {
		t.Fatal(err)
	}
	msgs, err := e.GetMessages("a1", "c1", 0, 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 2 {
		t.Fatalf("filtered window = %d messages, want 2", len(msgs))
	}
	for _, m := range msgs {
		if m.MsgID == "m2" {
			t.Fatal("matching message still returned")
		}
	}

	// Disabling the filter restores the full window.
	fs := e.ListAyuFilters()
	if len(fs) != 1 {
		t.Fatalf("filters = %+v", fs)
	}
	if err := e.SetAyuFilterEnabled(fs[0].ID, false); err != nil {
		t.Fatal(err)
	}
	msgs, err = e.GetMessages("a1", "c1", 0, 0, 50)
	if err != nil {
		t.Fatal(err)
	}
	if len(msgs) != 3 {
		t.Fatalf("disabled filter must not hide: %d", len(msgs))
	}
}
