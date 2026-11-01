package cores

import (
	"testing"
)

func TestIRCClientsReceiveFormattingStripped(t *testing.T) {
	c := NewIRCCore(nil)
	var got []Update
	c.OnUpdate(func(u Update) {
		if u.Message != nil {
			got = append(got, u)
		}
	})

	c.handlePrivmsg(parseIRCMsg(":alice!a@h PRIVMSG #chan :hi\x02!\x0f there\x0304,12red"))
	if len(got) != 1 || got[0].Message == nil {
		t.Fatalf("no message captured: %+v", got)
	}
	if txt := got[0].Message.Text; txt != "hi! there red" && txt != "hi! therered" {
		t.Errorf("PRIVMSG not stripped: %q", txt)
	}

	got = nil
	c.handleNotice(parseIRCMsg(":alice!a@h NOTICE #chan :\x04aabbccnotice\x0f"))
	if len(got) != 1 {
		t.Fatalf("no notice captured: %+v", got)
	}
	if txt := got[0].Message.Text; txt != "[NOTICE] notice" {
		t.Errorf("NOTICE not stripped: %q", txt)
	}
}

func TestStripFormattingPins(t *testing.T) {
	cases := []struct{ in, want string }{
		{"plain text", "plain text"},
		{"\x02bold\x02", "bold"},
		{"\x1fit\x1f \x1f\x1f", "it "},
		{"\x1estrike\x1e", "strike"},
		{"\x11invert\x11", "invert"},
		{"\x0304,12text\x03", "text"},
		{"\x035mid\x03", "mid"},
		{"\x04ff00aafade", "fade"},
		{"trailing\x0f", "trailing"},
		{"code \x03 alone", "code  alone"},
	}
	for _, c := range cases {
		if got := StripFormatting(c.in); got != c.want {
			t.Errorf("StripFormatting(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
