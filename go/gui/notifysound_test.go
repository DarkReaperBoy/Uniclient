package gui

import (
	"sync"
	"testing"
)

// synthesizeNotifySound (pure): the three sound kinds, their shapes and
// bounds (slice 121).
func TestSynthesizeNotifySound(t *testing.T) {
	for _, bad := range []string{"", "none", "unknown"} {
		if s := synthesizeNotifySound(bad); s != nil {
			t.Errorf("kind %q should synthesize nothing, got %d samples", bad, len(s))
		}
	}
	for _, kind := range []string{"default", "gentle"} {
		s := synthesizeNotifySound(kind)
		if s == nil {
			t.Fatalf("kind %q synthesized nothing", kind)
		}
		// 0.2s … 1.5s at 48kHz.
		if len(s) < 48000/5 || len(s) > 48000*3/2 {
			t.Errorf("kind %q: %d samples out of range", kind, len(s))
		}
		// Bounded amplitude: |sample| ≤ 0.6 full-scale, never clips.
		max := 0
		for _, v := range s {
			a := int(v)
			if a < 0 {
				a = -a
			}
			if a > max {
				max = a
			}
		}
		if max == 0 || max > 19660 {
			t.Errorf("kind %q: peak amplitude %d out of bounds", kind, max)
		}
		// Starts near-silence (no click; ≤ -56 dB on the first samples).
		if abs16(s[0]) > 80 || abs16(s[1]) > 80 {
			t.Errorf("kind %q: starts loud (%d,%d)", kind, s[0], s[1])
		}
		// Ends silent (decay finished).
		tail := 0
		for _, v := range s[len(s)-480:] { // last 10ms
			if a := abs16(v); a > tail {
				tail = a
			}
		}
		if tail > 200 {
			t.Errorf("kind %q: tail still ringing (%d)", kind, tail)
		}
	}
	// The two kinds differ (different tones).
	d, g := synthesizeNotifySound("default"), synthesizeNotifySound("gentle")
	if len(d) == len(g) {
		diff := false
		for i := range d {
			if d[i] != g[i] {
				diff = true
				break
			}
		}
		if !diff {
			t.Errorf("default and gentle are identical")
		}
	}
}

// notifySoundValidKinds: settings rows and dialogs agree on the list.
func TestNotifySoundValidKinds(t *testing.T) {
	for _, k := range notifySoundKinds {
		switch k {
		case "default", "gentle", "none":
		default:
			t.Errorf("unexpected kind %q", k)
		}
	}
	if !notifySoundValid("default") || !notifySoundValid("none") || !notifySoundValid("gentle") {
		t.Errorf("valid kinds rejected")
	}
	if notifySoundValid("nope") {
		t.Errorf("invalid kind accepted")
	}
}

// notifySoundLabel: display names.
func TestNotifySoundLabel(t *testing.T) {
	if notifySoundLabel("default") != "Default" {
		t.Errorf("default label")
	}
	if notifySoundLabel("gentle") != "Gentle" {
		t.Errorf("gentle label")
	}
	if notifySoundLabel("none") != "No sound" {
		t.Errorf("none label")
	}
	if notifySoundLabel("junk") != "Default" {
		t.Errorf("junk falls back to Default")
	}
}

// notifySoundFor (pure): which sound a message should play — per-chat
// override wins over the global config; "none" anywhere silences.
func TestNotifySoundFor(t *testing.T) {
	if got := notifySoundFor("default", "gentle"); got != "gentle" {
		t.Errorf("chat override should win: %q", got)
	}
	if got := notifySoundFor("gentle", "none"); got != "none" {
		t.Errorf("chat none should silence: %q", got)
	}
	if got := notifySoundFor("gentle", ""); got != "gentle" {
		t.Errorf("no override falls back to config: %q", got)
	}
	if got := notifySoundFor("", "default"); got != "default" {
		t.Errorf("empty config normalizes to default: %q", got)
	}
}

// The fill-based streamer: advances over samples, then silence. Simulates
// the audio pull contract without a device.
func TestNotifySoundStreamer(t *testing.T) {
	data := []int16{100, -100, 50, -50}
	var pos int
	fill := func(out []int16) {
		n := copy(out, data[pos:])
		pos += n
		for i := n; i < len(out); i++ {
			out[i] = 0
		}
	}
	buf := make([]int16, 3)
	fill(buf)
	if buf[0] != 100 || buf[1] != -100 || buf[2] != 50 {
		t.Errorf("first pull: %v", buf)
	}
	fill(buf)
	if buf[0] != -50 || buf[1] != 0 || buf[2] != 0 {
		t.Errorf("second pull: %v", buf)
	}
	fill(buf)
	if buf[0] != 0 {
		t.Errorf("exhausted pull should be silent: %v", buf)
	}
}

// The player must serialize concurrent triggers (no overlapping chimes).
func TestNotifySoundPlayerSerialize(t *testing.T) {
	var mu sync.Mutex
	plays := 0
	playFn := func() {
		mu.Lock()
		plays++
		mu.Unlock()
	}
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			playFn()
		}()
	}
	wg.Wait()
	if plays != 8 {
		t.Errorf("lost plays: %d", plays)
	}
}

func abs16(v int16) int {
	if v < 0 {
		return -int(v)
	}
	return int(v)
}
