package tests

import (
	"bufio"
	"encoding/base64"
	"fmt"
	"io"
	"net"
	"strings"
	"testing"
	"time"
	. "uniclient/cores"
)

type infiniteByteReader struct{ b byte }

func (r *infiniteByteReader) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = r.b
	}
	return len(p), nil
}

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
	x := ForTestNewXMPPCore(conn, nil, bufio.NewReaderSize(conn, 8192))
	_, _, err := x.ReadSASLElement()
	if err == nil {
		t.Fatal("endless SASL element accepted")
	}
	want := fmt.Sprintf("exceeds %d bytes", SaslElementMax)
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
	snonce, salt, iters, err := ParseScramServerFirst(
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
	_, _, _, err := ParseScramServerFirst(
		scramChallenge(t, "cn", "salt", "2000000000"), "cn")
	if err == nil || !strings.Contains(err.Error(), "iterations out of range") {
		t.Fatalf("huge iterations: err = %v, want iterations out of range", err)
	}
	for _, bad := range []string{"0", "-5"} {
		if _, _, _, err := ParseScramServerFirst(scramChallenge(t, "cn", "salt", bad), "cn"); err == nil {
			t.Fatalf("iterations=%s accepted", bad)
		}
	}
}

func TestParseScramServerFirstRejectsOversizedSalt(t *testing.T) {
	big := strings.Repeat("S", 4096)
	_, _, _, err := ParseScramServerFirst(scramChallenge(t, "cn", big, "4096"), "cn")
	if err == nil || !strings.Contains(err.Error(), "salt too large") {
		t.Fatalf("oversized salt: err = %v, want salt too large", err)
	}
}

func TestParseScramServerFirstRejectsNonceMismatch(t *testing.T) {
	_, _, _, err := ParseScramServerFirst(scramChallenge(t, "OTHER", "salt", "4096"), "cn")
	if err == nil || !strings.Contains(err.Error(), "doesn't start with client nonce") {
		t.Fatalf("nonce mismatch: err = %v", err)
	}
	_, _, _, err = ParseScramServerFirst("r=cnsrv,s=!!notb64!!,i=4096", "cn")
	if err == nil || !strings.Contains(err.Error(), "bad salt") {
		t.Fatalf("bad salt b64: err = %v", err)
	}
	_, _, _, err = ParseScramServerFirst("r=cnsrv,s=c2FsdA==,i=abc", "cn")
	if err == nil || !strings.Contains(err.Error(), "bad iterations") {
		t.Fatalf("bad iterations: err = %v", err)
	}
}
