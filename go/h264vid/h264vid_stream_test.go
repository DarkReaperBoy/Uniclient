package h264vid

// tests-first for slice 229 — playing video WITHOUT a fully downloaded
// file (parity row 281). The demuxer this package was built on
// (`govid/mp4`) is payload-hungry TWICE over: DecodeFile reads 100% of
// the file at construction (empirically measured: mdat is read through,
// zero seeks) and the index pass walks every packet's payload. Neither
// can ever sit on a fetch-on-read stream.
//
// So the container handling moves to mp4ff's lazy mode
// (`DecModeLazyMdat` — seeks over mdat) plus a table-driven packet
// pump that reads each sample's payload only when asked. What these
// tests pin, in order of importance:
//
//  1. pixel-identity — decode over the lazy path still produces the
//     ffmpeg-pinned sha256 (so a row-281 playback draws EXACTLY what
//     the downloaded file draws);
//  2. index identity — Parse and ParseSeek produce identical timelines;
//  3. packet identity — the pump's packets are byte-for-byte govid
//     Demuxer's packets (Data, Timestamp, Keyframe), which is what
//     makes (1) expected rather than lucky;
//  4. the budget — ParseSeek reads only headers+moov (< 25% of the
//     file), a GOP resume reads ZERO payload before the keyframe, and
//     one pump step reads exactly that sample's range. These three
//     numbers ARE row 281's "playback without full download".

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"image"
	"io"
	"testing"

	govidmp4 "github.com/liqmix/govid/mp4"
)

// countingSource counts every byte the parser or pump actually pulls.
// Seeks are free — a stream's Seek fetches nothing.
type countingSource struct {
	rs   *bytes.Reader
	read int64
}

func newCountingSource(data []byte) *countingSource {
	return &countingSource{rs: bytes.NewReader(data)}
}

func (c *countingSource) Read(p []byte) (int, error) {
	n, err := c.rs.Read(p)
	c.read += int64(n)
	return n, err
}

func (c *countingSource) Seek(off int64, whence int) (int64, error) {
	return c.rs.Seek(off, whence)
}

func (c *countingSource) ReadAt(p []byte, off int64) (int, error) {
	n, err := c.rs.ReadAt(p, off)
	c.read += int64(n)
	return n, err
}

// TestParseSeekDecodesToFFmpegPin is the pixel-identity pin: the lazy
// (payload-skipping) parse path must decode to the SAME sha256 ffmpeg
// produced — i.e. streaming playback draws what the full download
// draws, frame for frame.
func TestParseSeekDecodesToFFmpegPin(t *testing.T) {
	for _, c := range []struct{ file, want string }{
		{"round_video.mp4", roundVideoSHA256},
		{"high_bframes.mp4", highBframesSHA256},
	} {
		t.Run(c.file, func(t *testing.T) {
			v, err := ParseSeek(bytes.NewReader(fixture(t, c.file)))
			if err != nil {
				t.Fatalf("ParseSeek: %v", err)
			}
			h := sha256.New()
			n := 0
			if err := v.decodePass(0, 0, func(_ int, img *image.YCbCr) error {
				hashPlanes(h, img)
				n++
				return nil
			}); err != nil {
				t.Fatalf("decodePass: %v", err)
			}
			if n != wantFrames {
				t.Errorf("decoded %d frames, want %d", n, wantFrames)
			}
			if got := hex.EncodeToString(h.Sum(nil)); got != c.want {
				t.Errorf("lazy-path sha256 = %s\nwant         %s", got, c.want)
			}
		})
	}
}

// TestParseSeekTimelineEqualsParse: every timeline field identical
// between the byte path and the lazy/seeker path.
func TestParseSeekTimelineEqualsParse(t *testing.T) {
	for _, file := range []string{"round_video.mp4", "high_bframes.mp4"} {
		t.Run(file, func(t *testing.T) {
			data := fixture(t, file)
			a, err := Parse(data)
			if err != nil {
				t.Fatalf("Parse: %v", err)
			}
			b, err := ParseSeek(bytes.NewReader(data))
			if err != nil {
				t.Fatalf("ParseSeek: %v", err)
			}
			if a.Width != b.Width || a.Height != b.Height {
				t.Errorf("dims %dx%d vs %dx%d", a.Width, a.Height, b.Width, b.Height)
			}
			if a.Total != b.Total {
				t.Errorf("Total %v vs %v", a.Total, b.Total)
			}
			if a.FrameCount != b.FrameCount {
				t.Fatalf("FrameCount %d vs %d", a.FrameCount, b.FrameCount)
			}
			if a.keepAll != b.keepAll {
				t.Errorf("keepAll %v vs %v", a.keepAll, b.keepAll)
			}
			if len(a.frames) != len(b.frames) {
				t.Fatalf("frames %d vs %d", len(a.frames), len(b.frames))
			}
			for i := range a.frames {
				if a.frames[i] != b.frames[i] {
					t.Fatalf("frame %d: %+v vs %+v", i, a.frames[i], b.frames[i])
				}
			}
			if len(a.syncs) != len(b.syncs) {
				t.Fatalf("syncs %d vs %d", len(a.syncs), len(b.syncs))
			}
			for i := range a.syncs {
				if a.syncs[i] != b.syncs[i] {
					t.Fatalf("sync %d: %+v vs %+v", i, a.syncs[i], b.syncs[i])
				}
			}
		})
	}
}

