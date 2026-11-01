package gui

import (
	"strings"
	"testing"
)

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
	if strings.Contains(rest[:j], `"1&2`) {
		t.Errorf("launch attribute not escaped: %q", x)
	}
}

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

func TestXMLAttrEscape(t *testing.T) {
	if got := xmlAttrEscape(`a&b<c>d"e`); got != "a&amp;b&lt;c&gt;d&quot;e" {
		t.Errorf("xmlAttrEscape = %q", got)
	}
	if got := xmlAttrEscape("plain"); got != "plain" {
		t.Errorf("plain changed: %q", got)
	}
}
