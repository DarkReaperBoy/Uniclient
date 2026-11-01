package h264vid

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"image"
	"io"
	"testing"

	govidmp4 "github.com/liqmix/govid/mp4"
)

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

	resume := v.syncs[1].sample
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
	wantRange := v.moov.ranges[wantSample-1]
	got := c.read - afterParse
	if got != int64(wantRange.Size) {
		t.Errorf("first packet fetched %d bytes, want exactly sample %d's range (%d)",
			got, wantSample, wantRange.Size)
	}
}
