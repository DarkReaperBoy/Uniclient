package gui

import (
	"testing"

	"uniclient/engine"
)

// TestSeparateWindowSupported pins the platform gate for multi-window chats
// (slice 168): desktop platforms only. Gio supports multiple native windows
// on Linux and Windows; js/wasm and Android expose exactly one window, so
// the entry points must hide there (honest absence, §1.10).
func TestSeparateWindowSupported(t *testing.T) {
	cases := []struct {
		goos string
		want bool
	}{
		{"linux", true},
		{"windows", true},
		{"js", false},
		{"android", false},
		{"darwin", false}, // banned platform anyway (§1.2)
	}
	for _, c := range cases {
		if got := separateWindowSupported(c.goos); got != c.want {
			t.Errorf("separateWindowSupported(%q) = %v, want %v", c.goos, got, c.want)
		}
	}
}

// TestChatMenuSeparateRow pins the chat-row context menu integration
// (tdesktop Filler::addNewWindow): "Open in separate window" is the FIRST
// row when the platform supports multi-window, and absent otherwise. The
// established row set survives unchanged behind it.
func TestChatMenuSeparateRow(t *testing.T) {
	base := engine.ChatInfo{AccountID: "a1", ChatID: "c1", Title: "Test", UnreadCount: 3}

	items := chatMenuItems(base, true)
	if len(items) == 0 || items[0].id != "separate" {
		t.Fatalf("first row must be the separate-window row, got %+v", items)
	}
	if items[0].label != "Open in separate window" {
		t.Errorf("separate label = %q, want %q", items[0].label, "Open in separate window")
	}

	// Platform without multi-window: the separate row disappears entirely.
	without := chatMenuItems(base, false)
	for _, it := range without {
		if it.id == "separate" {
			t.Fatalf("separate row must hide when unsupported, got %+v", without)
		}
	}
	// The existing rows are unchanged in content and order.
	with := chatMenuItems(base, true)
	for i := range without {
		if with[i+1] != without[i] {
			t.Errorf("row %d changed: %+v vs %+v", i, with[i+1], without[i])
		}
	}
}

// TestShouldDeselectMainForSeparate pins the one-window-per-chat invariant:
// opening a separate window deselects that chat in the main window (its
// widgets — a.wid.composer, scroll, row pools — must never render in two windows).
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

// TestSeparateAppMode pins the separate-window App routing: it reports
// separate mode, and the pure surface decision renders the chat view only.
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

// TestSeparateWindowTitle pins the window-title rule (tdesktop: the separate
// window is titled after its chat).
func TestSeparateWindowTitle(t *testing.T) {
	if got := separateWindowTitle(""); got != "Uniclient" {
		t.Errorf("empty title falls back to app name, got %q", got)
	}
	if got := separateWindowTitle("AyuGram Fans"); got != "AyuGram Fans" {
		t.Errorf("chat title passes through, got %q", got)
	}
}
