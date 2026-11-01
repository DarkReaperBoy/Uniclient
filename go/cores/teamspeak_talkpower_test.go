package cores

import (
	"errors"
	"net"
	"strconv"
	"testing"
	"time"
)

func TestNotifyClientUpdatedCapturesOwnTalkPower(t *testing.T) {
	m := &TeamSpeakCore{myClientID: 7}
	m.tsHandleServerCommand(tsResp(t, "notifyclientupdated clid=7 client_talk_power=20 client_servergroups=10"))

	m.clientInfoMu.RLock()
	got := m.myTalkPower
	m.clientInfoMu.RUnlock()
	if got != 20 {
		t.Errorf("myTalkPower = %d — notifyclientupdated carries client_talk_power for our clid and it must be captured (B-26)", got)
	}
}

func TestJoinChannelRefreshesTalkPower(t *testing.T) {
	old := tsExecVoidTimeout
	tsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { tsExecVoidTimeout = old })

	core, tc, done := newExecHarness(t)
	defer done()
	core.authed = true
	core.myClientID = 1
	core.channels = make(map[int]tsChannelInfo)

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.cmdCh <- tsResp(t, "error id=0 msg=ok")
		time.Sleep(40 * time.Millisecond)
		tc.cmdCh <- tsResp(t, "channel_id=7 channel_needed_talk_power=50")
		tc.cmdCh <- tsResp(t, "error id=0 msg=ok")
	}()

	if err := core.JoinChannel(7, ""); err != nil {
		t.Fatalf("JoinChannel: %v", err)
	}

	deadline := time.Now().Add(2500 * time.Millisecond)
	for {
		core.channelsMu.RLock()
		ch := core.channels[7]
		core.channelsMu.RUnlock()
		if ch.talkPowerKnown {
			if ch.talkPower != 50 {
				t.Fatalf("talkPower = %d, want 50", ch.talkPower)
			}
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("channel talk power never populated after join (B-26): %+v — channel_needed_talk_power requires channelinfo, which nobody fetched", ch)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func udpVoicePair(t *testing.T) (*net.UDPConn, *net.UDPConn) {
	t.Helper()
	rx, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	tx, err := net.ListenUDP("udp", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		rx.Close()
		t.Fatal(err)
	}
	t.Cleanup(func() { rx.Close(); tx.Close() })
	return tx, rx
}

func TestSendVoiceBlockedWhenTalkPowerInsufficient(t *testing.T) {
	tx, rx := udpVoicePair(t)
	core := &TeamSpeakCore{
		authed:      true,
		myClientID:  1,
		myChannelID: 7,
		myTalkPower: 20,
		channels:    map[int]tsChannelInfo{7: {cid: 7, talkPower: 100, talkPowerKnown: true}},
		clientInfo:  make(map[int]tsClientInfo),
		tsConn: &tsConnection{
			conn: tx, addr: rx.LocalAddr().(*net.UDPAddr),
			cryptoOK:    true,
			pendingCmds: map[uint16]*tsPendingCmd{},
		},
	}

	err := core.SendVoice(4, []byte("opus-frame"))
	if !errors.Is(err, ErrPermission) {
		t.Errorf("SendVoice into a known-blocked room returned %v — want ErrPermission (B-26): audio would die silently server-side", err)
	}
	rx.SetReadDeadline(time.Now().Add(150 * time.Millisecond))
	buf := make([]byte, 1500)
	if _, _, rerr := rx.ReadFromUDP(buf); rerr == nil {
		t.Errorf("a voice packet was still sent into the blocked room (B-26)")
	}
}

func TestSendVoiceFailsOpenWhileUnknown(t *testing.T) {
	tx, rx := udpVoicePair(t)
	core := &TeamSpeakCore{
		authed:      true,
		myClientID:  1,
		myChannelID: 7,
		myTalkPower: 0,
		channels:    map[int]tsChannelInfo{7: {cid: 7, talkPower: 100, talkPowerKnown: false}},
		clientInfo:  make(map[int]tsClientInfo),
		tsConn: &tsConnection{
			conn: tx, addr: rx.LocalAddr().(*net.UDPAddr),
			cryptoOK:    true,
			pendingCmds: map[uint16]*tsPendingCmd{},
		},
	}

	if err := core.SendVoice(4, []byte("opus-frame")); err != nil {
		t.Fatalf("SendVoice with unknown talk power = %v — must fail open until channelinfo lands", err)
	}
	rx.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
	buf := make([]byte, 1500)
	if _, _, err := rx.ReadFromUDP(buf); err != nil {
		t.Errorf("fail-open send produced no packet: %v", err)
	}
}

func TestSendVoiceAllowedWhenPowerSufficient(t *testing.T) {
	tx, rx := udpVoicePair(t)
	core := &TeamSpeakCore{
		authed:      true,
		myClientID:  1,
		myChannelID: 7,
		myTalkPower: 100,
		channels:    map[int]tsChannelInfo{7: {cid: 7, talkPower: 20, talkPowerKnown: true}},
		clientInfo:  make(map[int]tsClientInfo),
		tsConn: &tsConnection{
			conn: tx, addr: rx.LocalAddr().(*net.UDPAddr),
			cryptoOK:    true,
			pendingCmds: map[uint16]*tsPendingCmd{},
		},
	}

	if err := core.SendVoice(4, []byte("opus-frame")); err != nil {
		t.Fatalf("SendVoice with sufficient power = %v", err)
	}
	rx.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
	buf := make([]byte, 1500)
	if _, _, err := rx.ReadFromUDP(buf); err != nil {
		t.Errorf("allowed send produced no packet: %v", err)
	}
}

func TestGetGroupCallReportsTalkPowerBlocked(t *testing.T) {
	m := &TeamSpeakCore{
		authed:      true,
		myClientID:  1,
		myChannelID: 7,
		myTalkPower: 20,
		channels:    map[int]tsChannelInfo{7: {cid: 7, talkPower: 9999, talkPowerKnown: true}},
		clientInfo:  make(map[int]tsClientInfo),
	}
	cs, err := m.GetGroupCall("ch:7")
	if err != nil {
		t.Fatalf("GetGroupCall: %v", err)
	}
	if cs.Meta["talk_power"] != "blocked" {
		t.Errorf("Meta[\"talk_power\"] = %q, want \"blocked\" — the polled UI path must see the dead-room state (B-26)", cs.Meta["talk_power"])
	}

	m.channels[7] = tsChannelInfo{cid: 7, talkPower: 5, talkPowerKnown: true}
	cs, err = m.GetGroupCall("ch:7")
	if err != nil {
		t.Fatal(err)
	}
	if cs.Meta["talk_power"] != "ok" {
		t.Errorf("sufficient power Meta = %q, want ok", cs.Meta["talk_power"])
	}
	m.channels[7] = tsChannelInfo{cid: 7}
	cs, err = m.GetGroupCall("ch:7")
	if err != nil {
		t.Fatal(err)
	}
	if cs.Meta["talk_power"] != "unknown" {
		t.Errorf("unfetched channel Meta = %q, want unknown", cs.Meta["talk_power"])
	}
}

func TestMyChannelIDConcurrentMoveAndReadRace(t *testing.T) {
	m := &TeamSpeakCore{
		authed:     true,
		myClientID: 1,
		channels:   make(map[int]tsChannelInfo),
		clientInfo: make(map[int]tsClientInfo),
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < 2000; i++ {
			m.tsHandleClientMoved(map[string]string{"clid": "1", "ctid": strconv.Itoa(7)})
		}
	}()
	for i := 0; i < 2000; i++ {
		_, _ = m.GetGroupCall("ch:7")
	}
	<-done
	m.clientInfoMu.RLock()
	got := m.myChannelID
	m.clientInfoMu.RUnlock()
	if got != 7 {
		t.Fatalf("myChannelID = %d, want 7 (move handler must be live)", got)
	}
}
