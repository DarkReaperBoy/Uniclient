package webm

// webm_test.go — tests-first (AGENTS.md §9): every parser behavior is
// pinned here before the implementation. Fixtures are hand-built minimal
// EBML trees assembled by the builder below; the real-vector end-to-end
// pins (frame counts, dims, timecodes) live in the vp9anim package tests
// against the committed official test streams.

import (
	"bytes"
	"encoding/binary"
	"errors"
	"testing"
)

// ── tiny EBML builder (test-side) ─────────────────────────────────────────

type el struct {
	id   uint32
	sub  []el // children (when data == nil)
	data []byte
}

func uintEl(id uint32, v uint64) el  { return el{id: id, data: uvar(v)} }
func bytesEl(id uint32, b []byte) el { return el{id: id, data: b} }
func strEl(id uint32, s string) el   { return el{id: id, data: []byte(s)} }

func uvar(v uint64) []byte {
	switch {
	case v < 1<<7:
		return []byte{byte(v)}
	case v < 1<<14:
		return []byte{byte(v >> 8), byte(v)}
	case v < 1<<21:
		return []byte{byte(v >> 16), byte(v >> 8), byte(v)}
	default:
		return []byte{byte(v >> 24), byte(v >> 16), byte(v >> 8), byte(v)}
	}
}

// vint encodes a value as an EBML vint WITH the length marker (used for
// in-block track numbers).
func vint(v uint64) []byte {
	switch {
	case v < 1<<7:
		return []byte{0x80 | byte(v)}
	case v < 1<<14:
		return []byte{0x40 | byte(v>>8), byte(v)}
	case v < 1<<21:
		return []byte{0x20 | byte(v>>16), byte(v >> 8), byte(v)}
	default:
		return []byte{0x10 | byte(v>>24), byte(v >> 16), byte(v >> 8), byte(v)}
	}
}

func be16(v int) []byte {
	var b [2]byte
	binary.BigEndian.PutUint16(b[:], uint16(int16(v)))
	return b[:]
}

func render(e el) []byte {
	var buf bytes.Buffer
	// element ID: minimal-length vint with marker kept
	id := e.id
	switch {
	case id < 1<<8:
		buf.WriteByte(byte(id))
	case id < 1<<16:
		buf.WriteByte(byte(id >> 8))
		buf.WriteByte(byte(id))
	case id < 1<<24:
		buf.WriteByte(byte(id >> 16))
		buf.WriteByte(byte(id >> 8))
		buf.WriteByte(byte(id))
	default:
		buf.WriteByte(byte(id >> 24))
		buf.WriteByte(byte(id >> 16))
		buf.WriteByte(byte(id >> 8))
		buf.WriteByte(byte(id))
	}
	// children render into the payload
	var payload []byte
	for _, c := range e.sub {
		payload = append(payload, render(c)...)
	}
	if e.data != nil {
		payload = e.data
	}
	// size: minimal-length vint with the length marker set
	n := len(payload)
	switch {
	case n < 1<<7:
		buf.WriteByte(0x80 | byte(n))
	case n < 1<<14:
		buf.WriteByte(0x40 | byte(n>>8))
		buf.WriteByte(byte(n))
	case n < 1<<21:
		buf.WriteByte(0x20 | byte(n>>16))
		buf.WriteByte(byte(n >> 8))
		buf.WriteByte(byte(n))
	default:
		buf.WriteByte(0x10 | byte(n>>24))
		buf.WriteByte(byte(n >> 16))
		buf.WriteByte(byte(n >> 8))
		buf.WriteByte(byte(n))
	}
	buf.Write(payload)
	return buf.Bytes()
}

// Element IDs used only by the fixtures (the rest live in webm.go).
const (
	idEBML          = 0x1A45DFA3
	idSeekHead      = 0x114D9B74
	idTrackUID      = 0x73C5
	idAlphaMode     = 0x53C0
	idBlockDuration = 0x9B
)

