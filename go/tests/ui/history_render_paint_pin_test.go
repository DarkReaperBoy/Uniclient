package tests

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func painterFuncBody(t *testing.T, src, name string) string {
	t.Helper()
	i := strings.Index(src, name)
	if i < 0 {
		t.Fatalf("%s not found in the painter source", name)
	}
	body := src[i:]
	if j := strings.Index(body[len(name):], "\nfunc "); j >= 0 {
		body = body[:len(name)+j+1]
	}
	return body
}

func TestChatPanePainterCallsComposeBar(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "ui", "history", "render", "painter.go"))
	if err != nil {
		t.Fatalf("read painter.go: %v", err)
	}
	body := painterFuncBody(t, string(raw), "func (p *ChatPainter) PaintChatPane(")
	if !strings.Contains(body, "p.PaintComposeBar(") {
		t.Fatalf("PaintChatPane must paint the compose bar (the W-2 zero-caller seam: the field would be invisible while typing works)")
	}
}
