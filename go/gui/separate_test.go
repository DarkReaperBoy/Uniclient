package gui

import (
	"testing"

	"uniclient/engine"
)

func TestSeparateWindowSupported(t *testing.T) {
	cases := []struct {
		goos string
		want bool
	}{
		{"linux", true},
		{"windows", true},
		{"js", false},
		{"android", false},
		{"darwin", false},
	}
	for _, c := range cases {
		if got := separateWindowSupported(c.goos); got != c.want {
			t.Errorf("separateWindowSupported(%q) = %v, want %v", c.goos, got, c.want)
		}
	}
}

func TestChatMenuSeparateRow(t *testing.T) {
	base := engine.ChatInfo{AccountID: "a1", ChatID: "c1", Title: "Test", UnreadCount: 3}

	items := chatMenuItems(base, true)
	if len(items) == 0 || items[0].id != "separate" {
		t.Fatalf("first row must be the separate-window row, got %+v", items)
	}
	if items[0].label != "Open in separate window" {
		t.Errorf("separate label = %q, want %q", items[0].label, "Open in separate window")
	}

	without := chatMenuItems(base, false)
	for _, it := range without {
		if it.id == "separate" {
			t.Fatalf("separate row must hide when unsupported, got %+v", without)
		}
	}
	with := chatMenuItems(base, true)
	for i := range without {
		if with[i+1] != without[i] {
			t.Errorf("row %d changed: %+v vs %+v", i, with[i+1], without[i])
		}
	}
}

func TestShouldDeselectMainForSeparate(t *testing.T) {
	k := chatKey{AccountID: "a1", ChatID: "c1"}
	if !shouldDeselectMainForSeparate(&k, k) {
		t.Errorf("same chat selected in main must deselect")
	}
	other := chatKey{AccountID: "a1", ChatID: "c2"}
	if shouldDeselectMainForSeparate(&other, k) {
		t.Errorf("different chat selected must stay selected")
	}
	if shouldDeselectMainForSeparate(nil, k) {
		t.Errorf("nothing selected must stay deselected")
	}
}

func TestSeparateAppMode(t *testing.T) {
	a := &App{}
	if a.isSeparate() {
		t.Errorf("default App is the main window")
	}
	k := chatKey{AccountID: "a1", ChatID: "c9"}
	a.separate = &k
	if !a.isSeparate() {
		t.Errorf("App with separate key must report separate mode")
	}
}

func TestSeparateWindowTitle(t *testing.T) {
	if got := separateWindowTitle(""); got != "Uniclient" {
		t.Errorf("empty title falls back to app name, got %q", got)
	}
	if got := separateWindowTitle("AyuGram Fans"); got != "AyuGram Fans" {
		t.Errorf("chat title passes through, got %q", got)
	}
}
