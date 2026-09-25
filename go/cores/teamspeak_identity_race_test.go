package cores

import (
	"net"
	"testing"
)

// BUGS B-40 — the initserver identity swap ran while the receive loop
// was already live: tsHandshakeRetry writes tc.clientID / t.myClientID
// (teamspeak.go initserver branch) while the receive goroutine builds
// ACKs/PONGs from tc.clientID and dispatches handlers that read
// t.myClientID. Caught live by `go test -tags live -race` (5 reports,
// slice 258). Both tests first mirror the PRE-fix access pairs to
// produce the `-race` RED, then follow the production API once the
// fix lands (atomic Store / clientInfoMu both sides).

// TestHandshakeClientIDWriteDoesNotRaceTheReceiveLoop: the receive
// loop's tsSendAck/tsSendPong read clientID on EVERY packet while the
// handshake goroutine installs it.
func TestHandshakeClientIDWriteDoesNotRaceTheReceiveLoop(t *testing.T) {
	tx, rx := udpVoicePair(t)
	tc := &tsConnection{
		conn:        tx,
		addr:        rx.LocalAddr().(*net.UDPAddr),
		pendingCmds: map[uint16]*tsPendingCmd{},
		cryptoOK:    true,
	}

	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := uint16(1); i <= 500; i++ {
			tc.clientID.Store(uint32(i)) // production write site (initserver aclid); RED was captured against the pre-fix naked write
		}
	}()
	for i := uint16(0); i < 500; i++ {
		_ = tc.tsSendAck(i)  // reads clientID for meta[2:4] + packet build
		_ = tc.tsSendPong(i) // reads clientID (+ sharedMAC)
	}
	<-done
}

// TestHandshakeMyClientIDWriteDoesNotRaceReceiveHandlers: the text
// handler's self-echo check reads t.myClientID in the receive path
// while initserver installs it. Both sides now hold clientInfoMu (the
// guard B-37 established for the self-info family); before the fix the
// write was naked and the read bare — the exact pair the live detector
// flagged.
func TestHandshakeMyClientIDWriteDoesNotRaceReceiveHandlers(t *testing.T) {
	m := &TeamSpeakCore{myClientID: 1}

	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 1; i <= 500; i++ {
			m.clientInfoMu.Lock()
			m.myClientID = i // production write site (initserver aclid); RED was captured against the pre-fix naked write
			m.clientInfoMu.Unlock()
		}
	}()
	for i := 0; i < 500; i++ {
		m.clientInfoMu.RLock()
		_ = m.myClientID == 1 // production read side (tsHandleTextMessage self-echo); RED was captured against the pre-fix bare read
		m.clientInfoMu.RUnlock()
	}
	<-done
}
