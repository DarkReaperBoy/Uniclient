package engine

import (
	"encoding/binary"
	"fmt"
	"os"

	"uniclient/aacaud"
	"uniclient/voice"
)

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

func DecodeMp4Audio(path string) ([]int16, error) {
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
	switch tr.Channels {
	case 1:
	case 2:
		samples = MixdownStereo(samples)
	default:
		return nil, fmt.Errorf("mp4: %d channels (want mono or stereo)", tr.Channels)
	}
	if tr.SampleRate > 0 && tr.SampleRate != voice.SampleRate {
		samples = ResampleLinear(samples, tr.SampleRate, voice.SampleRate)
	}
	if len(samples) == 0 {
		return nil, fmt.Errorf("mp4: no audio in %s", path)
	}
	return samples, nil
}
