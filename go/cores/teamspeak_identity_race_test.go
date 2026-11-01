package cores

import (
	"net"
	"testing"
)

func TestHandshakeClientIDWriteDoesNotRaceTheReceiveLoop(t *testing.T) {
	tx, rx := udpVoicePair(t)
	tc := &tsConnection{
		conn:        tx,
		addr:        rx.LocalAddr().(*net.UDPAddr),
		pendingCmds: map[uint16]*tsPendingCmd{},
		cryptoOK:    true,
	}

	done := make(chan struct{})
	var sendErrs int
	go func() {
		defer close(done)
		for i := uint16(1); i <= 500; i++ {
			tc.clientID.Store(uint32(i))
		}
	}()
	for i := uint16(0); i < 500; i++ {
		if err := tc.tsSendAck(i); err != nil {
			sendErrs++
		}
		if err := tc.tsSendPong(i); err != nil {
			sendErrs++
		}
	}
	<-done
	if sendErrs != 0 {
		t.Fatalf("%d send errors during the race battery", sendErrs)
	}
	if got := tc.clientID.Load(); got != 500 {
		t.Fatalf("clientID = %d, want 500 (write site must be live)", got)
	}
}

func TestHandshakeMyClientIDWriteDoesNotRaceReceiveHandlers(t *testing.T) {
	m := &TeamSpeakCore{myClientID: 1}

	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 1; i <= 500; i++ {
			m.clientInfoMu.Lock()
			m.myClientID = i
			m.clientInfoMu.Unlock()
		}
	}()
	for i := 0; i < 500; i++ {
		m.clientInfoMu.RLock()
		_ = m.myClientID == 1
		m.clientInfoMu.RUnlock()
	}
	<-done
	m.clientInfoMu.RLock()
	got := m.myClientID
	m.clientInfoMu.RUnlock()
	if got != 500 {
		t.Fatalf("myClientID = %d, want 500 (write site must be live)", got)
	}
}
