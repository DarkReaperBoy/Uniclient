package engine

import (
	"encoding/binary"
	"fmt"
	"os"

	"uniclient/aacaud"
	"uniclient/voice"
)

// In-app MP4/AAC audio (slice 224, the engine half of parity row 276).
//
// Telegram videos and round video notes are H.264 + AAC; until this file
// existed a tap on a video either played picture-only (slice 220) or left
// the app entirely for the system player. The track is read and decoded by
// go/aacaud (pure Go, measured byte-identical to ffmpeg's fixed-point AAC
// decoder), then shaped into exactly what the device callback takes: mono
// 48 kHz — the same pipeline decodeMp3 uses, so position, speed, seek and
// the volume gain all apply to video sound without a second code path.

// IsMp4 reports whether the file at path looks like an ISO-BMFF container:
// a box header at offset 0 with the type "ftyp" at offset 4, which every
// MP4/M4V author writes first. Sniffs 8 bytes.
func IsMp4(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	var hdr [8]byte
	n, _ := f.Read(hdr[:])
	if n < 8 {
		return false
	}
	return string(hdr[4:8]) == "ftyp"
}

// decodeMp4Audio decodes the MP4's audio track into mono 48 kHz PCM.
//
// A file with no audio track returns aacaud.ErrNoAudio wrapped, so the
// caller can tell "this message is silent" apart from "these bytes are
// broken" and choose inline playback or the system player honestly.
func decodeMp4Audio(path string) ([]int16, error) {
	tr, err := aacaud.ParseFile(path)
	if err != nil {
		return nil, fmt.Errorf("mp4: %w", err)
	}
	raw, err := aacaud.Decode(tr)
	if err != nil {
		return nil, fmt.Errorf("mp4: %w", err)
	}
	if len(raw) < 2 {
		return nil, fmt.Errorf("mp4: no audio in %s", path)
	}
	samples := make([]int16, len(raw)/2)
	for i := range samples {
		samples[i] = int16(binary.LittleEndian.Uint16(raw[i*2 : i*2+2]))
	}
	// Mix down ONLY stereo. mixdownStereo averages adjacent pairs, so
	// running it on mono would pair each sample with its neighbour and
	// destroy the waveform — a bug that sounds like static, not silence,
	// and therefore passes a "did it play" check.
	switch tr.Channels {
	case 1: // already mono: nothing to do
	case 2:
		samples = mixdownStereo(samples)
	default:
		return nil, fmt.Errorf("mp4: %d channels (want mono or stereo)", tr.Channels)
	}
	if tr.SampleRate > 0 && tr.SampleRate != voice.SampleRate {
		samples = resampleLinear(samples, tr.SampleRate, voice.SampleRate)
	}
	if len(samples) == 0 {
		return nil, fmt.Errorf("mp4: no audio in %s", path)
	}
	return samples, nil
}