// ebmlHeader builds a minimal valid EBML header declaring doc type webm.
func ebmlHeader() el {
	return el{id: idEBML, sub: []el{
		uintEl(0x4286, 1),        // EBMLVersion
		uintEl(0x42F7, 1),        // EBMLReadVersion
		uintEl(0x42F2, 4),        // EBMLMaxIDLength
		uintEl(0x42F3, 8),        // EBMLMaxSizeLength
		strEl(idDocType, "webm"), // DocType
		uintEl(0x4287, 2),        // DocTypeVersion
		uintEl(0x4285, 2),        // DocTypeReadVersion
	}}
}

// vp9Track builds a TrackEntry for a VP9 video track.
func vp9Track(num uint64, w, h uint64) el {
	return el{id: idTrackEntry, sub: []el{
		uintEl(idTrackNumber, num),
		uintEl(idTrackUID, num),
		uintEl(idTrackType, 1), // video
		strEl(idCodecID, "V_VP9"),
		el{id: idVideo, sub: []el{
			uintEl(idPixelWidth, w),
			uintEl(idPixelHeight, h),
		}},
	}}
}

// simpleBlock builds a SimpleBlock element for track t with the given
// timecode, flags and payload (no lacing).
func simpleBlock(t uint64, tc int, flags byte, payload []byte) el {
	var data []byte
	data = append(data, vint(t)...)
	data = append(data, be16(tc)...)
	data = append(data, flags)
	data = append(data, payload...)
	return bytesEl(idSimpleBlock, data)
}

const flagKey = 0x80 // SimpleBlock keyframe bit

// minimalDoc assembles a complete single-cluster webm.
func minimalDoc(tcs uint64, frames []el) el {
	return el{id: idSegment, sub: []el{
		el{id: idInfo, sub: []el{
			uintEl(idTimecodeScale, tcs),
		}},
		el{id: idTracks, sub: []el{vp9Track(1, 100, 100)}},
		el{id: idCluster, sub: append([]el{uintEl(idClusterTC, 0)}, frames...)},
	}}
}

// ── parse: header & structure ──────────────────────────────────────────────

func TestParseMinimal(t *testing.T) {
	data := append(render(ebmlHeader()), render(minimalDoc(1_000_000, []el{
		simpleBlock(1, 0, flagKey, []byte{0x01}),
		simpleBlock(1, 33, 0, []byte{0x02, 0x03}),
	}))...)

	doc, err := Parse(data)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if doc.Track.PixelWidth != 100 || doc.Track.PixelHeight != 100 {
		t.Fatalf("track dims = %dx%d, want 100x100", doc.Track.PixelWidth, doc.Track.PixelHeight)
	}
	if doc.Track.TrackNumber != 1 {
		t.Fatalf("track number = %d, want 1", doc.Track.TrackNumber)
	}
	if len(doc.Frames) != 2 {
		t.Fatalf("frames = %d, want 2", len(doc.Frames))
	}
	if !doc.Frames[0].Keyframe || doc.Frames[1].Keyframe {
		t.Fatalf("keyframe flags = [%v %v], want [true false]", doc.Frames[0].Keyframe, doc.Frames[1].Keyframe)
	}
	if !bytes.Equal(doc.Frames[0].Payload, []byte{0x01}) || !bytes.Equal(doc.Frames[1].Payload, []byte{0x02, 0x03}) {
		t.Fatalf("payloads = [%x %x]", doc.Frames[0].Payload, doc.Frames[1].Payload)
	}
	// Default 1ms scale: block timecodes are ns = tc × 1_000_000.
	if doc.Frames[0].TimecodeNs != 0 || doc.Frames[1].TimecodeNs != 33_000_000 {
		t.Fatalf("timecodes = [%d %d], want [0 33000000]", doc.Frames[0].TimecodeNs, doc.Frames[1].TimecodeNs)
	}
}

func TestParseRejectsNonWebM(t *testing.T) {
	if _, err := Parse([]byte("not webm at all")); err == nil {
		t.Fatal("Parse accepted garbage")
	}
	if _, err := Parse(nil); err == nil {
		t.Fatal("Parse accepted empty input")
	}
}

func TestParseCustomTimecodeScale(t *testing.T) {
	data := append(render(ebmlHeader()), render(minimalDoc(500_000, []el{
		simpleBlock(1, 10, flagKey, []byte{0xAA}),
	}))...)
	doc, err := Parse(data)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if want := uint64(10) * 500_000; doc.Frames[0].TimecodeNs != want {
		t.Fatalf("timecode = %d, want %d", doc.Frames[0].TimecodeNs, want)
	}
}

