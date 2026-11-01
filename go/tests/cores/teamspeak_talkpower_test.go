package tests

import (
	"errors"
	"net"
	"strconv"
	"testing"
	"time"
	. "uniclient/cores"
)

func TestNotifyClientUpdatedCapturesOwnTalkPower(t *testing.T) {
	m := ForTestNewTeamSpeakCore(false, nil, nil, nil, 0, 7, 0, nil)
	m.TsHandleServerCommand(tsResp(t, "notifyclientupdated clid=7 client_talk_power=20 client_servergroups=10"))

	m.ForTestClientInfoMu().RLock()
	got := m.ForTestMyTalkPower()
	m.ForTestClientInfoMu().RUnlock()
	if got != 20 {
		t.Errorf("myTalkPower = %d — notifyclientupdated carries client_talk_power for our clid and it must be captured (B-26)", got)
	}
}

func TestJoinChannelRefreshesTalkPower(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, tc, done := newExecHarness(t)
	defer done()
	core.ForTestSetAuthed(true)
	core.ForTestSetMyClientID(1)
	core.ForTestSetChannels(make(map[int]TsChannelInfo))

	go func() {
		time.Sleep(30 * time.Millisecond)
		tc.ForTestCmdCh() <- tsResp(t, "error id=0 msg=ok")
		time.Sleep(40 * time.Millisecond)
		tc.ForTestCmdCh() <- tsResp(t, "channel_id=7 channel_needed_talk_power=50")
		tc.ForTestCmdCh() <- tsResp(t, "error id=0 msg=ok")
	}()

	if err := core.JoinChannel(7, ""); err != nil {
		t.Fatalf("JoinChannel: %v", err)
	}

	deadline := time.Now().Add(2500 * time.Millisecond)
	for {
		core.ForTestChannelsMu().RLock()
		ch := core.ForTestChannels()[7]
		core.ForTestChannelsMu().RUnlock()
		if ch.ForTestTalkPowerKnown() {
			if ch.ForTestTalkPower() != 50 {
				t.Fatalf("talkPower = %d, want 50", ch.ForTestTalkPower())
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
	core := ForTestNewTeamSpeakCore(true, map[int]TsChannelInfo{7: *ForTestNewTsChannelInfo(7, 100, true)}, make(map[int]TsClientInfo), nil, 7, 1, 20, ForTestNewTsConnection(rx.LocalAddr().(*net.UDPAddr), nil, tx, true, nil, map[uint16]*TsPendingCmd{}, nil, [2]map[uint16]*TsDecryptedPkt{}, [64]byte{}))

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
	core := ForTestNewTeamSpeakCore(true, map[int]TsChannelInfo{7: *ForTestNewTsChannelInfo(7, 100, false)}, make(map[int]TsClientInfo), nil, 7, 1, 0, ForTestNewTsConnection(rx.LocalAddr().(*net.UDPAddr), nil, tx, true, nil, map[uint16]*TsPendingCmd{}, nil, [2]map[uint16]*TsDecryptedPkt{}, [64]byte{}))

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
	core := ForTestNewTeamSpeakCore(true, map[int]TsChannelInfo{7: *ForTestNewTsChannelInfo(7, 20, true)}, make(map[int]TsClientInfo), nil, 7, 1, 100, ForTestNewTsConnection(rx.LocalAddr().(*net.UDPAddr), nil, tx, true, nil, map[uint16]*TsPendingCmd{}, nil, [2]map[uint16]*TsDecryptedPkt{}, [64]byte{}))

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
	m := ForTestNewTeamSpeakCore(true, map[int]TsChannelInfo{7: *ForTestNewTsChannelInfo(7, 9999, true)}, make(map[int]TsClientInfo), nil, 7, 1, 20, nil)
	cs, err := m.GetGroupCall("ch:7")
	if err != nil {
		t.Fatalf("GetGroupCall: %v", err)
	}
	if cs.Meta["talk_power"] != "blocked" {
		t.Errorf("Meta[\"talk_power\"] = %q, want \"blocked\" — the polled UI path must see the dead-room state (B-26)", cs.Meta["talk_power"])
	}

	m.ForTestChannels()[7] = *ForTestNewTsChannelInfo(7, 5, true)
	cs, err = m.GetGroupCall("ch:7")
	if err != nil {
		t.Fatal(err)
	}
	if cs.Meta["talk_power"] != "ok" {
		t.Errorf("sufficient power Meta = %q, want ok", cs.Meta["talk_power"])
	}
	m.ForTestChannels()[7] = *ForTestNewTsChannelInfo(7, 0, false)
	cs, err = m.GetGroupCall("ch:7")
	if err != nil {
		t.Fatal(err)
	}
	if cs.Meta["talk_power"] != "unknown" {
		t.Errorf("unfetched channel Meta = %q, want unknown", cs.Meta["talk_power"])
	}
}

func TestMyChannelIDConcurrentMoveAndReadRace(t *testing.T) {
	m := ForTestNewTeamSpeakCore(true, make(map[int]TsChannelInfo), make(map[int]TsClientInfo), nil, 0, 1, 0, nil)
	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < 2000; i++ {
			m.TsHandleClientMoved(map[string]string{"clid": "1", "ctid": strconv.Itoa(7)})
		}
	}()
	for i := 0; i < 2000; i++ {
		_, _ = m.GetGroupCall("ch:7")
	}
	<-done
	m.ForTestClientInfoMu().RLock()
	got := m.ForTestMyChannelID()
	m.ForTestClientInfoMu().RUnlock()
	if got != 7 {
		t.Fatalf("myChannelID = %d, want 7 (move handler must be live)", got)
	}
}
