package gui

import (
	"strings"
	"testing"
)

// ── Send message with (tdesktop Messages setting) ────────────────────────

func TestComposerSubmitSends(t *testing.T) {
	// tdesktop default: Enter submits (Shift+Enter newline).
	if !composerSubmitSends("") {
		t.Error("empty mode: Enter should submit (tdesktop default)")
	}
	if !composerSubmitSends("enter") {
		t.Error("enter mode: Enter should submit")
	}
	if composerSubmitSends("ctrl-enter") {
		t.Error("ctrl-enter mode: Enter should NOT submit (Ctrl+Enter does)")
	}
}

// ── Ayu improve link previews ─────────────────────────────────────────────

func TestImproveLinkHostRewrite(t *testing.T) {
	cases := map[string]string{
		"twitter.com":         "fixupx.com",
		"www.twitter.com":     "fixupx.com",
		"x.com":               "fixupx.com",
		"www.x.com":           "fixupx.com",
		"tiktok.com":          "kktiktok.com",
		"vm.tiktok.com":       "vm.kktiktok.com",
		"reddit.com":          "vxreddit.com",
		"www.reddit.com":      "vxreddit.com",
		"instagram.com":       "kkclip.com",
		"www.instagram.com":   "kkclip.com",
		"pixiv.net":           "phixiv.net",
		"www.pixiv.net":       "phixiv.net",
		"example.com":         "",
		"api.twitter.com":     "",
		"nottwitter.com":      "",
		"twITTER.com":         "fixupx.com",
		"old.reddit.com":      "",
		"subdomain.pixiv.net": "",
		"google.com":          "",
		"github.com":          "",
	}
	for host, want := range cases {
		if got := improveLinkHost(host); got != want {
			t.Errorf("improveLinkHost(%q) = %q, want %q", host, got, want)
		}
	}
}

func TestImproveLinkURLs(t *testing.T) {
	// Path and query survive; only the host swaps (Ayu getBetterLinkPreview).
	in := "check https://twitter.com/durov/status/123?x=1 and http://www.reddit.com/r/golang top"
	out := improveLinkURLs(in)
	if !strings.Contains(out, "https://fixupx.com/durov/status/123?x=1") {
		t.Errorf("twitter rewrite missing: %q", out)
	}
	if !strings.Contains(out, "http://vxreddit.com/r/golang") {
		t.Errorf("reddit rewrite missing: %q", out)
	}
	if strings.Contains(out, "twitter.com/") || strings.Contains(out, "://reddit.com") || strings.Contains(out, "://www.reddit.com") {
		t.Errorf("original hosts must be gone: %q", out)
	}
}

func TestImproveLinkURLsLeavesOthers(t *testing.T) {
	in := "no links here, see https://example.com/a and www.google.com mailto:x@y.z"
	if out := improveLinkURLs(in); out != in {
		t.Errorf("untouched text changed: %q", out)
	}
}

func TestImproveLinkURLsPlainText(t *testing.T) {
	if out := improveLinkURLs("just words"); out != "just words" {
		t.Errorf("plain text changed: %q", out)
	}
	if out := improveLinkURLs(""); out != "" {
		t.Errorf("empty changed: %q", out)
	}
}

func TestImproveLinkURLsMultipleAndMixedCase(t *testing.T) {
	out := improveLinkURLs("https://X.com/a https://WWW.INSTAGRAM.COM/p/1")
	if !strings.Contains(out, "https://fixupx.com/a") {
		t.Errorf("case-insensitive x.com rewrite missing: %q", out)
	}
	if !strings.Contains(out, "https://kkclip.com/p/1") {
		t.Errorf("instagram rewrite missing (scheme case preserved is fine): %q", out)
	}
}

// configFieldChanges covers the new Ayu toggle key.
func TestConfigFieldChangesImproveLinkPreviews(t *testing.T) {
	c := configFieldChanges("ayu_improve_link_previews", true)
	if c == nil || c.AyuImproveLinkPreviews == nil || !*c.AyuImproveLinkPreviews {
		t.Fatal("ayu_improve_link_previews(true): missing change")
	}
	c = configFieldChanges("ayu_improve_link_previews", false)
	if c == nil || c.AyuImproveLinkPreviews == nil || *c.AyuImproveLinkPreviews {
		t.Fatal("ayu_improve_link_previews(false): missing change")
	}
}

func TestComposerSubmitLabel(t *testing.T) {
	if got := composerSubmitLabel(""); got != "Enter" {
		t.Errorf("label(\"\") = %q, want Enter", got)
	}
	if got := composerSubmitLabel("ctrl-enter"); got != "Ctrl+Enter" {
		t.Errorf("label(ctrl-enter) = %q, want Ctrl+Enter", got)
	}
}
