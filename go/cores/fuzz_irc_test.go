package cores

import "testing"

func FuzzParseIRCMsg(f *testing.F) {
	f.Add("")
	f.Add("PING :xyz")
	f.Add(":nick!user@host PRIVMSG #chan :hello world")
	f.Add(":a@b NOTICE * :*** Looking up your hostname")
	f.Add("PRIVMSG")
	f.Add(":" + string(make([]byte, 0)))
	f.Add("@batch=x :a!b@c PRIVMSG #d :e")
	f.Fuzz(func(t *testing.T, line string) {
		_ = parseIRCMsg(line)
	})
}

func FuzzParseStandardReply(f *testing.F) {
	f.Add("")
	f.Add("FAIL * 021 * :no help")
	f.Add("NOTE * 001 * :welcome")
	f.Add("unknown shape entirely")
	f.Fuzz(func(t *testing.T, line string) {
		_, _, _, _, _ = ParseStandardReply(line)
	})
}

func FuzzParsePROXYProtocol(f *testing.F) {
	f.Add("")
	f.Add("PROXY TCP4 192.168.0.1 192.168.0.2 1234 5678\r\n")
	f.Add("PROXY UNKNOWN\r\n")
	f.Add("PROXY TCP6 ::1 ::2 1 2")
	f.Add("PROXY TCP4 not-an-ip x 1 2")
	f.Fuzz(func(t *testing.T, line string) {
		_, _, _, _, _ = ParsePROXYProtocol(line)
	})
}
