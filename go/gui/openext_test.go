package gui

// OS handoff (slice 86): URL admission, platform command mapping, and the
// openOnDone flow — a tapped download hands its completed file to the
// system player, link taps open the browser with a clipboard fallback.

import (
	"errors"
	"slices"
	"testing"

	"uniclient/engine"
)

func TestSanitizeURL(t *testing.T) {
	ok := []string{
		"https://t.me/ayugram",
		"http://example.com/x?y=1",
		"tg://resolve?domain=durov",
		"  https://example.org  ",
		"HTTPS://UPPER.CASE",
	}
	for _, u := range ok {
		if got, good := sanitizeURL(u); !good || got != trimSpaces(u) {
			t.Errorf("sanitizeURL(%q) = %q, %v; want trimmed URL, true", u, got, good)
		}
	}
	bad := []string{"", "javascript:alert(1)", "file:///etc/passwd", "example.com", "mailto:a@b.c", "  "}
	for _, u := range bad {
		if _, good := sanitizeURL(u); good {
			t.Errorf("sanitizeURL(%q) = true, want false", u)
		}
	}
}

func trimSpaces(s string) string {
	out := make([]rune, 0, len(s))
	for _, r := range s {
		if r != ' ' && r != '\t' && r != '\n' {
			out = append(out, r)
		}
	}
	return string(out)
}

func TestOpenArgsFor(t *testing.T) {
	cases := []struct {
		goos  string
		prog  string
		first string
	}{
		{"linux", "xdg-open", "/tmp/a.mp4"},
		{"darwin", "open", "/tmp/a.mp4"},
		{"windows", "rundll32", "url.dll,FileProtocolHandler"},
		{"plan9", "", ""},
	}
	for _, c := range cases {
		prog, args := openArgsFor(c.goos, "/tmp/a.mp4")
		if prog != c.prog {
			t.Errorf("openArgsFor(%s) prog = %q, want %q", c.goos, prog, c.prog)
			continue
		}
		if prog == "" {
			continue
		}
		if args[0] != c.first {
			t.Errorf("openArgsFor(%s) args[0] = %q, want %q", c.goos, args[0], c.first)
		}
		if c.goos != "windows" && !slices.Contains(args, "/tmp/a.mp4") {
			t.Errorf("openArgsFor(%s) must pass the target: %v", c.goos, args)
		}
	}
}

func TestRevealArgsFor(t *testing.T) {
	if prog, args := revealArgsFor("linux", "/dl/a.mp4"); prog != "xdg-open" || args[0] != "/dl" {
		t.Errorf("linux reveal = %q %v, want xdg-open /dl", prog, args)
	}
	if prog, args := revealArgsFor("darwin", "/dl/a.mp4"); prog != "open" || args[0] != "-R" || args[1] != "/dl/a.mp4" {
		t.Errorf("darwin reveal = %q %v, want open -R <path>", prog, args)
	}
	if prog, args := revealArgsFor("windows", `C:\dl\a.mp4`); prog != "explorer" || args[0] != `/select,C:\dl\a.mp4` {
		t.Errorf("windows reveal = %q %v, want explorer /select,<path>", prog, args)
	}
	if prog, _ := revealArgsFor("plan9", "/dl/a.mp4"); prog != "" {
		t.Errorf("unsupported goos reveal = %q, want empty", prog)
	}
}

// TestOpenOnDoneFlow: mark → complete → exactly one open call, then the
// mark is spent (a second completion opens nothing).
func TestOpenOnDoneFlow(t *testing.T) {
	a := &App{}
	var opened []string
	var errToReturn error
	openExternalAsync = func(target string, done func(error)) {
		opened = append(opened, target)
		if done != nil {
			done(errToReturn)
		}
	}
	t.Cleanup(func() {
		openExternalAsync = func(string, func(error)) {}
	})

	a.setOpenOnDone("acct", "chat", "42", 0)
	if !a.consumeOpenOnDone("acct", "chat", "42", 0) {
		t.Fatal("consume after set = false, want true")
	}
	if a.consumeOpenOnDone("acct", "chat", "42", 0) {
		t.Error("second consume = true, want false (one-shot)")
	}

	// Full event path: mark again, deliver completion, assert the open.
	a.setOpenOnDone("acct", "chat", "43", 0)
	a.onDownloadComplete(engine.DownloadCompleteEvent{
		AccountID: "acct", ChatID: "chat", MsgID: "43", Seq: 0, LocalPath: "/dl/43.ogg",
	})
	if len(opened) != 1 || opened[0] != "/dl/43.ogg" {
		t.Fatalf("opened = %v, want [/dl/43.ogg]", opened)
	}
	if a.toast != "Playing in system player" {
		t.Errorf("toast = %q, want the playing toast", a.toast)
	}
	// The mark was consumed: a redelivery opens nothing.
	a.onDownloadComplete(engine.DownloadCompleteEvent{
		AccountID: "acct", ChatID: "chat", MsgID: "43", Seq: 0, LocalPath: "/dl/43.ogg",
	})
	if len(opened) != 1 {
		t.Errorf("opened = %v after redelivery, want still one entry", opened)
	}
	// Unmarked downloads never hand off (photos keep the viewer path).
	a.onDownloadComplete(engine.DownloadCompleteEvent{
		AccountID: "acct", ChatID: "chat", MsgID: "44", Seq: 0, LocalPath: "/dl/44.jpg",
	})
	if len(opened) != 1 {
		t.Errorf("unmarked completion opened %v, want none", opened)
	}
	// Opener failure is reported honestly.
	errToReturn = errors.New("no handler")
	a.setOpenOnDone("acct", "chat", "45", 0)
	a.onDownloadComplete(engine.DownloadCompleteEvent{
		AccountID: "acct", ChatID: "chat", MsgID: "45", Seq: 0, LocalPath: "/dl/45.ogg",
	})
	if a.toast != "Open failed: no handler" {
		t.Errorf("failure toast = %q, want Open failed: no handler", a.toast)
	}
}

