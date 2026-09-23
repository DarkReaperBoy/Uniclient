package aacaud

// tests-first pins for the AAC audio path (slice 223).
//
// The fixtures under testdata/ are shaped like what Telegram sends: an
// MP4 carrying H.264 video plus an AAC-LC audio track.
//
//	talk.mp4    regular video: 128x96 H.264 + AAC-LC 96k STEREO 48 kHz, 1.5 s
//	note.mp4    round video note: 192x192 H.264 + AAC-LC 64k MONO 48 kHz, 1.0 s
//	silent.mp4  video only — the negative case (no `soun` trak)
//
// Two independent kinds of pin:
//
//  1. FIXTURE INTEGRITY. Pinned SHA-256 of the committed MP4s, so a
//     silently regenerated fixture cannot make a broken decoder pass.
//
//  2. PCM CORRECTNESS (byte-exact vs ffmpeg). The pinned hashes below are
//     the digest of what *ffmpeg* writes when it decodes these same MP4s
//     with its FIXED-POINT AAC decoder, NOT the digest of our output, so a
//     passing test proves sample equality rather than self-consistency.
//     Derivation, repeatable anywhere:
//
//     ffmpeg -c:a aac_fixed -i talk.mp4 -vn -c:a pcm_s16le -f s16le ref.raw
//     sha256sum ref.raw
//
//     THE FLAG ORDER MATTERS AND BITES TWICE WHILE WRITING THIS:
//     `aac_fixed` is a DECODER, so it must be given BEFORE `-i`. Put it
//     after `-i` and ffmpeg treats it as an encoder, reports `Unknown
//     encoder 'aac_fixed'`, and — if another -c:a follows it — silently
//     falls back to the FLOAT decoder instead. ffmpeg's float and fixed
//     AAC decoders do NOT agree byte-for-byte (measured here: talk
//     5ea29f46… vs d9d10e1d…), so the wrong flag order yields a pin that
//     looks authoritative and belongs to the other decoder. Our decoder is
//     a port of ffmpeg's fixed-point one, so FIXED is the correct oracle,
//     and TestReferenceIsGenuineFFmpeg re-runs that exact invocation.

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

const (
	// fixture digests
	talkFixtureSHA256   = "a28f06fb73a7b812ed314bdf6de1949185adfbd94015a2bbd6711d029eb9ebda"
	noteFixtureSHA256   = "0e839834d9a87b5e4a9b4fea56dcf6887cb05c13b4511d271aa15512b7bf6aa9"
	silentFixtureSHA256 = "b062ba426f19eb0a83ebde2dec410d9f7bdb7d9b13695e8081852015df55dd2b"

	// ffmpeg `aac_fixed` PCM digests (little-endian S16 interleaved)
	talkPCMFFmpegSHA256 = "d9d10e1dbd0693c8b27ace05be0e576b7f2182b977df3d2562e59d188a7dc0e9"
	notePCMFFmpegSHA256 = "3759035b944e9148d9f3cc91a28449cc366390434e69dd779dd1e0a1f043bf0e"

	talkPCMLen = 288000 // 1.5 s × 48000 × 2ch × 2B
	notePCMLen = 96000  // 1.0 s × 48000 × 1ch × 2B
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

// ── fixture integrity ────────────────────────────────────────────────────

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

// ── parsing ──────────────────────────────────────────────────────────────

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
	// The edit list carries AAC's 1024-sample encoder priming; if Parse
	// stops reading it, every sample lands 21 ms late.
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

// Every access unit must be present, non-empty, and scheduled strictly
// after the previous one — this is the input A/V sync will live on.
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
			// AAC-LC frames are 1024 samples; a constant tick delta is
			// what makes the clock predictable for the audio sink.
			want := int64(1024)
			if d := tr.Samples[1].DTS - tr.Samples[0].DTS; d != want {
				t.Errorf("frame delta = %d ticks, want %d", d, want)
			}
		})
	}
}

// ── the headline pin: PCM equals ffmpeg's fixed-point decoder ────────────

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

// Provenance: re-derive the pinned constants from the committed MP4s with
// ffmpeg itself, so the pins are never taken on trust. Skipped when ffmpeg
// is absent (CI). Note the decoder flag comes BEFORE -i — see the header
// comment for why getting that wrong silently switches oracles.
func TestReferenceIsGenuineFFmpeg(t *testing.T) {
	ff, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg not available")
	}
	for _, c := range []struct{ file, want string }{
		{"talk.mp4", talkPCMFFmpegSHA256},
		{"note.mp4", notePCMFFmpegSHA256},
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

// ── honest failure modes ─────────────────────────────────────────────────

func TestVideoOnlyFileReportsNoAudio(t *testing.T) {
	_, err := Parse(bytes.NewReader(fixture(t, "silent.mp4")))
	if !errors.Is(err, ErrNoAudio) {
		t.Errorf("err = %v, want ErrNoAudio", err)
	}
}

func TestRejectHEAACConfig(t *testing.T) {
	// AudioObjectType 5 = SBR (HE-AAC). Our decoder is AAC-LC only, and a
	// decoder that decodes HE-AAC as if it were LC produces plausible-
	// looking noise, so the config must be refused up front.
	heAAC := []byte{0x28, 0x06, 0x56, 0xE5, 0x00} // AOT=5, 48 kHz, 2ch
	if err := checkASC(heAAC); !errors.Is(err, ErrUnsupported) {
		t.Errorf("checkASC(HE-AAC) = %v, want ErrUnsupported", err)
	}
	// and the real configs must be accepted, or the check is just "reject"
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

// Decode must refuse a track whose access units cannot be represented —
// go-aac's raw framing prefixes each unit with a uint16, and silently
// truncating a length would desynchronise every frame after it.
func TestDecodeRejectsOversizedAccessUnit(t *testing.T) {
	tr := parseFixture(t, "talk.mp4")
	tr.Samples[0].Data = make([]byte, 0x10001)
	if _, err := Decode(tr); !errors.Is(err, ErrCorrupt) {
		t.Errorf("Decode(oversized AU) = %v, want ErrCorrupt", err)
	}
}
