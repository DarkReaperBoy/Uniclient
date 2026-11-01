package gui

import (
	"strconv"
	"strings"

	"uniclient/engine"
)

func deepLinkTarget(url string) (kind, arg, post, topic, comment string) {
	u := strings.TrimSpace(url)
	if u == "" {
		return "", "", "", "", ""
	}
	low := strings.ToLower(u)

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

	if h, ok := extractInviteHash(u); ok {
		return "invite", h, "", "", ""
	}

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
			path, query, _ := strings.Cut(path, "?")
			params := parseQueryPairs(query)
			com := params["comment"]
			if com != "" && !isAllDigits(com) {
				com = ""
			}
			segs := strings.Split(path, "/")
			if len(segs) == 3 && segs[0] == "c" && isAllDigits(segs[1]) && isAllDigits(segs[2]) {
				return "permalink", "c/" + segs[1], segs[2], "", com
			}
			if len(segs) == 4 && segs[0] == "c" && isAllDigits(segs[1]) && isAllDigits(segs[2]) && isAllDigits(segs[3]) {
				return "permalink", "c/" + segs[1], segs[3], segs[2], ""
			}
			if len(segs) == 2 {
				if isAllDigits(segs[1]) && segs[0] != "" && !strings.HasPrefix(segs[0], "+") && !reservedTelegramPath(segs[0]) {
					return "permalink", segs[0], segs[1], "", com
				}
				return "", "", "", "", ""
			}
			if len(segs) == 3 && isAllDigits(segs[1]) && isAllDigits(segs[2]) && segs[0] != "" &&
				!strings.HasPrefix(segs[0], "+") && !reservedTelegramPath(segs[0]) {
				return "permalink", segs[0], segs[2], segs[1], ""
			}
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

func permalinkChatID(ref string) string {
	if strings.HasPrefix(ref, "c/") && isAllDigits(ref[2:]) {
		if id, err := strconv.ParseInt(ref[2:], 10, 64); err == nil {
			return strconv.FormatInt(-1000000000000-id, 10)
		}
	}
	return ""
}

func reservedTelegramPath(seg string) bool {
	switch seg {
	case "joinchat", "c", "s", "addstickers", "addemoji", "share", "login",
		"contact", "confirm", "socks", "proxy", "boost", "invoice", "giftcode":
		return true
	}
	return false
}

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

func (a *App) resolveDeepLinkPermalink(ref, msgID, topicID, commentID string) {
	acc := inviteScopeAccount(a.snapshotForInvite())
	if acc == "" {
		a.setToast("Connect an account first")
		return
	}

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

func (a *App) openPermalinkTarget(accountID, chatID, title, msgID, topicID, commentID string) {
	if commentID != "" {
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
