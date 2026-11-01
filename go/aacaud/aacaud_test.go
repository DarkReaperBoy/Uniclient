package aacaud

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"testing"
	"time"
)

const (
	talkFixtureSHA256   = "a28f06fb73a7b812ed314bdf6de1949185adfbd94015a2bbd6711d029eb9ebda"
	noteFixtureSHA256   = "0e839834d9a87b5e4a9b4fea56dcf6887cb05c13b4511d271aa15512b7bf6aa9"
	silentFixtureSHA256 = "b062ba426f19eb0a83ebde2dec410d9f7bdb7d9b13695e8081852015df55dd2b"

	talkPCMFFmpegSHA256 = "d9d10e1dbd0693c8b27ace05be0e576b7f2182b977df3d2562e59d188a7dc0e9"
	notePCMFFmpegSHA256 = "3759035b944e9148d9f3cc91a28449cc366390434e69dd779dd1e0a1f043bf0e"

	talkPCMLen = 288000
	notePCMLen = 96000
)

func fixture(t *testing.T, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Skipf("testdata missing: %v", err)
	}
	return b
}

func parseFixture(t *testing.T, name string) *Track {
	t.Helper()
	tr, err := Parse(bytes.NewReader(fixture(t, name)))
	if err != nil {
		t.Fatalf("Parse(%s): %v", name, err)
	}
	return tr
}

func TestFixtureIntegrity(t *testing.T) {
	for _, c := range []struct{ file, want string }{
		{"talk.mp4", talkFixtureSHA256},
		{"note.mp4", noteFixtureSHA256},
		{"silent.mp4", silentFixtureSHA256},
	} {
		t.Run(c.file, func(t *testing.T) {
			sum := sha256.Sum256(fixture(t, c.file))
			if got := hex.EncodeToString(sum[:]); got != c.want {
				t.Errorf("fixture sha256 = %s\nwant           %s\n"+
					"— the committed fixture changed; regenerate the pins too",
					got, c.want)
			}
		})
	}
}

func TestParseTalkTrack(t *testing.T) {
	tr := parseFixture(t, "talk.mp4")
	if tr.SampleRate != 48000 {
		t.Errorf("SampleRate = %d, want 48000", tr.SampleRate)
	}
	if tr.Channels != 2 {
		t.Errorf("Channels = %d, want 2", tr.Channels)
	}
	if got := hex.EncodeToString(tr.ASC); got != "119056e500" {
		t.Errorf("ASC = %s, want 119056e500", got)
	}
	if tr.Timescale != 48000 {
		t.Errorf("Timescale = %d, want 48000", tr.Timescale)
	}
	if tr.Priming != 1024 {
		t.Errorf("Priming = %d, want 1024", tr.Priming)
	}
	if tr.Length != 72000 {
		t.Errorf("Length = %d, want 72000 presentation samples", tr.Length)
	}
	if len(tr.Samples) != 72 {
		t.Errorf("Samples = %d, want 72 access units", len(tr.Samples))
	}
	if d := tr.Duration(); d != 1500*time.Millisecond {
		t.Errorf("Duration = %v, want 1.5s", d)
	}
}

func TestParseNoteTrack(t *testing.T) {
	tr := parseFixture(t, "note.mp4")
	if tr.SampleRate != 48000 || tr.Channels != 1 {
		t.Errorf("rate/channels = %d/%d, want 48000/1", tr.SampleRate, tr.Channels)
	}
	if got := hex.EncodeToString(tr.ASC); got != "118856e500" {
		t.Errorf("ASC = %s, want 118856e500", got)
	}
	if tr.Priming != 1024 {
		t.Errorf("Priming = %d, want 1024", tr.Priming)
	}
	if tr.Length != 48000 {
		t.Errorf("Length = %d, want 48000", tr.Length)
	}
	if len(tr.Samples) != 48 {
		t.Errorf("Samples = %d, want 48 access units", len(tr.Samples))
	}
	if d := tr.Duration(); d != time.Second {
		t.Errorf("Duration = %v, want 1s", d)
	}
}

func TestSampleTimingIsMonotonic(t *testing.T) {
	for _, name := range []string{"talk.mp4", "note.mp4"} {
		t.Run(name, func(t *testing.T) {
			tr := parseFixture(t, name)
			if len(tr.Samples) == 0 {
				t.Fatal("no samples")
			}
			for i, s := range tr.Samples {
				if len(s.Data) == 0 {
					t.Fatalf("sample %d is empty", i)
				}
				if i == 0 {
					if s.DTS != 0 {
						t.Errorf("first DTS = %d, want 0", s.DTS)
					}
					continue
				}
				if s.DTS <= tr.Samples[i-1].DTS {
					t.Fatalf("DTS not increasing at %d: %d <= %d",
						i, s.DTS, tr.Samples[i-1].DTS)
				}
			}
			want := int64(1024)
			if d := tr.Samples[1].DTS - tr.Samples[0].DTS; d != want {
				t.Errorf("frame delta = %d ticks, want %d", d, want)
			}
		})
	}
}

