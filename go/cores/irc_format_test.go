package cores

import (
	"testing"
)

// TestIRCClientsReceiveFormattingStripped: BUGS B-51 — IRC relays
// formatting control codes (bold/color/underline…) verbatim, and
// NOTHING stripped them on the receive path (StripFormatting existed
// with zero callers, GUI has no filter) — users saw raw \x02/\x03
// garbage in chat, the same class as B-14's mojibake. Strip at the
// four Trailing() extraction points; CTCP/ACTION inherit the stripped
// text. RED: codes still present.
func TestIRCClientsReceiveFormattingStripped(t *testing.T) {
	c := NewIRCCore(nil)
	var got []Update
	c.OnUpdate(func(u Update) {
		if u.Message != nil {
			got = append(got, u)
		}
	})

	// PRIVMSG with bold, underline-reset and mIRC colors.
	c.handlePrivmsg(parseIRCMsg(":alice!a@h PRIVMSG #chan :hi\x02!\x0f there\x0304,12red"))
	if len(got) != 1 || got[0].Message == nil {
		t.Fatalf("no message captured: %+v", got)
	}
	if txt := got[0].Message.Text; txt != "hi! there red" && txt != "hi! therered" {
		t.Errorf("PRIVMSG not stripped: %q", txt)
	}

	// Channel NOTICE from a user (hex-colored) → the [NOTICE] branch.
	// (A target of "*"/"AUTH" is server-origin by design and lands in
	// the server-log chat — that branch inherits the same stripped text.)
	got = nil
	c.handleNotice(parseIRCMsg(":alice!a@h NOTICE #chan :\x04aabbccnotice\x0f"))
	if len(got) != 1 {
		t.Fatalf("no notice captured: %+v", got)
	}
	if txt := got[0].Message.Text; txt != "[NOTICE] notice" {
		t.Errorf("NOTICE not stripped: %q", txt)
	}
}

// TestStripFormattingPins: the stripper becomes live code with B-51 —
// pin the mIRC grammar it accepts (control set, fg/bg digits, hex
// color) and that plain text passes through untouched.
func TestStripFormattingPins(t *testing.T) {
	cases := []struct{ in, want string }{
		{"plain text", "plain text"},
		{"\x02bold\x02", "bold"},
		{"\x1fit\x1f \x1f\x1f", "it "},
		{"\x1estrike\x1e", "strike"},
		{"\x11invert\x11", "invert"},
		{"\x0304,12text\x03", "text"},
		{"\x035mid\x03", "mid"}, // single-digit fg IS a color code (mIRC) and is consumed
		{"\x04ff00aafade", "fade"},
		{"trailing\x0f", "trailing"},
		{"code \x03 alone", "code  alone"}, // lone terminator is a control byte: removed
	}
	for _, c := range cases {
		if got := StripFormatting(c.in); got != c.want {
			t.Errorf("StripFormatting(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
