package gui

import (
	"strings"
	"testing"
)

// TestToastXML (slice 200): the Windows toast payload — template shape,
// both text lines, CDATA escaping that can never break out.
func TestToastXML(t *testing.T) {
	x := toastXML("Alice", "hello there", "")
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
	if strings.Contains(x, "activationType") {
		t.Errorf("no launch → no activation attributes: %q", x)
	}
}

// TestToastXMLCdataEscape: a message containing the CDATA terminator
// cannot break out of its section.
func TestToastXMLCdataEscape(t *testing.T) {
	x := toastXML("Evil", "]]><text>injected</text>", "")
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

// TestToastXMLLaunch (slice 202): a launch URI rides the toast element
// as protocol activation — and attribute-escaped, so ids carrying
// reserved characters cannot break the attribute open.
func TestToastXMLLaunch(t *testing.T) {
	x := toastXML("Alice", "hi", buildOpenURI("acc1", "chat\"1&2"))
	if !strings.Contains(x, `activationType="protocol"`) {
		t.Errorf("missing protocol activation: %q", x)
	}
	i := strings.Index(x, `launch="`)
	if i < 0 {
		t.Fatalf("missing launch attribute: %q", x)
	}
	rest := x[i+len(`launch="`):]
	j := strings.Index(rest, `"`)
	if j < 0 {
		t.Fatalf("launch attribute not closed: %q", x)
	}
	if got := rest[:j]; got != "uniclient://open?acc=acc1&amp;chat=chat%221%262" {
		t.Errorf("launch attribute = %q", got)
	}
	// The raw (escaped-unsafe) characters never appear inside the
	// attribute value itself.
	if strings.Contains(rest[:j], `"1&2`) {
		t.Errorf("launch attribute not escaped: %q", x)
	}
}

// TestXMLAttrEscape (slice 202): every XML-special rune is escaped,
// plain text untouched.
func TestXMLAttrEscape(t *testing.T) {
	if got := xmlAttrEscape(`a&b<c>d"e`); got != "a&amp;b&lt;c&gt;d&quot;e" {
		t.Errorf("xmlAttrEscape = %q", got)
	}
	if got := xmlAttrEscape("plain"); got != "plain" {
		t.Errorf("plain changed: %q", got)
	}
}
