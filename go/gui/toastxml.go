package gui

import (
	"hash/fnv"
	"strings"
)

func toastXML(title, body, launch, image string) string {
	attrs := ""
	if launch != "" {
		attrs = " activationType=\"protocol\" launch=\"" + xmlAttrEscape(launch) + "\""
	}
	img := ""
	if image != "" {
		img = "<image placement=\"appLogoOverride\" src=\"" + xmlAttrEscape(image) + "\"/>"
	}
	return "<toast scenario=\"default\" duration=\"short\"" + attrs + ">" +
		"<visual><binding template=\"ToastGeneric\">" + img +
		"<text><![CDATA[" + cdataSafe(title) + "]]></text>" +
		"<text><![CDATA[" + cdataSafe(body) + "]]></text>" +
		"</binding></visual>" +
		"<audio silent=\"true\"/>" +
		"</toast>"
}

func cdataSafe(s string) string {
	if !strings.Contains(s, "]]>") {
		return s
	}
	return strings.ReplaceAll(s, "]]>", "]] >")
}

func xmlAttrEscape(s string) string {
	if !strings.ContainsAny(s, `&<>"`) {
		return s
	}
	var b strings.Builder
	for _, r := range s {
		switch r {
		case '&':
			b.WriteString("&amp;")
		case '<':
			b.WriteString("&lt;")
		case '>':
			b.WriteString("&gt;")
		case '"':
			b.WriteString("&quot;")
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

func toastImageSrc(iconURI string) string {
	if !strings.HasPrefix(iconURI, "file://") {
		return ""
	}
	p := strings.TrimPrefix(iconURI, "file://")
	if !strings.HasPrefix(p, "/") {
		p = "/" + p
	}
	p = strings.ReplaceAll(p, "\\", "/")
	return "file://" + p
}

func toastTag(key string) string {
	h := fnv.New64a()
	h.Write([]byte(key))
	const hexdigits = "0123456789abcdef"
	v := h.Sum64()
	buf := make([]byte, 16)
	for i := 15; i >= 0; i-- {
		buf[i] = hexdigits[v&0xf]
		v >>= 4
	}
	return string(buf)
}
