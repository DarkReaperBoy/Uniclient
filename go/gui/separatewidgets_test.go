package gui

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestSeparateWindowWidgetsAreNotPackageLevel: BUGS B-47 — separate
// chat windows run their OWN event loop on their OWN goroutine (Root's
// `frameMu` serializes frames, but widget/selection STATE is shared),
// and their draw tree reaches layoutChatView + overlays. A call-graph
// walk from Root's separate branch (1,165 functions) found exactly the
// widgets below reachable among the 258 package-level ones, plus the
// session states used in those paths (reply-keyboard consumption,
// seen-inline last-own, forward selection — the last one also reset by
// ANY window's openChat/openForward, wiping another window's pick).
// All must live on the per-window App ("each window owns its widgets",
// slice 168). This test pins the fix structurally: each name may be
// declared ONLY inside the App struct.
func TestSeparateWindowWidgetsAreNotPackageLevel(t *testing.T) {
	// name → the type token its declaration line must carry.
	targets := [][2]string{
		{"inlineKbdBtns", "widget.Clickable"},
		{"replyKbdBtns", "widget.Clickable"},
		{"musicMenuBtn", "widget.Clickable"},
		{"schedDlgPresets", "widget.Clickable"},
		{"shadowDlgClose", "widget.Clickable"},
		{"shadowDlgUnban", "widget.Clickable"},
		{"replyKbdSingleUse", "bool"},
		{"replyKbdUsedFor", "string"},
		{"msgFrameLastOwn", "string"},
		{"fwdSel", "map[string]bool"},
	}

	appStruct := appStructBody(t)

	entries, err := filepath.Glob("*.go")
	if err != nil {
		t.Fatal(err)
	}
	for _, path := range entries {
		if strings.HasSuffix(path, "_test.go") {
			continue
		}
		data, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		body := string(data)
		for _, tv := range targets {
			name, typ := tv[0], tv[1]
			idx := 0
			for {
				i := strings.Index(body[idx:], name+" ")
				if i < 0 {
					break
				}
				i += idx
				lineStart := strings.LastIndex(body[:i], "\n") + 1
				lineEnd := strings.Index(body[i:], "\n")
				if lineEnd < 0 {
					lineEnd = len(body) - i
				}
				line := body[lineStart : i+lineEnd]
				idx = i + len(name) + 1
				if !strings.Contains(line, typ) {
					continue // not a declaration line (e.g. comment)
				}
				trimmed := strings.TrimSpace(line)
				if strings.Contains(line, "=") && !strings.HasPrefix(trimmed, "var ") {
					continue // an assignment (must be a.-qualified), not a declaration
				}
				if path == "state.go" && strings.Contains(appStruct, line) {
					continue // correctly an App field
				}
				t.Errorf("%s: %q declares %s outside the App struct — separate windows share this state (B-47)",
					path, strings.TrimSpace(line), name)
			}
		}
	}
}

// TestSeenInlineReceiptIsWired: BUGS B-48 — seenInlineGate needs
// isLastOwn, fed from msgFrameLastOwn, which NOTHING ever assigned
// (and the pure helper lastOwnMsgID had zero production callers) — the
// slice-152 inline "Seen" receipt could never render. The unit-tested
// pure layers hid the missing wire (B-12/B-13 class). Pins the
// assignment + the App-scoped read.
func TestSeenInlineReceiptIsWired(t *testing.T) {
	data, err := os.ReadFile("chat.go")
	if err != nil {
		t.Fatal(err)
	}
	body := string(data)
	if !strings.Contains(body, "msgFrameLastOwn = lastOwnMsgID(") {
		t.Error("messageList must set a.msgFrameLastOwn once per pass from the frame's messages (B-48): the inline Seen receipt is dead without it")
	}
	if !strings.Contains(body, "m.MsgID == a.msgFrameLastOwn") {
		t.Error("the receipt gate must read the App-scoped last-own id (B-48/B-47)")
	}
}

// appStructBody extracts the text of `type App struct { ... }`.
func appStructBody(t *testing.T) string {
	t.Helper()
	data, err := os.ReadFile("state.go")
	if err != nil {
		t.Fatal(err)
	}
	body := string(data)
	i := strings.Index(body, "type App struct {")
	if i < 0 {
		t.Fatal("App struct not found in state.go")
	}
	depth := 0
	for j := i; j < len(body); j++ {
		switch body[j] {
		case '{':
			depth++
		case '}':
			depth--
			if depth == 0 {
				return body[i : j+1]
			}
		}
	}
	t.Fatal("App struct braces unbalanced")
	return ""
}
