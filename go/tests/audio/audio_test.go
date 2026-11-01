package tests

import (
	"os"
	"testing"
	"time"
	. "uniclient/audio"
)

func TestAudioLiveLoopback(t *testing.T) {
	if os.Getenv("UNICLIENT_AUDIO_LIVE") != "1" {
		t.Skip("set UNICLIENT_AUDIO_LIVE=1 to run the live audio loopback")
	}
	if !Available() {
		t.Skip("no audio backend on this platform")
	}

	sess, err := Open()
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer sess.Close()

	frames, err := sess.StartMic()
	if err != nil {
		t.Fatalf("mic: %v", err)
	}

	var captured [][]byte
	deadline := time.After(2 * time.Second)
collect:
	for {
		select {
		case f, ok := <-frames:
			if !ok {
				break collect
			}
			captured = append(captured, f)
		case <-deadline:
			break collect
		}
	}
	sess.StopMic()
	if len(captured) < 50 {
		t.Fatalf("captured only %d frames", len(captured))
	}
	t.Logf("captured %d frames (%.1fs)", len(captured), float64(len(captured))*0.02)

	err = sess.StartPlayback(func(out []int16) {
		for i := range out {
			t := float64(i) / 48000
			out[i] = int16(0.2 * 32767 * sin2pi(440*t))
		}
	})
	if err != nil {
		t.Fatalf("playback: %v", err)
	}
	time.Sleep(1200 * time.Millisecond)
	sess.StopPlayback()
}

func sin2pi(x float64) float64 {
	const pi = 3.141592653589793
	s := 0.0
	y := 2 * pi * x
	y = y - float64(int(y/(2*pi)))*2*pi
	for i, term := 0, y; i < 12; i++ {
		s += term
		term = -term * y * y / float64((2*i+2)*(2*i+3))
	}
	return s
}