// ── track selection ────────────────────────────────────────────────────────

func TestTrackSelectionPrefersVP9Video(t *testing.T) {
	opusTrack := el{id: idTrackEntry, sub: []el{
		uintEl(idTrackNumber, 2),
		uintEl(idTrackUID, 2),
		uintEl(idTrackType, 2), // audio
		strEl(idCodecID, "A_OPUS"),
	}}
	segment := el{id: idSegment, sub: []el{
		el{id: idInfo, sub: []el{uintEl(idTimecodeScale, 1_000_000)}},
		el{id: idTracks, sub: []el{opusTrack, vp9Track(1, 352, 288)}},
		el{id: idCluster, sub: []el{
			uintEl(idClusterTC, 0),
			simpleBlock(2, 0, flagKey, []byte{0x99}), // audio block: ignored
			simpleBlock(1, 0, flagKey, []byte{0x01}), // video block
		}},
	}}
	doc, err := Parse(append(render(ebmlHeader()), render(segment)...))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if doc.Track.TrackNumber != 1 || doc.Track.PixelWidth != 352 || doc.Track.PixelHeight != 288 {
		t.Fatalf("picked track %+v, want the 352x288 VP9 track 1", doc.Track)
	}
	if len(doc.Frames) != 1 || doc.Frames[0].Payload[0] != 0x01 {
		t.Fatalf("frames = %+v, want only the video block", doc.Frames)
	}
}

func TestParseNoVideoTrack(t *testing.T) {
	opusOnly := el{id: idTrackEntry, sub: []el{
		uintEl(idTrackNumber, 1),
		uintEl(idTrackType, 2),
		strEl(idCodecID, "A_OPUS"),
	}}
	segment := el{id: idSegment, sub: []el{
		el{id: idInfo, sub: []el{uintEl(idTimecodeScale, 1_000_000)}},
		el{id: idTracks, sub: []el{opusOnly}},
		el{id: idCluster, sub: []el{uintEl(idClusterTC, 0)}},
	}}
	_, err := Parse(append(render(ebmlHeader()), render(segment)...))
	if !errors.Is(err, ErrNoVP9Track) {
		t.Fatalf("err = %v, want ErrNoVP9Track", err)
	}
}

// ── clusters & timestamps ──────────────────────────────────────────────────

func TestClusterTimecodesAccumulate(t *testing.T) {
	segment := el{id: idSegment, sub: []el{
		el{id: idInfo, sub: []el{uintEl(idTimecodeScale, 1_000_000)}},
		el{id: idTracks, sub: []el{vp9Track(1, 64, 64)}},
		el{id: idCluster, sub: []el{
			uintEl(idClusterTC, 100),
			simpleBlock(1, 0, flagKey, []byte{1}),
			simpleBlock(1, 33, 0, []byte{2}),
		}},
		el{id: idCluster, sub: []el{
			uintEl(idClusterTC, 200),
			simpleBlock(1, 0, 0, []byte{3}),
		}},
	}}
	doc, err := Parse(append(render(ebmlHeader()), render(segment)...))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	want := []uint64{100_000_000, 133_000_000, 200_000_000}
	if len(doc.Frames) != 3 {
		t.Fatalf("frames = %d, want 3", len(doc.Frames))
	}
	for i, w := range want {
		if doc.Frames[i].TimecodeNs != w {
			t.Fatalf("frame %d timecode = %d, want %d", i, doc.Frames[i].TimecodeNs, w)
		}
	}
}

func TestNegativeBlockTimecode(t *testing.T) {
	segment := el{id: idSegment, sub: []el{
		el{id: idInfo, sub: []el{uintEl(idTimecodeScale, 1_000_000)}},
		el{id: idTracks, sub: []el{vp9Track(1, 64, 64)}},
		el{id: idCluster, sub: []el{
			uintEl(idClusterTC, 100),
			simpleBlock(1, -35, flagKey, []byte{1}), // signed int16
		}},
	}}
	doc, err := Parse(append(render(ebmlHeader()), render(segment)...))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if want := uint64(65_000_000); doc.Frames[0].TimecodeNs != want {
		t.Fatalf("timecode = %d, want %d", doc.Frames[0].TimecodeNs, want)
	}
}

