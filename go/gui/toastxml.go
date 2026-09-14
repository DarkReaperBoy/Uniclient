package gui

import (
	"hash/fnv"
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
//
// Slice 203: a non-empty image rides the binding as the avatar
// (appLogoOverride — the sender photo slot, tdesktop-like); the audio
// element is silent because the app plays its own synthesized chime
// through the audio backend (slice 121) — without it the platform
// default sound doubles the app's.
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

// toastImageSrc (slice 203): the notify layer passes the avatar as a
// file:// URI whose tail is a plain OS path (backslashes on Windows) —
// the toast wants file:/// + forward slashes. Non-file URIs return ""
// (only local avatar files ride toasts; remote avatars are cached
// locally by the engine's avatar pipeline anyway). Pure.
func toastImageSrc(iconURI string) string {
	if !strings.HasPrefix(iconURI, "file://") {
		return ""
	}
	p := strings.TrimPrefix(iconURI, "file://")
	// file:/// already: keep; file://<path>: add the authority slash.
	if !strings.HasPrefix(p, "/") {
		p = "/" + p
	}
	p = strings.ReplaceAll(p, "\\", "/")
	return "file://" + p
}

// toastTag (slice 203): the per-chat toast replacement tag — a stable
// fnv64a hex digest of the chat key (16 chars, within the platform's
// tag length budget, distinct per chat). With a shared group, a new
// toast for the same chat replaces the previous one in Action Center —
// the slice-141 "banners never stack for one chat" semantics. Pure.
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
