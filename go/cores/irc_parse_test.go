package cores

import (
	"testing"
)

func TestParseIRCMsgPlain(t *testing.T) {
	m := parseIRCMsg("PING irc.example.com")
	if m == nil {
		t.Fatal("nil message")
	}
	if m.Command != "PING" {
		t.Fatalf("command = %q, want PING", m.Command)
	}
	if len(m.Params) != 1 || m.Params[0] != "irc.example.com" {
		t.Fatalf("params = %v, want [irc.example.com]", m.Params)
	}
}

func TestParseIRCMsgPrefixAndTrailing(t *testing.T) {
	m := parseIRCMsg(":nick!user@host.example.com PRIVMSG #chan :hello there")
	if m == nil {
		t.Fatal("nil message")
	}
	if m.Prefix != "nick!user@host.example.com" {
		t.Fatalf("prefix = %q", m.Prefix)
	}
	if m.Command != "PRIVMSG" {
		t.Fatalf("command = %q, want PRIVMSG", m.Command)
	}
	if len(m.Params) != 2 || m.Params[0] != "#chan" || m.Params[1] != "hello there" {
		t.Fatalf("params = %v, want [#chan \"hello there\"]", m.Params)
	}
}

func TestParseIRCMsgTags(t *testing.T) {
	m := parseIRCMsg("@time=2026-09-07T10:00:00Z;account=nick :nick!n@h PRIVMSG #chan :hi")
	if m == nil {
		t.Fatal("nil message")
	}
	if m.Tags["time"] != "2026-09-07T10:00:00Z" {
		t.Fatalf("tag time = %q", m.Tags["time"])
	}
	if m.Tags["account"] != "nick" {
		t.Fatalf("tag account = %q", m.Tags["account"])
	}
	if m.Command != "PRIVMSG" {
		t.Fatalf("command = %q", m.Command)
	}
}

func TestParseIRCMsgTagWithoutValue(t *testing.T) {
	// A valueless tag is just the bare key (no '=').
	m := parseIRCMsg("@intent :a!b@c JOIN #room")
	if m == nil {
		t.Fatal("nil message")
	}
	if v, ok := m.Tags["intent"]; !ok {
		t.Fatalf("valueless tag intent missing: %v", m.Tags)
	} else if v != "" {
		t.Fatalf("valueless tag intent = %q, want empty", v)
	}
	if m.Command != "JOIN" {
		t.Fatalf("command = %q, want JOIN", m.Command)
	}
}

func TestParseIRCMsgNumeric(t *testing.T) {
	m := parseIRCMsg(":server.example 372 nick :- Message of the day")
	if m == nil {
		t.Fatal("nil message")
	}
	if m.Command != "372" {
		t.Fatalf("command = %q, want 372", m.Command)
	}
	if m.Params[0] != "nick" {
		t.Fatalf("first param = %q, want nick", m.Params[0])
	}
	if m.Params[len(m.Params)-1] != "- Message of the day" {
		t.Fatalf("trailing = %q", m.Params[len(m.Params)-1])
	}
}

func TestParseStandardReply(t *testing.T) {
	severity, command, code, _, desc := ParseStandardReply(":server FAIL CHATHISTORY MESSAGE_ERROR too_many :There are too many entries")
	if severity != "FAIL" || command != "CHATHISTORY" || code != "MESSAGE_ERROR" {
		t.Fatalf("got %q/%q/%q, want FAIL/CHATHISTORY/MESSAGE_ERROR", severity, command, code)
	}
	if desc != "There are too many entries" {
		t.Fatalf("description = %q", desc)
	}
}
