package gui

import (
	"testing"

	"uniclient/engine"
)

func TestExtractInviteHash(t *testing.T) {
	cases := []struct {
		q    string
		want string
		ok   bool
	}{
		{"https://t.me/+AbCdEf12345", "AbCdEf12345", true},
		{"http://t.me/+AbCdEf12345", "AbCdEf12345", true},
		{"t.me/+AbCdEf12345", "AbCdEf12345", true},
		{"https://telegram.me/joinchat/AbCdEf12345", "AbCdEf12345", true},
		{"https://t.me/joinchat/AbCdEf12345", "AbCdEf12345", true},
		{"https://telegram.dog/+AbCdEf12345", "AbCdEf12345", true},
		{"+AbCdEf12345", "AbCdEf12345", true},
		{"www.t.me/+AbCdEf12345", "AbCdEf12345", true},
		{"  https://t.me/+AbCdEf12345  ", "AbCdEf12345", true},
		// Not invites: usernames, plain links, channels.
		{"https://t.me/durov", "", false},
		{"t.me/somechannel", "", false},
		{"@durov", "", false},
		{"hello world", "", false},
		{"", "", false},
		{"+ab", "", false}, // too short
	}
	for _, tc := range cases {
		got, ok := extractInviteHash(tc.q)
		if got != tc.want || ok != tc.ok {
			t.Errorf("extractInviteHash(%q) = (%q,%v), want (%q,%v)", tc.q, got, ok, tc.want, tc.ok)
		}
	}
}

func TestInviteScopeAccount(t *testing.T) {
	f := frame{acctFilter: "acc2", accounts: []engine.AccountInfo{{ID: "acc1"}, {ID: "acc2"}}}
	if got := inviteScopeAccount(f); got != "acc2" {
		t.Errorf("scoped = %q", got)
	}
	f.acctFilter = ""
	if got := inviteScopeAccount(f); got != "acc1" {
		t.Errorf("unscoped = %q, want first account", got)
	}
	f.accounts = nil
	if got := inviteScopeAccount(f); got != "" {
		t.Errorf("no accounts = %q", got)
	}
}
