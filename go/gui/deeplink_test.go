package gui

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
		{"tg://join", "", ""},
		{"tg://join?invite=", "", ""},
		{"tg://join?other=x", "", ""},
		{"tg://foo?invite=AbCdEf12345", "", ""},
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
		{"https://t.me/durov/123", "permalink", "durov"},
		{"https://t.me/c/123456/7", "permalink", "c/123456"},
		{"https://t.me/s/durov", "", ""},
		{"https://t.me/addstickers/durov", "", ""},
		{"https://t.me/", "", ""},
		{"tg://resolve?group=durov", "", ""},
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
		{"https://t.me/durov/123", "permalink", "durov", "123", "", ""},
		{"https://t.me/somechannel/99001", "permalink", "somechannel", "99001", "", ""},
		{"t.me/durov/123", "permalink", "durov", "123", "", ""},
		{"https://telegram.me/durov/123", "permalink", "durov", "123", "", ""},
		{"tg://resolve?domain=durov&post=123", "permalink", "durov", "123", "", ""},
		{"tg://resolve?domain=durov&single=123", "resolve", "durov", "", "", ""},

		{"https://t.me/c/123456/7", "permalink", "c/123456", "7", "", ""},
		{"https://t.me/c/1234567890/999", "permalink", "c/1234567890", "999", "", ""},
		{"t.me/c/123456/7", "permalink", "c/123456", "7", "", ""},
		{"https://t.me/c/123456", "", "", "", "", ""},
		{"https://t.me/c/abc/7", "", "", "", "", ""},

		{"https://t.me/durov/123?single=1", "permalink", "durov", "123", "", ""},
		{"https://t.me/durov?profile", "resolve", "durov", "", "", ""},
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
		{"https://t.me/supergroup/5/123", "permalink", "supergroup", "123", "5"},
		{"t.me/supergroup/42/99001", "permalink", "supergroup", "99001", "42"},
		{"https://telegram.me/forumchat/1/2", "permalink", "forumchat", "2", "1"},
		{"https://t.me/c/123456/5/7", "permalink", "c/123456", "7", "5"},
		{"t.me/c/123456/77/990", "permalink", "c/123456", "990", "77"},
		{"tg://resolve?domain=supergroup&post=123&topic=5", "permalink", "supergroup", "123", "5"},
		{"tg://resolve?domain=supergroup&post=123&topic=abc", "permalink", "supergroup", "123", ""},
		{"tg://resolve?domain=supergroup&topic=5", "resolve", "supergroup", "", ""},
		{"https://t.me/durov/5/abc", "", "", "", ""},
		{"https://t.me/supergroup/abc/123", "", "", "", ""},
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

func TestDeepLinkTargetCommentPermalink(t *testing.T) {
	cases := []struct {
		url                        string
		kind, ref, msg, topic, com string
	}{
		{"https://t.me/supergroup/123?comment=45", "permalink", "supergroup", "123", "", "45"},
		{"t.me/supergroup/123?comment=45", "permalink", "supergroup", "123", "", "45"},
		{"https://t.me/c/123456/7?comment=89", "permalink", "c/123456", "7", "", "89"},
		{"t.me/c/123456/7?comment=89", "permalink", "c/123456", "7", "", "89"},
		{"tg://resolve?domain=supergroup&post=123&comment=45", "permalink", "supergroup", "123", "", "45"},
		{"https://t.me/supergroup/123?comment=abc", "permalink", "supergroup", "123", "", ""},
		{"https://t.me/supergroup/123?comment=", "permalink", "supergroup", "123", "", ""},
		{"https://t.me/c/123456/7?comment=x1", "permalink", "c/123456", "7", "", ""},
		{"https://t.me/supergroup/5/123?comment=45", "permalink", "supergroup", "123", "5", ""},
		{"tg://resolve?domain=s&post=1&topic=5&comment=9", "permalink", "s", "1", "5", ""},
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
	if got := permalinkChatID("c/123456"); got != "-1000000123456" {
		t.Errorf("permalinkChatID(c/123456) = %q, want -1000000123456", got)
	}
	if got := permalinkChatID("durov"); got != "" {
		t.Errorf("username ref has no direct chat id: %q", got)
	}
	if got := permalinkChatID("c/"); got != "" {
		t.Errorf("empty channel id must not map: %q", got)
	}
	if got := permalinkChatID("c/abc"); got != "" {
		t.Errorf("non-numeric channel id must not map: %q", got)
	}
}
