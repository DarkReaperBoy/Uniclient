//go:build live

package tests

import (
	"fmt"
	"math/rand"
	"sort"
	"strconv"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/utils"
	"uniclient/voice"
)

func TestTeamSpeakLiveVoiceRoundTrip(t *testing.T) {
	server := osGetenvDefault("TS3_LIVE_SERVER", "ts.arcticblaze.net:9987")
	nickA := fmt.Sprintf("uc-voice-%d", rand.Intn(100000))

	dir := t.TempDir()
	vault, err := utils.CreateVault(dir+"/test.vault", "live-test")
	if err != nil {
		t.Fatalf("CreateVault: %v", err)
	}
	t.Cleanup(func() { vault.Close() })

	coreA := cores.NewTeamSpeakCore(utils.NewSessionStore(vault, "ts3-voice-a"))
	defer coreA.Close()
	if err := coreA.Authenticate(cores.AuthConfig{Extra: map[string]string{
		"server_address": server,
		"nickname":       nickA,
	}}); err != nil {
		t.Skipf("handshake failed on %s: %v", server, err)
	}

	coreB := cores.NewTeamSpeakCore(utils.NewSessionStore(vault, "ts3-voice-b"))
	defer coreB.Close()
	if err := coreB.Authenticate(cores.AuthConfig{Extra: map[string]string{
		"server_address": server,
		"nickname":       nickA + "-b",
	}}); err != nil {
		t.Skipf("B handshake failed on %s: %v", server, err)
	}

	dialogs, err := coreA.GetDialogs(cores.PaginationOpts{Limit: 100})
	if err != nil {
		t.Fatalf("GetDialogs: %v", err)
	}
	type cand struct {
		id    string
		count int
	}
	var cands []cand
	for _, d := range dialogs {
		if len(d.ID) < 4 || d.ID[:3] != "ch:" {
			continue
		}
		cands = append(cands, cand{d.ID, d.MemberCount})
	}
	if len(cands) == 0 {
		t.Fatal("no channels")
	}
	sort.Slice(cands, func(i, j int) bool { return cands[i].count < cands[j].count })
	if len(cands) > 5 {
		cands = cands[:5]
	}
	t.Logf("candidate channels: %v", cands)

	whoRows, err := coreA.RawExec("whoami")
	if err != nil || len(whoRows) == 0 {
		t.Fatalf("whoami: %v", err)
	}
	myTalkPower := -1
	if ci, err := coreA.RawExec("clientinfo clid=" + whoRows[0]["client_id"]); err == nil && len(ci) > 0 {
		if p, perr := strconv.Atoi(ci[0]["client_talk_power"]); perr == nil {
			myTalkPower = p
		}
	} else {
		t.Logf("clientinfo for own talk power failed (%v) — power filter disabled for this run", err)
	}
	t.Logf("guest talk power: %d", myTalkPower)
	powerCache := map[string]bool{}
	powerOK := func(cid string) bool {
		if v, ok := powerCache[cid]; ok {
			return v
		}
		v := true
		if myTalkPower >= 0 && len(cid) > 3 {
			v = false
			if rows, err := coreA.RawExec("channelinfo cid=" + cid[3:]); err == nil && len(rows) > 0 {
				if need, nerr := strconv.Atoi(rows[0]["channel_needed_talk_power"]); nerr == nil {
					v = need <= myTalkPower
				}
			}
		}
		powerCache[cid] = v
		return v
	}

	defaultRoom := fmt.Sprintf("ch:%d", coreA.DefaultChannelID())
	var tryRooms []string
	for _, c := range cands {
		tryRooms = append(tryRooms, c.id)
	}
	tryRooms = append(tryRooms, defaultRoom)
	joinRoom := func(core *cores.TeamSpeakCore, who string) string {
		for _, cid := range tryRooms {
			if !powerOK(cid) {
				t.Logf("%s skipping %s: talk power gated (server would drop its voice)", who, cid)
				continue
			}
			cs, err := core.JoinGroupCall(cid)
			if err == nil && cs != nil {
				return cid
			}
			t.Logf("%s cannot join %s (%v)", who, cid, err)
		}
		t.Skipf("%s: no channel available for guest voice (joinable AND talk power ≤ %d) — server config/permissions, environment not client", who, myTalkPower)
		return ""
	}
	roomA := joinRoom(coreA, "A")
	roomB := joinRoom(coreB, "B")
	if roomA != roomB {
		t.Skipf("A and B ended up in different channels (%s vs %s) — asymmetric guest permissions, environment not client", roomA, roomB)
	}
	bestID := roomA
	time.Sleep(700 * time.Millisecond)

	physCh := func(c *cores.TeamSpeakCore, label string) string {
		info, err := c.WhoAmI()
		if err != nil {
			t.Fatalf("whoami %s: %v", label, err)
		}
		return "ch:" + info["client_channel_id"]
	}
	for attempt := 0; ; attempt++ {
		pa, pb := physCh(coreA, "A"), physCh(coreB, "B")
		if pa == bestID && pb == bestID {
			break
		}
		if attempt >= 1 {
			t.Skipf("server relocated clients apart (A=%s B=%s, room=%s) — PrivateChannelManager-style bot, environment not client (B-22)", pa, pb, bestID)
		}
		t.Logf("server relocation detected: A=%s B=%s want %s — rejoining", pa, pb, bestID)
		if _, err := coreA.JoinGroupCall(bestID); err != nil {
			t.Logf("A rejoin: %v", err)
		}
		if _, err := coreB.JoinGroupCall(bestID); err != nil {
			t.Logf("B rejoin: %v", err)
		}
		time.Sleep(700 * time.Millisecond)
	}

	gc, err := coreB.GetGroupCall(bestID)
	if err != nil {
		t.Fatalf("GetGroupCall: %v", err)
	}
	for _, p := range gc.Participants {
		t.Logf("room member: %q (muted=%v speaking=%v)", p.DisplayName, p.IsMuted, p.IsSpeaking)
	}
	if len(gc.Participants) < 2 {
		t.Logf("warning: cache lists %d members in %s though whoami put both clients there — clientInfo view is stale/incomplete", len(gc.Participants), bestID)
	}

	type vpkt struct {
		clientID int
		codec    byte
		opus     []byte
	}
	recv := make(chan vpkt, 256)
	coreB.OnVoice(func(p cores.VoicePacket) {
		if len(p.AudioData) == 0 {
			return
		}
		recv <- vpkt{clientID: p.SenderClientID, codec: p.Codec, opus: p.AudioData}
	})

	enc, err := voice.NewEncoder(24000)
	if err != nil {
		t.Fatalf("encoder: %v", err)
	}
	frames := genToneFrames(440, 0.5, 1.5)
	go func() {
		for _, f := range frames {
			pkt, err := enc.Encode(f)
			if err != nil {
				t.Errorf("encode: %v", err)
				return
			}
			if err := coreA.SendVoice(4, pkt); err != nil {
				t.Errorf("SendVoice: %v", err)
				return
			}
			time.Sleep(voice.FrameDuration)
		}
	}()

	deadline := time.After(10 * time.Second)
	var got []vpkt
collect:
	for {
		select {
		case p := <-recv:
			got = append(got, p)
			if len(got) >= len(frames) {
				break collect
			}
		case <-deadline:
			break collect
		}
	}
	t.Logf("B received %d voice packets (sent %d frames)", len(got), len(frames))
	if len(got) < len(frames)/2 {
		fa, fb := physCh(coreA, "A"), physCh(coreB, "B")
		if fa != bestID || fb != bestID {
			t.Skipf("server relocated clients during the stream (A=%s B=%s, room=%s) — environment, not client (B-22)", fa, fb, bestID)
		}
		t.Fatalf("too few voice packets received: %d with both clients still in %s — S2C voice decrypt/routing broken", len(got), bestID)
	}

	senders := map[int]int{}
	for _, p := range got {
		if p.codec != 4 {
			t.Fatalf("unexpected codec %d (want 4 = Opus voice)", p.codec)
		}
		senders[p.clientID]++
	}
	if len(senders) != 1 {
		t.Fatalf("expected exactly one voice sender, got %d", len(senders))
	}

	dec := voice.NewDecoder()
	var stream []int16
	for _, p := range got {
		s, err := dec.Decode(p.opus)
		if err != nil {
			t.Fatalf("decode: %v", err)
		}
		stream = append(stream, s...)
	}
	if len(stream) < voice.SampleRate/2 {
		t.Fatalf("decoded only %d samples", len(stream))
	}
	m440 := goertzelMag(stream, 440)
	m880 := goertzelMag(stream, 880)
	m300 := goertzelMag(stream, 300)
	t.Logf("decoded %.2fs: 440Hz=%.4f 880Hz=%.4f 300Hz=%.4f rms=%.4f",
		float64(len(stream))/float64(voice.SampleRate), m440, m880, m300, rms16(stream))
	if rms16(stream) < 0.05 {
		t.Fatalf("decoded audio is near-silent (rms %.4f)", rms16(stream))
	}
	if m440 < 0.05 || m440 < m880*2 || m440 < m300*2 {
		t.Fatalf("440 Hz tone did not survive the round-trip: 440=%.4f 880=%.4f 300=%.4f", m440, m880, m300)
	}
	t.Log("TS3 VOICE ROUND-TRIP OK: EAX voice decryption + opus decode with the tone intact")
}
