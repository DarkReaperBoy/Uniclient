package gui

import (
	"strings"
)

// toastXML (slice 200): builds the Windows toast payload — the
// ToastGeneric binding with the sender and message lines, CDATA-escaped
// so message content can never break out of the XML. Pure — locked by
// tests (shared with the windows transport; every platform compiles it
// so the escaping stays pinned in CI on all three build targets).
func toastXML(title, body string) string {
	return "<toast scenario=\"default\" duration=\"short\">" +
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
