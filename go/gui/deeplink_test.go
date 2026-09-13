package gui

// Deep-link classification (slice 95, matrix row 292): tg:// and t.me
// forms route to invite-join / username-resolve; everything else (and
// the non-routable reserved paths) stays on the browser path.

import (
	"testing"
)

func TestDeepLinkTargetInvite(t *testing.T) {
	cases := []struct {
		url  string
		want string
		hash string
	}{
		{"tg://join?invite=AbCdEf12345", "invite", "AbCdEf12345"},
		{"https://t.me/+AbCdEf12345", "invite", "AbCdEf12345"},
		{"https://t.me/joinchat/AbCdEf12345", "invite", "AbCdEf12345"},
		{"t.me/joinchat/AbCdEf12345", "invite", "AbCdEf12345"},
		{"+AbCdEf12345", "invite", "AbCdEf12345"},
		{"tg://join", "", ""},                   // no invite param
		{"tg://join?invite=", "", ""},           // empty hash
		{"tg://join?other=x", "", ""},           // wrong param
		{"tg://foo?invite=AbCdEf12345", "", ""}, // non-join path
	}
	for _, tc := range cases {
		kind, arg, _, _, _ := deepLinkTarget(tc.url)
		if kind != tc.want || arg != tc.hash {
			t.Errorf("deepLinkTarget(%q) = %q/%q, want %q/%q", tc.url, kind, arg, tc.want, tc.hash)
		}
	}
}

func TestDeepLinkTargetResolve(t *testing.T) {
	cases := []struct {
		url  string
		want string
		name string
	}{
		{"tg://resolve?domain=durov", "resolve", "durov"},
		{"https://t.me/durov", "resolve", "durov"},
		{"http://t.me/somechannel", "resolve", "somechannel"},
		{"https://telegram.me/durov", "resolve", "durov"},
		{"https://t.me/durov/123", "permalink", "durov"},     // message permalink routes in-app (slice 161)
		{"https://t.me/c/123456/7", "permalink", "c/123456"}, // internal-id permalink now routes in-app (slice 161)
		{"https://t.me/s/durov", "", ""},                     // channel preview → browser
		{"https://t.me/addstickers/durov", "", ""},
		{"https://t.me/", "", ""},            // bare domain, no segment
		{"tg://resolve?group=durov", "", ""}, // wrong param
	}
	for _, tc := range cases {
		kind, arg, _, _, _ := deepLinkTarget(tc.url)
		if kind != tc.want || arg != tc.name {
			t.Errorf("deepLinkTarget(%q) = %q/%q, want %q/%q", tc.url, kind, arg, tc.want, tc.name)
		}
	}
}

func TestDeepLinkTargetNotALink(t *testing.T) {
	for _, u := range []string{"", "   ", "https://example.com/x", "http://google.com", "mailto:x@y.z"} {
		if kind, _, _, _, _ := deepLinkTarget(u); kind != "" {
			t.Errorf("deepLinkTarget(%q) = %q, want \"\"", u, kind)
		}
	}
}

func TestParseQueryPairs(t *testing.T) {
	got := parseQueryPairs("invite=abc&domain=x&domain=y&empty=&flag")
	if got["invite"] != "abc" {
		t.Errorf("invite = %q", got["invite"])
	}
	if got["domain"] != "y" {
		t.Errorf("domain should take the last value: %q", got["domain"])
	}
	if got["flag"] != "" {
		t.Errorf("bare key should be empty: %q", got["flag"])
	}
	if got["empty"] != "" {
		t.Errorf("empty = %q", got["empty"])
	}
}

func TestDeepLinkTargetPermalink(t *testing.T) {
	cases := []struct {
		url                        string
		kind, ref, msg, topic, com string
	}{
		// Public-username permalinks resolve in-app (slice 161).
		{"https://t.me/durov/123", "permalink", "durov", "123", "", ""},
		{"https://t.me/somechannel/99001", "permalink", "somechannel", "99001", "", ""},
		{"t.me/durov/123", "permalink", "durov", "123", "", ""},
		{"https://telegram.me/durov/123", "permalink", "durov", "123", "", ""},
		{"tg://resolve?domain=durov&post=123", "permalink", "durov", "123", "", ""},
		{"tg://resolve?domain=durov&single=123", "resolve", "durov", "", "", ""}, // no post param → plain resolve

		// Private-channel permalinks (t.me/c/<id>/<msg>).
		{"https://t.me/c/123456/7", "permalink", "c/123456", "7", "", ""},
		{"https://t.me/c/1234567890/999", "permalink", "c/1234567890", "999", "", ""},
		{"t.me/c/123456/7", "permalink", "c/123456", "7", "", ""},
		{"https://t.me/c/123456", "", "", "", "", ""}, // no message id → not routable
		{"https://t.me/c/abc/7", "", "", "", "", ""},  // non-numeric id → browser

		// Unknown query params are stripped, never break classification.
		{"https://t.me/durov/123?single=1", "permalink", "durov", "123", "", ""},
		{"https://t.me/durov?profile", "resolve", "durov", "", "", ""},
		// Non-numeric message id.
		{"https://t.me/durov/abc", "", "", "", "", ""},
	}
	for _, tc := range cases {
		kind, ref, msg, topic, com := deepLinkTarget(tc.url)
		if kind != tc.kind || ref != tc.ref || msg != tc.msg || topic != tc.topic || com != tc.com {
			t.Errorf("deepLinkTarget(%q) = %q/%q/%q/%q/%q, want %q/%q/%q/%q/%q",
				tc.url, kind, ref, msg, topic, com, tc.kind, tc.ref, tc.msg, tc.topic, tc.com)
		}
	}
}

