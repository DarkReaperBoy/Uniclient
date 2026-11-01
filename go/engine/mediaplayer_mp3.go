package engine

import (
	"encoding/binary"
	"fmt"
	"io"
	"os"

	gomp3 "github.com/hajimehoshi/go-mp3"

	"uniclient/voice"
)

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
	_ = err
	if string(buf[:3]) == "ID3" {
		return true
	}
	for i := 0; i+1 < n; i++ {
		if buf[i] == 0xFF && buf[i+1]&0xE0 == 0xE0 {
			layer := (buf[i+1] >> 1) & 0x3
			if layer != 0 {
				return true
			}
		}
	}
	return false
}

func IsInAppPlayable(path string) bool {
	return IsOpusOgg(path) || IsMp3(path) || IsMp4(path)
}

func MixdownStereo(in []int16) []int16 {
	if len(in) < 2 {
		return in
	}
	out := make([]int16, 0, len(in)/2)
	for i := 0; i+1 < len(in); i += 2 {
		out = append(out, int16((int32(in[i])+int32(in[i+1]))/2))
	}
	return out
}

func ResampleLinear(in []int16, from, to int) []int16 {
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

func DecodeMp3(path string) ([]int16, error) {
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
	samples := make([]int16, len(raw)/2)
	for i := range samples {
		samples[i] = int16(binary.LittleEndian.Uint16(raw[i*2 : i*2+2]))
	}
	mono := MixdownStereo(samples)
	if rate := dec.SampleRate(); rate > 0 && rate != voice.SampleRate {
		mono = ResampleLinear(mono, rate, voice.SampleRate)
	}
	if len(mono) == 0 {
		return nil, fmt.Errorf("mp3: no audio in %s", path)
	}
	return mono, nil
}
