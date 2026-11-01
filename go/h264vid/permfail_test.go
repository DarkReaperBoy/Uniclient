package h264vid

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"testing"
)

func bytesSource(data []byte) *bytes.Reader { return bytes.NewReader(data) }

type flakySource struct {
	data  []byte
	pos   int64
	allow int
}

func (f *flakySource) fail() bool {
	if f.allow <= 0 {
		return true
	}
	f.allow--
	return false
}

func (f *flakySource) Read(p []byte) (int, error) {
	if f.fail() {
		return 0, errors.New("stream: fetch chunk 2: dc unreachable")
	}
	if f.pos >= int64(len(f.data)) {
		return 0, io.EOF
	}
	n := copy(p, f.data[f.pos:])
	f.pos += int64(n)
	return n, nil
}

func (f *flakySource) Seek(off int64, whence int) (int64, error) {
	base := f.pos
	switch whence {
	case io.SeekStart:
		base = 0
	case io.SeekCurrent:
	case io.SeekEnd:
		base = int64(len(f.data))
	default:
		return 0, errors.New("bad whence")
	}
	f.pos = base + off
	return f.pos, nil
}

func (f *flakySource) ReadAt(p []byte, off int64) (int, error) {
	if f.fail() {
		return 0, errors.New("stream: fetch chunk 2: dc unreachable")
	}
	if off >= int64(len(f.data)) {
		return 0, io.EOF
	}
	return copy(p, f.data[off:]), nil
}

func TestParseSeekClassifiesDecodeStageFailure(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("testdata", "round_video.mp4"))
	if err != nil {
		t.Skipf("fixture missing: %v", err)
	}
	_, err = ParseSeek(&flakySource{data: data, allow: 0})
	if err == nil {
		t.Fatal("ParseSeek succeeded with a dead source")
	}
	if !errors.Is(err, ErrDecodeFailed) {
		t.Errorf("err = %v, want ErrDecodeFailed wrap", err)
	}
	if IsPermanent(err) {
		t.Errorf("a dead stream classified as permanent — one failed fetch would dead-end the clip forever")
	}
}

func TestParseSeekGarbageNotPermanent(t *testing.T) {
	_, err := ParseSeek(bytesSource([]byte("definitely not an mp4")))
	if err == nil {
		t.Fatal("garbage accepted")
	}
	if IsPermanent(err) {
		t.Errorf("garbage from a stream classified permanent: %v", err)
	}
}

func TestIsPermanentClassifiesVerdicts(t *testing.T) {
	const audioOnlySHA = "ade3487ed6edd15dcbd6ed3964086da999a8d574683dcb3989d1eeeb980b6bb7"
	data, err := os.ReadFile(filepath.Join("testdata", "audio_only.mp4"))
	if err != nil {
		t.Skipf("audio-only fixture missing: %v", err)
	}
	if sum := sha256.Sum256(data); hex.EncodeToString(sum[:]) != audioOnlySHA {
		t.Fatalf("audio_only.mp4 sha256 = %x, want %s (fixture drift)", sum, audioOnlySHA)
	}
	if _, err := ParseSeek(bytesSource(data)); err == nil {
		t.Fatal("audio-only file parsed as video")
	} else if !IsPermanent(err) {
		t.Errorf("audio-only (no video track) not permanent: %v", err)
	}

	for _, c := range []struct {
		name string
		err  error
		want bool
	}{
		{"unsupported codec (HEVC)", fmt.Errorf("%w: hvc1 track", ErrUnsupported), true},
		{"too large", ErrTooLarge, true},
		{"not a video, structural", fmt.Errorf("%w: no samples", ErrNotVideo), true},
		{"decode stage", fmt.Errorf("%w: %w: boom", ErrNotVideo, ErrDecodeFailed), false},
		{"unrelated error", errors.New("who knows"), false},
		{"nil", nil, false},
	} {
		if got := IsPermanent(c.err); got != c.want {
			t.Errorf("%s: IsPermanent(%v) = %v, want %v", c.name, c.err, got, c.want)
		}
	}
}
