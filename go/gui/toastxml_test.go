package gui

import (
	"strings"
	"testing"
)

// TestToastXML (slice 200): the Windows toast payload — template shape,
// both text lines, CDATA escaping that can never break out.
func TestToastXML(t *testing.T) {
	x := toastXML("Alice", "hello there")
	if !strings.Contains(x, `template="ToastGeneric"`) {
		t.Errorf("missing ToastGeneric binding: %q", x)
	}
	if !strings.Contains(x, "<![CDATA[Alice]]>") {
		t.Errorf("missing title line: %q", x)
	}
	if !strings.Contains(x, "<![CDATA[hello there]]>") {
		t.Errorf("missing body line: %q", x)
	}
	if !strings.HasPrefix(x, "<toast") || !strings.HasSuffix(x, "</toast>") {
		t.Errorf("not a toast document: %q", x)
	}
}

// TestToastXMLCdataEscape: a message containing the CDATA terminator
// cannot break out of its section.
func TestToastXMLCdataEscape(t *testing.T) {
	x := toastXML("Evil", "]]><text>injected</text>")
	if strings.Contains(x, "]]><text>") {
		t.Fatalf("CDATA terminator not neutralized: %q", x)
	}
	if got := cdataSafe("]]>"); got != "]] >" {
		t.Errorf("cdataSafe terminator = %q, want ]] >", got)
	}
	if got := cdataSafe("plain"); got != "plain" {
		t.Errorf("plain text changed: %q", got)
	}
}