// ── lacing ─────────────────────────────────────────────────────────────────

func TestLacingXiph(t *testing.T) {
	// 3 frames of 5, 3, 4 bytes; sizes before the last: 5, 3 → [0x05, 0x03]
	var lace []byte
	lace = append(lace, 2)    // frames - 1
	lace = append(lace, 0x05) // size frame0
	lace = append(lace, 0x03) // size frame1
	lace = append(lace, 1, 2, 3, 4, 5)
	lace = append(lace, 0xA1, 0xB2, 0xC3)
	lace = append(lace, 0xD4, 0xE5, 0xF6, 0x07)
	block := simpleBlock(1, 0, flagKey|0x02, lace) // flags: key | xiph lacing (01)
	segment := el{id: idSegment, sub: []el{
		el{id: idInfo, sub: []el{uintEl(idTimecodeScale, 1_000_000)}},
		el{id: idTracks, sub: []el{vp9Track(1, 64, 64)}},
		el{id: idCluster, sub: []el{uintEl(idClusterTC, 0), block}},
	}}
	doc, err := Parse(append(render(ebmlHeader()), render(segment)...))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(doc.Frames) != 3 {
		t.Fatalf("frames = %d, want 3", len(doc.Frames))
	}
	want := [][]byte{{1, 2, 3, 4, 5}, {0xA1, 0xB2, 0xC3}, {0xD4, 0xE5, 0xF6, 0x07}}
	for i, w := range want {
		if !bytes.Equal(doc.Frames[i].Payload, w) {
			t.Fatalf("frame %d = %x, want %x", i, doc.Frames[i].Payload, w)
		}
	}
}

func TestLacingXiph255Continuation(t *testing.T) {
	// frame0 = 255*2 + 30 = 540 bytes, frame1 = remainder (10 bytes)
	var lace []byte
	lace = append(lace, 1, 0xFF, 0xFF, 30)
	lace = append(lace, make([]byte, 540)...)
	lace = append(lace, make([]byte, 10)...)
	block := simpleBlock(1, 0, flagKey|0x02, lace)
	segment := el{id: idSegment, sub: []el{
		el{id: idInfo, sub: []el{uintEl(idTimecodeScale, 1_000_000)}},
		el{id: idTracks, sub: []el{vp9Track(1, 64, 64)}},
		el{id: idCluster, sub: []el{uintEl(idClusterTC, 0), block}},
	}}
	doc, err := Parse(append(render(ebmlHeader()), render(segment)...))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(doc.Frames) != 2 || len(doc.Frames[0].Payload) != 540 || len(doc.Frames[1].Payload) != 10 {
		t.Fatalf("frames = %d sizes [%d %d], want 2 sizes [540 10]",
			len(doc.Frames), len(doc.Frames[0].Payload), len(doc.Frames[1].Payload))
	}
}

func TestLacingFixed(t *testing.T) {
	var lace []byte
	lace = append(lace, 2) // frames - 1
	lace = append(lace, make([]byte, 12)...)
	block := simpleBlock(1, 0, flagKey|0x04, lace) // 10b = fixed
	segment := el{id: idSegment, sub: []el{
		el{id: idInfo, sub: []el{uintEl(idTimecodeScale, 1_000_000)}},
		el{id: idTracks, sub: []el{vp9Track(1, 64, 64)}},
		el{id: idCluster, sub: []el{uintEl(idClusterTC, 0), block}},
	}}
	doc, err := Parse(append(render(ebmlHeader()), render(segment)...))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(doc.Frames) != 3 {
		t.Fatalf("frames = %d, want 3", len(doc.Frames))
	}
	for i, f := range doc.Frames {
		if len(f.Payload) != 4 {
			t.Fatalf("frame %d size = %d, want 4 (fixed lace)", i, len(f.Payload))
		}
	}
}

