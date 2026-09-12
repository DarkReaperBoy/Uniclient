package gui

// Deep links (AyuGram, matrix row 292, slice 95 + 161): tapped t.me /
// tg:// links route INSIDE the app instead of the browser where the app
// can actually act on them — invite links open the join flow, username
// links resolve through the global server search and open the chat, and
// message permalinks (t.me/user/123, t.me/c/1234/567,
// tg://resolve?domain=user&post=123) resolve the chat AND the message:
// the engine fetches the message by id (caching it), the chat opens and
// the view jumps to the message. Topic/comment permalink forms and the
// reserved paths stay on the browser (honest scope). Pure classification
// in deepLinkTarget.

import (
	"strings"

	"uniclient/engine"
)

// deepLinkTarget classifies a tapped URL. kind "invite" carries the
// invite hash; "resolve" a public username; "permalink" a message
// permalink (arg = username or "c/<channelID>", post = the message id);
// "" means "not a routable deep link" (browser path). Pure — locked by
// tests.
func deepLinkTarget(url string) (kind, arg, post string) {
	u := strings.TrimSpace(url)
	if u == "" {
		return "", "", ""
	}
	low := strings.ToLower(u)

	// tg:// scheme: join?invite=hash and resolve?domain=user[&post=123].
	if strings.HasPrefix(low, "tg://") {
		rest := u[len("tg://"):]
		path, query, _ := strings.Cut(rest, "?")
		params := parseQueryPairs(query)
		switch strings.ToLower(path) {
		case "join":
			if h := params["invite"]; h != "" {
				return "invite", h, ""
			}
		case "resolve":
			if d := params["domain"]; d != "" {
				if p := params["post"]; p != "" {
					return "permalink", d, p
				}
				return "resolve", d, ""
			}
		}
		return "", "", ""
	}

	// t.me-style: invite forms go through the shared extractor.
	if h, ok := extractInviteHash(u); ok {
		return "invite", h, ""
	}

	// t.me/<username>[/<msg>] (no reserved prefix): a public
	// profile/channel link, optionally a message permalink.
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
			segs := strings.Split(path, "/")
			// t.me/c/<channelID>/<msg>: internal-id channel permalink.
			if len(segs) >= 3 && segs[0] == "c" && isAllDigits(segs[1]) && isAllDigits(segs[2]) {
				return "permalink", "c/" + segs[1], segs[2]
			}
			if len(segs) == 2 {
				// t.me/<username>/<msg> resolves the chat AND the message;
				// non-numeric message ids are not ours to route.
				if isAllDigits(segs[1]) && segs[0] != "" && !strings.HasPrefix(segs[0], "+") && !reservedTelegramPath(segs[0]) {
					return "permalink", segs[0], segs[1]
				}
				return "", "", ""
			}
			// Topic (t.me/user/<topic>/<msg>) and comment-thread forms
			// stay on the browser — topic-scoped resolution is honest
			// scope-cut (the topic view does not cross-load by message id).
			if len(segs) > 2 {
				return "", "", ""
			}
			name := segs[0]
			if name != "" && !strings.HasPrefix(name, "+") && !reservedTelegramPath(name) {
				return "resolve", name, ""
			}
			return "", "", ""
		}
	}
	return "", "", ""
}

// isAllDigits reports a non-empty all-ASCII-digit string. Pure.
func isAllDigits(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

// permalinkChatID maps a "c/<channelID>" permalink ref onto the engine's
// -100 chat-ID convention; username refs return "". Pure — locked by
// tests.
func permalinkChatID(ref string) string {
	if strings.HasPrefix(ref, "c/") && isAllDigits(ref[2:]) {
		return "-100" + ref[2:]
	}
	return ""
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
	kind, arg, post := deepLinkTarget(url)
	switch kind {
	case "invite":
		a.openInviteJoin(arg)
		return true
	case "resolve":
		a.resolveDeepLinkUser(arg)
		return true
	case "permalink":
		a.resolveDeepLinkPermalink(arg, post)
		return true
	}
	return false
}

// resolveDeepLinkPermalink opens a message permalink (t.me/user/123,
// t.me/c/1234/567, tg://resolve?domain=user&post=123): resolves the chat,
// fetches the message by id through the engine (caching it), then opens
// the chat with a pending jump to the message. Private c/ links only
// work for chats the account already has (honest empty state otherwise).
func (a *App) resolveDeepLinkPermalink(ref, msgID string) {
	acc := inviteScopeAccount(a.snapshotForInvite())
	if acc == "" {
		a.setToast("Connect an account first")
		return
	}

	// c/<channelID> form: the chat must already exist in the account's
	// dialogs (the link carries no access hash to resolve it).
	if chatID := permalinkChatID(ref); chatID != "" {
		a.mu.Lock()
		chats := append([]engine.ChatInfo(nil), a.chats...)
		a.mu.Unlock()
		for _, c := range chats {
			if c.AccountID == acc && c.ChatID == chatID {
				a.openPermalinkTarget(acc, chatID, c.Title, msgID)
				return
			}
		}
		a.setToast("Channel not found in your chats")
		return
	}

	// Username form: global server search, first hit (same as resolve).
	a.setToast("Opening @" + ref)
	go func() {
		hits, err := a.eng.SearchGlobalChats(acc, ref, 5)
		if err != nil || len(hits) == 0 {
			a.setToast("No chat found for @" + ref)
			return
		}
		c := hits[0]
		a.openPermalinkTarget(c.AccountID, c.ChatID, c.Title, msgID)
	}()
}

// openPermalinkTarget loads the message's timestamp (engine caches the
// message on the fetch) and schedules the open + jump on the GUI loop.
func (a *App) openPermalinkTarget(accountID, chatID, title, msgID string) {
	go func() {
		ts, err := a.eng.GetMessageTimestamp(accountID, chatID, msgID)
		if err != nil || ts <= 0 {
			// Still open the chat — the message just isn't resolvable.
			a.mu.Lock()
			k := chatKey{accountID, chatID}
			a.pendingOpen = &k
			a.pendingTitle = title
			a.mu.Unlock()
			a.invalidate()
			return
		}
		a.mu.Lock()
		k := chatKey{accountID, chatID}
		a.pendingOpen = &k
		a.pendingTitle = title
		a.pendingJump = &jumpReq{msgID: msgID, ts: ts}
		a.mu.Unlock()
		a.invalidate()
	}()
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
