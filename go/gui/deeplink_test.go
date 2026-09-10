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
		kind, arg := deepLinkTarget(tc.url)
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
		{"https://t.me/durov/123", "", ""},  // message permalink → browser
		{"https://t.me/c/123456/7", "", ""}, // internal-id permalink → browser
		{"https://t.me/s/durov", "", ""},    // channel preview → browser
		{"https://t.me/addstickers/durov", "", ""},
		{"https://t.me/", "", ""},            // bare domain, no segment
		{"tg://resolve?group=durov", "", ""}, // wrong param
	}
	for _, tc := range cases {
		kind, arg := deepLinkTarget(tc.url)
		if kind != tc.want || arg != tc.name {
			t.Errorf("deepLinkTarget(%q) = %q/%q, want %q/%q", tc.url, kind, arg, tc.want, tc.name)
		}
	}
}

func TestDeepLinkTargetNotALink(t *testing.T) {
	for _, u := range []string{"", "   ", "https://example.com/x", "http://google.com", "mailto:x@y.z"} {
		if kind, _ := deepLinkTarget(u); kind != "" {
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