func TestLacingEBML(t *testing.T) {
	// ffmpeg semantics: first size = plain vint value; deltas are
	// value - (2^(7n-1) - 1); last = remainder.
	// 3 frames of 8, 3, 6 bytes.
	//   first size: 0x88 → vint marker 0x80, value 8.
	//   delta (3-8 = -5): 1-byte vint: value - (2^6 - 1) = -5 → value = 58 = 0x3A.
	var lace []byte
	lace = append(lace, 2, 0x88, 0xBA)
	lace = append(lace, 1, 1, 1, 1, 1, 1, 1, 1)
	lace = append(lace, 2, 2, 2)
	lace = append(lace, 3, 3, 3, 3, 3, 3)
	block := simpleBlock(1, 0, flagKey|0x06, lace) // 11b = EBML lacing
	segment := el{id: idSegment, sub: []el{
		el{id: idInfo, sub: []el{uintEl(idTimecodeScale, 1_000_000)}},
		el{id: idTracks, sub: []el{vp9Track(1, 64, 64)}},
		el{id: idCluster, sub: []el{uintEl(idClusterTC, 0), block}},
	}}
	doc, err := Parse(append(render(ebmlHeader()), render(segment)...))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(doc.Frames) != 3 {
		t.Fatalf("frames = %d, want 3", len(doc.Frames))
	}
	for i, want := range []int{8, 3, 6} {
		if len(doc.Frames[i].Payload) != want {
			t.Fatalf("frame %d size = %d, want %d", i, len(doc.Frames[i].Payload), want)
		}
	}
}

// ── alpha side stream (BlockGroup + BlockAdditions) ───────────────────────

// alphaBlock builds a BlockGroup carrying a laced-less Block plus the VP9
// alpha side stream in BlockAdditional with BlockAddID 1 (WebM VP9 alpha).
func alphaBlock(t uint64, tc int, flags byte, payload, alpha []byte) el {
	return el{id: idBlockGroup, sub: []el{
		bytesEl(idBlock, func() []byte {
			var data []byte
			data = append(data, vint(t)...)
			data = append(data, be16(tc)...)
			data = append(data, flags)
			data = append(data, payload...)
			return data
		}()),
		el{id: idBlockAdditions, sub: []el{
			el{id: idBlockMore, sub: []el{
				uintEl(idBlockAddID, 1),
				bytesEl(idBlockAdditional, alpha),
			}},
		}},
	}}
}

func TestAlphaPairExtraction(t *testing.T) {
	segment := el{id: idSegment, sub: []el{
		el{id: idInfo, sub: []el{uintEl(idTimecodeScale, 1_000_000)}},
		el{id: idTracks, sub: []el{vp9Track(1, 64, 64)}},
		el{id: idCluster, sub: []el{
			uintEl(idClusterTC, 0),
			alphaBlock(1, 0, flagKey, []byte{0x11}, []byte{0xAA}),
			simpleBlock(1, 33, 0, []byte{0x22}), // no alpha on this one
			alphaBlock(1, 66, 0, []byte{0x33}, []byte{0xBB}),
		}},
	}}
	doc, err := Parse(append(render(ebmlHeader()), render(segment)...))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(doc.Frames) != 3 {
		t.Fatalf("frames = %d, want 3", len(doc.Frames))
	}
	if !bytes.Equal(doc.Frames[0].Alpha, []byte{0xAA}) {
		t.Fatalf("frame0 alpha = %x, want [AA]", doc.Frames[0].Alpha)
	}
	if doc.Frames[1].Alpha != nil {
		t.Fatalf("frame1 alpha = %x, want nil", doc.Frames[1].Alpha)
	}
	if !bytes.Equal(doc.Frames[2].Alpha, []byte{0xBB}) {
		t.Fatalf("frame2 alpha = %x, want [BB]", doc.Frames[2].Alpha)
	}
	if !doc.Frames[0].Keyframe {
		t.Fatal("BlockGroup keyframe flag lost")
	}
}

// ── robustness ─────────────────────────────────────────────────────────────