// TestOpenLinkExternal: http links go to the opener; opener failure and
// non-http schemes fall back to the clipboard copy.
func TestOpenLinkExternal(t *testing.T) {
	a := &App{}
	var targets []string
	fail := false
	openExternalAsync = func(target string, done func(error)) {
		targets = append(targets, target)
		if done != nil {
			if fail {
				done(errors.New("no opener"))
			} else {
				done(nil)
			}
		}
	}
	t.Cleanup(func() {
		openExternalAsync = func(string, func(error)) {}
	})

	a.openLinkExternal("https://example.com/ayugram")
	if len(targets) != 1 || targets[0] != "https://example.com/ayugram" {
		t.Fatalf("targets = %v, want the URL once", targets)
	}
	if a.toast != "Opened in browser" {
		t.Errorf("toast = %q, want Opened in browser", a.toast)
	}

	// slice 95: deep links route INSIDE — a t.me username link resolves
	// through the global search (no account here → honest toast, and the
	// browser opener must NOT have been attempted).
	a.openLinkExternal("https://t.me/ayugram")
	if len(targets) != 1 {
		t.Fatalf("deep link went to the browser: %v", targets)
	}
	if a.toast != "Connect an account first" {
		t.Errorf("toast = %q, want Connect an account first", a.toast)
	}
	// Invite links open the join flow (same honest no-account path).
	a.openLinkExternal("https://t.me/+AbCdEf12345")
	if len(targets) != 1 {
		t.Fatalf("invite link went to the browser: %v", targets)
	}
	if a.inviteDlg != nil {
		t.Errorf("inviteDlg = %+v, want cleared on no-account", a.inviteDlg)
	}

	fail = true
	a.openLinkExternal("http://example.com")
	if a.pendingCopy != "http://example.com" {
		t.Errorf("pendingCopy = %q, want the URL on opener failure", a.pendingCopy)
	}

	a.openLinkExternal("javascript:alert(1)")
	if a.pendingCopy != "javascript:alert(1)" {
		t.Errorf("pendingCopy = %q, want the raw URL for non-http schemes", a.pendingCopy)
	}
}

// TestRevealMedia: reveal failures and successes toast honestly.
func TestRevealMedia(t *testing.T) {
	a := &App{}
	revealAsync = func(path string, done func(error)) {
		if done != nil {
			done(errors.New("no file manager"))
		}
	}
	t.Cleanup(func() {
		revealAsync = func(string, func(error)) {}
	})
	a.revealMedia("/dl/a.mp4")
	if a.toast != "Reveal failed: no file manager" {
		t.Errorf("toast = %q, want reveal failure", a.toast)
	}
	a.revealMedia("") // no-op, no panic
}

// TestShowInFolderMenuAction: a message with a local file gains the OS
// integration row; without one, no row.
func TestShowInFolderMenuAction(t *testing.T) {
	a := &App{}
	m := engine.CachedMessage{
		AccountID: "acct", ChatID: "chat", MsgID: "7", IsOutgoing: true,
		MediaType: engine.MediaFile, MediaLocalPath: "/dl/7.bin",
	}
	f := frame{menu: &menuTarget{msg: m}}
	items := a.menuActionsFor(f, m)
	found := false
	for _, it := range items {
		if it.label == "Show in Folder" {
			found = true
		}
	}
	if !found {
		t.Errorf("Show in Folder missing for a downloaded file; items: %v", menuLabels(items))
	}
	// No local file → no row.
	m.MediaLocalPath = ""
	f2 := frame{menu: &menuTarget{msg: m}}
	for _, it := range a.menuActionsFor(f2, m) {
		if it.label == "Show in Folder" {
			t.Error("Show in Folder present without a local file")
		}
	}
}

func menuLabels(items []menuAction) []string {
	out := make([]string, 0, len(items))
	for _, it := range items {
		out = append(out, it.label)
	}
	return out
}
