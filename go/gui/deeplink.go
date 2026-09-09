package gui

// Deep links (AyuGram, matrix row 292, slice 95): tapped t.me / tg://
// links route INSIDE the app instead of the browser where the app can
// actually act on them — invite links open the join flow, username
// links resolve through the global server search and open the chat.
// Permalink forms with message ids (t.me/user/123, t.me/c/…) still go
// to the browser: resolving them needs a server message lookup the
// engine does not expose. Pure classification in deepLinkTarget.

import (
	"strings"
)

// deepLinkTarget classifies a tapped URL. kind "invite" carries the
// invite hash; "resolve" a public username; "" means "not a routable
// deep link" (browser path). Pure — locked by tests.
func deepLinkTarget(url string) (kind, arg string) {
	u := strings.TrimSpace(url)
	if u == "" {
		return "", ""
	}
	low := strings.ToLower(u)

	// tg:// scheme: join?invite=hash and resolve?domain=user.
	if strings.HasPrefix(low, "tg://") {
		rest := u[len("tg://"):]
		path, query, _ := strings.Cut(rest, "?")
		params := parseQueryPairs(query)
		switch strings.ToLower(path) {
		case "join":
			if h := params["invite"]; h != "" {
				return "invite", h
			}
		case "resolve":
			if d := params["domain"]; d != "" {
				return "resolve", d
			}
		}
		return "", ""
	}

	// t.me-style: invite forms go through the shared extractor.
	if h, ok := extractInviteHash(u); ok {
		return "invite", h
	}

	// t.me/<username> (single path segment, no reserved prefix):
	// a public profile/channel link.
	stripped := u
	low2 := low
	for _, pre := range []string{"https://", "http://", "www."} {
		if strings.HasPrefix(low2, pre) {
			low2 = low2[len(pre):]
			stripped = stripped[len(pre):]
		}
	}
	for _, d := range []string{"t.me/", "telegram.me/", "telegram.dog/"} {
		if strings.HasPrefix(low2, d) {
			path := stripped[len(d):]
			name, rest, _ := strings.Cut(path, "/")
			// Message-permalink / topic forms (t.me/user/123) need a
			// server message lookup the engine does not expose → browser.
			if rest != "" {
				return "", ""
			}
			if name != "" && !strings.HasPrefix(name, "+") && !reservedTelegramPath(name) {
				return "resolve", name
			}
			return "", ""
		}
	}
	return "", ""
}

// reservedTelegramPath lists t.me path prefixes that are NOT usernames.
func reservedTelegramPath(seg string) bool {
	switch seg {
	case "joinchat", "c", "s", "addstickers", "addemoji", "share", "login",
		"contact", "confirm", "socks", "proxy", "boost", "invoice", "giftcode":
		return true
	}
	return false
}

// parseQueryPairs parses a URL query into key→value (last wins).
// Pure.
func parseQueryPairs(query string) map[string]string {
	out := map[string]string{}
	for _, kv := range strings.Split(query, "&") {
		if kv == "" {
			continue
		}
		k, v, _ := strings.Cut(kv, "=")
		out[k] = v
	}
	return out
}

// tryDeepLink routes a tapped link internally when the app can act on
// it. Returns true when handled (caller skips the browser path).
// GUI-loop only (opens dialogs / chats).
func (a *App) tryDeepLink(url string) bool {
	kind, arg := deepLinkTarget(url)
	switch kind {
	case "invite":
		a.openInviteJoin(arg)
		return true
	case "resolve":
		a.resolveDeepLinkUser(arg)
		return true
	}
	return false
}

// resolveDeepLinkUser opens a public username link: global search on
// the active account, first hit schedules the chat open (the GUI loop's
// consumePendingOpen hop — openChat touches the composer editor and
// must not run from this goroutine).
func (a *App) resolveDeepLinkUser(name string) {
	acc := inviteScopeAccount(a.snapshotForInvite())
	if acc == "" {
		a.setToast("Connect an account first")
		return
	}
	a.setToast("Opening @" + name)
	go func() {
		hits, err := a.eng.SearchGlobalChats(acc, name, 5)
		if err != nil || len(hits) == 0 {
			a.setToast("No chat found for @" + name)
			return
		}
		c := hits[0]
		k := chatKey{AccountID: c.AccountID, ChatID: c.ChatID}
		a.mu.Lock()
		a.pendingOpen = &k
		a.pendingTitle = c.Title
		a.mu.Unlock()
		a.invalidate()
	}()
}
