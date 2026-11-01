package tests

import (
	"net"
	"testing"
	. "uniclient/cores"
)

func TestHandshakeClientIDWriteDoesNotRaceTheReceiveLoop(t *testing.T) {
	tx, rx := udpVoicePair(t)
	tc := ForTestNewTsConnection(rx.LocalAddr().(*net.UDPAddr), nil, tx, true, nil, map[uint16]*TsPendingCmd{}, nil, [2]map[uint16]*TsDecryptedPkt{}, [64]byte{})

	done := make(chan struct{})
	var sendErrs int
	go func() {
		defer close(done)
		for i := uint16(1); i <= 500; i++ {
			tc.ForTestClientID().Store(uint32(i))
		}
	}()
	for i := uint16(0); i < 500; i++ {
		if err := tc.ForTestTsSendAck(i); err != nil {
			sendErrs++
		}
		if err := tc.ForTestTsSendPong(i); err != nil {
			sendErrs++
		}
	}
	<-done
	if sendErrs != 0 {
		t.Fatalf("%d send errors during the race battery", sendErrs)
	}
	if got := tc.ForTestClientID().Load(); got != 500 {
		t.Fatalf("clientID = %d, want 500 (write site must be live)", got)
	}
}

func TestHandshakeMyClientIDWriteDoesNotRaceReceiveHandlers(t *testing.T) {
	m := ForTestNewTeamSpeakCore(false, nil, nil, nil, 0, 1, 0, nil)

	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 1; i <= 500; i++ {
			m.ForTestClientInfoMu().Lock()
			m.ForTestSetMyClientID(i)
			m.ForTestClientInfoMu().Unlock()
		}
	}()
	for i := 0; i < 500; i++ {
		m.ForTestClientInfoMu().RLock()
		_ = m.ForTestMyClientID() == 1
		m.ForTestClientInfoMu().RUnlock()
	}
	<-done
	m.ForTestClientInfoMu().RLock()
	got := m.ForTestMyClientID()
	m.ForTestClientInfoMu().RUnlock()
	if got != 500 {
		t.Fatalf("myClientID = %d, want 500 (write site must be live)", got)
	}
}
