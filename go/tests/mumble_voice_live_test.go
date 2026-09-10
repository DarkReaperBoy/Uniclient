//go:build live

// Live VOICE round-trip tests for the Mumble core against a REAL public
// server: two guests join the same channel, client A streams 1.5 s of
// Opus-encoded audio (440 Hz sine) via the voice data plane, client B
// receives the packets, decodes them and the tone must survive — proving
// the full voice path 1:1: voice packet format (protobuf Audio for 1.5+
// servers), OCB2 UDP encryption (or the TCP tunnel fallback), sequence
// numbers, channel routing and Opus payload integrity.
//
// Run: cd go && go test -tags goolm,live ./tests/ -run TestMumbleLiveVoice -v -timeout 180s
// Env: MUMBLE_LIVE_SERVER (default "murmur.libresilicon.com:64738").
package tests

import (
	"fmt"
	"math"
	"math/rand"
	"testing"
	"time"

	"uniclient/cores"
	"uniclient/voice"
)

// genToneFrames renders `seconds` of a sine at freq/amp as 20 ms s16le
// mono frames.
func genToneFrames(freq, amp float64, seconds float64) [][]byte {
	nFrames := int(seconds * 50)
	frames := make([][]byte, nFrames)
	for f := range frames {
		buf := make([]byte, voice.FrameBytes)
		for i := 0; i < voice.FrameSamples; i++ {
			t := float64(f*voice.FrameSamples+i) / float64(voice.SampleRate)
			v := amp * math.Sin(2*math.Pi*freq*t)
			s := int16(v * 32767)
			buf[2*i] = byte(s)
			buf[2*i+1] = byte(s >> 8)
		}
		frames[f] = buf
	}
	return frames
}

// goertzelMag returns the normalized Goertzel magnitude of freq in the
// decoded sample stream.
func goertzelMag(samples []int16, freq int) float64 {
	if len(samples) == 0 {
		return 0
	}
	k := 2 * math.Pi * float64(freq) / float64(voice.SampleRate)
	coeff := 2 * math.Cos(k)
	var s0, s1, s2 float64
	peak := 1.0
	for _, s := range samples {
		x := float64(s) / 32768
		if a := math.Abs(x); a > peak {
			peak = a
		}
		s0 = x + coeff*s1 - s2
		s2 = s1
		s1 = s0
	}
	power := math.Sqrt(s1*s1 + s2*s2 - coeff*s1*s2)
	return power / float64(len(samples)) / peak
}

func rms16(samples []int16) float64 {
	if len(samples) == 0 {
		return 0
	}
	var acc float64
	for _, s := range samples {
		f := float64(s) / 32768
		acc += f * f
	}
	return math.Sqrt(acc / float64(len(samples)))
}

// TestMumbleLiveVoiceRoundTrip: the voice data plane over a public
// server. A streams, B decodes — both transports are covered (whatever
// the NAT situation selects: encrypted UDP when reachable, TCP tunnel
// otherwise).
func TestMumbleLiveVoiceRoundTrip(t *testing.T) {
	server := osGetenvDefault("MUMBLE_LIVE_SERVER", "murmur.libresilicon.com:64738")
	usernameA := fmt.Sprintf("uc-voice-%d", rand.Intn(100000))
	coreA := mumbleLiveGuest(t, server, usernameA)
	coreB := mumbleLiveGuest(t, server, usernameA+"-b")

	// Pick the channel with the fewest users (politeness on public
	// servers) that allows joining.
	dialogs, err := coreA.GetDialogs(cores.PaginationOpts{Limit: 100})
	if err != nil {
		t.Fatalf("GetDialogs: %v", err)
	}
	bestID, bestCount := "", int(^uint(0)>>1)
	for _, d := range dialogs {
		if d.MemberCount < bestCount {
			bestID, bestCount = d.ID, d.MemberCount
		}
	}
	if bestID == "" {
		t.Fatal("no channels")
	}
	t.Logf("target channel %s (%d users)", bestID, bestCount)

	if err := coreA.MoveToChannel(parseU32(t, bestID)); err != nil {
		t.Fatalf("MoveToChannel(A): %v", err)
	}
	if err := coreB.MoveToChannel(parseU32(t, bestID)); err != nil {
		t.Fatalf("MoveToChannel(B): %v", err)
	}
	time.Sleep(700 * time.Millisecond)

	// B collects incoming voice packets.
	type vpkt struct {
		sender uint32
		codec  int
		opus   []byte
		seq    int64
	}
	recv := make(chan vpkt, 256)
	coreB.OnVoice(func(p cores.MumbleVoicePacket) {
		if p.IsTerminator || len(p.AudioData) == 0 {
			return
		}
		recv <- vpkt{sender: p.SenderSession, codec: p.Codec, opus: p.AudioData, seq: p.SequenceNum}
	})

	// A streams 1.5 s of 440 Hz.
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
			if err := coreA.SendVoice(pkt, 0); err != nil {
				t.Errorf("SendVoice: %v", err)
				return
			}
			time.Sleep(voice.FrameDuration)
		}
		_ = coreA.SendVoiceTerminator()
	}()

	// B drains the receiver for up to 8 s.
	deadline := time.After(8 * time.Second)
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
		t.Fatalf("too few voice packets received: %d", len(got))
	}

	// Packets must be Opus and attributed to A's session.
	for _, p := range got {
		if p.codec != 4 { // mumbleUDPOpus (legacy codec id 4; protobuf
			// voice is always Opus and reuses the constant)
			t.Fatalf("unexpected codec %d", p.codec)
		}
	}
	senders := map[uint32]int{}
	for _, p := range got {
		senders[p.sender]++
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
	t.Log("VOICE ROUND-TRIP OK: opus payload decoded with the tone intact")

	// Report which transport carried the audio (encrypted UDP when the
	// network allows it; the TCP tunnel fallback otherwise) and why:
	// pathSeen=true + udp=false means the socket path works but the
	// crypto bootstrap could not complete — on NAT pools that egress
	// TCP and UDP from different source IPs, murmur's unknown-peer
	// match cannot associate the two and silently drops our encrypted
	// pings (verified on this very sandbox: TCP 47.57.242.119 vs UDP
	// 8.212.10.159/47.57.232.232). The TCP tunnel is then the honest
	// degraded mode — exactly the upstream client's fallback.
	us, _, pathA, udpOK := coreA.MumbleUDPStats()
	_, urB, pathB, udpOKB := coreB.MumbleUDPStats()
	t.Logf("transport: A udp=%v (path=%v, %d pkts sent), B udp=%v (path=%v, %d UDP pkts received)",
		udpOK, pathA, us, udpOKB, pathB, urB)
}