// TestPacketPumpMatchesGovidDemuxer: byte-for-byte packet identity
// against the demuxer this package used before the refactor — Data,
// Timestamp and Keyframe for every sample of both fixtures. This is
// what makes the pixel pin above expected: the decoder is fed exactly
// the bytes it was fed before.
func TestPacketPumpMatchesGovidDemuxer(t *testing.T) {
	for _, file := range []string{"round_video.mp4", "high_bframes.mp4"} {
		t.Run(file, func(t *testing.T) {
			data := fixture(t, file)
			v, err := ParseSeek(bytes.NewReader(data))
			if err != nil {
				t.Fatalf("ParseSeek: %v", err)
			}
			d, err := govidmp4.NewDemuxer(bytes.NewReader(data))
			if err != nil {
				t.Fatalf("govid demuxer: %v", err)
			}
			defer d.Close()

			p := v.packetSrc()
			for i := 0; ; i++ {
				want, werr := d.NextPacket()
				if werr == io.EOF {
					// My pump must end at the same place.
					if _, err := p.next(); err != io.EOF {
						t.Fatalf("pump step %d: err=%v after govid EOF", i, err)
					}
					if i == 0 {
						t.Fatalf("no packets at all")
					}
					return
				}
				if werr != nil {
					t.Fatalf("govid next: %v", werr)
				}
				got, err := p.next()
				if err != nil {
					t.Fatalf("pump step %d: %v (govid still had packets)", i, err)
				}
				if !bytes.Equal(got.Data, want.Data) {
					t.Fatalf("packet %d: data %d bytes vs govid %d (or content differs)",
						i, len(got.Data), len(want.Data))
				}
				if got.Timestamp != want.Timestamp {
					t.Fatalf("packet %d: ts %v vs govid %v", i, got.Timestamp, want.Timestamp)
				}
				if got.Keyframe != want.Keyframe {
					t.Fatalf("packet %d: keyframe %v vs govid %v", i, got.Keyframe, want.Keyframe)
				}
			}
		})
	}
}

// TestParseSeekReadsNoPayload: the parse must touch only headers and
// moov — for round_video that is ~950 bytes of 11 926 (mdat is 11 027
// and sits BEFORE moov, so a payload-hungry parse reads ~100%).
func TestParseSeekReadsNoPayload(t *testing.T) {
	for _, file := range []string{"round_video.mp4", "high_bframes.mp4"} {
		t.Run(file, func(t *testing.T) {
			data := fixture(t, file)
			c := newCountingSource(data)
			if _, err := ParseSeek(c); err != nil {
				t.Fatalf("ParseSeek: %v", err)
			}
			if c.read >= int64(len(data))/4 {
				t.Errorf("ParseSeek read %d of %d bytes (≥25%%) — payload-hungry parse",
					c.read, len(data))
			}
			if c.read > 3000 {
				t.Errorf("ParseSeek read %d bytes, want ≤3000 (headers+moov)", c.read)
			}
		})
	}
}

// TestGopResumeReadsNoPayload: positioning a decode pass at a later
// keyframe must fetch ZERO bytes before it (the old demuxer read and
// discarded every skipped sample's payload). One pump step then reads
// exactly that sample's range — no more, no less.
func TestGopResumeReadsNoPayload(t *testing.T) {
	data := fixture(t, "round_video.mp4")
	c := newCountingSource(data)
	v, err := ParseSeek(c)
	if err != nil {
		t.Fatalf("ParseSeek: %v", err)
	}
	if len(v.syncs) < 2 {
		t.Fatalf("fixture has %d keyframes, need ≥2 for a GOP resume", len(v.syncs))
	}
	afterParse := c.read

	resume := v.syncs[1].sample // the SECOND keyframe
	p := v.packetSrc()
	p.skip(resume - 1)
	if c.read != afterParse {
		t.Errorf("GOP resume read %d bytes, want 0 (metadata-only skip)", c.read-afterParse)
	}

	wantSample := resume
	_, err = p.next()
	if err != nil {
		t.Fatalf("first packet after resume: %v", err)
	}
	// Exactly the resumed sample's payload — not one byte of the ones
	// before it.
	wantRange := v.moov.ranges[wantSample-1]
	got := c.read - afterParse
	if got != int64(wantRange.Size) {
		t.Errorf("first packet fetched %d bytes, want exactly sample %d's range (%d)",
			got, wantSample, wantRange.Size)
	}
}
