package gui

// openuri.go (slice 202) — the app's own launch URI, the click-through
// surface for Windows toast notifications: the toast XML carries
// activationType="protocol" launch="uniclient://open?acc=…&chat=…", the
// per-user protocol registration (instance_windows.go) maps the scheme
// to the binary, and a second process started by the shell forwards the
// open to the running instance (or routes it after a fresh boot). Pure
// — locked by tests on every platform; only the Windows transport and
// instance plumbing are platform code.

import (
	"net/url"
	"strings"
)

// openURIScheme is the URL scheme the app registers for protocol
// activation.
const openURIScheme = "uniclient"

// buildOpenURI encodes an open-this-chat command as
// uniclient://open?acc=<escaped>&chat=<escaped>. Account and chat ids
// are query-escaped so the URI is a single shell-safe token with no
// spaces or separators (the instance wire line is space-separated).
func buildOpenURI(acc, chat string) string {
	return openURIScheme + "://open?acc=" + url.QueryEscape(acc) +
		"&chat=" + url.QueryEscape(chat)
}

// parseOpenURI extracts the account/chat pair from a uniclient://open
// URI (the launcher arg or the forwarded line's payload). ok is false
// for any other URI — never a guess.
func parseOpenURI(uri string) (acc, chat string, ok bool) {
	u := strings.TrimSpace(uri)
	low := strings.ToLower(u)
	if !strings.HasPrefix(low, openURIScheme+"://") {
		return "", "", false
	}
	rest := u[len(openURIScheme)+3:]
	path, query, _ := strings.Cut(rest, "?")
	if !strings.EqualFold(path, "open") {
		return "", "", false
	}
	params := parseQueryPairs(query)
	acc, chat = params["acc"], params["chat"]
	if acc == "" || chat == "" {
		return "", "", false
	}
	if a, err := url.QueryUnescape(acc); err == nil {
		acc = a
	}
	if c, err := url.QueryUnescape(chat); err == nil {
		chat = c
	}
	return acc, chat, true
}

// isLaunchURI reports whether arg is one of our launch URIs (the
// launcher-side classifier: strict prefix + scheme path shape).
func isLaunchURI(arg string) bool {
	_, _, ok := parseOpenURI(arg)
	return ok
}

// splitNotifyKey splits the notification throttle key back into its
// account/chat pair (built as AccountID + "/" + ChatID — engine account
// ids are platform-prefixed hex, never containing "/").
func splitNotifyKey(key string) (acc, chat string, ok bool) {
	acc, chat, found := strings.Cut(key, "/")
	if !found || acc == "" || chat == "" {
		return "", "", false
	}
	return acc, chat, true
}
