//go:build live

// Live VOICE round-trip test for the TeamSpeak core against a REAL public
// TS3 server: two guests join the same channel, client A streams 1.5 s of
// Opus-encoded audio (440 Hz sine) as TS3 voice packets (codec 4, EAX
// voice encryption, per-type packet counters), client B receives, decrypts
// and decodes them — proving the full S2C voice path 1:1: voice packet
// layout (VoicePacketCounter + ClientID + Codec + payload), receive-side
// EAX decryption with generation tracking, and channel routing.
//
// Run: cd go && go test -tags goolm,live ./tests/ -run TestTeamSpeakLiveVoice -v -timeout 240s
// Env: TS3_LIVE_SERVER (default "ts.arcticblaze.net:9987").
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

	// Rank the emptiest real channels (ch:* dialogs; "server" is the
	// server-wide text chat, not a voice channel). Guests often lack
	// join power on arbitrary channels, so the test tries several.
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

	// Guest talk power here is 20 (clientinfo), and channels whose
	// channel_needed_talk_power is above it have their voice SILENTLY
	// discarded by the server — every "both clients in the room yet zero
	// voice relayed" failure was exactly that (needed=9999 entrance
	// hall, needed=125 music channel; probe evidence in BUGS B-22), and
	// the needed=999999 "◊ AUTO CHANNEL CREATOR ◊" channel additionally
	// relocates each joiner into their own "<nick>'s Channel"
	// (PrivateChannelManager) which split the pair. Joining such a room
	// SUCCEEDS, so the picker must pre-filter on talk power: needed ≤ ours.
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
		v := true // unknown power → fail open (old behavior), logged above
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

	// Join the channel on both clients (voice follows the channel).
	// Guests may lack join power on arbitrary channels; the server's
	// default channel is the guaranteed fallback (its id is
	// server-specific — never assume 0).
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
	// B tries A's room first (same filtered list follows); guests can
	// have asymmetric permissions, which is environment — skip honestly
	// instead of failing the round-trip oracle on it.
	roomB := joinRoom(coreB, "B")
	if roomA != roomB {
		t.Skipf("A and B ended up in different channels (%s vs %s) — asymmetric guest permissions, environment not client", roomA, roomB)
	}
	bestID := roomA
	time.Sleep(700 * time.Millisecond)

	// Physical truth before streaming (B-22): this public server runs a
	// "PrivateChannelManager" bot that can auto-create "<nick>'s Channel"
	// and relocate a guest the instant it moves — voice routing follows
	// the SERVER's per-client position, not our event cache, and a split
	// pair relays nothing. whoami is the server's own answer for THIS
	// connection: verify both clients, rejoin once if split, and skip
	// honestly if the bot insists (environment, not client).
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

	// Cache view is advisory from here on (physical position is
	// authoritative): log it, warn on disagreement — the voice
	// round-trip below is the real proof of co-membership.
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

	// B collects incoming voice packets.
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

	// A streams 1.5 s of 440 Hz as Opus voice packets.
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
			if err := coreA.SendVoice(4, pkt); err != nil { // codec 4 = Opus voice
				t.Errorf("SendVoice: %v", err)
				return
			}
			time.Sleep(voice.FrameDuration)
		}
	}()

	// B drains the receiver for up to 10 s.
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
		// If the server split the pair mid-stream, zero relay is its
		// routing decision, not ours (B-22) — skip honestly instead of
		// blaming the decrypt/routing path.
		fa, fb := physCh(coreA, "A"), physCh(coreB, "B")
		if fa != bestID || fb != bestID {
			t.Skipf("server relocated clients during the stream (A=%s B=%s, room=%s) — environment, not client (B-22)", fa, fb, bestID)
		}
		t.Fatalf("too few voice packets received: %d with both clients still in %s — S2C voice decrypt/routing broken", len(got), bestID)
	}

	// Packets must be Opus voice from exactly one client.
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

	// Decode the stream and verify the tone survived.
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
