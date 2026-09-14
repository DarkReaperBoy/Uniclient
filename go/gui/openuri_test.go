package gui

import (
	"strings"
	"testing"
)

// TestSplitNotifyKey (slice 202): the throttle key round-trips into the
// account/chat pair the launch URI needs.
func TestSplitNotifyKey(t *testing.T) {
	acc, chat, ok := splitNotifyKey("tg_a1b2c3d4/777000")
	if !ok || acc != "tg_a1b2c3d4" || chat != "777000" {
		t.Errorf("splitNotifyKey = %q %q %v", acc, chat, ok)
	}
	for _, bad := range []string{"", "noSlash", "acc/", "/chat"} {
		if _, _, ok := splitNotifyKey(bad); ok {
			t.Errorf("splitNotifyKey(%q) accepted", bad)
		}
	}
}

// TestOpenURIRoundTrip (slice 202): build → parse returns exactly the
// account/chat pair, including ids that carry reserved characters
// (Matrix room ids, IRC channel names, anything with spaces or &).
func TestOpenURIRoundTrip(t *testing.T) {
	cases := [][2]string{
		{"tg_a1b2c3d4", "777000"},
		{"xmpp_e9f1", "!room@conference.jabber.cz"},
		{"irc_11aa", "##off-topic"},
		{"matrix_0011", "#general:matrix.org"},
		{"a b&c", "chat with spaces & symbols"},
	}
	for _, c := range cases {
		uri := buildOpenURI(c[0], c[1])
		if !strings.HasPrefix(uri, "uniclient://open?acc=") {
			t.Errorf("buildOpenURI prefix wrong: %q", uri)
		}
		if strings.ContainsAny(strings.SplitN(uri, "?", 2)[1], " ") {
			t.Errorf("URI contains spaces (not shell/wire safe): %q", uri)
		}
		acc, chat, ok := parseOpenURI(uri)
		if !ok || acc != c[0] || chat != c[1] {
			t.Errorf("round trip %q → (%q,%q,%v), want (%q,%q)", uri, acc, chat, ok, c[0], c[1])
		}
	}
}

// TestOpenURIParseRejects (slice 202): anything that is not our open
// command is rejected — other schemes, other paths, missing params.
func TestOpenURIParseRejects(t *testing.T) {
	for _, bad := range []string{
		"", "http://x", "tg://resolve?domain=a", "uniclient://",
		"uniclient://other?acc=a&chat=b", "uniclient://open",
		"uniclient://open?acc=a", "uniclient://open?chat=b",
	} {
		if _, _, ok := parseOpenURI(bad); ok {
			t.Errorf("parseOpenURI(%q) accepted", bad)
		}
		if isLaunchURI(bad) {
			t.Errorf("isLaunchURI(%q) accepted", bad)
		}
	}
}
