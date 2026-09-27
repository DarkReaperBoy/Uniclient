package cores

import (
	"bufio"
	"encoding/base64"
	"fmt"
	"io"
	"net"
	"strings"
	"testing"
	"time"
)

// F-80 (slice 316): hostile-server DoS on the XMPP SCRAM login path.
//  - readSASLElement buffered the SASL element with NO size bound (only
//    a 15s read deadline) — a server streaming bytes without '>' pushes
//    gigabytes into buf in those 15 seconds (O(n²) on top: buf.String()
//    copies the whole buffer on EVERY byte).
//  - The server-challenge parameters were trusted: `i=2000000000`
//    made PBKDF2 burn multi-minutes of CPU at login (iterations only
//    checked for parseability), and an arbitrarily large `s=` salt was
//    base64-decoded into memory and HMAC'd `iterations` times
//    (amplification).
//
// Seam-RED (WORKLOG 316): undefined: parseScramServerFirst /
// saslElementMax / scramIterMax / scramSaltMax / ErrSCRAMParams.

// infiniteByteReader yields b forever (bounded by the code under test).
type infiniteByteReader struct{ b byte }

func (r *infiniteByteReader) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = r.b
	}
	return len(p), nil
}

// deadlineConn is a net.Conn whose deadlines are no-ops (the test
// asserts the SIZE bound, not the wall-clock one — F-9).
type deadlineConn struct{ r io.Reader }

func (c *deadlineConn) Read(p []byte) (int, error)         { return c.r.Read(p) }
func (c *deadlineConn) Write(p []byte) (int, error)        { return len(p), nil }
func (c *deadlineConn) Close() error                       { return nil }
func (c *deadlineConn) LocalAddr() net.Addr                { return nil }
func (c *deadlineConn) RemoteAddr() net.Addr               { return nil }
func (c *deadlineConn) SetDeadline(t time.Time) error      { return nil }
func (c *deadlineConn) SetReadDeadline(t time.Time) error  { return nil }
func (c *deadlineConn) SetWriteDeadline(t time.Time) error { return nil }

func TestReadSASLElementCapsHostileStream(t *testing.T) {
	conn := &deadlineConn{r: &infiniteByteReader{b: 'x'}}
	x := &XMPPCore{conn: conn, reader: bufio.NewReaderSize(conn, 8192)}
	_, _, err := x.readSASLElement()
	if err == nil {
		t.Fatal("endless SASL element accepted")
	}
	want := fmt.Sprintf("exceeds %d bytes", saslElementMax)
	if !strings.Contains(err.Error(), want) {
		t.Fatalf("err = %v, want %q", err, want)
	}
}

func scramChallenge(t *testing.T, clientNonce, saltPlain, iterations string) string {
	t.Helper()
	return "r=" + clientNonce + "srv,s=" +
		base64.StdEncoding.EncodeToString([]byte(saltPlain)) + ",i=" + iterations
}

func TestParseScramServerFirstValid(t *testing.T) {
	snonce, salt, iters, err := parseScramServerFirst(
		scramChallenge(t, "cn123", "saltysalt", "4096"), "cn123")
	if err != nil {
		t.Fatalf("valid challenge: %v", err)
	}
	if snonce != "cn123srv" {
		t.Fatalf("server nonce = %q", snonce)
	}
	if string(salt) != "saltysalt" {
		t.Fatalf("salt = %q", salt)
	}
	if iters != 4096 {
		t.Fatalf("iterations = %d", iters)
	}
}

func TestParseScramServerFirstRejectsHugeIterations(t *testing.T) {
	// Hostile server: i = 2^31 → PBKDF2 would burn multi-minutes of CPU
	// at login. (Pre-fix: Atoi succeeded, the loop ran.)
	_, _, _, err := parseScramServerFirst(
		scramChallenge(t, "cn", "salt", "2000000000"), "cn")
	if err == nil || !strings.Contains(err.Error(), "iterations out of range") {
		t.Fatalf("huge iterations: err = %v, want iterations out of range", err)
	}
	// Zero/negative iterations = trivial KDF (and pre-fix produced an
	// authentication with NO key stretching at all).
	for _, bad := range []string{"0", "-5"} {
		if _, _, _, err := parseScramServerFirst(scramChallenge(t, "cn", "salt", bad), "cn"); err == nil {
			t.Fatalf("iterations=%s accepted", bad)
		}
	}
}

func TestParseScramServerFirstRejectsOversizedSalt(t *testing.T) {
	big := strings.Repeat("S", 4096) // 4 KiB salt: 100× anything real (RFC uses 16-24 bytes)
	_, _, _, err := parseScramServerFirst(scramChallenge(t, "cn", big, "4096"), "cn")
	if err == nil || !strings.Contains(err.Error(), "salt too large") {
		t.Fatalf("oversized salt: err = %v, want salt too large", err)
	}
}

func TestParseScramServerFirstRejectsNonceMismatch(t *testing.T) {
	// Pins the EXISTING check (moved, not dropped).
	_, _, _, err := parseScramServerFirst(scramChallenge(t, "OTHER", "salt", "4096"), "cn")
	if err == nil || !strings.Contains(err.Error(), "doesn't start with client nonce") {
		t.Fatalf("nonce mismatch: err = %v", err)
	}
	// And the existing parse-failure messages stay honest.
	_, _, _, err = parseScramServerFirst("r=cnsrv,s=!!notb64!!,i=4096", "cn")
	if err == nil || !strings.Contains(err.Error(), "bad salt") {
		t.Fatalf("bad salt b64: err = %v", err)
	}
	_, _, _, err = parseScramServerFirst("r=cnsrv,s=c2FsdA==,i=abc", "cn")
	if err == nil || !strings.Contains(err.Error(), "bad iterations") {
		t.Fatalf("bad iterations: err = %v", err)
	}
}
