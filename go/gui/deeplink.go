package gui

// Deep links (AyuGram, matrix row 292, slice 95 + 161): tapped t.me /
// tg:// links route INSIDE the app instead of the browser where the app
// can actually act on them — invite links open the join flow, username
// links resolve through the global server search and open the chat, and
// message permalinks (t.me/user/123, t.me/c/1234/567,
// tg://resolve?domain=user&post=123) resolve the chat AND the message:
// the engine fetches the message by id (caching it), the chat opens and
// the view jumps to the message. Topic permalinks (slice 189 —
// t.me/<channel>/<topic>/<msg>, t.me/c/<id>/<topic>/<msg>,
// tg://resolve?...&topic=<id>) additionally scope the view to the forum
// topic before jumping. Comment-thread permalinks (slice 196 —
// t.me/<channel>/<post>?comment=<id>, t.me/c/<id>/<post>?comment=<id>,
// tg://resolve?...&comment=<id>) open the chat straight into the
// slice-195 thread view and jump to the linked comment. The reserved
// paths stay on the browser. Pure classification in deepLinkTarget.

import (
	"strconv"
	"strings"

	"uniclient/engine"
)

// deepLinkTarget classifies a tapped URL. kind "invite" carries the
// invite hash; "resolve" a public username; "permalink" a message
// permalink (arg = username or "c/<channelID>", post = the message id,
// topic = the forum topic id when the link is topic-scoped, comment =
// the linked comment id when the link is comment-thread form, else "");
// "" means "not a routable deep link" (browser path). Pure — locked by
// tests.
func deepLinkTarget(url string) (kind, arg, post, topic, comment string) {
	u := strings.TrimSpace(url)
	if u == "" {
		return "", "", "", "", ""
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
				return "invite", h, "", "", ""
			}
		case "resolve":
			if d := params["domain"]; d != "" {
				if p := params["post"]; p != "" {
					// tg://resolve?domain=u&post=123[&topic=45][&comment=67] —
					// the topic param scopes forum permalinks (slice 189), the
					// comment param routes comment threads (slice 196); a topic
					// link has no comment semantics, so the topic wins.
					t := params["topic"]
					if t != "" && !isAllDigits(t) {
						t = ""
					}
					c := params["comment"]
					if c != "" && (!isAllDigits(c) || t != "") {
						c = ""
					}
					return "permalink", d, p, t, c
				}
				return "resolve", d, "", "", ""
			}
		}
		return "", "", "", "", ""
	}

	// t.me-style: invite forms go through the shared extractor.
	if h, ok := extractInviteHash(u); ok {
		return "invite", h, "", "", ""
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
			// Query rides after the path (slice 196): ?comment=<id> routes
			// the comment thread; any other params are just stripped so
			// they never break segment classification.
			path, query, _ := strings.Cut(path, "?")
			params := parseQueryPairs(query)
			com := params["comment"]
			if com != "" && !isAllDigits(com) {
				com = ""
			}
			segs := strings.Split(path, "/")
			// t.me/c/<channelID>/<msg>: internal-id channel permalink.
			if len(segs) == 3 && segs[0] == "c" && isAllDigits(segs[1]) && isAllDigits(segs[2]) {
				return "permalink", "c/" + segs[1], segs[2], "", com
			}
			// t.me/c/<channelID>/<topic>/<msg>: topic-scoped channel
			// permalink (slice 189) — the topic wins, no comment routing.
			if len(segs) == 4 && segs[0] == "c" && isAllDigits(segs[1]) && isAllDigits(segs[2]) && isAllDigits(segs[3]) {
				return "permalink", "c/" + segs[1], segs[3], segs[2], ""
			}
			if len(segs) == 2 {
				// t.me/<username>/<msg> resolves the chat AND the message;
				// non-numeric message ids are not ours to route.
				if isAllDigits(segs[1]) && segs[0] != "" && !strings.HasPrefix(segs[0], "+") && !reservedTelegramPath(segs[0]) {
					return "permalink", segs[0], segs[1], "", com
				}
				return "", "", "", "", ""
			}
			// t.me/<username>/<topic>/<msg>: topic permalink (slice 189)
			// — opens the chat scoped to the topic and jumps. Comment
			// params on topic forms are not routed (the topic wins).
			if len(segs) == 3 && isAllDigits(segs[1]) && isAllDigits(segs[2]) && segs[0] != "" &&
				!strings.HasPrefix(segs[0], "+") && !reservedTelegramPath(segs[0]) {
				return "permalink", segs[0], segs[2], segs[1], ""
			}
			// Deeper forms stay on the browser — honest scope.
			if len(segs) > 2 {
				return "", "", "", "", ""
			}
			name := segs[0]
			if name != "" && !strings.HasPrefix(name, "+") && !reservedTelegramPath(name) {
				return "resolve", name, "", "", ""
			}
			return "", "", "", "", ""
		}
	}
	return "", "", "", "", ""
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