func TestDecodeMatchesFFmpegReference(t *testing.T) {
	for _, c := range []struct {
		file, want string
		wantBytes  int
	}{
		{"talk.mp4", talkPCMFFmpegSHA256, talkPCMLen},
		{"note.mp4", notePCMFFmpegSHA256, notePCMLen},
	} {
		t.Run(c.file, func(t *testing.T) {
			tr := parseFixture(t, c.file)
			pcm, err := Decode(tr)
			if err != nil {
				t.Fatalf("Decode: %v", err)
			}
			if len(pcm) != c.wantBytes {
				t.Errorf("decoded %d bytes, want %d", len(pcm), c.wantBytes)
			}
			sum := sha256.Sum256(pcm)
			if got := hex.EncodeToString(sum[:]); got != c.want {
				t.Errorf("decoded sha256 = %s\nwant           %s\n"+
					"— PCM differs from ffmpeg's fixed-point AAC decoder", got, c.want)
			}
		})
	}
}

var ffmpegRefPins = map[int]map[string]string{
	6: {"talk.mp4": talkPCMFFmpegSHA256, "note.mp4": notePCMFFmpegSHA256},
	7: {
		"talk.mp4": "b9aa2576848d84bc79f81d829426427fd0b1fa76dc13119f9ef48d3a2447d5a3",
		"note.mp4": "bab7fa9a17c5fcd79acce89c207444b32efb0d73a4da7aa99812b83dad5109e6",
	},
}

func TestReferenceIsGenuineFFmpeg(t *testing.T) {
	ff, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg not available")
	}
	vb, err := exec.Command(ff, "-version").Output()
	if err != nil {
		t.Skipf("ffmpeg -version failed: %v", err)
	}
	vm := regexp.MustCompile(`ffmpeg version (\d+)\.`).FindSubmatch(vb)
	if vm == nil {
		t.Skipf("cannot parse ffmpeg version from %q", vb)
	}
	major, err := strconv.Atoi(string(vm[1]))
	if err != nil {
		t.Skipf("cannot parse ffmpeg major from %q", vm[1])
	}
	pins, ok := ffmpegRefPins[major]
	if !ok {
		t.Skipf("ffmpeg major %d has no characterized pin table — add one derived with this exact invocation", major)
	}
	for _, c := range []struct{ file, want string }{
		{"talk.mp4", pins["talk.mp4"]},
		{"note.mp4", pins["note.mp4"]},
	} {
		t.Run(c.file, func(t *testing.T) {
			src := filepath.Join("testdata", c.file)
			if _, err := os.Stat(src); err != nil {
				t.Skipf("testdata missing: %v", err)
			}
			out := filepath.Join(t.TempDir(), "ref.raw")
			cmd := exec.Command(ff, "-loglevel", "error", "-y",
				"-c:a", "aac_fixed", "-i", src, "-vn",
				"-c:a", "pcm_s16le", "-f", "s16le", out)
			if b, err := cmd.CombinedOutput(); err != nil {
				t.Skipf("ffmpeg failed: %v (%s)", err, b)
			}
			raw, err := os.ReadFile(out)
			if err != nil {
				t.Fatal(err)
			}
			sum := sha256.Sum256(raw)
			if got := hex.EncodeToString(sum[:]); got != c.want {
				t.Errorf("ffmpeg produced sha256 = %s\nwant             %s\n"+
					"— the pinned constant does not come from ffmpeg's FIXED decoder; fix the pin",
					got, c.want)
			}
		})
	}
}

func TestVideoOnlyFileReportsNoAudio(t *testing.T) {
	_, err := Parse(bytes.NewReader(fixture(t, "silent.mp4")))
	if !errors.Is(err, ErrNoAudio) {
		t.Errorf("err = %v, want ErrNoAudio", err)
	}
}

func TestRejectHEAACConfig(t *testing.T) {
	heAAC := []byte{0x28, 0x06, 0x56, 0xE5, 0x00}
	if err := checkASC(heAAC); !errors.Is(err, ErrUnsupported) {
		t.Errorf("checkASC(HE-AAC) = %v, want ErrUnsupported", err)
	}
	if err := checkASC([]byte{0x11, 0x90, 0x56, 0xE5, 0x00}); err != nil {
		t.Errorf("checkASC(AAC-LC stereo) = %v, want nil", err)
	}
	if err := checkASC(nil); !errors.Is(err, ErrCorrupt) {
		t.Errorf("checkASC(nil) = %v, want ErrCorrupt", err)
	}
}

func TestParseRejectsGarbage(t *testing.T) {
	garbage := bytes.Repeat([]byte{0x00, 0x01, 0x02, 0x03}, 256)
	if _, err := Parse(bytes.NewReader(garbage)); err == nil {
		t.Error("Parse(garbage) succeeded, want error")
	}
}

func TestTruncatedFileIsRejectedNotPanicked(t *testing.T) {
	full := fixture(t, "talk.mp4")
	for _, frac := range []int{len(full) / 8, len(full) / 2, len(full) - 4} {
		if frac <= 0 {
			continue
		}
		_, err := Parse(bytes.NewReader(full[:frac]))
		if err == nil {
			t.Errorf("Parse(truncated to %d) succeeded, want error", frac)
		}
	}
}

func TestDecodeRejectsOversizedAccessUnit(t *testing.T) {
	tr := parseFixture(t, "talk.mp4")
	tr.Samples[0].Data = make([]byte, 0x10001)
	if _, err := Decode(tr); !errors.Is(err, ErrCorrupt) {
		t.Errorf("Decode(oversized AU) = %v, want ErrCorrupt", err)
	}
}
