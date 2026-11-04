package tests

import (
	"errors"
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

func newVoiceJourneyCore(t *testing.T, neededPower string) (*TeamSpeakCore, *tsScriptedServer) {
	t.Helper()
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })
	core, srv := newScriptedTSCore(t, tsScriptedConfig{ClientID: 1, ChannelLines: tsTalkPowerChannels()})
	var q tsScriptedQueue
	srv.SetResponder(func(line string) []string {
		if strings.HasPrefix(line, "channelinfo") {
			return q.take()
		}
		return nil
	})
	srv.Push("notifyclientmoved clid=1 ctid=7")
	waitSelfInChannel(t, core)
	q.add("channel_id=7 channel_needed_talk_power="+neededPower, "error id=0 msg=ok")
	core.TsRefreshChannelTalkPower(7)
	return core, srv
}

func waitSelfInChannel(t *testing.T, core *TeamSpeakCore) {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for {
		cs, err := core.GetGroupCall("ch:7")
		if err != nil {
			t.Fatalf("GetGroupCall: %v", err)
		}
		for _, p := range cs.Participants {
			if p.UserID == "1" {
				return
			}
		}
		if time.Now().After(deadline) {
			t.Fatalf("self never landed in ch:7 participants: %+v", cs.Participants)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func TestSendVoiceBlockedWhenTalkPowerInsufficient(t *testing.T) {
	core, srv := newVoiceJourneyCore(t, "9999")
	srv.Push("notifyclientupdated clid=1 client_talk_power=20")
	waitTalkPower(t, core, "blocked")

	if err := core.SendVoice(4, []byte("opus-frame")); !errors.Is(err, ErrPermission) {
		t.Errorf("SendVoice into a known-blocked room returned %v — want ErrPermission (B-26): audio would die silently server-side", err)
	}
	time.Sleep(150 * time.Millisecond)
	if got := srv.VoiceCount(); got != 0 {
		t.Errorf("a voice packet was still sent into the blocked room (B-26): the server received %d", got)
	}
}

func TestSendVoiceFailsOpenWhileUnknown(t *testing.T) {
	core, srv := newVoiceJourneyCore(t, "9999")

	if err := core.SendVoice(4, []byte("opus-frame")); err != nil {
		t.Fatalf("SendVoice with unknown talk power = %v — must fail open until channelinfo lands", err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for srv.VoiceCount() < 1 && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if got := srv.VoiceCount(); got < 1 {
		t.Fatalf("fail-open send produced no packet on the wire: server received %d", got)
	}
	assertOpusFrame(t, srv.LastVoicePayload())
}

func TestSendVoiceAllowedWhenPowerSufficient(t *testing.T) {
	core, srv := newVoiceJourneyCore(t, "20")
	srv.Push("notifyclientupdated clid=1 client_talk_power=100")
	waitTalkPower(t, core, "ok")

	if err := core.SendVoice(4, []byte("opus-frame")); err != nil {
		t.Fatalf("SendVoice with sufficient power = %v", err)
	}
	deadline := time.Now().Add(2 * time.Second)
	for srv.VoiceCount() < 1 && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if got := srv.VoiceCount(); got < 1 {
		t.Fatalf("allowed send produced no packet on the wire: server received %d", got)
	}
	assertOpusFrame(t, srv.LastVoicePayload())
}

func assertOpusFrame(t *testing.T, voice []byte) {
	t.Helper()
	if len(voice) != 3+len("opus-frame") || voice[2] != 4 || string(voice[3:]) != "opus-frame" {
		t.Errorf("server decoded voice payload %q — want codec byte 4 followed by the opus frame", voice)
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
	old := TsExecVoidTimeout
	TsExecVoidTimeout = 2 * time.Second
	t.Cleanup(func() { TsExecVoidTimeout = old })

	core, srv := newScriptedTSCore(t, tsScriptedConfig{ClientID: 1, ChannelLines: tsTalkPowerChannels()})
	done := make(chan struct{})
	go func() {
		defer close(done)
		for i := 0; i < 2000; i++ {
			srv.Push("notifyclientmoved clid=1 ctid=7")
			if i%25 == 24 {
				time.Sleep(2 * time.Millisecond)
			}
		}
	}()
	for i := 0; i < 2000; i++ {
		_, _ = core.GetGroupCall("ch:7")
	}
	<-done

	deadline := time.Now().Add(2 * time.Second)
	for {
		cs, err := core.GetGroupCall("ch:7")
		if err != nil {
			t.Fatalf("GetGroupCall: %v", err)
		}
		selfInRoom := false
		for _, p := range cs.Participants {
			if p.UserID == "1" {
				selfInRoom = true
			}
		}
		if selfInRoom {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("self not among ch:7 participants after 2000 wire moves (move handler must be live): %+v", cs.Participants)
		}
		time.Sleep(20 * time.Millisecond)
	}
}
