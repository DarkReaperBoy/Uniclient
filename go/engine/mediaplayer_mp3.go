package engine

import (
	"encoding/binary"
	"fmt"
	"io"
	"os"

	gomp3 "github.com/hajimehoshi/go-mp3"

	"uniclient/voice"
)

// In-app MP3 playback (slice 185, parity row "Audio file"): music files
// decode through the pure-Go go-mp3 decoder, mix down to mono and
// linearly resample to the player's 48 kHz — the same PCM pipeline the
// Opus voice path uses, so play/pause/speed/seek-elapsed all work
// in-app. Non-Opus non-MP3 files keep the system-player handoff
// (§1.10).

// IsMp3 reports whether the file at path looks like MPEG audio: an
// ID3v2 header or a raw MPEG frame sync. Sniffs the first 512 bytes.
func IsMp3(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	buf := make([]byte, 512)
	n, err := f.Read(buf)
	if n < 4 {
		return false
	}
	_ = err // a short read is fine — we only sniff what we got
	// ID3v2: "ID3" + version bytes.
	if string(buf[:3]) == "ID3" {
		return true
	}
	// MPEG frame sync: 11 set bits (0xFF then 0xE0 mask).
	for i := 0; i+1 < n; i++ {
		if buf[i] == 0xFF && buf[i+1]&0xE0 == 0xE0 {
			// Layer bits (buf[i+1] bits 4..5) must not be reserved.
			layer := (buf[i+1] >> 1) & 0x3
			if layer != 0 {
				return true
			}
		}
	}
	return false
}

// IsInAppPlayable: the file decodes through one of the in-app decoders
// (Ogg/Opus, MP3, or the AAC track of an MP4 — slice 224).
func IsInAppPlayable(path string) bool {
	return IsOpusOgg(path) || IsMp3(path) || IsMp4(path)
}

// mixdownStereo averages interleaved stereo pairs into mono; mono input
// passes through; a dangling odd sample drops. Pure — unit-tested.
func mixdownStereo(in []int16) []int16 {
	if len(in) < 2 {
		return in
	}
	out := make([]int16, 0, len(in)/2)
	for i := 0; i+1 < len(in); i += 2 {
		out = append(out, int16((int32(in[i])+int32(in[i+1]))/2))
	}
	return out
}

// resampleLinear resamples mono PCM between sample rates with linear
// interpolation. Same-rate and degenerate inputs pass through. Pure —
// unit-tested.
func resampleLinear(in []int16, from, to int) []int16 {
	if len(in) == 0 || from <= 0 || to <= 0 || from == to {
		return in
	}
	n := int(float64(len(in)) * float64(to) / float64(from))
	if n <= 0 {
		return in
	}
	out := make([]int16, n)
	step := float64(from) / float64(to)
	for i := 0; i < n; i++ {
		pos := float64(i) * step
		i0 := int(pos)
		if i0 >= len(in) {
			i0 = len(in) - 1
		}
		i1 := i0 + 1
		if i1 >= len(in) {
			i1 = i0
		}
		frac := pos - float64(i0)
		out[i] = int16(float64(in[i0])*(1-frac) + float64(in[i1])*frac)
	}
	return out
}

// decodeMp3 decodes an MPEG audio file into mono 48 kHz PCM through
// the pure-Go go-mp3 decoder (stereo mixes down; the source rate
// linearly resamples to the player's fixed 48 kHz).
func decodeMp3(path string) ([]int16, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	dec, err := gomp3.NewDecoder(f)
	if err != nil {
		return nil, fmt.Errorf("mp3: %w", err)
	}
	raw, err := io.ReadAll(dec)
	if err != nil && len(raw) == 0 {
		return nil, fmt.Errorf("mp3: %w", err)
	}
	if len(raw) < 4 {
		return nil, fmt.Errorf("mp3: no audio in %s", path)
	}
	// go-mp3 yields interleaved 16-bit LE stereo at the source rate.
	samples := make([]int16, len(raw)/2)
	for i := range samples {
		samples[i] = int16(binary.LittleEndian.Uint16(raw[i*2 : i*2+2]))
	}
	mono := mixdownStereo(samples)
	if rate := dec.SampleRate(); rate > 0 && rate != voice.SampleRate {
		mono = resampleLinear(mono, rate, voice.SampleRate)
	}
	if len(mono) == 0 {
		return nil, fmt.Errorf("mp3: no audio in %s", path)
	}
	return mono, nil
}
