package gui

import (
	"strings"
)

// toastXML (slice 200): builds the Windows toast payload — the
// ToastGeneric binding with the sender and message lines, CDATA-escaped
// so message content can never break out of the XML. Pure — locked by
// tests (shared with the windows transport; every platform compiles it
// so the escaping stays pinned in CI on all three build targets).
//
// Slice 202: a non-empty launch URI adds activationType="protocol" +
// launch="…" — clicking the toast activates our uniclient:// scheme
// (per-user registration, instance_windows.go), the single-binary
// click-through path (the COM activator alternative needs a separate
// in-proc DLL, banned by §1.3).
func toastXML(title, body, launch string) string {
	attrs := ""
	if launch != "" {
		attrs = " activationType=\"protocol\" launch=\"" + xmlAttrEscape(launch) + "\""
	}
	return "<toast scenario=\"default\" duration=\"short\"" + attrs + ">" +
		"<visual><binding template=\"ToastGeneric\">" +
		"<text><![CDATA[" + cdataSafe(title) + "]]></text>" +
		"<text><![CDATA[" + cdataSafe(body) + "]]></text>" +
		"</binding></visual></toast>"
}

// cdataSafe neutralizes CDATA terminators inside user text. Pure.
func cdataSafe(s string) string {
	if !strings.Contains(s, "]]>") {
		return s
	}
	return strings.ReplaceAll(s, "]]>", "]] >")
}

// xmlAttrEscape (slice 202): escapes a value for a double-quoted XML
// attribute — the launch URI carries user-controlled ids, so & < > "
// must be neutralized. Pure.
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