// permalinkChatID maps a "c/<channelID>" permalink ref onto the app-wide
// channel-ID convention (-1000000000000 - channelID — the exact string
// every Dialog/ChatInfo carries; the old "-100"+id form never matched a
// real dialog id, so t.me/c/ links always missed). Username refs return
// "". Pure — locked by tests.
func permalinkChatID(ref string) string {
	if strings.HasPrefix(ref, "c/") && isAllDigits(ref[2:]) {
		if id, err := strconv.ParseInt(ref[2:], 10, 64); err == nil {
			return strconv.FormatInt(-1000000000000-id, 10)
		}
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
	kind, arg, post, topic, comment := deepLinkTarget(url)
	switch kind {
	case "invite":
		a.openInviteJoin(arg)
		return true
	case "resolve":
		a.resolveDeepLinkUser(arg)
		return true
	case "permalink":
		a.resolveDeepLinkPermalink(arg, post, topic, comment)
		return true
	}
	return false
}

// resolveDeepLinkPermalink opens a message permalink (t.me/user/123,
// t.me/c/1234/567, tg://resolve?domain=user&post=123 — plus the
// topic-scoped forms of slice 189: t.me/<channel>/<topic>/<msg>,
// t.me/c/<id>/<topic>/<msg> — and the comment-thread forms of slice
// 196: t.me/<channel>/<post>?comment=<id>, t.me/c/<id>/<post>?comment=):
// resolves the chat, fetches the message by id through the engine
// (caching it), then opens the chat with a pending jump to the message;
// topic links scope the view to the forum topic first; comment links
// open straight into the thread view and jump to the linked comment.
// Private c/ links only work for chats the account already has
// (honest empty state otherwise).
func (a *App) resolveDeepLinkPermalink(ref, msgID, topicID, commentID string) {
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
				a.openPermalinkTarget(acc, chatID, c.Title, msgID, topicID, commentID)
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
		a.openPermalinkTarget(c.AccountID, c.ChatID, c.Title, msgID, topicID, commentID)
	}()
}

// openPermalinkTarget loads the message's timestamp (engine caches the
// message on the fetch) and schedules the open + jump on the GUI loop.
// A topic id (slice 189) rides along as pendingTopic — the chat opens
// straight into the topic view and the jump lands inside it. A comment
// id (slice 196) rides along as pendingThread instead — the chat opens
// straight into the comment-thread view (no timestamp prefetch: the
// thread fetch resolves its own rows) and the jump lands on the linked
// comment.
func (a *App) openPermalinkTarget(accountID, chatID, title, msgID, topicID, commentID string) {
	if commentID != "" {
		// Comment-thread deep link: schedule the open + thread hop. The
		// thread fetch (openCommentThreadDeep) loads its own rows, so no
		// per-message prefetch is needed here.
		a.mu.Lock()
		k := chatKey{accountID, chatID}
		a.pendingOpen = &k
		a.pendingTitle = title
		a.pendingThread = &threadOpenReq{postID: msgID, commentID: commentID}
		a.mu.Unlock()
		a.invalidate()
		return
	}
	go func() {
		ts, err := a.eng.GetMessageTimestamp(accountID, chatID, msgID)
		if err != nil || ts <= 0 {
			// Still open the chat (topic-scoped when the link says so) —
			// the message just isn't resolvable.
			a.mu.Lock()
			k := chatKey{accountID, chatID}
			a.pendingOpen = &k
			a.pendingTitle = title
			if topicID != "" {
				a.pendingTopic = &topicID
			}
			a.mu.Unlock()
			a.invalidate()
			return
		}
		a.mu.Lock()
		k := chatKey{accountID, chatID}
		a.pendingOpen = &k
		a.pendingTitle = title
		a.pendingJump = &jumpReq{msgID: msgID, ts: ts}
		if topicID != "" {
			a.pendingTopic = &topicID
		}
		a.mu.Unlock()
		a.invalidate()
	}()
}

// resolveDeepLinkUser opens a public username link: global search on
// the active account, first hit schedules the chat open (the GUI loop's
// consumePendingOpen hop — openChat touches the a.wid.composer editor and
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
