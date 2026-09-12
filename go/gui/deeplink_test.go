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
		kind, arg, _ := deepLinkTarget(tc.url)
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
		kind, arg, _ := deepLinkTarget(tc.url)
		if kind != tc.want || arg != tc.name {
			t.Errorf("deepLinkTarget(%q) = %q/%q, want %q/%q", tc.url, kind, arg, tc.want, tc.name)
		}
	}
}

func TestDeepLinkTargetNotALink(t *testing.T) {
	for _, u := range []string{"", "   ", "https://example.com/x", "http://google.com", "mailto:x@y.z"} {
		if kind, _, _ := deepLinkTarget(u); kind != "" {
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
		url            string
		kind, ref, msg string
	}{
		// Public-username permalinks resolve in-app (slice 161).
		{"https://t.me/durov/123", "permalink", "durov", "123"},
		{"https://t.me/somechannel/99001", "permalink", "somechannel", "99001"},
		{"t.me/durov/123", "permalink", "durov", "123"},
		{"https://telegram.me/durov/123", "permalink", "durov", "123"},
		{"tg://resolve?domain=durov&post=123", "permalink", "durov", "123"},
		{"tg://resolve?domain=durov&single=123", "resolve", "durov", ""}, // no post param → plain resolve

		// Private-channel permalinks (t.me/c/<id>/<msg>).
		{"https://t.me/c/123456/7", "permalink", "c/123456", "7"},
		{"https://t.me/c/1234567890/999", "permalink", "c/1234567890", "999"},
		{"t.me/c/123456/7", "permalink", "c/123456", "7"},
		{"https://t.me/c/123456", "", "", ""}, // no message id → not routable
		{"https://t.me/c/abc/7", "", "", ""},  // non-numeric id → browser

		// Topic form (t.me/user/<topic>/<msg>) stays on the browser —
		// honest scope: topic-scoped resolution is not modeled yet.
		{"https://t.me/supergroup/5/123", "", "", ""},
		// Comment-thread form likewise.
		{"https://t.me/supergroup/123?comment=45", "", "", ""},
		// Non-numeric message id.
		{"https://t.me/durov/abc", "", "", ""},
	}
	for _, tc := range cases {
		kind, ref, msg := deepLinkTarget(tc.url)
		if kind != tc.kind || ref != tc.ref || msg != tc.msg {
			t.Errorf("deepLinkTarget(%q) = %q/%q/%q, want %q/%q/%q",
				tc.url, kind, ref, msg, tc.kind, tc.ref, tc.msg)
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
