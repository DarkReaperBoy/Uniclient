package gui

import (
	"testing"
)

func TestAttachMenuItemsMusic(t *testing.T) {
	a := &App{}
	items := a.attachMenuItems()
	labels := make([]string, len(items))
	for i, it := range items {
		labels[i] = it.label
		if it.icon == nil {
			t.Errorf("item %q has no icon", it.label)
		}
		if it.run == nil {
			t.Errorf("item %q has no run func", it.label)
		}
	}
	want := []string{"Photo or Video", "File", "Poll", "Music", "Location", "Contact"}
	if len(labels) != len(want) {
		t.Fatalf("menu = %v, want %v", labels, want)
	}
	for i := range want {
		if labels[i] != want[i] {
			t.Fatalf("menu = %v, want %v", labels, want)
		}
	}
	for _, ext := range []string{".mp3", ".ogg", ".opus", ".flac", ".m4a"} {
		found := false
		for _, e := range musicExts {
			if e == ext {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("musicExts missing %s", ext)
		}
	}
	for _, ext := range []string{".mp4", ".txt"} {
		for _, e := range musicExts {
			if e == ext {
				t.Errorf("musicExts must not include %s", ext)
			}
		}
	}
}
