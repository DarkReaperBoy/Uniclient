package tests

import (
	"errors"
	"net"
	"strconv"
	"strings"
	"testing"
	"time"

	. "uniclient/cores"
)

func tsTalkPowerChannels() []string {
	return []string{"cid=7 pid=0 channel_name=Lobby channel_topic= total_clients=0 channel_order=0"}
}

func TestNotifyClientUpdatedCapturesOwnTalkPower(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{ClientID: 1, ChannelLines: tsTalkPowerChannels()})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "channelinfo") {
			return []string{"channel_id=7 channel_needed_talk_power=9999", "error id=0 msg=ok"}
		}
		return nil
	})

	cs, err := core.GetGroupCall("ch:7")
	if err != nil {
		t.Fatalf("GetGroupCall: %v", err)
	}
	if cs.Meta["talk_power"] != "unknown" {
		t.Errorf("before any own talk power: meta = %q, want unknown", cs.Meta["talk_power"])
	}

	core.TsRefreshChannelTalkPower(7)
	if cs, _ = core.GetGroupCall("ch:7"); cs.Meta["talk_power"] != "unknown" {
		t.Errorf("channel power known but own power still absent: meta = %q, want unknown", cs.Meta["talk_power"])
	}

	srv.Push("notifyclientupdated clid=99 client_talk_power=99999 client_servergroups=10")
	srv.Push("notifyclientupdated clid=1 client_talk_power=20 client_servergroups=10")

	deadline := time.Now().Add(2 * time.Second)
	for {
		cs, err := core.GetGroupCall("ch:7")
		if err != nil {
			t.Fatalf("GetGroupCall: %v", err)
		}
		if cs.Meta["talk_power"] == "blocked" {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("own notifyclientupdated talk power not captured (B-26): meta = %q, want blocked (20 < 9999) — and NOT ok, which a captured foreign clid=99 power of 99999 would produce", cs.Meta["talk_power"])
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func TestJoinChannelRefreshesTalkPower(t *testing.T) {
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{ClientID: 1, ChannelLines: tsTalkPowerChannels()})
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "clientmove") {
			return []string{"notifyclientmoved clid=1 ctid=7", "error id=0 msg=ok"}
		}
		if strings.HasPrefix(line, "channelinfo") {
			return []string{"channel_id=7 channel_needed_talk_power=50", "error id=0 msg=ok"}
		}
		return nil
	})
	srv.Push("notifyclientupdated clid=1 client_talk_power=20")

	if err := core.JoinChannel(7, ""); err != nil {
		t.Fatalf("JoinChannel: %v", err)
	}

	deadline := time.Now().Add(2500 * time.Millisecond)
	for {
		cs, err := core.GetGroupCall("ch:7")
		if err != nil {
			t.Fatalf("GetGroupCall: %v", err)
		}
		if cs.Meta["talk_power"] == "blocked" {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("channel talk power never populated after join (B-26): meta = %q — channel_needed_talk_power requires channelinfo, which nobody fetched", cs.Meta["talk_power"])
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
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{ClientID: 1, ChannelLines: tsTalkPowerChannels()})
	var q tsScriptedQueue
	srv.SetResponder(func(string) []string { return q.take() })

	cs, err := core.GetGroupCall("ch:7")
	if err != nil {
		t.Fatalf("GetGroupCall: %v", err)
	}
	if cs.Meta["talk_power"] != "unknown" {
		t.Errorf("unfetched channel Meta = %q, want unknown — the polled UI path must see the dead-room state (B-26)", cs.Meta["talk_power"])
	}

	q.add("channel_id=7 channel_needed_talk_power=9999", "error id=0 msg=ok")
	core.TsRefreshChannelTalkPower(7)
	if cs, err = core.GetGroupCall("ch:7"); err != nil {
		t.Fatal(err)
	}
	if cs.Meta["talk_power"] != "unknown" {
		t.Errorf("channel power fetched but own power still absent: meta = %q, want unknown", cs.Meta["talk_power"])
	}

	srv.Push("notifyclientupdated clid=1 client_talk_power=20")
	waitTalkPower(t, core, "blocked")

	q.add("channel_id=7 channel_needed_talk_power=5", "error id=0 msg=ok")
	core.TsRefreshChannelTalkPower(7)
	if cs, err = core.GetGroupCall("ch:7"); err != nil {
		t.Fatal(err)
	}
	if cs.Meta["talk_power"] != "ok" {
		t.Errorf("sufficient power Meta = %q, want ok", cs.Meta["talk_power"])
	}
}

func waitTalkPower(t *testing.T, core *TeamSpeakCore, want string) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for {
		cs, err := core.GetGroupCall("ch:7")
		if err != nil {
			t.Fatalf("GetGroupCall: %v", err)
		}
		if cs.Meta["talk_power"] == want {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("talk power meta never settled on %q: %q", want, cs.Meta["talk_power"])
		}
		time.Sleep(20 * time.Millisecond)
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
	cs, err := m.GetGroupCall("ch:7")
	if err != nil {
		t.Fatalf("GetGroupCall: %v", err)
	}
	selfInRoom := false
	for _, p := range cs.Participants {
		if p.UserID == "1" {
			selfInRoom = true
		}
	}
	if !selfInRoom {
		t.Fatalf("self not among ch:7 participants after 2000 moves (move handler must be live): %+v", cs.Participants)
	}
}