func TestDeepLinkTargetTopicPermalink(t *testing.T) {
	cases := []struct {
		url                  string
		kind, ref, msg, topc string
	}{
		// Public forum topic permalinks (slice 189).
		{"https://t.me/supergroup/5/123", "permalink", "supergroup", "123", "5"},
		{"t.me/supergroup/42/99001", "permalink", "supergroup", "99001", "42"},
		{"https://telegram.me/forumchat/1/2", "permalink", "forumchat", "2", "1"},
		// Private channel topic permalinks (t.me/c/<id>/<topic>/<msg>).
		{"https://t.me/c/123456/5/7", "permalink", "c/123456", "7", "5"},
		{"t.me/c/123456/77/990", "permalink", "c/123456", "990", "77"},
		// tg:// with the topic param.
		{"tg://resolve?domain=supergroup&post=123&topic=5", "permalink", "supergroup", "123", "5"},
		{"tg://resolve?domain=supergroup&post=123&topic=abc", "permalink", "supergroup", "123", ""}, // non-numeric topic dropped
		{"tg://resolve?domain=supergroup&topic=5", "resolve", "supergroup", "", ""},                 // no post → plain resolve
		// Degenerate: 4-seg username form, non-numeric parts.
		{"https://t.me/durov/5/abc", "", "", "", ""},
		{"https://t.me/supergroup/abc/123", "", "", "", ""},
		// Reserved paths never route as topics.
		{"https://t.me/addstickers/5/7", "", "", "", ""},
	}
	for _, tc := range cases {
		kind, ref, msg, topic, _ := deepLinkTarget(tc.url)
		if kind != tc.kind || ref != tc.ref || msg != tc.msg || topic != tc.topc {
			t.Errorf("deepLinkTarget(%q) = %q/%q/%q/%q, want %q/%q/%q/%q",
				tc.url, kind, ref, msg, topic, tc.kind, tc.ref, tc.msg, tc.topc)
		}
	}
}

// TestDeepLinkTargetCommentPermalink (slice 196): comment-thread deep
// links (?comment=<id>) classify as permalinks carrying the comment id —
// they route in-app into the slice-195 thread view instead of the
// browser. Topic-scoped forms have no comment semantics (the topic wins
// and the comment param is dropped).
func TestDeepLinkTargetCommentPermalink(t *testing.T) {
	cases := []struct {
		url                        string
		kind, ref, msg, topic, com string
	}{
		// t.me/<channel>/<post>?comment=<id> — public comment permalink.
		{"https://t.me/supergroup/123?comment=45", "permalink", "supergroup", "123", "", "45"},
		{"t.me/supergroup/123?comment=45", "permalink", "supergroup", "123", "", "45"},
		// t.me/c/<id>/<post>?comment=<id> — private-channel comment permalink.
		{"https://t.me/c/123456/7?comment=89", "permalink", "c/123456", "7", "", "89"},
		{"t.me/c/123456/7?comment=89", "permalink", "c/123456", "7", "", "89"},
		// tg://resolve with the comment param.
		{"tg://resolve?domain=supergroup&post=123&comment=45", "permalink", "supergroup", "123", "", "45"},
		// Non-numeric / empty comment ids drop the comment but keep the
		// permalink (plain message jump).
		{"https://t.me/supergroup/123?comment=abc", "permalink", "supergroup", "123", "", ""},
		{"https://t.me/supergroup/123?comment=", "permalink", "supergroup", "123", "", ""},
		{"https://t.me/c/123456/7?comment=x1", "permalink", "c/123456", "7", "", ""},
		// Topic-scoped forms: the topic wins, comment param is not routed.
		{"https://t.me/supergroup/5/123?comment=45", "permalink", "supergroup", "123", "5", ""},
		{"tg://resolve?domain=s&post=1&topic=5&comment=9", "permalink", "s", "1", "5", ""},
		// Plain resolve with a stray comment param is still a resolve.
		{"tg://resolve?domain=durov&comment=45", "resolve", "durov", "", "", ""},
	}
	for _, tc := range cases {
		kind, ref, msg, topic, com := deepLinkTarget(tc.url)
		if kind != tc.kind || ref != tc.ref || msg != tc.msg || topic != tc.topic || com != tc.com {
			t.Errorf("deepLinkTarget(%q) = %q/%q/%q/%q/%q, want %q/%q/%q/%q/%q",
				tc.url, kind, ref, msg, topic, com, tc.kind, tc.ref, tc.msg, tc.topic, tc.com)
		}
	}
}

func TestPermalinkChatRef(t *testing.T) {
	// The c/<channelID> form maps onto the -100 chat-ID convention.
	if got := permalinkChatID("c/123456"); got != "-100123456" {
		t.Errorf("permalinkChatID(c/123456) = %q", got)
	}
	if got := permalinkChatID("durov"); got != "" {
		t.Errorf("username ref has no direct chat id: %q", got)
	}
}
