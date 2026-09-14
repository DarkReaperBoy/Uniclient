package gui

import (
	"strings"
	"testing"
)

// TestToastXML (slice 200): the Windows toast payload — template shape,
// both text lines, CDATA escaping that can never break out.
func TestToastXML(t *testing.T) {
	x := toastXML("Alice", "hello there", "", "")
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
	if strings.Contains(x, "<image") {
		t.Errorf("no image → no image element: %q", x)
	}
}

// TestToastXMLCdataEscape: a message containing the CDATA terminator
// cannot break out of its section.
func TestToastXMLCdataEscape(t *testing.T) {
	x := toastXML("Evil", "]]><text>injected</text>", "", "")
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
	x := toastXML("Alice", "hi", buildOpenURI("acc1", "chat\"1&2"), "")
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

// TestToastXMLImage (slice 203): a non-empty image rides the binding
// as the appLogoOverride (the sender avatar slot), attribute-escaped,
// before the text lines.
func TestToastXMLImage(t *testing.T) {
	x := toastXML("Alice", "hi", "", "file:///C:/Users/o/.uniclient/avatars/a\"1.png")
	i := strings.Index(x, "<image ")
	if i < 0 {
		t.Fatalf("missing image element: %q", x)
	}
	if !strings.Contains(x, `placement="appLogoOverride"`) {
		t.Errorf("image not in the avatar slot: %q", x)
	}
	j := strings.Index(x, `src="`)
	if j < i || j > i+40 {
		t.Errorf("src attribute not inside the image element: %q", x)
	}
	if strings.Contains(x, "a\"1.png") {
		t.Errorf("image src not escaped: %q", x)
	}
	if k := strings.Index(x, "<text>"); k > -1 && k < i {
		t.Errorf("image element must precede the text lines: %q", x)
	}
}

// TestToastXMLAudio (slice 203): the toast is silent — the app plays its
// own synthesized chime through the audio backend (slice 121); without
// this the platform default sound doubles it.
func TestToastXMLAudio(t *testing.T) {
	x := toastXML("Alice", "hi", "", "")
	if !strings.Contains(x, "<audio silent=\"true\"/>") {
		t.Errorf("missing silent audio element: %q", x)
	}
	vi := strings.Index(x, "</visual>")
	ai := strings.Index(x, "<audio")
	if vi < 0 || ai < vi {
		t.Errorf("audio element must follow the visual: %q", x)
	}
	if !strings.HasSuffix(x, "</toast>") {
		t.Errorf("document shape broken: %q", x)
	}
}

// TestToastImageSrc (slice 203): the notify-layer file:// icon URI (a
// plain OS path after the scheme, possibly with backslashes) becomes a
// proper file:/// toast src; non-file URIs are dropped (only local
// avatars ride toasts).
func TestToastImageSrc(t *testing.T) {
	if got := toastImageSrc("file://C:\\Users\\o\\av.png"); got != "file:///C:/Users/o/av.png" {
		t.Errorf("toastImageSrc(backslash) = %q", got)
	}
	if got := toastImageSrc("file:///home/o/av.png"); got != "file:///home/o/av.png" {
		t.Errorf("toastImageSrc(posix) = %q", got)
	}
	if got := toastImageSrc(""); got != "" {
		t.Errorf("toastImageSrc(empty) = %q", got)
	}
	if got := toastImageSrc("https://example.com/a.png"); got != "" {
		t.Errorf("toastImageSrc(http) = %q, want empty", got)
	}
}

// TestToastTag (slice 203): the per-chat replacement tag — stable, ≤16
// characters, distinct per chat.
func TestToastTag(t *testing.T) {
	a := toastTag("acc1/chat1")
	b := toastTag("acc1/chat2")
	if a == b {
		t.Fatalf("tags collide: %q", a)
	}
	if a != toastTag("acc1/chat1") {
		t.Errorf("tag not stable: %q vs %q", a, toastTag("acc1/chat1"))
	}
	if len(a) > 16 {
		t.Errorf("tag %q longer than 16 chars", a)
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