func TestUnknownElementsSkipped(t *testing.T) {
	// SeekHead, Void and Cues between the elements we care about; a
	// future/unknown element inside Info too.
	segment := el{id: idSegment, sub: []el{
		el{id: idSeekHead, sub: []el{uintEl(0x53AB, 1)}},
		bytesEl(idVoid, []byte{0, 0, 0}),
		el{id: idInfo, sub: []el{
			uintEl(idTimecodeScale, 1_000_000),
			uintEl(0x4D80, 1), // MuxingApp (unknown to us): skipped
			uintEl(0x5741, 1), // WritingApp
		}},
		el{id: idTracks, sub: []el{vp9Track(1, 64, 64)}},
		bytesEl(0x1C53BB6B, []byte{0x01}), // Cues: skipped
		el{id: idCluster, sub: []el{
			uintEl(idClusterTC, 0),
			simpleBlock(1, 0, flagKey, []byte{7}),
		}},
	}}
	doc, err := Parse(append(render(ebmlHeader()), render(segment)...))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(doc.Frames) != 1 || doc.Frames[0].Payload[0] != 7 {
		t.Fatalf("frames = %+v", doc.Frames)
	}
}

func TestTruncatedInputErrors(t *testing.T) {
	good := append(render(ebmlHeader()), render(minimalDoc(1_000_000, []el{
		simpleBlock(1, 0, flagKey, make([]byte, 64)),
	}))...)
	for _, n := range []int{1, 5, 30, len(good) - 1} {
		if _, err := Parse(good[:n]); err == nil {
			t.Fatalf("Parse accepted truncation at %d bytes", n)
		}
	}
}

func TestDefaultDurationAndInfoDuration(t *testing.T) {
	// Duration element: 8-byte float, scaled by TimecodeScale.
	var dur [8]byte
	binary.BigEndian.PutUint64(dur[:], 0x4059000000000000) // 100.0
	segment := el{id: idSegment, sub: []el{
		el{id: idInfo, sub: []el{
			uintEl(idTimecodeScale, 1_000_000),
			bytesEl(idDuration, dur[:]),
		}},
		el{id: idTracks, sub: []el{
			el{id: idTrackEntry, sub: []el{
				uintEl(idTrackNumber, 1),
				uintEl(idTrackType, 1),
				strEl(idCodecID, "V_VP9"),
				uintEl(idDefaultDur, 41_708_333), // ~24fps in ns
				el{id: idVideo, sub: []el{uintEl(idPixelWidth, 64), uintEl(idPixelHeight, 64)}},
			}},
		}},
		el{id: idCluster, sub: []el{uintEl(idClusterTC, 0)}},
	}}
	doc, err := Parse(append(render(ebmlHeader()), render(segment)...))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if doc.DurationNs != 100_000_000 { // 100.0 × 1ms
		t.Fatalf("duration = %d, want 100000000", doc.DurationNs)
	}
	if doc.Track.DefaultDuration != 41_708_333 {
		t.Fatalf("default duration = %d, want 41708333", int(doc.Track.DefaultDuration))
	}
}

func TestFramesSortedByTimecode(t *testing.T) {
	// Out-of-order blocks must come back sorted by presentation time.
	segment := el{id: idSegment, sub: []el{
		el{id: idInfo, sub: []el{uintEl(idTimecodeScale, 1_000_000)}},
		el{id: idTracks, sub: []el{vp9Track(1, 64, 64)}},
		el{id: idCluster, sub: []el{
			uintEl(idClusterTC, 0),
			simpleBlock(1, 66, 0, []byte{3}),
			simpleBlock(1, 0, flagKey, []byte{1}),
			simpleBlock(1, 33, 0, []byte{2}),
		}},
	}}
	doc, err := Parse(append(render(ebmlHeader()), render(segment)...))
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	for i := 1; i < len(doc.Frames); i++ {
		if doc.Frames[i].TimecodeNs < doc.Frames[i-1].TimecodeNs {
			t.Fatalf("frames not sorted: [%d]=%d after [%d]=%d",
				i, doc.Frames[i].TimecodeNs, i-1, doc.Frames[i-1].TimecodeNs)
		}
	}
	if doc.Frames[0].Payload[0] != 1 || doc.Frames[2].Payload[0] != 3 {
		t.Fatalf("sort lost payload association: %x", doc.Frames[0].Payload)
	}
}
