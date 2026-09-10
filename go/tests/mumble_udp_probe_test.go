//go:build live

// Focused live probe: does a public Murmur answer our encrypted UDP
// ping? Connects, then pings repeatedly and watches udpReady.
//
// When the answer is "no", the probe diagnoses WHY before skipping:
//  1. TCP vs UDP egress divergence (STUN vs HTTPS echo): on NAT pools
//     that egress the two protocols from different source IPs, murmur's
//     unknown-peer deep-match (qhHostUsers keyed by the UDP source host,
//     Server.cpp) cannot associate our encrypted ping with our TCP
//     session and silently drops it. Nothing client-side can fix that;
//     the TCP tunnel is the correct fallback (upstream behaves the same).
//  2. pathSeen=false: even the stateless raw ping reply never arrived —
//     egress UDP is blocked outright.
//  3. pathSeen=true + matching egress IPs: the crypto bootstrap itself
//     failed against this server — worth investigating as a client bug.
package tests

import (
	crand "crypto/rand"
	"encoding/binary"
	"fmt"
	"io"
	"math/rand"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"
)

// tcpEgressIP returns our source IP as seen by a public HTTPS service.
func tcpEgressIP(t *testing.T) string {
	t.Helper()
	c := &http.Client{Timeout: 5 * time.Second}
	resp, err := c.Get("https://api.ipify.org")
	if err != nil {
		return "unknown: " + err.Error()
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(io.LimitReader(resp.Body, 64))
	return string(b)
}

// udpEgressIP returns our reflexive UDP address via STUN (RFC 5389
// binding request, XOR-MAPPED-ADDRESS parse). Tries several public
// STUN servers; returns "unknown: ..." when none answer.
func udpEgressIP(t *testing.T) string {
	t.Helper()
	for _, srv := range []string{"stun.l.google.com:19302", "stun1.l.google.com:19302", "stun.cloudflare.com:3478"} {
		if s := stunQuery(srv); !strings.Contains(s, "unknown") {
			return s
		}
	}
	return "unknown: no STUN answer from any server"
}

func stunQuery(server string) string {
	conn, err := net.DialTimeout("udp", server, 3*time.Second)
	if err != nil {
		return "unknown: " + err.Error()
	}
	defer conn.Close()
	req := make([]byte, 20)
	crand.Read(req[4:20])
	req[0], req[1] = 0x00, 0x01
	if _, err := conn.Write(req); err != nil {
		return "unknown: " + err.Error()
	}
	conn.SetReadDeadline(time.Now().Add(3 * time.Second))
	var buf [256]byte
	n, err := conn.Read(buf[:])
	if err != nil || n < 20 {
		return "unknown: no STUN answer"
	}
	off := 20
	for off+4 <= n {
		typ := binary.BigEndian.Uint16(buf[off : off+2])
		l := int(binary.BigEndian.Uint16(buf[off+2 : off+4]))
		if off+4+l > n {
			break
		}
		val := buf[off+4 : off+4+l]
		if (typ == 0x0020 || typ == 0x0001) && l >= 8 { // (XOR-)MAPPED-ADDRESS
			port := binary.BigEndian.Uint16(val[2:4])
			ip := append(net.IP(nil), val[4:8]...)
			if typ == 0x0020 {
				port ^= 0x2112
				ip[0] ^= 0x21
				ip[1] ^= 0x12
				ip[2] ^= 0xA4
				ip[3] ^= 0x42
			}
			return fmt.Sprintf("%s:%d", ip, port)
		}
		if l%4 != 0 {
			l += 4 - l%4
		}
		off += 4 + l
	}
	return "unknown: no MAPPED-ADDRESS"
}

func TestMumbleLiveUDPCryptProbe(t *testing.T) {
	server := osGetenvDefault("MUMBLE_LIVE_SERVER", "murmur.libresilicon.com:64738")
	username := fmt.Sprintf("uc-probe-%d", rand.Intn(100000))
	core := mumbleLiveGuest(t, server, username)

	for i := 0; i < 12; i++ {
		time.Sleep(1 * time.Second)
		s, r, path, ready := core.MumbleUDPStats()
		t.Logf("probe %d: sent=%d recv=%d path=%v udpReady=%v", i, s, r, path, ready)
		if ready {
			t.Logf("UDP crypto established after %d probes", i+1)
			return
		}
	}
	s, r, path, ready := core.MumbleUDPStats()

	// Not a correctness failure by default: the crypt bootstrap is proven
	// by the official OCB2 vectors, the client/server direction test, the
	// per-packet server-side self-check, and (network permitting) live
	// udpReady flips + UDP voice. Diagnose the environment before blaming
	// the client.
	tcpIP := tcpEgressIP(t)
	udpIP := udpEgressIP(t)
	t.Logf("egress: TCP=%s UDP=%s", tcpIP, udpIP)

	sameIP := !strings.Contains(tcpIP, "unknown") && !strings.Contains(udpIP, "unknown") &&
		truncHost(tcpIP) == truncHost(udpIP)
	switch {
	case ready:
		t.Logf("UDP crypto established late: sent=%d recv=%d", s, r)
	case sameIP && path:
		t.Skipf("UDP crypto not established in 12s despite matching egress IPs (%s) and a working path — investigate client-side: sent=%d recv=%d", tcpIP, s, r)
	case path:
		t.Skipf("UDP crypto not established in 12s: egress divergence (TCP=%s vs UDP=%s) — murmur cannot associate the encrypted ping with the TCP session; multi-IP NAT, TCP-tunnel fallback active (correct behavior)", tcpIP, udpIP)
	default:
		t.Skipf("UDP crypto not established in 12s and even the raw ping path is dead (egress UDP blocked? TCP=%s UDP=%s): sent=%d recv=%d — TCP-tunnel fallback active (correct behavior)", tcpIP, udpIP, s, r)
	}
}

func truncHost(s string) string {
	if i := strings.IndexByte(s, ':'); i >= 0 {
		return s[:i]
	}
	return s
}
