package gui

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestSeparateWindowWidgetsAreNotPackageLevel(t *testing.T) {
	if runtime.GOOS == "js" {
		t.Skip("source files are unreachable on js/wasm (no filesystem by design)")
	}
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
					continue
				}
				trimmed := strings.TrimSpace(line)
				if strings.Contains(line, "=") && !strings.HasPrefix(trimmed, "var ") {
					continue
				}
				if path == "state.go" && strings.Contains(appStruct, line) {
					continue
				}
				t.Errorf("%s: %q declares %s outside the App struct — separate windows share this state (B-47)",
					path, strings.TrimSpace(line), name)
			}
		}
	}
}

func TestSeenInlineReceiptIsWired(t *testing.T) {
	if runtime.GOOS == "js" {
		t.Skip("source files are unreachable on js/wasm (no filesystem by design)")
	}
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
