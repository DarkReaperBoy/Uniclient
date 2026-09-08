package gui

import "testing"

func TestIsPanelSubCount(t *testing.T) {
	safe := []string{"channel", "1 member", "128 members, 12 online", "online", "members"}
	for _, s := range safe {
		if !isPanelSubCount(s) {
			t.Errorf("%q should be streamer-safe", s)
		}
	}
	unsafe := []string{"last seen 5 minutes ago", "typing…", "@darkreaperboy"}
	for _, s := range unsafe {
		if isPanelSubCount(s) {
			t.Errorf("%q leaks identity and must be masked", s)
		}
	}
}
